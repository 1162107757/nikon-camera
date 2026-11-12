#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/cross-platform/.build/core-ios"
J2OBJCC="$ROOT/.tooling/cross-platform187/j2objc-3.1/dist/j2objcc"
"$J2OBJCC" -O2 -fobjc-arc -I"$WORK/generated" -I"$ROOT/cross-platform/native/ios/Classes" \
  @"$WORK/objc.args" "$ROOT/cross-platform/core/test/wifi_apple.m" \
  "$ROOT/cross-platform/native/ios/Classes/HueviaWifiSocket.m" \
  -framework Network -ljre_emul -o "$WORK/wifi-checks" > "$WORK/wifi-build.log" 2>&1 || { tail -n 45 "$WORK/wifi-build.log"; exit 1; }
"$WORK/wifi-checks" > "$WORK/wifi.log" 2>&1 || { cat "$WORK/wifi.log"; exit 1; }
cat "$WORK/wifi.log"
