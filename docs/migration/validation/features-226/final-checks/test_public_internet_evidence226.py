from pathlib import Path
import copy
import hashlib
import importlib.util
import json

base = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('public_gate', base / 'public_internet_evidence226.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
fixture = base / 'public-verifier-selftest' / 'public-internet'
fixture.mkdir(parents=True, exist_ok=True)
source = 'a' * 40
blobs = {name: ('synthetic verifier input: ' + name).encode() for name in gate.INPUTS}
valid = {'schemaVersion': 2, 'sourceCommit': source, 'passed': True, 'phase': 'complete',
         'exitCode': 0, 'compileExitCode': 0, 'executionExitCode': 0,
         'platform': 'macOS Foundation production I/O queues',
         'contract': {'accountConcurrency': 2, 'publicConcurrency': 3,
                      'serialCameraHeartbeatCommands': 16, 'physicalCameraExercised': False},
         'sourceSha256': {name: hashlib.sha256(data).hexdigest() for name, data in blobs.items()},
         'logs': gate.LOGS}
contents = {'compiler.log': 'Apple clang version 17.0.0 (synthetic verifier input only)\n',
            'build.log': '',
            'stdout.log': 'PASS Apple public I/O queue isolation: no physical camera exercised\n',
            'source-check.log': 'PASS iOS public I/O architecture: synthetic verifier input only\n'}
for name, text in contents.items():
    (fixture / name).write_text(text, encoding='utf-8')
def check(receipt, accepted):
    (fixture / 'result.json').write_text(json.dumps(receipt), encoding='utf-8')
    try:
        gate.verify_public_internet(fixture.parent, source, blobs.__getitem__)
    except AssertionError:
        assert not accepted
    else:
        assert accepted
check(valid, True)
for field in ['compileExitCode', 'executionExitCode']:
    bad = copy.deepcopy(valid); bad[field] = 1; check(bad, False)
bad = copy.deepcopy(valid); del bad['compileExitCode']; check(bad, False)
bad = copy.deepcopy(valid); bad['sourceCommit'] = 'b' * 40; check(bad, False)
bad = copy.deepcopy(valid); bad['sourceSha256'][gate.INPUTS[0]] = '0' * 64; check(bad, False)
bad = copy.deepcopy(valid); bad['schemaVersion'] = 1; check(bad, False)
bad = copy.deepcopy(valid); del bad['sourceSha256'][gate.INPUTS[0]]; check(bad, False)
(fixture / 'stdout.log').write_text('no pass marker\n', encoding='utf-8'); check(valid, False)
(fixture / 'stdout.log').write_text(contents['stdout.log'], encoding='utf-8')
(fixture / 'result.json').write_text(json.dumps(valid), encoding='utf-8')
(fixture.parent / 'selftest-result.json').write_text(json.dumps({
    'syntheticVerifierOnly': True, 'actualAppleFixtureExecuted': False,
    'checksPassed': 9, 'negativeCasesRejected': 8,
}) + '\n', encoding='utf-8')
print('PASS verifier self-test: 9 synthetic cases; not an Apple runtime execution')
