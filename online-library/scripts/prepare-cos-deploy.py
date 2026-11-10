"""Overlay the reviewed COS files onto the exact current production ZIP."""
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
folder = root / '.local' / 'cos-migration'
changed = ['server/app.mjs', 'server/index.mjs', 'server/releases.mjs', 'server/cos-release-storage.mjs',
           'server/vendor/cos-sdk.cjs', 'server/vendor/cos-sdk.manifest.json', 'server/vendor/COS-NOTICES.txt']
digest = lambda data: hashlib.sha256(data).hexdigest()
report = []
with ZipFile(folder / 'before.zip') as previous, ZipFile(folder / 'next.zip', 'w') as output:
    names = previous.namelist()
    if len(names) != len(set(names)):
        raise RuntimeError('Duplicate production archive entries')
    for item in previous.infolist():
        data = previous.read(item)
        if item.filename in changed:
            replacement = (root / item.filename).read_bytes()
            if digest(data) == digest(replacement):
                raise RuntimeError('Expected production change absent: ' + item.filename)
            report.append({'path': item.filename, 'before': digest(data), 'after': digest(replacement)})
            data = replacement
        output.writestr(item, data)
    for name in changed:
        if name in names:
            continue
        data = (root / name).read_bytes()
        item = ZipInfo(name)
        item.create_system = 3
        item.external_attr = 0o100644 << 16
        item.compress_type = ZIP_DEFLATED
        output.writestr(item, data)
        report.append({'path': name, 'before': None, 'after': digest(data)})
with ZipFile(folder / 'before.zip') as previous, ZipFile(folder / 'next.zip') as following:
    for name in previous.namelist():
        if name not in changed and previous.read(name) != following.read(name):
            raise RuntimeError('Unrelated production content changed')
        if previous.getinfo(name).external_attr != following.getinfo(name).external_attr:
            raise RuntimeError('Production file mode changed')
    if following.testzip():
        raise RuntimeError('Invalid deployment archive')
manifest = {'files': report, 'beforeSha256': digest((folder / 'before.zip').read_bytes()),
            'nextSha256': digest((folder / 'next.zip').read_bytes()), 'nextBytes': (folder / 'next.zip').stat().st_size}
(folder / 'deploy-audit.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps({'changedFiles': len(report), 'unrelatedFilesPreserved': True, 'bytes': manifest['nextBytes'], 'sha256': manifest['nextSha256']}))
