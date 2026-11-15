from pathlib import Path
import subprocess,json
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent
with (o/'check_back_navigation-pipeline.log').open('w',encoding='utf8') as f:p=subprocess.run(['python',str(o/'check_back_navigation.py')],cwd=r,stdout=f,stderr=subprocess.STDOUT)
j=json.loads((o/'android-acceptance-pipeline.json').read_text());j['check_back_navigation']=p.returncode;(o/'android-acceptance-pipeline.json').write_text(json.dumps(j,indent=2))
(o/'back-final.exit').write_text(str(p.returncode))
