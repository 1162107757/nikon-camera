#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/cross-platform/.build/mobile-apple"
STARTED="$(date +%s)"
DEVICE="$(python3 - <<'PY'
import json,subprocess
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j']))['devices']
for runtime,rows in reversed(list(devices.items())):
    if '.iOS-' in runtime:
        for device in rows:
            if device['name'].startswith('iPhone'):
                print(device['udid']);raise SystemExit(0)
raise SystemExit('No available iPhone simulator runtime')
PY
)"
finish() {
  code=$?
  if [[ "$code" != 0 ]]; then
    # Flutter loses its VM connection on native aborts. Keep the actual Apple
    # exception report and unified log before the ephemeral runner is removed.
    python3 - "$WORK" "$DEVICE" "$STARTED" <<'PY'
from pathlib import Path
import shutil,subprocess,sys
work,device,started=Path(sys.argv[1]),sys.argv[2],int(sys.argv[3])
try:
    result=subprocess.run(['xcrun','simctl','spawn',device,'log','show','--last','5m','--style','compact','--predicate','process == "Runner"'],capture_output=True,timeout=25)
    (work/'simulator-native.log').write_bytes((result.stdout+result.stderr)[-4*1024*1024:])
except subprocess.TimeoutExpired:(work/'simulator-native.log').write_text('Simulator unified log timed out\n')
roots=[Path.home()/'Library/Logs/DiagnosticReports',Path.home()/'Library/Developer/CoreSimulator/Devices'/device/'data/Library/Logs/CrashReporter']
reports=[]
for root in roots:
    if root.is_dir():reports.extend(p for p in root.rglob('Runner*.ips') if p.stat().st_mtime>=started and p.stat().st_size<=5*1024*1024)
target=work/'simulator-crashes';target.mkdir(exist_ok=True)
for index,report in enumerate(sorted(reports,key=lambda p:p.stat().st_mtime,reverse=True)[:8]):shutil.copy2(report,target/(str(index)+'-'+report.name))
print('Preserved '+str(min(8,len(reports)))+' native crash report(s)')
PY
  fi
  xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1 || true
  exit "$code"
}
trap finish EXIT
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b > "$WORK/simulator-boot.log" 2>&1
cd "$ROOT/cross-platform/app"
# The test suite's loading budget includes Xcode compilation. Compile the
# native simulator app first so a cold CI build cannot consume that budget
# immediately after Dart starts. Keep the actual test assertions/timeouts.
flutter build ios --simulator --debug --config-only --no-pub --target integration_test/native_pipeline_test.dart > "$WORK/simulator-config.log" 2>&1
# The generated JRE/LibRaw and Pods use the current host's simulator slice.
# Match it on the app target as well; a generic multi-architecture build cannot
# import a Swift module whose Pods were built only for the host architecture.
SIM_ARCH="$(uname -m)"
if [[ "$SIM_ARCH" != arm64 && "$SIM_ARCH" != x86_64 ]]; then echo "Unsupported simulator host: $SIM_ARCH"; exit 1; fi
xcrun simctl list devices available -j > "$WORK/simulator-devices.json"
xcrun xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug \
  -sdk iphonesimulator -destination "id=$DEVICE" "ARCHS=$SIM_ARCH" ONLY_ACTIVE_ARCH=YES \
  "BUILD_DIR=$ROOT/cross-platform/app/build/ios" build > "$WORK/simulator-build.log" 2>&1
flutter test integration_test/native_pipeline_test.dart --device-id "$DEVICE" --no-pub --reporter expanded --verbose > "$WORK/simulator-tests.log" 2>&1
