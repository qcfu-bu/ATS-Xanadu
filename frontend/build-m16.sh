#!/usr/bin/env bash
########################################################################
# M16 — DESUGARED LOOPS + LIST LITERALS LOWER + TYPECHECK at nerror=0.
#
# Proves the M16 success criterion: with `pyrt` (the flow datatype + iterator protocol +
# list_foldleft + range) LOADED into the global env at driver startup (via the stock loader
# filpath_pvsload, mirroring how the_tr12env_pvsl00d loads the prelude), the desugared loops'
# pyrt names RESOLVE via the ordinary tr12env GLOBAL fall-through, and the loops + list literals
# LOWER + TYPECHECK to nerror=0:
#
#   * pyrt resolution : `flow_next`/`flow_break` (flow ctors), `range` (a typed d2cst), and
#                       `list_foldleft` (via the for-loop) all RESOLVE (no unbound errck).
#   * while loop      : a pure (no break/continue/return) `while` -> a plain recursive `loop`.
#   * for loop        : `for x in <list>` (list_foldleft fast path) + `for i in range(...)`.
#   * list literals   : `[1, 2, 3]` -> the prelude list_cons/list_nil chain.
#
# THE M16 WIRING (two purely-additive frontend changes — see frontend/docs/M16-REPORT.md):
#   (a) the driver (pyfront_m3.dats) calls `filpath_pvsload(0, "/frontend/pyrt/pyrt.sats")` ONCE
#       at startup (after the prelude bootstrap), loading the pyrt INTERFACE into the global env.
#       The .sats (NOT the .dats) is loaded because a `.sats` `fun` is a typed d2cst CONSTANT
#       (resolves + type-checks at the call site), whereas a `.dats` `fun foo(...) = ...` binds a
#       local function d2var with no exported type (errcks on use).
#   (b) the list-literal lowering (pylower_dynexp.dats pl_list) wraps the empty list `[]` in a
#       zero-arg application D2Edap0(list_nil) — the bare constructor is a function value and
#       errcks against the expected list type.
#
# Operators in loop BODIES resolve via #13a (the L2 post-passes trans2a/trsym2b/t2read0) WHEN the
# operands have a concrete type: the for loop's list_foldleft typed signature `(a,x)->a` constrains
# the folder, so `acc + x` resolves; a while/for comparison against a literal (`acc < 5`) resolves.
# An operator with BOTH operands untyped loop-vars (e.g. `acc + i` over two plain accumulators in a
# while) is the pre-existing overload-needs-concrete-types gap (M4-REPORT) — DEFERRED, not pyrt.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats) as M4/M13a: build (or reuse) the M3
# driver bundle, then for each frontend/TEST/m16/*.py assert nerror=0 (after tread3a, which the
# driver runs before reporting). Codegen stays PARKED (#13b) — this verifies LOWER + TYPECHECK only.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-m16.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-m16.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/m16"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the M16 loop/list typecheck rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/m16-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — M16 cannot proceed (see BUILD/m16-driverbuild.log)" >&2
    tail -30 "$BUILD/m16-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/m16-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — M16 would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/m16-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the M16 loop/list typecheck over frontend/TEST/m16/*.py"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- each must LOWER + TYPECHECK to nerror=0 (pyrt resolved; loops/list lowered) -------------
VALID=(
  "m16_pyrt"       # pyrt names RESOLVE: flow_next/flow_break (ctors) + range (typed d2cst)
  "m16_while"      # pure `while acc < 5: acc = 9` -> a plain recursive loop, nerror=0
  "m16_for"        # `for x in [1,2,3]: acc = acc + x` -> list_foldleft fast path, nerror=0
  "m16_for_range"  # `for i in range(0,5): acc = acc + i` -> range + list_foldleft, nerror=0
  "m16_list"       # `[1, 2, 3]` list literals -> list_cons/list_nil chain, nerror=0
)
for base in "${VALID[@]}"; do
  py="$TESTDIR/${base}.py"
  echo "----------------------------------------------------------------------"
  echo ">> [valid] $py"
  if [ ! -f "$py" ]; then echo "!! missing $py" >&2; FAIL=1; continue; fi
  echo "-- source --"; cat "$py"
  # show the pyrt-load markers once (proves the pyrt-resolution wiring fired).
  if [ "$base" = "m16_pyrt" ]; then
    echo "-- pyrt-load markers --"
    $NODE "$BUNDLE" "$py" 2>&1 | grep -E "\[m16\]" | head -2
  fi
  n="$(nerror_of "$py")"
  echo ">> nerror (after tread3a) = ${n:-<none>}"
  if [ "${n:-X}" = "0" ]; then
    echo ">> PASS  ($base LOWERS + TYPECHECKS, nerror=0)"
  else
    echo "!! FAIL  ($base expected nerror=0; got ${n:-<none>})" >&2
    $NODE "$BUNDLE" "$py" 2>&1 | grep -E "F.PERR0-ERROR.*${base}" | head -5 >&2
    FAIL=1
  fi
done

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> M16: FAIL (see failures above)"; exit 1; fi
echo ">> M16: PASS (pyrt RESOLVES via filpath_pvsload; while + for(list/range) loops + list"
echo "            literals LOWER + TYPECHECK at nerror=0 — the desugared loops are unblocked)"
exit 0
