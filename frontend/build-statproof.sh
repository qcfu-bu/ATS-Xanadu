#!/usr/bin/env bash
########################################################################
# STAT/PROOF parity — static definitions (sortdef / stacst / stadef) +
# proof functions (prfun / prval / praxi), wired through the real frontend
# pipeline (lex -> parse -> elab -> lower -> trans2a -> trsym2b -> t2read0 ->
# trans23 -> tread3a) + TYPECHECKED.
#
# What this proves (each fixture nerror=0, after tread3a — the authoritative
# typecheck count; matches build-dep.sh's gate, codegen is out of scope):
#   * sp_sortdef.pdats — `sortdef Nat = SInt` (a SORT ALIAS) + a use of `Nat`
#                        as an index param sort (`def use_nat[n: Nat](...)`).
#   * sp_stacst.pdats  — `stacst maxlen: SInt` (a STATIC CONSTANT of a sort).
#   * sp_stadef.pdats  — `stadef Two = 2` (a STATIC-LEVEL int definition).
#   * sp_prfun.pdats   — `prfun id_pf(x: Int) -> Int: x` (a proof FUNCTION) +
#                        `prval pv = 0` (a proof VALUE) +
#                        `praxi ax(n: Int) -> Int` (a proof AXIOM, bodyless).
#
# Recipes are SPIKE-PROVEN (frontend/DATS/pyfront_dep_spike.dats P5/P6, all
# nerror=0): sortdef -> D2Csortdef(S2TEXsrt), stacst -> D2Cstacst0, stadef ->
# build_sexpdef(s2exp_int), prfun -> D2Cfundclst(FNKprfn1), prval ->
# D2Cvaldclst(VLKprval), praxi -> D2Cstatic(D2Cdynconst(FNKpraxi)).
#
# Rides the SAME M3 driver bundle (build-m3.sh). PURELY ADDITIVE: builds only
# into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-statproof.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-statproof.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/statproof"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the STAT/PROOF lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/statproof-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — STAT/PROOF cannot proceed (see BUILD/statproof-driverbuild.log)" >&2
    tail -40 "$BUILD/statproof-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/statproof-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — STAT/PROOF would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/statproof-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the STAT/PROOF lowering + typecheck over frontend/TEST/statproof/*.pdats"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "sp_sortdef"   # sortdef Nat = SInt + def use_nat[n: Nat](...)  (a SORT ALIAS)
  "sp_stacst"    # stacst maxlen: SInt                            (a STATIC CONSTANT)
  "sp_stadef"    # stadef Two = 2                                 (a STATIC int DEFINITION)
  "sp_prfun"     # prfun id_pf / prval pv / praxi ax              (PROOF fn / val / axiom)
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
if [ "$FAIL" -ne 0 ]; then echo ">> STAT/PROOF: FAIL (see failures above)"; exit 1; fi
echo ">> STAT/PROOF: PASS (sortdef/stacst/stadef static definitions + prfun/prval/praxi"
echo "           proof functions all PARSE + LOWER + TYPECHECK structurally, nerror=0."
echo "           prfun/prval/praxi typecheck over EXISTING types (Int) in v1; a real prop/"
echo "           dataprop body is a separate batch. stadef supports an int-literal RHS in v1.)"
exit 0
