from pathlib import Path
import hashlib,json,tarfile,datetime,re
ROOT=Path(__file__).resolve().parents[5]
BASE=ROOT/'.tooling/next227'
DEST=Path(__file__).resolve().parent
EXPECTED='ac5a7ef4ceca2d1b180d6321f683f90241f1234f'
sha=lambda b:hashlib.sha256(b).hexdigest()
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
gui=readj(BASE/'live-panel-gui-result.json')
assert gui['exit']==0 and gui['sourceCommit']==EXPECTED and len(gui['cases'])==5 and all(x['exit']==0 for x in gui['cases'])
assert readj(BASE/'android-release-result.json')['sourceCommit']==EXPECTED and readj(BASE/'android-release-result.json')['exit']==0
assert readj(BASE/'android-acceptance-pipeline.json')==dict(verify_android=0,verify_photos=0,run_release_runtime=0,check_back_navigation=0)
r8=readj(BASE/'release-runtime-result.json');back=readj(BASE/'back-navigation-result.json')
assert r8['sourceCommit']==EXPECTED and r8['exit']==0 and r8['accepted'] and r8['checksPassed']>=123 and r8['apkSha256']==gui['apkSha256']
assert back['sourceCommit']==EXPECTED and back['exit']==0 and len(back['rootCases'])==4 and all(x['sameActivityAndProcess'] for x in back['rootCases']) and back['connectionPageBackReturnsToSync'] and back['queueBackReturnsToSync']
photos=readj(ROOT/'docs/migration/validation/features-227/preset-preview-assets.json')
assert photos['sourceCommit']==EXPECTED and photos['imageCount']==10 and photos['allTenPreservedByteForByte']
newqa=(BASE/'qa_ui.py').read_text(encoding='utf-8-sig')
assert sha((BASE/'qa_ui.py').read_bytes())=='f08c230135199edfc191e1dbcd39998c5b72fa92c12b82a2a5c03467b4cecf98', 'Previously verified QA helper changed'
assert 'range(3)' in newqa and "E.fromstring(raw).tag == 'hierarchy'" in newqa and "b'dumped to:'" in newqa
proof=readj(BASE/'privacy-test-only-source-proof.json')
assert proof['sourceCommit']==EXPECTED and proof['allProductInputsUnchanged'] and proof['testExit']==0 and proof['wholePrivacyFilePassed']==2
assert sha((ROOT/'cross-platform/app/test/camera_live_panel_test.dart').read_bytes())==proof['privacyTestFileSha256']
for name,count in [('camera_selection_download_test.dart.log',2),('capsule_switch_test.dart.log',3)]:
 text=(BASE/name).read_text(encoding='utf-8',errors='replace')
 assert re.search(r'\+'+str(count)+r': All tests passed!',text) and 'exiting with code 0' in text
entries=[]
def record(src,dst,member=None):
 data=src.read_bytes()
 if member is None:out=(DEST/dst).read_bytes()
 else:
  with tarfile.open(DEST/dst,'r:xz') as archive:out=archive.extractfile(member).read()
 assert data==out,(src,dst,member)
 entries.append(dict(source=str(src.relative_to(ROOT)).replace('\\','/'),destination=dst,member=member,sourceBytes=len(data),destinationBytes=len(out),sourceSha256=sha(data),destinationSha256=sha(out),byteForByteEqual=True))
def copy(src,dst):
 path=DEST/dst;path.parent.mkdir(parents=True,exist_ok=True);data=src.read_bytes()
 if path.exists():assert path.read_bytes()==data,('existing different artifact',path)
 else:path.write_bytes(data)
 record(src,dst)
receipts=['source.json','android-release-result.json','android-arm64-release.log','android-x64-release.log','arm64-gradle.log','x64-gradle.log','instrumentation-build.log','instrumentation-runner-build.log','instrumentation-runner-build.exit','arm64-apksigner.bat-final.log','x64-apksigner.bat-final.log','arm64-zipalign.exe-final.log','x64-zipalign.exe-final.log','verify_android-pipeline.log','verify_photos-pipeline.log','release-runtime.log','release-runtime-result.json','release-runtime-mapping.json','run_release_runtime-pipeline.log','check_back_navigation-pipeline.log','back-navigation-result.json','live-panel-gui.log','live-panel-gui-result.json','android-acceptance-pipeline.json','android-acceptance-launcher.log','build-launcher.log','preservation.log','stop-independent-review.json','helper-review.json','delivery-helper-clone.json','back-final.exit','back-final-launcher.log','camera_selection_download_test.dart.log','capsule_switch_test.dart.log','privacy-test-only-source-proof.json','privacy-final-results.json']
for name in receipts:copy(BASE/name,'receipts/'+name)
for name in ['android-signing-alignment.json','preset-preview-assets.json']:copy(ROOT/'docs/migration/validation/features-227'/name,'receipts/'+name)
for name in ['build_releases.py','verify_android.py','verify_photos.py','run_release_runtime.py','check_back_navigation.py','check_live_panel_gui.py','qa_ui.py','android_acceptance_pipeline.py','run_back_final.py']:copy(BASE/name,'helpers/next226/'+name)
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
pack('ui-screenshots.tar.xz',pngs)
mappings=[(BASE/(abi+'-mapping.txt'),'mappings/'+abi+'-mapping.txt') for abi in ['arm64','x64']]
assert sha(mappings[1][0].read_bytes())==r8['mappingSha256']
pack('r8-mappings.tar.xz',mappings)
signing=readj(ROOT/'docs/migration/validation/features-227/android-signing-alignment.json')
packages=[]
for value in signing:
 path=BASE/'package-candidates'/('huevia-0.31.0-dev-227-android-'+value['abi']+'.apk')
 data=path.read_bytes();assert len(data)==value['bytes'] and sha(data)==value['sha256']
 assert value['apksignerVerified'] and value['zipalign16KiBVerified'] and value['allLoadSegments16KiBVerified']
 packages.append(dict(path=str(path.relative_to(ROOT)).replace('\\','/'),bytes=len(data),sha256=sha(data),copied=False))
