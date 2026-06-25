#!/usr/bin/env bash
# recompile_units.sh — compile compiler .dats units to Scheme IN PARALLEL.
#   tools/recompile_units.sh <unitlist>
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
BUNDLE="$HERE/srcgen2/BUILD/xats2chez-bundle.js"
CACHE="$HERE/srcgen2/BUILD/selfhost/cache2"; mkdir -p "$CACHE"
STK="${STK:-60000}"
export BUNDLE CACHE STK XATSHOME
co() {
  u="$1"; src=""
  for d in "$XATSHOME/srcgen2/DATS" "$XATSHOME/prelude/DATS" "$XATSHOME/prelude/DATS/VT" \
           "$XATSHOME/srcgen2/xats2chez/xats2cc/srcgen1/DATS" "$XATSHOME/srcgen2/xats2chez/srcgen2/DATS"; do
    [ -f "$d/$u.dats" ] && { src="$d/$u.dats"; break; }; done
  [ -n "$src" ] || { echo "MISS $u"; return; }
  node --stack-size="$STK" "$BUNDLE" "$src" 2>"$CACHE/$u.err" \
    | awk '/^;;==XATS2CHEZ-BEGIN==/{f=1;next}/^;;==XATS2CHEZ-END==/{f=0}f' > "$CACHE/$u.scm"
}
export -f co
grep -vE '^\s*#|^\s*$' "$1" | xargs -P 10 -n1 -I{} bash -c 'co "$@"' _ {}
echo ">> recompiled $(grep -vcE '^\s*#|^\s*$' "$1") units (parallel)"
