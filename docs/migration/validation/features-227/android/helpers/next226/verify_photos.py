from pathlib import Path
import zipfile,json,hashlib
r=Path(__file__).resolve().parents[2]
photos=sorted((r/'app/src/main/assets/preset-showcase').glob('*.jpg'))
assert len(photos)==10
expected={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in photos}
results=[]
for version,abi in [(217,'arm64'),(227,'arm64'),(227,'x64')]:
    directory=r/'.tooling/next227/package-candidates' if version==227 else r/f'dist/migration{version}'
    p=directory/f'huevia-0.31.0-dev-{version}-android-{abi}.apk'
    with zipfile.ZipFile(p) as z:
        names=[n for n in z.namelist() if '/preset-showcase/' in n and n.endswith('.jpg')]
        actual={Path(n).name:hashlib.sha256(z.read(n)).hexdigest() for n in names}
        assert len(names)==10 and actual==expected
    results.append(dict(version=version,abi=abi,apkSha256=hashlib.sha256(p.read_bytes()).hexdigest(),images=actual))
report=dict(sourceCommit=json.loads((r/'.tooling/next227/source.json').read_text())['sourceCommit'],imageCount=10,allTenPreservedByteForByte=True,comparedTo217=True,repositoryImages=expected,android=results)
(r/'docs/migration/validation/features-227/preset-preview-assets.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'images':10,'androidApksChecked':3,'allTenPreservedByteForByte':True}))
