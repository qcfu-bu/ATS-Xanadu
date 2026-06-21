#!/usr/bin/env bash
########################################################################
# VAR — Python-surface frontend: REAL var/mutation (aliasable mutable CELLS) toward
# ATS parity. DISTINCT from `let mut` (functional SSA rebinding):
#
#   var NAME [: T] = e   -> PCEvarcell -> a D2Cvardclst (d2vardcl_make_args, vpid=None)
#                           wrapped in D2Elet0 over the rest. A real in-place cell — NOT a
#                           loop accumulator (it never enters the loop `muts`/`accs` set).
#   lvalue := e          -> PCEassign  -> L2 D2Eassgn (typecheck checks rval vs lval's type,
#                           returns void). DISTINCT from `=` (the SSA-reassign path).
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse ->
# elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the
# M3 driver bundle (reusing build-m3.sh's compile+link), then for each frontend/TEST/var/*.pdats
# assert `nerror (after tread3a) = 0`.
#
# Fixtures:
#   var_basic.pdats : var x = 0 ; x := 10 ; x                          (straight-line, inferred)
#   var_typed.pdats : var x: Int = 0 ; x := 5 ; let y = x ; y          (typed + cell read)
#   var_loop.pdats  : var s,i ; while i<n: s := s+i ; i := i+1 ; s      (var mutated IN a loop)
#
# The KEY interaction is var_loop: the cells s,i are captured by the desugared tail-recursive
# loop closure and mutated IN PLACE (D2Eassgn) — NOT threaded as loop accumulators. SPIKE GO.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-var.sh                 # (re)build the M3 driver + run + verify VAR tests
#   bash frontend/build-var.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/var"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the var/:= lowerings ride the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/var-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — VAR cannot proceed (see BUILD/var-driverbuild.log)" >&2
    tail -40 "$BUILD/var-driverbuild.log" >&2
    exit 1
  fi
  # build-m3.sh also runs its own 4a/4b — surface their verdict (VAR must not regress M3).
  if ! grep -q ">> M3: PASS" "$BUILD/var-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — VAR would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/var-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the var/:= lowering + typecheck over frontend/TEST/var/*.pdats"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "var_basic"   # var x = 0 ; x := 10 ; x                    (straight-line, inferred type)
  "var_typed"   # var x: Int = 0 ; x := 5 ; let y = x ; y    (typed cell + read into a let)
  "var_loop"    # var s,i ; while i<n: s:=s+i ; i:=i+1 ; s    (var mutated INSIDE a loop)
)
for base in "${VALID[@]}"; do
  py="$TESTDIR/${base}.pdats"
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
if [ "$FAIL" -ne 0 ]; then echo ">> VAR: FAIL (see failures above)"; exit 1; fi
echo ">> VAR: PASS (var NAME [:T] = e -> D2Cvardclst, and lvalue := e -> D2Eassgn — all"
echo "            LOWER + TYPECHECK nerror=0, incl. a var captured+mutated inside a loop)"
exit 0
