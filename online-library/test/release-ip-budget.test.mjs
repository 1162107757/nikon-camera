import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { createReleaseRoutes, ReleaseStore } from '../server/releases.mjs';

let PGlite;
try { ({ PGlite } = await import('../../.community-pg-test/node_modules/@electric-sql/pglite/dist/index.js')); }
catch (error) { if (error.code !== 'ERR_MODULE_NOT_FOUND') throw error; }

test('public release limits isolate IPs and ignore historical global totals without resetting usage', { skip: !PGlite }, async () => {
  const db = new PGlite();
  try {
    await db.exec('CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE TABLE nikon_app_release_budgets(budget_key text PRIMARY KEY,requests bigint NOT NULL DEFAULT 0,bytes bigint NOT NULL DEFAULT 0,expires_at timestamptz NOT NULL);');
    await db.exec(await readFile(new URL('../database/018-app-download-budget.sql', import.meta.url), 'utf8'));
    const first = 'a'.repeat(64), second = 'b'.repeat(64), hash = 'c'.repeat(64), size = 31292511;
    await db.exec("INSERT INTO nikon_app_release_budgets VALUES ('file:global:'||to_char(clock_timestamp(),'YYYYMMDD'),1000,2147483648,clock_timestamp()+interval '2 days'),('meta:global:'||to_char(clock_timestamp(),'YYYYMMDDHH24MI'),1200,0,clock_timestamp()+interval '2 minutes')");
    const before = (await db.query('SELECT * FROM nikon_app_release_budgets ORDER BY budget_key')).rows;
    const migration = await readFile(new URL('../database/019-app-release-ip-budget.sql', import.meta.url), 'utf8');
    await db.exec(migration); await db.exec(migration);
    assert.deepEqual((await db.query('SELECT * FROM nikon_app_release_budgets ORDER BY budget_key')).rows, before);
    const reserve = async (key = first, sha = hash, bytes = size) => (await db.query('SELECT nikon_release_download_budget($1,$2,$3) AS v', [key, sha, bytes])).rows[0].v;
    const firstGrant = await reserve(); assert.equal(firstGrant.allowed, true); assert.equal(firstGrant.chargedBytes, size);
    const lease = (await db.query("SELECT * FROM nikon_app_release_budgets WHERE budget_key LIKE 'file:lease:%'")).rows[0];
    for (let i = 1; i < 60; i++) assert.equal((await reserve()).chargedBytes, 0, 'browser retries do not debit another complete package');
    assert.deepEqual((await db.query("SELECT * FROM nikon_app_release_budgets WHERE budget_key LIKE 'file:lease:%'")).rows[0], lease, 'retries do not prolong the fixed window');
    const denied = await reserve(); assert.equal(denied.error, 'IP_BUDGET'); assert.equal(denied.scope, 'ip'); assert.ok(denied.retryAfterSeconds >= 1 && denied.retryAfterSeconds <= 3600);
    const blockedBefore = (await db.query('SELECT * FROM nikon_app_release_budgets ORDER BY budget_key')).rows;
    await reserve(); assert.deepEqual((await db.query('SELECT * FROM nikon_app_release_budgets ORDER BY budget_key')).rows, blockedBefore, 'denied requests do not mutate usage');
    assert.equal((await reserve(second)).allowed, true, 'a saturated IP must not block another IP');
    for (const key of [first, second]) assert.equal((await db.query("SELECT nikon_release_budget_atomic($1,'metadata',0) AS v", [key])).rows[0].v.allowed, true, 'global metadata total cannot block a new IP');
    assert.deepEqual((await db.query("SELECT * FROM nikon_app_release_budgets WHERE budget_key LIKE '%:global:%' ORDER BY budget_key")).rows, before, 'global counters are never consulted or changed');
    await db.exec("UPDATE nikon_app_release_budgets SET requests=0 WHERE budget_key LIKE 'file:ip:%'; UPDATE nikon_app_release_budgets SET expires_at=clock_timestamp()-interval '1 second' WHERE budget_key LIKE 'file:lease:%'");
    assert.equal((await reserve()).chargedBytes, size, 'a later retry window is charged again');
    await db.exec("UPDATE nikon_app_release_budgets SET bytes=268435456 WHERE budget_key LIKE 'file:ip:%'");
    assert.equal((await reserve()).allowed, true, 'an already charged retry remains usable');
    assert.equal((await reserve(first, 'd'.repeat(64))).error, 'IP_BUDGET', 'a different package cannot borrow a lease');
    assert.equal((await reserve(first, hash, 0)).allowed, true, '304 responses debit no file bytes');
    for (const values of [[null, hash, size], [first, null, size], [first, hash, null], [first, hash, 33554433]]) {
      assert.equal((await db.query('SELECT nikon_release_download_budget($1,$2,$3) AS v', values)).rows[0].v.error, 'INVALID');
    }
    const privileges = (await db.query("SELECT has_function_privilege('anon','nikon_release_download_budget(text,text,integer)','EXECUTE') AS anon,has_function_privilege('authenticated','nikon_release_download_budget(text,text,integer)','EXECUTE') AS authenticated,has_function_privilege('service_role','nikon_release_download_budget(text,text,integer)','EXECUTE') AS service")).rows[0];
    assert.deepEqual(privileges, { anon: false, authenticated: false, service: true });
  } finally { await db.close(); }
});

