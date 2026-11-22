"""Run the production Android USB wire state machine against bounded host USB stubs."""
from pathlib import Path
import argparse,os,subprocess
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'cross-platform/.build/usb-session'
OUT.mkdir(parents=True,exist_ok=True)
parser=argparse.ArgumentParser();parser.add_argument('--java',type=Path,default=Path('D:/dev/Java/jdk-17.0.19'));options=parser.parse_args()
java=options.java/'bin'
native=ROOT/'cross-platform/app/android/app/src/main/java/cc/huevia/sharedapp'
sources=list((ROOT/'cross-platform/native/tests/usb-session-stubs').rglob('*.java'))+[ROOT/'cross-platform/native/tests/NativeUsbSessionBoundaryTest.java',native/'NativeUsbSlots.java',native/'NativeUsbPhotoClient.java']
classpath=ROOT/'cross-platform/.build/core-jvm/classes'
args=['--release','11','-encoding','UTF-8','-cp',str(classpath),'-d',str(OUT)]+[str(p) for p in sources]
result=subprocess.run([str(java/('javac.exe' if os.name=='nt' else 'javac')),'-J-Dfile.encoding=UTF-8','-J-Duser.language=en','-J-Duser.country=US',*args],cwd=ROOT,capture_output=True)
if result.returncode:print(result.stderr.decode('utf-8',errors='replace'));raise SystemExit(result.returncode)
result=subprocess.run([str(java/('java.exe' if os.name=='nt' else 'java')),'-Xmx192m','-cp',str(OUT)+os.pathsep+str(classpath),'cc.huevia.sharedapp.NativeUsbSessionBoundaryTest'],cwd=ROOT,capture_output=True)
print((result.stdout+result.stderr).decode('utf-8',errors='replace'))
raise SystemExit(result.returncode)
