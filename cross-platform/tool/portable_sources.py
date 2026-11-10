"""Find a Java 11-compilable closure; excluded classes remain explicit migration work."""
from pathlib import Path
import json,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'.tooling/cross-platform187/portable-closure'
WORK.mkdir(parents=True,exist_ok=True)
java=Path(r'D:/dev/Java/jdk-17.0.19/bin/javac.exe')
sources=[p for p in (ROOT/'app/src/main/java').rglob('*.java') if not re.search(r'\bandroid\.',p.read_text(encoding='utf-8-sig'))]
adapters=list((ROOT/'cross-platform/core/adapters').rglob('*.java'))
helpers=list((ROOT/'cross-platform/core/java').rglob('*.java'))
excluded=[]
for iteration in range(15):
    args=['--release','11','-encoding','UTF-8','-Xmaxerrs','1000','-d',str(WORK/'classes')]+[str(p) for p in sources+adapters+helpers]
    argfile=WORK/'javac.args';argfile.write_text('\n'.join('"'+a.replace('\\','/')+'"' for a in args),encoding='utf-8')
    result=subprocess.run([str(java),'-J-Duser.language=en','-J-Duser.country=US','@'+str(argfile)],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace')
    (WORK/f'compile-{iteration}.log').write_text(result.stderr+result.stdout,encoding='utf-8')
    if result.returncode==0:break
    names=set(re.findall(r'([^/\\:\n]+\.java):\d+: error:',result.stderr))
    failed=[p for p in sources if p.name in names]
    if not failed:raise SystemExit('Unclassified compiler failure: '+str(WORK/f'compile-{iteration}.log'))
    for p in failed:excluded.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'reason':'Requires a class/API outside the current portable Java closure','compilerLog':str((WORK/f'compile-{iteration}.log').relative_to(ROOT)).replace('\\','/')})
    sources=[p for p in sources if p not in failed]
else:raise SystemExit('Portable closure did not converge')
manifest={'sourceLevel':11,'sources':[str(p.relative_to(ROOT)).replace('\\','/') for p in sources+adapters],'excluded':excluded}
(ROOT/'cross-platform/core/portable-sources.json').parent.mkdir(parents=True,exist_ok=True)
(ROOT/'cross-platform/core/portable-sources.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'portableSources':len(sources),'excludedFromInitialClosure':len(excluded),'iterations':iteration+1}))
