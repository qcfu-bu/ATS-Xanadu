#!/usr/bin/env bash
# run_selfhost.sh — compile cached unit .scm to .so (parallel, fast), load them
# in order with per-unit markers, then a driver.  Sidesteps chez whole-program
# compile (which is superlinear); per-file objects load fast.
#   tools/run_selfhost.sh <unitlist> [driver.scm]
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
RT="$XATSHOME/srcgen1/prelude/DATS/CATS/CHEZ"
SO="$HERE/srcgen2/BUILD/selfhost/so"; mkdir -p "$SO"
CACHE="$HERE/srcgen2/BUILD/selfhost/cache2"
LIST="$1"; DRIVER="${2:-}"
cat "$RT/xats2chez_cats.scm" "$RT/xats2chez_runtime.scm" "$RT/xats2chez_collrt.scm" \
    "$RT/xats2chez_jsffi.scm" "$RT/xats2chez_jsrt.scm" > "$SO/floor.scm"
chez --optimize-level 0 -q >/dev/null 2>&1 <<E
(compile-file "$SO/floor.scm" "$SO/floor.so")
(compile-file "$RT/xats2chez_generics.scm" "$SO/generics.so")
E
grep -vE '^\s*#|^\s*$' "$LIST" | xargs -P 8 -I {} sh -c "[ -s '$CACHE/{}.scm' ] && chez --optimize-level 0 -q >/dev/null 2>&1 <<EE
(compile-file \"$CACHE/{}.scm\" \"$SO/{}.so\")
EE" 2>/dev/null
{
  echo "(load \"$SO/floor.so\")(load \"$SO/generics.so\")"
  grep -vE '^\s*#|^\s*$' "$LIST" | while read u; do
    [ -f "$SO/$u.so" ] && echo "(load \"$SO/$u.so\")(display \";;ld $u\")(newline)(flush-output-port)"
  done
  echo "(load \"$SO/generics.so\")(display \";;ld generics-end\")(newline)(flush-output-port)"
  [ -n "$DRIVER" ] && [ -f "$DRIVER" ] && cat "$DRIVER"
} > "$SO/load_run.scm"
echo ">> so=$(ls $SO/*.so | wc -l | tr -d ' '); loading..."
exec chez --script "$SO/load_run.scm"
