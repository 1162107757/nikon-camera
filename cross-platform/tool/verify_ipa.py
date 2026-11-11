"""Independently inspect a downloaded device IPA and its build report."""
import argparse
import hashlib
import json
import plistlib
import struct
import zipfile
from pathlib import Path, PurePosixPath


def device_slices(binary):
    """Return every ARM64 iPhoneOS slice; reject simulator and mixed bundles."""
    magic = binary[:4]
    if magic == b'\xca\xfe\xba\xbe':
        count = struct.unpack_from('>I', binary, 4)[0]
        if not 1 <= count <= 8 or len(binary) < 8 + 20 * count:
            raise ValueError('Invalid universal Mach-O table')
        slices = []
        for index in range(count):
            cpu, _, offset, size, _ = struct.unpack_from('>5I', binary, 8 + 20 * index)
            if cpu != 0x100000c or offset < 8 + 20 * count or offset + size > len(binary):
                raise ValueError('IPA contains a non-ARM64 or invalid universal slice')
            slices.extend(device_slices(binary[offset:offset + size]))
        return slices
    if magic != b'\xcf\xfa\xed\xfe' or len(binary) < 32:
        raise ValueError('Expected a 64-bit ARM64 Mach-O')
    _, cpu, _, _, count, length, _, _ = struct.unpack_from('<8I', binary)
    if cpu != 0x100000c or 32 + length > len(binary):
        raise ValueError('Invalid ARM64 Mach-O header')
    cursor, platforms, minimum = 32, [], None
    for _ in range(count):
        if cursor + 8 > 32 + length:
            raise ValueError('Truncated Mach-O command')
        command, size = struct.unpack_from('<II', binary, cursor)
        if size < 8 or cursor + size > 32 + length:
            raise ValueError('Invalid Mach-O command length')
        if command == 0x32:
            if size < 24:
                raise ValueError('Truncated platform build command')
            platforms.append(struct.unpack_from('<I', binary, cursor + 8)[0])
            packed = struct.unpack_from('<I', binary, cursor + 12)[0]
            minimum = [packed >> 16, (packed >> 8) & 255, packed & 255]
        cursor += size
    if cursor != 32 + length or platforms != [2]:
        raise ValueError('Mach-O must target iPhoneOS, not the simulator')
    return [{'architecture': 'arm64', 'platform': 'iPhoneOS', 'minimumOS': minimum}]


def verify(ipa, report, source):
    payload = ipa.read_bytes()
    sha = hashlib.sha256(payload).hexdigest()
    if report.get('sha256') != sha or report.get('bytes') != len(payload):
        raise ValueError('Downloaded IPA does not match the build report')
    if report.get('sourceCommit') != source:
        raise ValueError('Build source differs from the selected Actions run')
    binaries = []
    reference_fonts = []
    with zipfile.ZipFile(ipa) as archive:
        entries = archive.infolist()
        if len({e.filename for e in entries}) != len(entries):
            raise ValueError('Duplicate IPA archive paths')
        if sum(e.file_size for e in entries) > 512 * 1024 * 1024:
            raise ValueError('Unexpectedly large application archive')
        for entry in entries:
            path = PurePosixPath(entry.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in entry.filename:
                raise ValueError('Unsafe IPA archive path')
            if path.parts[:2] != ('Payload', 'Huevia.app'):
                raise ValueError('Unexpected additional IPA payload')
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Unexpected IPA symlink')
            if entry.file_size > 256 * 1024 * 1024:
                raise ValueError('Unexpectedly large application file')
            if path.name == 'kernel_blob.bin':
                raise ValueError('Development kernel found in a release IPA')
            binary = archive.read(entry)
            if binary[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
                binaries.append({'file': entry.filename, 'sha256': hashlib.sha256(binary).hexdigest(),
                                 'slices': device_slices(binary)})
        info = plistlib.loads(archive.read('Payload/Huevia.app/Info.plist'))
        expected = {'CFBundleIdentifier': 'cc.huevia.next', 'CFBundleSupportedPlatforms': ['iPhoneOS']}
        for key, value in expected.items():
            if info.get(key) != value:
                raise ValueError('Unexpected application identity or platform')
        for key, field in [('CFBundleShortVersionString', 'version'), ('CFBundleVersion', 'build'),
                           ('MinimumOSVersion', 'minimumOS')]:
            if info.get(key) != report.get(field):
                raise ValueError('Application metadata differs from build report: ' + key)
        for key in ('NSPhotoLibraryUsageDescription', 'NSPhotoLibraryAddUsageDescription'):
            if not isinstance(info.get(key), str) or not info[key].strip():
                raise ValueError('PhotoKit usage description is missing')
        if str(info['CFBundleVersion']).isdigit() and int(info['CFBundleVersion']) >= 202:
            font_root = Path(__file__).resolve().parents[1] / 'app/assets/fonts'
            manifest = json.loads((font_root / 'reference-fonts.json').read_text(encoding='utf-8'))
            for font in manifest['files']:
                matches = [entry.filename for entry in entries
                           if entry.filename.endswith('/' + font['file'])]
                flutter = [name for name in matches if '/flutter_assets/assets/fonts/' in name]
                native = [name for name in matches if 'HueviaNativeAssets.bundle/' in name]
                native_root = [name for name in native if name.endswith('HueviaNativeAssets.bundle/' + font['file'])]
                if len(flutter) != 1 or len(native_root) != 1 or len(native) not in (1, 2):
                    raise ValueError('Reference font is missing from Flutter or native border assets: ' + font['file'])
                for name in flutter + native:
                    data = archive.read(name)
                    if len(data) != font['bytes'] or hashlib.sha256(data).hexdigest() != font['sha256']:
                        raise ValueError('Reference font differs from the frozen Android source: ' + name)
                reference_fonts.append({'file': font['file'], 'sha256': font['sha256'],
                                        'flutterAsset': flutter[0], 'nativeAssets': native})
        required = {'Payload/Huevia.app/' + info['CFBundleExecutable'],
                    'Payload/Huevia.app/Frameworks/App.framework/App',
                    'Payload/Huevia.app/Frameworks/Flutter.framework/Flutter'}
        for entry in entries:
            if entry.filename.endswith('.framework/Info.plist'):
                framework = plistlib.loads(archive.read(entry))
                required.add(str(PurePosixPath(entry.filename).parent / framework['CFBundleExecutable']))
        if not required <= {b['file'] for b in binaries}:
            raise ValueError('Application, AOT, or declared framework device executable is missing')
        minimum = [int(part) for part in info['MinimumOSVersion'].split('.')]
        minimum += [0] * (3 - len(minimum))
        if any(s['minimumOS'] > minimum for b in binaries for s in b['slices']):
            raise ValueError('An executable requires a newer iOS than the application declares')
    return {'schema': 1, 'verified': True, 'sourceCommit': source, 'sha256': sha,
            'bytes': len(payload), 'bundleIdentifier': info['CFBundleIdentifier'],
            'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
            'minimumOS': info['MinimumOSVersion'], 'binaries': binaries,
            'referenceFonts': reference_fonts,
            'deviceInstallationVerified': False, 'fullParityComplete': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('report', type=Path)
    parser.add_argument('--source', required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.ipa, json.loads(args.report.read_text(encoding='utf-8')), args.source), indent=2))
