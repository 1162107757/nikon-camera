const API_PATH = '/preset-library/';
const LEGACY_ORIGIN = 'https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com';
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;

export function downloadUrl(release, origin) {
  const ios = release?.platform === 'ios', next = !ios && release?.packageName === 'cc.huevia.next';
  if (!release || (ios ? release.bundleId !== 'cc.huevia.next' || release.distribution !== 'unsigned-ipa' || !/^\d{1,2}\.\d{1,2}(?:\.\d{1,2})?$/.test(release.minimumIOS) : !['cc.huevia','cc.huevia.next'].includes(release.packageName))
      || typeof release.id !== 'string' || !UUID.test(release.id)
      || !/^[a-f0-9]{64}$/.test(release.sha256) || (!ios && !/^[a-f0-9]{64}$/.test(release.signerSha256))
      || !Number.isSafeInteger(release.versionCode) || release.versionCode < 1
      || !Number.isSafeInteger(release.byteLength) || release.byteLength < 1 || release.byteLength > (ios || next ? 128 : 100) * 1048576)
    throw Error('版本信息不完整，请稍后重新读取。');
  const current = new URL(origin), canonical = new URL(release.downloadUrl);
  const path = API_PATH + (ios ? 'ios/' : next ? 'next/' : '') + 'releases/' + release.id + '/file';
  if (!['https:', 'http:'].includes(current.protocol) || current.username || current.password
      || canonical.username || canonical.password || canonical.search || canonical.hash || release.downloadUrl.includes('?') || release.downloadUrl.includes('#')
      || release.downloadUrl !== canonical.href || canonical.pathname !== path
      || ![current.origin, LEGACY_ORIGIN].includes(canonical.origin)) throw Error('下载地址无法确认，请重新读取版本。');
  return new URL(path, current.origin).href;
}

