// Interactive login for the existing administrator; never accepts or stores a password argument.
import { emitKeypressEvents } from 'node:readline';
import { randomUUID } from 'node:crypto';
import { mkdir, lstat, realpath, open, rename, unlink } from 'node:fs/promises';
import { basename, dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const ORIGIN = 'https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com';
const BASE = ORIGIN + '/preset-library';
const SESSION_FILE = fileURLToPath(new URL('../.local/community-admin-session.json', import.meta.url));
const TOKEN = /^[A-Za-z0-9_-]{43}$/;
const COOKIE = /^__Host-nikon_session=[A-Za-z0-9_-]{43}$/;
export class LoginError extends Error {
  constructor(code) { super(code); this.code = code; }
}
const cancelled = () => new LoginError('LOGIN_CANCELLED');
const checkCancelled = signal => { if (signal?.aborted) throw cancelled(); };

export function promptHidden(label, { input = process.stdin, output = process.stdout, signal } = {}) {
  if (!input.isTTY || !output.isTTY || typeof input.setRawMode !== 'function') throw new LoginError('INTERACTIVE_TERMINAL_REQUIRED');
  checkCancelled(signal);
  return new Promise((resolveAnswer, reject) => {
    // Node 20's readline Interface treats DEL as text under TERM=dumb. Decode
    // public keypress events and edit locally, without a TERM-dependent editor
    // or any character echo/history. Preserve the caller's terminal mode.
    const wasRaw = input.isRaw === true, wasFlowing = input.readableFlowing === true;
    let settled = false, answer = '';
    const onCancel = () => finish(cancelled());
    const onError = () => finish(new LoginError('TERMINAL_INPUT_FAILED'));
    const onKey = (text, key = {}) => {
      if (key.name === 'return' || key.name === 'enter' || text === '\r' || text === '\n') return finish(null, answer);
      if ((key.ctrl && ['c', 'd'].includes(key.name)) || text === '\x03' || text === '\x04') return onCancel();
      if (key.name === 'backspace' || text === '\x7f' || text === '\b') {
        answer = Array.from(answer).slice(0, -1).join(''); return;
      }
      if (key.ctrl && key.name === 'u') { answer = ''; return; }
      if (typeof text !== 'string' || key.ctrl || key.meta || /[\x00-\x1f\x7f]/.test(text)) return;
      answer += text;
      if (answer.length > 256) finish(new LoginError('CREDENTIAL_FIELDS_REJECTED'));
    };
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      signal?.removeEventListener('abort', onCancel);
      input.removeListener('keypress', onKey); input.removeListener('end', onCancel); input.removeListener('error', onError);
      try { input.setRawMode(wasRaw); } catch { error ||= new LoginError('TERMINAL_RESTORE_FAILED'); }
      if (!wasFlowing) input.pause();
      answer = ''; output.write('\n');
      if (error) reject(error); else resolveAnswer(value);
    };
    try {
      emitKeypressEvents(input);
      input.on('keypress', onKey); input.once('end', onCancel); input.once('error', onError);
      signal?.addEventListener('abort', onCancel, { once: true });
      input.setRawMode(true); output.write(label); input.resume();
    } catch { finish(new LoginError('TERMINAL_INPUT_FAILED')); }
  });
}

function validSession(session) {
  return session && Object.keys(session).sort().join(',') === 'cookie,csrfToken'
    && typeof session.cookie === 'string' && COOKIE.test(session.cookie)
    && typeof session.csrfToken === 'string' && TOKEN.test(session.csrfToken);
}

