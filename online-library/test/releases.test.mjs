import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { hashPassword } from '../server/auth.mjs';
import { createHandler } from '../server/app.mjs';
import { selectRelease, createReleaseRoutes } from '../server/releases.mjs';
import { ReleaseMemoryStore } from './release-memory-store.mjs';

let apk;try{apk=await readFile(new URL('../../dist/nikon-usb-0.9.14-beta-debug.apk',import.meta.url));}catch{}

test('bundled signed APKs retain publication, integrity, budgets and withdrawal checks; other files use private storage', {skip:!apk}, async t => {
  const sha256=createHash('sha256').update(apk).digest('hex'),id='12345678-1234-4234-8234-123456789abc';
  const store=new ReleaseMemoryStore();
  const row={id,status:'published',sha256,byte_length:apk.length,storage_path:`app-releases/${sha256}.apk`,version_code:53};
  store.releaseRows.push(row);
  let mode='bundled',reads=0,remoteReads=0;
  const routes=createReleaseRoutes({store,publicBaseUrl:'https://updates.test',storage:{get:async()=>{remoteReads++;return apk;}},readBundledApk:async name=>{
    reads++;assert.equal(name,`${sha256}.apk`);
    if(mode==='missing')throw Object.assign(new Error('No bundled file'),{code:'ENOENT'});
    if(mode==='io-error')throw Object.assign(new Error('Unreadable bundled file'),{code:'EACCES'});
    if(mode==='withdraw-during-read')row.status='withdrawn';
    if(mode==='corrupt'){const changed=Buffer.from(apk);changed[500]^=1;return changed;}
    return apk;
  }});
  const server=createServer(async(req,res)=>{try{const url=new URL(req.url,'http://localhost');await routes.publicRoute(req,res,{path:url.pathname,url,json:(response,value)=>response.end(JSON.stringify(value))});}catch(error){res.writeHead(error.status||500);res.end(error.code||'ERROR');}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>{server.closeAllConnections();server.close();});
  const url=`http://127.0.0.1:${server.address().port}/releases/${id}/file`;
  let r=await fetch(url);assert.equal(r.status,200);assert.deepEqual(Buffer.from(await r.arrayBuffer()),apk);assert.equal(remoteReads,0);
  mode='missing';r=await fetch(url);assert.equal(r.status,200);await r.arrayBuffer();assert.equal(remoteReads,1);
  mode='corrupt';assert.equal((await fetch(url)).status,503);assert.equal(remoteReads,1,'do not substitute another copy for a corrupt bundled artifact');
  mode='io-error';assert.equal((await fetch(url)).status,503);
  store.releaseBudgetDenied=true;const priorReads=reads;assert.equal((await fetch(url)).status,429);assert.equal(reads,priorReads);store.releaseBudgetDenied=false;
  mode='withdraw-during-read';assert.equal((await fetch(url)).status,404);
  assert.equal((await fetch(url,{headers:{'If-None-Match':`"sha256-${sha256}"`}})).status,404);assert.equal(remoteReads,1);
});
test('update contract never downgrades or silently chooses an older version after withdrawal',()=>{
  const row={id:'test',status:'published',version_code:53,min_sdk:26};
  assert.equal(selectRelease(row,{versionCode:54}).reason,'client_newer');assert.equal(selectRelease(row,{versionCode:53}).reason,'current');
  assert.equal(selectRelease(row,{versionCode:52,sdk:25}).reason,'incompatible');assert.equal(selectRelease(row,{versionCode:52,sdk:26}).updateAvailable,true);
  assert.deepEqual(selectRelease({...row,status:'withdrawn'}),{schemaVersion:1,channel:'stable',release:null,updateAvailable:false,updateRequired:false,reason:'withdrawn'});
});

test('mandatory update contract applies only to a newer compatible published release and defaults old rows to optional',()=>{
  const row={id:'fixture',status:'published',version_code:99,min_sdk:26,revision:4};
  const optional=selectRelease(row,{versionCode:98,sdk:26});assert.equal(optional.updateRequired,false);assert.equal(optional.release.mandatory,false);
  const forced={...row,mandatory:true};
  const available=selectRelease(forced,{versionCode:98,sdk:26});assert.equal(available.schemaVersion,1);assert.equal(available.updateRequired,true);assert.equal(available.release.mandatory,true);assert.equal(available.release.revision,4);
  for(const [candidate,params,reason] of [[forced,{versionCode:99,sdk:26},'current'],[forced,{versionCode:100,sdk:26},'client_newer'],[forced,{versionCode:98,sdk:25},'incompatible'],[{...forced,status:'withdrawn'},{versionCode:98,sdk:26},'withdrawn'],[{...forced,status:'draft'},{versionCode:98,sdk:26},'no_release'],[null,{},'no_release']]){
    const result=selectRelease(candidate,params);assert.equal(result.reason,reason);assert.equal(result.updateRequired,false);assert.equal(result.updateAvailable,false);
  }
  for(const mandatory of ['true',1,null,undefined])assert.equal(selectRelease({...row,mandatory},{versionCode:98}).updateRequired,false);
  assert.equal(selectRelease({...forced,mandatory:false},{versionCode:98}).updateRequired,false,'rechecking the same release cancels a revoked requirement');
});

test('update policy HTTP enforces administrator, CSRF, booleans, revisions, artifact confirmation and withdrawal',async t=>{
  const store=new ReleaseMemoryStore(),password='Synthetic-policy-test-password',id='87654321-4321-4321-8321-cba987654321';
  store.admins.set('admin',{username:'admin',password_hash:await hashPassword(password)});
  const row={id,package_name:'cc.huevia',version_name:'fixture',version_code:99,min_sdk:26,sha256:'a'.repeat(64),channel:'beta',notes:'Synthetic notes',status:'draft',mandatory:false,revision:1};store.releaseRows.push(row);
  const server=createServer();await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>{server.closeAllConnections();server.close();});
  const origin=`http://127.0.0.1:${server.address().port}`;server.on('request',createHandler({store,storage:{},environmentId:'test-only',publicBaseUrl:origin,secureCookies:false}));
  let cookie='',csrf='';
  const request=(path,body,headers={})=>fetch(origin+'/preset-library'+path,{method:'PUT',headers:{Cookie:cookie,Origin:origin,'X-CSRF-Token':csrf,'Content-Type':'application/json',...headers},body:JSON.stringify(body)});
  const policy=(mandatory,extra={})=>({mandatory,expectedRevision:row.revision,confirmation:`${mandatory?'REQUIRE':'OPTIONAL'} 99 ${row.sha256}`,...extra});
  assert.equal((await request(`/api/releases/${id}/policy`,policy(true))).status,401);
  const login=await fetch(origin+'/preset-library/api/login',{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:JSON.stringify({username:'admin',password})});assert.equal(login.status,200);cookie=login.headers.get('set-cookie').split(';')[0];csrf=(await login.json()).csrfToken;
  assert.equal((await request(`/api/releases/${id}/policy`,policy(true),{'X-CSRF-Token':'wrong'})).status,403);
  for(const mandatory of ['true',1,null])assert.equal((await request(`/api/releases/${id}/policy`,policy(mandatory))).status,400);
  assert.equal((await request(`/api/releases/${id}/policy`,policy(true,{expectedRevision:0}))).status,400);
  assert.equal((await request(`/api/releases/${id}/policy`,policy(true,{expectedRevision:2}))).status,409);
  assert.equal((await request(`/api/releases/${id}/policy`,policy(true,{confirmation:'yes'}))).status,400);
  let changed=await request(`/api/releases/${id}/policy`,policy(true));assert.equal(changed.status,200);assert.equal((await changed.json()).release.mandatory,true);assert.equal(row.revision,2);
  assert.equal(selectRelease(row,{versionCode:98}).updateRequired,false,'draft policy does not publish');
  const published=await store.rpc('nikon_app_release_action',{p_actor:'admin',p_id:id,p_revision:row.revision,p_action:'publish',p_confirmation:`PUBLISH 99 ${row.sha256}`});assert.equal(published.status,'published');
  const latest=()=>fetch(origin+'/preset-library/releases/latest?packageName=cc.huevia&channel=beta&versionCode=98&sdk=35').then(r=>{assert.match(r.headers.get('cache-control'),/no-store/);return r.json();});
  assert.equal((await latest()).updateRequired,true);
  changed=await request(`/api/releases/${id}/policy`,policy(false));assert.equal(changed.status,200);assert.equal((await latest()).updateRequired,false);
  const auditCount=store.releaseAudits.length,unchangedRevision=row.revision;assert.equal((await request(`/api/releases/${id}/policy`,policy(false))).status,200);assert.equal(store.releaseAudits.length,auditCount);assert.equal(row.revision,unchangedRevision,'same policy is idempotent');
  assert.equal((await request(`/api/releases/${id}/policy`,policy(true,{expectedRevision:2}))).status,409,'stale manager cannot re-enable a revoked requirement');
  assert.equal((await request(`/api/releases/${id}/policy`,policy(true))).status,200);
  await store.rpc('nikon_app_release_action',{p_actor:'admin',p_id:id,p_revision:row.revision,p_action:'withdraw',p_confirmation:'WITHDRAW 99'});
  assert.equal((await latest()).updateRequired,false);assert.equal((await latest()).release,null);
  assert.equal((await request(`/api/releases/${id}/policy`,policy(false))).status,409);
  const policies=store.releaseAudits.filter(a=>a.action==='policy');assert.deepEqual(policies.map(a=>a.details.mandatory),[true,false,true]);assert.ok(policies.every(a=>a.actor==='admin'));
  store.admins.get('admin').disabled=true;assert.equal((await request(`/api/releases/${id}/policy`,policy(false))).status,401);
});
test('release HTTP: active administrators/CSRF, bounded durable chunks, actual metadata, immutable versions, public integrity and withdrawal', {skip:!apk},async t=>{
  const store=new ReleaseMemoryStore(),objects=new Map(),password='Synthetic-release-test-password';
  for(const name of ['rootmain','admin'])store.admins.set(name,{username:name,password_hash:await hashPassword(password)});
  const server=createServer();await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>{server.closeAllConnections();server.close();});
  const origin=`http://127.0.0.1:${server.address().port}`;
  server.on('request',createHandler({store,storage:{put:async(path,data)=>objects.set(path,Buffer.from(data)),get:async(path)=>objects.get(path)},environmentId:'test-only',publicBaseUrl:origin,secureCookies:false}));
  let cookie='',csrf='';
  const request=(path,{method='GET',body,raw=false,headers={}}={})=>fetch(origin+'/preset-library'+path,{method,headers:{...(cookie?{Cookie:cookie}:{}),...(method!=='GET'?{Origin:origin,'X-CSRF-Token':csrf,'Content-Type':raw?'application/octet-stream':'application/json'}:{}),...headers},body:body===undefined?undefined:raw?body:JSON.stringify(body),redirect:'manual'});
  const login=async username=>{const response=await request('/api/login',{method:'POST',body:{username,password}});assert.equal(response.status,200);cookie=response.headers.get('set-cookie').split(';')[0];csrf=(await response.json()).csrfToken;};
  assert.equal((await request('/api/releases')).status,401);await login('rootmain');assert.equal((await request('/api/releases')).status,200);await login('admin');assert.equal((await request('/api/releases')).status,200);
  assert.equal((await request('/api/releases/uploads',{method:'POST',headers:{'X-CSRF-Token':'wrong'},body:{}})).status,403);
    assert.equal((await request('/api/releases/uploads',{method:'POST',body:{byteLength:33554433,channel:'stable',notes:'超限'}})).status,400);
  async function upload(data){
    const response=await request('/api/releases/uploads',{method:'POST',body:{byteLength:data.length,channel:'beta',notes:'服务器验签测试',versionCode:99999,packageName:'forged.invalid'}});assert.equal(response.status,201);const task=await response.json();
    assert.equal((await request(`/api/releases/uploads/${task.uploadId}/complete`,{method:'POST',body:{}})).status,409);
    for(let offset=0,index=0;offset<data.length;offset+=task.chunkBytes,index++)assert.equal((await request(`/api/releases/uploads/${task.uploadId}/chunks/${index}`,{method:'PUT',raw:true,body:data.subarray(offset,offset+task.chunkBytes)})).status,200);
    return request(`/api/releases/uploads/${task.uploadId}/complete`,{method:'POST',body:{versionCode:99999}});
  }
  const created=await upload(apk);assert.equal(created.status,201);let release=(await created.json()).release;
  assert.equal(release.versionCode,53);assert.equal(release.packageName,'com.nikonpreset.usbprobe');assert.equal(release.status,'draft');
  assert.equal((await request(`/releases/${release.id}/file`)).status,404);assert.equal((await (await request('/releases/latest?channel=beta')).json()).release,null);
  assert.equal((await upload(apk)).status,409,'duplicate actual versionCode cannot be overwritten');
  const changed=Buffer.from(apk);changed[500]^=1;assert.equal((await upload(changed)).status,400,'valid certificate with changed APK contents is rejected');
  const action=(verb,body)=>request(`/api/releases/${release.id}/${verb}`,{method:'POST',body:{expectedRevision:release.revision,...body}});
  assert.equal((await action('publish',{confirmation:'yes'})).status,400);
  const published=await action('publish',{confirmation:`PUBLISH 53 ${release.sha256}`});assert.equal(published.status,200);release=(await published.json()).release;
  assert.equal((await request(`/api/releases/${release.id}`,{method:'PUT',body:{expectedRevision:release.revision,notes:'覆盖'}})).status,400);
  const latest=await(await request('/releases/latest?channel=beta&versionCode=52&sdk=26')).json();assert.equal(latest.updateAvailable,true);assert.equal(latest.release.id,release.id);
  const download=await request(`/releases/${release.id}/file`);assert.equal(download.status,200);assert.match(download.headers.get('cache-control'),/no-store/);assert.match(download.headers.get('content-disposition'),/attachment/);assert.equal(download.headers.get('x-content-sha256'),release.sha256);assert.deepEqual(Buffer.from(await download.arrayBuffer()),apk);
  assert.equal((await request(`/releases/${release.id}/file`,{headers:{'If-None-Match':download.headers.get('etag')}})).status,304);
  const withdrawal=await action('withdraw',{confirmation:'WITHDRAW 53'});assert.equal(withdrawal.status,200);
  assert.equal((await request(`/releases/${release.id}/file`,{headers:{'If-None-Match':download.headers.get('etag')}})).status,404);
  const after=await(await request('/releases/latest?channel=beta&versionCode=52&sdk=26')).json();assert.equal(after.reason,'withdrawn');assert.equal(after.release,null);
  assert.deepEqual(store.releaseAudits.filter(a=>a.release_id===release.id).map(a=>a.action),['upload_verified','publish','withdraw']);
  assert.ok(store.releaseAudits.every(a=>a.actor==='admin'),'audit records the administrator who actually acted');
  assert.equal(store.uploadBudgetBytes,apk.length*5,'all three chunk uploads and both valid assembled-APK writes reserve actual bytes');
  store.releaseBudgetDenied=true;assert.equal((await request('/releases/latest')).status,429);
  assert.equal((await request('/download/')).status,200);assert.equal((await request('/download/../server/apk.mjs')).status,404);
  store.admins.get('admin').disabled=true;assert.equal((await request('/api/releases')).status,401,'disabled administrator sessions cannot manage releases');
});

