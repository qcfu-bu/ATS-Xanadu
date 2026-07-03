#!/usr/bin/env bash
# wire-driver.sh — emit the CLI driver (srcgen2/UTIL/xats2go_goemit01.dats)
# and wire its REAL main into the assembled package: the driver lands in
# src/zz_driver.go (its own temps renamed godrvtnm) and emitter_all.go's
# synthetic trivial `func main` is removed so the driver's main links.
# Run AFTER assemble.sh (assemble regenerates the synthetic main each time).
set -uo pipefail
X=/home/user/ATS-Xanadu
export XATSHOME=$X
GOPATCHED=$X/srcgen2/xats2go/srcgen2/BUILD/xats2go-bundle.patched.js
OUT=$X/srcgen2/xats2go/selfhost-build
EMIT="$OUT/emit"

f=$X/srcgen2/xats2go/srcgen2/UTIL/xats2go_goemit01.dats
m=xats2go_goemit01
if [ ! -s "$EMIT/$m.go" ] || [ "$f" -nt "$EMIT/$m.go" ] || [ "$GOPATCHED" -nt "$EMIT/$m.go" ]; then
  node --stack-size=8801 "$GOPATCHED" "$f" > "$EMIT/$m.raw" 2>"$EMIT/$m.err"
  awk '/^\/\/==XATS2GO-BEGIN==/{f=1;next} /^\/\/==XATS2GO-END==/{f=0} f' "$EMIT/$m.raw" > "$EMIT/$m.go"
fi

# driver file: keep EVERYTHING including func main; rename temps godrvtnm.
{
  printf 'package main\n\nimport "xatsgo"\n\nvar _ = xatsgo.XATSNIL\n\n'
  awk 'BEGIN{started=0}
       /^func /{started=1}
       /^var [^_]/{started=1}
       started{print}' "$EMIT/$m.go" \
    | sed "s/goxtnm/godrvtnm/g"
} > "$OUT/src/zz_driver.go"

# drop the assembled package's synthetic main (the driver now provides main).
sed -i '/^func main() { xatsgo\.XATS2GO_flush_pending() }$/d' "$OUT/src/emitter_all.go"

echo ">> driver wired: src/zz_driver.go ($(wc -l < "$OUT/src/zz_driver.go") lines), synthetic main removed"
