from pathlib import Path
import subprocess,os,json
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent;flutter=r/'.tooling/cross-platform187/flutter-sdk/bin/flutter.bat'
e=dict(os.environ,PUB_CACHE=str(r/'.tooling/cross-platform187/pub-cache'),JAVA_HOME='D:/dev/Java/jdk-17.0.19',PYTHONUTF8='1',PYTHONIOENCODING='utf-8')
res=[]
def run(name,args):
 with (o/(name+'.log')).open('w',encoding='utf8') as f:
  p=subprocess.Popen(args,cwd=r/'cross-platform/app',env=e,stdout=f,stderr=subprocess.STDOUT)
  try:code=p.wait(timeout=45)
  except subprocess.TimeoutExpired:
   subprocess.run(['taskkill.exe','/PID',str(p.pid),'/T','/F'],stdout=f,stderr=subprocess.STDOUT);code=124
 res.append({'step':name,'exit':code});(o/'verified-regressions.json').write_text(json.dumps(res,indent=2))
 return code
if run('manual-verified-format',[str(flutter.with_name('dart.bat')),'format','test/camera_transfer_test.dart','test/camera_live_start_connection_test.dart']):raise SystemExit(1)
if run('analyze-verified',[str(flutter),'analyze','--no-pub']):raise SystemExit(1)
run('manual-verified',[str(flutter),'test','test/camera_transfer_test.dart','--reporter','expanded','--verbose','--concurrency=1'])
names=['Live tab and disconnected Start connect before one jpeg confirmation without loading camera photos','Live tab and disconnected Start connect before one raw confirmation without loading camera photos','Canceling a disconnected Start ends its intent even if another session becomes available','A connected snapshot with an empty session still reconnects before it can start','A to B to A account changes retire an awaiting Start connection intent','A valid session without RAW capability reports the format limitation without reconnecting']
for i,name in enumerate(names,1):run('start-verified-'+str(i),[str(flutter),'test','test/camera_live_start_connection_test.dart','--plain-name',name,'--reporter','expanded','--verbose','--concurrency=1'])
