from pathlib import Path
import subprocess,os,zipfile
root=Path(__file__).resolve().parent;sdk=Path('D:/dev/Android/Sdk');bt=sdk/'build-tools/36.1.0';jar=sdk/'platforms/android-35/android.jar'
env=dict(os.environ,JAVA_HOME='D:/dev/Java/jdk-17.0.19',JAVA_TOOL_OPTIONS='-Xms16m -Xmx128m -XX:+UseSerialGC')
classes=root/'classes';classes.mkdir(exist_ok=True);dex=root/'dex';dex.mkdir(exist_ok=True)
def run(args):subprocess.run([str(a) for a in args],cwd=root,env=env,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
run(['D:/dev/Java/jdk-17.0.19/bin/javac.exe','--release','8','-cp',jar,'-d',classes,root/'ShareReceiver.java'])
run([bt/'d8.bat','--lib',jar,'--output',dex,*classes.rglob('*.class')])
run([bt/'aapt2.exe','link','-I',jar,'--manifest',root/'AndroidManifest.xml','-o',root/'unsigned.apk'])
with zipfile.ZipFile(root/'unsigned.apk','a',zipfile.ZIP_DEFLATED) as z:z.write(dex/'classes.dex','classes.dex')
run([bt/'zipalign.exe','-f','4',root/'unsigned.apk',root/'aligned.apk'])
run([bt/'apksigner.bat','sign','--ks','C:/Users/11621/.android/debug.keystore','--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--key-pass','pass:android','--out',root/'share-qa.apk',root/'aligned.apk'])
print('Built local-only QA receiver; no network permission; '+str((root/'share-qa.apk').stat().st_size)+' bytes')
