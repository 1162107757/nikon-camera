#!/usr/bin/env python3
"""Offline, credential-free code/SQL/IAM review bundle. Never deploys or reads .local."""
from pathlib import Path
from io import BytesIO
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
LIBRARY = ROOT / 'online-library'
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=ROOT / 'dist/migration213/deployment-review')
parser.add_argument('--android-arm64', type=Path, default=ROOT / 'dist/migration213/huevia-0.31.0-dev-213-android-arm64.apk')
parser.add_argument('--android-x64', type=Path, default=ROOT / 'dist/migration213/huevia-0.31.0-dev-213-android-x64.apk')
parser.add_argument('--ios-ipa', type=Path, default=ROOT / 'dist/migration213/huevia-0.31.0-dev-213-ios-unsigned.ipa')
parser.add_argument('--android-evidence', type=Path, default=ROOT / 'docs/migration/validation/features-213/android-signing-alignment.json')
parser.add_argument('--android-source-revision', default='3db73d2', help='Declared Android build source; not a rebuild attestation')
parser.add_argument('--release-notes', type=Path, help='Reviewed exact UTF-8 release notes, required before approval readiness')
parser.add_argument('--rollback-main', type=Path, help='Read-only captured current Active main function ZIP')
parser.add_argument('--rollback-backup', type=Path, help='Read-only captured current Active backup worker ZIP')
parser.add_argument('--rollback-iam', type=Path, help='Captured policy IDs, versions and documents using the plan schema')
parser.add_argument('--database-precheck', type=Path, help='Read-only production metadata result before applying 022')
parser.add_argument('--production-capture', type=Path, help='Bind only the allowlisted redacted production capture files')
args = parser.parse_args()
out = args.output.resolve()
if not out.is_relative_to(ROOT):
    parser.error('Review output must stay inside the current workspace')
out.mkdir(parents=True, exist_ok=True)
sha = lambda data: hashlib.sha256(data).hexdigest()
generated = set()


def source_bytes(path):
    path = path.resolve() if not path.is_symlink() else path
    if path.is_symlink() or not path.resolve().is_relative_to(ROOT) or any(part == '.local' or part.startswith('.env') for part in path.parts):
        raise ValueError('Source must be a regular file inside the current workspace')
    return path.read_bytes()


def write_output(name, data):
    target = out / name
    if target.is_symlink() or not target.resolve().is_relative_to(out):
        raise ValueError('Review output must stay inside its output directory')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    generated.add(name)


def zip_bytes(path, files):
    with ZipFile(path, 'w', ZIP_DEFLATED, compresslevel=9) as archive:
        for name, (data, mode) in sorted(files.items()):
            if name.startswith('/') or '..' in Path(name).parts or any(part in {'.local', '.env', 'node_modules', '.git'} for part in Path(name).parts):
                raise ValueError('Forbidden package path')
            entry = ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = mode << 16
            entry.compress_type = ZIP_DEFLATED
            archive.writestr(entry, data)


NODE_INSPECT = r'''
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const input = JSON.parse(readFileSync(0, 'utf8'));
const apk = await import(pathToFileURL(input.apkModule));
const ipa = await import(pathToFileURL(input.ipaModule));
if (apk.MAX_APK_BYTES !== 32 * 1024 * 1024 || apk.MAX_NEXT_APK_BYTES !== 128 * 1024 * 1024 ||
    JSON.stringify(apk.APK_PACKAGES) !== JSON.stringify(['cc.huevia', 'com.nikonpreset.usbprobe']) ||
    apk.APK_SIGNER_SHA256 !== '04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31' ||
    apk.APK_PACKAGES.some(name => apk.APK_SIGNERS[name] !== apk.APK_SIGNER_SHA256)) throw Error('Legacy release trust boundary changed');
let defaultLimit = false;
try { apk.inspectApk(Buffer.alloc(apk.MAX_APK_BYTES + 1)); }
catch (error) { defaultLimit = /32 MiB/.test(error.message); }
if (!defaultLimit) throw Error('Default inspectApk must reject above 32 MiB before ZIP parsing');
const result = [];
for (const item of input.artifacts) {
  const bytes = readFileSync(item.path);
  const metadata = item.platform === 'android' ? apk.inspectApk(bytes, {packageName: 'cc.huevia.next'}) : ipa.inspectIpa(bytes);
  result.push({...item, metadata});
}
console.log(JSON.stringify({defaultLegacy32MiBGuardVerified: true, artifacts: result}));
'''

