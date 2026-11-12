#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/cross-platform/.build/mobile-apple"
mkdir -p "$WORK"
python3 "$ROOT/cross-platform/tool/source_check.py"
export CI=true FLUTTER_SUPPRESS_ANALYTICS=true
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
export PUB_CACHE="$ROOT/.tooling/cross-platform187/pub-cache"
SDK="$ROOT/.tooling/cross-platform187/flutter-sdk"
REVISION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["flutterRevision"])' "$ROOT/cross-platform/toolchain.json")"
if [[ ! -x "$SDK/bin/flutter" ]]; then
  mkdir -p "$SDK"
  git -C "$SDK" init -q
  git -C "$SDK" remote add origin https://github.com/flutter/flutter.git
  git -C "$SDK" -c http.version=HTTP/1.1 -c protocol.version=2 fetch --depth 1 origin "$REVISION"
  git -C "$SDK" checkout -q -B stable FETCH_HEAD
  git -C "$SDK" -c http.version=HTTP/1.1 fetch --depth 1 origin refs/tags/3.47.9:refs/tags/3.47.9
fi
export PATH="$SDK/bin:$JAVA_HOME/bin:$PATH"
flutter --version > "$WORK/flutter-bootstrap.log" 2>&1
flutter --version --machine > "$WORK/flutter-version.json"
python3 - "$WORK/flutter-version.json" "$REVISION" <<'PY'
import json,sys
value=json.load(open(sys.argv[1]));assert value['frameworkRevision']==sys.argv[2]
assert value['frameworkVersion']=='3.47.9'
PY
if [[ "${1:-all}" != build ]]; then
bash "$ROOT/cross-platform/tool/core_ios.sh"
bash "$ROOT/cross-platform/tool/avatar_apple.sh"
bash "$ROOT/cross-platform/tool/wifi_apple.sh"
python3 "$ROOT/cross-platform/tool/prepare_apple_plugin.py"
python3 "$ROOT/cross-platform/tool/raw_apple.py" > "$WORK/raw-build.log" 2>&1
python3 - "$ROOT" <<'PY'
import sys,shutil
from pathlib import Path
root=Path(sys.argv[1]);shutil.copytree(root/'app/src/main/assets/photo-borders',root/'cross-platform/native/ios/Assets/photo-borders',dirs_exist_ok=True)
shutil.copytree(root/'cross-platform/app/assets/fonts',root/'cross-platform/native/ios/Assets/reference-fonts',dirs_exist_ok=True)
shutil.copytree(root/'app/src/main/assets/preset-showcase',root/'cross-platform/native/ios/Assets/preset-showcase',dirs_exist_ok=True)
PY
# The hosted runner is disposable; this setting does not change a user machine.
flutter config --no-enable-swift-package-manager
cd "$ROOT/cross-platform/app"
flutter pub get > "$WORK/pub-get.log" 2>&1
python3 - <<'PY'
import json
from pathlib import Path
plugins=json.loads(Path('.flutter-plugins-dependencies').read_text())
if plugins.get('swift_package_manager_enabled',{}).get('ios') is not False:
    raise SystemExit('Apple native plugins must consistently use CocoaPods')
print('Verified project-level CocoaPods-only native plugin resolution')
PY
fi
if [[ "${1:-all}" == prepare ]]; then exit 0; fi
cd "$ROOT/cross-platform/app"
flutter analyze --no-pub > "$WORK/analyze.log" 2>&1
flutter test --no-pub --concurrency=1 --reporter expanded > "$WORK/flutter-tests.log" 2>&1
flutter build ios --release --no-codesign --no-pub > "$WORK/device-build.log" 2>&1
python3 "$ROOT/cross-platform/tool/package_ipa.py"
bash "$ROOT/cross-platform/tool/apple_integration.sh"
python3 "$ROOT/cross-platform/tool/inventory.py" --verify
