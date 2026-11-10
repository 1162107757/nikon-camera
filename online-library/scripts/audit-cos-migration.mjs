// Read-only inventory and exact production backup. Contains no credential output.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { CloudBaseStore } from '../server/cloudbase.mjs';
import { cloudApi, ENV_ID, FUNCTION_NAME } from './cloud-tools.mjs';
const folder = new URL('../.local/cos-migration/', import.meta.url); await mkdir(folder, { recursive: true });
const credential = JSON.parse(await readFile(new URL('../.local/service-credential.json', import.meta.url)));
const store = new CloudBaseStore(credential);
const releases = await store.rest('nikon_app_releases?select=*&order=version_code.asc&limit=1000');
const activeUploads = await store.rest('nikon_app_uploads?select=*&status=neq.complete&expires_at=gt.' + encodeURIComponent(new Date().toISOString()) + '&limit=1000');
const fn = cloudApi('scf', 'GetFunction', { Namespace: ENV_ID, FunctionName: FUNCTION_NAME, ShowCode: 'FALSE' });
if (fn.Status !== 'Active') throw Error('Production function is not Active.');
const address = cloudApi('scf', 'GetFunctionAddress', { Namespace: ENV_ID, FunctionName: FUNCTION_NAME });
const url = new URL(address.Url);
if (url.protocol !== 'https:' || !/(?:\.myqcloud\.com|\.tencentcos\.cn)$/.test(url.hostname)) throw Error('Unexpected code archive origin.');
const response = await fetch(url, { redirect: 'error', signal: AbortSignal.timeout(60000) });
if (!response.ok) throw Error('Code archive backup failed.');
const archive = Buffer.from(await response.arrayBuffer());
if (archive.length > 256 * 1024 * 1024) throw Error('Unexpected code archive size.');
await writeFile(new URL('before.zip', folder), archive);
await writeFile(new URL('function-before.json', folder), JSON.stringify(fn));
await writeFile(new URL('inventory-before.json', folder), JSON.stringify({ releases, activeUploads }, null, 2));
const summary = { releases: releases.map(r => ({ id: r.id, versionCode: r.version_code, bytes: r.byte_length, sha256: r.sha256, status: r.status, storagePath: r.storage_path })),
  activeUploads: activeUploads.length, archiveBytes: archive.length, archiveSha256: createHash('sha256').update(archive).digest('hex'), role: fn.Role, checkedAt: new Date().toISOString() };
await writeFile(new URL('audit-summary.json', folder), JSON.stringify(summary, null, 2));
console.log(JSON.stringify(summary));
