from pathlib import Path
import os,subprocess,sys,json,shutil,hashlib
ROOT=Path(r'D:\dev\ai-project\nikon-camera');WORK=ROOT/'.tooling/lmb';SDK=ROOT/'.tooling/cross-platform187/flutter-sdk';OUT=WORK/'.tooling';APP=WORK/'cross-platform/app'
mode=sys.argv[1];abi='android-x64' if mode=='debug' else 'android-arm64'
models={
 'face_landmarks_detector.tflite':('c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5',2553590),
 'face_skin_multiclass.shuffle4.zlib':('9920fafc503c9090b3840c6fb433efc7eeb117bb00176b04034bd589c0e19bb0',13881786),
}
asset_root=WORK/'cross-platform/.build/portrait-assets'
identities=[]
for name,(expected,length) in models.items():
 data=(ROOT/'.tooling/lp231/app/src/main/assets/portrait'/name).read_bytes()
 assert len(data)==length and hashlib.sha256(data).hexdigest()==expected
 destination=asset_root/'portrait'/name;destination.parent.mkdir(parents=True,exist_ok=True)
 if not destination.exists() or destination.read_bytes()!=data:destination.write_bytes(data)
 identities.append({'name':name,'sha256':expected,'bytes':length})
(OUT/'portrait-assets.json').write_text(json.dumps({'models':identities,'originalAppSourceModified':False},indent=2)+'\n',encoding='utf8')
portrait_init=OUT/'portrait-assets.init.gradle'
portrait_init.write_text("gradle.beforeProject { project -> project.pluginManager.withPlugin('com.android.application') { if (project.path == ':app') { project.extensions.getByName('android').sourceSets.getByName('main').assets.srcDir('"+asset_root.as_posix()+"') } } }\n",encoding='utf8')
native=ROOT/'.tooling/lp231/cross-platform/.build/raw-android';target=WORK/'cross-platform/.build/raw-android'
if not target.exists():
 shutil.copytree(native,target)
 assert all(hashlib.sha256(p.read_bytes()).digest()==hashlib.sha256((target/p.relative_to(native)).read_bytes()).digest() for p in native.rglob('*') if p.is_file())
 (OUT/'native-reuse.json').write_text(json.dumps({'source':str(native),'sha256Verified':True,'reason':'231 native sources unchanged; only Dart menu layout and icons changed.'})+'\n',encoding='utf8')
android=APP/'android';(android/'local.properties').write_text('sdk.dir=D:/dev/Android/Sdk\nflutter.sdk='+SDK.as_posix()+'\nflutter.versionName=0.31.0-dev\nflutter.versionCode=232\n',encoding='utf8')
env=dict(os.environ,JAVA_HOME='D:/dev/Java/jdk-17.0.19',ANDROID_HOME='D:/dev/Android/Sdk',ANDROID_SDK_ROOT='D:/dev/Android/Sdk',FLUTTER_ROOT=str(SDK),PUB_CACHE=str(ROOT/'.tooling/cross-platform187/pub-cache'),HUEVIA_FLUTTER_MAVEN=str(ROOT/'.tooling/cross-platform187/flutter-maven'),CI='true',FLUTTER_SUPPRESS_ANALYTICS='true')
env['PATH']=env['JAVA_HOME']+'/bin'+os.pathsep+env['PATH']
with (OUT/('build-'+mode+'.log')).open('w',encoding='utf8') as log:
 p=subprocess.run([str(SDK/'bin/cache/dart-sdk/bin/dart.exe'),'--packages='+str(SDK/'packages/flutter_tools/.dart_tool/package_config.json'),str(WORK/'cross-platform/tool/android_plugins.dart'),str(APP),mode,str(SDK)],cwd=APP,env=env,stdout=log,stderr=subprocess.STDOUT)
 if p.returncode:raise SystemExit(p.returncode)
 tasks=[':app:assembleDebug',':app:assembleDebugAndroidTest'] if mode=='debug' else [':app:assembleRelease']
 command=[str(android/'gradlew.bat'),*tasks,'--no-daemon','--offline','--max-workers=2','-Ptarget-platform='+abi,'-Dorg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=768m','--init-script',str(ROOT/'.tooling/cross-platform187/maven-proxy.init.gradle'),'--init-script',str(portrait_init)]
 if mode=='debug':command+=['-Ptarget='+str(APP/'integration_test/light_menu_b_device_test.dart')]
 p=subprocess.run(command,cwd=android,env=env,stdout=log,stderr=subprocess.STDOUT)
(OUT/('build-'+mode+'-result.json')).write_text(json.dumps({'exitCode':p.returncode,'versionCode':232,'abi':abi})+'\n',encoding='utf8');print('BUILD',mode,'EXIT',p.returncode,flush=True);raise SystemExit(p.returncode)
