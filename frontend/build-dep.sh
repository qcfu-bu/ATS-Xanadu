#!/usr/bin/env bash
########################################################################
# DEP (dependent-type SURFACE, Stages 1–2) — index sorts (SInt/SBool),
# INDEX ARGUMENTS in type applications (Vec[A, n] / Vec[Int, 0] / SInt[0]),
# and INDEX QUANTIFIERS on defs (def f[n: SInt](...)), wired through the
# real frontend pipeline + TYPECHECKED.
#
# What this proves (each fixture nerror=0):
#   * dep_index_lit.pdats   — a parametric `enum Vec[A, n: SInt]` (a TYPE param A +
#                             an INDEX param n: SInt) + `def empty_vec() -> Vec[Int, 0]`
#                             (a LITERAL index arg 0) typecheck.
#   * dep_index_var.pdats   — `def vec_id[A, n: SInt](v: Vec[A, n]) -> Vec[A, n]` (an
#                             index-VARIABLE-quantified def over the sized type) typechecks.
#   * dep_sint.pdats        — a `[n: SInt]`-quantified def with a `Vec[A, n]` param + a bare
#                             `SInt` return typecheck.
#   * dep_sint_index.pdats  — the INDEXED primitive `SInt[0]` / `SInt[n]` (routed through the
#                             registered the_s2exp_sint1, the DEP-spike P8 recipe) typechecks.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse ->
# elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the
# M3 driver bundle (reusing build-m3.sh's compile+link), then for each
# frontend/TEST/dep/*.pdats assert `nerror (after tread3a) = 0`.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-dep.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-dep.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/dep"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the DEP index lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/dep-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — DEP cannot proceed (see BUILD/dep-driverbuild.log)" >&2
    tail -40 "$BUILD/dep-driverbuild.log" >&2
    exit 1
  fi
  # build-m3.sh also runs its own 4a/4b — surface their verdict (DEP must not regress M3).
  if ! grep -q ">> M3: PASS" "$BUILD/dep-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — DEP would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/dep-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the DEP index lowering + typecheck over frontend/TEST/dep/*.pdats"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "dep_index_lit"    # enum Vec[A, n: SInt] + empty_vec() -> Vec[Int, 0]   (LITERAL index arg)
  "dep_index_var"    # vec_id[A, n: SInt](v: Vec[A, n]) -> Vec[A, n]       (index-VAR quantifier)
  "dep_sint"         # len_index[A, n: SInt](v: Vec[A, n]) -> SInt          (bare SInt return)
  "dep_sint_index"   # zero_idx() -> SInt[0] ; same_idx[n: SInt](x: SInt[n]) -> SInt[n] (the_s2exp_sint1)
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
if [ "$FAIL" -ne 0 ]; then echo ">> DEP: FAIL (see failures above)"; exit 1; fi
echo ">> DEP: PASS (SInt/SBool index sorts + LITERAL/VARIABLE index args in type"
echo "           applications (Vec[A,n] / Vec[Int,0] / SInt[0]) + INDEX QUANTIFIERS on defs"
echo "           (def f[n: SInt](...)) all lower + typecheck structurally, nerror=0. Static"
echo "           arithmetic (n+1) + guards ({n|n>=0}) are a SEPARATE follow-up.)"
exit 0
