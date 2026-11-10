// Verify only files returned by the COS console's HTTPS object download action.
import { readFile, writeFile, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, basename } from 'node:path';
import { inspectApk } from '../server/apk.mjs';
const folder = new URL('../.local/cos-migration/', import.meta.url);
const { releases } = JSON.parse(await readFile(new URL('inventory-before.json', folder)));
const files = JSON.parse(await readFile(new URL('readback-files.json', folder)));
const rows = [], seen = new Set();
for (const file of files) {
  const row = releases.find(r => r.storage_path === 'app-releases/' + file.name);
  if (!row || seen.has(file.name)) throw Error('Unexpected or duplicate downloaded object.');
  seen.add(file.name);
  const path = resolve(file.path), roots = [resolve('C:/Users/11621/Downloads') + '\\', resolve(new URL('readbacks/', folder).pathname.replace(/^\/(?=[A-Za-z]:)/, '')) + '\\'];
  if (!roots.some(root => path.startsWith(root)) || !basename(path).startsWith(file.name.slice(0, 64))) throw Error('Unexpected download artifact path.');
  if ((await stat(path)).size !== row.byte_length) throw Error('Downloaded size mismatch: ' + row.version_code);
  const bytes = await readFile(path), sha256 = createHash('sha256').update(bytes).digest('hex');
  if (sha256 !== row.sha256) throw Error('Downloaded SHA-256 mismatch: ' + row.version_code);
  const apk = inspectApk(bytes, { packageName: row.package_name });
  if (apk.versionCode !== row.version_code || apk.signerSha256 !== row.signer_sha256) throw Error('Downloaded APK identity mismatch: ' + row.version_code);
  rows.push({ versionCode: row.version_code, path: row.storage_path, bytes: bytes.length, sha256, signerSha256: apk.signerSha256 });
}
const proof = { at: new Date().toISOString(), bucket: 'huevia-updates-1252602548', origin: 'https://download.huevia.cc',
  method: 'COS console custom-origin HTTPS object downloads', count: rows.length, allVerified: rows.length === releases.length, rows };
await writeFile(new URL('target-integrity.json', folder), JSON.stringify(proof, null, 2) + '\n');
await writeFile(new URL('../../docs/validation/cos-migration-20261107/target-integrity.json', import.meta.url), JSON.stringify(proof, null, 2) + '\n');
console.log(JSON.stringify({ verified: rows.length, total: releases.length, allVerified: proof.allVerified, bytes: rows.reduce((s, row) => s + row.bytes, 0) }));
