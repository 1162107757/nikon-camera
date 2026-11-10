// Stage existing releases only. Never creates, publishes or changes a release.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { CloudBaseStore, CloudBaseStorage } from '../server/cloudbase.mjs';
import { inspectApk } from '../server/apk.mjs';
const folder = new URL('../.local/cos-migration/', import.meta.url);
const { releases } = JSON.parse(await readFile(new URL('inventory-before.json', folder)));
const credential = JSON.parse(await readFile(new URL('../.local/service-credential.json', import.meta.url)));
const source = new CloudBaseStorage(new CloudBaseStore(credential));
const objects = new URL('objects/', folder); await mkdir(objects, { recursive: true });
const report = [];
for (const row of releases) {
  let bytes, from = 'cloudbase';
  try { bytes = await source.get(row.storage_path, row.byte_length); }
  catch {
    from = 'production-bundle';
    try { bytes = await readFile(new URL('bundled/' + row.sha256 + '.apk', folder)); }
    catch { report.push({ versionCode: row.version_code, ok: false, reason: 'SOURCE_UNAVAILABLE' }); continue; }
  }
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  if (bytes.length !== row.byte_length || sha256 !== row.sha256) throw Error('Source integrity mismatch: ' + row.version_code);
  const apk = inspectApk(bytes, { packageName: row.package_name });
  if (apk.versionCode !== row.version_code || apk.versionName !== row.version_name || apk.signerSha256 !== row.signer_sha256) throw Error('APK identity mismatch: ' + row.version_code);
  await writeFile(new URL(row.storage_path.split('/')[1], objects), bytes);
  report.push({ versionCode: row.version_code, path: row.storage_path, bytes: bytes.length, sha256, from, ok: true });
  console.log(JSON.stringify({ staged: row.version_code, bytes: bytes.length, source: from }));
}
await writeFile(new URL('staged-apks.json', folder), JSON.stringify(report, null, 2));
console.log(JSON.stringify({ staged: report.filter(x => x.ok).length, missing: report.filter(x => !x.ok).map(x => x.versionCode), total: report.length }));
if (report.some(x => !x.ok)) process.exitCode = 1;
