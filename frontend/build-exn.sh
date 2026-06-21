#!/usr/bin/env bash
########################################################################
# EXN — Python-surface frontend: EXCEPTIONS (toward canonical-ATS parity).
#
#   exception E(T...)   -> D2Cexcptcon (a d2con of the built-in `exn` type, registered
#                          like a datatype con so raise/except resolve).
#   raise E(args)       -> D2Eraise (an expression of any type; raise does not return).
#   try: <body> except <pat>: <handler> ...
#                       -> D2Etry0(body, clauses-over-exn) — the whole try is a VALUE.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse ->
# elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the
# M3 driver bundle (reusing build-m3.sh's compile+link), then for each frontend/TEST/exn/*.pdats
# assert `nerror (after tread3a) = 0`.
#
# Fixtures:
#   exn_decl_raise.pdats : exception NotFound(Int) + raise + try/except NotFound(x)/_ (n-ary)
#   exn_nullary.pdats    : exception Empty + raise + try/except Empty/_                (nullary)
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-exn.sh                 # (re)build the M3 driver + run + verify EXN tests
#   bash frontend/build-exn.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/exn"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the EXN exception/raise/try lowerings ride the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/exn-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — EXN cannot proceed (see BUILD/exn-driverbuild.log)" >&2
    tail -30 "$BUILD/exn-driverbuild.log" >&2
    exit 1
  fi
  # build-m3.sh also runs its own 4a/4b — surface their verdict (EXN must not regress M3).
  if ! grep -q ">> M3: PASS" "$BUILD/exn-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — EXN would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/exn-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the EXN exception/raise/try lowering + typecheck over frontend/TEST/exn/*.pdats"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "exn_decl_raise"   # exception NotFound(Int) + raise NotFound(k) + try/except NotFound(x)/_
  "exn_nullary"      # exception Empty (nullary) + raise Empty + try/except Empty/_
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
if [ "$FAIL" -ne 0 ]; then echo ">> EXN: FAIL (see failures above)"; exit 1; fi
echo ">> EXN: PASS (exception E(T...) -> D2Cexcptcon, raise E(args) -> D2Eraise, and"
echo "            try/except -> D2Etry0(body, clauses-over-exn) — all LOWER + TYPECHECK nerror=0)"
exit 0
