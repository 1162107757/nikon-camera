import test from 'node:test';
import assert from 'node:assert/strict';
import { downloadUrl } from '../home/home.js';
const release = { id: '7205dc77-3d55-4c1a-95a6-9c8cdf7d3179', packageName: 'cc.huevia', sha256: 'a'.repeat(64), signerSha256: 'b'.repeat(64),
  versionCode: 155, byteLength: 34581880, downloadUrl: 'https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com/preset-library/releases/7205dc77-3d55-4c1a-95a6-9c8cdf7d3179/file' };
test('homepage keeps the current validated same-origin route, including APKs above32MiB', () => {
  assert.equal(downloadUrl(release, 'https://huevia.cc'), 'https://huevia.cc/preset-library/releases/' + release.id + '/file');
});
test('homepage rejects untrusted download locations and malformed release identity', () => {
  for (const download of ['https://evil.example/preset-library/releases/' + release.id + '/file', release.downloadUrl + '?token=x', release.downloadUrl + '#x', release.downloadUrl.replace('/file', '/other')])
    assert.throws(() => downloadUrl({ ...release, downloadUrl: download }, 'https://huevia.cc'));
  for (const patch of [{ id: '../admin' }, { packageName: 'other.app' }, { byteLength: 0 }, { sha256: 'nope' }])
    assert.throws(() => downloadUrl({ ...release, ...patch }, 'https://huevia.cc'));
});
