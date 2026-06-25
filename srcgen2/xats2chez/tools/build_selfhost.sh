#!/usr/bin/env bash
# build_selfhost.sh — compile the compiler units to Scheme (inline architecture,
# NO seeding) and assemble a loadable image with the FULL runtime.
#   tools/build_selfhost.sh <unitlist> <out.scm> [driver.scm]
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
BUNDLE="$HERE/srcgen2/BUILD/xats2chez-bundle.js"
RTDIR="$XATSHOME/srcgen1/prelude/DATS/CATS/CHEZ"
CACHE="$HERE/srcgen2/BUILD/selfhost/cache2"; mkdir -p "$CACHE"
LIST="$1"; OUT="$2"; DRIVER="${3:-}"
STK="${STK:-60000}"

srcof() { for d in "$XATSHOME/srcgen2/DATS" "$XATSHOME/prelude/DATS" "$XATSHOME/prelude/DATS/VT" \
                   "$XATSHOME/srcgen2/xats2chez/xats2cc/srcgen1/DATS" "$XATSHOME/srcgen2/xats2chez/srcgen2/DATS"; do
  [ -f "$d/$1.dats" ] && { echo "$d/$1.dats"; return; }; done; echo ""; }

UNITS="$(grep -vE '^\s*#|^\s*$' "$LIST")"
NU=$(echo "$UNITS" | wc -w | tr -d ' ')
echo ">> compiling $NU units (stack=$STK) ..."
fail=0; miss=0
for u in $UNITS; do
  src="$(srcof "$u")"; [ -n "$src" ] || { echo "MISS-SRC $u"; miss=$((miss+1)); continue; }
  node --stack-size=$STK "$BUNDLE" "$src" 2>"$CACHE/$u.err" > "$CACHE/$u.raw"
  rc=$?
  awk '/^;;==XATS2CHEZ-BEGIN==/{f=1;next}/^;;==XATS2CHEZ-END==/{f=0}f' "$CACHE/$u.raw" > "$CACHE/$u.scm"
  rm -f "$CACHE/$u.raw"
  if [ "$rc" -ne 0 ] || [ ! -s "$CACHE/$u.scm" ]; then echo "FAIL[$rc] $u :: $(tail -1 "$CACHE/$u.err" 2>/dev/null|cut -c1-60)"; fail=$((fail+1)); fi
done
echo ">> compile done: $NU units, $fail failed, $miss missing-src"

# assemble: runtime floor -> generics(boundary, before xbasics) -> units -> generics(end) -> driver
GEN="$RTDIR/xats2chez_generics.scm"
cat "$RTDIR/xats2chez_cats.scm" "$RTDIR/xats2chez_runtime.scm" "$RTDIR/xats2chez_collrt.scm" \
    "$RTDIR/xats2chez_jsffi.scm" "$RTDIR/xats2chez_jsrt.scm" > "$OUT"
bdone=0
for u in $UNITS; do
  if [ "$u" = "xbasics" ] && [ "$bdone" -eq 0 ]; then cat "$GEN" >> "$OUT"; bdone=1; fi
  [ -f "$CACHE/$u.scm" ] && cat "$CACHE/$u.scm" >> "$OUT"
done
cat "$GEN" >> "$OUT"
[ -n "$DRIVER" ] && [ -f "$DRIVER" ] && cat "$DRIVER" >> "$OUT"
echo ">> image: $OUT ($(grep -c '(define' "$OUT") defines, generics-boundary=$bdone)"
