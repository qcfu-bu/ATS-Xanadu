#!/usr/bin/env bash
########################################################################
# SURF1 — Python-surface frontend: four surface-PARITY features toward canonical-ATS
# syntax parity, riding the SAME M3 driver pipeline (lex -> parse -> elab -> lower ->
# trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a):
#
#   (1) comments  : `(* ... *)` NESTABLE block comments (lexer; `//` deferred — int-div conflict).
#   (2) op        : `op+` — an operator as a first-class VALUE (PyEop -> PCEvar -> pl_var sym).
#   (3) implement : `extern def foo(x:Int)->Int` + `implement foo(x): x+x` -> D2Cimplmnt0 (SPIKE-GO).
#                   Also covers a function-typed extern alias implemented with direct args.
#   (4) overload  : `overload show with my_show` (`#symload`) -> D2Csymload + env reg (SPIKE-GO).
#
# Fixtures (each must LOWER + TYPECHECK to nerror=0):
#   surf1_comments.pdats  : a (* nested (* block *) *) comment + a typed def that typechecks.
#   surf1_op.pdats        : let f = op+ ; f(1, 2)               (op-as-value).
#   surf1_impl.pdats      : extern def dbl + implement dbl(x): x+x + use_dbl()=dbl(5).
#   surf1_impl_funtyped.pdats : extern def f()->Unary + implement f(x), no extra nullary layer.
#   surf1_overload.pdats  : def my_show + overload show with my_show + use_show()=show(7).
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-surf1.sh                 # (re)build the M3 driver + run + verify SURF1 tests
#   bash frontend/build-surf1.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/surf1"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the surf1 lowerings ride the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/surf1-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — SURF1 cannot proceed (see BUILD/surf1-driverbuild.log)" >&2
    tail -40 "$BUILD/surf1-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/surf1-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — SURF1 would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/surf1-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the surf1 lowering + typecheck over frontend/TEST/surf1/*.pdats"
########################################################################
FAIL=0

nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "surf1_comments"   # (* nested (* block *) *) comment + a typed def
  "surf1_op"         # let f = op+ ; f(1, 2)
  "surf1_impl"       # extern def dbl + implement dbl(x): x+x + dbl(5)
  "surf1_impl_funtyped" # function-typed extern alias + direct-arg implementation
  "surf1_overload"   # def my_show + overload show with my_show + show(7)
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
if [ "$FAIL" -ne 0 ]; then echo ">> SURF1: FAIL (see failures above)"; exit 1; fi
echo ">> SURF1: PASS (block comments, op-as-value, implement, and overload all"
echo "            LOWER + TYPECHECK nerror=0 through the real pipeline)"
exit 0
