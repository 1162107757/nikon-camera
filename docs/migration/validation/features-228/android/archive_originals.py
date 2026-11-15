from pathlib import Path
import hashlib,json,tarfile,datetime,re
ROOT=Path(__file__).resolve().parents[2] if Path(__file__).resolve().parent.name=='next228' else Path(__file__).resolve().parents[5]
BASE=ROOT/'.tooling/next228'
DEST=ROOT/'docs/migration/validation/features-228/android'
EXPECTED='734aa3b0f6687dda815af9e13070f0f3c463873c'
SOURCE_SNAPSHOT=(DEST/'receipts/source.json').read_bytes() if (DEST/'receipts/source.json').is_file() else (BASE/'source.json').read_bytes()
assert json.loads(SOURCE_SNAPSHOT)['sourceCommit']==EXPECTED
sha=lambda b:hashlib.sha256(b).hexdigest()
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
gui=readj(BASE/'live-panel-gui-result.json')
assert gui['exit']==0 and gui['sourceCommit']==EXPECTED and len(gui['cases'])==5 and all(x['exit']==0 for x in gui['cases'])
assert readj(BASE/'android-release-result.json')['sourceCommit']==EXPECTED and readj(BASE/'android-release-result.json')['exit']==0
assert readj(BASE/'android-acceptance-pipeline.json')==dict(verify_android=0,verify_photos=0,run_release_runtime=0,check_back_navigation=0)
r8=readj(BASE/'release-runtime-result.json');back=readj(BASE/'back-navigation-result.json')
assert r8['sourceCommit']==EXPECTED and r8['exit']==0 and r8['accepted'] and r8['checksPassed']>=123 and r8['apkSha256']==gui['apkSha256']
assert back['sourceCommit']==EXPECTED and back['exit']==0 and len(back['rootCases'])==4 and all(x['sameActivityAndProcess'] for x in back['rootCases']) and back['connectionPageBackReturnsToSync'] and back['queueBackReturnsToSync']
photos=readj(ROOT/'docs/migration/validation/features-228/preset-preview-assets.json')
assert photos['sourceCommit']==EXPECTED and photos['imageCount']==10 and photos['allTenPreservedByteForByte']
newqa=(BASE/'qa_ui.py').read_text(encoding='utf-8-sig')
assert 'range(3)' in newqa and "E.fromstring(raw).tag == 'hierarchy'" in newqa and "b'dumped to:'" in newqa
local=readj(BASE/'local-ui-results.json')
assert local==[dict(step=name,exit=0) for name in ['format','analyze','sync-layout','download-circle']]
for name,count in [('sync-layout.log',7),('download-circle.log',4)]:
 text=(BASE/name).read_text(encoding='utf-8',errors='replace')
 assert re.search(r'\+'+str(count)+r': All tests passed!',text)
for name in ['format.exit','analyze.exit','sync-layout.exit','download-circle.exit']:
 assert (BASE/name).read_text().strip()=='0'
DEST.mkdir(parents=True,exist_ok=True)
(DEST/'archive_originals.py').write_bytes(Path(__file__).read_bytes())
(DEST/'verify_archive.py').write_bytes((BASE/'verify_android_archive.py').read_bytes())
entries=[]
def record(src,dst,member=None):
 data=SOURCE_SNAPSHOT if src==BASE/'source.json' else src.read_bytes()
 if member is None:out=(DEST/dst).read_bytes()
 else:
  with tarfile.open(DEST/dst,'r:xz') as archive:out=archive.extractfile(member).read()
 assert data==out,(src,dst,member)
 entries.append(dict(source=str(src.relative_to(ROOT)).replace('\\','/'),destination=dst,member=member,sourceBytes=len(data),destinationBytes=len(out),sourceSha256=sha(data),destinationSha256=sha(out),byteForByteEqual=True))
def copy(src,dst):
 path=DEST/dst;path.parent.mkdir(parents=True,exist_ok=True);data=SOURCE_SNAPSHOT if src==BASE/'source.json' else src.read_bytes()
 if path.exists():assert path.read_bytes()==data,('existing different artifact',path)
 else:path.write_bytes(data)
 record(src,dst)
