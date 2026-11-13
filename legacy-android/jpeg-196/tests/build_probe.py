"""Build only the standalone instrumentation APK. Does not run Gradle, ADB or alter the app."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUTPUT = ROOT / '.tooling/legacy-jpeg196/tests'
CERTIFICATE = '04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31'


def sha(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def run(command: list[str], log: Path) -> str:
    result = subprocess.run(command, cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True)
    log.write_bytes(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'Probe build operation failed ({result.returncode}); see {log}')
    return (result.stdout + result.stderr).decode('utf-8', errors='replace')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, default=Path('D:/dev/Android/Sdk'))
    parser.add_argument('--java', type=Path, default=Path('D:/dev/Java/jdk-17.0.19'))
    parser.add_argument('--build-tools', default='36.1.0')
    options = parser.parse_args()
    sdk, java = options.sdk.resolve(), options.java.resolve()
    android = sdk / 'platforms/android-35/android.jar'
    tools = sdk / 'build-tools' / options.build_tools
    source = HERE / 'src/cc/huevia/legacyjpeg196qa/LegacyJpeg196Probe.java'
    manifest = HERE / 'AndroidManifest.xml'
    inputs = [source, manifest, Path(__file__).resolve()]
    for path in [*inputs, android, java / 'bin/javac.exe', java / 'bin/java.exe',
                 java / 'bin/jar.exe', tools / 'aapt2.exe', tools / 'lib/d8.jar',
                 tools / 'zipalign.exe', tools / 'lib/apksigner.jar', ROOT / '.tooling/debug.keystore']:
        if not path.is_file():
            raise RuntimeError(f'Required standalone probe input missing: {path}')
    before = {p.relative_to(ROOT).as_posix(): sha(p) for p in inputs}
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='build-', dir=OUTPUT) as temporary:
        work = Path(temporary).resolve()
        if not work.is_relative_to(OUTPUT.resolve()) or work == OUTPUT.resolve():
            raise RuntimeError('Probe staging escaped its dedicated output directory')
        classes, dex = work / 'classes', work / 'dex'
        classes.mkdir(); dex.mkdir()
        run([str(java / 'bin/javac.exe'), '-J-Xmx256m', '-encoding', 'UTF-8', '-source', '11', '-target', '11',
             '-classpath', str(android), '-d', str(classes), str(source)], OUTPUT / 'probe-compile.log')
        jar = work / 'probe.jar'
        run([str(java / 'bin/jar.exe'), '--create', '--file', str(jar), '-C', str(classes), '.'], OUTPUT / 'probe-jar.log')
        run([str(java / 'bin/java.exe'), '-Xmx256m', '-cp', str(tools / 'lib/d8.jar'), 'com.android.tools.r8.D8',
             '--debug', '--min-api', '26', '--lib', str(android), '--output', str(dex), str(jar)], OUTPUT / 'probe-d8.log')
        unsigned = work / 'unsigned.apk'
        run([str(tools / 'aapt2.exe'), 'link', '-I', str(android), '--manifest', str(manifest),
             '--min-sdk-version', '26', '--target-sdk-version', '35', '-o', str(unsigned)], OUTPUT / 'probe-aapt.log')
        with zipfile.ZipFile(unsigned, 'a', compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(dex.glob('*.dex')):
                if path.name in archive.namelist():
                    raise RuntimeError('Duplicate DEX entry in probe APK')
                archive.write(path, path.name)
        aligned, signed = work / 'aligned.apk', work / 'signed.apk'
        run([str(tools / 'zipalign.exe'), '-f', '4', str(unsigned), str(aligned)], OUTPUT / 'probe-align.log')
        run([str(java / 'bin/java.exe'), '-Xmx128m', '-jar', str(tools / 'lib/apksigner.jar'), 'sign',
             '--ks', str(ROOT / '.tooling/debug.keystore'), '--ks-key-alias', 'androiddebugkey',
             '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', str(signed), str(aligned)], OUTPUT / 'probe-sign.log')
        signature = run([str(java / 'bin/java.exe'), '-Xmx128m', '-jar', str(tools / 'lib/apksigner.jar'),
                         'verify', '--verbose', '--print-certs', str(signed)], OUTPUT / 'probe-signature.log')
        values = re.findall(r'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', signature)
        if [value.lower() for value in values] != [CERTIFICATE]:
            raise RuntimeError('Instrumentation certificate differs from the original app')
        digest = sha(signed)
        final = OUTPUT / ('legacy-jpeg196-qa-' + digest[:12] + '.apk')
        if final.exists():
            if sha(final) != digest:
                raise RuntimeError('Existing probe artifact differs; retain previous output')
        else:
            shutil.copyfile(signed, final)
    if before != {p.relative_to(ROOT).as_posix(): sha(p) for p in inputs}:
        raise RuntimeError('Probe source changed during build; rebuild frozen inputs')
    receipt = {'schema': 1, 'apk': final.relative_to(ROOT).as_posix(), 'bytes': final.stat().st_size,
               'sha256': digest, 'certificateSha256': CERTIFICATE, 'targetPackage': 'cc.huevia',
               'instrumentation': 'cc.huevia.legacyjpeg196qa/.LegacyJpeg196Probe', 'inputSha256': before,
               'runPerformed': False, 'scope': 'Standalone instrumentation only; production loaded from installed target APK'}
    (OUTPUT / 'probe-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, zipfile.BadZipFile) as failure:
        print(str(failure))
        raise SystemExit(1)
