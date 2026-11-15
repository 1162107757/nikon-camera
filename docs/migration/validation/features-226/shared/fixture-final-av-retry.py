from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

root = Path(__file__).resolve().parents[2]
out = Path(__file__).parent
env = dict(os.environ, PUB_CACHE=str(root / '.tooling/cross-platform187/pub-cache'))
initial = json.loads((out / 'fixture-final-results.json').read_text(encoding='utf-8'))
results = []
for previous in initial:
    if previous['label'] not in ('ui1', 'ui2') or previous['exitCode'] != 79:
        continue
    label = previous['label'] + '-av-retry1'
    path = out / ('fixture-final-' + label + '.log')
    print('START', label, flush=True)
    with path.open('x', encoding='utf-8') as stream:
        proc = subprocess.run(previous['command'], cwd=root / 'cross-platform/app', env=env, stdout=stream, stderr=subprocess.STDOUT)
    raw = path.read_bytes()
    lines = raw.decode('utf-8', errors='replace').splitlines()
    row = {
        'label': label,
        'command': previous['command'],
        'exitCode': proc.returncode,
        'log': str(path.relative_to(root)),
        'logSha256': hashlib.sha256(raw).hexdigest(),
        'summary': [line for line in lines if re.search(r'All tests passed|Some tests failed|did not complete|code=-1073741819|EXCEPTION|TestFailure', line)],
        'testSources': previous['testSources'],
    }
    results.append(row)
    (out / 'fixture-final-av-retry-results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
    print('END', label, proc.returncode, row['summary'], flush=True)
