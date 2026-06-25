#!/usr/bin/env bash
########################################################################
# DEP2 (dataprop/dataview as @decorators on a plain `enum`) — the
# DECORATOR REWORK (slice 2) of the proof/view datatype surface:
#
#   @prop enum LE[...]: case ...   (was `dataprop LE[...]: ...`)  -> PCCdata w/ PCMprop
#   @view enum LEv[...]: case ...  (was `dataview LEv[...]: ...`) -> PCCdata w/ PCMview
#
# The @prop / @view decorator on a plain `enum` selects the datatype's RESULT sort
# (the_sort2_prop / the_sort2_view) — the SAME PCCdata lowering pipeline the old
# `dataprop`/`dataview` keywords used (DEP-spike P4/P9), just driven from a decorator.
#
# What this proves (each fixture nerror=0):
#   * dp_prop.pdats  — `@prop enum LE[m: SInt, n: SInt]` (LErefl / LEstep(LE[m,n])) + a
#                      `def le_use(p: LE[0, 1]) -> LE[0, 1]` (a PROP datatype, prop-sort) typechecks.
#   * dp_view.pdats  — `@view enum LEv[m: SInt, n: SInt]` (LEvrefl / LEvstep) + a def over
#                      `LEv[0, 1]` (a VIEW datatype, view-sort) typechecks.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats). Modeled on build-dep.sh.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-dep2.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-dep2.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/dep2"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the @prop/@view enum lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/dep2-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — DEP2 cannot proceed (see BUILD/dep2-driverbuild.log)" >&2
    tail -40 "$BUILD/dep2-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/dep2-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — DEP2 would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/dep2-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the @prop/@view enum lowering + typecheck over frontend/TEST/dep2/*.pdats"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "dp_prop"          # @prop enum LE[m: SInt, n: SInt] + def le_use(p: LE[0,1]) -> LE[0,1]   (PROP datatype)
  "dp_view"          # @view enum LEv[m: SInt, n: SInt] + def lev_use(p: LEv[0,1]) -> LEv[0,1] (VIEW datatype)
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
if [ "$FAIL" -ne 0 ]; then echo ">> DEP2: FAIL (see failures above)"; exit 1; fi
echo ">> DEP2: PASS (@prop enum / @view enum — the dataprop/dataview DECORATOR REWORK — lower"
echo "           through the SAME PCCdata pipeline carrying the PROP/VIEW mode (the_sort2_prop /"
echo "           the_sort2_view) and typecheck structurally, nerror=0.)"
exit 0
