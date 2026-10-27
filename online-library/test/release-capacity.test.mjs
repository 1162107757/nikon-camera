import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { inspectApk, MAX_APK_BYTES } from '../server/apk.mjs';
import { createReleaseRoutes, APK_CHUNK_BYTES } from '../server/releases.mjs';
import { ReleaseMemoryStore } from './release-memory-store.mjs';

function fixture() {
  const store = new ReleaseMemoryStore(), objects = new Map(), writes = [];
  store.admins.set('capacity-admin', {username:'capacity-admin',disabled:false});
  const routes = createReleaseRoutes({store,publicBaseUrl:'https://capacity.test',storage:{
    put:async(path,data,mime)=>{objects.set(path,Buffer.from(data));writes.push({path,mime});},
    get:async path=>objects.get(path)
  }});
  async function request(path,method,body) {
    let response;
    await routes.adminRoute({method},{},{path,session:{username:'capacity-admin'},
      readJson:async()=>body,readBody:async()=>body,json:(_res,value,status=200)=>{response={status,value};}});
    return response;
  }
  return {request,store,objects,writes};
}

test('APK capacity accepts 32 MiB declarations and chunk 63; rejects overflow and noncanonical indices',async()=>{
  assert.equal(MAX_APK_BYTES,33554432);assert.equal(APK_CHUNK_BYTES,524288);
  assert.throws(()=>inspectApk(Buffer.alloc(MAX_APK_BYTES+1)),/32 MiB/);
  const {request,objects}=fixture();
  const task=await request('/api/releases/uploads','POST',{byteLength:MAX_APK_BYTES,channel:'beta',notes:'Synthetic local boundary fixture'});
  assert.equal(task.status,201);assert.equal(task.value.maxApkBytes,MAX_APK_BYTES);
  const base=`/api/releases/uploads/${task.value.uploadId}/chunks/`;
  const chunk=Buffer.alloc(APK_CHUNK_BYTES,7);
  for(const index of [8,18,63]) assert.equal((await request(base+index,'PUT',chunk)).status,200);
  assert.equal(objects.size,3);
  for(const index of ['64','100','08','-1'])await assert.rejects(()=>request(base+index,'PUT',chunk),error=>error.status===404);
  for(const byteLength of [0,MAX_APK_BYTES+1,1.5])await assert.rejects(()=>request('/api/releases/uploads','POST',{byteLength,channel:'beta',notes:'Synthetic overflow'}),error=>error.code==='INVALID_APK_SIZE');
});

let candidate;
try {candidate=await readFile(process.env.HUEVIA_RELEASE_APK || new URL('../../dist/huevia-0.22.1-beta-debug.apk',import.meta.url));}catch{}
test('signed universal RAW APK over 4 MiB uploads across chunk 8 and retains exact signature, bytes and SHA', {skip:!candidate},async()=>{
  assert.ok(candidate.length>4*1024*1024);assert.ok(candidate.length<=MAX_APK_BYTES);
  const parsed=inspectApk(candidate);
  assert.equal(parsed.packageName,'cc.huevia');assert.deepEqual(parsed.signatureSchemes,[2,3]);
  const {request,objects,store,writes}=fixture();
  const begin=await request('/api/releases/uploads','POST',{byteLength:candidate.length,channel:'beta',notes:'Synthetic local signed large-package fixture'});
  const task=begin.value;
  for(let offset=0,index=0;offset<candidate.length;offset+=task.chunkBytes,index++){
    assert.equal((await request(`/api/releases/uploads/${task.uploadId}/chunks/${index}`,'PUT',candidate.subarray(offset,offset+task.chunkBytes))).status,200);
  }
  const complete=await request(`/api/releases/uploads/${task.uploadId}/complete`,'POST',{}),release=complete.value.release;
  assert.equal(complete.status,201);assert.equal(release.status,'draft');assert.equal(release.mandatory,false);
  assert.equal(release.byteLength,candidate.length);assert.equal(release.versionCode,parsed.versionCode);assert.equal(release.sha256,parsed.sha256);
  assert.equal(createHash('sha256').update(objects.get(`app-releases/${parsed.sha256}.bin`)).digest('hex'),parsed.sha256);
  assert.deepEqual(writes.at(-1),{path:`app-releases/${parsed.sha256}.bin`,mime:'application/octet-stream'});
  assert.equal(store.uploadBudgetBytes,candidate.length*2,'chunks and final object both consume the unchanged actual-byte budget');
  const changed=Buffer.from(candidate);changed[500]^=1;
  assert.throws(()=>inspectApk(changed),error=>error.code==='INVALID_APK','raising the cap must preserve protected-content verification');
});
