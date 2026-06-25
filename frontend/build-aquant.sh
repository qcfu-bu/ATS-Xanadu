#!/usr/bin/env bash
########################################################################
# A-QUANT (explicit-quantifier SURFACE) — `forall`/`exists` EXPLICIT
# quantifiers inside types, EXISTENTIAL result types, and SUBSET sorts
# (`@sort type Nat = {a: SInt | a >= 0}`), wired through the real frontend
# pipeline + TYPECHECKED.
#
# What this proves (each fixture nerror=0):
#   * aq_exists.pdats — `def some_vec[A](x: A) -> exists[m: SInt] Vec[A, m]` (an EXPLICIT
#                       EXISTENTIAL result type, s2exp_exi0) typechecks.
#   * aq_forall.pdats — `def apply[A](f: forall[n: SInt] (Vec[A, n]) -> SInt) -> SInt` (an
#                       EXPLICIT UNIVERSAL function-type argument, s2exp_uni0) typechecks.
#   * aq_subset.pdats — `@sort type Nat = {a: SInt | a >= 0}` (a SUBSET sort, S2TEXsub) + a use
#                       `def f[n: Nat](x: SInt[n]) -> SInt` (Nat resolved as a sort) typecheck.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse -> elab ->
# lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the M3 driver
# bundle (reusing build-m3.sh), then for each frontend/TEST/aquant/*.pdats assert
# `nerror (after tread3a) = 0`.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-aquant.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-aquant.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/aquant"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the A-QUANT lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/aquant-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — A-QUANT cannot proceed (see BUILD/aquant-driverbuild.log)" >&2
    tail -40 "$BUILD/aquant-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/aquant-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — A-QUANT would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/aquant-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the A-QUANT lowering + typecheck over frontend/TEST/aquant/*.pdats"
########################################################################
FAIL=0

nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

VALID=(
  "aq_exists"   # def some_vec[A](x: A) -> exists[m: SInt] Vec[A, m]   (EXISTENTIAL, s2exp_exi0)
  "aq_forall"   # def apply[A](f: forall[n: SInt] (Vec[A, n]) -> SInt) -> SInt  (UNIVERSAL, s2exp_uni0)
  "aq_subset"   # @sort type Nat = {a: SInt | a >= 0} + def f[n: Nat](x: SInt[n]) -> SInt  (S2TEXsub)
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
if [ "$FAIL" -ne 0 ]; then echo ">> A-QUANT: FAIL (see failures above)"; exit 1; fi
echo ">> A-QUANT: PASS (explicit forall/exists quantifiers in types, EXISTENTIAL result"
echo "             types (s2exp_exi0), and SUBSET sorts (@sort type Nat = {a | g}, S2TEXsub)"
echo "             all lower + typecheck structurally, nerror=0. Index/guard obligations are"
echo "             not solver-checked — same as stock past stpize.)"
exit 0
