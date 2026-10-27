import test from 'node:test';
import assert from 'node:assert/strict';
import { CloudBaseStore, CloudBaseStorage } from '../server/cloudbase.mjs';

const origin='https://fixture.api.tcloudbasegateway.com',path=`app-releases/${'a'.repeat(64)}.bin`;
const signedPath=`/v1/storages/object/sign/nikon-presets/${path}`;
const token=(seconds=60)=>`${Buffer.from('{"alg":"HS256"}').toString('base64url')}.${Buffer.from(JSON.stringify({exp:Math.floor(Date.now()/1000)+seconds})).toString('base64url')}.synthetic-signature`;
function fixture(value) {
  const calls=[],secret=token(3600);
  const store=new CloudBaseStore({environmentId:'fixture',apiOrigin:origin,serviceKey:secret,fetchImpl:async(url,options)=>{
    calls.push({url:String(url),options});return new Response(JSON.stringify(typeof value==='function'?value(secret):value),{status:200});
  }});
  return {storage:new CloudBaseStorage(store),calls,secret};
}

test('PG signing authenticates only the configured API and returns a short-lived exact private APK URL',async()=>{
  for(const url of [`${origin}${signedPath}?token=${token()}`,`${signedPath}?token=${token()}`,`/object/sign/nikon-presets/${path}?token=${token()}`]){
    const {storage,calls,secret}=fixture({fullSignedURL:url});
    const target=new URL(await storage.signDownload(path,60));
    assert.equal(target.origin,origin);assert.equal(target.pathname,signedPath);
    assert.equal(calls.length,1,'never fetch the signed download with service credentials');
    assert.equal(calls[0].url,origin+signedPath);assert.equal(calls[0].options.method,'POST');assert.equal(calls[0].options.redirect,'error');
    assert.deepEqual(JSON.parse(calls[0].options.body),{expiresIn:60});assert.equal(calls[0].options.headers.Authorization,`Bearer ${secret}`);
    assert.equal(target.href.includes(secret),false);
  }
});

test('signed APK URLs reject external origins, public/wrong objects, credential echoes and excessive lifetimes without leaking provider details',async()=>{
  const good=`${origin}${signedPath}?token=${token()}`;
  for(const value of [
    {fullSignedURL:good.replace(origin,'https://attacker.test')},
    {fullSignedURL:good.replace('https:','http:')},
    {fullSignedURL:good.replace(origin,`https://user:password@${new URL(origin).host}`)},
    {fullSignedURL:good+'#fragment'},
    {fullSignedURL:good.replace('/object/sign/','/object/public/')},
    {fullSignedURL:good.replace('/nikon-presets/','/other-bucket/')},
    {fullSignedURL:good.replace('a'.repeat(64),'b'.repeat(64))},
    {fullSignedURL:good+'&token=duplicate'},
    {fullSignedURL:good+'&unreviewed=query'},
    {fullSignedURL:`${origin}${signedPath}?token=${token(3600)}`},
    {fullSignedURL:`${origin}${signedPath}?token=${token(-1)}`},
    {fullSignedURL:`${origin}${signedPath}?token=opaque-provider-value`},
    secret=>({fullSignedURL:`${origin}${signedPath}?token=${secret}`}),
    {fullSignedURL:good+'\r\nInjected: value'}, {}, null
  ]){
    const {storage,secret}=fixture(value);
    await assert.rejects(()=>storage.signDownload(path),error=>error.code==='FILE_DOWNLOAD_UNAVAILABLE'&&!error.message.includes(secret)&&!error.message.includes('token='));
  }
  const {storage,calls}=fixture({fullSignedURL:good});
  for(const [name,ttl]of [['other/file.apk',60],[path,0],[path,61],[path,1.5]])await assert.rejects(()=>storage.signDownload(name,ttl),error=>error.code==='FILE_DOWNLOAD_UNAVAILABLE');
  assert.equal(calls.length,0,'reject invalid signing requests before authenticated network I/O');
});

test('only an immutable Huevia APK download filename is appended; arbitrary provider query and injected filenames remain rejected',async()=>{
  const good=`${origin}${signedPath}?token=${token()}`;
  const {storage}=fixture({fullSignedURL:good});
  const url=new URL(await storage.signDownload(path,60,'Huevia-111-beta.apk'));
  assert.equal(url.searchParams.get('download'),'Huevia-111-beta.apk');assert.equal([...url.searchParams].length,2);
  for(const name of ['other.apk','Huevia-0-beta.apk','Huevia-111-unknown.apk','Huevia-111-beta.apk\r\nInjected: value','../Huevia-111-beta.apk'])await assert.rejects(()=>storage.signDownload(path,60,name),error=>error.code==='FILE_DOWNLOAD_UNAVAILABLE');
  const unreviewed=fixture({fullSignedURL:good+'&download=other.apk'});
  await assert.rejects(()=>unreviewed.storage.signDownload(path,60,'Huevia-111-beta.apk'),error=>error.code==='FILE_DOWNLOAD_UNAVAILABLE');
  const legacy=path.replace('.bin','.apk'),legacyPath=signedPath.replace('.bin','.apk');
  const old=fixture({fullSignedURL:`${origin}${legacyPath}?token=${token()}`});
  assert.equal(new URL(await old.storage.signDownload(legacy,60)).pathname,legacyPath);
});
