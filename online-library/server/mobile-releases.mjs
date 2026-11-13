import { createHash } from 'node:crypto';
import { ServiceError } from './cloudbase.mjs';
import { createAbuseContext } from './abuse.mjs';
import { inspectIpa, MAX_IPA_BYTES, IOS_BUNDLE_IDS } from './ipa.mjs';
import { inspectApk, MAX_NEXT_APK_BYTES, NEXT_APK_PACKAGE } from './apk.mjs';

export const MOBILE_CHUNK_BYTES = 512 * 1024;
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const hash = data => createHash('sha256').update(data).digest('hex');
const statuses = { FORBIDDEN: 403, NOT_FOUND: 404, INVALID: 400, CONFLICT: 409, DUPLICATE: 409, INCOMPLETE: 409, EXPIRED: 409, BUDGET: 429, CONFIRMATION: 400, DOWNGRADE: 409 };
const channelOf = value => { if (!['stable', 'beta'].includes(value)) throw new ServiceError(400, 'INVALID_CHANNEL', '更新通道无效。'); return value; };
const notesOf = value => { if (typeof value !== 'string' || !value.trim() || value.length > 6000 || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value)) throw new ServiceError(400, 'INVALID_NOTES', '请填写 1–6000 字更新说明。'); return value.trim(); };
function view(row, base) {
  const metadata = { ...row.metadata, platform: row.platform, createdAt: row.created_at,
    publishedAt: row.published_at, withdrawnAt: row.withdrawn_at };
  if (row.platform === 'ios') return { ...metadata, schema: 1, platform: 'ios', distribution: 'unsigned-ipa', notes: row.notes,
    id: row.id, channel: row.channel, revision: row.revision, downloadUrl: `${base}/ios/releases/${row.id}/file` };
  return { ...metadata, notes: row.notes, id: row.id, channel: row.channel, revision: row.revision, mandatory: false,
    downloadUrl: `${base}/next/releases/${row.id}/file` };
}
export function createMobileReleaseRoutes({ store, storage, publicBaseUrl, basePath = '/preset-library', trustedProxyHops = 0, trustedProxyAddresses, trustedForwardedProxyAddresses }) {
  const base = new URL(publicBaseUrl).origin + basePath.replace(/\/$/, '');
  const source = createAbuseContext({ store, secret: store.serviceKey || 'mobile-release-local-source-budget-v1', trustedProxyHops, trustedProxyAddresses, trustedForwardedProxyAddresses });
  async function rpc(actor, action, body) {
    const value = await store.rpc('nikon_mobile_release_manage', { p_actor: actor, p_action: action, p_body: body });
    if (value?.error) throw new ServiceError(statuses[value.error] || 503, `MOBILE_RELEASE_${value.error}`, value.error === 'CONFIRMATION' ? '请先复核版本和 SHA-256，再确认发布操作。' : '版本操作未完成，请核对权限、版本、上传完整性和配额。');
    return value;
  }
  async function budget(req, kind, bytes = 0) {
    const value = await store.rpc('nikon_mobile_release_budget', { p_key: source.context(req).sourceHash, p_kind: kind, p_bytes: bytes });
    if (value?.error) throw new ServiceError(value.error === 'BUDGET' ? 429 : 503, 'MOBILE_RELEASE_BUDGET', '更新请求或流量达到上限，请稍后重试。');
  }
  async function row(id) { return (await store.rest(`nikon_mobile_releases?id=eq.${id}&select=*&limit=1`))[0] || null; }
  async function publicRoute(req, res, { path, url, json }) {
    const iosLatest = path === '/ios/releases/latest';
    const nextLatest = path === '/releases/latest' && url.searchParams.get('packageName') === NEXT_APK_PACKAGE;
    if (iosLatest || nextLatest) {
      if (req.method !== 'GET') throw new ServiceError(405, 'METHOD_NOT_ALLOWED', '请使用 GET 查询更新。');
      const platform = iosLatest ? 'ios' : 'android', identity = iosLatest ? url.searchParams.get('bundleId') || IOS_BUNDLE_IDS[0] : NEXT_APK_PACKAGE;
      if (!(iosLatest ? IOS_BUNDLE_IDS : [NEXT_APK_PACKAGE]).includes(identity)) throw new ServiceError(400, 'INVALID_PACKAGE', '应用身份不正确。');
      const channel = channelOf(url.searchParams.get('channel') || 'stable');
      const versionText = url.searchParams.get('versionCode') || '0'; if (!/^\d{1,9}$/.test(versionText)) throw new ServiceError(400, 'INVALID_VERSION', '版本参数无效。');
      const sdkText = url.searchParams.get('sdk') || '999'; if (!/^\d{1,3}$/.test(sdkText)) throw new ServiceError(400, 'INVALID_VERSION', '系统版本参数无效。');
      const abi = url.searchParams.get('abi') || '';
      if (abi && !['arm64-v8a','armeabi-v7a','x86_64'].includes(abi)) throw new ServiceError(400, 'INVALID_ABI', 'Android 安装架构无效。');
      await budget(req, 'metadata');
      const selected = (await store.rest(`nikon_mobile_releases?platform=eq.${platform}&package_name=eq.${identity}&channel=eq.${channel}&status=in.(published,withdrawn)&select=*&order=version_code.desc&limit=1`))[0];
      let release = null, reason = 'no_release';
      if (selected?.status === 'withdrawn') reason = 'withdrawn';
      else if (selected?.status === 'published') { release = view(selected, base); reason = platform === 'android' && (Number(sdkText) < release.minSdk || abi && !release.abis?.includes(abi)) ? 'incompatible' : Number(versionText) > selected.version_code ? 'client_newer' : Number(versionText) === selected.version_code ? 'current' : 'available'; }
      res.setHeader('Cache-Control', 'no-store');
      json(res, { schemaVersion: 1, channel, release, reason, updateAvailable: reason === 'available', updateRequired: false });return true;
    }
    const match = /^\/(ios|next)\/releases\/([a-f0-9-]+)\/file$/.exec(path);
    if (!match || !UUID.test(match[2])) return false;
    const selected = await row(match[2]);
    if (!selected) throw new ServiceError(404, 'MOBILE_RELEASE_NOT_FOUND', '版本不存在或已下架。');
    if (req.method !== 'GET') throw new ServiceError(405, 'METHOD_NOT_ALLOWED', '请使用 GET 下载版本文件。');
    if (selected.status !== 'published' || (match[1] === 'ios' ? 'ios' : 'android') !== selected.platform) throw new ServiceError(404, 'MOBILE_RELEASE_NOT_FOUND', '版本不存在或已下架。');
    const metadata = selected.metadata, key = `mobile-releases/${selected.platform}/${metadata.sha256}.bin`;
    if (!/^[a-f0-9]{64}$/.test(metadata.sha256) || selected.storage_path !== key || !Number.isInteger(metadata.byteLength) || metadata.byteLength < 1024 || metadata.byteLength > (selected.platform === 'ios' ? MAX_IPA_BYTES : MAX_NEXT_APK_BYTES)) throw new ServiceError(503, 'MOBILE_RELEASE_INVALID', '发布文件资料校验失败。');
    const etag = `"sha256-${metadata.sha256}"`, unchanged = req.headers['if-none-match'] === etag;
    await budget(req, 'download', unchanged ? 0 : metadata.byteLength);res.setHeader('Cache-Control', 'no-store, max-age=0');
    if (unchanged) { res.writeHead(304, { ETag: etag });res.end();return true; }
    if (typeof storage.verify !== 'function' || typeof storage.signDownload !== 'function') throw new ServiceError(503, 'MOBILE_STORAGE_REQUIRED', '移动版大文件分发需要已配置的私有 COS 存储。');
    if (await storage.verify(key, metadata.byteLength, metadata.sha256) !== true) throw new ServiceError(503, 'MOBILE_RELEASE_CHANGED', '发布文件摘要校验失败。');
    const name = selected.platform === 'ios' ? `Huevia-iOS-${selected.version_code}-${selected.channel}.ipa` : `Huevia-next-${selected.version_code}-${selected.channel}.apk`;
    const download = await storage.signDownload(key, 60, name);
    if ((await row(selected.id))?.status !== 'published') throw new ServiceError(404, 'MOBILE_RELEASE_NOT_FOUND', '此版本已下架。');
    if (req.aborted || res.destroyed) return true;
    res.writeHead(307, { Location: download, ETag: etag, 'Content-Length': 0, 'X-Content-SHA256': metadata.sha256, 'Referrer-Policy': 'no-referrer' });res.end();return true;
  }
  async function adminRoute(req, res, { path, session, json, readJson, readBody }) {
    const prefix = path.startsWith('/api/ios/releases') ? '/api/ios/releases' : path.startsWith('/api/next/releases') ? '/api/next/releases' : '';
    if (!prefix) return false;
    const administrator = session?.username ? await store.findAdmin(session.username) : null;
    if (!administrator || administrator.disabled) throw new ServiceError(403, 'MOBILE_RELEASE_FORBIDDEN', '请使用有效的后台管理员账号。');
    const actor = session.username, platform = prefix.includes('/ios/') ? 'ios' : 'android';
    if (!['GET', 'HEAD', 'OPTIONS'].includes(req.method)) await rpc(actor, 'budget', { bytes: 0, countRequest: true });
    if (path === prefix && req.method === 'GET') {
      const items = await store.rest(`nikon_mobile_releases?platform=eq.${platform}&select=*&order=version_code.desc&limit=200`);
      json(res, { items: items.map(row => ({ ...view(row, base), status: row.status })), maxBytes: MAX_IPA_BYTES, chunkBytes: MOBILE_CHUNK_BYTES });return true;
    }
    const audit = /^\/([a-f0-9-]+)\/audit$/.exec(path.slice(prefix.length));
    if (audit && UUID.test(audit[1]) && req.method === 'GET') {
      const selected = await row(audit[1]);
      if (!selected || selected.platform !== platform) throw new ServiceError(404, 'MOBILE_RELEASE_NOT_FOUND', '版本不存在。');
      const items = await store.rest(`nikon_mobile_release_audit?release_id=eq.${audit[1]}&select=actor,action,details,created_at&order=created_at.desc&limit=100`);
      json(res, { items });return true;
    }
    if (path === prefix + '/uploads' && req.method === 'POST') {
      const body = await readJson(req);if (!Number.isInteger(body.byteLength) || body.byteLength < 1024 || body.byteLength > MAX_IPA_BYTES) throw new ServiceError(400, 'INVALID_MOBILE_SIZE', '请选择不超过 128 MiB 的完整安装包。');
      const value = await rpc(actor, 'begin', { platform, byteLength: body.byteLength, channel: channelOf(body.channel), notes: notesOf(body.notes) });
      json(res, { ...value, chunkBytes: MOBILE_CHUNK_BYTES }, 201);return true;
    }
    const upload = /^\/uploads\/([a-f0-9-]+)\/(chunks\/(\d{1,3})|complete)$/.exec(path.slice(prefix.length));
    if (upload && UUID.test(upload[1])) {
      if (upload[2].startsWith('chunks/') && req.method === 'PUT') {
        const index = Number(upload[3]);if (index > 255) throw new ServiceError(400, 'INVALID_CHUNK', '分块序号无效。');
        const bytes = await readBody(req, MOBILE_CHUNK_BYTES);await rpc(actor, 'budget', { bytes: bytes.length, countRequest: false });
        if (!bytes.length) throw new ServiceError(400, 'EMPTY_CHUNK', '上传分块为空。');
        const sha256 = hash(bytes), key = `mobile-upload/${upload[1]}/${index}-${sha256}.part`;
        const body = { platform, id: upload[1], index, bytes: bytes.length, sha256, path: key };
        await rpc(actor, 'reserve', body);await storage.put(key, bytes, 'application/octet-stream');await rpc(actor, 'chunk', body);
        json(res, { uploaded: true, index });return true;
      }
      if (upload[2] === 'complete' && req.method === 'POST') {
        await readJson(req);const task = await rpc(actor, 'claim', { platform, id: upload[1] });
        try {
        if (!Number.isInteger(task.byteLength) || task.byteLength < 1024 || task.byteLength > MAX_IPA_BYTES || !Array.isArray(task.chunks) || task.chunks.length > 256) throw new ServiceError(503, 'MOBILE_UPLOAD_INVALID', '上传任务校验失败。');
        const bytes = Buffer.allocUnsafe(task.byteLength);let offset = 0;
        for (const chunk of task.chunks) {
          if (!Number.isInteger(chunk.size) || chunk.size < 1 || chunk.size > MOBILE_CHUNK_BYTES || offset + chunk.size > bytes.length || !/^mobile-upload\/[a-f0-9-]{36}\/\d{1,3}-[a-f0-9]{64}[.]part$/.test(chunk.path) || !chunk.path.startsWith(`mobile-upload/${upload[1]}/`)) throw new ServiceError(400, 'MOBILE_CHUNK_INVALID', '上传清单校验失败。');
          const data = await storage.get(chunk.path, MOBILE_CHUNK_BYTES);
          if (!data || data.length !== chunk.size || hash(data) !== chunk.sha256) throw new ServiceError(400, 'MOBILE_CHUNK_CHANGED', '上传分块校验失败，请重新上传。');
          data.copy(bytes, offset);offset += data.length;
        }
        if (offset !== bytes.length) throw new ServiceError(400, 'MOBILE_UPLOAD_INCOMPLETE', '安装包尚未传完。');
        const metadata = platform === 'ios' ? inspectIpa(bytes) : inspectApk(bytes, { packageName: NEXT_APK_PACKAGE });
        const key = `mobile-releases/${platform}/${metadata.sha256}.bin`;
        await rpc(actor, 'budget', { bytes: bytes.length, countRequest: false });
        await storage.put(key, bytes, 'application/octet-stream');
        const created = await rpc(actor, 'create', { platform, id: upload[1], metadata, path: key });
        json(res, { release: { ...view(created, base), status: created.status } }, 201);return true;
        } catch (failure) {
          try { await rpc(actor, 'fail', { platform, id: upload[1] }); } catch {}
          throw failure;
        }
      }
    }
    const action = /^\/([a-f0-9-]+)\/(publish|withdraw)$/.exec(path.slice(prefix.length));
    if (action && UUID.test(action[1]) && req.method === 'POST') {
      const body = await readJson(req);
      if (!Number.isInteger(body.expectedRevision) || body.expectedRevision < 1 || typeof body.confirmation !== 'string') throw new ServiceError(400, 'REVISION_REQUIRED', '请刷新版本并复核发布确认文字。');
      const selected = await row(action[1]);
      if (!selected || selected.platform !== platform) throw new ServiceError(404, 'MOBILE_RELEASE_NOT_FOUND', '版本不存在。');
      if (action[2] === 'publish') {
        if (typeof storage.verify !== 'function' || await storage.verify(selected.storage_path, selected.metadata.byteLength, selected.metadata.sha256) !== true) throw new ServiceError(503, 'MOBILE_RELEASE_CHANGED', '发布前文件摘要校验失败。');
      }
      const changed = await rpc(actor, action[2], { platform, id: action[1], expectedRevision: body.expectedRevision, confirmation: body.confirmation });
      json(res, { release: { ...view(changed, base), status: changed.status } });return true;
    }
    throw new ServiceError(404, 'MOBILE_RELEASE_ROUTE_NOT_FOUND', '版本操作不存在。');
  }
  return { publicRoute, adminRoute };
}
