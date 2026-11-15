from pathlib import Path
import subprocess,os,json,time
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent
flutter=r/'.tooling/cross-platform187/flutter-sdk/bin/flutter.bat'
e=dict(os.environ,PUB_CACHE=str(r/'.tooling/cross-platform187/pub-cache'),JAVA_HOME='D:/dev/Java/jdk-17.0.19',PYTHONUTF8='1',PYTHONIOENCODING='utf-8')
changed=subprocess.check_output(['git','diff','--name-only','--','cross-platform/app'],cwd=r,text=True).splitlines()+subprocess.check_output(['git','ls-files','--others','--exclude-standard','cross-platform/app'],cwd=r,text=True).splitlines()
files=sorted({str(Path(x).relative_to('cross-platform/app')).replace('\\','/') for x in changed if x.endswith('.dart')})
results=[]
targets=['camera_live_start_connection_test.dart','camera_selection_download_test.dart','capsule_switch_test.dart','camera_live_panel_226_test.dart','camera_live_panel_test.dart','camera_transfer_retirement_226_test.dart','camera_reconnect_226_test.dart','camera_intent_test.dart','camera_sync_autoload_test.dart','camera_design_ui_test.dart']
marker=o/'controllers-frozen.json'
if marker.exists():targets+=json.loads(marker.read_text()).get('additionalTestTargets',[])
for name in dict.fromkeys(targets):
 with (o/(name+'.log')).open('w',encoding='utf8') as f:
  try:p=subprocess.run([str(flutter),'test','test/'+name,'--reporter','expanded','--verbose','--concurrency=1'],cwd=r/'cross-platform/app',env=e,stdout=f,stderr=subprocess.STDOUT,timeout=180);code=p.returncode
  except subprocess.TimeoutExpired:code=124
 results.append(dict(file=name,exit=code));(o/'ui-regression-results.json').write_text(json.dumps(results,indent=2))
