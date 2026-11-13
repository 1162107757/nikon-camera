// Inspect by default; uploading keeps the artifact in a private draft until exact publication confirmation.
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { inspectIpa } from '../server/ipa.mjs';
import { inspectApk, NEXT_APK_PACKAGE } from '../server/apk.mjs';
import { PUBLIC_ORIGIN } from './cloud-tools.mjs';

const args = process.argv.slice(2), artifact = args[0];
const valueOf = flag => { const index = args.indexOf(flag);return index >= 0 ? args[index + 1] : undefined; };
if (!artifact || !/[.](ipa|apk)$/i.test(artifact) || !valueOf('--notes-file')) throw Error('Usage: node scripts/prepare-mobile-release.mjs <device.ipa|next.apk> --notes-file <notes.txt> [--stable] [--upload-draft] [--publish --confirm "PUBLISH code sha256"] [--verify-public]');
const bytes = await readFile(artifact), platform = /[.]ipa$/i.test(artifact) ? 'ios' : 'android';
const metadata = platform === 'ios' ? inspectIpa(bytes) : inspectApk(bytes, { packageName: NEXT_APK_PACKAGE });
const notes = (await readFile(valueOf('--notes-file'), 'utf8')).trim(), channel = args.includes('--stable') ? 'stable' : 'beta';
if (!notes || notes.length > 6000) throw Error('Notes must contain 1–6000 characters.');
const base = PUBLIC_ORIGIN + '/preset-library', prefix = platform === 'ios' ? '/api/ios/releases' : '/api/next/releases';
const inspectOnly = !args.includes('--upload-draft') && !args.includes('--publish') && !args.includes('--verify-public');
if (inspectOnly) {
  console.log(JSON.stringify({ inspected: true, uploaded: false, published: false, platform, channel, ...metadata,
    manifestUrl: `${base}/${platform === 'ios' ? 'ios/' : ''}releases/latest?${platform === 'ios' ? 'bundleId' : 'packageName'}=cc.huevia.next&channel=${channel}`,
    publishConfirmation: `PUBLISH ${metadata.versionCode} ${metadata.sha256}` }, null, 2));
  process.exit(0);
}
const confirmation = valueOf('--confirm');
if (args.includes('--publish') && confirmation !== `PUBLISH ${metadata.versionCode} ${metadata.sha256}`) throw Error('Publication requires the exact reviewed version and SHA-256 confirmation.');
const sessionFile = valueOf('--session-file') || new URL('../.local/community-admin-session.json', import.meta.url);
const session = JSON.parse(await readFile(sessionFile, 'utf8'));
if (typeof session.cookie !== 'string' || typeof session.csrfToken !== 'string') throw Error('Existing administrator session is unavailable; refresh the session through the existing login workflow.');
const stateFile = new URL(`../.local/mobile-release-${platform}-${metadata.versionCode}-${metadata.sha256}.json`, import.meta.url);
let state;try { state = JSON.parse(await readFile(stateFile, 'utf8')); } catch { state = {}; }
if (state.sha256 && (state.sha256 !== metadata.sha256 || state.channel !== channel)) throw Error('Saved upload state has a different artifact or channel.');
state = { ...state, platform, sha256: metadata.sha256, versionCode: metadata.versionCode, channel };
const save = () => writeFile(stateFile, JSON.stringify(state, null, 2) + '\n', { mode: 0o600 });
async function request(path, method = 'GET', body) {
  const raw = Buffer.isBuffer(body), response = await fetch(base + path, { method, redirect: 'error', signal: AbortSignal.timeout(path.endsWith('/complete') ? 240000 : 60000),
    headers: { Cookie: session.cookie, Origin: PUBLIC_ORIGIN, 'X-CSRF-Token': session.csrfToken,
      ...(body === undefined ? {} : { 'Content-Type': raw ? 'application/octet-stream' : 'application/json' }) },
    body: body === undefined ? undefined : raw ? body : JSON.stringify(body) });
  const result = await response.json();
  if (!response.ok) { const error = new Error(`Mobile release API ${response.status} ${result.error?.code || 'UNAVAILABLE'}`);error.code = result.error?.code;throw error; }
  return result;
}
const listing = await request(prefix);state.release = listing.items.find(row => row.sha256 === metadata.sha256);
if (!state.release && (args.includes('--upload-draft') || args.includes('--publish'))) {
  if (!state.uploadId) {
    const task = await request(prefix + '/uploads', 'POST', { byteLength: bytes.length, channel, notes });
    state.uploadId = task.uploadId;state.chunkBytes = task.chunkBytes;state.nextChunk = 0;await save();
  }
  try {
    if (state.chunkBytes !== 524288) throw Error('Unexpected server chunk policy.');
    for (let index = state.nextChunk || 0; index < Math.ceil(bytes.length / state.chunkBytes); index++) {
      await request(`${prefix}/uploads/${state.uploadId}/chunks/${index}`, 'PUT', bytes.subarray(index * state.chunkBytes, Math.min(bytes.length, (index + 1) * state.chunkBytes)));
      state.nextChunk = index + 1;await save();
    }
    state.release = (await request(`${prefix}/uploads/${state.uploadId}/complete`, 'POST', {})).release;await save();
  } catch (failure) {
    if (['MOBILE_RELEASE_EXPIRED', 'MOBILE_RELEASE_NOT_FOUND', 'MOBILE_RELEASE_INVALID', 'INVALID_IPA', 'INVALID_APK'].includes(failure.code)) { delete state.uploadId;state.nextChunk = 0;await save(); }
    throw failure;
  }
}
if (!state.release || state.release.sha256 !== metadata.sha256 || state.release.byteLength !== bytes.length) throw Error('No matching server-verified release exists; upload a private draft first.');
if (args.includes('--publish')) {
  if (state.release.status === 'withdrawn') throw Error('Withdrawn artifacts cannot be republished.');
  if (state.release.status === 'draft') state.release = (await request(`${prefix}/${state.release.id}/publish`, 'POST', { expectedRevision: state.release.revision, confirmation })).release;
  await save();
}
if (args.includes('--verify-public')) {
  if (state.release.status !== 'published') throw Error('Public verification requires an already reviewed and published artifact.');
  let url = new URL(state.release.downloadUrl), response;
  for (let i = 0; i < 3; i++) {
    if (url.protocol !== 'https:' || url.username || url.password || url.hash || !(url.origin === PUBLIC_ORIGIN || url.origin === 'https://download.huevia.cc')) throw Error('Public download escaped the configured release origins.');
    response = await fetch(url, { redirect: 'manual', signal: AbortSignal.timeout(120000) });
    if (response.status === 307) { url = new URL(response.headers.get('location'), url);await response.body?.cancel();continue; }break;
  }
  if (response?.status !== 200) throw Error('Public artifact is unavailable.');
  const hash = createHash('sha256');let received = 0;
  for await (const chunk of response.body) { received += chunk.length;if (received > bytes.length) throw Error('Public artifact exceeded its byte declaration.');hash.update(chunk); }
  if (received !== bytes.length || hash.digest('hex') !== metadata.sha256) throw Error('Public artifact bytes do not match the reviewed package.');
  state.publicBytesVerified = true;state.verifiedAt = new Date().toISOString();await save();
}
console.log(JSON.stringify({ platform, channel, versionCode: metadata.versionCode, sha256: metadata.sha256,
  status: state.release.status, uploaded: true, published: state.release.status === 'published',
  downloadUrl: state.release.downloadUrl, publicBytesVerified: state.publicBytesVerified === true }, null, 2));
