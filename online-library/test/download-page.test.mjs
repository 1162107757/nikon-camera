import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { SourceTextModule, createContext } from 'node:vm';
import { MAX_APK_BYTES } from '../server/apk.mjs';

const source = await readFile(new URL('../download/download.js', import.meta.url), 'utf8');
const legacyOrigin = 'https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com';
const id = '12345678-1234-4234-8234-123456789abc';
function release(overrides = {}) {
  return { id, downloadUrl: `${legacyOrigin}/preset-library/releases/${id}/file`, sha256: 'a'.repeat(64),
    signerSha256: 'b'.repeat(64), byteLength: 3400000, versionCode: 74, versionName: 'fixture',
    minSdk: 26, publishedAt: '2026-10-21T00:00:00.000Z', notes: 'Synthetic release',
    packageName: 'com.nikonpreset.usbprobe', ...overrides };
}
async function fixture(moduleUrl, selectedRelease = release(), options = {}) {
  const nodes = new Map(), calls = [], groups = new Map();
  for(const [key,values] of Object.entries({channel:['stable','beta'],platform:['android','ios'],edition:['legacy','next']})) {
    groups.set(`[data-${key}]`,values.map(value=>({dataset:{[key]:value},listeners:{},setAttribute(){},addEventListener(event,callback){this.listeners[event]=callback;}})));
  }
  const byId = id => {
    if (!nodes.has(id)) nodes.set(id, { hidden: false, textContent: '', href: '', addEventListener() {}, replaceChildren() {} });
    return nodes.get(id);
  };
  const location = new URL('./?'+(options.query||'channel=beta'), moduleUrl);
  const context = createContext({ URL, location, Intl, document: { getElementById: byId, querySelectorAll: selector => groups.get(selector)||[] },
    history: { replaceState() {} }, navigator: { userAgent:options.userAgent||'',clipboard: { writeText: async () => {} } },
    fetch: async (url, init) => { calls.push({ url: String(url), options:init }); return { ok: true,
      json: async () => options.response ? options.response(new URL(url)) : ({ release: selectedRelease, reason: selectedRelease ? 'available' : 'no_release' }) }; } });
  const module = new SourceTextModule(source, { context, initializeImportMeta(meta) { meta.url = moduleUrl; } });
  await module.link(() => { throw new Error('The download page must not import external modules'); });
  await module.evaluate();
  await new Promise(resolve => setImmediate(resolve));
  return { helper: module.namespace.releaseDownloadUrl, nodes, calls, click(key,value){groups.get(`[data-${key}]`).find(item=>item.dataset[key]===value).listeners.click();} };
}

for (const origin of [legacyOrigin, 'https://custom.example.test']) {
  test(`${origin}: real download page keeps legacy metadata and renders a current-origin APK link`, async () => {
    const f = await fixture(origin + '/preset-library/download/download.js');
    assert.equal(f.nodes.get('release').hidden, false);
    assert.equal(f.nodes.get('empty').hidden, true);
    assert.equal(f.nodes.get('download-button').href, `${origin}/preset-library/releases/${id}/file`);
    assert.equal(f.calls[0].url, origin + '/preset-library/releases/latest?channel=beta&packageName=cc.huevia');
    assert.equal(f.calls[0].options.credentials, 'omit');
    assert.equal(f.nodes.get('sha256').textContent, 'a'.repeat(64));
    assert.equal(f.nodes.get('signer').textContent, 'b'.repeat(64));
  });
}

test('download routes support root deployment and canonical URLs already using the custom domain', async () => {
  const f = await fixture('https://custom.example.test/download/download.js');
  assert.equal(f.nodes.get('download-button').href, `https://custom.example.test/releases/${id}/file`);
  const base = 'https://custom.example.test/preset-library/';
  const expected = `${base}releases/${id}/file`;
  assert.equal(f.helper(release({ downloadUrl: expected }), base).href, expected);
});

const iosRelease = overrides => release({platform:'ios',distribution:'unsigned-ipa',bundleId:'cc.huevia.next',minimumIOS:'15.0',
  downloadUrl:`${legacyOrigin}/preset-library/ios/releases/${id}/file`,signerSha256:undefined,packageName:undefined,...overrides});
