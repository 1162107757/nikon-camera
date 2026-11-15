from pathlib import Path
import hashlib,json,tarfile,datetime
ROOT=Path(__file__).resolve().parents[5]
BASE=ROOT/'.tooling/next226'
DEST=Path(__file__).resolve().parent
EXPECTED='61423d6b144229e3113edd54da6597177efc0555'
sha=lambda b:hashlib.sha256(b).hexdigest()
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
gui=readj(BASE/'live-panel-gui-result.json')
assert gui['exit']==0 and gui['sourceCommit']==EXPECTED and len(gui['cases'])==3 and all(x['exit']==0 for x in gui['cases'])
assert readj(BASE/'android-release-result.json')['sourceCommit']==EXPECTED and readj(BASE/'android-release-result.json')['exit']==0
assert readj(BASE/'android-acceptance-pipeline.json')==dict(verify_android=0,verify_photos=0,run_release_runtime=0,check_back_navigation=0)
r8=readj(BASE/'release-runtime-result.json');back=readj(BASE/'back-navigation-result.json')
assert r8['sourceCommit']==EXPECTED and r8['exit']==0 and r8['accepted'] and r8['checksPassed']>=123 and r8['apkSha256']==gui['apkSha256']
assert back['sourceCommit']==EXPECTED and back['exit']==0 and len(back['rootCases'])==4 and all(x['sameActivityAndProcess'] for x in back['rootCases']) and back['connectionPageBackReturnsToSync'] and back['queueBackReturnsToSync']
photos=readj(ROOT/'docs/migration/validation/features-226/preset-preview-assets.json')
assert photos['sourceCommit']==EXPECTED and photos['imageCount']==10 and photos['allTenPreservedByteForByte']
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
receipts=['source.json','android-release-result.json','android-arm64-release.log','android-x64-release.log','arm64-gradle.log','x64-gradle.log','instrumentation-build.log','instrumentation-runner-build.log','instrumentation-runner-build.exit','arm64-apksigner.bat-final.log','x64-apksigner.bat-final.log','arm64-zipalign.exe-final.log','x64-zipalign.exe-final.log','verify_android-pipeline.log','verify_photos-pipeline.log','release-runtime.log','release-runtime-result.json','release-runtime-mapping.json','run_release_runtime-pipeline.log','check_back_navigation-pipeline.log','back-navigation-result.json','live-panel-gui.log','live-panel-gui-result.json','android-acceptance-pipeline.json','android-acceptance-launcher.log','build-launcher.log','preservation-final-source.log','reconnect-independent-review.json','gui-probe-initial-expectation.json']
for name in receipts:copy(BASE/name,'receipts/'+name)
for name in ['android-signing-alignment.json','preset-preview-assets.json']:copy(ROOT/'docs/migration/validation/features-226'/name,'receipts/'+name)
for name in ['build_releases.py','verify_android.py','verify_photos.py','run_release_runtime.py','check_back_navigation.py','check_live_panel_gui.py','qa_ui.py','android_acceptance_pipeline.py']:copy(BASE/name,'helpers/next226/'+name)
for name in ['android_build.py','verify_android_apk.py','raw_android.py']:copy(ROOT/'cross-platform/tool'/name,'helpers/cross-platform/tool/'+name)
copy(BASE/'release-runtime.init.gradle','runtime/release-runtime.init.gradle')
copy(ROOT/'.tooling/cross-platform187/maven-proxy.init.gradle','runtime/maven-proxy.init.gradle')
for src,dst in [('cross-platform/app/android/app/src/androidTest/java/cc/huevia/sharedapp/ReleaseRuntimeInstrumentation.java','runtime/ReleaseRuntimeInstrumentation.java'),('cross-platform/app/android/app/build.gradle.kts','runtime/app-build.gradle.kts'),('cross-platform/app/android/build.gradle.kts','runtime/root-build.gradle.kts'),('cross-platform/app/android/settings.gradle.kts','runtime/settings.gradle.kts'),('cross-platform/app/android/gradle.properties','runtime/gradle.properties'),('cross-platform/app/android/gradlew.bat','runtime/gradlew.bat'),('cross-platform/app/android/gradle/wrapper/gradle-wrapper.properties','runtime/gradle-wrapper.properties')]:copy(ROOT/src,dst)
pngs=[]
for src in sorted((BASE/'ui').iterdir()):
 if src.suffix=='.xml':copy(src,'ui/'+src.name)
 elif src.suffix=='.png':pngs.append((src,'ui/'+src.name))
