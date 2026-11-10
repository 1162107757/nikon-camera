"""Build the pinned LibRaw source for real iPhoneOS and the current simulator host."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import json,os,subprocess,platform,shutil
import raw_sources
ROOT=raw_sources.ROOT
work=ROOT/'cross-platform/.build/raw-apple'
manifest=json.loads((work/'sources.json').read_text())
source=Path(manifest['root']);output=ROOT/'cross-platform/native/ios/Frameworks/LibRaw.xcframework'
libraries=[]
for name,sdk,target in [('iphoneos','iphoneos','arm64-apple-ios16.0'),('simulator','iphonesimulator',('arm64' if platform.machine()=='arm64' else 'x86_64')+'-apple-ios16.0-simulator')]:
    destination=work/name;destination.mkdir(exist_ok=True)
    sysroot=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
    compiler=subprocess.check_output(['xcrun','--sdk',sdk,'--find','clang++'],text=True).strip()
    flags=['-target',target,'-isysroot',sysroot,'-std=c++17','-O2','-fPIC','-pthread','-DNDEBUG','-DUSE_ZLIB','-DLIBRAW_NODLL','-ffunction-sections','-fdata-sections','-I'+str(source)]
    def compile_one(relative):
        obj=destination/(relative.replace('/','_')+'.o')
        if not obj.is_file():
            run=subprocess.run([compiler,*flags,'-c',str(source/relative),'-o',str(obj)],capture_output=True,text=True)
            (obj.with_suffix('.log')).write_text(run.stdout+run.stderr)
            if run.returncode:raise RuntimeError(relative+'\n'+run.stderr[-3000:])
        return obj
    with ThreadPoolExecutor(max_workers=4) as pool:objects=list(pool.map(compile_one,manifest['sources']))
    archive=destination/'libraw.a'
    subprocess.run(['xcrun','libtool','-static','-o',str(archive),*[str(obj) for obj in objects]],check=True)
    libraries.extend(['-library',str(archive),'-headers',str(source/'libraw')])
    print('Built LibRaw for '+target,flush=True)
if output.exists():
    # Only a known generated XCFramework within this plugin can be replaced.
    if not output.resolve().is_relative_to((ROOT/'cross-platform/native/ios/Frameworks').resolve()):raise SystemExit('Unsafe generated framework path')
    shutil.rmtree(output)
output.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(['xcodebuild','-create-xcframework',*libraries,'-output',str(output)],check=True)
shutil.copytree(source/'libraw',ROOT/'cross-platform/native/ios/RuntimeHeaders/libraw',dirs_exist_ok=True)
notices=ROOT/'cross-platform/native/ios/Notices';notices.mkdir(exist_ok=True)
for name in ['LICENSE.LGPL','LICENSE.CDDL','COPYRIGHT']:
    shutil.copy2(source/name,notices/name)
shutil.copy2(ROOT/'app/src/main/assets/third-party/libraw/LibRaw-0.22.3-source.zip',notices/'LibRaw-0.22.3-source.zip')
print('Prepared source, licences and both Apple LibRaw platform slices')
