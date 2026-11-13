import COS from './vendor/cos-sdk.cjs';
import { AsyncLocalStorage } from 'node:async_hooks';
import { createHash } from 'node:crypto';
import { ServiceError } from './cloudbase.mjs';
import { MAX_APK_BYTES } from './apk.mjs';
import { MAX_IPA_BYTES } from './ipa.mjs';

const APK = /^app-releases\/([a-f0-9]{64})\.(?:apk|bin)$/;
const CHUNK = /^app-upload\/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\/(?:0|[1-9][0-9]?|1[0-9]{2})-([a-f0-9]{64})\.part$/;
const MOBILE = /^mobile-releases\/(ios|android)\/([a-f0-9]{64})\.bin$/;
const MOBILE_CHUNK = /^mobile-upload\/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\/(?:0|[1-9][0-9]?|1[0-9]{2}|2[0-4][0-9]|25[0-5])-([a-f0-9]{64})\.part$/;
const objectHash = path => (APK.exec(path) || CHUNK.exec(path) || MOBILE_CHUNK.exec(path))?.[1] || MOBILE.exec(path)?.[2];
const maximumFor = path => MOBILE.test(path) ? MAX_IPA_BYTES : APK.test(path) ? MAX_APK_BYTES : 512 * 1024;
const hash = data => createHash('sha256').update(data).digest('hex');
const unavailable = () => new ServiceError(503, 'COS_RELEASE_UNAVAILABLE', '更新包存储暂时不可用，请稍后重试。');
const requestCredentials = new AsyncLocalStorage();

// SCF replaces these reserved headers. Read fresh credentials on each request,
// never cache cold-start credentials, log them, or forward them to the client.
export function withReleaseCredentials(req, run, env = process.env) {
  const peer = req.socket?.remoteAddress;
  const trusted = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(peer);
  if (env.TENCENTCLOUD_RUNENV !== 'SCF' || !trusted) return run();
  const h = req.headers;
  const secretId = h['x-scf-secret-id'], secretKey = h['x-scf-secret-key'], securityToken = h['x-scf-session-token'];
  if (![secretId, secretKey, securityToken].every(x => typeof x === 'string' && x.length > 0 && x.length < 4096)
      || h['x-scf-name'] !== env.SCF_FUNCTIONNAME) return run();
  return requestCredentials.run({ secretId, secretKey, securityToken }, run);
}