export async function saveSessionAtomic(session, { signal, sessionFile = SESSION_FILE } = {}) {
  if (!validSession(session)) throw new LoginError('SESSION_FIELDS_REJECTED');
  checkCancelled(signal);
  const folder = dirname(sessionFile);
  let temporary, handle;
  try {
    await mkdir(folder, { recursive: true, mode: 0o700 });
    const canonical = await realpath(folder);
    const same = process.platform === 'win32' ? canonical.toLowerCase() === resolve(folder).toLowerCase() : canonical === resolve(folder);
    if (!same || (await lstat(folder)).isSymbolicLink()) throw new LoginError('SESSION_PATH_REJECTED');
    try { if ((await lstat(sessionFile)).isSymbolicLink()) throw new LoginError('SESSION_PATH_REJECTED'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    temporary = resolve(folder, '.community-admin-session-' + randomUUID() + '.tmp');
    handle = await open(temporary, 'wx', 0o600);
    await handle.writeFile(JSON.stringify({ cookie: session.cookie, csrfToken: session.csrfToken }, null, 2) + '\n');
    await handle.sync(); await handle.close(); handle = undefined;
    checkCancelled(signal);
    await rename(temporary, sessionFile);
    temporary = undefined;
  } catch (error) {
    if (error instanceof LoginError) throw error;
    throw new LoginError('SESSION_SAVE_FAILED');
  } finally {
    await handle?.close().catch(() => {});
    if (temporary) await unlink(temporary).catch(() => {});
  }
}

async function readJson(response, maximum) {
  if (!/^application\/json(?:;|$)/i.test(response.headers.get('content-type') || '')) throw new LoginError('RESPONSE_FIELDS_REJECTED');
  const chunks = []; let length = 0;
  for await (const chunk of response.body || []) {
    length += chunk.length;
    if (length > maximum) { await response.body?.cancel().catch(() => {}); throw new LoginError('RESPONSE_FIELDS_REJECTED'); }
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new LoginError('RESPONSE_FIELDS_REJECTED'); }
}

function loginCookie(response) {
  const headers = typeof response.headers.getSetCookie === 'function' ? response.headers.getSetCookie() : [response.headers.get('set-cookie') || ''];
  const cookies = headers.filter(value => value.startsWith('__Host-nikon_session='));
  if (cookies.length !== 1) throw new LoginError('SESSION_FIELDS_REJECTED');
  const [cookie, ...attributes] = cookies[0].split(';').map(value => value.trim());
  const flags = attributes.map(value => value.toLowerCase());
  const age = flags.find(value => value.startsWith('max-age='))?.slice(8) || '';
  if (!COOKIE.test(cookie) || !flags.includes('secure') || !flags.includes('httponly')
    || !flags.includes('path=/') || !flags.includes('samesite=strict') || flags.some(value => value.startsWith('domain='))
    || !/^[0-9]+$/.test(age) || Number(age) <= 0 || Number(age) > 28800) throw new LoginError('SESSION_FIELDS_REJECTED');
  return cookie;
}

export async function loginAdministrator(credentials, { fetchImpl = globalThis.fetch, signal, persist = saveSessionAtomic } = {}) {
  if (!credentials || Object.keys(credentials).sort().join(',') !== 'password,username'
    || typeof credentials.username !== 'string' || typeof credentials.password !== 'string') throw new LoginError('CREDENTIAL_FIELDS_REJECTED');
  const username = credentials.username.trim().toLowerCase();
  let password = credentials.password;
  if (!/^[a-z0-9_.-]{1,64}$/.test(username) || !password.length || password.length > 256) throw new LoginError('CREDENTIAL_FIELDS_REJECTED');
  async function request(path, { body, cookie, maximum = 65536 } = {}) {
    checkCancelled(signal);
    let response;
    try {
      response = await fetchImpl(BASE + path, { method: body === undefined ? 'GET' : 'POST',
        redirect: 'error', signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(45000)]) : AbortSignal.timeout(45000),
        headers: { Origin: ORIGIN, ...(cookie ? { Cookie: cookie } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
        body: body === undefined ? undefined : JSON.stringify(body) });
    } catch { checkCancelled(signal); throw new LoginError('LOGIN_NETWORK_FAILED'); }
    if (!response.ok) { await response.body?.cancel().catch(() => {}); throw new LoginError(response.status === 429 ? 'LOGIN_THROTTLED' : 'LOGIN_REJECTED'); }
    try { return { response, value: await readJson(response, maximum) }; }
    catch (error) { checkCancelled(signal); if (error instanceof LoginError) throw error; throw new LoginError('LOGIN_NETWORK_FAILED'); }
  }
  try {
    const login = await request('/api/login', { body: { username, password } });
    password = '';
    if (!login.value || login.value.authenticated !== true || login.value.user?.username !== username || typeof login.value.csrfToken !== 'string' || !TOKEN.test(login.value.csrfToken)) throw new LoginError('SESSION_FIELDS_REJECTED');
    const session = { cookie: loginCookie(login.response), csrfToken: login.value.csrfToken };
    const verified = (await request('/api/session', { cookie: session.cookie })).value;
    if (!verified || verified.authenticated !== true || verified.user?.username !== username || verified.csrfToken !== session.csrfToken) throw new LoginError('SESSION_VERIFICATION_FAILED');
    const releases = (await request('/api/releases', { cookie: session.cookie, maximum: 2 * 1024 * 1024 })).value;
    if (!releases || !Array.isArray(releases.items)) throw new LoginError('ADMIN_RELEASE_ACCESS_FAILED');
    checkCancelled(signal);
    await persist(session, { signal });
    return { authenticated: true, csrfVerified: true, adminReleasesReadable: true, sessionSaved: true };
  } finally { password = ''; }
}

export async function main(args = process.argv.slice(2), options = {}) {
  const output = options.output || process.stdout;
  if (args.length === 1 && args[0] === '--help') {
    output.write('node scripts/login-release-admin.mjs --login\n在本机交互终端输入当前管理员用户名和密码；两者不回显。密码不接受命令行参数或管道，不保存密码。\n');
    return;
  }
  if (args.length !== 1 || args[0] !== '--login') throw new LoginError('LOGIN_FLAG_REQUIRED');
  const sourceDirectory = dirname(fileURLToPath(import.meta.url));
  if (basename(sourceDirectory) !== 'scripts' || basename(dirname(sourceDirectory)) !== 'online-library') throw new LoginError('PROJECT_ENTRY_REQUIRED');
  const input = options.input || process.stdin;
  if (!input.isTTY || !output.isTTY) throw new LoginError('INTERACTIVE_TERMINAL_REQUIRED');
  const controller = new AbortController();
  const interrupt = () => controller.abort();
  process.once('SIGINT', interrupt);
  let password = '';
  try {
    output.write('Huevia 管理员登录：' + BASE + '/admin/\nCtrl+C 可取消；此操作只准备管理员会话。\n');
    const username = await promptHidden('当前管理员用户名（不回显）：', { input, output, signal: controller.signal });
    password = await promptHidden('当前管理员密码（不回显）：', { input, output, signal: controller.signal });
    await loginAdministrator({ username, password }, { fetchImpl: options.fetchImpl, persist: options.persist, signal: controller.signal });
    output.write('管理员会话与发布访问已验证并原子保存；密码未持久保存。\n部署、草稿上传和公开发布仍需另行执行。\n');
  } finally { password = ''; process.removeListener('SIGINT', interrupt); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => {
    const code = error instanceof LoginError ? error.code : 'LOGIN_PREPARATION_FAILED';
    process.stderr.write(code === 'LOGIN_CANCELLED' ? '登录已取消，原本地会话保留。\n' : '登录未完成（' + code + '），原本地会话保留。\n');
    process.exitCode = code === 'LOGIN_CANCELLED' ? 130 : 1;
  });
}
