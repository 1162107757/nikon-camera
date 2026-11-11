import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {observeRequest} from '../server/request-observer.mjs';

const id = '12345678-1234-4234-8234-123456789abc';
const env = {TENCENTCLOUD_RUNENV:'SCF',SCF_FUNCTIONNAME:'fixture',BASE_PATH:'/preset-library'};
const request = () => ({method:'GET',url:`/preset-library/releases/${id}/file?token=private-query`,socket:{remoteAddress:'127.0.0.1'},headers:{'x-scf-name':'fixture','x-scf-request-id':id,authorization:'Bearer private-auth',cookie:'private-cookie','x-scf-secret-key':'private-role-key'}});
const response = () => Object.assign(new EventEmitter(),{statusCode:200,writableFinished:false});

test('request context contains only a fixed route group, method and validated identifiers', () => {
  const entries = [],req = request(),res = response();
  observeRequest(req,res,{env,sink:(entry,level)=>entries.push({entry,level})});
  assert.equal(entries.length,1);assert.equal(entries[0].entry.route,'release_download');assert.equal(entries[0].entry.requestId,id);
  assert.deepEqual(Object.keys(entries[0].entry).sort(),['event','method','requestId','route','traceId']);
  const serialized = JSON.stringify(entries);
  for (const privateValue of ['private-query','private-auth','private-cookie','private-role-key','127.0.0.1']) assert.ok(!serialized.includes(privateValue));
});

test('untrusted or malformed platform identifiers never become authoritative log correlation', () => {
  for (const alter of [req=>{req.socket.remoteAddress='203.0.113.9';},req=>{req.headers['x-scf-name']='other';},req=>{req.headers['x-scf-request-id']='bad\nidentifier';}]) {
    const entries = [],req = request();alter(req);
    observeRequest(req,response(),{env,sink:entry=>entries.push(entry)});
    assert.equal(entries[0].requestId,undefined);
    assert.match(entries[0].traceId,/^[a-f0-9-]{36}$/);
  }
});

test('cancellations, slow completions and genuine server failures are recorded once with correct severity', () => {
  for (const kind of ['cancel','slow','failure','normal']) {
    const entries = [],res = response();let now = 100;
    observeRequest(request(),res,{env,clock:()=>now,sink:(entry,level)=>entries.push({...entry,level})});
    now += kind === 'slow' ? 3500 : 200;
    if (kind === 'failure') res.statusCode = 503;
    if (kind !== 'cancel') {res.writableFinished=true;res.emit('finish');}
    res.emit('close');res.emit('close');
    assert.equal(entries.length,kind === 'normal' ? 1 : 2);
    if (kind === 'normal') continue;
    const last = entries[1];
    assert.equal(last.event,kind === 'cancel'?'http.request.canceled':kind === 'failure'?'http.request.failed':'http.request.slow');
    assert.equal(last.level,kind === 'failure'?'error':'info');
    assert.equal(last.durationMs,kind === 'slow'?3500:200);
  }
});

test('diagnostic sink failures cannot change request handling and arbitrary paths stay private', () => {
  const req = request(),res = response();req.url='/preset-library/api/personal/user-private-id?password=private-query';
  const entries = [];
  observeRequest(req,res,{env,sink:entry=>{entries.push(entry);throw Error('diagnostic fixture');}});
  assert.equal(entries[0].route,'personal_api');
  assert.ok(!JSON.stringify(entries).includes('user-private-id'));
  assert.doesNotThrow(()=>{res.writableFinished=true;res.emit('finish');res.emit('close');});
});
