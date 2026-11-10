"""Capture original projects and Android feature obligations without modifying them."""
from pathlib import Path
import hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/migration'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def tracked(*paths):
    return [ROOT/p for p in subprocess.check_output(['git','ls-files','-z',*paths],cwd=ROOT).decode().split('\0') if p]
def capture():
    files=tracked('app','ios')
    manifest={'baselineCommit':'6fb5003d8be85fcbb0fa3b4d99aef63cc1751f3c','files':[{'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':digest(p),'bytes':p.stat().st_size} for p in files]}
    (OUT/'preserved-projects.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    java=list((ROOT/'app/src/main/java').rglob('*.java'))
    classes=[]
    for p in java:
        text=p.read_text(encoding='utf-8-sig');classes.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':digest(p),'lines':len(text.splitlines()),'androidApiReferences':bool(re.search(r'\bandroid\.',text)),'imports':re.findall(r'^import\s+([^;]+);',text,re.M)})
    (OUT/'java-core-inventory.json').write_text(json.dumps(classes,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'preservedFiles':len(files),'javaFiles':len(classes),'javaLines':sum(p['lines'] for p in classes),'withoutAndroidReferences':sum(not p['androidApiReferences'] for p in classes)}))
def verify():
    manifest=json.loads((OUT/'preserved-projects.json').read_text(encoding='utf-8'))
    changed=[]
    for row in manifest['files']:
        path=ROOT/row['path']
        if not path.is_file():changed.append(row['path']);continue
        if digest(path)==row['sha256']:continue
        # Git may check text out with LF on macOS and CRLF on Windows. Accept
        # that conversion only when Git's canonical blob is still identical.
        actual=subprocess.check_output(['git','hash-object','--path',row['path'],row['path']],cwd=ROOT,text=True).strip()
        expected=row.get('gitBlob')
        if not expected or actual!=expected:changed.append(row['path'])
    if changed:raise SystemExit('Original project changed: '+', '.join(changed))
    print('Original Android/iOS files unchanged: '+str(len(manifest['files'])))
if __name__=='__main__':
    import sys
    verify() if '--verify' in sys.argv else capture()
