#!/usr/bin/env bash
########################################################################
# M5b.3b — Python-surface frontend: PARAMETRIC (generic) datatype / struct / type-alias
# lowering + TYPECHECK.
#
# Slice 3b (the parametric delta on the monomorphic M5b.3 / M5b.4/.5 recipes): a parametric
#   * `enum Opt[A]`  lowers to a D2Cdatatype whose type s2cst has a FUNCTION sort
#     (type)->tbox, whose cons are quantified {A} (in the d2con tqas) with result `Opt(A)`,
#   * `struct Pair[A,B]` / `type Box[A] = ...` lower to a D2Csexpdef wrapped in s2exp_lam1,
# so an INSTANTIATED use (`Opt[Int]`, `Pair[Int,Int]`, `Box[Int]`) typechecks end-to-end:
#   * a parametric enum + a `match` (binding `x` at the instantiated param) -> nerror=0,
#   * a parametric struct field projection `p.fst` through the lam'd alias -> nerror=0,
#   * a parametric alias instantiated at Int -> nerror=0,
#   * a self-recursive parametric enum (`Node(A, Tree[A])`) resolving through the registered
#     s2cst -> nerror=0.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse ->
# elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the
# M3 driver bundle (reusing build-m3.sh's compile+link), then for each
# frontend/TEST/m5b3b/*.py assert `nerror (after tread3a) = 0`.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-m5b3b.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-m5b3b.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/m5b3b"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the M5b.3b parametric lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/m5b3b-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — M5b.3b cannot proceed (see BUILD/m5b3b-driverbuild.log)" >&2
    tail -30 "$BUILD/m5b3b-driverbuild.log" >&2
    exit 1
  fi
  # build-m3.sh also runs its own 4a/4b — surface their verdict (M5b.3b must not regress M3).
  if ! grep -q ">> M3: PASS" "$BUILD/m5b3b-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — M5b.3b would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/m5b3b-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the M5b.3b parametric lowering + typecheck over frontend/TEST/m5b3b/*.py"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "m5b_opt"        # enum Opt[A]{Nothing,Just(A)} + unwrap(o: Opt[Int]) -> Int : match  (param datatype)
  "m5b_pair"       # struct Pair[A,B]{fst:A,snd:B} + first(p: Pair[Int,Int]) -> Int : p.fst (param struct)
  "m5b_alias_gen"  # type Box[A] = List[A] + size(b: Box[Int]) -> Int : 0            (param alias)
  "m5b_tree"       # enum Tree[A]{Leaf,Node(A,Tree[A])} + root(t: Tree[Int]) : match  (SELF-recursive param)
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
if [ "$FAIL" -ne 0 ]; then echo ">> M5b3b: FAIL (see failures above)"; exit 1; fi
echo ">> M5b3b: PASS (parametric enum (D2Cdatatype, FUNCTION sort + per-con tqas), parametric"
echo "            struct/alias (D2Csexpdef + s2exp_lam1), instantiated uses (Opt[Int],"
echo "            Pair[Int,Int], Box[Int]) + a self-recursive param enum all LOWER + TYPECHECK"
echo "            nerror=0; monomorphic paths unchanged)"
exit 0
