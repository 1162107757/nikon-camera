"""Synthetic provenance verifier tests; this does not execute an Apple build."""
import copy
import json
from pathlib import Path
from apple_full_source_evidence228 import verify_full_mac_run

source = 'a' * 40
run = {'id': 1, 'head_sha': source, 'event': 'workflow_dispatch',
       'path': '.github/workflows/cross-platform-mobile.yml',
       'status': 'completed', 'conclusion': 'success'}
jobs = {'total_count': 1, 'jobs': [{
    'id': 2, 'run_id': 1, 'head_sha': source, 'name': 'apple-app',
    'status': 'completed', 'conclusion': 'success', 'labels': ['macos-26'],
    'steps': [
        {'name': 'Verify core parity and prepare native runtimes',
         'status': 'completed', 'conclusion': 'success'},
        {'name': 'Build and test the unsigned device app',
         'status': 'completed', 'conclusion': 'success'},
        {'name': 'Diagnose the native simulator pipeline without accepting an IPA',
         'status': 'completed', 'conclusion': 'skipped'},
    ],
}]}
metadata = {'build': 228, 'sourceCommit': source, 'sourceFrozen': True, 'published': False}
artifact = {'id': 3, 'workflow_run': {'id': 1, 'head_sha': source}}
assert verify_full_mac_run(run, jobs, metadata, artifact)['passed'] is True
checks = ['valid synthetic full-run provenance accepted']


def reject(name, mutate):
    values = copy.deepcopy([run, jobs, metadata, artifact])
    mutate(*values)
    try:
        verify_full_mac_run(*values)
    except AssertionError:
        checks.append(name)
    else:
        raise AssertionError('Accepted invalid provenance: ' + name)


reject('unfrozen source rejected', lambda r, j, m, a: m.update(sourceFrozen=False))
reject('other source rejected', lambda r, j, m, a: r.update(head_sha='b' * 40))
reject('wrong workflow rejected', lambda r, j, m, a: r.update(path='other.yml'))
reject('wrong event rejected', lambda r, j, m, a: r.update(event='push'))
reject('wrong runner rejected', lambda r, j, m, a: j['jobs'][0].update(labels=['macos-26-intel']))
reject('skipped prepare rejected', lambda r, j, m, a: j['jobs'][0]['steps'][0].update(conclusion='skipped'))
reject('diagnostic-only job rejected', lambda r, j, m, a: j['jobs'][0]['steps'][1].update(conclusion='skipped'))
reject('different job source rejected', lambda r, j, m, a: j['jobs'][0].update(head_sha='b' * 40))
reject('different artifact source rejected', lambda r, j, m, a: a['workflow_run'].update(head_sha='b' * 40))
reject('publishing state rejected', lambda r, j, m, a: m.update(published=True))
result = {'syntheticVerifierOnly': True, 'actualAppleBuildExecuted': False,
          'passed': True, 'checks': len(checks), 'cases': checks}
Path(__file__).with_name('full-source-verifier-selftest.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
