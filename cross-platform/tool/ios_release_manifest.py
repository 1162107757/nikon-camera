#!/usr/bin/env python3
"""Create a manifest for an actual unsigned device IPA; never invent a distribution URL."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import struct
import urllib.parse
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('ipa', type=pathlib.Path)
parser.add_argument('--download-url', required=True)
parser.add_argument('--notes-file', type=pathlib.Path, required=True)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
url = urllib.parse.urlsplit(args.download_url)
if url.scheme != 'https' or not url.hostname or url.username or url.password or url.fragment:
    parser.error('Provide the real HTTPS IPA asset URL')
with zipfile.ZipFile(args.ipa) as ipa:
    paths = [name for name in ipa.namelist() if re.fullmatch(r'Payload/[^/]+[.]app/Info[.]plist', name)]
    if len(paths) != 1:
        parser.error('IPA must contain exactly one application')
    info = plistlib.loads(ipa.read(paths[0]))
    binary = ipa.read(str(pathlib.PurePosixPath(paths[0]).parent / info['CFBundleExecutable']))
    offset = 0
    if binary[:4] == b'\xca\xfe\xba\xbe':
        offsets = [struct.unpack_from('>IIIII', binary, 8 + 20 * i) for i in range(struct.unpack_from('>I', binary, 4)[0])]
        matches = [entry for entry in offsets if entry[0] == 0x100000c]
        if len(matches) != 1:
            parser.error('IPA must contain a device ARM64 executable')
        offset = matches[0][2]
    if binary[offset:offset + 4] != b'\xcf\xfa\xed\xfe' or struct.unpack_from('<I', binary, offset + 4)[0] != 0x100000c:
        parser.error('IPA executable is not ARM64 Mach-O')
    at, platform = offset + 32, None
    for _ in range(struct.unpack_from('<I', binary, offset + 16)[0]):
        command, size = struct.unpack_from('<II', binary, at)
        if command == 0x32:
            platform = struct.unpack_from('<I', binary, at + 8)[0]
        at += size
    if platform != 2:
        parser.error('IPA executable is not built for iPhoneOS')
    prefix = str(pathlib.PurePosixPath(paths[0]).parent) + '/'
    if any(name.startswith(prefix + '_CodeSignature/') for name in ipa.namelist()) or prefix + 'embedded.mobileprovision' in ipa.namelist():
        parser.error('This channel accepts unsigned IPA only; remove signing material in the packaging stage')
notes = args.notes_file.read_text(encoding='utf-8')
if len(notes) > 12000 or not re.fullmatch(r'[0-9A-Za-z][0-9A-Za-z._+-]{0,99}', info['CFBundleShortVersionString']):
    parser.error('Release notes or version name is invalid')
manifest = {'schema': 1, 'platform': 'ios', 'distribution': 'unsigned-ipa',
    'bundleId': info['CFBundleIdentifier'], 'versionName': info['CFBundleShortVersionString'],
    'versionCode': int(info['CFBundleVersion']), 'minimumIOS': info['MinimumOSVersion'], 'downloadUrl': args.download_url,
    'sha256': hashlib.file_digest(args.ipa.open('rb'), 'sha256').hexdigest(),
    'byteLength': args.ipa.stat().st_size, 'notes': notes}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'output': str(args.output), 'bundleId': manifest['bundleId'],
    'versionCode': manifest['versionCode'], 'sha256': manifest['sha256'], 'published': False}))
