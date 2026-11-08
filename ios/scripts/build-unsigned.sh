#!/bin/bash
set -euo pipefail
IOS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${1:-$IOS_ROOT/build/artifacts}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
ICON="$IOS_ROOT/Huevia/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICON"
sips -z 1024 1024 "$IOS_ROOT/Huevia/icon-source.png" --out "$ICON/AppIcon.png" >/dev/null
cat > "$ICON/Contents.json" <<'JSON'
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
JSON
python3 "$IOS_ROOT/scripts/generate_project.py"
xcodebuild -project "$IOS_ROOT/Huevia.xcodeproj" -scheme Huevia -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$IOS_ROOT/build/device" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
APP="$IOS_ROOT/build/device/Build/Products/Release-iphoneos/Huevia.app"
STAGE="$(mktemp -d "$IOS_ROOT/build/ipa.XXXXXX")"
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/Huevia.app"
IPA="$OUTPUT/Huevia-0.1.0-unsigned.ipa"
ditto -c -k --keepParent "$STAGE/Payload" "$IPA"
python3 "$IOS_ROOT/scripts/verify_ipa.py" "$IPA" > "$OUTPUT/ipa-verification.json"
shasum -a 256 "$IPA" > "$OUTPUT/Huevia-0.1.0-unsigned.ipa.sha256"
printf '\nUnsigned iPhone IPA: %s\n' "$IPA"
