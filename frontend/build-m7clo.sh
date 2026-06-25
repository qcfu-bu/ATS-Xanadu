#!/usr/bin/env bash
########################################################################
# M7clo — @func non-capturing-lambda CHECK (uniform-cloref default).
#
# The surface default is "uniform cloref": every lambda is a CAPTURING first-class closure
# (ATS-Xanadu's F2CLfun / CXFREF is already a non-linear GC'd closure, so a capturing lambda
# that escapes already typechecks — verified by the spike). `@func` opts a lambda into being
# NON-capturing, ENFORCED by a FRONTEND free-variable/capture check in the elaborator: a
# `@func (params) => body` lambda may reference only its own params + inner-bound names + MODULE/
# global/imported/prelude names; referencing an ENCLOSING FUNCTION-LOCAL is an error.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats: lex -> parse -> elab -> lower ->
# trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a). Build the M3 driver bundle (reusing
# build-m3.sh's compile+link), then for each frontend/TEST/m7clo/* assert the expected verdict.
#
# Fixtures:
#   m7clo_ok.pdats      : a @func lambda that captures NOTHING -> nerror=0.
#   m7clo_capture.pdats : a @func lambda that captures enclosing local `n` -> nerror>0 + the
#                         capture diagnostic on the .pdats span (the check works).
#   m7clo_default.pdats : the SAME capturing body WITHOUT @func -> nerror=0 (the default cloref
#                         captures fine; @func is the ONLY thing that rejects the capture).
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-m7clo.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-m7clo.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/m7clo"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the @func capture check rides the M3 elaborate->lower pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/m7clo-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — M7clo cannot proceed (see BUILD/m7clo-driverbuild.log)" >&2
    tail -30 "$BUILD/m7clo-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/m7clo-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — M7clo would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/m7clo-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the @func capture check over frontend/TEST/m7clo/*.pdats"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID @func (no capture): nerror=0 ------------------------------------
run_valid() {
  local base="$1" why="$2"
  local py="$TESTDIR/${base}.pdats"
  echo "----------------------------------------------------------------------"
  echo ">> [valid] $py  ($why)"
  if [ ! -f "$py" ]; then echo "!! missing $py" >&2; FAIL=1; return; fi
  echo "-- source --"; cat "$py"
  local n; n="$(nerror_of "$py")"
  echo ">> nerror (after tread3a) = ${n:-<none>}"
  if [ "${n:-X}" = "0" ]; then
    echo ">> PASS  ($base nerror=0)"
  else
    echo "!! FAIL  ($base expected nerror=0; got ${n:-<none>})" >&2
    $NODE "$BUNDLE" "$py" 2>&1 | grep -E "F3PERR0-ERROR|captures local" | head -8 >&2
    FAIL=1
  fi
}

run_valid m7clo_ok      "@func lambda captures NOTHING"
run_valid m7clo_default "SAME capturing body WITHOUT @func — default cloref captures fine"

# ---- CAPTURING @func: nerror>0 WITH the capture diagnostic ------------------
echo "----------------------------------------------------------------------"
PY="$TESTDIR/m7clo_capture.pdats"
echo ">> [capture-error] $PY  (@func lambda captures enclosing local \`n\` -> MUST error)"
if [ ! -f "$PY" ]; then
  echo "!! missing $PY" >&2; FAIL=1
else
  echo "-- source --"; cat "$PY"
  OUT="$($NODE "$BUNDLE" "$PY" 2>&1)"
  N="$(echo "$OUT" | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1)"
  echo ">> nerror (after tread3a) = ${N:-<none>}"
  echo "-- elaboration diagnostics (the @func capture check) --"
  echo "$OUT" | grep -E "captures local|@func" | head -8
  CAPLINE="$(echo "$OUT" | grep -E "@func lambda captures local" | head -1)"
  if [ "${N:-0}" != "0" ] && [ -n "$CAPLINE" ]; then
    echo ">> PASS  (m7clo_capture nerror>0 AND the capture diagnostic names \`n\` on the span)"
  else
    echo "!! FAIL  (m7clo_capture expected nerror>0 WITH a '@func lambda captures local' diagnostic)" >&2
    echo "         nerror=${N:-<none>}  capline='${CAPLINE:-<none>}'" >&2
    FAIL=1
  fi
fi

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> M7clo: FAIL (see failures above)"; exit 1; fi
echo ">> M7clo: PASS (@func non-capture CHECK works: ok nerror=0, default-cloref nerror=0,"
echo "            and a capturing @func lambda is REJECTED with a capture diagnostic on its span)"
exit 0
