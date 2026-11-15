from pathlib import Path
import hashlib
import json
import re

INPUTS = (
    'cross-platform/native/ios/Classes/HueviaPublicInternetQueues.h',
    'cross-platform/native/ios/Classes/HueviaPublicInternetQueues.m',
    'cross-platform/native/ios/Classes/HueviaCorePlugin.m',
    'cross-platform/native/tests/public_internet_queue_apple.m',
    'cross-platform/tool/public_internet_queue_source_check.py',
    'cross-platform/tool/public_internet_apple.sh',
)
LOGS = {
    'compiler': 'compiler.log',
    'build': 'build.log',
    'stdout': 'stdout.log',
    'architecture': 'source-check.log',
}


def verify_public_internet(directory, source, read_git_blob):
    assert re.fullmatch(r'[0-9a-f]{40}', source), 'Invalid frozen source'
    receipts = [p for p in Path(directory).rglob('result.json')
                if p.parent.name == 'public-internet']
    assert len(receipts) == 1, 'Exactly one Apple public-internet result is required'
    path = receipts[0]
    assert path.stat().st_size <= 128 * 1024
    result = json.loads(path.read_text(encoding='utf-8'))
    assert result.get('schemaVersion') == 2, 'Explicit public-I/O exit schema required'
    assert result.get('sourceCommit') == source, 'Public-I/O job source mismatch'
    assert result.get('passed') is True and result.get('phase') == 'complete'
    for field in ('exitCode', 'compileExitCode', 'executionExitCode'):
        assert type(result.get(field)) is int and result[field] == 0, field
    assert result.get('platform') == 'macOS Foundation production I/O queues'
    assert result.get('contract') == {
        'accountConcurrency': 2,
        'publicConcurrency': 3,
        'serialCameraHeartbeatCommands': 16,
        'physicalCameraExercised': False,
    }
    fingerprints = result.get('sourceSha256')
    assert isinstance(fingerprints, dict) and set(fingerprints) == set(INPUTS)
    proof = []
    for name in INPUTS:
        expected = fingerprints[name]
        assert isinstance(expected, str) and re.fullmatch(r'[0-9a-f]{64}', expected)
        actual = hashlib.sha256(read_git_blob(name)).hexdigest()
        assert actual == expected, 'Public-I/O compiled input differs from frozen Git: ' + name
        proof.append({'path': name, 'gitBlobSha256': actual})
    assert result.get('logs') == LOGS
    logs = {}
    text = {}
    for kind, name in LOGS.items():
        log = path.parent / name
        assert log.is_file() and log.stat().st_size <= 4 * 1024 * 1024, name
        data = log.read_bytes()
        text[kind] = data.decode('utf-8', errors='replace')
        logs[name] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    assert re.search(r'clang version \d+', text['compiler']), 'Missing real compiler identity'
    assert 'PASS iOS public I/O architecture:' in text['architecture']
    assert 'PASS Apple public I/O queue isolation:' in text['stdout']
    assert 'no physical camera exercised' in text['stdout']
    assert not re.search(r'^FAIL\b', text['stdout'], re.MULTILINE)
    return {
        'passed': True,
        'sourceCommit': source,
        'receipt': str(path),
        'receiptSha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'schemaVersion': 2,
        'compileExitCode': 0,
        'executionExitCode': 0,
        'sourceProof': proof,
        'logs': logs,
        'contract': result['contract'],
        'physicalCameraExercised': False,
    }
