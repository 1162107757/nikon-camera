"""Run isolated JVM regression checks against the generated legacy JPEG repair."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
GENERATED = ROOT / 'app/build/generated/legacy-jpeg195/java'
OUTPUT = ROOT / '.tooling/legacy-jpeg195/tests'


def required(path: Path) -> Path:
    if not path.is_file():
        try:
            display = path.relative_to(ROOT)
        except ValueError:
            display = path
        raise RuntimeError(f'Required regression input is missing: {display}')
    return path


def sha256(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def invoke(command: list[str], log: Path) -> str:
    result = subprocess.run(command, cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True)
    log.write_bytes(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'JVM regression operation failed ({result.returncode}); see {log.relative_to(ROOT)}')
    return (result.stdout + result.stderr).decode('utf-8', errors='replace')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--java', type=Path, default=Path(os.environ.get('JAVA_HOME', 'D:/dev/Java/jdk-17.0.19')))
    options = parser.parse_args()
    java = options.java.resolve()
    suffix = '.exe' if os.name == 'nt' else ''
    javac = required(java / 'bin' / ('javac' + suffix))
    runtime = required(java / 'bin' / ('java' + suffix))
    helper_relative = Path('cc/huevia/album/LegacyJpegInventory.java')
    helper = HERE / 'src' / helper_relative
    if not helper.is_file():
        helper = GENERATED / helper_relative
    helper = required(helper)
    patched_format = required(GENERATED / 'cc/huevia/album/PhotoFormat.java')
    ptp = ROOT / 'app/src/main/java/cc/huevia/ptp'
    names = ['PtpObjectInfo', 'PtpDatasetReader', 'PtpProtocolException', 'PtpConstants',
             'PtpContainer', 'PtpStorageIds', 'PtpObjectHandles', 'PtpResponseException']
    originals = [required(ptp / (name + '.java')) for name in names]
    tests = sorted((HERE / 'tests').rglob('*.java'))
    if not tests:
        raise RuntimeError('No legacy JPEG regression sources found')
    sources = [helper, patched_format, *originals, *tests]
    # Record the precise generated/portable inputs and verify they remain unchanged.
    before = {path.relative_to(ROOT).as_posix(): sha256(path) for path in sources}
    OUTPUT.mkdir(parents=True, exist_ok=True)
    classes = OUTPUT / 'classes'
    classes.mkdir(exist_ok=True)
    invoke([str(javac), '-J-Xmx256m', '--release', '11', '-encoding', 'UTF-8',
            '-d', str(classes), *map(str, sources)], OUTPUT / 'compile.log')
    text = invoke([str(runtime), '-Xmx128m', '-Dfile.encoding=UTF-8', '-cp', str(classes),
                   'cc.huevia.album.LegacyJpegInventoryTest'], OUTPUT / 'run.log')
    match = re.search(r'^PASS LEGACY_JPEG_195_CHECKS=([0-9]+) CASES=([0-9]+)\r?$', text, re.MULTILINE)
    if not match:
        raise RuntimeError('The JVM did not report a complete legacy JPEG regression pass')
    after = {path.relative_to(ROOT).as_posix(): sha256(path) for path in sources}
    if before != after:
        raise RuntimeError('A test input changed during JVM validation; freeze and rerun')
    receipt = {'schema': 1, 'passed': True, 'checks': int(match[1]), 'cases': int(match[2]),
               'compiler': 'JDK17 --release11 UTF-8', 'heapMiB': 128,
               'sourceScope': 'Generated PhotoFormat and legacy inventory helper; original PTP dependency bytes unchanged',
               'sourceSha256': before, 'compileLog': (OUTPUT / 'compile.log').relative_to(ROOT).as_posix(),
               'runLog': (OUTPUT / 'run.log').relative_to(ROOT).as_posix(),
               'runLogSha256': sha256(OUTPUT / 'run.log'), 'originalInputsUnchanged': True}
    (OUTPUT / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'passed': True, 'checks': receipt['checks'], 'cases': receipt['cases'],
                      'receipt': (OUTPUT / 'receipt.json').relative_to(ROOT).as_posix()}, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as failure:
        print(str(failure), file=sys.stderr)
        raise SystemExit(1)
