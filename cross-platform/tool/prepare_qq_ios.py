#!/usr/bin/env python3
"""Prepare the pinned official QQ iOS SDK; validate every Mach-O platform before use."""
import hashlib
import io
import json
import pathlib
import plistlib
import shutil
import struct
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
URL = 'https://tangram-1251316161.file.myqcloud.com/files/20261030/8c572807d00ffda26d522fadceac7eca.zip'
SHA256 = '38a2fb7f26d8de683b942e16c5c1e46aeb054810d193bab0292686f8e5c74ae1'


def objects(data):
    magic = data[:4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        wide = magic[-1] == 0xbf
        count = struct.unpack_from('>I', data, 4)[0]
        for i in range(count):
            offset = 8 + i * (32 if wide else 20)
            start, size = struct.unpack_from('>QQ' if wide else '>II', data, offset + 8)
            yield from objects(data[start:start + size])
    elif data.startswith(b'!<arch>\n'):
        at = 8
        while at + 60 <= len(data):
            header = data[at:at + 60]
            if header[58:60] != b'`\n':
                raise ValueError('Invalid SDK archive member')
            size = int(header[48:58])
            body = data[at + 60:at + 60 + size]
            name = header[:16].decode('ascii').strip()
            if name.startswith('#1/'):
                body = body[int(name[3:]):]
            yield from objects(body)
            at += 60 + size + size % 2
    elif magic in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe'):
        is64 = magic == b'\xcf\xfa\xed\xfe'
        cpu = struct.unpack_from('<I', data, 4)[0]
        count = struct.unpack_from('<I', data, 16)[0]
        at = 32 if is64 else 28
        for _ in range(count):
            command, size = struct.unpack_from('<II', data, at)
            if size < 8 or at + size > len(data):
                raise ValueError('Invalid SDK Mach-O command')
            if command == 0x32:
                platform, minimum = struct.unpack_from('<II', data, at + 8)
                yield cpu, platform, minimum
                return
            at += size
        raise ValueError('SDK object lacks explicit LC_BUILD_VERSION platform')


def verify(path):
    info = plistlib.loads((path / 'Info.plist').read_bytes())
    summary = []
    for library in info['AvailableLibraries']:
        variant = library.get('SupportedPlatformVariant', '')
        expected = 7 if variant == 'simulator' else 2
        if library['SupportedPlatform'] != 'ios' or variant not in ('', 'simulator'):
            raise ValueError('Unexpected QQ SDK platform')
        binary = path / library['LibraryIdentifier'] / library['BinaryPath']
        rows = list(objects(binary.read_bytes()))
        if not rows or any(platform != expected for _, platform, _ in rows):
            raise ValueError('QQ SDK device/simulator binary mismatch')
        minimum = max(row[2] for row in rows)
        if minimum > 16 << 16:
            raise ValueError('QQ SDK requires newer iOS than application deployment target')
        cpu_names = {0x100000c: 'arm64', 0x1000007: 'x86_64'}
        actual = {cpu_names.get(row[0], str(row[0])) for row in rows}
        if actual != set(library['SupportedArchitectures']):
            raise ValueError('QQ SDK architecture metadata mismatch')
        summary.append({'slice': library['LibraryIdentifier'], 'platform': expected,
                        'architectures': sorted(actual), 'objects': len(rows),
                        'minimumIOS': f'{minimum >> 16}.{minimum >> 8 & 255}'})
    if len(summary) != 2 or {r['platform'] for r in summary} != {2, 7}:
        raise ValueError('QQ SDK must contain distinct device and simulator slices')
    return summary


def prepare():
    cache = ROOT / '.build' / 'qq-ios'
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / 'sdk.zip'
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        with urllib.request.urlopen(URL, timeout=45) as response:
            data = response.read(32 * 1024 * 1024 + 1)
        if len(data) > 32 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != SHA256:
            raise ValueError('Official QQ SDK checksum mismatch')
        archive.write_bytes(data)
    with zipfile.ZipFile(archive) as outer:
        inner = outer.read('TencentOpenAPI.xcframework(Lite).zip')
    staged = cache / 'prepared' / 'TencentOpenAPI.xcframework'
    if staged.exists():
        shutil.rmtree(staged)
    staged.mkdir(parents=True)
    with zipfile.ZipFile(io.BytesIO(inner)) as sdk:
        for entry in sdk.infolist():
            relative = pathlib.PurePosixPath(entry.filename)
            if relative.is_absolute() or '..' in relative.parts or entry.external_attr >> 16 & 0o170000 == 0o120000:
                raise ValueError('Unsafe official SDK archive path')
        sdk.extractall(staged)
    summary = verify(staged)
    destination = ROOT / 'native' / 'ios' / 'Frameworks' / 'TencentOpenAPI.xcframework'
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(staged, destination)
    print(json.dumps({'sdk': 'TencentOpenAPI 3.6.22.459', 'sha256': SHA256,
                      'slices': summary}, ensure_ascii=False))


if __name__ == '__main__':
    prepare()
