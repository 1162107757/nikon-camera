import test from 'node:test';
import assert from 'node:assert/strict';
import { downloadUrl, mountDownload } from '../home/home.js';
const release = { id: '7205dc77-3d55-4c1a-95a6-9c8cdf7d3179', packageName: 'cc.huevia', sha256: 'a'.repeat(64), signerSha256: 'b'.repeat(64),
  versionCode: 155, byteLength: 34581880, downloadUrl: 'https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com/preset-library/releases/7205dc77-3d55-4c1a-95a6-9c8cdf7d3179/file' };
test('homepage keeps the current validated same-origin route, including APKs above32MiB', () => {
  assert.equal(downloadUrl(release, 'https://huevia.cc'), 'https://huevia.cc/preset-library/releases/' + release.id + '/file');
});

const fullRelease={...release,versionName:'0.31.0-dev',minSdk:26,publishedAt:'2026-11-13T00:00:00.000Z',notes:'Root homepage fixture'};
const iosRelease={...fullRelease,platform:'ios',packageName:undefined,signerSha256:undefined,bundleId:'cc.huevia.next',distribution:'unsigned-ipa',minimumIOS:'16.0',downloadUrl:release.downloadUrl.replace('/releases/','/ios/releases/')};
const nextRelease={...fullRelease,platform:'android',packageName:'cc.huevia.next',downloadUrl:release.downloadUrl.replace('/releases/','/next/releases/')};
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function page({query='channel=beta',response=()=>({release:fullRelease,reason:'available'}),userAgent=''}={}){
  const nodes=new Map(),groups=new Map(),calls=[],urls=[];
  const element=dataset=>({dataset,hidden:false,href:'',textContent:'',attributes:{},listeners:{},setAttribute(key,value){this.attributes[key]=value;},addEventListener(event,callback){this.listeners[event]=callback;}});
  for(const [name,values] of Object.entries({channel:['stable','beta'],platform:['android','ios'],edition:['legacy','next'],'download-platform':['android','ios']})){
    const key=name==='download-platform'?'downloadPlatform':name;
    groups.set(`[data-${name}]`,values.map(value=>element({[key]:value})));
  }
  const doc={getElementById(id){if(!nodes.has(id))nodes.set(id,element({}));return nodes.get(id);},querySelectorAll(selector){return groups.get(selector)||[];}};
  const location=new URL('https://huevia.cc/?'+query);
  const ready=mountDownload(doc,location,async(path,options)=>{calls.push({path,options});return {ok:true,json:()=>response(new URL(path,location))};},{replaceState(_,_unused,url){assert.equal(url.origin,location.origin);assert.equal(url.pathname,'/');urls.push(url);}}, {userAgent});
  return {ready,nodes,calls,urls,click(name,value){const key=name==='download-platform'?'downloadPlatform':name;groups.get(`[data-${name}]`).find(el=>el.dataset[key]===value).listeners.click();}};
}

test('the existing root beta homepage still downloads original Android without navigating to another page',async()=>{
  const f=page();await f.ready;assert.equal(f.calls[0].path,'/preset-library/releases/latest?channel=beta&packageName=cc.huevia');
  assert.equal(f.nodes.get('release-info').hidden,false);assert.equal(f.nodes.get('download-file').href,'https://huevia.cc/preset-library/releases/'+release.id+'/file');assert.equal(f.urls.length,0);
});