failed=['61423d6-gui-old-label','61423d6-gui-existing-raw-choice']
for attempt in failed:
 q=readj(BASE/'attempts'/attempt/'qualification.json');assert q['exit']==1 and q['actualProductFailureEstablished']==False
 for src in sorted((BASE/'attempts'/attempt).iterdir()):
  dst='attempts/'+attempt+'/'+src.name
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
signing=readj(ROOT/'docs/migration/validation/features-226/android-signing-alignment.json')
packages=[]
for value in signing:
 path=BASE/'package-candidates'/('huevia-0.31.0-dev-226-android-'+value['abi']+'.apk')
 data=path.read_bytes();assert len(data)==value['bytes'] and sha(data)==value['sha256']
 assert value['apksignerVerified'] and value['zipalign16KiBVerified'] and value['allLoadSegments16KiBVerified']
 packages.append(dict(path=str(path.relative_to(ROOT)).replace('\\','/'),bytes=len(data),sha256=sha(data),copied=False))
qualification=dict(schema=1,sourceCommit=EXPECTED,build=226,published=False,scope='Original Android build/gate/runtime/UI receipts for source614; not package promotion or physical-camera transport acceptance.',gateSummary=dict(androidBuildExit=0,verifyAndroidExit=0,presetPhotoExit=0,r8Checks=123,rootBackCases=4,childBackCases=2,guiCases=3,guiExit=0),failedGuiAttempts=dict(count=2,countedAsPass=False,paths=['attempts/'+x for x in failed],reason='Raw script/log/qualification preserved. First used a retired connection label, second did not initialize the existing JPEG/RAW selection. Neither establishes product failure.'),backFinalScreen=dict(raw=back['finalScreen'],rawModified=False,observedHeader='预设',snapshot='ui/back226-resumed-presets.xml',note='The old helper finalScreen literal is 我的预设; the captured root header/tab is 预设 and the page also contains a 我的预设 filter. This naming discrepancy does not change four root same-process/activity cases or two child-return assertions.'),screenshots=dict(container='ui-screenshots.tar.xz',originalPngMembers=len(pngs),supportingProbePrefix='ui/live226-',supportingProbesCountedAsGate=False,verification='Every member decompressed and byte-compared to the original PNG; XML copied byte-for-byte.'),mappings=dict(container='r8-mappings.tar.xz',members=2,verification='Both original mappings decompressed and compared byte-for-byte; original bytes/SHA listed separately per member in archive-manifest.json.'),reconnectReview=dict(path='receipts/reconnect-independent-review.json',qualification='Original independent review is retained unchanged. It records the former base source and bounded owner-reply fix pending parent validation at that time; it is not a runtime pass receipt.'),sourceSnapshot=dict(path='receipts/source.json',qualification='Raw source metadata copied at archive time; its pending/platform acceptance flags are preserved without upgrading them. Parent owns final package promotion.'),excluded=['APK payloads','classes trees','uncompressed mapping files','old-source 0bf8da5 attempt tree'],packages=packages,sdkAdbGitExecutedByArchiver=False)
(DEST/'qualification.json').write_text(json.dumps(qualification,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for entry in entries:
 src=ROOT/entry['source'];assert len(src.read_bytes())==entry['sourceBytes'] and sha(src.read_bytes())==entry['sourceSha256'],('source changed during archival',src)
artifacts=[]
for path in sorted(DEST.rglob('*')):
 if path.is_file() and path.name!='archive-manifest.json':
  data=path.read_bytes();artifacts.append(dict(path=str(path.relative_to(DEST)).replace('\\','/'),bytes=len(data),sha256=sha(data)))
manifest=dict(schema=1,sourceCommit=EXPECTED,createdAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),archiveRoot=str(DEST.relative_to(ROOT)).replace('\\','/'),allSourceDestinationBytesAndShaVerified=True,originalFileCount=len(entries),directOriginalCopies=sum(x['member'] is None for x in entries),compressedOriginalMembers=sum(x['member'] is not None for x in entries),destinationFileCountIncludingManifest=len(artifacts)+1,destinationBytesExcludingManifest=sum(x['bytes'] for x in artifacts),originalBytes=sum(x['sourceBytes'] for x in entries),entries=entries,artifacts=artifacts)
(DEST/'archive-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:manifest[k] for k in ['allSourceDestinationBytesAndShaVerified','originalFileCount','directOriginalCopies','compressedOriginalMembers','destinationFileCountIncludingManifest','destinationBytesExcludingManifest','originalBytes']},indent=2))
print('PNG members='+str(len(pngs))+'; mappings=2; failed attempts=2; GUI cases=3; no APK/classes copied')
