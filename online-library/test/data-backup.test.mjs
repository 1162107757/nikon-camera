import test from 'node:test';
import assert from 'node:assert/strict';
import {gunzipSync} from 'node:zlib';
import {runBackup,pruneOldBackups,inspectSnapshot,safePath,digest} from '../backup/core.mjs';
import {credentialsForInvocation,cloudbaseReader,cosStorage,readBounded,invocationAction} from '../backup/runtime.mjs';
const id='87654321-1234-4567-89ab-123456789abc',now=new Date('2026-11-09T10:00:00Z');
const payload=Buffer.from('real file bytes'),hash=digest(payload);
function fixture(){return {format:'huevia-data-backup-v1',capturedAt:now.toISOString(),columns:[],functions:[],tables:{
  'storage.buckets':[{id:'nikon-presets',public:false}],
  'storage.objects':[{bucket_id:'nikon-presets',name:'presets/file.np3',metadata:{size:payload.length}}],
  'public.nikon_presets':[],'public.nikon_users':[],
  'public.nikon_app_releases':[{storage_path:'app-releases/'+hash+'.apk',sha256:hash,byte_length:payload.length}]}};}
function memory(){const files=new Map(),removed=[];return {files,removed,
  async put(key,bytes){assert(!files.has(key));files.set(key,Buffer.from(bytes));},
  async get(key){return Buffer.from(files.get(key));},
  async list(){return {keys:[...files.keys()],next:null};},async remove(key){removed.push(key);files.delete(key);}};}