if args.production_capture:
    captured = args.production_capture.resolve()
    for field, filename in [('rollback_main', 'main-active.zip'), ('rollback_backup', 'backup-active.zip'),
                            ('rollback_iam', 'iam-before.json'), ('database_precheck', 'database-before-022.json')]:
        if getattr(args, field) is None and (captured / filename).is_file():
            setattr(args, field, captured / filename)


requested = [('androidArm64', args.android_arm64, 'android', 'arm64-v8a'),
             ('androidX64', args.android_x64, 'android', 'x86_64'),
             ('iosUnsignedIpa', args.ios_ipa, 'ios', None)]
inputs, artifact_bytes = [], {}
for key, path, platform, abi in requested:
    if not path.exists():
        continue
    if path.stat().st_size > 128 * 1024 * 1024 or not re.fullmatch(r'[A-Za-z0-9._-]+\.(apk|ipa)', path.name):
        raise ValueError('Invalid or oversized release artifact: ' + key)
    data = source_bytes(path)
    artifact_bytes[key] = data
    inputs.append({'key': key, 'path': str(path.resolve()), 'platform': platform, 'expectedAbi': abi})
inspection = subprocess.run(['node', '--input-type=module', '-e', NODE_INSPECT],
    input=json.dumps({'apkModule': str(LIBRARY / 'server/apk.mjs'), 'ipaModule': str(LIBRARY / 'server/ipa.mjs'), 'artifacts': inputs}),
    cwd=ROOT, capture_output=True, text=True, encoding='utf-8', check=True)
inspected = json.loads(inspection.stdout)
evidence_bytes = source_bytes(args.android_evidence) if any(item['platform'] == 'android' for item in inputs) else None
evidence = json.loads(evidence_bytes) if evidence_bytes else []
artifacts = {}
for item in inspected['artifacts']:
    key, metadata = item['key'], item['metadata']
    data = artifact_bytes[key]
    if metadata['sha256'] != sha(data) or metadata['byteLength'] != len(data) or str(metadata['versionCode']) != '213':
        raise ValueError('Artifact bytes/version changed or are not actual version 213: ' + key)
    if item['platform'] == 'android':
        if metadata['packageName'] != 'cc.huevia.next' or metadata['signerSha256'] != '76398947a8b493df81ebf2e90ad7b62e3eefee5fcf6cf865feaaa9bef8127b75' or metadata['abis'] != [item['expectedAbi']]:
            raise ValueError('Unexpected Android identity, signer or ABI: ' + key)
        rows = [row for row in evidence if row.get('abi') == ('arm64' if key == 'androidArm64' else 'x64')]
        if len(rows) != 1 or rows[0]['sha256'] != sha(data) or rows[0]['bytes'] != len(data) or any(rows[0].get(flag) is not True for flag in ['apksignerVerified', 'zipalign16KiBVerified', 'allLoadSegments16KiBVerified']):
            raise ValueError('Android signing/alignment evidence does not match actual bytes: ' + key)
    elif metadata['bundleId'] != 'cc.huevia.next' or metadata['distribution'] != 'unsigned-ipa':
        raise ValueError('Unexpected iOS bundle/distribution')
    name = 'artifacts/' + key + '/' + Path(item['path']).name
    write_output(name, data)
    artifacts[key] = {'path': name, 'sourcePath': Path(item['path']).relative_to(ROOT).as_posix(),
        'metadata': metadata, 'releaseId': None, 'publishedDownloadUrl': None,
        'intendedUse': 'direct-delivery-only; same-version mobile service has one asset' if key == 'androidX64' else 'candidate-for-reviewed-beta-draft'}
