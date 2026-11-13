import { createHash } from 'node:crypto';

const table = Array.from({ length: 256 }, (_, value) => { for (let i = 0; i < 8; i++) value = value & 1 ? 0xedb88320 ^ value >>> 1 : value >>> 1; return value >>> 0; });
const crc32 = bytes => { let crc = 0xffffffff; for (const byte of bytes) crc = table[(crc ^ byte) & 255] ^ crc >>> 8; return (crc ^ 0xffffffff) >>> 0; };
export function zipFixture(files) {
  const local = [], central = [];let offset = 0;
  for (const [name, input] of Object.entries(files)) {
    const data = Buffer.from(input), encoded = Buffer.from(name), crc = crc32(data), header = Buffer.alloc(30), entry = Buffer.alloc(46);
    header.writeUInt32LE(0x04034b50);header.writeUInt16LE(20, 4);header.writeUInt32LE(crc, 14);header.writeUInt32LE(data.length, 18);header.writeUInt32LE(data.length, 22);header.writeUInt16LE(encoded.length, 26);
    entry.writeUInt32LE(0x02014b50);entry.writeUInt16LE(20, 4);entry.writeUInt16LE(20, 6);entry.writeUInt32LE(crc, 16);entry.writeUInt32LE(data.length, 20);entry.writeUInt32LE(data.length, 24);entry.writeUInt16LE(encoded.length, 28);entry.writeUInt32LE(offset, 42);
    local.push(header, encoded, data);central.push(entry, encoded);offset += header.length + encoded.length + data.length;
  }
  const directory = Buffer.concat(central), end = Buffer.alloc(22);end.writeUInt32LE(0x06054b50);end.writeUInt16LE(Object.keys(files).length, 8);end.writeUInt16LE(Object.keys(files).length, 10);end.writeUInt32LE(directory.length, 12);end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, directory, end]);
}
// These are synthetic parser fixtures, never an installable binary or an authorization result.
export function ipaFixture({ platform = 2, bundleId = 'cc.huevia.next', version = '213', signed = false, extra = {} } = {}) {
  const executable = Buffer.alloc(56);executable.writeUInt32LE(0xfeedfacf);executable.writeUInt32LE(0x100000c, 4);executable.writeUInt32LE(2, 12);executable.writeUInt32LE(1, 16);executable.writeUInt32LE(24, 20);executable.writeUInt32LE(0x32, 32);executable.writeUInt32LE(24, 36);executable.writeUInt32LE(platform, 40);executable.writeUInt32LE(16 << 16, 44);
  const info = `<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>${bundleId}</string><key>CFBundleVersion</key><string>${version}</string><key>CFBundleShortVersionString</key><string>0.31.0-dev</string><key>CFBundleExecutable</key><string>Runner</string><key>MinimumOSVersion</key><string>16.0</string></dict></plist>`;
  return zipFixture({ 'Payload/Runner.app/Info.plist': info, 'Payload/Runner.app/Runner': executable,
    'Payload/Runner.app/parser-fixture.bin': Buffer.alloc(1100, 42), ...(signed ? { 'Payload/Runner.app/_CodeSignature/CodeResources': 'fixture signature' } : {}), ...extra });
}
export const digest = bytes => createHash('sha256').update(bytes).digest('hex');
