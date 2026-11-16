import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createHandler} from '../server/app.mjs';
import {ReleaseMemoryStore} from './release-memory-store.mjs';
let PGlite;
try {({PGlite}=await import('../../.community-pg-test/node_modules/@electric-sql/pglite/dist/index.js'));}
catch(error){if(error.code!=='ERR_MODULE_NOT_FOUND')throw error;}

test('mobile SQL preserves quotas, debits fixed retries once and isolates files and sources',{skip:!PGlite},async()=>{
  const db=new PGlite();
  try {
    await db.exec('CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE TABLE nikon_mobile_release_budgets(budget_key text PRIMARY KEY,requests bigint NOT NULL DEFAULT 0,bytes bigint NOT NULL DEFAULT 0,expires_at timestamptz NOT NULL);');
    await db.exec("INSERT INTO nikon_mobile_release_budgets VALUES('historical',7,12345,clock_timestamp()+interval '2 days')");
    const migration=await readFile(new URL('../database/024-mobile-download-retry.sql',import.meta.url),'utf8');
    const snapshot=async()=>(await db.query('SELECT * FROM nikon_mobile_release_budgets ORDER BY budget_key')).rows;
    const before=await snapshot();await db.exec(migration);await db.exec(migration);assert.deepEqual(await snapshot(),before);
    const source='a'.repeat(64),sha='b'.repeat(64),size=53264170;
    const reserve=async(key=source,hash=sha,bytes=size)=>(await db.query('SELECT nikon_mobile_release_download_budget($1,$2,$3) AS v',[key,hash,bytes])).rows[0].v;
    assert.equal((await reserve()).chargedBytes,size);
    const lease=(await db.query("SELECT * FROM nikon_mobile_release_budgets WHERE budget_key LIKE 'file:lease:%'")).rows[0];
    for(let i=1;i<20;i++)assert.equal((await reserve()).chargedBytes,0,'each retry must not reserve a second full download');
    assert.deepEqual((await db.query("SELECT * FROM nikon_mobile_release_budgets WHERE budget_key LIKE 'file:lease:%'")).rows[0],lease,'retry expiry is not extended');
    const denied=await reserve();assert.equal(denied.error,'BUDGET');assert.equal(denied.scope,'ip');assert.ok(denied.retryAfterSeconds>=1&&denied.retryAfterSeconds<=3600);
    const blocked=await snapshot();await reserve();assert.deepEqual(await snapshot(),blocked,'denials preserve all counters');
    assert.equal((await reserve('c'.repeat(64))).chargedBytes,size,'another source has an independent lease');
    await db.exec("UPDATE nikon_mobile_release_budgets SET requests=0 WHERE budget_key LIKE 'file:ip:%';UPDATE nikon_mobile_release_budgets SET bytes=536870912 WHERE budget_key LIKE 'file:ip:%'");
    assert.equal((await reserve()).allowed,true,'charged retry still works at byte ceiling');
    assert.equal((await reserve(source,'d'.repeat(64))).scope,'ip','different file cannot borrow the lease');
    assert.equal((await reserve(source,sha,size+1)).scope,'ip','changed length cannot borrow the lease');
    assert.equal((await reserve(source,sha,0)).chargedBytes,0,'304 remains zero bytes');
    await db.exec("UPDATE nikon_mobile_release_budgets SET bytes=0,requests=0 WHERE budget_key LIKE 'file:ip:%';UPDATE nikon_mobile_release_budgets SET expires_at=clock_timestamp()-interval '1 second' WHERE budget_key LIKE 'file:lease:%'");
    assert.equal((await reserve()).chargedBytes,size,'expired retry window charges again');
    await db.exec("UPDATE nikon_mobile_release_budgets SET bytes=5368709120 WHERE budget_key LIKE 'file:global:%'");
    assert.equal((await reserve()).chargedBytes,0,'already reserved retry does not consume more global bytes');
    assert.equal((await reserve('e'.repeat(64))).scope,'global','global protection still blocks new reservations');
    await db.exec("UPDATE nikon_mobile_release_budgets SET requests=1000 WHERE budget_key LIKE 'file:global:%'");
    const global=await reserve();assert.equal(global.scope,'global');assert.ok(global.retryAfterSeconds>=1&&global.retryAfterSeconds<=86400);
    for(const values of [[null,sha,size],[source,null,size],[source,sha,null],[source,sha,-1],[source,sha,134217729]])assert.equal((await db.query('SELECT nikon_mobile_release_download_budget($1,$2,$3) AS v',values)).rows[0].v.error,'INVALID');
    const privileges=(await db.query("SELECT has_function_privilege('anon','nikon_mobile_release_download_budget(text,text,integer)','EXECUTE') AS anon,has_function_privilege('authenticated','nikon_mobile_release_download_budget(text,text,integer)','EXECUTE') AS authenticated,has_function_privilege('service_role','nikon_mobile_release_download_budget(text,text,integer)','EXECUTE') AS service")).rows[0];
    assert.deepEqual(privileges,{anon:false,authenticated:false,service:true});
  } finally {await db.close();}
});

