#!/usr/bin/env bash
# assemble_ordered.sh — assemble the FULL compiler image in dependency
# (staload) order so eager top-level inits resolve.  Order:
#   runtime floor (cats/runtime/collrt) -> compiled units in
#   all_ordered.units order -> generics layer (LAST, wins clobbers) -> [driver]
# Uses the phase-1 fxp cache by default (no continuation seeding); pass a
# different cache dir as $2 for a seeded image.
#   tools/assemble_ordered.sh [out.scm] [cachedir] [driver.scm]
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
RT_DIR="$HERE/../../srcgen1/prelude/DATS/CATS/CHEZ"
OUT="${1:-$HERE/srcgen2/BUILD/selfhost/ordered.scm}"
CACHE="${2:-$HERE/srcgen2/BUILD/selfhost/fxp}"
DRIVER="${3:-}"
UNITS="$HERE/srcgen2/TEST/selfhost/all_ordered.units"

cat "$RT_DIR/xats2chez_cats.scm" "$RT_DIR/xats2chez_runtime.scm" \
    "$RT_DIR/xats2chez_collrt.scm" > "$OUT"
# The generics/floor layer is emitted at the prelude->compiler BOUNDARY (so
# compiler eager top-level inits see native strn_append/list ops instead of the
# prelude's type-erased lambda-lifted instances) AND again at the END (so it wins
# over any clobbers from the compiler units themselves for runtime calls).
n=0; boundary_done=0
while read -r u; do
  # first compiler unit (xbasics) => drop the boundary generics first
  if [ "$u" = "xbasics" ] && [ "$boundary_done" -eq 0 ]; then
    cat "$RT_DIR/xats2chez_generics.scm" >> "$OUT"; boundary_done=1
  fi
  [ -f "$CACHE/$u.scm" ] && { cat "$CACHE/$u.scm" >> "$OUT"; n=$((n+1)); }
done < "$UNITS"
cat "$RT_DIR/xats2chez_generics.scm" >> "$OUT"
[ -n "$DRIVER" ] && [ -f "$DRIVER" ] && cat "$DRIVER" >> "$OUT"
echo ">> $OUT : $n units, $(grep -c '(define' "$OUT") defines (generics at boundary=$boundary_done + end)"
