from pathlib import Path
import subprocess
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent
with (o/'core-check-canonical.log').open('w',encoding='utf8') as f:p=subprocess.run(['python',str(o/'core_check_canonical.py')],cwd=r,stdout=f,stderr=subprocess.STDOUT)
(o/'core-check-canonical.exit').write_text(str(p.returncode))
