#!/usr/bin/env bash
########################################################################
# M4 — Python-surface frontend: CONTROL-FLOW & DATA lowering (PyCore -> L2).
#
# M4 exit (R1.5 — CODEGEN IS PARKED): LOWER + TYPECHECK + DIAGNOSTICS-ON-PYTHON-SPANS.
# Verified via the SAME M3 driver path (frontend/DATS/pyfront_m3.dats): build the M3 driver
# bundle (reusing build-m3.sh's compile+link), then for each frontend/TEST/m4/*.py:
#   - VALID programs LOWER + TYPECHECK -> assert `nerror=0` (after tread3a, which the driver
#     runs internally before reporting). We do NOT run JS for these (arithmetic/function
#     codegen is BLOCKED by the two pre-existing backend-infra blockers; M3-REPORT §6.1).
#   - the INVALID program -> assert a diagnostic on the EXACT .py span (file + line:col).
#
# Constructs covered (all nerror=0): `match` on literals/tuples/wildcards INCLUDING a guarded
# arm; `if/elif/else`; tuples; record + field. Operator-dependent guards/conditions, list
# literals, and loops are DEFERRED (blocked by the operator `$`-template gap + pyrt staloading;
# see frontend/docs/M4-REPORT.md §"Deferred"). The for-loop fast-path #14 fix + its golden are
# verified by build-m2_5.sh (TEST/m2_5/m25_for_break.golden — a single-acc `for` with `break`
# routes through the iterator/flow path, NOT list_foldleft).
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-m4.sh                 # (re)build the M3 driver + run + verify M4 tests
#   bash frontend/build-m4.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/m4"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the M4 lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/m4-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — M4 cannot proceed (see BUILD/m4-driverbuild.log)" >&2
    tail -30 "$BUILD/m4-driverbuild.log" >&2
    exit 1
  fi
  # build-m3.sh also runs its own 4a/4b — surface their verdict (M4 must not regress M3).
  if ! grep -q ">> M3: PASS" "$BUILD/m4-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — M4 would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/m4-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the M4 lowering + typecheck over frontend/TEST/m4/*.py"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "m4_match"        # match: int literal arm + a GUARDED arm (bool guard, D2GPTgua) + wildcard
  "m4_match_tuple"  # match on a TUPLE pattern (literal + binder components)
  "m4_if"           # if / elif / else as a value (nested D2Eift0)
  "m4_tuple"        # tuple literals (D2Etup0) bound to untyped lets
  "m4_record"       # record literal (D2Ercd2) + field projection (D2Eproj)
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
    $NODE "$BUNDLE" "$py" 2>&1 | grep -E "F3PERR0-ERROR.*${base}" | head -3 >&2
    FAIL=1
  fi
done

# ---- INVALID program: a non-bool guard -> diagnostic on the EXACT .py span ---
# `case x if 7:` — the guard `7` is checked against `bool` (trans23_d2gua), so the type error
# lands on the `7` token's span. Assert (a) nerror>0, (b) the diagnostic cites the .py file with
# a line:col span, AND (c) it points at the guard expression on line 2.
echo "----------------------------------------------------------------------"
E_PY="$TESTDIR/m4_typeerr.py"
echo ">> [invalid] $E_PY  (non-bool guard -> diagnostic on the .py span)"
echo "-- source --"; cat "$E_PY"
EOUT="$($NODE "$BUNDLE" "$E_PY" 2>&1)"
EN="$(echo "$EOUT" | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1)"
echo ">> nerror (after tread3a) = ${EN:-<none>}"
echo "-- the f3perr0 diagnostic on the .py span --"
echo "$EOUT" | grep -oE "m4_typeerr\.py\)@\([0-9]+\(line=[0-9]+,offs=[0-9]+\)--[0-9]+\(line=[0-9]+,offs=[0-9]+\)" | head -2
if [ "${EN:-0}" != "0" ] \
   && echo "$EOUT" | grep -Eq "F3PERR0-ERROR:LCSRCsome1\([^)]*m4_typeerr\.py\)@\([0-9]+\(line=[0-9]+" \
   && echo "$EOUT" | grep -Eq "m4_typeerr\.py\)@\([0-9]+\(line=2,offs=15\)"; then
  echo ">> PASS  (type error on the guard '7' at m4_typeerr.py line=2,offs=15 with a line:col span)"
else
  echo "!! FAIL  (expected nerror>0 + a diagnostic citing m4_typeerr.py line 2 with a line=/offs= span)" >&2
  FAIL=1
fi

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> M4: FAIL (see failures above)"; exit 1; fi
echo ">> M4: PASS (match incl. guarded arm + if/elif/else + tuple + record/field LOWER + TYPECHECK"
echo "           nerror=0; the invalid guard reports a diagnostic on its exact .py span)"
exit 0
