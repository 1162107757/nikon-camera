const API_PATH = '/preset-library/';
const LEGACY_ORIGIN = 'https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;

export function downloadUrl(release, origin) {
  if (!release || release.packageName !== 'cc.huevia' || !UUID.test(release.id)
      || !/^[a-f0-9]{64}$/.test(release.sha256) || !/^[a-f0-9]{64}$/.test(release.signerSha256)
      || !Number.isSafeInteger(release.versionCode) || release.versionCode < 1
      || !Number.isSafeInteger(release.byteLength) || release.byteLength < 1 || release.byteLength > 512 * 1048576)
    throw Error('版本信息不完整，请稍后重新读取。');
  const current = new URL(origin), canonical = new URL(release.downloadUrl);
  const path = API_PATH + 'releases/' + release.id + '/file';
  if (!['https:', 'http:'].includes(current.protocol) || current.username || current.password
      || canonical.username || canonical.password || canonical.search || canonical.hash
      || release.downloadUrl !== canonical.href || canonical.pathname !== path
      || ![current.origin, LEGACY_ORIGIN].includes(canonical.origin)) throw Error('下载地址无法确认，请使用完整下载页。');
  return new URL(path, current.origin).href;
}

export function mountDownload(document, location, fetchImpl = fetch, historyImpl = history) {
  const byId = id => document.getElementById(id);
  let channel = new URL(location.href).searchParams.get('channel') === 'beta' ? 'beta' : 'stable';
  let serial = 0;
  const controls = [...document.querySelectorAll('[data-channel]')];
  function choose(next, updateUrl = true) {
    channel = next;
    controls.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.channel === channel)));
    if (updateUrl) { const url = new URL(location.href); if (next === 'beta') url.searchParams.set('channel', next); else url.searchParams.delete('channel'); historyImpl.replaceState(null, '', url); }
  }
  async function latest(selected) {
    const response = await fetchImpl(API_PATH + 'releases/latest?channel=' + selected + '&packageName=cc.huevia',
      { credentials: 'omit', cache: 'no-store', headers: { Accept: 'application/json' }, signal: AbortSignal.timeout(20000) });
    if (!response.ok) throw Error('暂时无法读取版本，请稍后重试。');
    return response.json();
  }
  async function load(fallback = false) {
    const request = ++serial;
    byId('release-info').hidden = true; byId('release-status').hidden = false;
    byId('release-status').textContent = '正在读取可下载版本…'; byId('retry').hidden = true;
    try {
      let data = await latest(channel), usedFallback = false;
      if (fallback && channel === 'stable' && data.reason === 'no_release') {
        const beta = await latest('beta');
        if (request !== serial) return;
        if (beta.release) { data = beta; usedFallback = true; choose('beta'); }
      }
      if (request !== serial) return;
      const release = data.release;
      if (!release) {
        byId('release-status').textContent = data.reason === 'withdrawn' ? '当前版本已撤回，请等待后续版本。'
          : channel === 'stable' ? '暂未发布正式版，可以切换查看测试版。' : '暂未发布测试版，请稍后再来。';
        return;
      }
      const href = downloadUrl(release, location.origin);
      byId('download-file').href = href;
      byId('version-name').textContent = 'Huevia ' + release.versionName;
      byId('channel-label').textContent = channel === 'beta' ? '测试版' : '正式版';
      const android = ({ 26: '8.0', 27: '8.1', 28: '9', 29: '10', 30: '11', 31: '12', 32: '12L', 33: '13', 34: '14', 35: '15', 36: '16' })[release.minSdk] || 'API ' + release.minSdk;
      const date = new Intl.DateTimeFormat('zh-CN', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(release.publishedAt));
      byId('version-meta').textContent = 'Android ' + android + ' 及以上 · ' + (release.byteLength / 1048576).toFixed(2) + ' MiB · ' + date;
      byId('release-notes').textContent = release.notes || '本次版本暂无补充说明。';
      byId('release-sha').textContent = release.sha256;
      byId('release-info').hidden = false;
      byId('release-status').hidden = channel !== 'beta';
      byId('release-status').textContent = usedFallback ? '暂无正式版，以下为当前可用的测试版。' : '测试版功能仍在调整，欢迎体验。';
    } catch (error) {
      if (request !== serial) return;
      byId('release-info').hidden = true; byId('release-status').hidden = false;
      byId('release-status').textContent = error.message || '暂时无法读取版本，请使用完整下载页。';
      byId('retry').hidden = false;
    }
  }
  controls.forEach(button => button.addEventListener('click', () => { choose(button.dataset.channel); load(); }));
  byId('retry').addEventListener('click', () => load());
  choose(channel, false);
  return load(true);
}
if (typeof document !== 'undefined') mountDownload(document, location);
