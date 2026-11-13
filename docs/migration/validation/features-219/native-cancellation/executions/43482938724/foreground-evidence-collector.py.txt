"""Collect foreground evidence without confusing absent test logging with skips."""
from pathlib import Path
import hashlib
import json
import re


PINNED_SOURCES = {
    'cross-platform/app/integration_test/camera_foreground_fixture.dart':
        '66df9c8ce4e10be6d0eeed0c737eb0a656a6ee30e9d671179d6c29e3e0c2e543',
    'cross-platform/app/integration_test/native_pipeline_test.dart':
        '96200fa8c41674756a61eba9ad2eecce179a1c30097118e7717d01591f98075e',
}
CASE = 'Native codecs and LibRaw retain originals, dimensions and white highlights'
BOOL_KEYS = {'snapshotOnMainThread', 'applicationForeground', 'foregroundActive',
             'registeredPresenterAttached', 'presenterAvailable'}
COUNT_KEYS = {'activeSceneCount', 'eligibleWindowCount'}


def _one(directory, name):
    paths = list(Path(directory).rglob(name))
    assert len(paths) == 1, f'Expected one {name} evidence file'
    return paths[0]


def _json(directory, name):
    return json.loads(_one(directory, name).read_text(encoding='utf-8'))


def _marker(text):
    values = {}
    for part in text[1:-1].split(','):
        match = re.fullmatch(r'\s*([A-Za-z][A-Za-z0-9]*)\s*:\s*(true|false|[0-9]+)\s*', part)
        assert match, 'Malformed camera foreground fixture marker'
        key, raw = match.groups()
        assert key not in values, 'Duplicate foreground fixture field'
        assert key in BOOL_KEYS | COUNT_KEYS, 'Unexpected foreground fixture field'
        values[key] = raw == 'true' if raw in ('true', 'false') else int(raw)
    assert set(values) == BOOL_KEYS | COUNT_KEYS, 'Incomplete foreground fixture marker'
    assert all(type(values[key]) is bool for key in BOOL_KEYS), 'Non-boolean foreground field'
    assert all(values[key] is True for key in BOOL_KEYS - {'registeredPresenterAttached'}), 'Inactive foreground fixture marker'
    assert all(type(values[key]) is int and values[key] > 0 for key in COUNT_KEYS), 'Missing foreground scene/window'
    return values


def verify_foreground(directory, expected_source, read_git_blob):
    """Use an observed marker first; otherwise prove the audited mandatory path.

    The pinned whole Dart blobs have been manually audited: the single case
    unconditionally awaits foreground at line276, with no catch/skip around it;
    the fixture can return early only on non-iOS. The machine result producer
    requires allTestsPassed, no failure details and exactly that successful case.
    Any changed source needs another explicit audit, not a loose call-name match.
    """
    assert re.fullmatch(r'[0-9a-f]{40}', expected_source), 'Invalid expected source'
    artifact = _json(directory, 'artifact.json')
    assert artifact['workflow_run']['head_sha'] == expected_source, 'Artifact source mismatch'
    native = _json(directory, 'simulator-result.json')
    ready = _json(directory, 'simulator-initial-access.json')
    assert native.get('schema') == 1 and native.get('success') is True, 'Native machine test did not pass'
    assert native.get('sourceCommit') == expected_source == ready.get('sourceCommit'), 'Native/ready source mismatch'
    assert native.get('results') == {CASE: 'success'}, 'Native test missing, skipped or failed'
    assert ready.get('phase') == 'ready', 'Missing native ready handshake'
    assert re.fullmatch(r'[0-9a-fA-F-]{36}', native.get('runId', '')), 'Missing fresh native run ID'
    assert native['runId'] == ready.get('runId'), 'Native result is from another run'
    fixture = _one(directory, 'Huevia-QA-PhotoKit.png')
    assert native.get('fixtureSha256') == hashlib.sha256(fixture.read_bytes()).hexdigest(), 'Native fixture hash mismatch'
    selection = _json(directory, 'simulator-selection.json')
    assert selection.get('freshDevice') is True, 'Simulator was not fresh'
    assert re.fullmatch(r'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+', selection.get('runtime', '')), 'Not an actual iOS simulator runtime'
    build = _one(directory, 'simulator-build.log').read_text(encoding='utf-8', errors='replace')
    assert re.search(r'(?:-sdk\s+iphonesimulator\b|SDKROOT\s*=\s*iphonesimulator[0-9.]+|PLATFORM_NAME\\?=\s*iphonesimulator\b)', build), 'Missing iOS simulator SDK proof'
    source_proof = []
    for path, expected in PINNED_SOURCES.items():
        actual = hashlib.sha256(read_git_blob(path)).hexdigest()
        assert actual == expected, f'Unreviewed foreground source blob: {path}'
        source_proof.append({'path': path, 'gitBlobSha256': actual})
    markers = []
    for name in ['simulator-pipeline.log', 'simulator-pipeline-stderr.log']:
        text = _one(directory, name).read_text(encoding='utf-8', errors='replace')
        markers.extend(re.findall(r'iOS camera foreground presentation:\s*(\{[^\r\n]*\})', text))
    if markers:
        snapshots = [_marker(value) for value in markers]
        return {'passed': True, 'snapshot': snapshots[-1], 'evidence': 'log-marker', 'sourceProof': source_proof}
    # Flutter can intercept debugPrint while retaining the full test result.
    # Do not manufacture counts or a snapshot from the assertion outcome.
    return {'passed': True, 'snapshot': None, 'evidence': 'machine-test', 'sourceProof': source_proof}
