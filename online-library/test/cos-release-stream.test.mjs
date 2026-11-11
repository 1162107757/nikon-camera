import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {CosReleaseStorage,withReleaseCredentials} from '../server/cos-release-storage.mjs';
import {createReleaseRoutes} from '../server/releases.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const payload = Buffer.from('a complete private APK is checked in chunks');
const path = `app-releases/${hash(payload)}.apk`;
const config = {region:'ap-shanghai',bucket:'example-updates-1250000000',downloadOrigin:'https://download.huevia.cc',secretId:'fixture-id',secretKey:'synthetic-fixture-key'};
const stream = (bytes = payload, declared = String(bytes.length), state = {}) => {
  let offset = 0;
  return new Response(new ReadableStream({
    pull(controller) {
      state.pulls = (state.pulls || 0) + 1;
      if (offset >= bytes.length) { controller.close(); return; }
      const end = Math.min(offset + 3,bytes.length);
      controller.enqueue(bytes.subarray(offset,end)); offset = end;
    },
    cancel() { state.canceled = true; }
  }), {headers:declared === null ? {} : {'Content-Length':declared}});
};
const fixture = (storage) => {
  const row = {id:'12345678-1234-4234-8234-123456789abc',status:'published',sha256:hash(payload),byte_length:payload.length,storage_path:path,version_code:186,channel:'beta'};
  const counts = {rows:0,budgets:0};
  const routes = createReleaseRoutes({store:{rest:async()=>{counts.rows++;return [{...row}];},rpc:async()=>{counts.budgets++;return {allowed:true};}},storage,publicBaseUrl:'https://fixture.example'});
  const req = () => ({method:'GET',headers:{},socket:{remoteAddress:'127.0.0.1'}});
  const res = () => ({setHeader(){},writeHead(status,headers){this.status=status;this.headers=headers;},end(){this.ended=true;}});
  const run = (request=req(),response=res()) => routes.publicRoute(request,response,{path:`/releases/${row.id}/file`,url:new URL(`https://fixture.example/releases/${row.id}/file`)}).then(()=>response);
  return {row,counts,req,res,run};
};

test('stream verification checks every byte and exact size with or without Content-Length', async () => {
  for (const declared of [String(payload.length),null]) {
    const storage = new CosReleaseStorage({...config,fetchImpl:async()=>stream(payload,declared)});
    assert.equal(await storage.verify(path,payload.length,hash(payload)),true);
    assert.equal(storage.pendingVerifications.size,0);
  }
  for (const bytes of [Buffer.from(payload.toString().replace('private','changed')),payload.subarray(0,payload.length-1),Buffer.concat([payload,Buffer.from('extra')])]) {
    const storage = new CosReleaseStorage({...config,fetchImpl:async()=>stream(bytes,null)});
    assert.equal(await storage.verify(path,payload.length,hash(payload)),false);
  }
});

test('invalid size headers stop and cancel the source instead of buffering it', async () => {
  for (const declared of ['0','-1','1.5',String(payload.length+1),'not-a-size']) {
    const state = {};
    const storage = new CosReleaseStorage({...config,fetchImpl:async()=>stream(payload,declared,state)});
    assert.equal(await storage.verify(path,payload.length,hash(payload)),false);
    assert.equal(state.canceled,true);
    assert.ok(state.pulls <= 1,'a header mismatch must not consume a complete object');
  }
});

test('invalid identities and metadata are rejected before any network read', async () => {
  let reads = 0;
  const storage = new CosReleaseStorage({...config,fetchImpl:async()=>{reads++;return stream();}});
  for (const args of [[path,payload.length,'a'.repeat(64)],[path,0,hash(payload)],[path,33554433,hash(payload)],[path,NaN,hash(payload)],['../'+path,payload.length,hash(payload)],['app-upload/fixture.part',payload.length,hash(payload)]]) {
    await assert.rejects(storage.verify(...args),e=>e.code==='COS_RELEASE_UNAVAILABLE');
  }
  assert.equal(reads,0);
});

test('simultaneous identical checks share one read but later requests recheck changed bytes', {timeout:3000}, async () => {
  let reads = 0,changed = false,release,notifyRead;
  const gate = new Promise(resolve=>{release=resolve;});
  const started = new Promise(resolve=>{notifyRead=resolve;});
  const storage = new CosReleaseStorage({...config,fetchImpl:async()=>{reads++;notifyRead();await gate;return stream(changed?Buffer.alloc(payload.length):payload);}});
  const group = Array.from({length:8},()=>storage.verify(path,payload.length,hash(payload)));
  await started;
  assert.equal(reads,1);
  release();
  assert.deepEqual(await Promise.all(group),Array(8).fill(true));
  assert.equal(storage.pendingVerifications.size,0);
  changed = true;
  assert.equal(await storage.verify(path,payload.length,hash(payload)),false);
  assert.equal(reads,2,'a completed integrity check is not cached');
  assert.equal(storage.pendingVerifications.size,0);
});

