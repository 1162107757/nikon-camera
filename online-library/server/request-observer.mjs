import {randomUUID} from 'node:crypto';

const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i;
const METHODS = new Set(['GET','HEAD','POST','PUT','PATCH','DELETE','OPTIONS']);
function routeGroup(url, prefix) {
  const path = String(url || '').split('?')[0];
  if (!path.startsWith(prefix + '/')) return 'other';
  const relative = path.slice(prefix.length);
  if (/^\/releases\/[a-f0-9-]{36}\/file$/i.test(relative)) return 'release_download';
  if (relative === '/releases/latest') return 'release_metadata';
  if (relative === '/catalog' || relative === '/catalog.json') return 'preset_catalog';
  if (relative.startsWith('/files/')) return 'preset_asset';
  if (relative.startsWith('/api/community/')) return 'community_api';
  if (relative.startsWith('/api/personal/')) return 'personal_api';
  if (relative.startsWith('/api/')) return 'other_api';
  return 'page';
}

/** Bounded request context for correlating platform failures; never log URLs, headers or bodies. */
export function observeRequest(req, res, {env=process.env,clock=()=>performance.now(),sink=(entry,level)=>console[level](JSON.stringify(entry))} = {}) {
  const start = clock(), prefix = (env.BASE_PATH || '/preset-library').replace(/\/$/,'');
  const peer = req.socket?.remoteAddress;
  const trusted = env.TENCENTCLOUD_RUNENV === 'SCF' && ['127.0.0.1','::1','::ffff:127.0.0.1'].includes(peer)
    && req.headers?.['x-scf-name'] === env.SCF_FUNCTIONNAME;
  const platformId = req.headers?.['x-scf-request-id'];
  const base = {traceId:randomUUID(),...(trusted && typeof platformId === 'string' && UUID.test(platformId) ? {requestId:platformId} : {}),
    method:METHODS.has(req.method) ? req.method : 'OTHER',route:routeGroup(req.url,prefix)};
  const emit = (entry,level='info') => {try {sink({...base,...entry},level);} catch {/* Diagnostics must not fail a request. */}};
  emit({event:'http.request.start'});
  let finished = false;
  const complete = canceled => {
    if (finished) return;
    finished = true;
    const durationMs = Math.max(0,Math.round(clock()-start));
    if (canceled) emit({event:'http.request.canceled',durationMs});
    else if (res.statusCode >= 500) emit({event:'http.request.failed',status:res.statusCode,durationMs},'error');
    else if (durationMs >= 3000) emit({event:'http.request.slow',status:res.statusCode,durationMs});
  };
  res.once('finish',()=>complete(false));
  res.once('close',()=>complete(!res.writableFinished));
}
