from pathlib import Path
import subprocess,os,json
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent
flutter=r/'.tooling/cross-platform187/flutter-sdk/bin/flutter.bat'
e=dict(os.environ,PUB_CACHE=str(r/'.tooling/cross-platform187/pub-cache'),JAVA_HOME='D:/dev/Java/jdk-17.0.19',PYTHONIOENCODING='utf-8')
steps=[('downloads-late-reply-format',['dart','format','lib/camera_downloads.dart','test/camera_downloads_test.dart']),('downloads-late-reply-analyze',['flutter','analyze','--no-pub']),('downloads-late-reply-tests',['flutter','test','test/camera_downloads_test.dart','--reporter','expanded','--verbose','--concurrency=1'])]
results=[]
for name,args in steps:
 tool=flutter.with_name('dart.bat') if args[0]=='dart' else flutter
 with (o/(name+'.log')).open('w',encoding='utf8') as out:q=subprocess.run([str(tool),*args[1:]],cwd=r/'cross-platform/app',env=e,stdout=out,stderr=subprocess.STDOUT)
 results.append(dict(step=name,exit=q.returncode));(o/'downloads-late-reply-result.json').write_text(json.dumps(results,indent=2))
 if q.returncode:raise SystemExit(q.returncode)
