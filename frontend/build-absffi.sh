#!/usr/bin/env bash
########################################################################
# ABSFFI — Python-surface frontend: ABSTRACT TYPES + FFI EXTERN (toward ATS parity).
#
#   abstype Name [tvs]  -> D2Cabstype(s2cst, A2TDFsome()) — an OPAQUE type (no sexp attached;
#                          opacity holds at typecheck — a distinct singleton).
#   assume Name = T     -> D2Cabsimpl(tok, SIMPLone1(s2cst), T) — gives the abstract type its
#                          hidden representation (the s2cst selected by name).
#   extern def foo(...) -> R
#                       -> D2Cextern(D2Cdynconst(<bodyless d2cst : (args)->R>)) — an FFI function
#                          SIGNATURE; calls to foo(...) typecheck against the declared type.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse ->
# elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the
# M3 driver bundle (reusing build-m3.sh's compile+link), then for each frontend/TEST/absffi/*.pdats
# assert `nerror (after tread3a) = 0`.
#
# Fixtures:
#   abs_decl.pdats   : abstype Stack + def id_stack(s: Stack) -> Stack (opaque use) + assume Stack=List[Int]
#   extern_def.pdats : extern def c_strlen(s: String) -> Int + def use(s: String) -> Int: c_strlen(s)
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-absffi.sh                 # (re)build the M3 driver + run + verify ABSFFI tests
#   bash frontend/build-absffi.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/absffi"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the ABSFFI abstype/assume/extern lowerings ride the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/absffi-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — ABSFFI cannot proceed (see BUILD/absffi-driverbuild.log)" >&2
    tail -40 "$BUILD/absffi-driverbuild.log" >&2
    exit 1
  fi
  # build-m3.sh also runs its own 4a/4b — surface their verdict (ABSFFI must not regress M3).
  if ! grep -q ">> M3: PASS" "$BUILD/absffi-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — ABSFFI would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/absffi-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the ABSFFI abstype/assume/extern lowering + typecheck over frontend/TEST/absffi/*.pdats"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "abs_decl"     # abstype Stack + opaque-use def + assume Stack = List[Int]
  "extern_def"   # extern def c_strlen(s: String) -> Int + a call to it
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
if [ "$FAIL" -ne 0 ]; then echo ">> ABSFFI: FAIL (see failures above)"; exit 1; fi
echo ">> ABSFFI: PASS (abstype Name -> D2Cabstype (opaque), assume Name=T -> D2Cabsimpl, and"
echo "            extern def foo(...) -> D2Cextern(D2Cdynconst signature) — all LOWER + TYPECHECK nerror=0)"
exit 0
