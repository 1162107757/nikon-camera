#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/cross-platform/.build/public-internet-apple"
CLASSES="$ROOT/cross-platform/native/ios/Classes"
mkdir -p "$WORK"
PHASE=toolchain
SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
COMPILE_EXIT=""
EXECUTION_EXIT=""
finish() {
  status=$?
  trap - EXIT
  python3 - "$ROOT" "$WORK" "$PHASE" "$status" "$SOURCE_COMMIT" "$COMPILE_EXIT" "$EXECUTION_EXIT" <<'PY'
import datetime,hashlib,json,sys
from pathlib import Path
root,work=map(Path,sys.argv[1:3]);phase=sys.argv[3];code=int(sys.argv[4])
source=sys.argv[5];compile_code=int(sys.argv[6]) if sys.argv[6] else None
execution_code=int(sys.argv[7]) if sys.argv[7] else None
sources=['cross-platform/native/ios/Classes/HueviaPublicInternetQueues.h',
         'cross-platform/native/ios/Classes/HueviaPublicInternetQueues.m',
         'cross-platform/native/ios/Classes/HueviaCorePlugin.m',
         'cross-platform/native/tests/public_internet_queue_apple.m',
         'cross-platform/tool/public_internet_queue_source_check.py',
         'cross-platform/tool/public_internet_apple.sh']
receipt={'schemaVersion':2,'passed':code==0,'exitCode':code,'phase':phase,
         'sourceCommit':source,'compileExitCode':compile_code,'executionExitCode':execution_code,
         'verifiedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),
         'platform':'macOS Foundation production I/O queues',
         'sourceSha256':{name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
         'contract':{'accountConcurrency':2,'publicConcurrency':3,'serialCameraHeartbeatCommands':16,
                     'physicalCameraExercised':False},
         'logs':{'compiler':'compiler.log','build':'build.log','stdout':'stdout.log','architecture':'source-check.log'}}
(work/'result.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
PY
  for destination in "$ROOT/cross-platform/.build/core-ios/public-internet" "$ROOT/cross-platform/.build/mobile-apple/public-internet"; do
    mkdir -p "$destination"
    for receipt in result.json compiler.log build.log stdout.log source-check.log; do
      if [[ -f "$WORK/$receipt" ]]; then cp "$WORK/$receipt" "$destination/$receipt"; fi
    done
  done
  exit "$status"
}
trap finish EXIT
: > "$WORK/build.log"
: > "$WORK/stdout.log"
: > "$WORK/source-check.log"
xcrun --sdk macosx clang --version > "$WORK/compiler.log" 2>&1
PHASE=architecture
python3 "$ROOT/cross-platform/tool/public_internet_queue_source_check.py" > "$WORK/source-check.log" 2>&1
PHASE=compile
if xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra \
  -I"$CLASSES" "$CLASSES/HueviaPublicInternetQueues.m" \
  "$ROOT/cross-platform/native/tests/public_internet_queue_apple.m" \
  -framework Foundation -o "$WORK/public-internet-queue-checks" > "$WORK/build.log" 2>&1; then
  COMPILE_EXIT=0
else
  COMPILE_EXIT=$?
  tail -n 60 "$WORK/build.log"
  exit "$COMPILE_EXIT"
fi
PHASE=runtime
if "$WORK/public-internet-queue-checks" > "$WORK/stdout.log" 2>&1; then
  EXECUTION_EXIT=0
else
  EXECUTION_EXIT=$?
  cat "$WORK/stdout.log"
  exit "$EXECUTION_EXIT"
fi
python3 - "$WORK/stdout.log" <<'PY'
import sys
from pathlib import Path
text=Path(sys.argv[1]).read_text()
assert 'PASS Apple public I/O queue isolation:' in text, 'Apple public I/O fixture did not report its required PASS'
print(text,end='')
PY
PHASE=complete
