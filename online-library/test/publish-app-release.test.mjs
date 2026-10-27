import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { createContext, SourceTextModule, SyntheticModule } from 'node:vm';

const source = await readFile(new URL('../scripts/publish-app-release.mjs', import.meta.url), 'utf8');
const origin = 'https://release-fixture.example.test';
const apk = Buffer.from('Synthetic signed-artifact bytes; APK inspection is an explicit test facade.');
const sha256 = createHash('sha256').update(apk).digest('hex');

// Execute the actual helper with an already-published synthetic artifact. Every
// file and request is intercepted: no credentials, filesystem writes or network.
async function fixture(packageName, { foreignMetadata = false, mandatory = false, flags = [], initialStatus = 'published', policyMetadataMismatch = false } = {}) {
  const calls = [], writes = [], logs = [];
  const metadata = { packageName, versionName: 'fixture-beta', versionCode: 77, sha256 };
  const release = { id: 'fixture', packageName, versionCode: 77, sha256, status: initialStatus, mandatory, revision: 2,
    downloadUrl: `${origin}/preset-library/releases/fixture/file` };
  const context = createContext({ Buffer, URL, process: { argv: ['node', 'publish-app-release.mjs', 'fixture.apk',
    '--publish', '--notes-file', 'release-notes.txt', ...flags] }, console: { log: value => logs.push(String(value)) },
    fetch: async (input, options = {}) => {
      const url = new URL(input); calls.push({ url, method: options.method || 'GET', body: options.body && JSON.parse(options.body) });
      if (url.pathname === '/preset-library/api/releases') return { ok: true, json: async () => ({ items: [release] }) };
      if (url.pathname === '/preset-library/api/releases/fixture/policy') {
        const body=JSON.parse(options.body);assert.equal(options.method,'PUT');assert.equal(body.expectedRevision,release.revision);
        assert.equal(body.confirmation,`${body.mandatory?'REQUIRE':'OPTIONAL'} 77 ${sha256}`);
        release.mandatory=body.mandatory;release.revision++;return {ok:true,json:async()=>({release:{...release}})};
      }
      if (url.pathname === '/preset-library/api/releases/fixture/publish') {
        const body=JSON.parse(options.body);assert.equal(options.method,'POST');assert.equal(body.expectedRevision,release.revision);
        assert.equal(body.confirmation,`PUBLISH 77 ${sha256}`);release.status='published';release.revision++;return {ok:true,json:async()=>({release:{...release}})};
      }
      if (url.href === release.downloadUrl) return { ok: true,
        arrayBuffer: async () => apk.buffer.slice(apk.byteOffset, apk.byteOffset + apk.length) };
      if (url.pathname === '/preset-library/releases/latest') {
        const requested = url.searchParams.get('packageName') ?? 'com.nikonpreset.usbprobe';
        if (requested !== packageName) return { ok: true, json: async () => ({ updateAvailable: false, release: null }) };
        return { ok: true, json: async () => ({ updateAvailable: true, updateRequired: policyMetadataMismatch?!release.mandatory:release.mandatory,
          release: { ...release, packageName: foreignMetadata ? 'another.application' : packageName } }) };
      }
      throw new Error('Unexpected synthetic request: ' + url.pathname);
    } });
  const modules = {
    'node:fs/promises': { readFile: async input => {
      const path = String(input);
      if (path === 'fixture.apk') return apk;
      if (path === 'release-notes.txt') return 'Synthetic notes';
      if (path.endsWith('/community-admin-session.json')) return JSON.stringify({ cookie: 'synthetic=test', csrfToken: 'fixture' });
      if (path.endsWith('/app-release-publication-77.json')) throw new Error('Synthetic state is initially absent');
      throw new Error('Unexpected synthetic file read');
    }, writeFile: async (input, value, options) => writes.push({ path: String(input), state: JSON.parse(value), mode: options?.mode }) },
    'node:crypto': { createHash }, '../server/apk.mjs': { inspectApk: input => {
      assert.ok(Buffer.from(input).equals(apk)); return metadata;
    } }, './cloud-tools.mjs': { PUBLIC_ORIGIN: origin }
  };
  const module = new SourceTextModule(source, { context,
    initializeImportMeta(meta) { meta.url = 'file:///synthetic-online-library/scripts/publish-app-release.mjs'; } });
  await module.link(specifier => {
    const exports = modules[specifier];
    if (!exports) throw new Error('Unexpected helper dependency: ' + specifier);
    return new SyntheticModule(Object.keys(exports), function () {
      for (const [key, value] of Object.entries(exports)) this.setExport(key, value);
    }, { context });
  });
  let error;
  try { await module.evaluate(); } catch (failure) { error = failure; }
  return { calls, writes, logs, error };
}