export function mountDownload(document, location, fetchImpl = fetch, historyImpl = history, navigatorImpl = globalThis.navigator) {
  const byId = id => document.getElementById(id);
  const parameters = new URL(location.href).searchParams;
  let channel = parameters.get('channel') === 'beta' ? 'beta' : 'stable';
  let platform = parameters.get('platform') === 'ios' || !parameters.has('platform') && /iPhone|iPad|iPod/.test(navigatorImpl?.userAgent || '') ? 'ios' : 'android';
  let edition = parameters.get('edition') === 'next' ? 'next' : 'legacy';
  let serial = 0;
  const controls = [...document.querySelectorAll('[data-channel]')];
  const platforms = [...document.querySelectorAll('[data-platform]')], editions = [...document.querySelectorAll('[data-edition]')];
  function pageUrl() {
    const url = new URL('/', location.origin);
    if (channel === 'beta') url.searchParams.set('channel', channel);
    url.searchParams.set('platform', platform);
    if (platform === 'android' && edition === 'next') url.searchParams.set('edition', edition);
    return url;
  }
  function drawQr() {
    if (!globalThis.qrcodegen) return;
    const qr = globalThis.qrcodegen.QrCode.encodeText(pageUrl().href, globalThis.qrcodegen.QrCode.Ecc.MEDIUM), ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns,'svg'), path = document.createElementNS(ns,'path');
    svg.setAttribute('viewBox',`0 0 ${qr.size+8} ${qr.size+8}`);svg.setAttribute('shape-rendering','crispEdges');svg.setAttribute('aria-label','当前平台与版本渠道的官网下载二维码');
    let d='';for(let y=0;y<qr.size;y++)for(let x=0;x<qr.size;x++)if(qr.getModule(x,y))d+=`M${x+4},${y+4}h1v1h-1z`;
    path.setAttribute('d',d);path.setAttribute('fill','#262320');svg.append(path);byId('qr-code').replaceChildren(svg);
  }
  function sync(updateUrl = true) {
    controls.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.channel === channel)));
    platforms.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.platform === platform)));
    editions.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.edition === edition)));
    byId('android-editions').hidden = platform === 'ios';
    byId('ios-file-note').hidden = platform !== 'ios';
    if(updateUrl){const url=pageUrl();url.hash=location.hash||'';historyImpl.replaceState(null,'',url);}
    drawQr();
  }
  function choose(next, updateUrl = true) {
    channel = next;
    sync(updateUrl);
  }
  async function latest(selected, selectedPlatform, selectedEdition) {
    const path=selectedPlatform==='ios'?'ios/releases/latest?channel='+selected+'&bundleId=cc.huevia.next':'releases/latest?channel='+selected+'&packageName='+(selectedEdition==='next'?'cc.huevia.next':'cc.huevia');
    const response = await fetchImpl(API_PATH + path,
      { credentials: 'omit', cache: 'no-store', headers: { Accept: 'application/json' }, signal: globalThis.AbortSignal?.timeout?.(20000) });
    if (!response.ok) throw Error('暂时无法读取版本，请稍后重试。');
    return response.json();
  }
  async function load(fallback = false) {
    const request = ++serial;
    const selectedPlatform=platform, selectedEdition=edition;
    byId('release-info').hidden = true; byId('release-status').hidden = false;
    byId('download-file').href = '';
    byId('release-status').textContent = '正在读取可下载版本…'; byId('retry').hidden = true;
    try {
      let data = await latest(channel, selectedPlatform, selectedEdition), usedFallback = false;
      if(request!==serial)return;
      if (fallback && channel === 'stable' && data.reason === 'no_release') {
        const beta = await latest('beta', selectedPlatform, selectedEdition);
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
      const ios=platform==='ios';
      if(ios!==(release.platform==='ios')||!ios&&((edition==='next')!==(release.packageName==='cc.huevia.next')))throw Error('版本平台不匹配，请重新读取。');
      byId('download-file').href = href;
      byId('ios-file-note').hidden = true;
      byId('download-label').textContent=ios?'下载 iOS IPA 文件':edition==='next'?'下载 Android 新版':'下载 Android 安装包';
      byId('download-hint').textContent=ios?'下载 IPA 文件后，请自行签名安装。':'下载后打开 APK，按手机提示安装。';
      byId('version-name').textContent = 'Huevia ' + release.versionName;
      byId('channel-label').textContent = channel === 'beta' ? '测试版' : '正式版';
      const android = ({ 26: '8.0', 27: '8.1', 28: '9', 29: '10', 30: '11', 31: '12', 32: '12L', 33: '13', 34: '14', 35: '15', 36: '16' })[release.minSdk] || 'API ' + release.minSdk;
      const date = new Intl.DateTimeFormat('zh-CN', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(release.publishedAt));
      byId('version-meta').textContent = (ios?'iOS '+release.minimumIOS:'Android '+android) + ' 及以上 · ' + (release.byteLength / 1048576).toFixed(2) + ' MiB · ' + date;
      byId('release-notes').textContent = release.notes || '本次版本暂无补充说明。';
      byId('release-sha').textContent = release.sha256;
      byId('release-info').hidden = false;
      byId('release-status').hidden = channel !== 'beta';
      byId('release-status').textContent = usedFallback ? '暂无正式版，以下为当前可用的测试版。' : '测试版功能仍在调整，欢迎体验。';
    } catch (error) {
      if (request !== serial) return;
      byId('release-info').hidden = true; byId('release-status').hidden = false;
      byId('release-status').textContent = error.message || '暂时无法读取版本，请稍后重新读取。';
      byId('retry').hidden = false;
    } finally {if(request===serial)drawQr();}
  }
  controls.forEach(button => button.addEventListener('click', () => { choose(button.dataset.channel); load(); }));
  platforms.forEach(button=>button.addEventListener('click',()=>{if(platform===button.dataset.platform)return;platform=button.dataset.platform;sync();load(true);}));
  editions.forEach(button=>button.addEventListener('click',()=>{if(edition===button.dataset.edition)return;edition=button.dataset.edition;sync();load(true);}));
  document.querySelectorAll('[data-download-platform]').forEach(link=>link.addEventListener('click',()=>{platform=link.dataset.downloadPlatform;sync();load(true);}));
  byId('retry').addEventListener('click', () => load());
  choose(channel, false);
  return load(true);
}
if (typeof document !== 'undefined') mountDownload(document, location);
