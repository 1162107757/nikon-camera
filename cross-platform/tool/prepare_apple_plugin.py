"""Stage generated sources and pinned runtime in the ignored development pod."""
from pathlib import Path
import json,platform,plistlib,shutil
ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'cross-platform/.build/core-ios/generated'
toolchain=ROOT/'.tooling/cross-platform187/j2objc-3.1/dist'
jre=toolchain/'frameworks/JRE.xcframework'
info=plistlib.loads((jre/'Info.plist').read_bytes());sim='arm64' if platform.machine() in ['arm64','aarch64'] else 'x86_64'
for variant,arch in [('', 'arm64'),('simulator',sim)]:
    matches=[item for item in info['AvailableLibraries'] if item['SupportedPlatform']=='ios' and item.get('SupportedPlatformVariant','')==variant and arch in item['SupportedArchitectures']]
    if len(matches)!=1 or not (jre/matches[0]['LibraryIdentifier']/matches[0]['LibraryPath']).is_file():raise SystemExit('Missing JRE iOS '+variant+' '+arch+' slice')
report=ROOT/'cross-platform/.build/mobile-apple/native-runtime.json';report.parent.mkdir(parents=True,exist_ok=True)
report.write_text(json.dumps({'hostSimulatorArchitecture':sim,'jreLibraries':info['AvailableLibraries']},indent=2)+'\n')
pod=ROOT/'cross-platform/native/ios'
if not (ROOT/'cross-platform/.build/core-ios/parity.json').is_file():
    raise SystemExit('Apple core parity must pass before staging the plugin')
for original,target in [(source,pod/'Generated'),(toolchain/'include',pod/'RuntimeHeaders'),(toolchain/'frameworks/JRE.xcframework',pod/'Frameworks/JRE.xcframework')]:
    if not original.is_dir():raise SystemExit('Missing verified native build output: '+str(original))
    shutil.copytree(original,target,dirs_exist_ok=True)
print('Staged verified generated core and pinned JRE runtime for the Apple host')
shutil.copy2(ROOT/'cross-platform/core/apple/HueviaCoreBootstrap.h',pod/'Generated/HueviaCoreBootstrap.h')
