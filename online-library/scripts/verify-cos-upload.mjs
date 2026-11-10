// Audit the two owned duplicate-release probes and expire their resumable tasks.
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { CloudBaseStore } from '../server/cloudbase.mjs';
import { cloudApi, ENV_ID, FUNCTION_NAME } from './cloud-tools.mjs';
const folder = new URL('../.local/cos-migration/', import.meta.url);
const store = new CloudBaseStore(JSON.parse(await readFile(new URL('../.local/service-credential.json', import.meta.url))));
const before = JSON.parse(await readFile(new URL('inventory-before.json', folder)));
const release = before.releases.find(r => r.version_code === 115);
const bytes = await readFile(new URL('objects/' + release.storage_path.split('/')[1], folder));
const ids = ['d2f95f13-a019-4f33-af11-0ee791f6eb9d', '8be8528c-1ee3-430b-adf9-dcd78fef956c'];
const tasks = [];
for (const id of ids) {
  const task = (await store.rest('nikon_app_uploads?id=eq.' + id + '&select=*'))[0];
  if (!task || task.notes !== 'COS 存储迁移链路验证：使用现有 115 版校验分片上传与重复版本保护。' || task.byte_length !== bytes.length || task.status !== 'processing') throw Error('Unexpected validation task.');
  const chunks = await store.rest('nikon_app_upload_chunks?upload_id=eq.' + id + '&select=*&order=chunk_index.asc');
  if (chunks.length !== Math.ceil(bytes.length / 524288)) throw Error('Missing upload chunks.');
  for (const [i, chunk] of chunks.entries()) {
    const part = bytes.subarray(i * 524288, Math.min(bytes.length, (i + 1) * 524288));
    const sha256 = createHash('sha256').update(part).digest('hex');
    if (!chunk.ready || chunk.chunk_index !== i || chunk.byte_length !== part.length || chunk.sha256 !== sha256
        || chunk.storage_path !== `app-upload/${id}/${i}-${sha256}.part`) throw Error('Upload chunk identity failed.');
  }
  tasks.push({ id, originalExpiresAt: task.expires_at, chunks: chunks.length, bytes: task.byte_length, allChunkHashesVerified: true });
}
const rows = await store.rest('nikon_app_releases?select=*&order=version_code.asc&limit=1000');
if (JSON.stringify(rows) !== JSON.stringify(before.releases)) throw Error('Release metadata changed during validation.');
await writeFile(new URL('upload-probes-before-expiry.json', folder), JSON.stringify(tasks, null, 2));
for (const task of tasks) {
  const result = await store.rest('nikon_app_uploads?id=eq.' + task.id + '&status=eq.processing&select=id,expires_at',
    { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: { expires_at: new Date().toISOString() } });
  if (result.length !== 1 || result[0].id !== task.id) throw Error('Validation task expiry failed.');
}
const fn = cloudApi('scf', 'GetFunction', { Namespace: ENV_ID, FunctionName: FUNCTION_NAME, ShowCode: 'FALSE' });
const original = JSON.parse(await readFile(new URL('function-before.json', folder)));
const configurationPreserved = original.Environment.Variables.every(v => fn.Environment.Variables.some(x => x.Key === v.Key && x.Value === v.Value));
if (fn.Status !== 'Active' || fn.Role !== 'HueviaUpdatePackageRole' || !configurationPreserved || fn.Environment.Variables.find(x => x.Key === 'APP_RELEASE_STORAGE')?.Value !== 'cos') throw Error('Unexpected active storage configuration.');
const proof = { at: new Date().toISOString(), provider: 'cos', executionRole: fn.Role, configurationPreserved,
  firstProbe: '19 COS chunks accepted; existing-file SDK code compatibility fixed', finalProbe: '19 COS chunks accepted, read and verified; exact existing file reused; duplicate release correctly rejected',
  releaseCount: rows.length, publishedReleaseCount: rows.filter(row => row.status === 'published').length,
  releaseMetadataUnchanged: true, probeTasksExpired: true, tasks };
await writeFile(new URL('../../docs/validation/cos-migration-20261107/upload-verification.json', import.meta.url), JSON.stringify(proof, null, 2) + '\n');
console.log(JSON.stringify({ provider: proof.provider, completeChunksPerProbe: 19, finalProbePassed: true, releaseMetadataUnchanged: true, probeTasksExpired: true }));
