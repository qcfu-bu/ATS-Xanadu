#!/usr/bin/env bash
########################################################################
# #13a SPIKE — OPERATOR RESOLUTION: arithmetic + comparison TYPECHECK.
#
# Proves the spike's success criterion: with the three L2 post-passes
# (d2parsed_of_trans2a -> d2parsed_by_trsym2b -> d2parsed_of_t2read0) now
# run BEFORE d3parsed_of_trans23 in the pyfront driver (mirroring the stock
# trans03_from_fpath:87-92), an OPERATOR-bearing program resolves its
# overload symbols (D2ITMsym -> concrete d2cst) and TYPECHECKS at nerror=0.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats) as M4/M3:
# build (or reuse) the M3 driver bundle, then for each frontend/TEST/m13a/*.py
# assert it LOWERS + TYPECHECKS to nerror=0 (after tread3a, which the driver
# runs internally before reporting). Codegen stays PARKED (the operator
# $-template backend gap, M3-REPORT) — this verifies the FRONTEND typecheck.
#
# Before this spike, the same program errcked (the operator head lowered to
# D3Edapp(D3Enone0()) — the unresolved overload; see frontend/docs/M13a-REPORT.md).
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-m13a.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-m13a.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/m13a"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the #13a operator typecheck rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/m13a-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — #13a cannot proceed (see BUILD/m13a-driverbuild.log)" >&2
    tail -30 "$BUILD/m13a-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/m13a-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — #13a would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/m13a-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the #13a operator typecheck over frontend/TEST/m13a/*.py"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- each must LOWER + TYPECHECK with operators RESOLVED -> nerror=0 ----------
VALID=(
  "m13a_arith"   # `let a = 1 + 2` / `let b = a < 5`  (arithmetic + comparison operators)
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
    echo ">> PASS  ($base LOWERS + TYPECHECKS with operators RESOLVED, nerror=0)"
  else
    echo "!! FAIL  ($base expected nerror=0; got ${n:-<none>})" >&2
    $NODE "$BUNDLE" "$py" 2>&1 | grep -E "F3PERR0-ERROR.*${base}" | head -5 >&2
    FAIL=1
  fi
done

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> #13a: FAIL (see failures above)"; exit 1; fi
echo ">> #13a: PASS (arithmetic + comparison operators RESOLVE + TYPECHECK at nerror=0 —"
echo "             the three L2 post-passes unblock operators for a clean LSP)"
exit 0
