from pathlib import Path
import hashlib, json, tarfile

r = Path(__file__).resolve().parents[2]
proof = {}
tar_cache = {}
for number in [227, 228]:
    root = r / f'docs/migration/validation/features-{number}'
    count = archive_members = 0
    for path in sorted(root.rglob('*.json')):
        value = json.loads(path.read_text(encoding='utf8'))
        if not isinstance(value, dict):
            continue
        parts = path.relative_to(root).parts
        if path.name == 'archive-manifest.json' and len(parts) == 2 and parts[0].startswith('android'):
            for entry in value['entries']:
                dest = (path.parent / entry['destination']).resolve()
                assert dest.is_relative_to(root.resolve()), str(dest)
                if entry['member']:
                    if dest not in tar_cache:
                        with tarfile.open(dest) as archive:
                            tar_cache[dest] = {
                                item.name: archive.extractfile(item).read()
                                for item in archive.getmembers() if item.isfile()}
                    raw = tar_cache[dest][entry['member']]
                    archive_members += 1
                else:
                    raw = dest.read_bytes()
                assert len(raw) == entry['sourceBytes'] == entry['destinationBytes'], entry
                assert hashlib.sha256(raw).hexdigest() == entry['sourceSha256'] == entry['destinationSha256'], entry
                count += 1
            for entry in value['artifacts']:
                dest = (path.parent / entry['path']).resolve()
                assert dest.is_relative_to(root.resolve()), str(dest)
                raw = dest.read_bytes()
                assert len(raw) == entry['bytes'] and hashlib.sha256(raw).hexdigest() == entry['sha256'], entry
                count += 1
        current_manifest = (
            path.name == 'byte-manifest.json' and (len(parts) == 1 or parts == ('shared','byte-manifest.json')
                or len(parts) == 3 and parts[0] == 'attempts')
            or parts == ('core','copy-manifest.json'))
        if current_manifest:
            base = root if path.parent.name == 'shared' else path.parent
            for entry in value.get('files', []):
                if not all(k in entry for k in ['path','bytes','sha256']):
                    continue
                dest = (base / entry['path']).resolve()
                assert dest.is_relative_to(root.resolve()), str(dest)
                raw = dest.read_bytes()
                assert len(raw) == entry['bytes'] and hashlib.sha256(raw).hexdigest() == entry['sha256'], (str(path),entry)
                count += 1
    proof[str(number)] = dict(manifestEntriesVerified=count,compressedMembersVerified=archive_members,
                              everyJsonParsed=True,allBytesAndSha256Match=True)
(r/'.tooling/next228/root-archives-verification.json').write_text(json.dumps(proof,indent=2)+'\n')
print(json.dumps(proof))