if evidence_bytes:
    write_output('evidence/android-signing-alignment.json', evidence_bytes)
try:
    android_source_revision = subprocess.check_output(['git', 'rev-parse', '--verify', args.android_source_revision + '^{commit}'], cwd=ROOT, text=True).strip()
except (OSError, subprocess.CalledProcessError):
    raise ValueError('Declared Android source revision must exist in this workspace')
release_notes = None
if args.release_notes:
    notes = source_bytes(args.release_notes)
    text_notes = notes.decode('utf-8').strip()
    if not text_notes or len(text_notes) > 4000:
        raise ValueError('Release notes must contain 1..4000 UTF-8 characters')
    write_output('RELEASE-NOTES.txt', notes)
    release_notes = {'path': 'RELEASE-NOTES.txt', 'sha256': sha(notes), 'bytes': len(notes)}
rollback = {}
for key, path in [('mainFunction', args.rollback_main), ('backupFunction', args.rollback_backup)]:
    if not path:
        continue
    if path.stat().st_size > 128 * 1024 * 1024:
        raise ValueError('Production rollback archive exceeds review size limit')
    data = source_bytes(path)
    with ZipFile(BytesIO(data)) as archive:
        entries = archive.infolist()
        if not entries or len(entries) > 4096 or sum(entry.file_size for entry in entries) > 512 * 1024 * 1024 or any(
            entry.filename.startswith('/') or '\\' in entry.filename or '..' in Path(entry.filename).parts
            or (entry.external_attr >> 16) & 0o170000 == 0o120000 or entry.flag_bits & 1
            or re.search(r'(?:^|/)(?:\.env[^/]*|\.local|\.git)(?:/|$)', entry.filename) for entry in entries):
            raise ValueError('Unsafe production rollback archive')
        if archive.testzip() is not None:
            raise ValueError('Production rollback archive CRC mismatch')
    name = 'rollback/' + ('main-active.zip' if key == 'mainFunction' else 'backup-active.zip')
    write_output(name, data)
    rollback[key] = {'path': name, 'sha256': sha(data), 'bytes': len(data), 'captureClaimRequiresProductionReview': True}
    if args.production_capture:
        evidence_name = 'main-active.json' if key == 'mainFunction' else 'backup-active.json'
        evidence_data = source_bytes(args.production_capture / evidence_name)
        state = json.loads(evidence_data)
        allowed = {'schema', 'capturedAt', 'namespace', 'functionName', 'qualifier', 'codeBytes', 'codeSha256',
                   'providerCodeSha256Matched', 'configurationStableDuringCapture', 'environmentValuesExcluded',
                   'Status', 'Runtime', 'Role', 'MemorySize', 'Timeout', 'InitTimeout', 'Handler', 'Type', 'ModTime',
                   'AddTime', 'FunctionVersion', 'CodeSize', 'ClsLogsetId', 'ClsTopicId'}
        expected_function = 'nikon-preset-library' if key == 'mainFunction' else 'huevia-data-backup'
        expected_role = 'HueviaUpdatePackageRole' if key == 'mainFunction' else 'HueviaDataBackupRole'
        if set(state) - allowed or state.get('namespace') != 'nikon-d8girdjsr252fd90e' or state.get('functionName') != expected_function or state.get('Role') != expected_role or state.get('Status') != 'Active' or state.get('codeSha256') != sha(data) or state.get('codeBytes') != len(data) or any(state.get(flag) is not True for flag in ['providerCodeSha256Matched', 'configurationStableDuringCapture', 'environmentValuesExcluded']):
            raise ValueError('Redacted production metadata must match its actual Active rollback archive')
        evidence_target = 'evidence/production/' + evidence_name
        write_output(evidence_target, evidence_data)
        rollback[key]['captureEvidence'] = {'path': evidence_target, 'sha256': sha(evidence_data), 'capturedAt': state['capturedAt']}