test('Android and iOS HTTP download routes bind retry accounting, preserve 304 and expose real retry times',async t=>{
  const store=new ReleaseMemoryStore(),sha='a'.repeat(64),id='12345678-1234-4234-8234-123456789abc';
  let platform='android',denial=null,verified=0;const calls=[];
  const row=()=>({id,platform,status:'published',version_code:229,metadata:{sha256:sha,byteLength:2048},storage_path:`mobile-releases/${platform}/${sha}.bin`});
  const originalRest=store.rest.bind(store),originalRpc=store.rpc.bind(store);
  store.rest=async path=>path.startsWith('nikon_mobile_releases?')?[row()]:originalRest(path);
  store.rpc=async(name,body)=>{
    if(name==='nikon_mobile_release_download_budget'){calls.push({name,body});return denial||{allowed:true};}
    return originalRpc(name,body);
  };
  const handler=createHandler({store,storage:{verify:async()=>{verified++;return true;},signDownload:async()=> 'https://download.example/fixture'},publicBaseUrl:'http://127.0.0.1',environmentId:'fixture',secureCookies:false});
  const server=createServer(handler);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>{server.closeAllConnections();server.close();});
  for(const prefix of ['next','ios']){
    platform=prefix==='ios'?'ios':'android';denial=null;
    const url=`http://127.0.0.1:${server.address().port}/preset-library/${prefix}/releases/${id}/file`;
    let response=await fetch(url,{redirect:'manual'});assert.equal(response.status,307);assert.equal(calls.at(-1).body.p_sha256,sha);assert.equal(calls.at(-1).body.p_bytes,2048);
    response=await fetch(url,{headers:{'If-None-Match':`"sha256-${sha}"`}});assert.equal(response.status,304);assert.equal(calls.at(-1).body.p_bytes,0);
    const reads=verified;
    for(const [scope,retry,code,title,wait] of [['ip',123,'MOBILE_RELEASE_IP_BUDGET','当前网络下载已达上限','3 分钟'],['global',3723,'MOBILE_RELEASE_GLOBAL_BUDGET','今日下载服务已达上限','1 小时 3 分钟']]){
      denial={error:'BUDGET',scope,retryAfterSeconds:retry};
      response=await fetch(url,{headers:{Accept:'application/json'}});assert.equal(response.status,429);assert.equal(response.headers.get('retry-after'),String(retry));assert.equal((await response.json()).error.code,code);
      response=await fetch(url,{headers:{Accept:'text/html'}});const html=await response.text();assert.equal(response.status,429);assert.match(response.headers.get('content-type'),/text\/html/);assert.ok(html.includes(title));assert.ok(html.includes(wait));assert.ok(html.includes(prefix==='ios'?'platform=ios':'edition=next'));assert.equal(response.headers.get('content-disposition'),null);
    }
    assert.equal(verified,reads,'denied requests do not touch the binary');
    denial={error:'INVALID',scope:'ip',retryAfterSeconds:123};response=await fetch(url);assert.equal(response.status,503);assert.equal(response.headers.get('retry-after'),null);
  }
});
