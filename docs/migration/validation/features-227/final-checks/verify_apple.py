from pathlib import Path
import sys, json, zipfile, io, plistlib, struct, shutil, hashlib, re, subprocess

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / '.tooling/features212'))
sys.path.insert(0, str(root / 'cross-platform/tool'))
from github import api
from verify_ipa import verify

run_id = int(sys.argv[1])
if (root / '.tooling/next227' / ('hold-delivery-' + str(run_id))).exists():
    sys.argv.append('--diagnostic')
    print('Source snapshot held for final UI cancellation fix; do not copy a deliverable IPA')
run = api(f'/actions/runs/{run_id}')
if run['status'] != 'completed':
    print(json.dumps({k: run[k] for k in ['id', 'head_sha', 'status', 'conclusion']}))
    raise SystemExit(2)
selected = next(a for a in api(f'/actions/runs/{run_id}/artifacts')['artifacts']
                if a['name'] == 'huevia-cross-platform-ios-development' and not a['expired'])
directory = root / '.tooling/next227' / f'apple-{run_id}-artifacts'
directory.mkdir(exist_ok=True)
if not (directory / 'artifact.json').exists():
    data = api('/actions/artifacts/' + str(selected['id']) + '/zip', binary=True)
    digest = hashlib.sha256(data).hexdigest()
    assert selected.get('digest') == 'sha256:' + digest
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        assert sum(e.file_size for e in archive.infolist()) <= 1024 ** 3
        for entry in archive.infolist():
            assert (directory / entry.filename).resolve().is_relative_to(directory.resolve())
            assert (entry.external_attr >> 16) & 0o170000 != 0o120000
        archive.extractall(directory)
    (directory / 'artifact.json').write_text(json.dumps({k: selected.get(k) for k in
        ['id', 'name', 'size_in_bytes', 'digest', 'workflow_run']}, indent=2) + '\n')

if run['conclusion'] != 'success' or '--diagnostic' in sys.argv:
    for filename in ['flutter-tests.log', 'device-build.log', 'simulator-build.log',
                     'simulator-tests.log', 'simulator-pipeline.log', 'simulator-pipeline-stderr.log']:
        for path in directory.rglob(filename):
            lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
            findings = [f'{i + 1}: {s}' for i, s in enumerate(lines)
                        if re.search(r'error:|Error \(|failed|Exception|Assertion|\[E\]|^FAIL', s, re.I)]
            print(filename, '\n' + '\n'.join(findings[-25:] or lines[-15:]))
    for filename in ['simulator-native.log', 'simulator-pipeline.log', 'simulator-pipeline-stderr.log']:
        for path in directory.rglob(filename):
            lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
            details = [s for s in lines if 'HueviaRetouch' in s or 'native stages:' in s]
            if details:
                print(filename, '\n' + '\n'.join(details[-40:]))
    if '--diagnostic' in sys.argv:
        print('Diagnostic run only; no accepted IPA is copied to delivery')
        raise SystemExit(0 if run['conclusion'] == 'success' else 1)
    raise SystemExit(1)

