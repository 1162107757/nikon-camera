from pathlib import Path
import subprocess,os,json
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent
flutter=r/'.tooling/cross-platform187/flutter-sdk/bin/flutter.bat'
e=dict(os.environ,PUB_CACHE=str(r/'.tooling/cross-platform187/pub-cache'),JAVA_HOME='D:/dev/Java/jdk-17.0.19',PYTHONIOENCODING='utf-8')
steps=[('a-dialog-readiness-format',['dart','format','lib/camera_live_card.dart','test/camera_live_panel_226_test.dart']),('a-dialog-readiness-analyze',['flutter','analyze','--no-pub']),('a-dialog-readiness-tests',['flutter','test','test/camera_live_panel_226_test.dart','--reporter','expanded','--verbose','--concurrency=1'])]
results=[]
for name,args in steps:
 tool=flutter.with_name('dart.bat') if args[0]=='dart' else flutter
 with (o/(name+'.log')).open('w',encoding='utf8') as out:q=subprocess.run([str(tool),*args[1:]],cwd=r/'cross-platform/app',env=e,stdout=out,stderr=subprocess.STDOUT)
 results.append(dict(step=name,exit=q.returncode));(o/'a-dialog-readiness-result.json').write_text(json.dumps(results,indent=2))
 if q.returncode:raise SystemExit(q.returncode)