qualification=dict(
 schema=1,sourceCommit=EXPECTED,build=227,published=False,
 scope='Fresh Android sourceac5a7ef build/gate/runtime/UI receipts; no package promotion or physical-camera transport acceptance.',
 gateSummary=dict(androidBuildExit=0,verifyAndroidExit=0,presetPhotoExit=0,r8Checks=123,rootBackCases=4,childBackCases=2,guiCases=5,guiExit=0),
 initialInfrastructureAttempt=dict(count=0,paths=[],countedAsPass=False,reason='No previous-source infrastructure attempts or their payloads are included in this fresh source archive.'),
 qaRetry=dict(maxFreshDumps=3,validatesDumpSuccessMarker=True,validatesHierarchyXml=True,sameQaHelperAsPreviousVerifiedArchive=True,functionalLabelAssertionsChanged=False,qualification='Current QA helper SHA matches the previously verified helper; fresh dump success and hierarchy checks remain bounded to three attempts. No prior failure attempt is read or copied by this archive.'),
 backFinalScreen=dict(raw=back['finalScreen'],rawModified=False,observedHeader='预设',snapshot='ui/back227-resumed-presets.xml',note='Current report and header use 预设. Four root same-process/activity cases plus two child-return assertions pass after the infrastructure retry.'),
 screenshots=dict(container='ui-screenshots.tar.xz',originalPngMembers=len(pngs),prefixes=['back227-','gui227-'],verification='Every decompressed PNG member is byte-compared to its source; corresponding XML is copied byte-for-byte.'),
 mappings=dict(container='r8-mappings.tar.xz',members=2,verification='Both original mappings decompressed and byte-compared; original bytes/SHA are separately listed per member in archive-manifest.json.'),
 widgetEvidence=dict(selectionCircleAndLongPress=dict(path='receipts/camera_selection_download_test.dart.log',cases=2,exit=0),capsuleAnimation=dict(path='receipts/capsule_switch_test.dart.log',cases=3,exit=0),qualification='These supporting widget success logs were retained from the previous frozen source. The current privacy-test-only proof confirms all product inputs unchanged; they are not claimed as freshly rerun AC device tests. Existing aggregate local evidence remains in ../shared.'),
 physicalCameraTested=False,connectedThenDisconnectedTransportProvenByThisGui=False,
 stopTransportQualification='Ordinary-stop transport behavior is covered by held-transaction Dart regressions and SharedCore same-session JPEG/NEF tests in the shared/core archives; no physical burst/stop claim is made for this disconnected emulator GUI.',
 privacyTestOnlyProof=dict(path='receipts/privacy-test-only-source-proof.json',qualification='Only the privacy widget fixture changed from BF to AC; source hash and its actual whole-file 2/0 result are verified. Raw result JSON is also copied.'),
 stopReview=dict(path='receipts/stop-independent-review.json',qualification='Original static review preserved unchanged; its earlier pre-SDK state is not a runtime pass receipt.'),
 sourceSnapshot=dict(path='receipts/source.json',qualification='Unmodified source-frozen, before-promotion metadata snapshot. acceptedfalse/pending flags are retained; parent later promotion metadata does not rewrite this raw original.'),
 excluded=['APK payloads','classes trees','uncompressed mapping files','private HANDOFF.json','226 evidence','other WIP/old UI snapshots','prior-source infrastructure attempts'],
 packages=packages,sdkAdbGitExecutedByArchiver=False)

(DEST/'qualification.json').write_text(json.dumps(qualification,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for entry in entries:
 src=ROOT/entry['source'];assert len(src.read_bytes())==entry['sourceBytes'] and sha(src.read_bytes())==entry['sourceSha256'],('source changed during archival',src)
artifacts=[]
for path in sorted(DEST.rglob('*')):
 if path.is_file() and path.name!='archive-manifest.json':
  data=path.read_bytes();artifacts.append(dict(path=(str(path.relative_to(DEST)) if path.is_relative_to(DEST) else '../'+str(path.relative_to(DEST.parent))).replace('\\','/'),bytes=len(data),sha256=sha(data)))
manifest=dict(schema=1,sourceCommit=EXPECTED,createdAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),archiveRoot=str(DEST.relative_to(ROOT)).replace('\\','/'),allSourceDestinationBytesAndShaVerified=True,originalFileCount=len(entries),directOriginalCopies=sum(x['member'] is None for x in entries),compressedOriginalMembers=sum(x['member'] is not None for x in entries),destinationFileCountIncludingManifest=len(artifacts)+1,destinationBytesExcludingManifest=sum(x['bytes'] for x in artifacts),originalBytes=sum(x['sourceBytes'] for x in entries),entries=entries,artifacts=artifacts)
(DEST/'archive-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:manifest[k] for k in ['allSourceDestinationBytesAndShaVerified','originalFileCount','directOriginalCopies','compressedOriginalMembers','destinationFileCountIncludingManifest','destinationBytesExcludingManifest','originalBytes']},indent=2))
print('PNG members='+str(len(pngs))+'; mappings=2; infra failed attempts=0; GUI cases=5; no APK/classes copied')