if args.rollback_iam:
    data = source_bytes(args.rollback_iam)
    policies = json.loads(data)
    if policies.get('schema') != 1 or not policies.get('capturedAt'):
        raise ValueError('IAM snapshot requires schema 1 and capturedAt')
    for role in ['release', 'backup']:
        policy = policies.get(role, {})
        expected_policy = '293055026' if role == 'release' else '293266107'
        if not isinstance(policy.get('roleArn'), str) or not policy['roleArn'].startswith('qcs::cam::uin/1162107757:role') or str(policy.get('policyId')) != expected_policy or not re.fullmatch(r'[1-9][0-9]*', str(policy.get('version', ''))) or not isinstance(policy.get('document', {}).get('statement'), list):
            raise ValueError('IAM snapshot requires both actual role/policy IDs, versions and policy documents')
    if re.search(r'"(?:secret|secretId|secretKey|password|accessToken|refreshToken|privateKey)"\s*:', data.decode('utf-8'), re.I):
        raise ValueError('IAM review snapshot must not contain credentials')
    write_output('rollback/iam-before.json', data)
    rollback['iamPolicies'] = {'path': 'rollback/iam-before.json', 'sha256': sha(data), 'bytes': len(data), 'captureClaimRequiresProductionReview': True}
    semantic_diff = {'schema': 1, 'beforeSnapshotSha256': sha(data), 'capturedAt': policies['capturedAt'],
        'comparison': 'Parsed JSON equality after removing only the exact approved added resource prefixes; not a schema-only check',
        'policies': {}, 'backupRetention': {'verified': False, 'reason': 'Production backup ZIP not bound'}}
    prefix = 'qcs::cos:ap-shanghai:uid/1252602548:huevia-updates-1252602548/huevia-updates/'
    for role, filename in [('release', 'cos-release-policy.json'), ('backup', 'cos-backup-policy.json')]:
        candidate_bytes = source_bytes(LIBRARY / 'infra' / filename)
        candidate = json.loads(candidate_bytes)
        reduced = json.loads(candidate_bytes)
        expected_added = [prefix + 'mobile-releases/*'] + ([prefix + 'mobile-upload/*'] if role == 'release' else [])
        expected_actions = ['name/cos:GetObject', 'name/cos:PutObject'] if role == 'release' else ['name/cos:GetObject']
        observed_added, permissions = [], []
        for statement in reduced['statement']:
            added = [resource for resource in statement['resource'] if resource in expected_added]
            if added:
                if statement.get('effect') != 'allow' or sorted(statement['action']) != sorted(expected_actions):
                    raise ValueError('Unexpected actions granted on a new mobile prefix')
                observed_added.extend(added)
                permissions.extend({'effect': 'allow', 'actions': expected_actions, 'resource': resource} for resource in added)
            statement['resource'] = [resource for resource in statement['resource'] if resource not in added]
        if sorted(observed_added) != sorted(expected_added) or reduced != policies[role]['document']:
            raise ValueError('Candidate IAM policy changes more than the reviewed mobile prefixes: ' + role)
        semantic_diff['policies'][role] = {'policyId': str(policies[role]['policyId']), 'beforeVersion': str(policies[role]['version']),
            'candidateFile': 'policies/' + filename, 'candidateSha256': sha(candidate_bytes),
            'addedPermissions': permissions, 'removedPermissions': [], 'allExistingPolicyJsonPreserved': True}
    if args.rollback_backup:
        with ZipFile(BytesIO(source_bytes(args.rollback_backup))) as archive:
            old_core = archive.read('backup/core.mjs').decode('utf-8').replace('\r\n', '\n')
            old_runtime = archive.read('backup/runtime.mjs').decode('utf-8').replace('\r\n', '\n')
        new_core = source_bytes(LIBRARY / 'backup/core.mjs').decode('utf-8').replace('\r\n', '\n')
        new_runtime = source_bytes(LIBRARY / 'backup/runtime.mjs').decode('utf-8').replace('\r\n', '\n')
        def unique_line(text, marker):
            matches = [line.strip() for line in text.splitlines() if marker in line]
            if len(matches) != 1:
                raise ValueError('Cannot establish the existing backup retention boundary')
            return matches[0]
        def list_guard(text):
            return text[text.index('    async list(prefix,marker)'):text.index('    remove:key')].strip()
        old_prune = old_core[old_core.index('export async function pruneOldBackups('):].strip()
        new_prune = new_core[new_core.index('export async function pruneOldBackups('):].strip()
        if old_prune != new_prune or 'now-30*86400000' not in new_prune:
            raise ValueError('Backup 30-day cleanup implementation changed')
        for marker in ["export const PREFIX=", 'const shanghaiDay=']:
            if unique_line(old_core, marker) != unique_line(new_core, marker):
                raise ValueError('Backup prefix or Shanghai calendar boundary changed')
        for marker in ['const own=key=>', "remove:key=>call('deleteObject'", 'const removed=await pruneOldBackups(storage,result)']:
            if unique_line(old_runtime, marker) != unique_line(new_runtime, marker):
                raise ValueError('Backup deletion guard or successful-backup cleanup sequencing changed')
        if list_guard(old_runtime) != list_guard(new_runtime) or old_runtime.count("'deleteObject'") != new_runtime.count("'deleteObject'") or old_core.count('storage.remove(') != new_core.count('storage.remove('):
            raise ValueError('Backup list/delete scope changed')
        semantic_diff['backupRetention'] = {'verified': True, 'retentionDays': 30, 'calendar': 'Asia/Shanghai',
            'prefix': 'huevia-backups/daily/', 'pruneFunctionSha256': sha(new_prune.encode('utf-8')),
            'pruneFunctionIdenticalToProduction': True, 'prefixAndCalendarHelpersIdentical': True,
            'storageListAndDeleteGuardsIdentical': True, 'cleanupAfterSuccessfulBackupCallIdentical': True,
            'deleteCallCountsUnchanged': True,
            'iamTimeBoundary': 'IAM limits the object scope; the unchanged worker implements the 30-day time boundary'}
    semantic_bytes = (json.dumps(semantic_diff, indent=2) + '\n').encode('utf-8')
    write_output('evidence/production/iam-semantic-diff.json', semantic_bytes)
    rollback['iamPolicies']['semanticDiffEvidence'] = {'path': 'evidence/production/iam-semantic-diff.json', 'sha256': sha(semantic_bytes)}
