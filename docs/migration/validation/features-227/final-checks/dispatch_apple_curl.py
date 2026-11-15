from pathlib import Path
import subprocess,json
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent;s=json.loads((o/'source.json').read_text())['sourceCommit']
proof=json.loads((o/('apple-discovery-'+s[:12]+'-recovery')/'result.json').read_text());assert proof['status']=='not-found' and proof['successfulListGets']>=3 and all(x['apiSucceeded'] and x['totalCount']==0 and not x['exactMatches'] for x in proof['observations'])
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip()==s
attempt=o/('dispatch-curl-attempt-'+s[:12]+'.json');assert not attempt.exists(),'Never duplicate an uncertain curl POST';attempt.write_text(json.dumps({'sourceCommit':s,'transport':'Windows curl HTTPS HTTP1.1, certificate verification enabled','reason':'Two urllib SSL EOF requests, each followed by3 successful no-run GET proofs','inputs':{'verification':'full','apple_runner':'macos-26'}},indent=2))
p=subprocess.run(['git','credential','fill'],input=b'protocol=https\nhost=github.com\n\n',cwd=r,capture_output=True);assert p.returncode==0;cred=dict(x.split('=',1) for x in p.stdout.decode().splitlines() if '=' in x);secret=cred.get('password') or cred.get('credential');assert secret,'GitHub credential unavailable'
def quote(v):return '"'+v.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')+'"'
body=json.dumps({'ref':'codex/features215','inputs':{'verification':'full','apple_runner':'macos-26'}})
config='\n'.join(['url = '+quote('https://api.github.com/repos/1162107757/nikon-camera/actions/workflows/cross-platform-mobile.yml/dispatches'),'request = "POST"','header = '+quote('Authorization: Bearer '+secret),'header = '+quote('Accept: application/vnd.github+json'),'header = '+quote('Content-Type: application/json'),'header = '+quote('X-GitHub-Api-Version: 2022-11-28'),'data-binary = '+quote(body)])+'\n'
# Authentication config stays in stdin memory; it is never logged or written.
p=subprocess.run(['curl.exe','--config','-','--http1.1','--connect-timeout','20','--max-time','40','--silent','--show-error','--output',str(o/'dispatch-curl-response.json'),'--write-out','%{http_code}'],input=config.encode(),cwd=r,capture_output=True)
status=p.stdout.decode(errors='replace').strip();(o/'dispatch-curl-result.json').write_text(json.dumps({'sourceCommit':s,'curlExit':p.returncode,'httpStatus':status,'stderr':p.stderr.decode(errors='replace')},indent=2))
assert p.returncode==0 and status=='204','curl dispatch did not receive204; inspect result and GET runs before any retry'
(o/('dispatch-curl-ack-'+s[:12]+'.json')).write_text(json.dumps({'sourceCommit':s,'acknowledged':True,'httpStatus':204}))
print('HTTPS curl full/macOS26 dispatch acknowledged for '+s)
