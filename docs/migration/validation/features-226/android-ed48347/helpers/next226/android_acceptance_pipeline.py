from pathlib import Path
import json,subprocess,time
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent
until=time.monotonic()+1200
while not (o/'android-release-result.json').exists():
 if time.monotonic()>until:raise SystemExit('Build receipt timeout')
 time.sleep(3)
b=json.loads((o/'android-release-result.json').read_text());assert b['exit']==0,b
res={}
for n in ['verify_android','verify_photos','run_release_runtime','check_back_navigation']:
 with (o/(n+'-pipeline.log')).open('w',encoding='utf8') as f:p=subprocess.run(['python',str(o/(n+'.py'))],cwd=r,stdout=f,stderr=subprocess.STDOUT)
 res[n]=p.returncode;(o/'android-acceptance-pipeline.json').write_text(json.dumps(res,indent=2))
 if p.returncode:break
