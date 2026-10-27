import test from 'node:test';
import assert from 'node:assert/strict';
import { CloudBaseStore } from '../server/cloudbase.mjs';
import { buildCatalog } from '../server/validation.mjs';

const id = value => '11111111-1111-4111-8111-' + String(value).padStart(12, '0');
const fixture = value => ({ id: id(value), status: 'published', published: {
  name: `fixture-${value}`, description: '完整保留原始发布快照', category: '胶片', compatibleModels: ['Z 6II'], sortOrder: value,
  file: { id: `ncp-${String(value).padStart(64, '0')}`, url: `https://fixture.invalid/${value}.ncp`,
    sha256: String(value).padStart(64, '0'), byteLength: 52, ncpVersion: '0100', fileFormat: 'NCP' },
  preview: null
} });

function database(rows, providerCap = 1000, reply, { admin = false } = {}) {
  const calls = [];
  const store = new CloudBaseStore({ environmentId: 'fixture', serviceKey: 'local-only-fixture', fetchImpl: async url => {
    const query = url.searchParams, limit = Number(query.get('limit')), cursor = query.get('id');
    assert.equal(url.pathname, '/v1/rdb/rest/nikon_presets');
    assert.equal(query.get('status'), admin ? null : 'eq.published');
    assert.equal(query.get('select'), admin ? '*' : 'id,status,published');
    assert.equal(query.get('order'), 'id.asc');
    assert.ok(Number.isSafeInteger(limit) && limit >= 1 && limit <= 512);
    assert.equal(query.has('offset'), false);
    if (cursor) assert.match(cursor, /^gt\.[0-9a-f-]{36}$/);
    calls.push({ limit, after: cursor?.slice(3) || '' });
    if (reply) return reply(calls.length, calls.at(-1));
    const page = rows.filter(row => !cursor || row.id > cursor.slice(3)).sort((left, right) => left.id.localeCompare(right.id))
      .slice(0, Math.min(limit, providerCap));
    return Response.json(page);
  } });
  return { store, calls };
}

test('published catalog reads all 390 rows and preserves complete snapshots', async () => {
  const expected = Array.from({ length: 390 }, (_, index) => fixture(index + 1));
  const { store, calls } = database(expected);
  const actual = await store.catalogRows();
  assert.deepEqual(actual, expected);
  assert.equal(buildCatalog(actual).presets.length, 390);
  assert.equal(calls.length, 2, 'the final empty page confirms completeness');
});

test('1024 published rows cross provider pages without exceeding their row cap', async () => {
  const expected = Array.from({ length: 1024 }, (_, index) => fixture(index + 1));
  const { store, calls } = database(expected);
  const actual = await store.catalogRows();
  assert.deepEqual(actual, expected);
  assert.equal(buildCatalog(actual).presets.length, 1024);
  assert.deepEqual(calls.map(call => call.limit), [512, 512, 1]);
});

test('the overflow sentinel reaches validation instead of silently truncating a larger catalog', async () => {
  const { store, calls } = database(Array.from({ length: 1100 }, (_, index) => fixture(index + 1)));
  const rows = await store.catalogRows();
  assert.equal(rows.length, 1025);
  assert.throws(() => buildCatalog(rows), error => error.code === 'invalid_catalog');
  assert.equal(calls.length, 3, 'reads stop at one overflow row');
});

test('a provider cap smaller than the requested batch never makes a short page final', async () => {
  const expected = Array.from({ length: 1024 }, (_, index) => fixture(index + 1));
  const { store, calls } = database(expected, 127);
  assert.deepEqual(await store.catalogRows(), expected);
  assert.ok(calls.length > 3);
  assert.equal(calls.at(-1).after, id(1024));
});

test('an empty published catalog returns an empty array', async () => {
  const { store, calls } = database([]);
  assert.deepEqual(await store.catalogRows(), []);
  assert.equal(calls.length, 1);
});

