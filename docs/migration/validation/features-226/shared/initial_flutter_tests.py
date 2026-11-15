from pathlib import Path
import subprocess,os,json
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent;s=r/'.tooling/cross-platform187/flutter-sdk/bin';e=dict(os.environ,PUB_CACHE=str(r/'.tooling/cross-platform187/pub-cache'));results=[]
for name in ['camera_transfer_retirement_226_test.dart','camera_live_panel_226_test.dart','camera_live_test.dart','camera_live_panel_test.dart','camera_connection_test.dart','camera_sync_autoload_test.dart','camera_intent_test.dart','camera_downloads_test.dart']:
 with (o/(name+'.initial.log')).open('w',encoding='utf8') as f:p=subprocess.run([str(s/'flutter.bat'),'test','test/'+name,'--reporter','expanded','--concurrency=1'],cwd=r/'cross-platform/app',env=e,stdout=f,stderr=subprocess.STDOUT)
 results.append(dict(file=name,exit=p.returncode));(o/'initial-flutter-results.json').write_text(json.dumps(results,indent=2))
