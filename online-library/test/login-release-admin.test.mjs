import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, readdir, rm, rmdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PassThrough, Writable } from 'node:stream';
import { ORIGIN, loginAdministrator, saveSessionAtomic, promptHidden, main } from '../scripts/login-release-admin.mjs';

const token = 'A'.repeat(43), csrf = 'B'.repeat(43);
const credentials = { username: 'fixture_admin', password: 'fixture-password-never-real' };
const cookie = '__Host-nikon_session=' + token;
const header = cookie + '; Path=/; HttpOnly; SameSite=Strict; Secure; Max-Age=28800';
function response(value, { status = 200, setCookie } = {}) {
  return new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json', ...(setCookie ? { 'Set-Cookie': setCookie } : {}) } });
}
function transport({ login, loginHeader = header, session, listing, fail, cancel } = {}) {
  const requests = [];
  const fetchImpl = async (url, options) => {
    const path = new URL(url).pathname;
    assert.equal(new URL(url).origin, ORIGIN);
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.Origin, ORIGIN);
    requests.push({ path, method: options.method });
    if (path === '/preset-library/api/login') {
      assert.equal(options.method, 'POST');
      assert.deepEqual(JSON.parse(options.body), credentials);
      if (fail) return response({ error: { message: 'PRIVATE_SERVER_RESPONSE' } }, { status: 401 });
      cancel?.abort();
      return response(login ?? { authenticated: true, user: { username: credentials.username }, csrfToken: csrf }, { setCookie: loginHeader });
    }
    assert.equal(options.method, 'GET');
    assert.equal(options.headers.Cookie, cookie);
    if (path === '/preset-library/api/session') return response(session ?? { authenticated: true, user: { username: credentials.username }, csrfToken: csrf });
    if (path === '/preset-library/api/releases') return response(listing ?? { items: [] });
    throw new Error('Unexpected endpoint');
  };
  return { fetchImpl, requests };
}

test('normal login verifies both GET endpoints and atomically stores only session/CSRF', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'huevia-admin-login-'));
  const sessionFile = join(directory, 'session.json');
  try {
    await writeFile(sessionFile, 'OLD_SESSION');
    const fixture = transport();
    const result = await loginAdministrator(credentials, { fetchImpl: fixture.fetchImpl,
      persist: (value, options) => saveSessionAtomic(value, { ...options, sessionFile }) });
    assert.deepEqual(result, { authenticated: true, csrfVerified: true, adminReleasesReadable: true, sessionSaved: true });
    const bytes = await readFile(sessionFile, 'utf8');
    assert.deepEqual(JSON.parse(bytes), { cookie, csrfToken: csrf });
    assert.ok(!bytes.includes(credentials.username) && !bytes.includes(credentials.password));
    assert.deepEqual(fixture.requests.map(row => row.method), ['POST', 'GET', 'GET']);
    assert.deepEqual(await readdir(directory), ['session.json']);
  } finally { await rm(sessionFile, { force: true }); await rmdir(directory); }
});

test('failed login never persists or exposes the server response/credentials', async () => {
  const fixture = transport({ fail: true }); let saved = false;
  await assert.rejects(loginAdministrator(credentials, { fetchImpl: fixture.fetchImpl, persist: async () => { saved = true; } }),
    error => error.code === 'LOGIN_REJECTED' && !error.message.includes('PRIVATE_SERVER_RESPONSE') && !error.message.includes(credentials.password));
  assert.equal(saved, false);
  assert.equal(fixture.requests.length, 1);
});

test('cancellation before and after POST preserves the existing local session', async () => {
  for (const before of [true, false]) {
    const controller = new AbortController(); if (before) controller.abort();
    const fixture = transport({ cancel: before ? undefined : controller }); let saved = false;
    await assert.rejects(loginAdministrator(credentials, { fetchImpl: fixture.fetchImpl, signal: controller.signal, persist: async () => { saved = true; } }), { code: 'LOGIN_CANCELLED' });
    assert.equal(saved, false); assert.equal(fixture.requests.length, before ? 0 : 1);
  }
});

