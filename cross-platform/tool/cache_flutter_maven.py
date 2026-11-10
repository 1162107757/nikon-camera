"""Download exact official engine artifacts when local Java TLS cannot reach GCS."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib,json,subprocess,sys,zipfile
ROOT=Path(__file__).resolve().parents[2]
pin=json.loads((ROOT/'cross-platform/toolchain.json').read_text())
engine=pin['engineRevision']
mode=sys.argv[1] if len(sys.argv)>1 else 'debug'
if mode not in ['debug','release','profile']:raise SystemExit('Unsupported engine mode')
repo=ROOT/'.tooling/cross-platform187/flutter-maven'
arches=sys.argv[2:] or ['armeabi_v7a','arm64_v8a','x86_64']
if any(arch not in ['armeabi_v7a','arm64_v8a','x86_64'] for arch in arches):raise SystemExit('Unsupported engine architecture')
names=['flutter_embedding',*arches]
def fetch(name):
    artifact=name+'_'+mode;version='1.0.0-'+engine;relative='io/flutter/'+artifact+'/'+version
    destination=repo/relative;destination.mkdir(parents=True,exist_ok=True)
    evidence=[]
    for extension in ['pom','jar']:
        filename=artifact+'-'+version+'.'+extension;target=destination/filename
        url='https://storage.googleapis.com/download.flutter.io/'+relative+'/'+filename
        if target.is_file() and extension=='jar' and not zipfile.is_zipfile(target):target.unlink()
        if not target.is_file():
            subprocess.run(['curl.exe' if sys.platform=='win32' else 'curl','--fail','--location','--silent','--show-error','--retry','3','--connect-timeout','15','--max-time','240','--max-filesize','536870912',url,'--output',str(target)],check=True)
        if extension=='jar' and not zipfile.is_zipfile(target):raise RuntimeError('Invalid official engine JAR: '+artifact)
        if extension=='pom' and (artifact not in target.read_text() or version not in target.read_text()):raise RuntimeError('Engine POM mismatch')
        evidence.append({'url':url,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    return evidence
with ThreadPoolExecutor(max_workers=2) as pool:records=[row for result in pool.map(fetch,names) for row in result]
(repo/('evidence-'+mode+'.json')).write_text(json.dumps(records,indent=2)+'\n')
print('Cached '+str(len(records))+' official pinned engine files in '+str(repo))
