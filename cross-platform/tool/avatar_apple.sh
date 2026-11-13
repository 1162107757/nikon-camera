#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/cross-platform/.build/core-ios"
J2OBJCC="$ROOT/.tooling/cross-platform187/j2objc-3.1/dist/j2objcc"
failure_logs() {
  code=$?
  if [[ "$code" != 0 ]]; then
    for file in "$WORK"/avatar*.log; do echo "Log: $(basename "$file")"; tail -n 35 "$file"; done
  fi
  exit "$code"
}
trap failure_logs EXIT
# Exercise the production ImageIO avatar adapter directly, with owned images
# and no signed-in session or production test API. Keep the toolchain cache
# independent of these checks; they run after core_ios.sh prepares the runtime.
"$J2OBJCC" -O2 -fobjc-arc -I"$ROOT/cross-platform/native/ios/Classes" \
  -c "$ROOT/cross-platform/native/ios/Classes/HueviaTask.m" \
  -o "$WORK/avatar-task.o" > "$WORK/avatar-build.log" 2>&1
"$J2OBJCC" -O2 -fobjc-arc -I"$ROOT/cross-platform/native/ios/Classes" \
  "$ROOT/cross-platform/core/test/avatar_apple.mm" \
  "$ROOT/cross-platform/native/ios/Classes/HueviaAvatar.mm" \
  "$ROOT/cross-platform/native/ios/Classes/HueviaTaskCancellation.m" \
  "$WORK/avatar-task.o" \
  -framework ImageIO -framework CoreGraphics -ljre_emul -lc++ \
  -o "$WORK/avatar-checks" >> "$WORK/avatar-build.log" 2>&1
"$WORK/avatar-checks" > "$WORK/avatar.log" 2>&1
cat "$WORK/avatar.log"