test('failed shared reads are cleared for retry and provider details stay private', async () => {
  let reads = 0,fail = true;
  const storage = new CosReleaseStorage({...config,fetchImpl:async()=>{reads++;await new Promise(resolve=>setImmediate(resolve));if(fail)throw Error('sensitive signed URL and credentials');return stream();}});
  const result = await Promise.allSettled(Array.from({length:4},()=>storage.verify(path,payload.length,hash(payload))));
  assert.equal(reads,1);
  for (const r of result) {assert.equal(r.status,'rejected');assert.equal(r.reason.code,'COS_RELEASE_UNAVAILABLE');assert.doesNotMatch(r.reason.message,/sensitive|credentials/);}
  assert.equal(storage.pendingVerifications.size,0);
  fail = false;
  assert.equal(await storage.verify(path,payload.length,hash(payload)),true);
  assert.equal(reads,2);
});

test('request-scoped credentials and independent metadata remain isolated during shared verification', async () => {
  let reads = 0;
  const storage = new CosReleaseStorage({...config,secretId:undefined,secretKey:undefined,roleCredentials:true,fetchImpl:async()=>{reads++;await new Promise(resolve=>setImmediate(resolve));return stream();}});
  const env = {TENCENTCLOUD_RUNENV:'SCF',SCF_FUNCTIONNAME:'fixture'};
  const request = id => ({socket:{remoteAddress:'127.0.0.1'},headers:{'x-scf-name':'fixture','x-scf-secret-id':id,'x-scf-secret-key':'fixture-key','x-scf-session-token':'fixture-token'}});
  const values = await Promise.all(['first','second'].map(id=>withReleaseCredentials(request(id),async()=>{
    assert.equal(await storage.verify(path,payload.length,hash(payload)),true);
    return new URL(await storage.signDownload(path,60,'Huevia-186-beta.apk')).searchParams.get('q-ak');
  },env)));
  assert.deepEqual(values,['first','second']);assert.equal(reads,1);
  await assert.rejects(storage.verify(path,payload.length,hash(payload)),e=>e.code==='COS_RELEASE_UNAVAILABLE');
  const other = new CosReleaseStorage({...config,fetchImpl:async()=>stream()});
  assert.deepEqual(await Promise.all([other.verify(path,payload.length,hash(payload)),other.verify(path,payload.length+1,hash(payload))]),[true,false]);
});

test('signed routes use streamed verification and never grant a URL for altered objects', async () => {
  let changed = false,signs = 0;
  const storage = new CosReleaseStorage({...config,fetchImpl:async()=>stream(changed?Buffer.alloc(payload.length):payload)});
  storage.get = () => {throw Error('the signed route must not buffer a complete APK');};
  const sign = storage.signDownload.bind(storage);
  storage.signDownload = (...args) => {signs++;return sign(...args);};
  const f = fixture(storage);
  const response = await f.run();
  assert.equal(response.status,307);assert.equal(response.headers['Content-Length'],0);
  changed = true;
  await assert.rejects(f.run(),e=>e.code==='RELEASE_FILE_CHANGED');assert.equal(signs,1);
  const fallback = fixture({preferSignedDownloads:true,get:async()=>undefined,signDownload:async()=>{throw Error('must not sign unverified data');}});
  await assert.rejects(fallback.run(),e=>e.code==='RELEASE_FILE_CHANGED');
});

test('withdrawal during verification still blocks a new signed download', async () => {
  const storage = new CosReleaseStorage({...config,fetchImpl:async()=>{f.row.status='withdrawn';return stream();}});
  const f = fixture(storage);
  await assert.rejects(f.run(),e=>e.status===404);
});

test('closed downloads skip work and one disconnect does not cancel another pending download', {timeout:3000}, async () => {
  let reads = 0,release,notifyRead;
  const gate = new Promise(resolve=>{release=resolve;});
  const started = new Promise(resolve=>{notifyRead=resolve;});
  const storage = new CosReleaseStorage({...config,fetchImpl:async()=>{reads++;notifyRead();await gate;return stream();}});
  const f = fixture(storage);
  const aborted = f.req();aborted.aborted = true;
  await f.run(aborted);assert.deepEqual(f.counts,{rows:0,budgets:0});assert.equal(reads,0);
  const closed = f.res();closed.destroyed = true;
  await f.run(f.req(),closed);assert.equal(reads,0);
  const first = f.res(),second = f.res();
  const requests = [f.run(f.req(),first),f.run(f.req(),second)];
  await started;
  assert.equal(reads,1);
  first.destroyed = true;release();
  await Promise.all(requests);
  assert.equal(first.status,undefined);assert.equal(first.ended,undefined);
  assert.equal(second.status,307);
});
