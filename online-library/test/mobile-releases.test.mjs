import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { inspectIpa } from '../server/ipa.mjs';
import { inspectApk, APK_SIGNER_SHA256, NEXT_APK_SIGNER_SHA256, APK_SIGNERS } from '../server/apk.mjs';
import { createHandler } from '../server/app.mjs';
import { hashPassword } from '../server/auth.mjs';
import { ReleaseMemoryStore } from './release-memory-store.mjs';
import { ipaFixture, zipFixture, digest } from './mobile-release-fixture.mjs';
let PGlite;
try { ({ PGlite } = await import('../../.community-pg-test/node_modules/@electric-sql/pglite/dist/index.js')); } catch {}

test('IPA parser accepts bounded unsigned device identity and rejects wrong platforms, signatures and paths', () => {
  const bytes = ipaFixture(), metadata = inspectIpa(bytes);
  assert.equal(metadata.bundleId, 'cc.huevia.next');assert.equal(metadata.versionCode, 213);assert.equal(metadata.sha256, digest(bytes));assert.equal(metadata.distribution, 'unsigned-ipa');
  for (const fixture of [ipaFixture({ platform: 7 }), ipaFixture({ bundleId: 'another.app' }), ipaFixture({ signed: true }), ipaFixture({ version: '213.5' }), ipaFixture({ extra: { '../escape': 'unsafe' } }), zipFixture({ 'Payload/Fake.app/Info.plist': 'not a plist' })]) assert.throws(() => inspectIpa(fixture), { code: 'INVALID_IPA' });
  const changed = Buffer.from(bytes);changed[60] ^= 1;assert.throws(() => inspectIpa(changed), { code: 'INVALID_IPA' });
});

let nextApk, oldApk;
try { nextApk = await readFile(new URL('../../dist/migration212/huevia-0.31.0-dev-212-android-arm64.apk', import.meta.url)); } catch {}
try { oldApk = await readFile(new URL('../../dist/nikon-usb-0.9.14-beta-debug.apk', import.meta.url)); } catch {}
if (!oldApk) try { oldApk = await readFile(new URL('../../dist/huevia-0.25.0-beta-debug.apk', import.meta.url)); } catch {}
test('actual 212 APK has its own pinned signer; old and new package signers cannot cross', { skip: !nextApk || !oldApk }, () => {
  const next = inspectApk(nextApk, { packageName: 'cc.huevia.next' }), old = inspectApk(oldApk);
  assert.equal(next.packageName, 'cc.huevia.next');assert.equal(next.versionCode, 212);assert.equal(next.signerSha256, NEXT_APK_SIGNER_SHA256);assert.equal(next.byteLength, 51309171);
  assert.equal(old.signerSha256, APK_SIGNER_SHA256);assert.equal(APK_SIGNERS['cc.huevia'], APK_SIGNER_SHA256);assert.equal(APK_SIGNERS['com.nikonpreset.usbprobe'], APK_SIGNER_SHA256);
  assert.throws(() => inspectApk(nextApk), /32 MiB/);
  assert.throws(() => inspectApk(nextApk, { packageName: 'cc.huevia.next', signerSha256: APK_SIGNER_SHA256 }), { code: 'INVALID_APK' });
  assert.throws(() => inspectApk(oldApk, { signerSha256: NEXT_APK_SIGNER_SHA256 }), { code: 'INVALID_APK' });
  assert.throws(() => inspectApk(nextApk, { packageName: 'cc.huevia' }), { code: 'INVALID_APK' });
  assert.throws(() => inspectApk(oldApk, { packageName: 'cc.huevia.next' }), { code: 'INVALID_APK' });
  const changed = Buffer.from(nextApk);changed[500] ^= 1;assert.throws(() => inspectApk(changed), { code: 'INVALID_APK' });
});