test('iOS renders a direct current-site IPA file link, metadata and self-signing notice',async()=>{
  const f=await fixture('https://custom.example.test/preset-library/download/download.js',iosRelease(),{query:'platform=ios&channel=beta'});
  assert.equal(f.calls[0].url,'https://custom.example.test/preset-library/ios/releases/latest?channel=beta&bundleId=cc.huevia.next');
  assert.equal(f.nodes.get('download-button').href,`https://custom.example.test/preset-library/ios/releases/${id}/file`);
  assert.equal(f.nodes.get('download-label').textContent,'下载 iOS IPA 文件');
  assert.match(f.nodes.get('metadata').textContent,/iOS 15.0/);assert.equal(f.nodes.get('signer').hidden,true);
  assert.equal(f.nodes.get('android-editions').hidden,true);assert.equal(f.nodes.get('ios-file-note').hidden,false);
  assert.match(f.nodes.get('install-copy').textContent,/自行签名/);assert.doesNotMatch(f.nodes.get('download-button').href,/itms-services/);
  for(const invalid of [{distribution:'enterprise'},{bundleId:'another.app'},{minimumIOS:'invalid'},{byteLength:134217729}])assert.throws(()=>f.helper(iosRelease(invalid),'https://custom.example.test/preset-library/'),/版本信息不完整/);
  for(const downloadUrl of [`${legacyOrigin}/preset-library/next/releases/${id}/file`,`https://evil.test/ios/releases/${id}/file`])assert.throws(()=>f.helper(iosRelease({downloadUrl}),'https://custom.example.test/preset-library/'),/下载地址校验失败/);
});

