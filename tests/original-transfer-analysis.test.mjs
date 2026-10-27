import assert from 'node:assert/strict';
import { test } from 'node:test';
import { analyzeOriginalTransfers } from '../scripts/analyze-original-transfers.mjs';

const row = (event, elapsed, bytes, rest = '') => `time event=PTP_ORIGINAL_${event} conn=9 op=0x1009 tx=1 elapsed_ms=${elapsed} bytes=${bytes} total_bytes=12853156 payload_read_ms=${elapsed - 500} sink_write_ms=77 progress_callback_ms=10 timeouts=0 ${rest}`;
test('isolates receive time without attributing it to Wi-Fi or retaining private report text', () => {
  const result = analyzeOriginalTransfers({ serial: 'SECRET', connectionTrace: [row('PROGRESS', 2000, 100000), row('COMPLETE', 111032, 12853156, 'filename=SECRET.JPG')].join('\n') });
  assert.equal(result.completed, 1); assert.equal(result.transfers[0].averageMBps, .116);
  assert.equal(result.transfers[0].sinkWriteMs, 77); assert.equal(result.transfers[0].otherElapsedMs, 413);
  assert.equal(result.transfers[0].longestSampleIntervalMs, 109032);
  assert.ok(!JSON.stringify(result).includes('SECRET'));
});
test('failed or truncated transfers are excluded from completed throughput statistics', () => {
  const result = analyzeOriginalTransfers({ connectionTrace: row('FAILED', 6000, 1000) + '\n' + row('PROGRESS', 2000, 1000).replace('tx=1', 'tx=2') });
  assert.equal(result.completed, 0); assert.equal(result.medianCompletedMBps, null);
  assert.deepEqual(result.transfers.map(t => t.status), ['FAILED', 'IN_PROGRESS']);
});
test('missing, unsafe and unrelated fields never become fabricated zero-time results', () => {
  const result = analyzeOriginalTransfers({ connectionTrace: row('COMPLETE', 2000, 1000).replace('elapsed_ms=2000', 'elapsed_ms=9007199254740992') + '\n' + row('COMPLETE', 2000, 1000).replace('op=0x1009', 'op=0x90c4') });
  assert.deepEqual(result.transfers, []); assert.equal(analyzeOriginalTransfers({}).completed, 0);
});
