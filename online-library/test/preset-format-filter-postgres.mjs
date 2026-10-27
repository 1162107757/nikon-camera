// Isolated PostgreSQL acceptance. No cloud credentials, network or production data.
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import { PGlite } from '../../.community-pg-test/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
let checks = 0;
const same = (actual, expected, label) => { assert.deepEqual(actual, expected, label); checks++; };
const definition = async () => (await db.query("SELECT pg_get_functiondef('public.nikon_community(text,uuid,uuid,jsonb)'::regprocedure) AS source")).rows[0].source;
const functions = async () => (await db.query(`SELECT p.oid::regprocedure::text AS name,pg_get_functiondef(p.oid) AS source,
  p.proacl::text AS acl,p.proowner AS owner FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' ORDER BY p.oid::regprocedure::text`)).rows;
const migration = await readFile(new URL('../database/015-preset-format-filter.sql', import.meta.url), 'utf8');
try {
  await db.exec('CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;');
  for (const name of (await readdir(new URL('../database/', import.meta.url))).filter(name => /^0\d\d-.+\.sql$/.test(name) && name < '015-').sort())
    await db.exec(await readFile(new URL(`../database/${name}`, import.meta.url), 'utf8'));
  const before = await functions(), sourceBefore = await definition();
  await db.exec(migration); const sourceAfter = await definition();
  await db.exec(migration); same(await definition(), sourceAfter, 'migration is idempotent');
  const beforeFeed = sourceBefore.indexOf(" IF p_action='feed' THEN"), beforeDetail = sourceBefore.indexOf("ELSIF p_action='detail' THEN");
  const afterFeed = sourceAfter.indexOf(" IF p_action='feed' THEN"), afterDetail = sourceAfter.indexOf("ELSIF p_action='detail' THEN");
  assert.ok(beforeFeed >= 0 && beforeDetail > beforeFeed && afterDetail > afterFeed); checks++;
  same(sourceAfter.slice(0, afterFeed), sourceBefore.slice(0, beforeFeed), 'dispatcher setup unchanged');
  same(sourceAfter.slice(afterDetail), sourceBefore.slice(beforeDetail), 'all non-feed branches unchanged');
  const after = await functions(); same(after.length, before.length, 'no function added or removed');
  for (let i = 0; i < before.length; i++) {
    same(after[i].name, before[i].name, 'same function identity');
    same(after[i].acl, before[i].acl, `ACL preserved: ${before[i].name}`);
    same(after[i].owner, before[i].owner, `owner preserved: ${before[i].name}`);
    if (before[i].name !== 'nikon_community(text,uuid,uuid,jsonb)') same(after[i].source, before[i].source, `other function unchanged: ${before[i].name}`);
  }
  await db.exec('BEGIN; SET LOCAL ROLE service_role;');
  const actor = '00000000-0000-4000-8000-000000000001';
  await db.query('INSERT INTO nikon_users(id,nickname) VALUES($1,$2)', [actor, 'format-filter-local-fixture']);
  const fixtures = [];
  for (let i = 1; i <= 65; i++) {
    const id = `11111111-1111-4111-8111-${String(i).padStart(12, '0')}`;
    const format = i <= 40 ? 'NP3' : 'NCP', category = ['', '胶片', '人像'][i % 3];
    const publishedAt = new Date(Date.UTC(2026, 0, 1, 0, 0, 0) - Math.floor(i / 5) * 1000).toISOString();
    const file = { url: `https://fixture.invalid/${i}.${format.toLowerCase()}`, sha256: String(i).padStart(64, '0'),
      byteLength: format === 'NP3' ? 392 : 52, ncpVersion: format === 'NP3' ? '0310' : '0100',
      ...(i < 60 ? { fileFormat: format } : {}) };
    const snapshot = { name: `format-fixture-${i}`, category, description: '', compatibleModels: [], file };
    const source = i % 2 ? 'curated' : 'community';
    if (source === 'curated') await db.query(`INSERT INTO nikon_presets(id,draft,published,published_revision,status,published_at)
      VALUES($1,$2::jsonb,$2::jsonb,1,'published',$3)`, [id, JSON.stringify(snapshot), publishedAt]);
    else await db.query(`INSERT INTO nikon_community_submissions(id,user_id,draft,published,published_revision,status,published_at)
      VALUES($1,$2,$3::jsonb,$3::jsonb,1,'published',$4)`, [id, actor, JSON.stringify(snapshot), publishedAt]);
    fixtures.push({ id, format, category, publishedAt, source });
  }
  await db.exec(`INSERT INTO nikon_presets(draft,status) VALUES('"never-public-fixture"'::jsonb,'draft');
    INSERT INTO nikon_community_submissions(user_id,draft,status) VALUES('${actor}','"never-public-fixture"'::jsonb,'draft');`);
  fixtures.sort((a, b) => b.publishedAt.localeCompare(a.publishedAt) || a.id.localeCompare(b.id));
  const feed = async body => (await db.query("SELECT nikon_community('feed',NULL,NULL,$1::jsonb) AS result", [JSON.stringify(body)])).rows[0].result;
  for (const fileFormat of ['', 'NCP', 'NP3']) for (const category of ['', '__uncategorized__', '胶片', '人像', '不存在']) {
    const expected = fixtures.filter(row => (!fileFormat || row.format === fileFormat)
      && (!category || row.category === (category === '__uncategorized__' ? '' : category)));
    const pageSize = 7;
    for (let page = 1; page <= Math.ceil(expected.length / pageSize) + 1; page++) {
      const result = await feed({ page, pageSize, category, fileFormat });
      same(result.fileFormat, fileFormat, 'database acknowledges actual applied filter');
      same(result.total, expected.length, 'total counts all matching rows before LIMIT');
      same(result.page, page, 'actual page'); same(result.pageSize, pageSize, 'actual page size');
      same(result.hasMore, page * pageSize < expected.length, 'hasMore uses filtered total');
      same(result.items.map(item => item.id), expected.slice((page - 1) * pageSize, page * pageSize).map(item => item.id), 'stable global page order, no omissions');
      same([...result.categories].sort(), ['', '胶片', '人像'].sort(), 'categories remain global even on empty format/category combination');
      if (fileFormat) same(result.items.every(item => item.fileFormat === fileFormat), true, 'every page item matches requested format');
    }
  }
  const legacy = await feed({ page: 1, pageSize: 50 });
  same(legacy.total, 65, 'old client missing format sees all records'); same(legacy.fileFormat, '', 'missing format acknowledged as all');
  const ncp = await feed({ page: 1, pageSize: 50, fileFormat: 'NCP' });
  same(ncp.items.filter(item => Number(item.id.slice(-12)) >= 60).length, 6, 'legacy metadata defaults to NCP');
  const np3 = await feed({ page: 1, pageSize: 50, fileFormat: 'NP3' });
  same([...new Set(np3.items.map(item => item.source))].sort(), ['community', 'curated'], 'both publication sources included');
  for (const fileFormat of ['ncp', 'NP3 ', 'JPEG', 'NCP&category=胶片', null, true, 1, [], {}]) {
    await db.exec('SAVEPOINT invalid_filter;');
    await assert.rejects(feed({ fileFormat }), error => error.message.includes('INVALID_PRESET_FORMAT_FILTER')); checks++;
    await db.exec('ROLLBACK TO SAVEPOINT invalid_filter; RELEASE SAVEPOINT invalid_filter;');
  }
  same(await db.query("SELECT nikon_community('detail',NULL,$1) AS result", [fixtures[0].id]).then(value => value.rows[0].result.id), fixtures[0].id, 'detail branch still works');
  await db.exec('ROLLBACK;');
  same((await db.query('SELECT count(*)::integer AS n FROM nikon_users')).rows[0].n, 0, 'fixtures rolled back');
  same((await db.query('SELECT count(*)::integer AS n FROM nikon_presets')).rows[0].n, 0, 'curated fixtures rolled back');
  same((await db.query('SELECT count(*)::integer AS n FROM nikon_app_releases')).rows[0].n, 0, 'release records untouched');
  // An unexpected deployed feed body must fail instead of replacing another change.
  await db.exec(sourceBefore.replace(" IF p_action='feed' THEN", " IF p_action='feed' THEN -- independent feed change"));
  const changed = await definition();
  await assert.rejects(db.exec(migration), error => error.message.includes('PRESET_FORMAT_FILTER_PATCH_MISMATCH')); checks++;
  await db.exec('ROLLBACK;'); same(await definition(), changed, 'failed migration leaves unexpected definition intact');
  console.log(`Preset format filter PostgreSQL: ${checks} checks passed; all 001..014 migrations, feed-only/rerun/fail-closed patch, exact filtered totals/pages, global categories, legacy NCP and ACL/release preservation.`);
} finally { await db.close(); }
