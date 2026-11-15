from pathlib import Path
import hashlib, json, sys

r=Path(__file__).resolve().parents[2]
assert '--write' in sys.argv or '--verify' in sys.argv
report={}
for number,source in [(227,'ac5a7ef4ceca2d1b180d6321f683f90241f1234f'),(228,'734aa3b0f6687dda815af9e13070f0f3c463873c')]:
    root=r/f'docs/migration/validation/features-{number}'
    manifest=root/'byte-manifest.json'
    metadata=json.loads((root/'source.json').read_text(encoding='utf8'))
    package_metadata=json.loads((r/f'dist/migration{number}/ARTIFACTS.json').read_text(encoding='utf8'))
    assert metadata==package_metadata and metadata['sourceCommit']==source
    assert metadata['published'] is False and metadata['acceptedForDelivery'] is False
    package_checks=[]
    for item in metadata['artifacts']:
        file=r/f'dist/migration{number}'/item['file'];raw=file.read_bytes()
        assert len(raw)==item['bytes'] and hashlib.sha256(raw).hexdigest()==item['sha256']
        assert item['sourceCommit']==source and item['published'] is False and item['acceptedForLocalTesting'] is True
        package_checks.append({'file':item['file'],'bytes':len(raw),'sha256':item['sha256']})
    if '--write' in sys.argv:
        files=[]
        for file in sorted(root.rglob('*')):
            if not file.is_file() or file==manifest:
                continue
            assert file.resolve().is_relative_to(root.resolve())
            raw=file.read_bytes()
            if file.suffix=='.json':json.loads(raw.decode('utf8'))
            files.append(dict(path=file.relative_to(root).as_posix(),bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()))
        value=dict(schemaVersion=1,sourceCommit=source,published=False,
            qualification='Byte manifest includes all files, including nested attempt manifests; only this exact root manifest is excluded to avoid self-reference.',
            fileCount=len(files),totalBytes=sum(x['bytes'] for x in files),files=files)
        manifest.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    value=json.loads(manifest.read_text(encoding='utf8'))
    declared={x['path'] for x in value['files']}
    actual={x.relative_to(root).as_posix() for x in root.rglob('*') if x.is_file() and x!=manifest}
    assert actual==declared,(number,actual-declared,declared-actual)
    for entry in value['files']:
        file=(root/entry['path']).resolve();assert file.is_relative_to(root.resolve())
        raw=file.read_bytes()
        assert len(raw)==entry['bytes'] and hashlib.sha256(raw).hexdigest()==entry['sha256'],entry['path']
    assert value['fileCount']==len(declared)
    report[str(number)]=dict(sourceCommit=source,allFilesVerified=len(declared),bytes=value['totalBytes'],
        manifestSha256=hashlib.sha256(manifest.read_bytes()).hexdigest(),packages=package_checks,
        iosAcceptedForLocalTesting=metadata['iosAcceptedForLocalTesting'],published=False)
(r/'.tooling/next228/global-integrity-result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
