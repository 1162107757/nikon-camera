from pathlib import Path
import hashlib, json, subprocess

r = Path(__file__).resolve().parents[2]
p = Path(__file__).parent
d = r / 'docs/migration/validation/features-228/core'
baseline = r / 'docs/migration/validation/features-227/core'
source = json.loads((p/'source.json').read_text())['sourceCommit']
inputs = json.loads((baseline/'input-fingerprints.json').read_text())
files = inputs['files']
assert len(files) == 246 and inputs['inputCount'] == 261
specs = ''.join(source + ':' + x['path'] + '\n' for x in files)
batch = subprocess.run(['git','cat-file','--batch'],input=specs.encode(),stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE,cwd=r,check=True).stdout
cursor = 0
verified = []
for entry in files:
    end = batch.index(b'\n',cursor)
    header = batch[cursor:end].split()
    assert len(header) == 3 and header[1] == b'blob', header
    size = int(header[2]); data = batch[end+1:end+1+size]
    cursor = end + size + 2
    raw = (r/entry['path']).read_bytes()
    assert hashlib.sha256(data).hexdigest() == entry['gitLfSha256'], entry['path']
    assert hashlib.sha256(raw).hexdigest() == entry['rawSha256'], entry['path']
    verified.append(dict(path=entry['path'],gitSha256=entry['gitLfSha256'],rawSha256=entry['rawSha256']))
assert cursor == len(batch)
raw_proofs = []
manifest = json.loads((baseline/'copy-manifest.json').read_text())
for entry in manifest['files']:
    raw = (baseline/entry['path']).read_bytes()
    assert len(raw) == entry['bytes'] and hashlib.sha256(raw).hexdigest() == entry['sha256']
    raw_proofs.append(dict(path='../../features-227/core/'+entry['path'],bytes=len(raw),sha256=entry['sha256']))
proof = dict(sourceCommit=source,totalSharedChecks=1891,inputCount=261,distinctInputCount=246,
    allInputsMatch=True,testRerunForBinding=False,actualFresh228Execution=False,
    reusedActual227Execution=True,qualification='UI-only228 reuses unchanged227 JVM execution; all inputs bound to228 Git. Binding is not a test rerun.',
    originalExecution='../../features-227/core/result.json',originalRawProofs=raw_proofs,files=verified)
(d/'source-binding.json').write_text(json.dumps(proof,indent=2)+'\n')
s=json.loads((p/'source.json').read_text());s['jvm'].update(sourceBindingPending=False,immutableBindingSourceCommit=source)
(p/'source.json').write_text(json.dumps(s,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('Bound unchanged227 JVM1891 execution,261/246 inputs to228; no rerun claimed')
