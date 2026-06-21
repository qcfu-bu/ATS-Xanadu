#!/usr/bin/env bash
########################################################################
# TAIL (bootstrap P1, feature 6) — the remaining surface backlog from
# two real-file round-trips. WIRED items get a fixture proving nerror=0
# through the real frontend pipeline; DEFERRED items get a note (no fixture).
#
# Per-item verdict (see frontend/docs/BOOTSTRAP-PLAN.md "Reality check"):
#   ITEM 1 (abstract-bound `<= REP`)  — WIRED      -> tl_abstract_bound.pdats
#   ITEM 2 (`#define` const)          — ALREADY-COVERED (plain `let NAME=v`) -> tl_define_const.pdats
#   ITEM 3 (`$`-in-ident foo$bar)     — WIRED-VERDICT (collisions force preserving `$`; lexer task)
#   ITEM 4 (qualified `M.x`/`$M.x`)   — DEFERRED (bare-name `$.` fall-through covers corpus)
#   ITEM 5 (`#include` textual splice)— DEFERRED (shared-scope splice = driver concern; HATS glue)
#
# This script verifies the two WIRED-with-fixture items (1 + the ALREADY-COVERED confirmation 2):
#   * tl_abstract_bound.pdats — `@abstract type Stamp <= Int` + an @extern producer + a use; the
#                               `<= REP` rep lowers to A2TDFlteq (codegen-only) and opacity holds
#                               at typecheck -> nerror=0.
#   * tl_define_const.pdats    — named int constants (`let KINFIXL = 1`, hex bit-flags) USED in
#                               dynamic arithmetic + a comparison (the `#define`-const shape) ->
#                               nerror=0 (proves the plain `let` path already covers the corpus use).
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse -> elab ->
# lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the M3 driver
# bundle (reusing build-m3.sh's compile+link), then for each frontend/TEST/tail/*.pdats assert
# `nerror (after tread3a) = 0`.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-tail.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-tail.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/tail"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the TAIL abstract-bound + const lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/tail-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — TAIL cannot proceed (see BUILD/tail-driverbuild.log)" >&2
    tail -40 "$BUILD/tail-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/tail-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — TAIL would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/tail-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the TAIL lowering + typecheck over frontend/TEST/tail/*.pdats"
########################################################################
FAIL=0

nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

VALID=(
  "tl_abstract_bound"   # @abstract type Stamp <= Int + @extern producer + use  (A2TDFlteq rep)
  "tl_define_const"     # let KINFIXL=1 / hex bit-flags USED in dynamic arithmetic + comparison
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
if [ "$FAIL" -ne 0 ]; then echo ">> TAIL: FAIL (see failures above)"; exit 1; fi
echo ">> TAIL: PASS (abstract-type rep bound `@abstract type Stamp <= Int` carries A2TDFlteq +"
echo "            typechecks opaque; `#define`-as-const modeled by plain `let NAME = value` used"
echo "            in dynamic arithmetic/comparison; both nerror=0. ITEMS 3/4/5 verdicts in"
echo "            the report (WIRE-verdict / DEFER).)"
exit 0