test('bad CSRF/cookie/session/admin fields cannot replace the previous session', async () => {
  const fixtures = [
    { login: { authenticated: true, user: { username: credentials.username }, csrfToken: [csrf] } },
    { loginHeader: header.replace('; Secure', '') },
    { loginHeader: header + '; Domain=example.invalid' },
    { loginHeader: header.replace(token, 'short') },
    { loginHeader: header.replace('Max-Age=28800', 'Max-Age=0') },
    { login: null, loginHeader: header.replace('Max-Age=28800', 'Max-Age=999999') },
    { session: { authenticated: true, user: { username: credentials.username }, csrfToken: 'C'.repeat(43) } },
    { session: { authenticated: false } },
    { listing: { items: {} } }
  ];
  const directory = await mkdtemp(join(tmpdir(), 'huevia-admin-reject-')); const sessionFile = join(directory, 'session.json');
  try {
    await writeFile(sessionFile, 'KEEP_PREVIOUS_SESSION');
    for (const input of fixtures) {
      const fixture = transport(input);
      await assert.rejects(loginAdministrator(credentials, { fetchImpl: fixture.fetchImpl,
        persist: (value, options) => saveSessionAtomic(value, { ...options, sessionFile }) }));
      assert.equal(await readFile(sessionFile, 'utf8'), 'KEEP_PREVIOUS_SESSION');
    }
    assert.deepEqual(await readdir(directory), ['session.json']);
  } finally { await rm(sessionFile, { force: true }); await rmdir(directory); }
});

test('credential arguments and extra persisted fields are rejected before network/write', async () => {
  let called = false;
  await assert.rejects(loginAdministrator({ ...credentials, origin: 'https://example.invalid' }, { fetchImpl: async () => { called = true; } }), { code: 'CREDENTIAL_FIELDS_REJECTED' });
  await assert.rejects(saveSessionAtomic({ cookie, csrfToken: csrf, password: credentials.password }), { code: 'SESSION_FIELDS_REJECTED' });
  await assert.rejects(main(['--login', '--password', credentials.password]), { code: 'LOGIN_FLAG_REQUIRED' });
  assert.equal(called, false);
});

test('noninteractive input is refused, without a file/argv fallback', async () => {
  const input = new PassThrough(); const output = new Writable({ write(_chunk, _encoding, done) { done(); } });
  await assert.rejects(main(['--login'], { input, output }), { code: 'INTERACTIVE_TERMINAL_REQUIRED' });
});

function terminal() {
  const input = new PassThrough(); input.isTTY = true; input.isRaw = false;
  input.setRawMode = value => { input.isRaw = value; return input; };
  let display = ''; const output = new Writable({ write(chunk, _encoding, done) { display += chunk.toString(); done(); } });
  output.isTTY = true; output.columns = 80;
  return { input, output, display: () => display };
}
test('terminal editing works without echoing username or password', async () => {
  const fixture = terminal(); const answer = promptHidden('Password: ', fixture);
  setImmediate(() => fixture.input.write('sensitive-text\x7f!\r'));
  assert.equal(await answer, 'sensitive-tex!');
  assert.ok(!fixture.display().includes('sensitive')); assert.equal(fixture.input.isRaw, false);
});
test('terminal Ctrl+C cancels and restores terminal mode without echoing secrets', async () => {
  const fixture = terminal(); const answer = promptHidden('Password: ', fixture);
  setImmediate(() => fixture.input.write('sensitive-text\x03'));
  await assert.rejects(answer, { code: 'LOGIN_CANCELLED' });
  assert.ok(!fixture.display().includes('sensitive')); assert.equal(fixture.input.isRaw, false);
});
test('full interactive CLI prompts twice and saves only the verified normal-login session', async () => {
  const fixture = terminal(), api = transport(); const write = fixture.output.write.bind(fixture.output);
  fixture.output.write = (chunk, ...args) => {
    const result = write(chunk, ...args);
    if (String(chunk).includes('当前管理员用户名')) setImmediate(() => fixture.input.write(credentials.username + '\r'));
    if (String(chunk).includes('当前管理员密码')) setImmediate(() => fixture.input.write(credentials.password + '\r'));
    return result;
  };
  let saved;
  await main(['--login'], { input: fixture.input, output: fixture.output, fetchImpl: api.fetchImpl, persist: async value => { saved = value; } });
  assert.deepEqual(saved, { cookie, csrfToken: csrf });
  assert.equal(api.requests.length, 3); assert.equal(fixture.input.isRaw, false);
  assert.ok(!fixture.display().includes(credentials.username) && !fixture.display().includes(credentials.password));
});
