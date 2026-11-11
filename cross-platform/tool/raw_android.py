"""Stage original JNI libraries and rebuild only the guarded heap-based RAW bridge."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess
import raw_sources

ROOT=raw_sources.ROOT
parser=argparse.ArgumentParser();parser.add_argument('--sdk',type=Path,required=True)
parser.add_argument('--abi',choices=['android-arm','android-arm64','android-x64'],required=True)
options=parser.parse_args()
abi,triple={'android-arm':('armeabi-v7a','armv7a-linux-androideabi'),'android-arm64':('arm64-v8a','aarch64-linux-android'),'android-x64':('x86_64','x86_64-linux-android')}[options.abi]
ndk=options.sdk/'ndk/28.2.13676358';tool=ndk/'toolchains/llvm/prebuilt/windows-x86_64'
compiler=tool/'bin/clang++.exe'
if not compiler.is_file():raise SystemExit('The pinned Android NDK 28.2.13676358 is required')
source=Path(json.loads((ROOT/'cross-platform/.build/raw-apple/sources.json').read_text())['root'])
work=ROOT/'cross-platform/.build/raw-android';work.mkdir(parents=True,exist_ok=True)
original=ROOT/'app/src/main/cpp/huevia_raw.cpp';text=original.read_text(encoding='utf-8-sig')
before='LibRaw raw(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);'
if text.count(before)!=3:raise SystemExit('RAW JNI allocation adapter requires review')
adapted=text.replace(before,'auto storage=std::make_unique<LibRaw>(LIBRAW_OPTIONS_NO_DATAERR_CALLBACK);LibRaw& raw=*storage;')
bridge=work/'huevia_raw.cpp'
if not bridge.exists() or bridge.read_bytes()!=adapted.encode('utf-8'):bridge.write_text(adapted,encoding='utf-8',newline='\n')
original_libs=ROOT/'app/src/main/jniLibs'/abi;destination=work/'jniLibs'/abi;destination.mkdir(parents=True,exist_ok=True)
for library in original_libs.glob('*.so'):
    if library.name!='libhuevia_raw.so':shutil.copy2(library,destination/library.name)
flags=['--target='+triple+'26','--sysroot='+str(tool/'sysroot'),'-std=c++17','-O2','-fPIC','-pthread','-DNDEBUG','-DUSE_ZLIB','-DLIBRAW_NODLL','-ffunction-sections','-fdata-sections','-Wframe-larger-than=131072','-Werror=frame-larger-than','-I'+str(source)]
link=['-shared','-Wl,--build-id=sha1','-Wl,--no-undefined','-Wl,-z,max-page-size=16384','-Wl,-z,common-page-size=16384','-nostdlib++','-lc++_shared','-lz','-lm','-latomic']
identity=hashlib.sha256((adapted+json.dumps(flags)+json.dumps(link)+(ndk/'source.properties').read_text()+hashlib.sha256((original_libs/'libraw.so').read_bytes()).hexdigest()).encode()).hexdigest()
output=destination/'libhuevia_raw.so';stamp=work/(abi+'.identity')
if not output.is_file() or not stamp.is_file() or stamp.read_text()!=identity:
    subprocess.run([str(compiler),*flags,str(bridge),'-L'+str(original_libs),'-lraw','-ljnigraphics','-llog',*link,'-Wl,-soname,libhuevia_raw.so','-o',str(output)],check=True)
    subprocess.run([str(tool/'bin/llvm-strip.exe'),'--strip-unneeded',str(output)],check=True)
    stamp.write_text(identity)
headers=subprocess.check_output([str(tool/'bin/llvm-readelf.exe'),'-lW',str(output)],text=True)
loads=[int(line.split()[-1],16) for line in headers.splitlines() if line.strip().startswith('LOAD ')]
if not loads or min(loads)<16384:raise SystemExit('RAW bridge must retain 16 KiB LOAD alignment')
assets=work/'assets/native-runtime';assets.mkdir(parents=True,exist_ok=True)
(assets/'huevia_raw.cpp').write_text(adapted,encoding='utf-8',newline='\n')
report={'abi':abi,'heapAllocatedLibRaw':True,'sourceBridgeSha256':hashlib.sha256(original.read_bytes()).hexdigest(),'adaptedBridgeSha256':hashlib.sha256(adapted.encode()).hexdigest(),'librarySha256':hashlib.sha256(output.read_bytes()).hexdigest(),'originalLibRawSha256':hashlib.sha256((original_libs/'libraw.so').read_bytes()).hexdigest(),'compiler':'Android NDK 28.2.13676358','minimumApi':26,'minimumLoadAlignment':min(loads),'bridgeFrameLimitBytes':131072,'originalLibrariesUnmodified':True}
(assets/(abi+'.json')).write_text(json.dumps(report,indent=2)+'\n')
fixture=work/'test-assets/raw-stack.dng'
subprocess.run([str(ROOT/'.tooling/cross-platform187/flutter-sdk/bin/cache/dart-sdk/bin/dart.exe'),str(ROOT/'cross-platform/tool/raw_stack_fixture.dart'),str(fixture)],check=True)
print('Prepared heap-based RAW JNI bridge: '+abi)
