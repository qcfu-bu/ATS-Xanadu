#!/usr/bin/env bash
########################################################################
# B-LINEAR (Area B — linear / view / pointer SURFACE) — at-views, linear-consume
# patterns, address-of / dereference, and move / swap, wired through the real
# frontend pipeline + TYPECHECKED.
#
# What this proves (each fixture nerror=0):
#   * b_atview.pdats   — a def `keep[A, l: Addr](pf: A at l, p: ptr[l]) -> ptr[l]` whose FIRST
#                        (proof) param is annotated with the AT-VIEW `A at l` (-> S2Eatx2). The
#                        body returns the pointer. (SPIKE BL-AT2-proven the at-view s2exp rides
#                        clean as a proof param. NB: a `!p` deref of a BARE ptr[l] is NO-GO — it
#                        needs the absent view solver to recover the element type; DEFERRED.)
#   * b_linpat.pdats   — a `@linear enum LList[A]` + a `match` consuming each arm via `~LNil` /
#                        `~LCons(x, rest)` (the LINEAR-CONSUME `~p` -> D2Pfree). (SPIKE BL-LIN.)
#   * b_ptr.pdats      — `&x` ADDRESS-OF (-> D2Eaddr) + `!p` DEREFERENCE (-> D2Eeval) on the
#                        element-typed pointer `&x` makes. (SPIKE BL-ADDR + BL-DERF2.)
#   * b_moveswap.pdats — `var` cells + MOVE `x :=> y` (-> D2Exazgn) + SWAP `x :=: y` (-> D2Exchng).
#                        (SPIKE BL-MV + BL-SW.)
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse -> elab ->
# lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the M3 driver
# bundle (reusing build-m3.sh's compile+link), then for each frontend/TEST/blin/*.pdats assert
# `nerror (after tread3a) = 0`.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-blin.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-blin.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/blin"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the B-LINEAR lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/blin-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — B-LINEAR cannot proceed (see BUILD/blin-driverbuild.log)" >&2
    tail -40 "$BUILD/blin-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/blin-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — B-LINEAR would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/blin-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the B-LINEAR lowering + typecheck over frontend/TEST/blin/*.pdats"
########################################################################
FAIL=0

nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

VALID=(
  "b_atview"     # keep[A, l: Addr](pf: A at l, p: ptr[l]) -> ptr[l]   (AT-VIEW proof param)
  "b_linpat"     # @linear enum LList + match ~LNil / ~LCons(x, rest)  (LINEAR-CONSUME ~p)
  "b_ptr"        # &x address-of + !p deref of an element-typed ptr
  "b_moveswap"   # var cells + x :=> y move + x :=: y swap
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
if [ "$FAIL" -ne 0 ]; then echo ">> B-LINEAR: FAIL (see failures above)"; exit 1; fi
echo ">> B-LINEAR: PASS (at-views 'A at l' (S2Eatx2), linear-consume patterns '~p' (D2Pfree),"
echo "           address-of '&x' (D2Eaddr) + dereference '!p' (D2Eeval), and move 'x :=> y'"
echo "           (D2Exazgn) / swap 'x :=: y' (D2Exchng) all lower + typecheck structurally,"
echo "           nerror=0. The view/linear obligations are not solver-checked — same as stock.)"
exit 0