source = run['head_sha']
from apple_full_source_evidence227 import verify_full_mac_run
source_metadata = json.loads((root / '.tooling/next227/source.json').read_text(encoding='utf-8'))
jobs_response = api(f'/actions/runs/{run_id}/jobs?filter=latest&per_page=100')
full_source_proof = verify_full_mac_run(run, jobs_response, source_metadata, selected)
cached_artifact = json.loads((directory / 'artifact.json').read_text(encoding='utf-8'))
assert cached_artifact['id'] == selected['id'] and cached_artifact['digest'] == selected['digest'], 'Cached artifact is from another run attempt'
from public_internet_evidence227 import verify_public_internet
public_internet = verify_public_internet(
    directory, source,
    lambda path: subprocess.check_output(['git', 'show', source + ':' + path], cwd=root),
)
ipa = next(directory.rglob('*.ipa'))
build_path = next(directory.rglob('ipa-verification.json'))
report = json.loads(build_path.read_text(encoding='utf-8'))
verified = verify(ipa, report, source)
assert verified['build'] == '227' and verified['version'] == '0.31.0'
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None
    info = plistlib.loads(archive.read('Payload/Huevia.app/Info.plist'))
    assert info.get('CFBundleDisplayName') == 'Huevia', 'The packaged iOS display name must be Huevia'
    assert info.get('NSCameraUsageDescription', '').strip()
    assert info.get('HueviaQqUniversalLink') == ''
    assert info.get('HueviaIosReleaseManifest', '').startswith('https://nikon-')
    binary = archive.read('Payload/Huevia.app/' + info['CFBundleExecutable'])
    at, signature, libraries = 32, False, []
    for _ in range(struct.unpack_from('<I', binary, 16)[0]):
        command, length = struct.unpack_from('<II', binary, at)
        if command == 0x1d:
            signature |= struct.unpack_from('<I', binary, at + 12)[0] > 0
        if command in [0xc, 0x80000018]:
            offset = struct.unpack_from('<I', binary, at + 8)[0]
            libraries.append(binary[at + offset:at + length].split(b'\0')[0].decode())
        at += length
    assert not signature
    assert not any(n.endswith('embedded.mobileprovision') for n in archive.namelist())
    assert 'Payload/Huevia.app/_CodeSignature/CodeResources' not in archive.namelist()
    assert any('/ImageCaptureCore.framework/ImageCaptureCore' in name for name in libraries)
    assert any('/WebKit.framework/WebKit' in name for name in libraries)
    for name in ['HueviaWiredCameras', 'HueviaWiredClient', 'HueviaPortraitInference',
                 'HueviaQqAuthorization', 'TencentOAuth']:
        assert name.encode() in binary, name
    models = {}
    expected = {
        'face_landmarks_detector.tflite': 'c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5',
        'face_skin_multiclass.shuffle4.zlib': '9920fafc503c9090b3840c6fb433efc7eeb117bb00176b04034bd589c0e19bb0',
    }
    for name in archive.namelist():
        if 'HueviaNativeAssets.bundle/' in name and Path(name).name in expected:
            models[name] = hashlib.sha256(archive.read(name)).hexdigest()
            assert models[name] == expected[Path(name).name], name
    assert {Path(name).name for name in models} == set(expected), models
    verified['portraitAssets'] = models
    photo_reference = json.loads((root / 'docs/migration/validation/features-227/preset-preview-assets.json').read_text(encoding='utf-8'))['repositoryImages']
    photo_assets = {}
    for name in archive.namelist():
        if '/preset-showcase/' in name and Path(name).name in photo_reference:
            digest = hashlib.sha256(archive.read(name)).hexdigest()
            assert digest == photo_reference[Path(name).name], name
            photo_assets[Path(name).name] = digest
    assert len(photo_reference) == 10 and photo_assets == photo_reference
    verified['presetPreviewAssets'] = dict(imageCount=10, allTenPreservedByteForByte=True, imageSha256=photo_assets)
verified.update(displayName=info['CFBundleDisplayName'], displayNameVerified=True,
                unsignedApplicationExecutable=True, embeddedProvisioningProfile=False,
                imageCaptureCoreLinked=True, wiredNativeClassesLinked=True,
                webKitLinked=True, cameraUsageDescriptionPresent=True, qqUniversalLinkConfigured=False)
out = root / 'docs/migration/validation/features-227/apple'
out.mkdir(parents=True, exist_ok=True)
public_directory = Path(public_internet['receipt']).parent
public_out = out / 'public-internet'
public_out.mkdir(exist_ok=True)
for path in public_directory.iterdir():
    if path.name in ['result.json', 'compiler.log', 'build.log', 'stdout.log', 'source-check.log']:
        shutil.copyfile(path, public_out / path.name)
(public_out / 'independent-verification.json').write_text(json.dumps(public_internet, indent=2) + '\n')
(out / 'independent-verification.json').write_text(json.dumps(verified, indent=2) + '\n')
shutil.copyfile(build_path, out / 'ipa-verification.json')
shutil.copyfile(directory / 'artifact.json', out / 'artifact-api.json')
(out / 'full-run-api.json').write_text(json.dumps(run, indent=2) + '\n')
(out / 'full-jobs-api.json').write_text(json.dumps(jobs_response, indent=2) + '\n')
(out / 'full-source-verification.json').write_text(json.dumps(full_source_proof, indent=2) + '\n')
for name in ['flutter-tests.log', 'analyze.log', 'device-build.log', 'simulator-tests.log', 'simulator-result.json', 'simulator-initial-access.json',
             'avatar-test.log', 'wifi-test.log', 'portrait-models.log', 'simulator-pipeline.log',
             'simulator-pipeline-stderr.log', 'simulator-selection.json', 'native-runtime.json',
             'flutter-version.json', 'native-task-tests.log']:
    matches = list(directory.rglob(name))
    if len(matches) == 1:
        shutil.copyfile(matches[0], out / name)