class SqlStore extends ReleaseMemoryStore {
  constructor(db) { super();this.db = db;this.blockDownloads = false; }
  async rpc(name, body) {
    if (name === 'nikon_mobile_release_manage') return (await this.db.query('SELECT nikon_mobile_release_manage($1,$2,$3) AS value', [body.p_actor, body.p_action, body.p_body])).rows[0].value;
    if (name === 'nikon_mobile_release_budget') {
      if (this.blockDownloads) return { error: 'BUDGET' };
      return (await this.db.query('SELECT nikon_mobile_release_budget($1,$2,$3) AS value', [body.p_key, body.p_kind, body.p_bytes])).rows[0].value;
    }
    return super.rpc(name, body);
  }
  async rest(path) {
    if (!path.startsWith('nikon_mobile_releases?')) return super.rest(path);
    const parameters = new URL(path, 'https://test.invalid').searchParams, where = [], values = [];
    for (const key of ['id', 'platform', 'package_name', 'channel']) if (parameters.has(key)) { values.push(parameters.get(key).slice(3));where.push(`${key}=$${values.length}`); }
    if (parameters.has('status')) where.push("status IN ('published','withdrawn')");
    return (await this.db.query(`SELECT * FROM nikon_mobile_releases${where.length ? ' WHERE ' + where.join(' AND ') : ''} ORDER BY version_code DESC LIMIT ${parameters.get('limit') === '1' ? 1 : 200}`, values)).rows;
  }
}
test('real SQL + HTTP performs admin/CSRF, resumable chunks, draft review, same-domain manifest, integrity and withdrawal', { skip: !PGlite }, async t => {
  const db = new PGlite();t.after(() => db.close());
  await db.exec("CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role BYPASSRLS;CREATE TABLE nikon_admins(username text PRIMARY KEY,disabled boolean NOT NULL DEFAULT false);INSERT INTO nikon_admins VALUES('admin',false);CREATE FUNCTION nikon_app_admin_allowed(p_actor text) RETURNS boolean LANGUAGE sql AS $$SELECT EXISTS(SELECT 1 FROM nikon_admins WHERE username=p_actor AND NOT disabled)$$;");
  const sql = await readFile(new URL('../database/022-mobile-releases.sql', import.meta.url), 'utf8');await db.exec(sql);
  const store = new SqlStore(db), objects = new Map(), password = 'Synthetic-mobile-release-test-password';
  store.admins.set('admin', { username: 'admin', password_hash: await hashPassword(password) });
  let withdrawDuringRead = false, mutableId;
  const storage = { provider: 'cos', put: async (path, bytes) => objects.set(path, Buffer.from(bytes)), get: async path => objects.get(path),
    verify: async (path, length, sha) => { if (withdrawDuringRead && mutableId) await db.query("UPDATE nikon_mobile_releases SET status='withdrawn' WHERE id=$1", [mutableId]);const bytes = objects.get(path);return !!bytes && bytes.length === length && digest(bytes) === sha; },
    signDownload: async path => 'https://download.huevia.cc/huevia-updates/' + path + '?short-lived-test-signature=fixture' };
  const server = createServer();await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));t.after(() => { server.closeAllConnections();server.close(); });
  const origin = `http://127.0.0.1:${server.address().port}`;server.on('request', createHandler({ store, storage, releaseStorage: storage, environmentId: 'test-only', publicBaseUrl: origin, secureCookies: false }));
  let cookie = '', csrf = '';
  const request = (path, { method = 'GET', body, raw = false, headers = {} } = {}) => fetch(origin + '/preset-library' + path, { method, redirect: 'manual', headers: { Cookie: cookie, ...(method !== 'GET' ? { Origin: origin, 'X-CSRF-Token': csrf, 'Content-Type': raw ? 'application/octet-stream' : 'application/json' } : {}), ...headers }, body: body === undefined ? undefined : raw ? body : JSON.stringify(body) });
  assert.equal((await request('/api/ios/releases')).status, 401);
  let response = await request('/api/login', { method: 'POST', body: { username: 'admin', password } });assert.equal(response.status, 200);cookie = response.headers.get('set-cookie').split(';')[0];csrf = (await response.json()).csrfToken;
  const bytes = ipaFixture();
  assert.equal((await request('/api/ios/releases/uploads', { method: 'POST', body: { byteLength: bytes.length, channel: 'beta', notes: '实际 IPA 发布说明' }, headers: { 'X-CSRF-Token': 'wrong' } })).status, 403);
  response = await request('/api/ios/releases/uploads', { method: 'POST', body: { byteLength: bytes.length, channel: 'beta', notes: '实际 IPA 发布说明' } });assert.equal(response.status, 201);const upload = await response.json();
  const chunkPath = `/api/ios/releases/uploads/${upload.uploadId}/chunks/0`;
  assert.equal((await request(`/api/ios/releases/uploads/${upload.uploadId}/complete`, { method: 'POST', body: {} })).status, 409);
  assert.equal((await request(chunkPath, { method: 'PUT', raw: true, body: bytes })).status, 200);
  assert.equal((await request(chunkPath, { method: 'PUT', raw: true, body: bytes })).status, 200, 'same verified chunk can resume idempotently');
  const changed = Buffer.from(bytes);changed[10] ^= 1;assert.equal((await request(chunkPath, { method: 'PUT', raw: true, body: changed })).status, 409);
  response = await request(`/api/ios/releases/uploads/${upload.uploadId}/complete`, { method: 'POST', body: {} });assert.equal(response.status, 201);let release = (await response.json()).release;mutableId = release.id;
  assert.equal(release.status, 'draft');assert.equal(release.sha256, digest(bytes));assert.equal(release.bundleId, 'cc.huevia.next');
  assert.equal((await request(`/ios/releases/${release.id}/file`)).status, 404);
  let latest = await (await request('/ios/releases/latest?bundleId=cc.huevia.next&channel=beta&versionCode=212')).json();assert.equal(latest.release, null);
  const action = (verb, confirmation, revision = release.revision) => request(`/api/ios/releases/${release.id}/${verb}`, { method: 'POST', body: { expectedRevision: revision, confirmation } });
  assert.equal((await action('publish', 'yes')).status, 400);
  response = await action('publish', `PUBLISH 213 ${release.sha256}`);assert.equal(response.status, 200);release = (await response.json()).release;
  latest = await (await request('/ios/releases/latest?bundleId=cc.huevia.next&channel=beta&versionCode=212')).json();assert.equal(latest.updateAvailable, true);assert.equal(new URL(latest.release.downloadUrl).origin, origin);
  response = await request(`/ios/releases/${release.id}/file`);assert.equal(response.status, 307);assert.match(response.headers.get('location'), /^https:\/\/download[.]huevia[.]cc\/huevia-updates\/mobile-releases\/ios\//);
  const etag = response.headers.get('etag');assert.equal((await request(`/ios/releases/${release.id}/file`, { headers: { 'If-None-Match': etag } })).status, 304);
  const saved = objects.get(`mobile-releases/ios/${release.sha256}.bin`);objects.set(`mobile-releases/ios/${release.sha256}.bin`, Buffer.from('corrupt'));assert.equal((await request(`/ios/releases/${release.id}/file`)).status, 503);objects.set(`mobile-releases/ios/${release.sha256}.bin`, saved);
  store.blockDownloads = true;assert.equal((await request('/ios/releases/latest')).status, 429);store.blockDownloads = false;
  assert.equal((await action('withdraw', `WITHDRAW 213 ${release.sha256}`, 1)).status, 409);
  assert.equal((await action('withdraw', `WITHDRAW 213 ${release.sha256}`)).status, 200);
  latest = await (await request('/ios/releases/latest?channel=beta')).json();assert.equal(latest.reason, 'withdrawn');assert.equal(latest.release, null);assert.equal((await request(`/ios/releases/${release.id}/file`, { headers: { 'If-None-Match': etag } })).status, 404);
  const audit = (await db.query('SELECT action FROM nikon_mobile_release_audit ORDER BY id')).rows;assert.deepEqual(audit.map(row => row.action), ['upload_verified', 'publish', 'withdraw']);
  await db.exec(sql);assert.equal((await db.query('SELECT count(*)::integer AS n FROM nikon_mobile_releases')).rows[0].n, 1, 'migration is repeatable and does not republish');
  await db.exec('SET ROLE anon');await assert.rejects(db.query('SELECT * FROM nikon_mobile_releases'));await db.exec('RESET ROLE');
  await db.exec('SET ROLE anon');await assert.rejects(db.query("SELECT nikon_mobile_release_manage('admin','begin','{}')"));await db.exec('RESET ROLE');
  // A forged APK row cannot substitute the legacy certificate for the new package.
  const forged = { packageName: 'cc.huevia.next', versionCode: 999, byteLength: 2048,
    sha256: 'a'.repeat(64), signerSha256: APK_SIGNER_SHA256 };
  await assert.rejects(db.query("INSERT INTO nikon_mobile_releases(platform,package_name,version_code,sha256,byte_length,metadata,storage_path,channel,notes) VALUES('android','cc.huevia.next',999,$1,2048,$2,$3,'beta','forged')", [forged.sha256, forged, `mobile-releases/android/${forged.sha256}.bin`]));
  const second = ipaFixture({ version: '214' });
  response = await request('/api/ios/releases/uploads', { method: 'POST', body: { byteLength: second.length, channel: 'beta', notes: '第二个实际流程夹具' } });const secondUpload = await response.json();
  assert.equal((await request(`/api/ios/releases/uploads/${secondUpload.uploadId}/chunks/0`, { method: 'PUT', raw: true, body: second })).status, 200);
  response = await request(`/api/ios/releases/uploads/${secondUpload.uploadId}/complete`, { method: 'POST', body: {} });release = (await response.json()).release;mutableId = release.id;
  response = await action('publish', `PUBLISH 214 ${release.sha256}`);release = (await response.json()).release;
  withdrawDuringRead = true;assert.equal((await request(`/ios/releases/${release.id}/file`)).status, 404, 'withdrawal during remote verification prevents a new signed download');
  // Legacy version routes do not query the new table or change their existing public contract.
  assert.equal((await (await request('/releases/latest?packageName=cc.huevia')).json()).schemaVersion, 1);
  if (nextApk) {
    const metadata = inspectApk(nextApk, { packageName: 'cc.huevia.next' }), key = `mobile-releases/android/${metadata.sha256}.bin`;
    await db.query("INSERT INTO nikon_mobile_releases(platform,package_name,version_code,sha256,byte_length,metadata,storage_path,channel,notes,status) VALUES('android','cc.huevia.next',$1,$2,$3,$4,$5,'beta','actual APK fixture','published')", [metadata.versionCode, metadata.sha256, metadata.byteLength, metadata, key]);
    const matching = await (await request('/releases/latest?packageName=cc.huevia.next&channel=beta&versionCode=211&sdk=35&abi=arm64-v8a')).json();
    assert.equal(matching.updateAvailable, true);assert.deepEqual(matching.release.abis, ['arm64-v8a']);assert.match(matching.release.downloadUrl, /\/next\/releases\//);
    const incompatible = await (await request('/releases/latest?packageName=cc.huevia.next&channel=beta&versionCode=211&sdk=35&abi=x86_64')).json();
    assert.equal(incompatible.reason, 'incompatible');assert.equal(incompatible.updateAvailable, false);
  }
});
