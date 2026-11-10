#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/cross-platform/.build/core-ios"
mkdir -p "$WORK"
failure_logs() {
  code=$?
  if [[ $code != 0 ]]; then
    for file in "$WORK"/*.log; do echo "Log: $(basename "$file")"; tail -n 25 "$file"; done
  fi
  exit "$code"
}
trap failure_logs EXIT
export JAVA_HOME="${HUEVIA_JAVA_HOME:-$(/usr/libexec/java_home -v 21)}"
export PATH="$JAVA_HOME/bin:$PATH"
python3 "$ROOT/cross-platform/tool/core_check.py" > "$WORK/jvm.log" 2>&1
python3 "$ROOT/cross-platform/tool/inventory.py" --verify

TOOLCHAIN="$ROOT/.tooling/cross-platform187/j2objc-3.1"
if [[ ! -x "$TOOLCHAIN/dist/j2objc" ]]; then
  mkdir -p "$(dirname "$TOOLCHAIN")"
  curl --fail --location --retry 3 --connect-timeout 20 \
    https://codeload.github.com/google/j2objc/zip/refs/tags/3.1 \
    --output "$WORK/j2objc-source.zip"
  echo '8116d3accee27ec83aec69cfd738bf75b632a226af7f0f736f00ae60cc2c70d5  '"$WORK/j2objc-source.zip" | shasum -a 256 -c -
  unzip -q -o "$WORK/j2objc-source.zip" -d "$(dirname "$TOOLCHAIN")"
  # macosx is x86_64; macosx64 is arm64. Only the required mobile/host
  # architectures are built, without watchOS/tvOS/Catalyst runtimes.
  if [[ "$(uname -m)" == arm64 ]]; then
    export J2OBJC_ARCHS="macosx64 iphone64 simulator64"
  else
    export J2OBJC_ARCHS="macosx iphone64 simulator"
  fi
  make -C "$TOOLCHAIN" -j4 translator_dist jre_emul_dist > "$WORK/toolchain-build.log" 2>&1
fi

J2OBJC="$TOOLCHAIN/dist/j2objc"
J2OBJCC="$TOOLCHAIN/dist/j2objcc"
mkdir -p "$WORK/generated"
python3 - "$ROOT" "$WORK" <<'PY'
import json,sys
from pathlib import Path
root,work=map(Path,sys.argv[1:])
paths=json.loads((root/'cross-platform/.build/core-jvm/sources.json').read_text())
# J2ObjC 3.1 lacks TimeZone.toZoneId(). Its JDK equivalent uses the same short
# ID map. Adapt only the translation input; preserved sources stay untouched.
adapted=[]
for name in paths:
    source=root/name
    if name.endswith('/PhotoDateGroups.java'):
        text=source.read_text(encoding='utf-8-sig')
        a='TimeZone.getDefault().toZoneId()'
        b='Objects.requireNonNull(timeZone, "timeZone").toZoneId()'
        if text.count(a)!=1 or text.count(b)!=1:raise SystemExit('TimeZone adapter requires review')
        text=text.replace(a,'ZoneId.of(TimeZone.getDefault().getID(), ZoneId.SHORT_IDS)').replace(b,'ZoneId.of(Objects.requireNonNull(timeZone, "timeZone").getID(), ZoneId.SHORT_IDS)')
        source=work/'translation-input'/name
        source.parent.mkdir(parents=True,exist_ok=True);source.write_text(text)
    adapted.append(source)
# J2ObjC's response-file reader treats quote characters as filename characters.
# macOS CI paths contain no whitespace; use its literal one-path-per-line format.
if any(any(c.isspace() for c in str(p)) for p in adapted):
    raise SystemExit('J2ObjC source paths must not contain whitespace')
(work/'sources.args').write_text('\n'.join(str(p) for p in adapted)+'\n')
PY
"$J2OBJC" -source 11 -encoding UTF-8 -use-arc -d "$WORK/generated" \
  @"$WORK/sources.args" > "$WORK/translation.log" 2>&1
python3 - "$WORK" <<'PY'
import sys
from pathlib import Path
work=Path(sys.argv[1])
(work/'objc.args').write_text('\n'.join('"'+str(p)+'"' for p in (work/'generated').rglob('*.m'))+'\n')
PY
"$J2OBJCC" -O2 -fobjc-arc -ffp-contract=off -I"$WORK/generated" \
  @"$WORK/objc.args" "$ROOT/cross-platform/core/test/main.m" -ljre_emul \
  -o "$WORK/core-parity" > "$WORK/objc-build.log" 2>&1
"$WORK/core-parity" > "$WORK/objc.log" 2>&1
python3 - "$ROOT" "$WORK" <<'PY'
import json,sys
from pathlib import Path
root,work=map(Path,sys.argv[1:])
expected=json.loads((root/'cross-platform/.build/core-jvm/golden.json').read_text())
text=(work/'objc.log').read_text()
actual=json.loads(next(line.split('=',1)[1] for line in text.splitlines() if line.startswith('HUEVIA_CORE_GOLDEN=')))
if expected!=actual: raise SystemExit('JVM / Objective-C core fingerprints differ')
(work/'parity.json').write_text(json.dumps({'pass':True,'platform':'macOS Objective-C runtime; iOS static runtime built separately','golden':actual},indent=2)+'\n')
print('PASS original JVM tests translated to Objective-C and matching image fingerprints')
PY