database_precheck = None
if args.database_precheck:
    data = source_bytes(args.database_precheck)
    state = json.loads(data)
    required = state.get('prerequisites', {})
    if state.get('queryReadOnly') is not True or state.get('mobileTables') != [] or state.get('mobileManageRpc') is not False or state.get('mobileBudgetRpc') is not False or sorted(required.get('roles', [])) != ['anon', 'authenticated', 'service_role'] or any(required.get(flag) is not True for flag in ['adminAllowedFunction', 'uuidFunction', 'legacyReleasesTable', 'backupSnapshotFunction']):
        raise ValueError('Production 022 precondition evidence is incomplete or no longer matches this plan')
    write_output('evidence/production/database-before-022.json', data)
    database_precheck = {'path': 'evidence/production/database-before-022.json', 'sha256': sha(data), 'capturedAt': state['capturedAt']}
if args.production_capture:
    for name in ['iam-role-bindings.json', 'iam-policy-probe.json', 'browser-state.json', 'cli-caller-identity.json',
                 'admin-session-preflight.json', 'admin-credential-preflight.json', 'deployment-access-preflight.json']:
        path = args.production_capture / name
        if path.is_file():
            data = source_bytes(path)
            json.loads(data)
            if re.search(r'"(?:Environment|Variables|secret|secretId|secretKey|password|accessToken|refreshToken|privateKey|Cookie)"\s*:', data.decode('utf-8'), re.I):
                raise ValueError('Production evidence must exclude credential-bearing configuration')
            write_output('evidence/production/' + name, data)


