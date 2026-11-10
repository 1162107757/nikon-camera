import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { CosReleaseStorage, releaseStorageFromEnv, withReleaseCredentials } from '../server/cos-release-storage.mjs';
import { createReleaseRoutes } from '../server/releases.mjs';
import { ReleaseMemoryStore } from './release-memory-store.mjs';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const config = { region: 'ap-shanghai', bucket: 'example-updates-1250000000', prefix: 'huevia-updates/',
  downloadOrigin: 'https://download.huevia.cc', secretId: 'test-secret-id', secretKey: 'synthetic-key-never-used-on-a-service' };
const body = Buffer.from('test-only bounded COS object'), path = 'app-releases/' + digest(body) + '.bin';
function fake() {
  const objects = new Map(), signer = new CosReleaseStorage(config).context().client;
  return { objects, getObjectUrl: signer.getObjectUrl.bind(signer), putObject(params, callback) {
    assert.equal(params.Headers['x-cos-forbid-overwrite'], 'true');
    if (objects.has(params.Key)) return callback({ code: 'FileAlreadyExists', statusCode: 409 });
    objects.set(params.Key, Buffer.from(params.Body)); callback(null, {});
  }, fetchImpl: async url => { const bytes = objects.get(new URL(url).pathname.slice(1)); return new Response(bytes, { status: bytes ? 200 : 404 }); } };
}
test('APK storage switches independently and incomplete COS config fails closed', () => {
  const legacy = {}; assert.equal(releaseStorageFromEnv({}, legacy), legacy);
  assert.throws(() => releaseStorageFromEnv({ APP_RELEASE_STORAGE: 'cos' }, legacy));
  assert.throws(() => releaseStorageFromEnv({ APP_RELEASE_STORAGE: 'unknown' }, legacy));
});
test('COS uploads are content addressed, cannot overwrite, and reads have actual byte bounds', async () => {
  const client = fake(), store = new CosReleaseStorage({ ...config, client, fetchImpl: client.fetchImpl });
  await store.put(path, body); await store.put(path, body); assert.deepEqual(await store.get(path, 1024), body);
  assert.deepEqual([...client.objects.keys()], ['huevia-updates/' + path]);
  await assert.rejects(store.get(path, body.length - 1)); await assert.rejects(store.put(path, Buffer.from('changed')));
  client.objects.set(store.key(path), Buffer.from('different stored bytes')); await assert.rejects(store.put(path, body));
});
test('COS release adapter excludes presets, traversal, unrelated objects and signed upload chunks', async () => {
  const client = fake(), store = new CosReleaseStorage({ ...config, client, fetchImpl: client.fetchImpl });
  for (const invalid of ['preview/' + digest(body) + '.jpg', '../app-releases/' + digest(body) + '.bin', 'https://untrusted.example/file', 'app-releases/nope.apk']) {
    await assert.rejects(store.get(invalid, 1024)); await assert.rejects(store.put(invalid, body)); await assert.rejects(store.signDownload(invalid, 60, 'Huevia-115-beta.apk'));
  }
  const chunk = 'app-upload/af092912-0000-4000-8000-73fb99788888/0-' + digest(body) + '.part';
  await store.put(chunk, body); await assert.rejects(store.signDownload(chunk, 60, 'Huevia-115-beta.apk'));
});
test('official COS SDK signs the exact custom HTTPS origin, response filename, host and sixty second lifetime', async () => {
  const store = new CosReleaseStorage(config), url = new URL(await store.signDownload(path, 60, 'Huevia-115-beta.apk'));
  assert.equal(url.origin, config.downloadOrigin); assert.equal(url.pathname, '/huevia-updates/' + path);
  assert.equal(url.searchParams.get('response-content-disposition'), 'attachment; filename=Huevia-115-beta.apk');
  assert.equal(url.searchParams.get('q-header-list'), 'host'); assert.equal(url.href.includes(config.secretKey), false);
  await assert.rejects(store.signDownload(path, 61, 'Huevia-115-beta.apk')); await assert.rejects(store.signDownload(path, 60, '../bad.apk'));
  for (const change of [u => { u.hostname = 'untrusted.example'; }, u => { u.searchParams.set('extra', 'value'); },
    u => { u.pathname += '.changed'; }, u => { u.searchParams.set('q-sign-time', '1;3600'); }]) {
    const altered = new URL(url); change(altered);
    const alteredStore = new CosReleaseStorage({ ...config, client: { getObjectUrl: (_, callback) => callback(null, { Url: altered.href }) } });
    await assert.rejects(alteredStore.signDownload(path, 60, 'Huevia-115-beta.apk'));
  }
});
test('concurrent SCF requests isolate rotating role credentials and ignore untrusted peers', async () => {
  const store = new CosReleaseStorage({ ...config, secretId: undefined, secretKey: undefined, roleCredentials: true });
  const env = { TENCENTCLOUD_RUNENV: 'SCF', SCF_FUNCTIONNAME: 'fixture' };
  const req = id => ({ socket: { remoteAddress: '127.0.0.1' }, headers: { 'x-scf-name': 'fixture',
    'x-scf-secret-id': id, 'x-scf-secret-key': 'test-key', 'x-scf-session-token': 'test-token' } });
  const results = await Promise.all(['first', 'second'].map(id => withReleaseCredentials(req(id), async () => {
    await new Promise(resolve => setImmediate(resolve)); return new URL(await store.signDownload(path, 60, 'Huevia-115-beta.apk')).searchParams.get('q-ak');
  }, env)));
  assert.deepEqual(results, ['first', 'second']);
  const untrusted = req('forged'); untrusted.socket.remoteAddress = '203.0.113.1';
  await assert.rejects(async () => withReleaseCredentials(untrusted, () => store.signDownload(path, 60, 'Huevia-115-beta.apk'), env));
});
test('small historical COS APKs use verified private downloads and retain withdrawal gates', async () => {
  const client = fake(), storage = new CosReleaseStorage({ ...config, client, fetchImpl: client.fetchImpl });
  await storage.put(path, body);
  const store = new ReleaseMemoryStore(), id = '12345678-1234-4234-8234-123456789abc';
  store.releaseRows.push({ id, status: 'published', sha256: digest(body), byte_length: body.length,
    storage_path: path, version_code: 115, channel: 'beta' });
  const routes = createReleaseRoutes({ store, storage, publicBaseUrl: 'https://fixture.example',
    readBundledApk: () => { throw Error('COS must not read a bundled fallback'); } });
  const req = { method: 'GET', headers: {}, socket: { remoteAddress: '127.0.0.1' } };
  const headers = {}; const res = { setHeader: (key, value) => { headers[key] = value; },
    writeHead: (status, values) => { res.status = status; Object.assign(headers, values); }, end() {} };
  const relative = '/releases/' + id + '/file';
  assert.equal(await routes.publicRoute(req, res, { path: relative, url: new URL('https://fixture.example' + relative) }), true);
  assert.equal(res.status, 307); assert.equal(new URL(headers.Location).origin, config.downloadOrigin);
  assert.equal(headers['X-Content-SHA256'], digest(body));
  store.releaseRows[0].status = 'withdrawn';
  await assert.rejects(routes.publicRoute(req, res, { path: relative, url: new URL('https://fixture.example' + relative) }), error => error.status === 404);
});
