import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
let PGlite;
try { ({ PGlite } = await import('../../.community-pg-test/node_modules/@electric-sql/pglite/dist/index.js')); }
catch (error) { if (error.code !== 'ERR_MODULE_NOT_FOUND') throw error; }
test('modern APK upload allowance preserves usage, admin identity and request/task/package ceilings', { skip: !PGlite }, async () => {
 const db = new PGlite();
 try {
  await db.exec("CREATE TABLE nikon_app_release_budgets(budget_key text PRIMARY KEY,requests bigint NOT NULL,bytes bigint NOT NULL,expires_at timestamptz NOT NULL); CREATE TABLE nikon_app_uploads(id uuid DEFAULT gen_random_uuid(),actor text,byte_length integer,channel text,notes text,status text DEFAULT 'uploading',created_at timestamptz DEFAULT now(),expires_at timestamptz DEFAULT now()+interval '1 hour'); CREATE FUNCTION nikon_app_admin_allowed(text) RETURNS boolean LANGUAGE sql AS 'SELECT $1=''admin''';");
  const prior = await readFile(new URL('../database/017-app-release-capacity.sql', import.meta.url), 'utf8');
  for (const name of ['nikon_app_upload_budget', 'nikon_app_upload_begin']) {
   const start = prior.indexOf('CREATE OR REPLACE FUNCTION public.' + name + '('), end = prior.indexOf('END; $$;', start) + 8;
   await db.exec(prior.slice(start, end));
  }
  await db.exec("INSERT INTO nikon_app_release_budgets VALUES('upload:bytes:'||to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYYMMDD'),0,62585022,now()+interval '2 days'); INSERT INTO nikon_app_uploads(actor,byte_length,channel,notes,status) VALUES('admin',31292511,'beta','prior','complete'),('admin',19062600,'beta','prior','processing');");
  const budget = async (size, count = false, actor = 'admin') => (await db.query('SELECT nikon_app_upload_budget($1,$2,$3) AS v', [actor, size, count])).rows[0].v;
  const begin = async (size, actor = 'admin') => (await db.query("SELECT nikon_app_upload_begin($1,$2,'beta','reviewed update') AS v", [actor, size])).rows[0].v;
  assert.equal((await budget(31292511)).error, 'BUDGET'); assert.equal((await begin(31292511)).error, 'BUDGET');
  const before = (await db.query('SELECT * FROM nikon_app_release_budgets')).rows;
  const migration = await readFile(new URL('../database/020-admin-apk-upload-budget.sql', import.meta.url), 'utf8'); await db.exec(migration); await db.exec(migration);
  assert.deepEqual((await db.query('SELECT * FROM nikon_app_release_budgets')).rows, before);
  assert.equal((await budget(31292511)).allowed, true); assert.equal((await budget(31292511)).allowed, true);
  assert.ok((await begin(31292511)).uploadId);
  assert.equal((await budget(33554433)).error, 'INVALID'); assert.equal((await begin(33554433)).error, 'INVALID');
  assert.equal((await budget(1, false, 'guest')).error, 'FORBIDDEN'); assert.equal((await begin(1, 'guest')).error, 'FORBIDDEN');
  await db.exec("INSERT INTO nikon_app_release_budgets VALUES('upload:requests:'||floor(extract(epoch FROM clock_timestamp())/900)::bigint::text,256,0,now()+interval '30 minutes');");
  assert.equal((await budget(0, true)).error, 'BUDGET');
  await db.exec("UPDATE nikon_app_release_budgets SET bytes=268435456 WHERE budget_key LIKE 'upload:bytes:%'"); assert.equal((await budget(1)).error, 'BUDGET');
  await db.exec("INSERT INTO nikon_app_uploads(actor,byte_length,channel,notes) VALUES('admin',1,'beta','active'),('admin',1,'beta','active'),('admin',1,'beta','active')"); assert.equal((await begin(1)).error, 'BUDGET', 'four active uploads remain the task ceiling');
  await db.exec("UPDATE nikon_app_uploads SET status='complete'");
  await db.exec("INSERT INTO nikon_app_uploads(actor,byte_length,channel,notes,status) VALUES('admin',33554432,'beta','existing','complete'),('admin',18000000,'beta','existing','complete')"); assert.equal((await begin(33554432)).error, 'BUDGET');
 } finally { await db.close(); }
});
