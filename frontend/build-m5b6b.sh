#!/usr/bin/env bash
########################################################################
# M5b.6b — Python-surface frontend: type-PARAMETER SORT ANNOTATIONS
# ([A: VType @unboxed]) wired into the s2var sort + TYPECHECK.
#
# Slice 6b (the LAST piece of M5b): a param's declared surface sort now SELECTS its s2var
# sort, instead of every param being forced to the_sort2_type. The mapping (SURFACE-GRAMMAR
# §5.7.1): Type/none -> the_sort2_type (+@unboxed -> the_sort2_tflt); VType -> the_sort2_vwtp
# (+@unboxed -> the_sort2_vtft); Prop -> the_sort2_prop. PyCore now carries the param sort
# (pcparam = name + sort name + @unboxed flag) through the elaborator into M3's psort2_of.
#
# Verifies:
#   * a parametric `enum VBox[A: VType]` (param sorted VType) instantiated at a NON-linear type
#     (`VBox[Int]` — vtype superset of type, so Int is accepted) + a `match` -> nerror=0,
#   * a PLAIN `enum PBox[A]` (default Type sort, the regression-equality case — byte-identical
#     to before this slice) instantiated at `PBox[Int]` + a `match` -> nerror=0.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse ->
# elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the
# M3 driver bundle (reusing build-m3.sh's compile+link), then for each
# frontend/TEST/m5b6b/*.py assert `nerror (after tread3a) = 0`.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-m5b6b.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-m5b6b.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/m5b6b"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the M5b.6b param-sort lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/m5b6b-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — M5b.6b cannot proceed (see BUILD/m5b6b-driverbuild.log)" >&2
    tail -30 "$BUILD/m5b6b-driverbuild.log" >&2
    exit 1
  fi
  # build-m3.sh also runs its own 4a/4b — surface their verdict (M5b.6b must not regress M3).
  if ! grep -q ">> M3: PASS" "$BUILD/m5b6b-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — M5b.6b would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/m5b6b-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the M5b.6b param-sort lowering + typecheck over frontend/TEST/m5b6b/*.py"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "m5b_vtype_param" # enum VBox[A: VType]{VWrap(A)} + unwrapv(b: VBox[Int]) -> Int : match (VType param)
  "m5b_plain_param" # enum PBox[A]{PWrap(A)}        + unwrapp(b: PBox[Int]) -> Int : match (plain param)
)
for base in "${VALID[@]}"; do
  py="$TESTDIR/${base}.py"
  echo "----------------------------------------------------------------------"
  echo ">> [valid] $py"
  if [ ! -f "$py" ]; then echo "!! missing $py" >&2; FAIL=1; continue; fi
  echo "-- source --"; cat "$py"
  n="$(nerror_of "$py")"
  echo ">> nerror (after tread3a) = ${n:-<none>}"
  if [ "${n:-X}" = "0" ]; then
    echo ">> PASS  ($base LOWERS + TYPECHECKS, nerror=0)"
  else
    echo "!! FAIL  ($base expected nerror=0; got ${n:-<none>})" >&2
    echo "-- f3perr0 diagnostics (stock reporter) --" >&2
    $NODE "$BUNDLE" "$py" 2>&1 | grep -E "F3PERR0-ERROR" | head -8 >&2
    FAIL=1
  fi
done

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> M5b6b: FAIL (see failures above)"; exit 1; fi
echo ">> M5b6b: PASS (a VType-sorted param ([A: VType]) selects the_sort2_vwtp s2var sort and"
echo "            instantiates at a non-linear Int (vtype superset of type) -> nerror=0; a plain"
echo "            [A] still defaults to the_sort2_type -> nerror=0, byte-identical to before)"
exit 0