receipts=['source.json','android-release-result.json','android-arm64-release.log','android-x64-release.log','arm64-gradle.log','x64-gradle.log','instrumentation-build.log','instrumentation-runner-build.log','instrumentation-runner-build.exit','arm64-apksigner.bat-final.log','x64-apksigner.bat-final.log','arm64-zipalign.exe-final.log','x64-zipalign.exe-final.log','verify_android-pipeline.log','verify_photos-pipeline.log','release-runtime.log','release-runtime-result.json','release-runtime-mapping.json','run_release_runtime-pipeline.log','check_back_navigation-pipeline.log','back-navigation-result.json','live-panel-gui.log','live-panel-gui-result.json','android-acceptance-pipeline.json','android_acceptance_pipeline-launcher.log','build_releases-launcher.log','preservation-final.log','preservation-final.exit','helper-review.json','format.log','format.exit','analyze.log','analyze.exit','sync-layout.log','sync-layout.exit','download-circle.log','download-circle.exit','local-ui-results.json']
for name in receipts:copy(BASE/name,'receipts/'+name)
for name in ['android-signing-alignment.json','preset-preview-assets.json']:copy(ROOT/'docs/migration/validation/features-228'/name,'receipts/'+name)
for name in ['build_releases.py','verify_android.py','verify_photos.py','run_release_runtime.py','check_back_navigation.py','check_live_panel_gui.py','qa_ui.py','android_acceptance_pipeline.py','run_back_final.py','local_ui_checks.py']:copy(BASE/name,'helpers/next226/'+name)
for name in ['android_build.py','verify_android_apk.py','raw_android.py']:copy(ROOT/'cross-platform/tool'/name,'helpers/cross-platform/tool/'+name)
copy(BASE/'release-runtime.init.gradle','runtime/release-runtime.init.gradle')
copy(ROOT/'.tooling/cross-platform187/maven-proxy.init.gradle','runtime/maven-proxy.init.gradle')
for src,dst in [('cross-platform/app/android/app/src/androidTest/java/cc/huevia/sharedapp/ReleaseRuntimeInstrumentation.java','runtime/ReleaseRuntimeInstrumentation.java'),('cross-platform/app/android/app/build.gradle.kts','runtime/app-build.gradle.kts'),('cross-platform/app/android/build.gradle.kts','runtime/root-build.gradle.kts'),('cross-platform/app/android/settings.gradle.kts','runtime/settings.gradle.kts'),('cross-platform/app/android/gradle.properties','runtime/gradle.properties'),('cross-platform/app/android/gradlew.bat','runtime/gradlew.bat'),('cross-platform/app/android/gradle/wrapper/gradle-wrapper.properties','runtime/gradle-wrapper.properties')]:copy(ROOT/src,dst)
pngs=[]
for src in sorted((BASE/'ui').iterdir()):
 if not src.name.startswith(('back227-','gui227-')):continue
 if src.suffix=='.xml':copy(src,'ui/'+src.name)
 elif src.suffix=='.png':pngs.append((src,'ui/'+src.name))
failed=[]
for attempt in failed:
 q=readj(BASE/'attempts'/attempt/'qualification.json');assert q['exit']==1 and q['productFailureEstablished']==False
 for src in sorted((BASE/'attempts'/attempt).iterdir()):
  dst='../attempts/'+attempt+'/'+src.name
  if src.suffix=='.png':pngs.append((src,dst))
  elif src.is_file():copy(src,dst)
def pack(name,files):
 with tarfile.open(DEST/name,'w:xz',preset=6) as archive:
  for src,member in files:archive.add(src,arcname=member,recursive=False)
 for src,member in files:record(src,name,member)
assert len(pngs)==15, 'Expected 7 Back and 8 GUI current snapshots'
pack('ui-screenshots.tar.xz',pngs)
mappings=[(BASE/(abi+'-mapping.txt'),'mappings/'+abi+'-mapping.txt') for abi in ['arm64','x64']]
assert sha(mappings[1][0].read_bytes())==r8['mappingSha256']
pack('r8-mappings.tar.xz',mappings)
signing=readj(ROOT/'docs/migration/validation/features-228/android-signing-alignment.json')
packages=[]
for value in signing:
 path=BASE/'package-candidates'/('huevia-0.31.0-dev-228-android-'+value['abi']+'.apk')
 data=path.read_bytes();assert len(data)==value['bytes'] and sha(data)==value['sha256']
 assert value['apksignerVerified'] and value['zipalign16KiBVerified'] and value['allLoadSegments16KiBVerified']
 packages.append(dict(path=str(path.relative_to(ROOT)).replace('\\','/'),bytes=len(data),sha256=sha(data),copied=False))
