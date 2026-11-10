"""Check the shipped DEX method references, not just Java source or host-JDK behavior."""
import argparse
import json
import struct
from pathlib import Path
from zipfile import ZipFile

parser = argparse.ArgumentParser()
parser.add_argument('apk', type=Path)
parser.add_argument('--expect', choices=['baseline', 'compatible'], required=True)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
found = []

with ZipFile(args.apk) as archive:
    for name in archive.namelist():
        if not name.endswith('.dex'):
            continue
        data = archive.read(name)
        assert data[:4] == b'dex\n', 'Expected standard DEX'
        u32 = lambda at: struct.unpack_from('<I', data, at)[0]
        u16 = lambda at: struct.unpack_from('<H', data, at)[0]
        strings = []
        for i in range(u32(56)):
            pos = u32(u32(60) + i * 4)
            while data[pos] & 0x80:
                pos += 1
            pos += 1
            strings.append(data[pos:data.index(b'\0', pos)].decode('utf-8', errors='replace'))
        types = [strings[u32(u32(68) + i * 4)] for i in range(u32(64))]
        for i in range(u32(88)):
            at = u32(92) + i * 8
            if types[u16(at)] != 'Ljava/net/URLEncoder;' or strings[u32(at + 4)] != 'encode':
                continue
            proto = u32(76) + u16(at + 2) * 12
            param = u32(proto + 8)
            parameters = [] if not param else [types[u16(param + 4 + j * 2)] for j in range(u32(param))]
            found.append({'dex': name, 'class': 'java.net.URLEncoder', 'method': 'encode',
                          'descriptor': '(' + ''.join(parameters) + ')' + types[u32(proto + 4)]})

unsafe = '(Ljava/lang/String;Ljava/nio/charset/Charset;)Ljava/lang/String;'
legacy = '(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;'
has_unsafe = any(m['descriptor'] == unsafe for m in found)
has_legacy = any(m['descriptor'] == legacy for m in found)
passed = has_unsafe if args.expect == 'baseline' else not has_unsafe and has_legacy
result = {'apk': str(args.apk), 'expectation': args.expect, 'pass': passed,
          'charsetOverloadRemaining': has_unsafe, 'legacyEncodingNameOverload': has_legacy,
          'methodReferences': found,
          'apiReference': 'https://developer.android.com/reference/java/net/URLEncoder'}
if args.output:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result))
assert passed, 'Shipped encoding API expectation failed'
