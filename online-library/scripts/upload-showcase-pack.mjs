// Upload independent, licensed gallery source photos. Never edits or publishes preset records.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname, sep } from 'node:path';
import { createHash } from 'node:crypto';
import { validatePreview } from '../server/validation.mjs';
import { ENV_ID, PUBLIC_ORIGIN } from './cloud-tools.mjs';
import { CloudBaseStore, CloudBaseStorage } from '../server/cloudbase.mjs';

const args = process.argv.slice(2);
const manifestPath = args.find(value => !value.startsWith('--'));
const receiptArg = args.find(value => value.startsWith('--receipt='));
if (!manifestPath || !receiptArg || !args.includes('--upload') && !args.includes('--verify'))
  throw Error('Usage: node scripts/upload-showcase-pack.mjs <manifest.json> --upload|--verify --receipt=<path>');
const manifestDir = dirname(resolve(manifestPath));
const manifest = JSON.parse(await readFile(resolve(manifestPath), 'utf8'));
if (manifest.version !== 1 || manifest.id !== 'photography-v1' || !Array.isArray(manifest.items)
    || manifest.items.length !== 10) throw Error('Unexpected showcase pack.');
const sha = value => createHash('sha256').update(value).digest('hex');
const files = [];
for (const item of manifest.items) {
  if (!/^[a-z-]+\.jpg$/.test(item.file) || item.licenseUrl !== 'https://www.pexels.com/license/'
      || !/^https:\/\/www\.pexels\.com\/photo\/[a-z0-9-]+\/$/.test(item.pageUrl) || !item.author)
    throw Error('Missing photo provenance.');
  const path = resolve(manifestDir, item.file);
  if (!path.startsWith(manifestDir + sep)) throw Error('Photo escapes the manifest directory.');
  const data = await readFile(path), details = validatePreview(data, 'image/jpeg');
  if (details.sha256 !== item.sha256 || details.byteLength !== item.byteLength
      || !(item.width > 0 && item.width <= 960 && item.height > 0 && item.height <= 960) || details.extension !== 'jpg')
    throw Error('Photo does not match the checked manifest: ' + item.id);
  files.push({ item, data, details });
}
const receiptPath = resolve(receiptArg.slice('--receipt='.length));
const service = args.includes('--service');
const session = service ? null : JSON.parse(await readFile(new URL('../.local/community-admin-session.json', import.meta.url), 'utf8'));
let store, storage;
if (service) {
  const credential = JSON.parse(await readFile(new URL('../.local/service-credential.json', import.meta.url), 'utf8'));
  if (credential.environmentId !== ENV_ID) throw Error('Unexpected cloud environment.');
  store = new CloudBaseStore({ environmentId: ENV_ID, serviceKey: credential.serviceKey });
  storage = new CloudBaseStorage(store);
}
const base = PUBLIC_ORIGIN + '/preset-library';
async function request(path, method = 'GET', body) {
  const response = await fetch(base + path, { method, redirect: 'error', signal: AbortSignal.timeout(45000),
    headers: { Cookie: session.cookie, Origin: PUBLIC_ORIGIN, 'X-CSRF-Token': session.csrfToken,
      ...(body === undefined ? {} : { 'Content-Type': 'image/jpeg' }) }, body });
  if (!response.ok) throw Error('Showcase API request failed: HTTP ' + response.status);
  return response;
}
const listing = async () => service ? { items: (await store.presets()).map(row => ({ id: row.id, revision: row.revision,
  publishedRevision: row.published_revision, status: row.status, file: row.draft?.file, preview: row.draft?.preview })) }
  : (await request('/api/presets')).json();
const baseline = await listing();
const presetState = listing => sha(JSON.stringify(listing.items.map(row => ({ id: row.id, revision: row.revision,
  publishedRevision: row.publishedRevision, status: row.status, file: row.file?.sha256, preview: row.preview?.id || null }))
  .sort((a, b) => a.id.localeCompare(b.id))));
if (!Array.isArray(baseline.items)) throw Error('Incomplete preset listing.');
const receipt = { version: 1, pack: manifest.id, verifiedAt: new Date().toISOString(),
  publicCatalogModified: false, purpose: 'Independent source photography for labelled phone-side gallery simulations; not camera reference samples.',
  presetCount: baseline.items.length, presetStateBefore: presetState(baseline), items: [] };
for (const { item, data, details } of files) {
  const id = 'preview-' + details.sha256;
  if (args.includes('--upload')) {
    let result;
    if (service) {
      let asset = await store.asset(id);
      if (!asset) {
        const storagePath = 'preview/' + details.sha256 + '.jpg';
        await storage.put(storagePath, data, 'image/jpeg');
        asset = await store.addAsset({ id, kind: 'preview', url: base + '/files/' + id + '.jpg',
          adminUrl: base + '/api/assets/' + id + '/content', storagePath,
          originalName: 'showcase-' + item.file, ...details });
      }
      result = { asset };
    } else result = await (await request('/api/uploads?kind=preview&filename=' + encodeURIComponent('showcase-' + item.file), 'POST', data)).json();
    if (result.asset?.id !== id || result.asset?.sha256 !== item.sha256 || result.asset?.byteLength !== item.byteLength)
      throw Error('Uploaded photo identity did not match: ' + item.id);
  }
  const asset = service ? await store.asset(id) : null;
  if (service && (!asset || asset.kind !== 'preview' || asset.sha256 !== item.sha256)) throw Error('Stored asset mismatch.');
  const downloaded = service ? await storage.get(asset.storagePath, 1024 * 1024)
    : Buffer.from(await (await request('/api/assets/' + id + '/content')).arrayBuffer());
  if (downloaded.length !== data.length || sha(downloaded) !== item.sha256)
    throw Error('Uploaded photo verification failed: ' + item.id);
  receipt.items.push({ id: item.id, assetId: id, sha256: item.sha256, byteLength: data.length,
    authenticatedByteForByteRead: true, boundToPreset: false, author: item.author, pageUrl: item.pageUrl, licenseUrl: item.licenseUrl });
  console.log(JSON.stringify({ verified: receipt.items.length, total: files.length, photo: item.id }));
}
const final = await listing();
receipt.presetStateAfter = presetState(final);
if (receipt.presetStateAfter !== receipt.presetStateBefore) throw Error('Preset state changed while uploading source photos.');
await mkdir(dirname(receiptPath), { recursive: true });
await writeFile(receiptPath, JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify({ completed: receipt.items.length, bytes: files.reduce((sum, f) => sum + f.data.length, 0), presetStateUnchanged: true }));
