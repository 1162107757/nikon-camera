from pathlib import Path
import subprocess,json,shutil,os
r=Path(__file__).resolve().parents[2];stage=r/'.tooling/next227/package-candidates';stage.mkdir(exist_ok=True)
expected=json.loads((r/'.tooling/next227/source.json').read_text(encoding='utf-8'))['sourceCommit']
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip()==expected
subprocess.run(['git','diff','--exit-code','--','cross-platform/app'],cwd=r,check=True)
(r/'.tooling/next227/android-release-result.json').unlink(missing_ok=True)
with (r/'.tooling/next227/instrumentation-build.log').open('w',encoding='utf-8') as out:
 p=subprocess.run(['python','cross-platform/tool/android_build.py','--sdk','D:/dev/Android/Sdk','--java','D:/dev/Java/jdk-17.0.19','--offline','--mode','debug','--abi','android-x64'],cwd=r,stdout=out,stderr=subprocess.STDOUT)
if p.returncode:
 (r/'.tooling/next227/android-release-result.json').write_text(json.dumps({'exit':p.returncode,'phase':'instrumentation','sourceCommit':expected}));raise SystemExit(p.returncode)
env=os.environ.copy()
env.update(JAVA_HOME='D:/dev/Java/jdk-17.0.19',ANDROID_HOME='D:/dev/Android/Sdk',ANDROID_SDK_ROOT='D:/dev/Android/Sdk',FLUTTER_ROOT=str(r/'.tooling/cross-platform187/flutter-sdk'),PUB_CACHE=str(r/'.tooling/cross-platform187/pub-cache'),HUEVIA_FLUTTER_MAVEN=str(r/'.tooling/cross-platform187/flutter-maven'),CI='true',FLUTTER_SUPPRESS_ANALYTICS='true')
env['PATH']='D:/dev/Java/jdk-17.0.19/bin;'+str(r/'.tooling/cross-platform187/flutter-sdk/bin')+';'+env.get('PATH','')
with (r/'.tooling/next227/instrumentation-runner-build.log').open('w',encoding='utf-8') as out:
 p=subprocess.run([str(r/'cross-platform/app/android/gradlew.bat'),':app:assembleDebugAndroidTest','--no-daemon','--max-workers=2','-Ptarget-platform=android-x64','--offline','--init-script',str(r/'.tooling/cross-platform187/maven-proxy.init.gradle'),'--init-script',str(r/'.tooling/next227/release-runtime.init.gradle')],cwd=r/'cross-platform/app/android',env=env,stdout=out,stderr=subprocess.STDOUT)
(r/'.tooling/next227/instrumentation-runner-build.exit').write_text(str(p.returncode))
if p.returncode:
 (r/'.tooling/next227/android-release-result.json').write_text(json.dumps({'exit':p.returncode,'phase':'instrumentation-runner','sourceCommit':expected}));raise SystemExit(p.returncode)
for abi in ['android-arm64','android-x64']:
 log=r/f'.tooling/next227/{abi}-release.log'
 with log.open('w',encoding='utf-8') as out:
  p=subprocess.run(['python','cross-platform/tool/android_build.py','--sdk','D:/dev/Android/Sdk','--java','D:/dev/Java/jdk-17.0.19','--offline','--mode','release','--abi',abi],cwd=r,stdout=out,stderr=subprocess.STDOUT)
 if p.returncode:
  (r/'.tooling/next227/android-release-result.json').write_text(json.dumps({'exit':p.returncode,'abi':abi,'sourceCommit':expected}));raise SystemExit(p.returncode)
 suffix='arm64' if abi=='android-arm64' else 'x64'
 shutil.copy2(r/'cross-platform/app/build/app/outputs/apk/release/app-release.apk',stage/f'huevia-0.31.0-dev-227-android-{suffix}.apk')
 for source,name in [('cross-platform/app/build/app/outputs/mapping/release/mapping.txt',f'{suffix}-mapping.txt'),('.tooling/cross-platform187/android-proxy-build.log',f'{suffix}-gradle.log')]:shutil.copy2(r/source,r/'.tooling/next227'/name)
(r/'.tooling/next227/android-release-result.json').write_text(json.dumps({'exit':0,'sourceCommit':expected,'abis':['android-arm64','android-x64']}))
