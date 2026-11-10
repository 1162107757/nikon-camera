import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createServer} from 'node:http';
import {createAbuseContext} from '../server/abuse.mjs';
import {createHandler} from '../server/app.mjs';
import {ReleaseMemoryStore} from './release-memory-store.mjs';

const secret = 'website-forwarded-source-fixture-key-20261110';
const proxy = '198.51.100.10', client = '203.0.113.20', other = '203.0.113.21';
const gateway = ['10.0.0.1', '10.0.0.2', '10.0.0.3'];
const request = (forwarded, remote = '127.0.0.1') => ({socket:{remoteAddress:remote},headers:{'x-forwarded-for':forwarded}});
const forwarded = (ip, viaWebsite = true, prefix = []) => [...prefix, ip, ...(viaWebsite ? [proxy] : []), ...gateway].join(', ');
const plain = createAbuseContext({store:{},secret});
const identity = ip => plain.context(request('', ip)).sourceHash;
const options = {store:{},secret,trustedProxyHops:4,trustedForwardedProxyAddresses:[proxy]};

test('website and direct gateway use the same client IP, not the shared website proxy', () => {
  const fixed = createAbuseContext(options);
  const before = createAbuseContext({store:{},secret,trustedProxyHops:4});
  assert.equal(before.context(request(forwarded(client))).sourceHash, identity(proxy), 'reproduces the shared website bucket');
  assert.equal(fixed.context(request(forwarded(client))).sourceHash, identity(client));
  assert.equal(fixed.context(request(forwarded(client, false))).sourceHash, identity(client));
  assert.equal(fixed.context(request(forwarded(other))).sourceHash, identity(other));
  assert.notEqual(identity(client), identity(other));
});

test('spoofed leading IPs, trusted-proxy literals and Host cannot select the source', () => {
  const fixed = createAbuseContext(options);
  for (const viaWebsite of [true, false]) {
    for (const prefix of [[], ['192.0.2.99'], ['192.0.2.99', proxy], [proxy, proxy, '192.0.2.99']]) {
      const req = request(forwarded(client, viaWebsite, prefix));
      req.headers.host = 'attacker.invalid';
      req.headers['x-forwarded-host'] = 'huevia.cc';
      assert.equal(fixed.context(req).sourceHash, identity(client));
    }
  }
  const unrelated = createAbuseContext({...options,trustedForwardedProxyAddresses:['198.51.100.11']});
  assert.equal(unrelated.context(request(forwarded(client))).sourceHash, identity(proxy), 'unlisted intermediaries stay untrusted');
  const disabled = createAbuseContext({...options,trustedProxyHops:0});
  assert.equal(disabled.context(request(forwarded(client), other)).sourceHash, identity(other), 'headers are ignored when gateway trust is disabled');
});

test('proxy allowlist stays exact, validates addresses and preserves the socket trust boundary', () => {
  for (const value of ['198.51.100.10', ['*'], ['198.51.100.0/24'], [''], [null]]) {
    assert.throws(() => createAbuseContext({...options,trustedForwardedProxyAddresses:value}), /Invalid trusted forwarded proxy/);
  }
  const fixed = createAbuseContext(options);
  assert.throws(() => fixed.context(request(forwarded(client), '192.0.2.4')), {code:'INVALID_PROXY_SOURCE',status:403});
  assert.throws(() => fixed.context(request([proxy,...gateway].join(', '))), {code:'INVALID_PROXY_SOURCE',status:400});
  assert.throws(() => fixed.context(request(`malformed, ${forwarded(client)}`)), {code:'INVALID_PROXY_SOURCE',status:400});
  const mapped = createAbuseContext({...options,trustedForwardedProxyAddresses:['::ffff:198.51.100.10']});
  assert.equal(mapped.context(request(forwarded(client), '::ffff:127.0.0.1')).sourceHash, identity(client));
  const secondProxy = '2001:db8::10';
  const multiple = createAbuseContext({...options,trustedForwardedProxyAddresses:[proxy,secondProxy]});
  assert.equal(multiple.context(request([client,proxy,'2001:0db8:0:0:0:0:0:10',...gateway].join(', '))).sourceHash, identity(client));
  assert.equal(fixed.context(request(forwarded('2001:db8:1:2::1'))).sourceHash, identity('2001:db8:1:2::abcd'), 'IPv6 /64 grouping remains consistent');
});

test('full handler isolates website download quotas and explains IP limits with the actual wait', async t => {
  const store = new ReleaseMemoryStore(), payload = Buffer.from('forwarded-source APK fixture');
  const sha = createHash('sha256').update(payload).digest('hex');
  const id = '12345678-1234-4234-8234-123456789abc';
  store.releaseRows.push({id,status:'published',sha256:sha,byte_length:payload.length,storage_path:`app-releases/${sha}.bin`,version_code:186,channel:'beta',package_name:'cc.huevia'});
  const blocked = new Set(), calls = [];
  const rpc = store.rpc.bind(store);
  store.rpc = async (name, body) => {
    if (name === 'nikon_release_download_budget' || name === 'nikon_release_budget_atomic') {
      calls.push({name,...body});
      return blocked.has(body.p_key) ? {error:'IP_BUDGET',retryAfterSeconds:123} : {allowed:true};
    }
    return rpc(name, body);
  };
  const handler = createHandler({store,storage:{get:async()=>payload},environmentId:'fixture',publicBaseUrl:'http://127.0.0.1',secureCookies:false,trustedProxyHops:4,trustedForwardedProxyAddresses:[proxy]});
  const server = createServer(handler);
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>{server.closeAllConnections();server.close();});
  const url = `http://127.0.0.1:${server.address().port}/preset-library/releases/${id}/file`;
  const download = async (ip, html = false, viaWebsite = true, prefix = []) => {
    const response = await fetch(url,{headers:{Accept:html?'text/html':'application/json','X-Forwarded-For':forwarded(ip,viaWebsite,prefix)}});
    return {response,body:await response.text()};
  };
  assert.equal((await download(client)).response.status,200);
  const first = calls.at(-1).p_key;
  assert.equal((await download(client,false,false)).response.status,200);
  assert.equal(calls.at(-1).p_key,first,'both entrypoints debit the same IP');
  blocked.add(first);
  const denied = await download(client,true,true,['192.0.2.99',proxy]);
  assert.equal(denied.response.status,429);
  assert.equal(denied.response.headers.get('retry-after'),'123');
  assert.match(denied.body,/当前网络下载已达上限/);
  assert.match(denied.body,/约 3 分钟后可重试/);
  assert.equal((await download(other)).response.status,200,'one saturated website visitor must not block another');
  assert.notEqual(calls.at(-1).p_key,first);
  const api = await download(client);
  assert.equal(JSON.parse(api.body).error.code,'RELEASE_IP_BUDGET','Android keeps its JSON error contract');
});