native = json.loads(next(directory.rglob('simulator-result.json')).read_text(encoding='utf-8'))
assert native['success'] is True and native['sourceCommit'] == source
assert native['results'] and all(value == 'success' for value in native['results'].values())
photo_kit_tests = next(directory.rglob('simulator-tests.log')).read_text(encoding='utf-8')
assert '** TEST EXECUTE SUCCEEDED **' in photo_kit_tests
assert re.search(r'Executed 5 tests, with 0 failures', photo_kit_tests)

required_ui_cases = {
    'testCameraPresenterRecoversFromMissingAndDetachedRegistration',
    'testCameraPresenterRejectsBackgroundAndHiddenWindows',
    'testCameraPresentationCancellationPreventsQueuedPresentation',
    'testNativeTaskCancellationRetiresBeforeDelivery',
    'testPhotoLibraryConsent',
}
passed_ui_cases = set(re.findall(r"Test Case '-\[[^]]+ (test\w+)\]' passed", photo_kit_tests))
assert required_ui_cases <= passed_ui_cases, (required_ui_cases, passed_ui_cases)

from foreground_evidence227 import verify_foreground
foreground_proof = verify_foreground(directory, source, lambda path: subprocess.check_output(['git', 'show', source + ':' + path], cwd=root))
foreground_snapshot = foreground_proof['snapshot']
foreground_evidence = foreground_proof['evidence']
foreground_verified = foreground_proof['passed']
foreground_source_proof = foreground_proof['sourceProof']

parity_path = next(directory.rglob('parity.json'))
parity = json.loads(parity_path.read_text(encoding='utf-8'))
assert parity['pass'] is True
golden_path = root / 'docs/migration/validation/features-227/core/golden.json'
assert parity['golden'] == json.loads(golden_path.read_text(encoding='utf-8'))
shutil.copyfile(golden_path, out.parent / 'jvm-golden.json')
shutil.copyfile(parity_path, out / 'core-parity.json')
tests = next(directory.rglob('flutter-tests.log')).read_text(encoding='utf-8')
passed = re.findall(r'\+(\d+): All tests passed!', tests)
assert passed
assert int(passed[-1]) >= 721, 'Full Flutter suite must retain all 721 current widget/controller tests'
android_source = source_metadata['sourceCommit']
assert source == android_source, 'Apple and Android must use the same frozen product source'
changes = subprocess.check_output(['git', 'diff', '--name-only', android_source, source],
                                  cwd=root, text=True).splitlines()
ci = {'run': run_id, 'url': run['html_url'], 'sourceCommit': source,
      'conclusion': run['conclusion'], 'flutterTestsPassed': int(passed[-1]), 'photoKitXCTestPassed': True,
      'nativeScenariosPassed': len(native['results']), 'uiKitTestsPassed': 5, 'cameraPresentationUIKitTestsPassed': 3, 'nativeTaskCancellationUIKitTestsPassed': 1, 'nativeForegroundSnapshotFixturePassed': foreground_verified, 'nativeForegroundSnapshot': foreground_snapshot, 'nativeForegroundSnapshotEvidence': foreground_evidence, 'nativeForegroundSourceProof': foreground_source_proof, 'androidSourceCommit': android_source,
      'publicInternetAppleIsolationPassed': public_internet['passed'],
      'publicInternetAppleSourceProof': public_internet['sourceProof'],
      'publicInternetAppleCompileExitCode': public_internet['compileExitCode'],
      'publicInternetAppleExecutionExitCode': public_internet['executionExitCode'],
       'fullMacSourceProof': full_source_proof,
      'changesFromAndroidSource': changes}
(out / 'ci-result.json').write_text(json.dumps(ci, indent=2) + '\n')
target = root / '.tooling/next227/package-candidates/huevia-0.31.0-dev-227-ios-unsigned.ipa'
shutil.copyfile(ipa, target)
print(json.dumps({'verified': True, 'source': source, 'path': str(target),
                  'sha256': verified['sha256'], 'bytes': verified['bytes'],
                  'flutterTests': ci['flutterTestsPassed'], 'nativeScenarios': ci['nativeScenariosPassed']}))
