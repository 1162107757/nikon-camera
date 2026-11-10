"""Build the isolated event worker, without .env, account credentials or APKs."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib, json

root=Path(__file__).resolve().parents[1]
out=root/'build/data-backup'
out.mkdir(parents=True,exist_ok=True)
files={
 'index.js':(root/'backup/index.cjs').read_bytes(),
 **{f'backup/{name}':(root/'backup'/name).read_bytes() for name in ['core.mjs','runtime.mjs']},
 'backup/recovery/RECOVERY.md':(root/'backup/RECOVERY.md').read_bytes(),
 'backup/recovery/schema-migrations.sql':b'\n\n'.join(p.read_bytes() for p in sorted((root/'database').glob('[0-9]*.sql'))),
 'server/vendor/cos-sdk.cjs':(root/'server/vendor/cos-sdk.cjs').read_bytes(),
}
for path in (root/'server/vendor').iterdir():
 if path.name!='cos-sdk.cjs' and path.is_file():files['server/vendor/'+path.name]=path.read_bytes()
with ZipFile(out/'worker.zip','w',ZIP_DEFLATED,compresslevel=9) as z:
 for name,data in files.items():z.writestr(name,data)
sha=lambda b:hashlib.sha256(b).hexdigest()
manifest={'sha256':sha((out/'worker.zip').read_bytes()),'bytes':(out/'worker.zip').stat().st_size,
 'files':[{'path':name,'bytes':len(data),'sha256':sha(data)} for name,data in files.items()]}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'packageSha256':manifest['sha256'],'bytes':manifest['bytes'],'files':len(files)}))
