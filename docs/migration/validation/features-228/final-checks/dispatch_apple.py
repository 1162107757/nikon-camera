from pathlib import Path
import runpy,json,subprocess
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent;api=runpy.run_path(str(r/'.tooling/features212/github.py'))['api']
s=json.loads((o/'source.json').read_text())['sourceCommit']
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip()==s
assert not (o/('dispatch-attempt-'+s[:12]+'.json')).exists(),'Do not duplicate an uncertain POST; inspect Actions runs first'
(o/('dispatch-attempt-'+s[:12]+'.json')).write_text(json.dumps({'sourceCommit':s,'workflow':'cross-platform-mobile.yml','ref':'codex/features215','inputs':{'verification':'full','apple_runner':'macos-26'}},indent=2))
api('/actions/workflows/cross-platform-mobile.yml/dispatches',{'ref':'codex/features215','inputs':{'verification':'full','apple_runner':'macos-26'}})
(o/('dispatch-ack-'+s[:12]+'.json')).write_text(json.dumps({'sourceCommit':s,'acknowledged':True}))
print('Full Apple verification dispatched for '+s)