runtime = {}
for directory in ('server', 'admin', 'download'):
    for path in sorted((LIBRARY / directory).rglob('*')):
        if path.is_symlink():
            raise ValueError('Source symlinks are excluded from deployment packages')
        if path.is_file():
            name = path.relative_to(LIBRARY).as_posix()
            if re.search(r'(?:\.env|\.local|node_modules|test|scripts|database)', name):
                raise ValueError('Unexpected runtime package path')
            runtime[name] = (source_bytes(path), 0o100644)
runtime['package.json'] = (source_bytes(LIBRARY / 'package.json'), 0o100644)
runtime['scf_bootstrap'] = (source_bytes(LIBRARY / 'scf_bootstrap').replace(b'\r\n', b'\n'), 0o100755)
if (out / 'runtime-service.zip').is_symlink():
    raise ValueError('Package output must not be a symlink')
zip_bytes(out / 'runtime-service.zip', runtime)
generated.add('runtime-service.zip')
backup = {
    'index.js': (source_bytes(LIBRARY / 'backup/index.cjs'), 0o100644),
    **{f'backup/{name}': (source_bytes(LIBRARY / 'backup' / name), 0o100644) for name in ('core.mjs', 'runtime.mjs')},
    'backup/recovery/RECOVERY.md': (source_bytes(LIBRARY / 'backup/RECOVERY.md'), 0o100644),
    'backup/recovery/schema-migrations.sql': (b'\n\n'.join(source_bytes(path) for path in sorted((LIBRARY / 'database').glob('[0-9]*.sql'))), 0o100644),
}
for path in sorted((LIBRARY / 'server/vendor').iterdir()):
    if path.is_file():
        backup['server/vendor/' + path.name] = (source_bytes(path), 0o100644)
if (out / 'backup-worker.zip').is_symlink():
    raise ValueError('Package output must not be a symlink')
zip_bytes(out / 'backup-worker.zip', backup)
generated.add('backup-worker.zip')
copies = {
    'database/022-mobile-releases.sql': LIBRARY / 'database/022-mobile-releases.sql',
    'policies/cos-release-policy.json': LIBRARY / 'infra/cos-release-policy.json',
    'policies/cos-backup-policy.json': LIBRARY / 'infra/cos-backup-policy.json',
    'PLAN.md': ROOT / 'docs/migration/a13-deployment-plan.md',
    'SOURCE-REVIEW.md': ROOT / 'docs/migration/account-delivery-development.md',
    'QQ-DEPENDENCIES.md': ROOT / 'docs/migration/qq-android-dependencies.md',
    'CAM-READONLY.md': ROOT / 'docs/migration/cam-readonly-setup.md',
    'ADMIN-LOGIN.md': ROOT / 'docs/migration/release-admin-login.md',
    'policies/cam-readonly-optional-proposal.json': ROOT / 'docs/migration/cam-readonly-policy.json',
    'tools/prepare-mobile-release.mjs': LIBRARY / 'scripts/prepare-mobile-release.mjs',
    'tools/login-release-admin.mjs': LIBRARY / 'scripts/login-release-admin.mjs',
    'tools/login-release-admin.test.mjs': LIBRARY / 'test/login-release-admin.test.mjs',
    'tools/package-mobile-release-review.py': Path(__file__),
}
for name, source in copies.items():
    write_output(name, source_bytes(source))
write_output('database/disable-mobile-release-management.sql', (
    '-- Optional reviewed stop switch; withdraw newly published versions first. No rows or objects are deleted.\n'
    'BEGIN;\nREVOKE EXECUTE ON FUNCTION public.nikon_mobile_release_manage(text,text,jsonb) FROM service_role;\nCOMMIT;\n').encode('utf-8'))
pending = {'actual213AndroidArm64Apk': artifacts.get('androidArm64'),
           'actual213AndroidX64Apk': artifacts.get('androidX64'),
           'actual213IosUnsignedIpa': artifacts.get('iosUnsignedIpa'),
           'productionMainFunctionRollbackArchive': rollback.get('mainFunction'),
           'productionBackupFunctionRollbackArchive': rollback.get('backupFunction'),
           'productionIamPolicyVersionsBeforeChange': rollback.get('iamPolicies'),
           'productionDatabasePrecheck': database_precheck,
           'reviewedReleaseNotes': release_notes}