test('download routes reserve per-IP retries, count 304 with zero bytes and propagate real retry time', async t => {
  const bytes = Buffer.from('an immutable test object'), hash = createHash('sha256').update(bytes).digest('hex');
  const row = { id: '12345678-1234-4234-8234-123456789abc', status: 'published', sha256: hash, byte_length: bytes.length, storage_path: `app-releases/${hash}.bin`, version_code: 156, channel: 'beta' };
  const calls = []; let reads = 0, denied = false;
  const store = { rest: async () => [{ ...row }], rpc: async (name, body) => { calls.push({ name, body }); return denied ? { error: 'IP_BUDGET', retryAfterSeconds: 123 } : { allowed: true }; } };
  const routes = createReleaseRoutes({ store, storage: {}, publicBaseUrl: 'https://updates.test', readBundledApk: async () => { reads++; return bytes; } });
  const server = createServer(async (req, res) => {
    try { const url = new URL(req.url, 'http://localhost'); await routes.publicRoute(req, res, { path: url.pathname, url }); }
    catch (error) { if (error.retryAfterSeconds) res.setHeader('Retry-After', String(error.retryAfterSeconds)); res.writeHead(error.status || 500); res.end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); t.after(() => { server.closeAllConnections(); server.close(); });
  const url = `http://127.0.0.1:${server.address().port}/releases/${row.id}/file`;
  let response = await fetch(url); assert.equal(response.status, 200); await response.arrayBuffer();
  assert.equal(calls[0].name, 'nikon_release_download_budget'); assert.equal(calls[0].body.p_sha256, hash); assert.equal(calls[0].body.p_bytes, bytes.length);
  response = await fetch(url, { headers: { 'If-None-Match': `"sha256-${hash}"` } }); assert.equal(response.status, 304); assert.equal(calls[1].body.p_bytes, 0); assert.equal(reads, 1);
  row.status = 'withdrawn'; assert.equal((await fetch(url, { headers: { 'If-None-Match': `"sha256-${hash}"` } })).status, 404); assert.equal(calls.length, 2);
  row.status = 'published'; denied = true; response = await fetch(url); assert.equal(response.status, 429); assert.equal(response.headers.get('retry-after'), '123'); assert.equal(reads, 1);
  await assert.rejects(new ReleaseStore(store).rpc('nikon_release_download_budget', {}), e => e.code === 'RELEASE_IP_BUDGET' && e.retryAfterSeconds === 123 && /当前网络/.test(e.message));
});