/** Only APKs and their upload chunks use this adapter; all other assets stay in CloudBase. */
export class CosReleaseStorage {
  constructor({ region, bucket, prefix = 'huevia-updates/', downloadOrigin, secretId, secretKey, securityToken,
    roleCredentials = false, client, fetchImpl = fetch } = {}) {
    if (!/^[a-z]{2}-[a-z0-9]+(?:-[a-z0-9]+)*$/.test(region || '')
        || !/^[a-z0-9][a-z0-9-]{1,49}-[0-9]{5,20}$/.test(bucket || '')
        || !/^(?:[a-z0-9][a-z0-9-]*\/){1,4}$/.test(prefix || '') || prefix.length > 96
        || !client && !roleCredentials && (!secretId || !secretKey)) throw Error('COS 更新包配置不完整。');
    let origin;
    try { origin = new URL(downloadOrigin); } catch { throw Error('COS 更新包下载域名无效。'); }
    if (origin.protocol !== 'https:' || origin.username || origin.password || origin.search || origin.hash || origin.pathname !== '/') throw Error('COS 更新包下载域名无效。');
    this.provider = 'cos'; this.preferSignedDownloads = true;
    this.region = region; this.bucket = bucket; this.prefix = prefix; this.origin = origin.origin;
    this.fixedCredentials = secretId && secretKey ? { secretId, secretKey, securityToken } : null;
    this.injectedClient = client; this.fetch = fetchImpl;
    this.pendingVerifications = new Map();
  }
  key(path) {
    if (typeof path !== 'string' || !(APK.test(path) || CHUNK.test(path) || MOBILE.test(path) || MOBILE_CHUNK.test(path))) throw unavailable();
    return this.prefix + path;
  }
  context() {
    const credentials = requestCredentials.getStore() || this.fixedCredentials;
    if (!credentials && !this.injectedClient) throw unavailable();
    return { credentials, client: this.injectedClient || new COS({ SecretId: credentials.secretId, SecretKey: credentials.secretKey,
      SecurityToken: credentials.securityToken, Protocol: 'https:', Domain: this.origin.slice(8), ForceSignHost: true,
      AutoSwitchHost: false, Timeout: 60000 }) };
  }
  params(path) { return { Bucket: this.bucket, Region: this.region, Key: this.key(path) }; }
  async put(path, data, mimeType = 'application/octet-stream') {
    const params = this.params(path), expected = objectHash(path);
    const maximum = maximumFor(path);
    if (!Buffer.isBuffer(data) || !data.length || data.length > maximum || hash(data) !== expected || mimeType !== 'application/octet-stream') throw unavailable();
    try {
      const { client } = this.context();
      await new Promise((resolve, reject) => client.putObject({ ...params, Body: data, ContentLength: data.length,
        ContentType: mimeType, CacheControl: 'no-store', ContentMD5: createHash('md5').update(data).digest('base64'),
        Headers: { 'x-cos-forbid-overwrite': 'true' } }, (error, result) => error ? reject(error) : resolve(result)));
    } catch (error) {
      if (!['FileAlreadyExists', 'ObjectAlreadyExists', 'ObjectAlreadyExist'].includes(error?.code || error?.Code)) throw unavailable();
      if (APK.test(path) || MOBILE.test(path)) {
        if (!await this.verify(path, data.length, expected)) throw unavailable();
        return;
      }
      const existing = await this.get(path, maximum);
      if (existing.length !== data.length || hash(existing) !== expected) throw unavailable();
    }
  }
  async signedGet(path, expiresIn, query) {
    const params = this.params(path), { client, credentials } = this.context();
    try {
      const result = await new Promise((resolve, reject) => client.getObjectUrl({ ...params, Method: 'GET', Sign: true,
        Protocol: 'https:', Domain: this.origin.slice(8), ForceSignHost: true, Expires: expiresIn, Query: query },
        (error, value) => error ? reject(error) : resolve(value)));
      const url = new URL(result.Url), pairs = [...url.searchParams], names = pairs.map(([name]) => name);
      const allowed = new Set(['q-sign-algorithm', 'q-ak', 'q-sign-time', 'q-key-time', 'q-header-list', 'q-url-param-list', 'q-signature', 'x-cos-security-token', ...Object.keys(query)]);
      const time = (url.searchParams.get('q-sign-time') || '').split(';').map(Number), now = Math.floor(Date.now() / 1000);
      const signedQuery = decodeURIComponent(url.searchParams.get('q-url-param-list') || '').split(';').filter(Boolean);
      if (url.origin !== this.origin || url.username || url.password || url.hash || url.pathname !== '/' + params.Key
          || names.length !== new Set(names).size || names.some(name => !allowed.has(name))
          || Object.entries(query).some(([name, value]) => url.searchParams.get(name) !== value || !signedQuery.includes(name))
          || url.searchParams.get('q-sign-algorithm') !== 'sha1' || !/^[a-f0-9]{40}$/.test(url.searchParams.get('q-signature') || '')
          || url.searchParams.get('q-header-list') !== 'host' || time.length !== 2 || !time.every(Number.isSafeInteger)
          || Math.abs(now - time[0]) > 30 || time[1] - time[0] !== expiresIn || time[1] <= now
          || url.searchParams.get('q-key-time') !== url.searchParams.get('q-sign-time')
          || credentials && url.searchParams.get('q-ak') !== credentials.secretId
          || credentials?.secretKey && pairs.some(([, value]) => value.includes(credentials.secretKey))) throw unavailable();
      return url.href;
    } catch { throw unavailable(); }
  }
  async get(path, maximum) {
    const cap = maximumFor(path);
    if (!Number.isSafeInteger(maximum) || maximum < 1 || maximum > cap) throw unavailable();
    let response;
    try {
      response = await this.fetch(await this.signedGet(path, 60, {}), { redirect: 'error', signal: AbortSignal.timeout(60000) });
      if (response.status !== 200) throw unavailable();
      const header = response.headers.get('content-length'), declared = header === null ? null : Number(header);
      if (declared !== null && (!Number.isSafeInteger(declared) || declared < 1 || declared > maximum)) throw unavailable();
      const chunks = []; let size = 0;
      for await (const chunk of response.body) { size += chunk.length; if (size > maximum) throw unavailable(); chunks.push(chunk); }
      if (declared !== null && size !== declared) throw unavailable();
      return Buffer.concat(chunks, size);
    } catch { throw unavailable(); }
    finally { try { if (response?.body && !response.body.locked) await response.body.cancel(); } catch {} }
  }
  async verify(path, byteLength, sha256) {
    if (typeof path !== 'string' || !(APK.test(path) || MOBILE.test(path)) || objectHash(path) !== sha256 || !Number.isSafeInteger(byteLength) || byteLength < 1 || byteLength > maximumFor(path)) throw unavailable();
    this.key(path);
    // Each caller must still have valid request-scoped credentials. Sharing a
    // read never shares download URLs or skips a later request's integrity check.
    this.context();
    const key = `${path}:${byteLength}`, pending = this.pendingVerifications.get(key);
    if (pending) return pending;
    const task = this.verifyObject(path, byteLength, sha256);
    this.pendingVerifications.set(key, task);
    try { return await task; }
    finally { if (this.pendingVerifications.get(key) === task) this.pendingVerifications.delete(key); }
  }
  async verifyObject(path, byteLength, sha256) {
    let response;
    try {
      response = await this.fetch(await this.signedGet(path, 60, {}), { redirect: 'error', signal: AbortSignal.timeout(60000) });
      if (response.status !== 200) throw unavailable();
      const declared = response.headers.get('content-length');
      if (declared !== null && (!/^[1-9][0-9]*$/.test(declared) || Number(declared) !== byteLength)) return false;
      const digest = createHash('sha256'); let size = 0;
      for await (const chunk of response.body) {
        size += chunk.byteLength;
        if (size > byteLength) return false;
        digest.update(chunk);
      }
      return size === byteLength && digest.digest('hex') === sha256;
    } catch { throw unavailable(); }
    finally { try { if (response?.body && !response.body.locked) await response.body.cancel(); } catch {} }
  }
  async signDownload(path, expiresIn = 60, downloadName) {
    this.key(path);
    const mobile=MOBILE.exec(path);
    const validName=mobile ? (mobile[1]==='ios' ? /^Huevia-iOS-[1-9][0-9]{0,8}-(?:beta|stable)\.ipa$/ : /^Huevia-next-[1-9][0-9]{0,8}-(?:beta|stable)\.apk$/).test(downloadName || '') : /^Huevia-[1-9][0-9]{0,9}-(?:beta|stable)\.apk$/.test(downloadName || '');
    if (!(APK.test(path) || mobile) || !Number.isInteger(expiresIn) || expiresIn < 1 || expiresIn > 60 || !validName) throw unavailable();
    // The validated ASCII filename is a legal header token; avoid provider/proxy quote escaping.
    return this.signedGet(path, expiresIn, { 'response-content-disposition': `attachment; filename=${downloadName}`,
      'response-content-type': mobile?.[1]==='ios' ? 'application/octet-stream' : 'application/vnd.android.package-archive' });
  }
}
export function releaseStorageFromEnv(env, legacyStorage) {
  if (!env.APP_RELEASE_STORAGE || env.APP_RELEASE_STORAGE === 'cloudbase') return legacyStorage;
  if (env.APP_RELEASE_STORAGE !== 'cos') throw Error('不支持的更新包存储配置。');
  return new CosReleaseStorage({ region: env.COS_REGION, bucket: env.COS_BUCKET, prefix: env.COS_PREFIX || 'huevia-updates/',
    downloadOrigin: env.COS_DOWNLOAD_ORIGIN, secretId: env.COS_SECRET_ID, secretKey: env.COS_SECRET_KEY,
    securityToken: env.COS_SECURITY_TOKEN, roleCredentials: env.TENCENTCLOUD_RUNENV === 'SCF' });
}
