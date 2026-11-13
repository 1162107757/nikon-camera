const base = new URL('../', import.meta.url), byId = id => document.getElementById(id);
const legacyOrigin = 'https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const MAX_APK_BYTES = 100 * 1024 * 1024;
const MAX_MOBILE_BYTES = 128 * 1024 * 1024;

export function releaseDownloadUrl(release, currentBase = base) {
  const ios = release?.platform === 'ios', next = !ios && release?.packageName === 'cc.huevia.next';
  if (!release || !/^[a-f0-9]{64}$/.test(release.sha256) || (!ios && !/^[a-f0-9]{64}$/.test(release.signerSha256))
      || !Number.isSafeInteger(release.versionCode) || release.versionCode < 1
      || !Number.isSafeInteger(release.byteLength) || release.byteLength < 1 || release.byteLength > (ios || next ? MAX_MOBILE_BYTES : MAX_APK_BYTES)
      || ios && (release.bundleId !== 'cc.huevia.next' || release.distribution !== 'unsigned-ipa' || !/^\d{1,2}\.\d{1,2}(?:\.\d{1,2})?$/.test(release.minimumIOS))) {
    throw new Error('版本信息不完整，请稍后重试。');
  }
  try {
    if (typeof release.id !== 'string' || !UUID.test(release.id) || typeof release.downloadUrl !== 'string') throw new Error();
    const current = new URL(currentBase), canonical = new URL(release.downloadUrl);
    const path = `${ios ? 'ios/' : next ? 'next/' : ''}releases/${release.id}/file`;
    const currentRoute = canonical.origin === current.origin && canonical.pathname === current.pathname + path;
    const legacyRoute = canonical.origin === legacyOrigin && canonical.pathname === '/preset-library/' + path;
    if (!['http:', 'https:'].includes(current.protocol) || current.username || current.password || current.search || current.hash
        || !current.pathname.endsWith('/') || canonical.username || canonical.password || canonical.search || canonical.hash
        || release.downloadUrl.includes('?') || release.downloadUrl.includes('#')
        || release.downloadUrl !== canonical.href || !(currentRoute || legacyRoute)) throw new Error();
    // Follow only the current site's validated release route; canonical metadata stays compatible with old Android builds.
    return new URL(path, current);
  } catch { throw new Error('下载地址校验失败，请稍后重试。'); }
}
const parameters = new URL(location.href).searchParams;
let activeChannel = parameters.get('channel') === 'beta' ? 'beta' : 'stable';
let activePlatform = parameters.get('platform') === 'ios' || !parameters.has('platform') && /iPhone|iPad|iPod/.test(navigator.userAgent || '') ? 'ios' : 'android';
let activeEdition = parameters.get('edition') === 'next' ? 'next' : 'legacy';
let serial = 0;
const android = sdk => ({24:'7.0',25:'7.1',26:'8.0',27:'8.1',28:'9',29:'10',30:'11',31:'12',32:'12L',33:'13',34:'14',35:'15',36:'16',37:'17'}[sdk] || `API ${sdk}`);
function pageUrl() {
  const url = new URL('https://huevia.cc/');
  if (activeChannel === 'beta') url.searchParams.set('channel', 'beta');
  url.searchParams.set('platform', activePlatform);
  if (activePlatform === 'android' && activeEdition === 'next') url.searchParams.set('edition', 'next');
  return url.href;
}
function drawQr() {
  const target = byId('qr'); target.replaceChildren();
  if (!globalThis.qrcodegen) { target.textContent = '请使用下方链接'; return; }
  const qr = globalThis.qrcodegen.QrCode.encodeText(pageUrl(), globalThis.qrcodegen.QrCode.Ecc.MEDIUM), ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg'); svg.setAttribute('viewBox', `0 0 ${qr.size + 8} ${qr.size + 8}`); svg.setAttribute('shape-rendering', 'crispEdges');
  const path = document.createElementNS(ns, 'path'); let d = '';
  for (let y = 0; y < qr.size; y++) for (let x = 0; x < qr.size; x++) if (qr.getModule(x,y)) d += `M${x+4},${y+4}h1v1h-1z`;
  path.setAttribute('d', d); path.setAttribute('fill', '#20242B'); svg.append(path); target.append(svg);
}
async function latest(channel, platform, edition) {
  const path = platform === 'ios' ? `ios/releases/latest?channel=${channel}&bundleId=cc.huevia.next` : `releases/latest?channel=${channel}&packageName=${edition === 'next' ? 'cc.huevia.next' : 'cc.huevia'}`;
  const response = await fetch(new URL(path, base), { credentials:'omit', cache:'no-store', headers:{Accept:'application/json'} });
  const value = await response.json(); if (!response.ok) throw new Error(value?.error?.message || '版本暂时无法读取，请稍后重试。');
  return value;
}
function chooseChannel(channel) {
  activeChannel = channel;
  syncSelection();
}
function syncSelection() {
  document.querySelectorAll('[data-channel]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.channel === activeChannel)));
  document.querySelectorAll('[data-platform]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.platform === activePlatform)));
  document.querySelectorAll('[data-edition]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.edition === activeEdition)));
  const ios = activePlatform === 'ios';
  byId('android-editions').hidden = ios;
  byId('ios-file-note').hidden = !ios;
  byId('install-title').textContent = ios ? '关于 IPA 文件' : '安装前的小提示';
  byId('install-copy').textContent = ios ? '此处仅提供未签名 IPA 文件下载。请自行签名后安装，下载文件不会自动安装应用。' : '下载完成后，打开 APK 并按 Android 提示安装。系统可能需要你允许浏览器安装应用。新版与原版分别安装，各自保留本机数据。';
  const currentUrl=new URL(location.href);currentUrl.search=new URL(pageUrl()).search;
  history.replaceState(null, '', currentUrl);
}
function render(data, fallback = false) {
  const release = data.release;
  byId('release').hidden = !release; byId('details').hidden = !release; byId('empty').hidden = Boolean(release);
  byId('channel-note').textContent = fallback ? '暂无正式版，以下为测试版，功能仍在调整。' : activeChannel === 'beta' ? '测试版用于提前体验，功能仍在调整。' : '';
  if (!release) {
    byId('empty-title').textContent = data.reason === 'withdrawn' ? '当前版本已撤回' : `暂未发布${activeChannel === 'beta' ? '测试版' : '正式版'}`;
    byId('empty-copy').textContent = data.reason === 'withdrawn' ? '请等待修复版本上架。已下载的旧包不会被自动替换。' : '安装包上架后，会显示在这里。'; return;
  }
  const download = releaseDownloadUrl(release);
  const ios = activePlatform === 'ios';
  if (ios !== (release.platform === 'ios') || !ios && ((activeEdition === 'next') !== (release.packageName === 'cc.huevia.next'))) throw new Error('版本平台不匹配，请重新检查。');
  byId('version').textContent = `Huevia ${release.versionName}`; byId('channel-label').textContent = activeChannel === 'beta' ? '测试版' : '正式版';
  byId('download-button').href = download.href;
  byId('download-label').textContent = ios ? '下载 iOS IPA 文件' : activeEdition === 'next' ? '下载 Android 新版' : '下载 Android 安装包';
  const time = new Intl.DateTimeFormat('zh-CN', {year:'numeric',month:'long',day:'numeric'}).format(new Date(release.publishedAt));
  byId('metadata').textContent = `${ios ? `iOS ${release.minimumIOS}` : `Android ${android(release.minSdk)}`} 及以上 · ${(release.byteLength/1048576).toFixed(2)} MiB · ${time}`;
  byId('notes').textContent = release.notes; byId('sha256').textContent = release.sha256; byId('package').textContent = ios ? release.bundleId : release.packageName; byId('signer').textContent = ios ? '' : release.signerSha256;
  byId('package-label').textContent = ios ? '应用标识' : '包名';
  byId('signer-label').hidden = ios;byId('signer').hidden = ios;
  drawQr();
}
async function load({allowFallback = false} = {}) {
  const request = ++serial; byId('loading').hidden = false; byId('empty').hidden = true; byId('release').hidden = true; byId('details').hidden = true;
  byId('download-button').href = '';
  const platform = activePlatform, edition = activeEdition;
  try {
    let data = await latest(activeChannel, platform, edition), fallback = false;
    if (request !== serial) return;
    if (allowFallback && activeChannel === 'stable' && data.reason === 'no_release') {
      const beta = await latest('beta', platform, edition);
      if (beta.release) { if (request !== serial) return; chooseChannel('beta'); data = beta; fallback = true; }
    }
    if (request !== serial) return; render(data, fallback);
  } catch(error) {
    if (request !== serial) return;
    byId('release').hidden = true; byId('details').hidden = true; byId('empty').hidden = false;
    byId('empty-title').textContent = '暂时无法读取版本'; byId('empty-copy').textContent = error.message;
  } finally { if (request === serial) byId('loading').hidden = true; }
}
document.querySelectorAll('[data-channel]').forEach(button => button.addEventListener('click', () => { chooseChannel(button.dataset.channel); load(); }));
document.querySelectorAll('[data-platform]').forEach(button => button.addEventListener('click', () => { if(activePlatform===button.dataset.platform)return;activePlatform=button.dataset.platform;syncSelection();load({allowFallback:true}); }));
document.querySelectorAll('[data-edition]').forEach(button => button.addEventListener('click', () => { if(activeEdition===button.dataset.edition)return;activeEdition=button.dataset.edition;syncSelection();load({allowFallback:true}); }));
byId('retry').addEventListener('click', () => load());
byId('copy-link').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(pageUrl()); byId('copy-status').textContent = '链接已复制'; }
  catch { byId('copy-status').textContent = '请复制浏览器地址栏中的链接。'; }
});
chooseChannel(activeChannel); load({allowFallback:true});