for (const packageName of ['cc.huevia', 'com.nikonpreset.usbprobe']) {
  test(`publication helper verifies the same ${packageName} namespace as the signed artifact`, async () => {
    const result = await fixture(packageName);
    assert.equal(result.error, undefined);
    const query = result.calls.find(call => call.url.pathname.endsWith('/releases/latest')).url.searchParams;
    assert.equal(query.get('packageName'), packageName);
    assert.equal(query.get('channel'), 'beta');
    assert.equal(query.get('sdk'), '35');
    assert.ok(result.calls.every(call => call.method === 'GET'), 'Already-published verification does not issue another publication');
    assert.equal(result.writes.at(-1).state.packageName, packageName);
    assert.equal(result.writes.at(-1).state.publicBytesVerified, true);
    assert.equal(result.writes.at(-1).mode, 0o600);
    const output = JSON.parse(result.logs.at(-1));
    assert.equal(output.packageName, packageName);
    assert.equal(output.published, true);
    assert.equal(output.sha256, sha256);
  });
}

test('publication helper refuses a foreign namespace in returned public metadata', async () => {
  const result = await fixture('cc.huevia', { foreignMetadata: true });
  assert.match(String(result.error?.message), /Published update metadata mismatch/);
  assert.ok(result.writes.every(write => write.state.publicBytesVerified !== true));
  assert.equal(result.logs.length, 0, 'Mismatched public metadata is never announced as verified publication');
});

test('publication helper preserves a reviewed mandatory policy when no flag is supplied',async()=>{
  const result=await fixture('cc.huevia',{mandatory:true});assert.equal(result.error,undefined);
  assert.ok(result.calls.every(call=>call.method==='GET'));assert.equal(JSON.parse(result.logs.at(-1)).mandatory,true);
});

for(const [mandatory,flag] of [[true,'--mandatory'],[false,'--optional']]){
  test(`publication helper ${flag} explicitly updates policy before publishing a draft`,async()=>{
    const result=await fixture('cc.huevia',{mandatory:!mandatory,flags:[flag],initialStatus:'draft'});assert.equal(result.error,undefined);
    const mutations=result.calls.filter(call=>call.method!=='GET');assert.deepEqual(mutations.map(call=>call.url.pathname.split('/').at(-1)),['policy','publish']);
    assert.equal(mutations[0].body.mandatory,mandatory);assert.equal(mutations[1].body.expectedRevision,3);assert.equal(JSON.parse(result.logs.at(-1)).mandatory,mandatory);
  });
}

test('publication helper refuses conflicting flags and mismatched public policy',async()=>{
  const conflict=await fixture('cc.huevia',{flags:['--mandatory','--optional']});assert.match(conflict.error?.message,/Usage:/);assert.equal(conflict.calls.length,0);assert.equal(conflict.writes.length,0);
  const mismatch=await fixture('cc.huevia',{flags:['--mandatory'],policyMetadataMismatch:true});assert.match(mismatch.error?.message,/Published update policy mismatch/);assert.equal(mismatch.logs.length,0);assert.ok(mismatch.writes.every(write=>write.state.publicBytesVerified!==true));
});