test('later-page failures cannot return a partial catalog', async () => {
  const { store } = database([], 1000, call => call === 1
    ? Response.json([fixture(1)]) : Response.json({ message: 'provider-only-details' }, { status: 503 }));
  await assert.rejects(() => store.catalogRows(), error => error.code === 'CLOUD_REQUEST_FAILED' && !error.message.includes('provider-only-details'));
});

test('malformed, excessive, repeated and unordered pages fail closed', async () => {
  for (const payload of [null, {}, [null], [{ id: 'not-a-uuid' }], [{ ...fixture(1), status: 'draft' }], [fixture(2), fixture(1)], [fixture(1), fixture(1)],
    Array.from({ length: 513 }, (_, index) => fixture(index + 1))]) {
    const { store } = database([], 1000, () => Response.json(payload));
    await assert.rejects(() => store.catalogRows(), error => error.code === 'CLOUD_REQUEST_FAILED');
  }
  const { store, calls } = database([], 1000, () => Response.json([fixture(1)]));
  await assert.rejects(() => store.catalogRows(), error => error.code === 'CLOUD_REQUEST_FAILED');
  assert.equal(calls.length, 2, 'an ignored cursor cannot cause an infinite read loop');
});

test('admin lists all 1024 snapshots and restores update order with a stable ID tie-break', async () => {
  const rows = Array.from({ length: 1024 }, (_, index) => ({ ...fixture(index + 1),
    status: index % 2 ? 'draft' : 'published', revision: index + 1, draft: { name: `private-draft-${index}` },
    updated_at: new Date(Date.UTC(2026, 0, 1, 0, 0, index % 10)).toISOString() }));
  const expected = [...rows].sort((left, right) => Date.parse(right.updated_at) - Date.parse(left.updated_at) || left.id.localeCompare(right.id));
  const { store } = database(rows, 1000, undefined, { admin: true });
  assert.deepEqual(await store.presets(), expected, 'all selected admin fields and private draft snapshots remain intact');
});

test('admin pagination continues through 127-row provider caps and preserves actual timestamp order', async () => {
  const rows = Array.from({ length: 1024 }, (_, index) => ({ id: id(index + 1), status: 'draft',
    updated_at: index % 2 ? '2026-01-01T08:00:00+08:00' : '2026-01-01T00:00:01Z' }));
  const expected = [...rows].sort((left, right) => Date.parse(right.updated_at) - Date.parse(left.updated_at) || left.id.localeCompare(right.id));
  const { store, calls } = database(rows, 127, undefined, { admin: true });
  assert.deepEqual(await store.presets(), expected);
  assert.ok(calls.length > 3);
});

test('admin management retains its 5000-row cap and fails explicitly on its overflow sentinel', async () => {
  const rows = Array.from({ length: 5001 }, (_, index) => ({ id: id(index + 1), updated_at: '2026-01-01T00:00:00Z' }));
  const valid = database(rows.slice(0, 5000), 1000, undefined, { admin: true });
  assert.deepEqual(await valid.store.presets(), rows.slice(0, 5000));
  const overflow = database(rows, 1000, undefined, { admin: true });
  await assert.rejects(() => overflow.store.presets(), error => error.code === 'CLOUD_REQUEST_FAILED' && /管理上限/.test(error.message));
  assert.equal(overflow.calls.at(-1).after, id(4608));
  assert.equal(overflow.calls.at(-1).limit, 393);
});

test('admin lists reject invalid timestamps and cannot return partial rows on later-page failure', async () => {
  const invalid = database([{ id: id(1), updated_at: 'invalid' }], 1000, undefined, { admin: true });
  await assert.rejects(() => invalid.store.presets(), error => error.code === 'CLOUD_REQUEST_FAILED');
  const failed = database([], 1000, call => call === 1 ? Response.json([{ id: id(1), updated_at: '2026-01-01T00:00:00Z' }])
    : Response.json({}, { status: 503 }), { admin: true });
  await assert.rejects(() => failed.store.presets(), error => error.code === 'CLOUD_REQUEST_FAILED');
});
