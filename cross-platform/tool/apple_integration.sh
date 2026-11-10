#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/cross-platform/.build/mobile-apple"
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
trap 'xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b > "$WORK/simulator-boot.log" 2>&1
cd "$ROOT/cross-platform/app"
flutter test integration_test/native_pipeline_test.dart --device-id "$DEVICE" --no-pub --reporter expanded > "$WORK/simulator-tests.log" 2>&1
