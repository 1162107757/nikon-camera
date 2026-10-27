import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHash } from 'node:crypto';
import { CloudBaseStore, CloudBaseStorage } from '../server/cloudbase.mjs';
import { createReleaseRoutes, APK_INLINE_BYTES, APK_SIGNED_URL_TTL_SECONDS } from '../server/releases.mjs';
import { MAX_APK_BYTES } from '../server/apk.mjs';
import { ReleaseMemoryStore } from './release-memory-store.mjs';

test('large private APK download issues only a bounded 307 after bytes/hash, budget and post-sign withdrawal checks',async t=>{
  const apk=Buffer.alloc(APK_INLINE_BYTES+17,7),sha256=createHash('sha256').update(apk).digest('hex');
  const id='12345678-1234-4234-8234-123456789abc',storagePath=`app-releases/${sha256}.bin`;
  const store=new ReleaseMemoryStore(),row={id,status:'published',sha256,byte_length:apk.length,storage_path:storagePath,version_code:111,channel:'beta'};
  store.releaseRows.push(row);
  const expires=Math.floor(Date.now()/1000)+APK_SIGNED_URL_TTL_SECONDS;
  const jwt=`header.${Buffer.from(JSON.stringify({exp:expires})).toString('base64url')}.signature`;
  let mode='valid',reads=0,signs=0;
  const signer=new CloudBaseStorage(new CloudBaseStore({environmentId:'fixture',apiOrigin:'https://fixture.api.tcloudbasegateway.com',serviceKey:'synthetic-private-credential',fetchImpl:async(url,options)=>{
    signs++;assert.equal(options.redirect,'error');assert.equal(String(url),`https://fixture.api.tcloudbasegateway.com/v1/storages/object/sign/nikon-presets/${storagePath}`);
    assert.deepEqual(JSON.parse(options.body),{expiresIn:60});
    if(mode==='withdraw-during-sign')row.status='withdrawn';
    return new Response(JSON.stringify({fullSignedURL:`https://${mode==='bad-url'?'attacker.test':'fixture.api.tcloudbasegateway.com'}/v1/storages/object/sign/nikon-presets/${storagePath}?token=${jwt}`}));
  }}));
  const routes=createReleaseRoutes({store,publicBaseUrl:'https://updates.test',storage:{
    get:async(path,maximum)=>{reads++;assert.equal(path,storagePath);assert.equal(maximum,MAX_APK_BYTES);if(mode==='withdraw-during-read')row.status='withdrawn';return mode==='corrupt'?Buffer.alloc(apk.length,8):mode==='wrong-size'?apk.subarray(1):apk;},
    signDownload:signer.signDownload.bind(signer)
  },readBundledApk:async()=>{throw Error('large redirects must verify the real private object, not bundled bytes');}});
  const server=createServer(async(req,res)=>{try{const url=new URL(req.url,'http://localhost');await routes.publicRoute(req,res,{path:url.pathname,url,json:(_r,value)=>res.end(JSON.stringify(value))});}catch(error){res.writeHead(error.status||500);res.end(error.code||'ERROR');}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>{server.closeAllConnections();server.close();});
  const endpoint=`http://127.0.0.1:${server.address().port}/releases/${id}/file`;
  const request=headers=>fetch(endpoint,{redirect:'manual',headers});
  let response=await request();
  assert.equal(response.status,307);assert.equal(response.headers.get('content-length'),'0');assert.equal((await response.arrayBuffer()).byteLength,0);
  assert.match(response.headers.get('cache-control'),/no-store/);assert.equal(response.headers.get('referrer-policy'),'no-referrer');assert.equal(response.headers.get('x-content-sha256'),sha256);
  const location=new URL(response.headers.get('location'));assert.equal(location.origin,'https://fixture.api.tcloudbasegateway.com');assert.equal(location.searchParams.get('token'),jwt);
  assert.equal(location.searchParams.get('download'),'Huevia-111-beta.apk');assert.equal([...location.searchParams].length,2);
  assert.equal(response.headers.get('authorization'),null);assert.equal(response.headers.get('set-cookie'),null);
  assert.equal(reads,1);assert.equal(signs,1);
  response=await request({'If-None-Match':`"sha256-${sha256}"`});assert.equal(response.status,304);assert.equal(signs,1);
  store.releaseBudgetDenied=true;response=await request();assert.equal(response.status,429);assert.equal(reads,1);assert.equal(signs,1);store.releaseBudgetDenied=false;
  for(const invalid of ['corrupt','wrong-size']){mode=invalid;response=await request();assert.equal(response.status,503);assert.equal(response.headers.get('location'),null);assert.equal(signs,1);}
  for(const invalid of ['withdraw-during-read','withdraw-during-sign']){row.status='published';mode=invalid;response=await request();assert.equal(response.status,404);assert.equal(response.headers.get('location'),null);}
  response=await request({'If-None-Match':`"sha256-${sha256}"`});assert.equal(response.status,404,'withdrawal remains ahead of conditional responses');
  row.status='published';mode='bad-url';response=await request();assert.equal(response.status,503);assert.equal(response.headers.get('location'),null);assert.equal((await response.text()).includes('token='),false);
});
