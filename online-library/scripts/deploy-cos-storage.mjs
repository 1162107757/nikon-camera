// Publish only the production overlay; activate COS only after the target-byte audit.
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { cloudApi, ENV_ID, FUNCTION_NAME } from './cloud-tools.mjs';
import { CloudBaseStore } from '../server/cloudbase.mjs';
const folder = new URL('../.local/cos-migration/', import.meta.url);
const before = JSON.parse(await readFile(new URL('function-before.json', folder)));
const inventory = JSON.parse(await readFile(new URL('inventory-before.json', folder)));
const credential = JSON.parse(await readFile(new URL('../.local/service-credential.json', import.meta.url)));
const store = new CloudBaseStore(credential);
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
async function ready() {
  for (let i = 0; i < 24; i++) {
    const value = cloudApi('scf', 'GetFunction', { Namespace: ENV_ID, FunctionName: FUNCTION_NAME, ShowCode: 'FALSE' });
    if (value.Status === 'Active') return value;
    if (!['Updating', 'Publishing', 'Creating'].includes(value.Status)) throw Error('Unexpected function state.');
    await new Promise(resolve => setTimeout(resolve, 2500));
  }
  throw Error('Function update remains pending; inspect before retry.');
}
async function unchangedInventory() {
  const rows = await store.rest('nikon_app_releases?select=*&order=version_code.asc&limit=1000');
  if (JSON.stringify(rows) !== JSON.stringify(inventory.releases)) throw Error('Release metadata changed; repeat the migration audit.');
  const active = await store.rest('nikon_app_uploads?select=id&status=neq.complete&expires_at=gt.' + encodeURIComponent(new Date().toISOString()) + '&limit=1000');
  if (active.length) throw Error('An upload is in progress; finish or expire it before switching storage.');
}
const mode = process.argv[2];
let current = await ready();
if (mode === '--deploy-code') {
  if (current.ModTime !== before.ModTime || JSON.stringify(current.Environment) !== JSON.stringify(before.Environment) || current.Role !== before.Role) throw Error('Production configuration changed since backup.');
  const audit = JSON.parse(await readFile(new URL('deploy-audit.json', folder)));
  const zip = await readFile(new URL('next.zip', folder));
  if (sha(zip) !== audit.nextSha256 || audit.files.length !== 7) throw Error('Deployment artifact differs from the reviewed overlay.');
  await unchangedInventory();
  cloudApi('scf', 'UpdateFunctionCode', { Namespace: ENV_ID, FunctionName: FUNCTION_NAME, ZipFile: zip.toString('base64') });
  current = await ready();
  if (JSON.stringify(current.Environment) !== JSON.stringify(before.Environment) || current.Role !== before.Role) throw Error('Unrelated configuration changed.');
  await writeFile(new URL('code-deployed.json', folder), JSON.stringify({ at: new Date().toISOString(), sha256: sha(zip), modTime: current.ModTime }));
  console.log('Reviewed COS-capable code is Active; legacy storage remains selected.');
} else if (mode === '--activate') {
  const deployed = JSON.parse(await readFile(new URL('code-deployed.json', folder)));
  const artifact = JSON.parse(await readFile(new URL('deploy-audit.json', folder)));
  if (current.ModTime !== deployed.modTime || deployed.sha256 !== artifact.nextSha256 || current.Role !== before.Role) throw Error('Reviewed code deployment must precede activation without other configuration changes.');
  const proof = JSON.parse(await readFile(new URL('target-integrity.json', folder)));
  if (proof.count !== inventory.releases.length || !proof.allVerified || proof.bucket !== 'huevia-updates-1252602548'
      || proof.origin !== 'https://download.huevia.cc' || !Array.isArray(proof.rows)
      || inventory.releases.some(row => !proof.rows.some(p => p.path === row.storage_path && p.sha256 === row.sha256 && p.bytes === row.byte_length))) throw Error('Full target object verification is required.');
  await unchangedInventory();
  if (JSON.stringify(current.Environment) !== JSON.stringify(before.Environment)) throw Error('Environment changed since backup.');
  const added = { APP_RELEASE_STORAGE: 'cos', COS_REGION: 'ap-shanghai', COS_BUCKET: 'huevia-updates-1252602548',
    COS_PREFIX: 'huevia-updates/', COS_DOWNLOAD_ORIGIN: 'https://download.huevia.cc' };
  const variables = current.Environment.Variables.filter(row => !Object.hasOwn(added, row.Key));
  variables.push(...Object.entries(added).map(([Key, Value]) => ({ Key, Value })));
  cloudApi('scf', 'UpdateFunctionConfiguration', { Namespace: ENV_ID, FunctionName: FUNCTION_NAME,
    Role: 'HueviaUpdatePackageRole', Environment: { Variables: variables } });
  current = await ready();
  if (current.Role !== 'HueviaUpdatePackageRole' || variables.some(v => !current.Environment.Variables.some(x => x.Key === v.Key && x.Value === v.Value))) throw Error('COS configuration verification failed.');
  await writeFile(new URL('activated.json', folder), JSON.stringify({ at: new Date().toISOString(), role: current.Role, provider: 'cos' }));
  console.log('COS update storage is Active; original environment entries are preserved.');
} else if (mode === '--rollback-storage') {
  if (current.Role !== 'HueviaUpdatePackageRole' || current.Environment.Variables.find(x => x.Key === 'APP_RELEASE_STORAGE')?.Value !== 'cos') throw Error('The expected COS configuration is not active.');
  if (before.Environment.Variables.some(v => !current.Environment.Variables.some(x => x.Key === v.Key && x.Value === v.Value))) throw Error('Original environment changed; reconcile before rollback.');
  cloudApi('scf', 'UpdateFunctionConfiguration', { Namespace: ENV_ID, FunctionName: FUNCTION_NAME, Role: before.Role, Environment: before.Environment });
  current = await ready();
  if (JSON.stringify(current.Environment) !== JSON.stringify(before.Environment) || current.Role !== before.Role) throw Error('Rollback verification failed.');
  console.log('Original storage and execution role restored; compatible code retained.');
} else throw Error('Use --deploy-code, --activate or --rollback-storage after reviewing the corresponding audit.');
