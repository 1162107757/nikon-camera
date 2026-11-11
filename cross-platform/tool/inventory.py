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
    # Keep the frozen 186 record. Separately identify original-project repairs
    # authorized after migration started; every accepted blob must be pinned.
    allowed={}
    updates=OUT/'approved-original-updates.json'
    if updates.is_file():
        approval=json.loads(updates.read_text(encoding='utf-8'))
        if approval.get('baselineCommit')!=manifest['baselineCommit']:
            raise SystemExit('Original update baseline does not match the frozen manifest')
        baseline={}
        for entry in subprocess.check_output(['git','ls-tree','-r','-z',manifest['baselineCommit'],'--','app','ios'],cwd=ROOT).split(b'\0'):
            if entry:
                meta,path=entry.decode().split('\t',1);baseline[path]=meta.split()[2]
        for row in manifest['files']:
            if not row.get('gitBlob') or baseline.get(row['path'])!=row['gitBlob']:
                raise SystemExit('Frozen original Git reference changed: '+row['path'])
        previous=manifest['baselineCommit']
        for update in approval['updates']:
            commit=update['commit']
            if not re.fullmatch(r'[0-9a-f]{40}',commit) or subprocess.run(['git','merge-base','--is-ancestor',previous,commit],cwd=ROOT).returncode:
                raise SystemExit('Original repairs must follow the frozen commit history')
            seen=set()
            for row in update['files']:
                path=row['path']
                if path not in baseline or path in seen:
                    raise SystemExit('Invalid original update path: '+path)
                seen.add(path)
                pinned=subprocess.check_output(['git','rev-parse',update['commit']+':'+path],cwd=ROOT,text=True).strip()
                if pinned!=row['gitBlob']:
                    raise SystemExit('Original update does not match its pinned commit: '+path)
                allowed[path]=pinned
            previous=commit
    changed=[]
    for row in manifest['files']:
        path=ROOT/row['path']
        if not path.is_file():changed.append(row['path']);continue
        if row['path'] not in allowed and digest(path)==row['sha256']:continue
        # Git may check text out with LF on macOS and CRLF on Windows. Accept
        # that conversion only when Git's canonical blob is still identical.
        actual=subprocess.check_output(['git','hash-object','--path',row['path'],row['path']],cwd=ROOT,text=True).strip()
        expected=allowed.get(row['path'],row.get('gitBlob'))
        if not expected or actual!=expected:changed.append(row['path'])
    if changed:raise SystemExit('Original project changed: '+', '.join(changed))
    if allowed:
        print('Frozen original Git reference preserved: '+str(len(manifest['files']))+
              '; approved original repairs verified: '+str(len(allowed))+
              '; other original files unchanged: '+str(len(manifest['files'])-len(allowed)))
    else:print('Original Android/iOS files unchanged: '+str(len(manifest['files'])))
if __name__=='__main__':
    import sys
    verify() if '--verify' in sys.argv else capture()
