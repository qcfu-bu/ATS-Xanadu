#!/usr/bin/env bash
# wire-driver.sh — emit the CLI driver (srcgen2/UTIL/xats2go_goemit01.dats)
# and wire its REAL main into the assembled package: the driver lands in
# src/zz_driver.go (its own temps renamed godrvtnm) and emitter_all.go's
# synthetic trivial `func main` is removed so the driver's main links.
# Run AFTER assemble.sh (assemble regenerates the synthetic main each time).
set -uo pipefail
# repo root: three levels up from this script (srcgen2/xats2go/selfhost-build)
X="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export XATSHOME=$X
# deep-recursion headroom (see assemble.sh): OS stack up, V8 limit under it.
ulimit -s 65520 2>/dev/null || true
NODESTK="${NODESTK:-50000}"
GOPATCHED=$X/srcgen2/xats2go/srcgen2/BUILD/xats2go-bundle.patched.js
OUT=$X/srcgen2/xats2go/selfhost-build
EMIT="$OUT/emit"

f=$X/srcgen2/xats2go/srcgen2/UTIL/xats2go_goemit01.dats
m=xats2go_goemit01
if [ ! -s "$EMIT/$m.go" ] || [ "$f" -nt "$EMIT/$m.go" ] || [ "$GOPATCHED" -nt "$EMIT/$m.go" ]; then
  node --stack-size=$NODESTK "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
  awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
fi

# driver file: keep EVERYTHING including func main; rename temps godrvtnm.
{
  printf 'package main\n\nimport "xatsgo"\n\nvar _ = xatsgo.XATSNIL\n\n'
  awk 'BEGIN{started=0}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$EMIT/$m.go" \
    | sed -E "s/goxtnm([0-9])/godrvtnm\\1/g"
} > "$OUT/src/zz_driver.go"

# drop the assembled package's synthetic main (the driver now provides main).
# portable in-place edit (GNU and BSD sed both accept an attached -i suffix)
sed -i.bak '/^func main() { xatsgo\.XATS2GO_flush_pending() }$/d' "$OUT/src/emitter_all.go"
rm -f "$OUT/src/emitter_all.go.bak"

echo ">> driver wired: src/zz_driver.go ($(wc -l < "$OUT/src/zz_driver.go") lines), synthetic main removed"
