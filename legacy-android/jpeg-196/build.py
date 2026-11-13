"""Build legacy JPEG 196 through generated sources; preserve the original app and frozen 195/213 packages."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CERTIFICATE = '04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31'
PACKAGE = 'cc.huevia'
VERSION_CODE = 196
VERSION_NAME = '0.30.36-beta-jpeg-fix'
ABIS = {'arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'}
NATIVE_LIBRARIES = {'libraw.so', 'libhuevia_raw.so', 'libc++_shared.so', 'libtensorflowlite_jni.so'}


def sha256(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source_snapshot() -> dict[str, str]:
    java = ROOT / 'app/src/main/java'
    files = sorted(path for path in java.rglob('*') if path.is_file())
    files += [ROOT / 'app/src/main/AndroidManifest.xml', ROOT / 'app/build.gradle',
              ROOT / 'cross-platform/legacy-android/overlay.gradle']
    if not files:
        raise RuntimeError('Original Java source tree is empty')
    return {path.relative_to(ROOT).as_posix(): sha256(path) for path in files}


def required(path: Path) -> Path:
    if not path.is_file():
        raise RuntimeError(f'Required build input missing: {path}')
    return path


def run(command: list[str], log: Path, env: dict[str, str]) -> str:
    with log.open('wb') as output:
        result = subprocess.run(command, cwd=ROOT, env=env, stdin=subprocess.DEVNULL,
                                stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f'Build operation failed ({result.returncode}); see {log.relative_to(ROOT)}')
    return log.read_text(encoding='utf-8-sig', errors='replace')


def verify_badging(text: str) -> None:
    match = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", text, re.MULTILINE)
    if not match or match.groups() != (PACKAGE, str(VERSION_CODE), VERSION_NAME):
        raise RuntimeError('APK package or version is not the legacy JPEG 196 repair')
    for literal in ["minSdkVersion:'26'", "targetSdkVersion:'35'", "application-label:'Huevia'"]:
        if literal not in text:
            raise RuntimeError(f'APK is missing required original behavior: {literal}')
    launchers = re.findall(r"^launchable-activity: name='([^']+)'", text, re.MULTILINE)
    if launchers != ['cc.huevia.MainActivity']:
        raise RuntimeError('APK must expose exactly the normal Huevia MainActivity launcher')


def verify_manifest_tree(text: str) -> None:
    """Check actual compiled manifest structure, including exported=false on the helper."""
    roots: list[dict] = []
    stack: list[tuple[int, dict]] = []
    for line in text.splitlines():
        element = re.match(r'^(\s*)E:\s+([A-Za-z0-9_:-]+)(?:\s|$)', line)
        if element:
            depth = len(element[1])
            while stack and stack[-1][0] >= depth:
                stack.pop()
            node = {'tag': element[2], 'attributes': {}, 'children': []}
            (stack[-1][1]['children'] if stack else roots).append(node)
            stack.append((depth, node))
            continue
        attribute = re.match(r'^\s*A:\s+([^\s(=]+)(?:\([^)]*\))?=(.*)$', line)
        if attribute and stack:
            stack[-1][1]['attributes'][attribute[1].rsplit(':', 1)[-1]] = attribute[2].strip()

    def named(node: dict, key: str) -> str:
        match = re.match(r'^"([^"]*)"', node['attributes'].get(key, ''))
        return match[1] if match else ''

    def boolean(node: dict, key: str) -> bool | None:
        raw = node['attributes'].get(key, '').strip()
        if raw == 'true' or re.fullmatch(r'(?:\(type 0x12\)\s*)?0x(?:ffffffff|1)', raw, re.IGNORECASE):
            return True
        if raw == 'false' or re.fullmatch(r'(?:\(type 0x12\)\s*)?0x0+', raw, re.IGNORECASE):
            return False
        return None

    def qualified(name: str) -> str:
        return PACKAGE + name if name.startswith('.') else PACKAGE + '.' + name if '.' not in name else name

    def filters(node: dict) -> list[tuple[set[str], set[str]]]:
        return [({named(child, 'name') for child in item['children'] if child['tag'] == 'action'},
                 {named(child, 'name') for child in item['children'] if child['tag'] == 'category'})
                for item in node['children'] if item['tag'] == 'intent-filter']

    nodes: list[dict] = []
    pending = list(roots)
    while pending:
        node = pending.pop(0)
        nodes.append(node)
        pending.extend(node['children'])
    manifests = [node for node in roots if node['tag'] == 'manifest']
    if len(manifests) != 1 or named(manifests[0], 'package') != PACKAGE:
        raise RuntimeError('Compiled Android manifest package is invalid')
    components = [node for node in nodes if node['tag'] in ('activity', 'activity-alias')]
    main = [node for node in components if qualified(named(node, 'name')) == 'cc.huevia.MainActivity']
    exported_helper = [node for node in components
                       if qualified(named(node, 'name')) == 'cc.huevia.legacyexport.LegacyExportActivity']
    if len(main) != 1 or boolean(main[0], 'exported') is not True or boolean(main[0], 'enabled') is False:
        raise RuntimeError('Normal Huevia launcher activity must remain enabled and exported')
    if len(exported_helper) != 1 or boolean(exported_helper[0], 'exported') is not False:
        raise RuntimeError('Legacy export helper must remain present and non-exported')
    for actions, categories in filters(exported_helper[0]):
        if 'android.intent.action.MAIN' in actions or 'android.intent.category.LAUNCHER' in categories:
            raise RuntimeError('Legacy export helper still exposes a desktop intent filter')
    launchers = [qualified(named(node, 'name')) for node in components for actions, categories in filters(node)
                 if 'android.intent.action.MAIN' in actions and 'android.intent.category.LAUNCHER' in categories]
    if launchers != ['cc.huevia.MainActivity']:
        raise RuntimeError('Compiled manifest has an extra or missing launcher')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, default=Path('D:/dev/Android/Sdk'))
    parser.add_argument('--java', type=Path, default=Path('D:/dev/Java/jdk-17.0.19'))
    parser.add_argument('--gradle', type=Path,
                        default=ROOT / '.tooling/next213/gradle-pinned/gradle-8.11.1/bin/gradle.bat')
    parser.add_argument('--build-tools', default='36.1.0')
    parser.add_argument('--online', action='store_true', help='Allow Gradle dependency resolution; default is offline')
    options = parser.parse_args()
    sdk, java, gradle = options.sdk.resolve(), options.java.resolve(), options.gradle.resolve()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', options.build_tools):
        raise RuntimeError('Build-tools version must have three numeric components')
    tools = sdk / 'build-tools' / options.build_tools
    java_exe = required(java / 'bin/java.exe')
    keytool = required(java / 'bin/keytool.exe')
    required(java / 'bin/javac.exe')
    required(sdk / 'platforms/android-35/android.jar')
    required(gradle)
    align = required(tools / 'zipalign.exe')
    signer = required(tools / 'lib/apksigner.jar')
    aapt = required(tools / 'aapt2.exe')
    key = required(ROOT / '.tooling/debug.keystore')
    overlay194 = required(ROOT / 'cross-platform/legacy-android/overlay.gradle')
    overlay196 = required(HERE / 'overlay.gradle')
    patch = required(HERE / 'patch_sources.py')
    env = dict(os.environ, JAVA_HOME=str(java), ANDROID_HOME=str(sdk), ANDROID_SDK_ROOT=str(sdk))
    env['PATH'] = str(java / 'bin') + os.pathsep + env.get('PATH', '')

    # Compare the actual public certificate before touching a build output.
    certificate = subprocess.run([str(keytool), '-exportcert', '-keystore', str(key),
                                  '-alias', 'androiddebugkey', '-storepass', 'android'],
                                 cwd=ROOT, env=env, stdin=subprocess.DEVNULL, capture_output=True)
    if certificate.returncode or hashlib.sha256(certificate.stdout).hexdigest() != CERTIFICATE:
        raise RuntimeError('Original Android signing certificate does not match; do not uninstall the old app')

    destination = ROOT / 'dist/legacy-jpeg196'
    destination.mkdir(parents=True, exist_ok=True)
    if destination.resolve() != destination.absolute() or not destination.resolve().is_relative_to(ROOT):
        raise RuntimeError('Legacy JPEG delivery directory escaped the workspace')
    evidence = destination / 'build-evidence'
    evidence.mkdir(exist_ok=True)
    before = source_snapshot()
    source_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    command = [str(gradle), ':app:assembleRelease', '--no-daemon', '--max-workers=1',
               '-Dorg.gradle.jvmargs=-Xmx768m -Dfile.encoding=UTF-8',
               '-PlegacyJpegPython=' + sys.executable]
    if not options.online:
        command.append('--offline')
    proxy_init = ROOT / '.tooling/cross-platform187/maven-proxy.init.gradle'
    if proxy_init.is_file():
        command += ['--init-script', str(proxy_init)]
    command += ['--init-script', str(overlay194), '--init-script', str(overlay196)]
    try:
        run(command, evidence / 'gradle.log', env)
    finally:
        if source_snapshot() != before:
            raise RuntimeError('Original Java, manifest, build file or export overlay changed during the build')

    unsigned = required(ROOT / 'app/build/outputs/apk/release/app-release-unsigned.apk')
    with zipfile.ZipFile(unsigned) as archive:
        if archive.testzip() is not None or len(archive.namelist()) != len(set(archive.namelist())):
            raise RuntimeError('Built APK ZIP integrity or duplicate-entry check failed')
        abis = {name.split('/')[1] for name in archive.namelist()
                if name.startswith('lib/') and name.endswith('.so')}
        if abis != ABIS:
            raise RuntimeError(f'Original four native ABIs were not preserved: {sorted(abis)}')
        for abi in ABIS:
            if not {f'lib/{abi}/{library}' for library in NATIVE_LIBRARIES}.issubset(archive.namelist()):
                raise RuntimeError(f'Original native libraries are incomplete for {abi}')
    verify_badging(run([str(aapt), 'dump', 'badging', str(unsigned)], evidence / 'badging.log', env))
    verify_manifest_tree(run([str(aapt), 'dump', 'xmltree', '--file', 'AndroidManifest.xml', str(unsigned)],
                             evidence / 'manifest-tree.log', env))

    final = destination / f'huevia-{VERSION_NAME}-{VERSION_CODE}.apk'
    # Staging is unique and confined to this delivery directory. Never replace an
    # existing different delivery package or any frozen migration213 artifact.
    with tempfile.TemporaryDirectory(prefix='package-', dir=destination) as temporary:
        staging = Path(temporary)
        if not staging.resolve().is_relative_to(destination.resolve()) or not staging.name.startswith('package-'):
            raise RuntimeError('Temporary package directory escaped the delivery directory')
        aligned, signed = staging / 'aligned.apk', staging / 'signed.apk'
        run([str(align), '-P', '16', '-f', '4', str(unsigned), str(aligned)], evidence / 'zipalign-build.log', env)
        run([str(java_exe), '-Xmx128m', '-jar', str(signer), 'sign', '--ks', str(key),
             '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android', '--key-pass', 'pass:android',
             '--v1-signing-enabled', 'false', '--v2-signing-enabled', 'true', '--v3-signing-enabled', 'true',
             '--out', str(signed), str(aligned)], evidence / 'sign.log', env)
        signature = run([str(java_exe), '-Xmx128m', '-jar', str(signer), 'verify', '--verbose', '--print-certs', str(signed)],
                        evidence / 'signature.log', env)
        fingerprints = re.findall(r'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})', signature)
        if [value.lower() for value in fingerprints] != [CERTIFICATE]:
            raise RuntimeError('Final APK certificate does not match the old installation')
        for scheme in ('v2', 'v3'):
            if not re.search(r'Verified using ' + scheme + r' scheme[^\n]*:\s*true', signature):
                raise RuntimeError('Final APK signature scheme missing: ' + scheme)
        run([str(align), '-c', '-P', '16', '4', str(signed)], evidence / 'zipalign-final.log', env)
        verify_badging(run([str(aapt), 'dump', 'badging', str(signed)], evidence / 'badging-final.log', env))
        verify_manifest_tree(run([str(aapt), 'dump', 'xmltree', '--file', 'AndroidManifest.xml', str(signed)],
                                 evidence / 'manifest-tree-final.log', env))
        digest = sha256(signed)
        if final.exists():
            if sha256(final) != digest:
                raise RuntimeError('A different 196 package already exists; retain it as a candidate before rebuilding')
        else:
            shutil.copyfile(signed, final)

    receipt = {'package': PACKAGE, 'versionCode': VERSION_CODE, 'versionName': VERSION_NAME,
               'apk': final.relative_to(ROOT).as_posix(), 'bytes': final.stat().st_size,
               'sha256': sha256(final), 'certificateSha256': CERTIFICATE, 'abis': sorted(ABIS),
               'sourceCommit': source_commit, 'originalSourceUnchanged': True,
               'patchSha256': sha256(patch), 'overlaySha256': sha256(overlay196), 'manualInstallOnly': True,
               'launchers': ['cc.huevia.MainActivity'], 'legacyExportExported': False}
    (evidence / 'original-source-hashes.json').write_text(json.dumps(before, indent=2) + '\n', encoding='utf-8')
    (destination / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    (destination / 'SHA256SUMS.txt').write_text(receipt['sha256'] + '  ' + final.name + '\n', encoding='utf-8')
    print(json.dumps(receipt, separators=(',', ':')))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError, zipfile.BadZipFile) as failure:
        print(str(failure), file=sys.stderr)
        raise SystemExit(1)
