// Isolated PostgreSQL acceptance. No cloud credentials or production data.
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import { PGlite } from '../../.community-pg-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
let checks = 0;
const same = (actual, expected, label) => { assert.deepEqual(actual, expected, label); checks++; };
const functions = async () => (await db.query(`SELECT p.oid::regprocedure::text AS name,
  pg_get_functiondef(p.oid) AS source,p.proacl::text AS acl,p.proowner AS owner
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
  ORDER BY p.oid::regprocedure::text`)).rows;
const id = value => '11111111-1111-4111-8111-' + String(value).padStart(12, '0');
const snapshot = description => ({ name: 'capacity-fixture', category: '胶片', description, compatibleModels: [],
  file: { id: 'ncp-capacity-fixture', url: 'https://fixture.invalid/preset.ncp', sha256: 'a'.repeat(64),
    byteLength: 52, ncpVersion: '0100', fileFormat: 'NCP' } });
const publish = (value, revision = 1) => db.query('SELECT nikon_publish_preset($1,$2,true) AS result', [id(value), revision]);
const insertPublished = async (count, description) => db.query(`INSERT INTO nikon_presets
  (id,draft,published,published_revision,status,published_at)
  SELECT ('11111111-1111-4111-8111-'||lpad(i::text,12,'0'))::uuid,$2::jsonb,$2::jsonb,1,'published',now()
  FROM generate_series(1,$1::integer) i`, [count, JSON.stringify(snapshot(description))]);
const insertDraft = value => db.query('INSERT INTO nikon_presets(id,draft) VALUES($1,$2::jsonb)', [id(value), JSON.stringify(snapshot('字'.repeat(2000)))]);
const catalogBytes = async () => Number((await db.query("SELECT octet_length(convert_to(nikon_catalog_manifest()::text,'UTF8')) AS bytes")).rows[0].bytes);
const migration = await readFile(new URL('../database/016-catalog-capacity.sql', import.meta.url), 'utf8');

try {
  await db.exec('CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;');
  for (const name of (await readdir(new URL('../database/', import.meta.url)))
    .filter(name => /^0\d\d-.+\.sql$/.test(name) && name < '016-').sort())
    await db.exec(await readFile(new URL(`../database/${name}`, import.meta.url), 'utf8'));
  const before = await functions();
  await db.exec(migration);
  const after = await functions();
  await db.exec(migration);
  same(await functions(), after, 'migration is idempotent');
  same(after.length, before.length, 'no public function added or removed');
  for (let index = 0; index < before.length; index++) {
    same(after[index].name, before[index].name, 'function identity preserved');
    same(after[index].acl, before[index].acl, 'function privileges preserved');
    same(after[index].owner, before[index].owner, 'function owner preserved');
    if (before[index].name !== 'nikon_publish_preset(uuid,integer,boolean)')
      same(after[index].source, before[index].source, 'unrelated function body preserved');
  }
  await db.exec('SET ROLE service_role;');
  await db.query('INSERT INTO nikon_assets(id,payload) VALUES($1,$2::jsonb)', ['ncp-capacity-fixture', '{}']);
  await insertPublished(1023, '');
  await insertDraft(1024);
  await publish(1024);
  same((await db.query("SELECT count(*)::integer AS n FROM nikon_presets WHERE status='published'")).rows[0].n, 1024, '1024th preset publishes');
  same((await db.query("SELECT ever_published FROM nikon_assets WHERE id='ncp-capacity-fixture'")).rows[0].ever_published, true, 'published file authorization preserved');
  await insertDraft(1025);
  await assert.rejects(() => publish(1025), /CATALOG_FULL/); checks++;
  same((await db.query('SELECT status FROM nikon_presets WHERE id=$1', [id(1025)])).rows[0].status, 'draft', 'count overflow rolls publication back');
  await assert.rejects(() => publish(1024, 2), /REVISION_CONFLICT/); checks++;

  await db.exec('DELETE FROM nikon_presets;');
  await insertPublished(300, '字'.repeat(2000));
  const bytes = await catalogBytes();
  assert.ok(bytes > 512 * 1024 && bytes < 2 * 1024 * 1024); checks++;
  await publish(1);
  let rejected = false;
  for (let value = 301; value <= 1024; value++) {
    await insertDraft(value);
    try { await publish(value); }
    catch (error) {
      assert.match(error.message, /CATALOG_TOO_LARGE/); checks++;
      same((await db.query('SELECT status FROM nikon_presets WHERE id=$1', [id(value)])).rows[0].status, 'draft', 'byte overflow rolls publication back');
      assert.ok(await catalogBytes() <= 2 * 1024 * 1024); checks++;
      rejected = true; break;
    }
  }
  same(rejected, true, 'actual UTF-8 catalog byte limit remains enforced below item limit');
  await db.exec('RESET ROLE;');
  const definition = (await functions()).find(row => row.name === 'nikon_publish_preset(uuid,integer,boolean)').source;
  await db.exec(definition.replace("manifest->'presets') > 1024", "manifest->'presets') > 1000"));
  await assert.rejects(() => db.exec(migration), /CATALOG_CAPACITY_PATCH_MISMATCH/); checks++;
  await db.exec('ROLLBACK;');
  console.log(`Catalog capacity PostgreSQL acceptance: ${checks} checks passed; no network or production writes.`);
} finally { await db.close(); }
