from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

root = Path(__file__).resolve().parents[2]
out = Path(__file__).parent
sdk = root / '.tooling/cross-platform187/flutter-sdk/bin'
env = dict(os.environ, PUB_CACHE=str(root / '.tooling/cross-platform187/pub-cache'))
app = root / 'cross-platform/app'
tests = ['test/camera_reconnect_226_test.dart', 'test/camera_live_panel_226_test.dart']
steps = [
    ('format', [str(sdk / 'dart.bat'), 'format', *tests]),
    ('analyze', [str(sdk / 'flutter.bat'), 'analyze', *tests]),
]
for label, name, pattern in [
    ('reconnect5', tests[0], None),
    ('records', tests[1], 'Live records use the root shell overlay and the last row is clickable where the tabs used to cover it'),
    ('ui1', tests[1], 'A central start keeps the same preview bounds and freezes the mutually exclusive format'),
    ('ui2', tests[1], 'A committed photograph keeps the preview frame and never carries a large action over its pixels'),
]:
    cmd = [str(sdk / 'flutter.bat'), 'test', name, '--reporter', 'expanded', '--verbose', '--concurrency=1']
    if pattern:
        cmd += ['--plain-name', pattern]
    steps.append((label, cmd))

results = []
for label, command in steps:
    log = out / ('fixture-final-' + label + '.log')
    print('START', label, flush=True)
    with log.open('x', encoding='utf-8') as stream:
        proc = subprocess.run(command, cwd=app, env=env, stdout=stream, stderr=subprocess.STDOUT)
    raw = log.read_bytes()
    text = raw.decode('utf-8', errors='replace')
    row = {
        'label': label,
        'command': command,
        'exitCode': proc.returncode,
        'log': str(log.relative_to(root)),
        'logSha256': hashlib.sha256(raw).hexdigest(),
        'summary': [line for line in text.splitlines() if re.search(r'All tests passed|Some tests failed|No issues found|\+\d+.*(?:\[E\]|\[.*\]|All tests)', line)][-12:],
        'testSources': {name: hashlib.sha256((app / name).read_bytes()).hexdigest() for name in tests},
    }
    results.append(row)
    (out / 'fixture-final-results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
    print('END', label, proc.returncode, row['summary'], flush=True)
    if label in ('format', 'analyze') and proc.returncode != 0:
        break
