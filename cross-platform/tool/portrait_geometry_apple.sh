#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${HUEVIA_GEOMETRY_WORK:-$ROOT/.tooling/retouch-migration/portrait-geometry-probe}"
mkdir -p "$WORK"
SOURCE="$ROOT/cross-platform/tool/portrait_geometry_apple.mm"
PHOTO="$ROOT/app/src/main/assets/preset-showcase/portrait-smile.jpg"
FRAMEWORKS=(-framework Foundation -framework CoreGraphics -framework ImageIO -framework Vision)
xcrun clang++ -std=c++17 -fobjc-arc -ffp-contract=off -Wno-deprecated-declarations "$SOURCE" "${FRAMEWORKS[@]}" -o "$WORK/host-probe"
"$WORK/host-probe" "$PHOTO" > "$WORK/host.json"
cat "$WORK/host.json"
ARCH="$(uname -m)"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator clang++ -std=c++17 -fobjc-arc -ffp-contract=off -Wno-deprecated-declarations \
  -target "$ARCH-apple-ios16.0-simulator" -isysroot "$SDK" "$SOURCE" \
  "${FRAMEWORKS[@]}" -o "$WORK/simulator-probe"
codesign --force --sign - "$WORK/simulator-probe"
if [[ -n "${HUEVIA_GEOMETRY_DEVICE:-}" ]]; then
  DEVICE="$HUEVIA_GEOMETRY_DEVICE"
else
  xcrun simctl list devices available -j > "$WORK/devices.json"
  DEVICE="$(python3 - "$WORK/devices.json" <<'PY'
import json,re,sys
devices=json.load(open(sys.argv[1]))['devices']
versions=sorted((runtime for runtime in devices if 'iOS' in runtime),key=lambda s:tuple(map(int,re.findall(r'\d+',s))),reverse=True)
phones=[]
for runtime in versions:
    phones=[d for d in devices[runtime] if d.get('isAvailable') and d['name'].startswith('iPhone')]
    if phones:break
phones.sort(key=lambda d:d.get('state')!='Booted')
if not phones:raise SystemExit('No available iOS simulator')
print(phones[0]['udid'])
PY
)"
fi
xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE" -b > "$WORK/boot.log" 2>&1
xcrun simctl spawn "$DEVICE" "$WORK/simulator-probe" "$PHOTO" > "$WORK/simulator.json" 2> "$WORK/simulator-stderr.log"
cat "$WORK/simulator.json"
