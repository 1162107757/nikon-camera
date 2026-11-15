from pathlib import Path
import runpy,json,subprocess
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent;api=runpy.run_path(str(r/'.tooling/features212/github.py'))['api'];s=json.loads((o/'source.json').read_text())['sourceCommit']
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip()==s
proof=json.loads((o/('apple-discovery-'+s[:12])/'result.json').read_text());assert proof['sourceCommit']==s and proof['successfulListGets']>=3 and proof['status']=='not-found';assert all(x['apiSucceeded'] and x['totalCount']==0 and not x['exactMatches'] for x in proof['observations'])
f=o/('dispatch-recovery-attempt-'+s[:12]+'.json');assert not f.exists(),'Recovery POST must not be duplicated';f.write_text(json.dumps({'sourceCommit':s,'reason':'Initial SSL EOF; three independent successful GETs show no matching run','absenceProof':'apple-discovery-'+s[:12]+'/result.json','inputs':{'verification':'full','apple_runner':'macos-26'}},indent=2))
api('/actions/workflows/cross-platform-mobile.yml/dispatches',{'ref':'codex/features215','inputs':{'verification':'full','apple_runner':'macos-26'}})
(o/('dispatch-recovery-ack-'+s[:12]+'.json')).write_text(json.dumps({'sourceCommit':s,'acknowledged':True,'recoveryAfterThreeConfirmedEmptyGets':True}))
print('Recovery dispatch acknowledged for '+s)
