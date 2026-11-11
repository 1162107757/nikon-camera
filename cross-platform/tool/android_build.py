"""Build only the coinstalled migration app without changing global SDK settings."""
from pathlib import Path
import argparse,os,re,subprocess,sys
from verify_android_apk import verify

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--sdk',required=True,type=Path)
parser.add_argument('--java',required=True,type=Path)
parser.add_argument('--offline',action='store_true')
parser.add_argument('--mode',choices=['debug','release'],default='debug')
parser.add_argument('--target',type=Path)
parser.add_argument('--abi',choices=['android-x64','android-arm64','android-arm'],default='android-x64')
options=parser.parse_args()
if options.mode=='release' and options.target:parser.error('Integration test targets require debug mode')
sdk=options.sdk.resolve();java=options.java.resolve()
if not (sdk/'platform-tools/adb.exe').is_file() or not (java/'bin/java.exe').is_file():
    raise SystemExit('A complete Windows Android SDK and JDK are required')
flutter=ROOT/'.tooling/cross-platform187/flutter-sdk';android=ROOT/'cross-platform/app/android'
local=android/'local.properties';text=local.read_text(encoding='utf-8') if local.exists() else ''
version=re.search(r'(?m)^version:\s*([^+\s]+)\+(\d+)\s*$',(android.parent/'pubspec.yaml').read_text(encoding='utf-8'))
if not version:raise SystemExit('The app version must include its build number')
for name,value in [('sdk.dir',sdk.as_posix()),('flutter.sdk',flutter.as_posix()),('flutter.versionName',version[1]),('flutter.versionCode',version[2])]:
    pattern=r'(?m)^'+re.escape(name)+r'=.*$'
    if re.search(pattern,text):text=re.sub(pattern,lambda _:name+'='+value,text)
    else:text+='\n'+name+'='+value+'\n'
local.write_text(text,encoding='utf-8')
env=dict(os.environ,JAVA_HOME=str(java),ANDROID_HOME=str(sdk),ANDROID_SDK_ROOT=str(sdk),
    FLUTTER_ROOT=str(flutter),PUB_CACHE=str(ROOT/'.tooling/cross-platform187/pub-cache'),
    HUEVIA_FLUTTER_MAVEN=str(ROOT/'.tooling/cross-platform187/flutter-maven'),
    CI='true',FLUTTER_SUPPRESS_ANALYTICS='true')
env['PATH']=str(java/'bin')+os.pathsep+env['PATH']
tasks=[':app:assembleDebug',':app:assembleDebugAndroidTest'] if options.mode=='debug' else [':app:assembleRelease']
command=[str(android/'gradlew.bat'),*tasks,'--no-daemon','--max-workers=2','-Ptarget-platform='+options.abi]
if options.target:
    target=options.target.resolve()
    if not target.is_relative_to(ROOT/'cross-platform/app') or not target.is_file():raise SystemExit('Test target must be inside the shared app')
    command+=['-Ptarget='+str(target)]
init=ROOT/'.tooling/cross-platform187/maven-proxy.init.gradle'
if init.is_file():command+=['--init-script',str(init)]
if options.offline:command+=['--offline']
log=ROOT/'.tooling/cross-platform187/android-proxy-build.log'
with log.open('w',encoding='utf-8') as output:
    native=subprocess.run([sys.executable,str(ROOT/'cross-platform/tool/raw_android.py'),'--sdk',str(sdk),'--abi',options.abi],cwd=ROOT,env=env,stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT)
    if native.returncode:raise SystemExit('Android RAW bridge preparation failed; see '+str(log))
    generator=[str(flutter/'bin/cache/dart-sdk/bin/dart.exe'),
        '--packages='+str(flutter/'packages/flutter_tools/.dart_tool/package_config.json'),
        str(ROOT/'cross-platform/tool/android_plugins.dart'),str(android.parent),options.mode,str(flutter)]
    preparation=subprocess.run(generator,cwd=android.parent,env=env,stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT)
    if preparation.returncode:raise SystemExit('Android plugin generation failed; see '+str(log))
    result=subprocess.run(command,cwd=android,env=env,stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT)
print('Android build exit '+str(result.returncode)+'; log: '+str(log))
if result.returncode==0:
    artifact=ROOT/'cross-platform/app/build/app/outputs/apk'/options.mode/('app-'+options.mode+'.apk')
    evidence=verify(artifact,options.abi,options.mode)
    print('Verified '+evidence['abi']+' '+options.mode+' APK: '+str(evidence['bytes'])+' bytes; SHA-256 '+evidence['sha256'])
raise SystemExit(result.returncode)
