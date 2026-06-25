#!/usr/bin/env bash
########################################################################
# M5a — TYPE-ANNOTATION CARRYING: a typed `def` + a typed loop LOWER + TYPECHECK at nerror=0.
#
# Proves the M5a success criterion: the surface type annotations (PyParam's `: T`, PyCfun's
# `-> T`, PyDlet's `: T`) — which the elaborator USED to DROP (M3-REPORT §4) — are now THREADED
# through PyCore (new optional type fields on PCFundcl / PCElet / PCElam) into L2, so that:
#
#   (a) m5a_def         : `def double(x: Int) -> Int: x + x` -> nerror=0. The typed `x` makes
#                         `x + x` RESOLVE (operators resolve when operands are typed, #13a). The
#                         param type lowers to an annotated f2arg binder (D2Pannot); the return
#                         type to the d2fundcl's s2res.
#   (b) m5a_loop        : `def sum_upto(n: Int) -> Int: let mut acc: Int = 0; let mut i: Int = 0;
#                         while i < n: acc = acc + i; i = i + 1; acc` -> nerror=0. The M16
#                         untyped-loop-var deferral FIXED: the `let mut acc: Int`/`let mut i: Int`
#                         annotations flow into the synthesized loop's accumulator param types, so
#                         `acc + i` (both operands now typed) resolves. (The N-accumulator loop
#                         calling-convention is also corrected — a 2+-acc loop takes ONE tuple
#                         parameter matching its single tuple call argument.)
#   (c) m5a_unannotated : `let x = 1; let y = x` -> nerror=0. Annotations are OPTIONAL — an
#                         unannotated binding/param still lowers exactly as before (types inferred).
#
# THE M5a FIX (purely-additive, frontend-only — see frontend/docs/M5a-REPORT.md):
#   * PyCore (pycore.sats): PCFundcl carries `list(pytypopt)` param types + a `pytypopt` return;
#     PCElet carries the binding annotation; PCElam carries parallel param types.
#   * Elaborator: threads PyParam/PyCfun-return/PyDlet annotations into those fields; for loops,
#     `let mut x : T` accumulator annotations flow onto the synthesized loop's params.
#   * Lowering: a typed param -> D2Pannot(D2Pvar, s2exp) via pylower_typ; a return -> pylower_sres;
#     a typed `let` -> D2Eannot. The capitalized built-ins (Int/Bool/String/Char/Float) alias to
#     the prelude's INTERNAL `the_s2exp_*0` type names (the SAME T2Pcst an int/bool literal
#     carries) so unify short-circuits on stamp equality — NO hard `XATS000_cfail` (the surface
#     `int`/`bool` typedef expands to an existential the direct-L2 unifier mishandles).
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats) as M4/M13a/M16: build (or reuse)
# the M3 driver bundle, then for each frontend/TEST/m5a/*.py assert nerror=0 (after tread3a, which
# the driver runs before reporting). Codegen stays PARKED (#13b) — verifies LOWER + TYPECHECK only.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-m5a.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-m5a.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/m5a"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the M5a typed-def/typed-loop typecheck rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/m5a-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — M5a cannot proceed (see BUILD/m5a-driverbuild.log)" >&2
    tail -30 "$BUILD/m5a-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/m5a-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — M5a would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/m5a-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the M5a type-annotation typecheck over frontend/TEST/m5a/*.py"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- each must LOWER + TYPECHECK to nerror=0 (annotations respected; operators resolve) ------
VALID=(
  "m5a_def"          # typed def: `def double(x: Int) -> Int: x + x` -> x+x resolves, nerror=0
  "m5a_loop"         # typed 2-acc while loop (the M16 deferral fixed) -> nerror=0
  "m5a_unannotated"  # OPTIONALITY: an unannotated `let x = 1` still typechecks -> nerror=0
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
    echo ">> PASS  ($base LOWERS + TYPECHECKS with its annotations, nerror=0)"
  else
    echo "!! FAIL  ($base expected nerror=0; got ${n:-<none>})" >&2
    $NODE "$BUNDLE" "$py" 2>&1 | grep -E "F.PERR0-ERROR.*${base}" | head -5 >&2
    FAIL=1
  fi
done

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> M5a: FAIL (see failures above)"; exit 1; fi
echo ">> M5a: PASS (typed def x+x resolves; typed 2-acc loop typechecks — M16 deferral fixed;"
echo "            unannotated bindings still typecheck — annotations are OPTIONAL; all nerror=0)"
exit 0
