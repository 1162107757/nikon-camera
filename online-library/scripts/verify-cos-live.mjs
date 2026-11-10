import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { inspectApk } from '../server/apk.mjs';
import { PUBLIC_ORIGIN } from './cloud-tools.mjs';
const cos = process.argv.includes('--cos'), base = PUBLIC_ORIGIN + '/preset-library';
const { releases } = JSON.parse(await readFile(new URL('../.local/cos-migration/inventory-before.json', import.meta.url)));
const expected = releases.find(r => r.version_code === 115), withdrawn = releases.find(r => r.status === 'withdrawn');
const checks = [];
for (const [name, url] of [['home', 'https://huevia.cc/'], ['admin', 'https://admin.huevia.cc/preset-library/admin/'],
  ['health', base + '/health'], ['presets', base + '/catalog.json']]) {
  const response = await fetch(url, { redirect: 'error', signal: AbortSignal.timeout(30000) });
  checks.push({ name, status: response.status }); await response.body?.cancel();
  if (response.status !== 200) throw Error('Public route failed: ' + name);
}
const metaResponse = await fetch(base + '/releases/latest?channel=beta&packageName=cc.huevia', { signal: AbortSignal.timeout(30000) });
const meta = await metaResponse.json(), row = meta.release;
if (metaResponse.status !== 200 || row?.id !== expected.id || row.sha256 !== expected.sha256 || row.byteLength !== expected.byte_length
    || row.revision !== expected.revision || row.mandatory !== expected.mandatory || row.downloadUrl !== base + '/releases/' + expected.id + '/file') throw Error('Published release metadata changed.');
checks.push({ name: 'published-beta-identity', versionCode: row.versionCode, revision: row.revision, mandatory: row.mandatory });
const response = await fetch(row.downloadUrl, { redirect: 'manual', signal: AbortSignal.timeout(45000) });
if (response.status !== 307 || response.headers.get('x-content-sha256') !== row.sha256) throw Error('Update redirect failed.');
const location = new URL(response.headers.get('location'));
await response.body?.cancel();
if (location.protocol !== 'https:' || (cos ? location.hostname !== 'download.huevia.cc' : !location.hostname.endsWith('.api.tcloudbasegateway.com'))) throw Error('Unexpected package storage provider.');
if (cos) {
  const time = location.searchParams.get('q-sign-time')?.split(';').map(Number);
  if (time?.length !== 2 || time[1] - time[0] !== 60 || location.searchParams.get('q-header-list') !== 'host') throw Error('Unexpected COS signature lifetime.');
}
const file = await fetch(location, { redirect: 'error', signal: AbortSignal.timeout(45000) });
if (file.status !== 200) throw Error('Final package download failed.');
const bytes = Buffer.from(await file.arrayBuffer()), sha256 = createHash('sha256').update(bytes).digest('hex');
if (bytes.length !== row.byteLength || sha256 !== row.sha256) throw Error('Downloaded bytes changed.');
const apk = inspectApk(bytes, { packageName: row.packageName });
if (apk.versionCode !== row.versionCode || apk.signerSha256 !== row.signerSha256) throw Error('Downloaded APK identity failed.');
checks.push({ name: 'full-package-download', provider: cos ? 'cos' : 'cloudbase', status: file.status, bytes: bytes.length, sha256, signerSha256: apk.signerSha256 });
const denied = await fetch(base + '/releases/' + withdrawn.id + '/file', { redirect: 'manual', headers: { 'If-None-Match': '"sha256-' + withdrawn.sha256 + '"' }, signal: AbortSignal.timeout(30000) });
if (denied.status !== 404 || denied.headers.has('location')) throw Error('Withdrawn package gate failed.'); await denied.body?.cancel();
checks.push({ name: 'withdrawn-package-with-etag', status: denied.status });
const proof = { at: new Date().toISOString(), allPassed: true, checks };
await writeFile(new URL('../../docs/validation/cos-migration-20261107/' + (cos ? 'live-cos' : 'live-compatible') + '.json', import.meta.url), JSON.stringify(proof, null, 2) + '\n');
console.log(JSON.stringify({ checks: checks.length, allPassed: true, provider: cos ? 'cos' : 'cloudbase', versionCode: row.versionCode }));