test('complete marker only after real file and compressed DB readbacks; raw integer text preserved',async()=>{
  const s=fixture();s.tables['public.nikon_users'].push({id:'user'});
  const raw=Buffer.from(JSON.stringify(s).replace('"user"','90071992547409931234'));const store=memory();
  const complete=await runBackup({snapshotBytes:raw,storage:store,source:{get:async()=>payload},id,now});
  assert.equal(complete.files.length,2);assert.equal(complete.complete,true);
  assert(gunzipSync(store.files.get(complete.database.key)).equals(raw));
  for(const file of complete.files){assert.equal(digest(store.files.get(file.key)),file.sha256);assert.equal(file.size,payload.length);}
  assert.deepEqual(JSON.parse(store.files.get(complete.run+'COMPLETE.json')),complete);
});
test('missing file or corrupt readback cannot publish COMPLETE',async()=>{
  for(const mode of ['source','readback']){const store=memory(),read=store.get;
    if(mode==='readback')store.get=async key=>key.includes('/files/')?Buffer.from('corrupt'):read(key);
    await assert.rejects(runBackup({snapshotBytes:Buffer.from(JSON.stringify(fixture())),storage:store,
      source:{get:async()=>{if(mode==='source')throw Error('missing');return payload;}},id,now}));
    assert(![...store.files.keys()].some(k=>k.endsWith('/COMPLETE.json')));assert.equal(store.removed.length,0);
  }
});
test('expected APK SHA is checked, not merely the object length',async()=>{
  const store=memory();await assert.rejects(runBackup({snapshotBytes:Buffer.from(JSON.stringify(fixture())),storage:store,
    source:{get:async item=>item.provider==='cos'?Buffer.alloc(payload.length):payload},id,now}),/SOURCE_HASH_MISMATCH/);
  assert(![...store.files.keys()].some(k=>k.endsWith('/COMPLETE.json')));
});
test('new mobile release bytes join complete backups while temporary mobile chunks remain excluded',async()=>{
  const bytes=Buffer.alloc(2048,42),sha=digest(bytes),s=fixture();
  s.tables['public.nikon_mobile_releases']=[{platform:'ios',storage_path:`mobile-releases/ios/${sha}.bin`,sha256:sha,byte_length:bytes.length}];
  s.tables['public.nikon_mobile_upload_chunks']=[{storage_path:'mobile-upload/unfinished.part'}];
  const complete=await runBackup({snapshotBytes:Buffer.from(JSON.stringify(s)),storage:memory(),source:{get:async item=>item.path.startsWith('mobile-releases/')?bytes:payload},id,now});
  assert.equal(complete.files.length,3);assert.equal(complete.files.find(item=>item.path.startsWith('mobile-releases/')).sha256,sha);
  for(const path of [`mobile-upload/${sha}.bin`,`mobile-releases/other/${sha}.bin`,`mobile-releases/ios/${'b'.repeat(64)}.bin`]){
    s.tables['public.nikon_mobile_releases'][0].storage_path=path;assert.throws(()=>inspectSnapshot(Buffer.from(JSON.stringify(s))),/INVALID_MOBILE_RELEASE/);
  }
});
test('daily directory follows Beijing date across UTC midnight boundary',async()=>{
  const result=await runBackup({snapshotBytes:Buffer.from(JSON.stringify(fixture())),storage:memory(),source:{get:async()=>payload},id,now:new Date('2026-11-09T20:00:00Z')});
  assert(result.run.startsWith('huevia-backups/daily/2026-11-10/'));
});
test('path traversal, wrong bucket and missing tables fail before uploading',()=>{
  for(const path of ['../secret','/root','a//b','a\\b','a/./b','a\u0000b'])assert.throws(()=>safePath(path));
  for(const mutate of [s=>delete s.tables['public.nikon_users'],s=>s.tables['storage.buckets'][0].public=true,
    s=>s.tables['storage.objects'][0].bucket_id='other']){const s=fixture();mutate(s);assert.throws(()=>inspectSnapshot(Buffer.from(JSON.stringify(s))));}
});
test('30-day retention requires a completed backup and never touches source APKs',async()=>{
  const store=memory();store.files.set('huevia-backups/daily/2026-10-01/old/file',payload);store.files.set('huevia-backups/daily/2026-11-01/new/file',payload);
  await assert.rejects(pruneOldBackups(store,{complete:false},now));assert.equal(store.removed.length,0);
  const complete={complete:true,run:'huevia-backups/daily/2026-11-09/run/'};
  assert.equal(await pruneOldBackups(store,complete,now),1);assert.equal(store.removed[0],'huevia-backups/daily/2026-10-01/old/file');
  store.files.clear();store.files.set('huevia-updates/app-releases/protected.apk',payload);
  await assert.rejects(pruneOldBackups(store,complete,now),/UNSAFE_RETENTION_KEY/);assert.equal(store.removed.length,1);
});
test('temporary role credentials refresh each invocation; no stale env fallback',()=>{
  assert.throws(()=>credentialsForInvocation({}));
  assert.equal(credentialsForInvocation({TENCENTCLOUD_SECRETID:'new-id',TENCENTCLOUD_SECRETKEY:'new-key',TENCENTCLOUD_SESSIONTOKEN:'new-token'}).SecurityToken,'new-token');
  const newer={TENCENTCLOUD_SECRETID:'new-id',TENCENTCLOUD_SECRETKEY:'new-key',TENCENTCLOUD_SESSIONTOKEN:'fresh-token'};
  assert.equal(credentialsForInvocation({environment:JSON.stringify(newer)}).SecurityToken,'fresh-token');
  assert.equal(credentialsForInvocation({environ:'TENCENTCLOUD_SECRETID=id;TENCENTCLOUD_SECRETKEY=key;TENCENTCLOUD_SESSIONTOKEN=token=with=equals'}).SecurityToken,'token=with=equals');
  assert.throws(()=>credentialsForInvocation({environment:'invalid'}),/INVALID_BACKUP_CONTEXT/);
});
test('forged timer-shaped requests cannot launch backups or read private status',()=>{
  const token='a'.repeat(64),event={Type:'Timer',TriggerName:'huevia-daily-backup',Message:JSON.stringify({action:'backup',token})};
  assert.equal(invocationAction(event,token),'backup');
  for(const message of [undefined,'status','{}',JSON.stringify({action:'status',token:'wrong'})])assert.throws(()=>invocationAction({...event,Message:message},token),/BACKUP_INVOCATION_DENIED/);
  assert.throws(()=>invocationAction(event,'b'.repeat(64)),/BACKUP_INVOCATION_DENIED/);
});
test('CloudBase reader keeps credentials on the fixed origin and does not reflect errors',async()=>{
  const calls=[];const reader=cloudbaseReader('private-service-key-for-test',async(url,options)=>{calls.push({url,options});return new Response(payload);});
  await reader.get({path:'photos/a b.jpg',size:payload.length});
  assert.match(calls[0].url,/^https:\/\/nikon-d8girdjsr252fd90e\.api\.tcloudbasegateway\.com\/v1\/storages\/object\/authenticated\/nikon-presets\/photos\/a%20b.jpg$/);
  assert.equal(calls[0].options.redirect,'error');assert.equal(calls[0].options.headers.Authorization,'Bearer private-service-key-for-test');
  await assert.rejects(readBounded(new Response(Buffer.alloc(10)),4),/SOURCE_TOO_LARGE/);
});
test('COS adapter constrains object operations, SSE, overwrite and bounded reads',async()=>{
  const calls=[];const client=new Proxy({},{get:(_,name)=>(params,done)=>{calls.push({name,params});done(null,{Body:payload});}});
  const store=cosStorage(client);const key='huevia-backups/daily/2026-11-09/valid-run/files/object';
  await store.put(key,payload,'application/octet-stream');assert.equal(calls[0].params.Headers['x-cos-server-side-encryption'],'AES256');
  assert.equal(calls[0].params.Headers['x-cos-forbid-overwrite'],'true');await store.get(key,payload.length);assert.equal(calls[1].params.Range,'bytes=0-'+payload.length);
  assert.throws(()=>store.remove('huevia-updates/app-releases/source.apk'));assert.throws(()=>store.put('other/file',payload,'x'));
  await assert.rejects(store.list('other/'),/INVALID_LIST_PREFIX/);
});