test('new Android uses its own package, signer and 128MiB boundary without changing original URLs',async()=>{
  const value=release({packageName:'cc.huevia.next',platform:'android',byteLength:134217728,downloadUrl:`${legacyOrigin}/preset-library/next/releases/${id}/file`});
  const f=await fixture('https://custom.example.test/preset-library/download/download.js',value,{query:'platform=android&edition=next&channel=beta'});
  assert.match(f.calls[0].url,/packageName=cc.huevia.next$/);assert.match(f.nodes.get('download-button').href,/\/next\/releases\//);
  assert.equal(f.nodes.get('download-label').textContent,'下载 Android 新版');assert.equal(f.nodes.get('signer').hidden,false);
  const mismatched=await fixture('https://custom.example.test/preset-library/download/download.js',value);
  assert.equal(mismatched.nodes.get('release').hidden,true);assert.match(mismatched.nodes.get('empty-copy').textContent,/平台不匹配/);
});

test('iPhone starts on iOS, beta fallback stays on the selected platform and withdrawal never falls back',async()=>{
  const f=await fixture('https://custom.example.test/preset-library/download/download.js',null,{query:'platform=ios',response:url=>url.searchParams.get('channel')==='beta'?{release:iosRelease(),reason:'available'}:{release:null,reason:'no_release'}});
  assert.equal(f.calls.length,2);assert.ok(f.calls.every(call=>call.url.includes('/ios/releases/latest')));assert.equal(f.nodes.get('release').hidden,false);
  assert.match(f.nodes.get('channel-note').textContent,/暂无正式版/);
  const iphone=await fixture('https://custom.example.test/preset-library/download/download.js',iosRelease(),{userAgent:'iPhone'});assert.match(iphone.calls[0].url,/\/ios\//);
  const withdrawn=await fixture('https://custom.example.test/preset-library/download/download.js',null,{query:'platform=ios',response:()=>({release:null,reason:'withdrawn'})});
  assert.equal(withdrawn.calls.length,1);assert.match(withdrawn.nodes.get('empty-title').textContent,/撤回/);
});

test('a late Android response cannot overwrite the iOS selection or its download link',async()=>{
  let resolveAndroid;
  const f=await fixture('https://custom.example.test/preset-library/download/download.js',null,{response:url=>url.pathname.includes('/ios/')?{release:iosRelease(),reason:'available'}:new Promise(resolve=>{resolveAndroid=resolve;})});
  f.click('platform','ios');await new Promise(resolve=>setImmediate(resolve));
  resolveAndroid({release:release(),reason:'available'});await new Promise(resolve=>setImmediate(resolve));
  assert.equal(f.nodes.get('download-label').textContent,'下载 iOS IPA 文件');assert.match(f.nodes.get('download-button').href,/\/ios\/releases\//);
});

for (const origin of [legacyOrigin, 'https://huevia.cc']) {
  test(`${origin}: large APKs render through the server capacity boundary`, async () => {
    for (const byteLength of [4 * 1024 * 1024 + 1, 9478052, MAX_APK_BYTES]) {
      const f = await fixture(origin + '/preset-library/download/download.js', release({
        byteLength, versionCode: 110, versionName: '0.22.1-beta', packageName: 'cc.huevia'
      }));
      assert.equal(f.nodes.get('release').hidden, false, `${byteLength} bytes visible`);
      assert.equal(f.nodes.get('empty').hidden, true);
      assert.equal(f.nodes.get('download-button').href, `${origin}/preset-library/releases/${id}/file`);
      assert.match(f.nodes.get('metadata').textContent, new RegExp(`${(byteLength / 1048576).toFixed(2).replace('.', '\\.')} MiB`));
    }
  });
}

test('download page rejects arbitrary external links, mismatched paths, credentials and invalid release IDs', async () => {
  const f = await fixture('https://custom.example.test/preset-library/download/download.js');
  const base = 'https://custom.example.test/preset-library/';
  const valid = release();
  for (const downloadUrl of [`https://attacker.example.test/preset-library/releases/${id}/file`,
    `https://custom.example.test/preset-library/releases/${id}/file/extra`,
    `${legacyOrigin}/preset-library/releases/12345678-1234-4234-8234-123456789def/file`,
    `${legacyOrigin}/preset-library/releases/${id}/file?token=forged`,
    `${legacyOrigin}/preset-library/releases/${id}/file?`,
    `${legacyOrigin}/preset-library/releases/${id}/file#fragment`,
    `${legacyOrigin}/preset-library/releases/${id}/file#`,
    `${legacyOrigin.replace('https://', 'https://user:secret@')}/preset-library/releases/${id}/file`,
    `http://${new URL(legacyOrigin).host}/preset-library/releases/${id}/file`,
    `/preset-library/releases/${id}/file`, 'javascript:alert(1)', 'https://attacker.example.test/collect']) {
    assert.throws(() => f.helper({ ...valid, downloadUrl }, base), /下载地址校验失败/);
  }
  for (const invalidId of [null, 1, [id], id.toUpperCase(), 'not-a-uuid', id + '/../../auth/logout', id + '?token=1']) {
    assert.throws(() => f.helper({ ...valid, id: invalidId }, base), /下载地址校验失败/);
  }
});

test('download page retains bounded byte lengths, versions and SHA checks and hides failed releases', async () => {
  const f = await fixture('https://custom.example.test/preset-library/download/download.js');
  for (const invalid of [{ sha256: 'bad' }, { signerSha256: 'bad' }, { byteLength: 0 }, { byteLength: -1 },
    { byteLength: MAX_APK_BYTES + 1 }, { byteLength: '3400000' }, { versionCode: -1 }, { versionCode: 1.5 }]) {
    assert.throws(() => f.helper(release(invalid), 'https://custom.example.test/preset-library/'), /版本信息不完整/);
  }
  const invalidPage = await fixture('https://custom.example.test/preset-library/download/download.js',
    release({ downloadUrl: 'https://attacker.example.test/collect' }));
  assert.equal(invalidPage.nodes.get('release').hidden, true);
  assert.equal(invalidPage.nodes.get('empty').hidden, false);
  assert.match(invalidPage.nodes.get('empty-copy').textContent, /下载地址校验失败/);
  assert.equal(invalidPage.nodes.get('download-button')?.href || '', '');
});