test('upload conflict and zero-byte requests are bounded before storage; reservations preserve task ownership and readiness',async()=>{
  const store=new ReleaseMemoryStore(),objects=new Map(),writes=[];
  for(const username of ['admin','rootmain'])store.admins.set(username,{username,disabled:false});
  store.admins.set('disabled',{username:'disabled',disabled:true});
  const routes=createReleaseRoutes({store,storage:{put:async(path,data)=>{writes.push(path);objects.set(path,Buffer.from(data));}},publicBaseUrl:'https://updates.test'});
  const {uploadId}=await store.rpc('nikon_app_upload_begin',{p_actor:'admin',p_size:524288,p_channel:'beta',p_notes:'In-memory safety fixture'});
  const chunk=(data,actor='admin')=>routes.adminRoute({method:'PUT'},{},{path:`/api/releases/uploads/${uploadId}/chunks/0`,session:{username:actor},readBody:async()=>data,json:()=>{}});
  const original=Buffer.alloc(524288,1);
  await chunk(original);
  for(let i=2;i<=6;i++)await assert.rejects(()=>chunk(Buffer.alloc(524288,i)),error=>error.code==='RELEASE_CONFLICT');
  assert.equal(objects.size,1,'conflicting hashes never create orphan objects');assert.equal(writes.length,1);
  assert.equal(store.uploadBudgetBytes,6*524288,'conflicting requests still consume the actual-byte budget');
  await assert.rejects(()=>chunk(original,'rootmain'),error=>error.code==='RELEASE_UPLOAD_EXPIRED','a different valid administrator cannot write another upload task');
  for(const actor of ['missing','disabled'])await assert.rejects(()=>chunk(original,actor),error=>error.code==='RELEASE_FORBIDDEN');
  store.uploadBudgetBytes=838860800-original.length;
  await chunk(original);assert.equal(store.uploadBudgetBytes,838860800);
  await assert.rejects(()=>chunk(original),error=>error.code==='RELEASE_BUDGET');assert.equal(writes.length,2,'exhausted budget prevents another put');
  store.uploadBudgetRequests=255;
  await assert.rejects(()=>chunk(Buffer.alloc(0)),error=>error.code==='EMPTY_CHUNK');
  await assert.rejects(()=>chunk(Buffer.alloc(0)),error=>error.code==='RELEASE_BUDGET');
  assert.equal(store.uploadBudgetRequests,256,'empty requests reach the same 15-minute request ceiling');
  const pending=await store.rpc('nikon_app_upload_begin',{p_actor:'admin',p_size:4,p_channel:'beta',p_notes:'Ready-state fixture'});
  const reserved={p_actor:'admin',p_id:pending.uploadId,p_index:0,p_size:4,p_sha256:'a'.repeat(64),p_path:`app-upload/${pending.uploadId}/0-${'a'.repeat(64)}.part`};
  await store.rpc('nikon_app_upload_reserve',reserved);
  assert.equal((await store.rpc('nikon_app_upload_claim',{p_actor:'admin',p_id:pending.uploadId})).error,'INCOMPLETE','a reserved chunk cannot be assembled before storage succeeds');
  await store.rpc('nikon_app_upload_chunk',reserved);
  assert.ok(!(await store.rpc('nikon_app_upload_claim',{p_actor:'admin',p_id:pending.uploadId})).error);
});
