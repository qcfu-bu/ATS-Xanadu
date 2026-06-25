#!/usr/bin/env bash
########################################################################
# FFI (bootstrap P1, feature 3) — the compiler's FFI-heavy prelude round-trip.
#
# The ATS3 compiler self-hosts with NO inline C: FFI is PURE NAME-BINDING. The corpus pattern
# (recon-confirmed, e.g. xatslib/libcats/DATS/CATS/PY/gbas000.dats, xatslib/.../JS/dynarr0.dats):
#
#   #extern fun XATS000_foo(...): T = $extnam()           -- a bodyless FFI SIGNATURE
#   #impltmp NAME<a>(...) = XATS000_foo(...)               -- a generic impl whose body refs it
#
# INVESTIGATION VERDICT (no new lowering code needed): a `#extern fun ... = $extnam()` is, at
# TYPECHECK, EXACTLY a bodyless d2cst carrying the function type. The `= $extnam()` body adds NO
# ATS body (trans12_decl00.dats:3058-3076 maps it to an X2NAM side-table keyed by stamp); that
# side-table is READ ONLY by the codegen backends (xats2js/xats2py js1emit_utils0/py1emit_utils0),
# NEVER by trans12/trans23/tcheck — so it has ZERO effect on nerror. Its sole codegen effect is to
# SUPPRESS the stamp-suffix so the emitted symbol is the bare foreign name; and even there the
# explicit-name string in $extnam("x") is IGNORED (f0_some emits `dcst.name`, not the gnam). The
# d2cst struct (dynexp2.sats:462-486) has NO extnam slot. The corpus uses $extnam() (49) with a
# NON-empty name 0 times. So our bare `@extern def` (build_extern: bodyless, env-registered
# foreign d2cst) IS the $extnam-default case, and `@impl def NAME(...) = FOREIGN(...)` IS the
# #impltmp foreign-ref body. NO `@extern["name"]` surface is warranted.
#
# This script PROVES the corpus FFI pattern round-trips (typechecks nerror=0) through the real
# frontend pipeline (the same M3 driver: lex -> parse -> elab -> lower -> trans2a -> trsym2b ->
# t2read0 -> trans23 -> tread3a):
#
# Fixtures:
#   ffi_extern.pdats   : @extern def XATS000_foo(x: Int) -> Int    ($extnam-DEFAULT FFI signature)
#                        + a caller that typechecks against the declared signature.
#   ffi_impltmp.pdats  : @template[A] def bar + @impl[Int] def bar(x): XATS000_bar(x) whose body
#                        references a foreign @extern (the #impltmp per-backend-dispatch pattern).
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-ffi.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-ffi.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/ffi"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the FFI extern/impltmp pattern rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/ffi-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — FFI cannot proceed (see BUILD/ffi-driverbuild.log)" >&2
    tail -40 "$BUILD/ffi-driverbuild.log" >&2
    exit 1
  fi
  # build-m3.sh also runs its own 4a/4b — surface their verdict (FFI must not regress M3).
  if ! grep -q ">> M3: PASS" "$BUILD/ffi-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — FFI would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/ffi-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the FFI extern/impltmp lowering + typecheck over frontend/TEST/ffi/*.pdats"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "ffi_extern"    # @extern def XATS000_foo(x: Int) -> Int + a caller   ($extnam-DEFAULT signature)
  "ffi_impltmp"   # @template[A] def bar + @impl[Int] def bar(x): XATS000_bar(x)  (#impltmp foreign-ref body)
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
if [ "$FAIL" -ne 0 ]; then echo ">> FFI: FAIL (see failures above)"; exit 1; fi
echo ">> FFI: PASS (the corpus FFI name-binding pattern round-trips: @extern def = a bodyless"
echo "           foreign d2cst (the \$extnam-default FFI signature), and @template + @impl def"
echo "           NAME(...) = FOREIGN(...) = the #impltmp per-backend-dispatch shape — both LOWER"
echo "           + TYPECHECK nerror=0. The d2cst has NO external-NAME slot at typecheck; the"
echo "           \$extnam codegen side-table is codegen-only + ignores the name string, so no"
echo "           @extern[\"name\"] surface is warranted — the corpus is 100% \$extnam-default.)"
exit 0
