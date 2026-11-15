from pathlib import Path
import hashlib,json,tarfile
base=Path(__file__).resolve().parent
manifest=json.loads((base/'archive-manifest.json').read_text(encoding='utf-8'))
sha=lambda data:hashlib.sha256(data).hexdigest()
containers={}
for artifact in manifest['artifacts']:
 data=(base/artifact['path']).read_bytes()
 assert len(data)==artifact['bytes'] and sha(data)==artifact['sha256'],artifact['path']
for entry in manifest['entries']:
 if entry['member'] is None:data=(base/entry['destination']).read_bytes()
 else:
  name=entry['destination']
  if name not in containers:
   with tarfile.open(base/name,'r:xz') as archive:containers[name]={m.name:archive.extractfile(m).read() for m in archive.getmembers() if m.isfile()}
  data=containers[name][entry['member']]
 assert len(data)==entry['sourceBytes']==entry['destinationBytes'] and sha(data)==entry['sourceSha256']==entry['destinationSha256'],entry
assert len(manifest['entries'])==manifest['originalFileCount']
print('VERIFIED '+str(len(manifest['entries']))+' original destination files/members; '+str(len(manifest['artifacts']))+' artifact hashes; source '+manifest['sourceCommit'])