missing = [name for name, value in pending.items() if value is None]
readiness = {'artifactsComplete': len(artifacts) == 3, 'productionRollbackComplete': len(rollback) == 3,
             'databasePrecheckBound': database_precheck is not None, 'releaseNotesBound': release_notes is not None, 'approvalReady': not missing,
             'missing': missing, 'authorizedToDeploy': False, 'authorizedToPublish': False}
artifact_binding = {'schema': 1, 'expectedVersionCode': 213, 'artifacts': artifacts,
    'androidSourceRevisionDeclared': android_source_revision, 'sourceRevisionIsNotARebuildAttestation': True,
    'androidSigningAlignmentEvidence': 'evidence/android-signing-alignment.json' if evidence_bytes else None,
    'defaultLegacy32MiBGuardVerified': inspected['defaultLegacy32MiBGuardVerified'],
    'qqExternalAcceptance': {'androidRegistration': 'user said possible; actual saved registration remains unverified',
                             'iosUniversalLink': 'user explicitly said not configured'},
    'readiness': readiness}
write_output('ARTIFACTS.json', (json.dumps(artifact_binding, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))
write_output('REVIEW-STATUS.md', ('# Offline review readiness\n\n'
    + ('Inputs are complete for a separate human production review.\n' if not missing else 'INCOMPLETE: deployment/publication approval is not ready.\n')
    + '\nBound artifacts: ' + ', '.join(sorted(artifacts)) + '.\n'
    + '\nMissing inputs:\n' + ('\n'.join('- ' + name for name in missing) if missing else '- None')
    + '\n\nNo cloud operation or publication has been performed. Release IDs and published file URLs stay null until the real service returns them.\n'
    + 'The source revision is declared build provenance, not a reproducible-build attestation or a production rollback snapshot.\n').encode('utf-8'))
write_output('PENDING-INPUTS.json', (json.dumps(pending, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))
source_files = [{'path': f'online-library/{name}', 'bytes': len(data), 'sha256': sha(data)} for name, (data, _) in sorted(runtime.items())]
try:
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
except (OSError, subprocess.CalledProcessError):
    head = None
manifest = {'schema': 2, 'kind': 'offline-mobile-release-review', 'deployed': False, 'published': False,
    'environmentId': 'nikon-d8girdjsr252fd90e', 'region': 'ap-shanghai',
    'baseUrl': 'https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com/preset-library',
    'headAtPackaging': head, 'headIsNotADeployedVersionClaim': True, 'pending': pending,
    'artifactBinding': artifact_binding, 'readiness': readiness,
    'runtimeSources': source_files, 'backupSources': [{'path': name, 'bytes': len(data), 'sha256': sha(data)} for name, (data, _) in sorted(backup.items())],
    'files': []}
for name in sorted(generated):
    data = (out / name).read_bytes()
    manifest['files'].append({'path': name, 'bytes': len(data), 'sha256': sha(data)})
write_output('MANIFEST.json', (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))
outer = {name: ((out / name).read_bytes(), 0o100644) for name in sorted(generated)}
if (out / 'deployment-review.zip').is_symlink():
    raise ValueError('Package output must not be a symlink')
zip_bytes(out / 'deployment-review.zip', outer)
print(json.dumps({'output': str(out), 'reviewZipSha256': sha((out / 'deployment-review.zip').read_bytes()),
    'runtimeZipSha256': sha((out / 'runtime-service.zip').read_bytes()),
    'backupZipSha256': sha((out / 'backup-worker.zip').read_bytes()),
    'runtimeFiles': len(runtime), 'backupFiles': len(backup), 'artifacts': sorted(artifacts),
    'readiness': readiness, 'deployed': False, 'published': False}, ensure_ascii=False))
