const escape = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

/** Browser navigations get a readable error page; API and Android clients keep JSON errors. */
export function renderReleaseDownloadError(req, res, { status, code, retryAfterSeconds, message, prefix = '/preset-library' }) {
  const path = String(req.url || '').split('?')[0];
  const html = String(req.headers?.accept || '').split(',').some(part => {
    const [type, ...params] = part.split(';');
    return type.trim().toLowerCase() === 'text/html' && !params.some(p => /^\s*q\s*=\s*0(?:\.0*)?\s*$/.test(p));
  });
  if (req.method !== 'GET' || !/\/releases\/[a-f0-9-]{36}\/file$/i.test(path) || !html) return false;
  const ipLimited = status === 429 && code === 'RELEASE_IP_BUDGET';
  const title = ipLimited ? '当前网络下载已达上限' : status === 429 ? '下载请求较多，请稍后再试' : '暂时无法下载安装包';
  if (ipLimited && Number.isInteger(retryAfterSeconds) && retryAfterSeconds >= 1 && retryAfterSeconds <= 3600) {
    message = `当前网络（IP）的下载次数或流量已达上限，约 ${Math.ceil(retryAfterSeconds / 60)} 分钟后可重试。`;
  }
  const platform = /\/ios\/releases\//.test(path) ? '&platform=ios' : /\/next\/releases\//.test(path) ? '&platform=android&edition=next' : '';
  const returnUrl = `https://huevia.cc/?channel=beta${platform}`;
  const page = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>${title} · Huevia</title><link rel="stylesheet" href="${escape(prefix)}/download/tokens.css"><link rel="stylesheet" href="${escape(prefix)}/download/download.css"></head><body><main><section class="intro"><h1>${title}</h1><p class="intro-copy">${escape(message)}</p><p class="channel-note">请返回下载页重试，当前未下载安装包。</p><p class="version-line"><a class="download-button" href="${escape(returnUrl)}">返回下载页</a></p></section></main></body></html>`;
  res.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8', 'Content-Length': Buffer.byteLength(page), 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  res.end(page); return true;
}