test('root iOS selection renders the IPA file and self-signing copy in the existing download section',async()=>{
  const f=page({query:'channel=beta&platform=ios',response:()=>({release:iosRelease,reason:'available'})});await f.ready;
  assert.match(f.calls[0].path,/\/ios\/releases\/latest/);assert.match(f.nodes.get('download-file').href,/\/ios\/releases\//);
  assert.equal(f.nodes.get('download-label').textContent,'下载 iOS IPA 文件');assert.match(f.nodes.get('download-hint').textContent,/自行签名/);
  assert.equal(f.nodes.get('android-editions').hidden,true);assert.equal(f.nodes.get('ios-file-note').hidden,true);
});

test('homepage hero iOS action switches the same root panel and preserves beta in the root URL',async()=>{
  const f=page({response:url=>({release:url.pathname.includes('/ios/')?iosRelease:fullRelease,reason:'available'})});await f.ready;
  f.click('download-platform','ios');await tick();
  assert.equal(f.nodes.get('download-label').textContent,'下载 iOS IPA 文件');assert.equal(f.urls.at(-1).searchParams.get('channel'),'beta');assert.equal(f.urls.at(-1).searchParams.get('platform'),'ios');
  assert.ok(f.urls.every(url=>url.pathname==='/'));assert.ok(f.calls.every(call=>call.options.credentials==='omit'));
});

test('root homepage new Android selection uses its separate package and rejects a mismatched platform',async()=>{
  const f=page({response:url=>({release:url.searchParams.get('packageName')==='cc.huevia.next'?nextRelease:fullRelease,reason:'available'})});await f.ready;
  f.click('edition','next');await tick();assert.match(f.calls.at(-1).path,/packageName=cc.huevia.next$/);assert.match(f.nodes.get('download-file').href,/\/next\/releases\//);
  const wrong=page({query:'channel=beta&platform=ios'});await wrong.ready;assert.equal(wrong.nodes.get('release-info').hidden,true);assert.match(wrong.nodes.get('release-status').textContent,/平台不匹配/);
});

test('a late original Android response cannot overwrite the root iOS panel',async()=>{
  let resolveOriginal;const f=page({response:url=>url.pathname.includes('/ios/')?({release:iosRelease,reason:'available'}):new Promise(resolve=>{resolveOriginal=resolve;})});
  f.click('platform','ios');await tick();resolveOriginal({release:fullRelease,reason:'available'});await f.ready;
  assert.equal(f.nodes.get('download-label').textContent,'下载 iOS IPA 文件');assert.match(f.nodes.get('download-file').href,/\/ios\/releases\//);
});

test('root iOS beta fallback stays on iOS, while a withdrawn release does not fall back',async()=>{
  const f=page({query:'platform=ios',response:url=>url.searchParams.get('channel')==='beta'?{release:iosRelease,reason:'available'}:{release:null,reason:'no_release'}});await f.ready;
  assert.equal(f.calls.length,2);assert.ok(f.calls.every(call=>call.path.includes('/ios/')));assert.equal(f.urls.at(-1).searchParams.get('channel'),'beta');
  const withdrawn=page({query:'platform=ios',response:()=>({release:null,reason:'withdrawn'})});await withdrawn.ready;assert.equal(withdrawn.calls.length,1);assert.match(withdrawn.nodes.get('release-status').textContent,/已撤回/);
});

test('root iPhone detection and IPA identity and size boundaries remain explicit',async()=>{
  const f=page({userAgent:'iPhone',response:()=>({release:iosRelease,reason:'available'})});await f.ready;assert.match(f.calls[0].path,/\/ios\//);
  for(const invalid of [{bundleId:'another.app'},{distribution:'enterprise'},{minimumIOS:'bad'},{byteLength:134217729},{id:[release.id]}])assert.throws(()=>downloadUrl({...iosRelease,...invalid},'https://huevia.cc'));
  assert.throws(()=>downloadUrl({...fullRelease,byteLength:104857601},'https://huevia.cc'));
  assert.match(downloadUrl({...nextRelease,byteLength:134217728},'https://huevia.cc'),/\/next\//);
});
test('homepage rejects untrusted download locations and malformed release identity', () => {
  for (const download of ['https://evil.example/preset-library/releases/' + release.id + '/file', release.downloadUrl + '?token=x', release.downloadUrl + '#x', release.downloadUrl.replace('/file', '/other')])
    assert.throws(() => downloadUrl({ ...release, downloadUrl: download }, 'https://huevia.cc'));
  for (const patch of [{ id: '../admin' }, { packageName: 'other.app' }, { byteLength: 0 }, { sha256: 'nope' }])
    assert.throws(() => downloadUrl({ ...release, ...patch }, 'https://huevia.cc'));
});
