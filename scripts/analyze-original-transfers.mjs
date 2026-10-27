import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

/** Fixed numeric fields only: do not echo unrelated report content or camera identifiers. */
export function analyzeOriginalTransfers(report) {
  const trace = typeof report?.connectionTrace === 'string' ? report.connectionTrace : '';
  const transfers = new Map();
  const fields = ['conn', 'tx', 'elapsed_ms', 'bytes', 'total_bytes', 'payload_read_ms', 'sink_write_ms', 'progress_callback_ms', 'timeouts'];
  for (const line of trace.split(/\r?\n/)) {
    const event = line.match(/\bevent=PTP_ORIGINAL_(PROGRESS|COMPLETE|FAILED)\b/)?.[1];
    if (!event || !/\bop=0x1009\b/.test(line)) continue;
    const values = {};
    for (const field of fields) {
      const raw = line.match(new RegExp(`\\b${field}=(\\d+)(?=\\s|$)`))?.[1];
      if (raw !== undefined && Number.isSafeInteger(Number(raw))) values[field] = Number(raw);
    }
    if (fields.some(field => values[field] === undefined)) continue;
    const key = `${values.conn}:${values.tx}`;
    let transfer = transfers.get(key);
    if (!transfer) transfers.set(key, transfer = { samples: [], status: 'IN_PROGRESS' });
    transfer.samples.push(values);
    if (event !== 'PROGRESS') transfer.status = event;
  }
  const summaries = [...transfers.values()].map((transfer, index) => {
    const samples = transfer.samples.sort((a, b) => a.elapsed_ms - b.elapsed_ms);
    const last = samples.at(-1);
    let longestSampleIntervalMs = null;
    for (let i = 1; i < samples.length; i++) longestSampleIntervalMs = Math.max(longestSampleIntervalMs ?? 0, samples[i].elapsed_ms - samples[i - 1].elapsed_ms);
    return {
      transfer: index + 1, status: transfer.status, samples: samples.length,
      bytes: last.bytes, totalBytes: last.total_bytes, elapsedMs: last.elapsed_ms,
      averageMBps: last.elapsed_ms > 0 ? Number((last.bytes / last.elapsed_ms / 1000).toFixed(3)) : null,
      payloadReadMs: last.payload_read_ms, sinkWriteMs: last.sink_write_ms,
      progressCallbackMs: last.progress_callback_ms, timeouts: last.timeouts,
      otherElapsedMs: Math.max(0, last.elapsed_ms - last.payload_read_ms - last.sink_write_ms - last.progress_callback_ms),
      payloadReadPercent: last.elapsed_ms > 0 ? Number((last.payload_read_ms * 100 / last.elapsed_ms).toFixed(1)) : null,
      longestSampleIntervalMs,
    };
  });
  const completed = summaries.filter(s => s.status === 'COMPLETE' && s.elapsedMs > 0);
  const rates = completed.map(s => s.averageMBps).sort((a, b) => a - b);
  const middle = Math.floor(rates.length / 2);
  return {
    schemaVersion: 1, transfers: summaries,
    completed: completed.length,
    medianCompletedMBps: rates.length ? (rates.length % 2 ? rates[middle] : Number(((rates[middle - 1] + rates[middle]) / 2).toFixed(3))) : null,
    limitation: '接收耗时包含等待读取；不能单凭此报告区分相机发送与无线链路。采样间隔不等于网络停顿。报告仅保留最近一段日志，未完成记录可能已被截断。',
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const filename = process.argv[2];
  if (!filename) { console.error('用法：node scripts/analyze-original-transfers.mjs <导出的报告.json>'); process.exitCode = 1; }
  else {
    try { console.log(JSON.stringify(analyzeOriginalTransfers(JSON.parse(fs.readFileSync(filename, 'utf8').replace(/^\uFEFF/, ''))), null, 2)); }
    catch { console.error('报告读取失败，请检查文件路径和 JSON 格式。'); process.exitCode = 1; }
  }
}
