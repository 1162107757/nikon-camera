import { createHash } from 'node:crypto';
import { inflateRawSync } from 'node:zlib';
import { ServiceError } from './cloudbase.mjs';

export const MAX_IPA_BYTES = 128 * 1024 * 1024;
export const IOS_BUNDLE_IDS = Object.freeze(['cc.huevia.next']);
const invalid = () => { throw new ServiceError(400, 'INVALID_IPA', '请选择完整的未签名 iPhoneOS ARM64 IPA；应用身份、版本或包结构校验失败。'); };
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const crcTable = Array.from({ length: 256 }, (_, value) => {
  for (let i = 0; i < 8; i++) value = value & 1 ? 0xedb88320 ^ value >>> 1 : value >>> 1;
  return value >>> 0;
});
function crc32(data) { let crc = 0xffffffff; for (const byte of data) crc = crcTable[(crc ^ byte) & 255] ^ crc >>> 8; return (crc ^ 0xffffffff) >>> 0; }
function zip(bytes) {
  let end = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
    if (bytes.readUInt32LE(i) === 0x06054b50 && i + 22 + bytes.readUInt16LE(i + 20) === bytes.length) { end = i; break; }
  }
  if (end < 0 || bytes.readUInt16LE(end + 4) || bytes.readUInt16LE(end + 6)) invalid();
  const count = bytes.readUInt16LE(end + 10), start = bytes.readUInt32LE(end + 16), size = bytes.readUInt32LE(end + 12);
  if (!count || count > 12000 || count !== bytes.readUInt16LE(end + 8) || start + size !== end) invalid();
  let at = start, expandedTotal = 0; const entries = new Map(), ranges = [];
  for (let i = 0; i < count; i++) {
    if (at + 46 > end || bytes.readUInt32LE(at) !== 0x02014b50) invalid();
    const flags = bytes.readUInt16LE(at + 8), method = bytes.readUInt16LE(at + 10), compressed = bytes.readUInt32LE(at + 20), expanded = bytes.readUInt32LE(at + 24);
    const nameLength = bytes.readUInt16LE(at + 28), extra = bytes.readUInt16LE(at + 30), comment = bytes.readUInt16LE(at + 32), local = bytes.readUInt32LE(at + 42);
    if (flags & 1 || ![0, 8].includes(method) || at + 46 + nameLength + extra + comment > end || local + 30 > start) invalid();
    const encoded = bytes.subarray(at + 46, at + 46 + nameLength), name = new TextDecoder('utf-8', { fatal: true }).decode(encoded);
    if (!name || name.length > 1024 || /(^\/|\\|\x00|(?:^|\/)\.{1,2}(?:\/|$))/.test(name) || entries.has(name)) invalid();
    const mode = bytes.readUInt32LE(at + 38) >>> 16;
    if ((mode & 0xf000) === 0xa000) invalid(); // symlinks have no place in the device IPA channel.
    if (bytes.readUInt32LE(local) !== 0x04034b50 || bytes.readUInt16LE(local + 6) !== flags || bytes.readUInt16LE(local + 8) !== method) invalid();
    const localName = bytes.readUInt16LE(local + 26), localExtra = bytes.readUInt16LE(local + 28), dataStart = local + 30 + localName + localExtra;
    if (!bytes.subarray(local + 30, local + 30 + localName).equals(encoded) || dataStart + compressed > start) invalid();
    ranges.push([local, dataStart + compressed]); expandedTotal += expanded;
    if (expandedTotal > 1024 * 1024 * 1024) invalid();
    entries.set(name, { data: bytes.subarray(dataStart, dataStart + compressed), method, expanded, crc: bytes.readUInt32LE(at + 16) });
    at += 46 + nameLength + extra + comment;
  }
  ranges.sort((a, b) => a[0] - b[0]);
  if (at !== end || ranges.some((range, index) => index > 0 && range[0] < ranges[index - 1][1])) invalid();
  return entries;
}
function contents(entry, limit) {
  if (!entry || entry.expanded < 1 || entry.expanded > limit || entry.data.length > limit) invalid();
  const data = entry.method === 0 ? entry.data : inflateRawSync(entry.data, { maxOutputLength: limit });
  if (data.length !== entry.expanded || crc32(data) !== entry.crc) invalid();
  return data;
}
function binaryPlist(data) {
  if (data.length < 40 || data.toString('ascii', 0, 8) !== 'bplist00') invalid();
  const trailer = data.length - 32, offsetBytes = data[trailer + 6], refBytes = data[trailer + 7];
  const integer = (at, bytes) => { if (bytes < 1 || bytes > 8 || at < 0 || at + bytes > data.length) invalid(); let result = 0n; for (let i = 0; i < bytes; i++) result = result * 256n + BigInt(data[at + i]); if (result > BigInt(Number.MAX_SAFE_INTEGER)) invalid(); return Number(result); };
  const count = integer(trailer + 8, 8), top = integer(trailer + 16, 8), table = integer(trailer + 24, 8);
  if (count < 1 || count > 65536 || top >= count || offsetBytes < 1 || offsetBytes > 8 || refBytes < 1 || refBytes > 8 || table + count * offsetBytes > trailer) invalid();
  const visiting = new Set();
  function object(index, depth = 0) {
    if (index >= count || depth > 32 || visiting.has(index)) invalid();
    visiting.add(index);
    try {
      let at = integer(table + index * offsetBytes, offsetBytes); if (at < 8 || at >= table) invalid();
      const marker = data[at++], type = marker >>> 4; let length = marker & 15;
      if (type === 0) { if (![0, 8, 9].includes(length)) invalid(); return length === 0 ? null : length === 9; }
      if (type === 1) return integer(at, 2 ** length);
      if (length === 15) { const sizeMarker = data[at++]; if (sizeMarker >>> 4 !== 1) invalid(); const size = 2 ** (sizeMarker & 15); length = integer(at, size); at += size; }
      if (length > 65536) invalid();
      if (type === 5 || type === 6) {
        const bytes = length * (type === 6 ? 2 : 1); if (at + bytes > table) invalid();
        if (type === 5) return data.toString('ascii', at, at + bytes);
        const copied = Buffer.from(data.subarray(at, at + bytes)); copied.swap16(); return copied.toString('utf16le');
      }
      if (type === 10) { if (at + length * refBytes > table) invalid(); return Array.from({ length }, (_, i) => object(integer(at + i * refBytes, refBytes), depth + 1)); }
      if (type === 13) {
        if (at + length * refBytes * 2 > table) invalid(); const result = Object.create(null);
        const wanted = new Set(['CFBundleIdentifier', 'CFBundleVersion', 'CFBundleShortVersionString', 'CFBundleExecutable', 'MinimumOSVersion', 'CFBundleSupportedPlatforms']);
        for (let i = 0; i < length; i++) { const key = object(integer(at + i * refBytes, refBytes), depth + 1); if (typeof key !== 'string') invalid(); if (Object.hasOwn(result, key)) invalid(); if (wanted.has(key)) result[key] = object(integer(at + (length + i) * refBytes, refBytes), depth + 1); }
        return result;
      }
      invalid();
    } finally { visiting.delete(index); }
  }
  return object(top);
}
function plist(data) {
  if (data.toString('ascii', 0, 8) === 'bplist00') return binaryPlist(data);
  const xml = new TextDecoder('utf-8', { fatal: true }).decode(data);
  if (!xml.includes('<plist') || /<!ENTITY/i.test(xml)) invalid();
  const decode = text => text.replace(/&(?:amp|lt|gt|quot|apos);/g, value => ({ '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" })[value]);
  const result = Object.create(null);
  for (const key of ['CFBundleIdentifier', 'CFBundleVersion', 'CFBundleShortVersionString', 'CFBundleExecutable', 'MinimumOSVersion']) {
    const matches = [...xml.matchAll(new RegExp(`<key>\\s*${key}\\s*</key>\\s*<(string|integer)>([^<]{0,600})</\\1>`, 'g'))];
    if (matches.length !== 1) invalid(); result[key] = decode(matches[0][2]);
  }
  return result;
}
function deviceExecutable(data) {
  let offset = 0, end = data.length;
  if (data.length < 32) invalid();
  if (data.readUInt32BE(0) === 0xcafebabe) {
    const count = data.readUInt32BE(4); if (count < 1 || count > 8 || 8 + count * 20 > data.length) invalid();
    const slices = Array.from({ length: count }, (_, i) => { const at = 8 + i * 20; return { cpu: data.readUInt32BE(at), offset: data.readUInt32BE(at + 8), size: data.readUInt32BE(at + 12) }; });
    if (slices.length !== 1 || slices[0].cpu !== 0x100000c || slices[0].offset + slices[0].size > data.length) invalid();
    offset = slices[0].offset; end = offset + slices[0].size;
  }
  if (offset + 32 > end || data.readUInt32LE(offset) !== 0xfeedfacf || data.readUInt32LE(offset + 4) !== 0x100000c) invalid();
  const count = data.readUInt32LE(offset + 16), commandBytes = data.readUInt32LE(offset + 20); let at = offset + 32, platform;
  if (count > 4096 || at + commandBytes > end) invalid();
  for (let i = 0; i < count; i++) { if (at + 8 > end) invalid(); const command = data.readUInt32LE(at), size = data.readUInt32LE(at + 4); if (size < 8 || at + size > end) invalid(); if (command === 0x32) { if (size < 24 || platform !== undefined) invalid(); platform = data.readUInt32LE(at + 8); } at += size; }
  if (platform !== 2) invalid();
}
export function inspectIpa(bytes) {
  try {
    if (!Buffer.isBuffer(bytes) || bytes.length < 1024 || bytes.length > MAX_IPA_BYTES) invalid();
    const entries = zip(bytes), apps = [...entries.keys()].filter(name => /^Payload\/[^/]+[.]app\/Info[.]plist$/.test(name));
    if (apps.length !== 1) invalid();
    const root = apps[0].slice(0, -'Info.plist'.length), metadata = plist(contents(entries.get(apps[0]), 1024 * 1024));
    if (!IOS_BUNDLE_IDS.includes(metadata.CFBundleIdentifier) || !/^[1-9][0-9]{0,8}$/.test(metadata.CFBundleVersion) || !/^[0-9A-Za-z][0-9A-Za-z._+-]{0,99}$/.test(metadata.CFBundleShortVersionString) || !/^[A-Za-z0-9._-]{1,100}$/.test(metadata.CFBundleExecutable) || !/^\d{1,2}[.]\d{1,2}(?:[.]\d{1,2})?$/.test(metadata.MinimumOSVersion)) invalid();
    if ([...entries.keys()].some(name => name.startsWith(root + '_CodeSignature/') || name === root + 'embedded.mobileprovision')) invalid();
    deviceExecutable(contents(entries.get(root + metadata.CFBundleExecutable), 64 * 1024 * 1024));
    return { schema: 1, platform: 'ios', distribution: 'unsigned-ipa', bundleId: metadata.CFBundleIdentifier,
      versionName: metadata.CFBundleShortVersionString, versionCode: Number(metadata.CFBundleVersion), minimumIOS: metadata.MinimumOSVersion,
      sha256: digest(bytes), byteLength: bytes.length };
  } catch (error) { if (error instanceof ServiceError) throw error; invalid(); }
}
