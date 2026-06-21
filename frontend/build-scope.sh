#!/usr/bin/env bash
########################################################################
# SCOPING SURFACE (bootstrap P1, feature 1) — the `where:` block and the
# `private` keyword, wired through the real frontend pipeline + TYPECHECKED.
#
# What this proves (each fixture nerror=0):
#   * sc_where.pdats          — `def fact(n) = go(n,1) where: def go(k,acc) = ...`
#                               the where-decls are BACKWARDS-scoped around the body
#                               (ATS `e where {decls}` -> D2Ewhere). The body calls a
#                               where-defined helper. SPIKE-PROVEN (S1).
#   * sc_private_block.pdats  — a `private:` block of helpers + a public def using them.
#                               capture-rest: privates = local-head D1, the following
#                               publics = local-body D2 of ONE D2Clocal0. SPIKE-PROVEN (S2).
#   * sc_private_mod.pdats     — a single `private def helper` MODIFIER + a public user.
#   * sc_where_private.pdats   — a def with BOTH a `where:` block AND sitting after a
#                                `private` decl (interaction sanity; both scopings coexist).
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse ->
# elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the
# M3 driver bundle (reusing build-m3.sh's compile+link), then for each
# frontend/TEST/scope/*.pdats assert `nerror (after tread3a) = 0`.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-scope.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-scope.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/scope"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the SCOPING lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/scope-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — SCOPING cannot proceed (see BUILD/scope-driverbuild.log)" >&2
    tail -40 "$BUILD/scope-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/scope-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — SCOPING would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/scope-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the SCOPING lowering + typecheck over frontend/TEST/scope/*.pdats"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "sc_where"          # def fact(n) = go(n,1) where: def go(k,acc) = ...   (D2Ewhere)
  "sc_private_block"  # private: { add1, dbl } ; def combine uses them      (D2Clocal0 capture-rest)
  "sc_private_mod"    # private def helper ; def public_use uses it         (D2Clocal0, 1-elem run)
  "sc_where_private"  # private def base ; def compute(...) where: def step (both scopings)
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
if [ "$FAIL" -ne 0 ]; then echo ">> SCOPE: FAIL (see failures above)"; exit 1; fi
echo ">> SCOPE: PASS (the where: block (D2Ewhere, backwards-scoped) + the private"
echo "            keyword (modifier + block; D2Clocal0 capture-rest) all lower +"
echo "            typecheck structurally, nerror=0.)"
exit 0