qualification=dict(
 schema=1,sourceCommit=EXPECTED,build=228,published=False,
 scope='Fresh Android source734aa3b build/gate/runtime/UI receipts; no previous-build attempt payloads or physical-camera transport acceptance.',
 gateSummary=dict(androidBuildExit=0,verifyAndroidExit=0,presetPhotoExit=0,r8Checks=123,rootBackCases=4,childBackCases=2,guiCases=5,guiExit=0),
 localUi=dict(result='receipts/local-ui-results.json',format=dict(log='receipts/format.log',exit='receipts/format.exit',actualExit=0),analyze=dict(log='receipts/analyze.log',exit='receipts/analyze.exit',actualExit=0),layout=dict(log='receipts/sync-layout.log',exit='receipts/sync-layout.exit',actualCases=7,actualExit=0),downloadButton=dict(log='receipts/download-circle.log',exit='receipts/download-circle.exit',actualCases=4,actualExit=0),qualification='These are actual 228 whole-file runs. Layout includes the real CameraPage with 30 mocked camera photos and scroll geometry; download button tests include explicit dark/white paint under conflicting themes and enabled/disabled states. They are widget evidence, not a connected physical camera GUI.'),
 infrastructureAttempts=dict(count=0,countedAsPass=False,qualification='No 227 or earlier infrastructure/test attempts are included in this 228 archive.'),
 qaRetry=dict(maxFreshDumps=3,validatesDumpSuccessMarker=True,validatesHierarchyXml=True,functionalLabelAssertionsChangedByArchiver=False),
 screenshots=dict(container='ui-screenshots.tar.xz',originalPngMembers=len(pngs),prefixes=['back227-','gui227-'],sourceDirectory='.tooling/next228/ui',qualification='The 228 helper intentionally retained old filename stems. These originals come only from next228 and are bound to source734aa3b/228 APK by fresh gate reports; no next227 file is included.',verification='Every decompressed PNG member is byte-compared to source; corresponding XML is copied byte-for-byte.'),
 mappings=dict(container='r8-mappings.tar.xz',members=2,verification='Both original mappings decompressed and byte-compared; original bytes/SHA listed separately per member in archive-manifest.json.'),
 rawHelperLiterals=dict(guiStdout='GUI227',selectionProofCaseLiteral=2,qualification='Raw helper/log/JSON labels are retained unchanged. Source/APK gate identity is 228; actual current selection/button whole-file count is 4 per local log+exit, rather than the inherited proof text 2.'),
 physicalCameraTested=False,connectedThenDisconnectedTransportProvenByThisGui=False,
 stopTransportQualification='This GUI archive does not claim physical burst/stop or a connected physical camera grid; unchanged Core/transport validation is bound elsewhere by the parent.',
 sourceSnapshot=dict(path='receipts/source.json',statusAtCapture=readj(DEST/'receipts/source.json').get('status'),androidAcceptedAtCapture=readj(DEST/'receipts/source.json').get('androidAcceptedForLocalTesting'),qualification='Unmodified source-frozen metadata captured before this archive run. Flags are preserved from that snapshot; later parent promotion may change the mutable source metadata and must not rewrite this raw original. Snapshot bytes, rather than later promoted bytes, are compared throughout archival.'),
 excluded=['APK payloads','classes trees','uncompressed mapping files','private HANDOFF','227 and earlier evidence/attempts','non-current UI snapshots'],
 packages=packages,sdkAdbGitExecutedByArchiver=False)
(DEST/'qualification.json').write_text(json.dumps(qualification,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for entry in entries:
 src=ROOT/entry['source'];data=SOURCE_SNAPSHOT if src==BASE/'source.json' else src.read_bytes();assert len(data)==entry['sourceBytes'] and sha(data)==entry['sourceSha256'],('source changed during archival',src)
artifacts=[]
for path in sorted(DEST.rglob('*')):
 if path.is_file() and path.name!='archive-manifest.json':
  data=path.read_bytes();artifacts.append(dict(path=(str(path.relative_to(DEST)) if path.is_relative_to(DEST) else '../'+str(path.relative_to(DEST.parent))).replace('\\','/'),bytes=len(data),sha256=sha(data)))
manifest=dict(schema=1,sourceCommit=EXPECTED,createdAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),archiveRoot=str(DEST.relative_to(ROOT)).replace('\\','/'),allSourceDestinationBytesAndShaVerified=True,originalFileCount=len(entries),directOriginalCopies=sum(x['member'] is None for x in entries),compressedOriginalMembers=sum(x['member'] is not None for x in entries),destinationFileCountIncludingManifest=len(artifacts)+1,destinationBytesExcludingManifest=sum(x['bytes'] for x in artifacts),originalBytes=sum(x['sourceBytes'] for x in entries),entries=entries,artifacts=artifacts)
(DEST/'archive-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:manifest[k] for k in ['allSourceDestinationBytesAndShaVerified','originalFileCount','directOriginalCopies','compressedOriginalMembers','destinationFileCountIncludingManifest','destinationBytesExcludingManifest','originalBytes']},indent=2))
print('PNG members='+str(len(pngs))+'; mappings=2; infra failed attempts=0; GUI cases=5; no APK/classes copied')
