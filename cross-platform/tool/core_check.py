from pathlib import Path
import json,subprocess,os,sys
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'cross-platform/.build/core-jvm'
OUT.mkdir(parents=True,exist_ok=True)
sources=json.loads((ROOT/'cross-platform/core/portable-sources.json').read_text())['sources']
sources += [str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'cross-platform/core/java').rglob('*.java')]
sources += [str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'cross-platform/core/test').rglob('*.java')]
sources += ['tests/java/cc/huevia/ncp/NcpPreviewProfileTest.java','tests/java/cc/huevia/ncp/NcpCompatibilityFixtures.java','tests/local-edits-java/cc/huevia/ncp/PhotoLocalEditsTest.java','tests/raw-development-java/cc/huevia/ncp/RawJpegColorMatchTest.java','tests/raw-development-java/cc/huevia/ncp/RawHighlightColorTest.java']
java_home=os.environ.get('JAVA_HOME',r'D:/dev/Java/jdk-17.0.19')
javac=str(Path(java_home)/'bin'/('javac.exe' if os.name=='nt' else 'javac'))
java=str(Path(java_home)/'bin'/('java.exe' if os.name=='nt' else 'java'))
args=['--release','11','-encoding','UTF-8','-d',str(OUT/'classes')]+[str(ROOT/p) for p in sources]
argfile=OUT/'javac.args';argfile.write_text('\n'.join('"'+a.replace('\\','/')+'"' for a in args),encoding='utf-8')
subprocess.run([javac,'-J-Xmx512m','@'+str(argfile)],cwd=ROOT,check=True)
run=subprocess.run([java,'-Xmx256m','-Dfile.encoding=UTF-8','-cp',str(OUT/'classes'),'cc.huevia.shared.CoreParity'],cwd=ROOT,text=True,encoding='utf-8',capture_output=True)
(OUT/'run.log').write_text(run.stdout+run.stderr,encoding='utf-8')
if run.returncode:print(run.stderr[-3000:]);raise SystemExit(run.returncode)
golden=next(line.split('=',1)[1] for line in run.stdout.splitlines() if line.startswith('HUEVIA_CORE_GOLDEN='))
(OUT/'golden.json').write_text(json.dumps(json.loads(golden),indent=2)+'\n',encoding='utf-8')
(OUT/'sources.json').write_text(json.dumps(sources,indent=2)+'\n',encoding='utf-8')
print('\n'.join(line for line in run.stdout.splitlines() if line.startswith('PASS')))
print('Shared JVM golden: '+str(OUT/'golden.json'))
