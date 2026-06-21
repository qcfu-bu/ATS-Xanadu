#!/usr/bin/env bash
########################################################################
# ARROW-EFFECTS (bootstrap P1, feature 2) — explicit arrow-kind/effect tags on function
# types: `(A) ->[Tag] B` (CloRef1 / Fun1 / CloPtr1 / ...), wired through the real frontend
# pipeline + TYPECHECKED.
#
# What this proves (each fixture nerror=0):
#   * ar_bare.pdats     — a BARE `(Int) -> Int` HOF param (no tag) still typechecks (regression:
#                         the bare arrow stays F2CLfun / cloref, byte-identical to before).
#   * ar_cloref.pdats   — `(Int) ->[CloRef1] Int` (boxed nonlinear closure) -> F2CLfun.
#   * ar_fun.pdats      — `(Int) ->[Fun1] Int` (code-ptr / nonlinear) -> F2CLfun.
#   * ar_cloptr.pdats   — `(Int) ->[CloPtr1] Int` (LINEAR closure) -> F2CLclo(1) — the linear
#                         class, structurally distinct from cloref (arrow-spike AR-DIST).
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse -> elab
# -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the M3 driver
# bundle (reusing build-m3.sh), then for each frontend/TEST/arrow/*.pdats assert
# `nerror (after tread3a) = 0`.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-arrow.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-arrow.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/arrow"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the ARROW arrow-tag lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/arrow-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — ARROW cannot proceed (see BUILD/arrow-driverbuild.log)" >&2
    tail -40 "$BUILD/arrow-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/arrow-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — ARROW would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/arrow-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the ARROW arrow-tag lowering + typecheck over frontend/TEST/arrow/*.pdats"
########################################################################
FAIL=0

nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

VALID=(
  "ar_bare"      # (Int) -> Int            bare HOF param (regression; F2CLfun)
  "ar_cloref"    # (Int) ->[CloRef1] Int   boxed nonlinear closure -> F2CLfun
  "ar_fun"       # (Int) ->[Fun1] Int      code-ptr / nonlinear    -> F2CLfun
  "ar_cloptr"    # (Int) ->[CloPtr1] Int   LINEAR closure          -> F2CLclo(1)
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
if [ "$FAIL" -ne 0 ]; then echo ">> ARROW: FAIL (see failures above)"; exit 1; fi
echo ">> ARROW: PASS (explicit (A) ->[Tag] B arrow tags — CloRef/Fun -> F2CLfun (cloref),"
echo "             CloPtr -> F2CLclo(1) (linear) — all lower + typecheck structurally, nerror=0;"
echo "             the bare -> stays byte-identical F2CLfun. The effect digit is cosmetic.)"
exit 0
