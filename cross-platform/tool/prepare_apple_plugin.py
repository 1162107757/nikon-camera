"""Stage generated sources and pinned runtime in the ignored development pod."""
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parents[2]
source=ROOT/'cross-platform/.build/core-ios/generated'
toolchain=ROOT/'.tooling/cross-platform187/j2objc-3.1/dist'
pod=ROOT/'cross-platform/native/ios'
if not (ROOT/'cross-platform/.build/core-ios/parity.json').is_file():
    raise SystemExit('Apple core parity must pass before staging the plugin')
for original,target in [(source,pod/'Generated'),(toolchain/'include',pod/'RuntimeHeaders'),(toolchain/'frameworks/JRE.xcframework',pod/'Frameworks/JRE.xcframework')]:
    if not original.is_dir():raise SystemExit('Missing verified native build output: '+str(original))
    shutil.copytree(original,target,dirs_exist_ok=True)
print('Staged verified generated core and pinned JRE runtime for the Apple host')
