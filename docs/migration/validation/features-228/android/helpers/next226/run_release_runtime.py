from pathlib import Path
import subprocess,json,re,hashlib
r=Path(__file__).resolve().parents[2];base=r/'.tooling/next228';mapping=base/'x64-mapping.txt'
source=json.loads((base/'source.json').read_text(encoding='utf-8'))['sourceCommit']
build=json.loads((base/'android-release-result.json').read_text(encoding='utf-8'))
assert build['exit']==0 and build['sourceCommit']==source
apk=r/'.tooling/next228/package-candidates/huevia-0.31.0-dev-228-android-x64.apk'
test_apk=r/'cross-platform/app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk'
provenance={'sourceCommit':source,'apkSha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'instrumentationApkSha256':hashlib.sha256(test_apk.read_bytes()).hexdigest()}
s=mapping.read_text(encoding='utf-8')
def block(name):
 start=s.index(name+' -> ');tail=s[start:].splitlines()[1:];out=[]
 for line in tail:
  if line and not line.startswith((' ','#')):break
  out.append(line)
 return '\n'.join(out)
def field(name):
 matches=re.findall(r'^    [^\n]+ '+re.escape(name)+r' -> (\w+)$',block('cc.huevia.sharedapp.MainActivity'),re.M)
 assert len(matches)==1,(name,matches)
 return matches[0]
methods=set(re.findall(r'java.lang.String request\(java.lang.String,java.lang.String,java.util.function.BooleanSupplier,java.util.function.DoubleConsumer\)[^\n]* -> (\w+)',block('cc.huevia.sharedapp.NativeMedia')))
assert len(methods)==1,methods
fields={'mediaField':field('media'),'mediaMethod':methods.pop(),'workerField':field('worker'),'mappingSha256':hashlib.sha256(mapping.read_bytes()).hexdigest()}
task_classes=re.findall(r'^cc\.huevia\.sharedapp\.NativeTaskCancellation -> ([^:]+):$',s,re.M)
assert len(task_classes)==1,task_classes
fields['taskClass']=task_classes[0]
(base/'release-runtime-mapping.json').write_text(json.dumps(fields,indent=2),encoding='utf-8')
cmd=[r'D:/dev/Android/Sdk/platform-tools/adb.exe','-s','emulator-5584'];instrument=['shell','am','instrument','-r','-w']
for name in ['mediaField','mediaMethod','workerField','taskClass']:instrument+=['-e',name,fields[name]]
instrument+=['cc.huevia.next.test/cc.huevia.sharedapp.ReleaseRuntimeInstrumentation']
with (base/'release-runtime.log').open('w',encoding='utf-8') as out:
 for args in [['install','-r','--no-streaming',str(r/'.tooling/next228/package-candidates/huevia-0.31.0-dev-228-android-x64.apk')],['install','-r','--no-streaming',str(r/'cross-platform/app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk')],instrument]:
  result=subprocess.run(cmd+args,cwd=r,stdout=out,stderr=subprocess.STDOUT)
  if result.returncode:break
log=(base/'release-runtime.log').read_text(encoding='utf-8',errors='replace')
passed=re.search(r'PASS (\d+) R8 release runtime checks',log)
checks=int(passed[1]) if passed else 0
accepted=result.returncode==0 and checks>=123 and 'INSTRUMENTATION_CODE: -1' in log
(base/'release-runtime-result.json').write_text(json.dumps({'exit':result.returncode,'accepted':accepted,'checksPassed':checks,'minimumChecks':123,**fields,**provenance},indent=2))
if not accepted:raise SystemExit(1)
