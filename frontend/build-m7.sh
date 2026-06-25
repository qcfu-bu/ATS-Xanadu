#!/usr/bin/env bash
########################################################################
# M7 — Python-surface frontend: complete THREE deferred lowerings so they typecheck E2E.
#
#   (A) tuple types  `(Int, Bool)`   — PyTtup -> S2Etrcd with INTEGER labels 0..n-1.
#   (B) function types `(A) -> B`     — PyTfun -> S2Efun1 (the proven con-fun maker, F2CLfun).
#   (C) as-patterns  `p as x`         — PyPas -> PCPas -> D2Prfpt (fixes the dropped-binding bug:
#                                       `x` PARSED but elaboration DROPPED it; now `x` binds + is
#                                       usable in the arm body).
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse -> elab ->
# lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the M3 driver
# bundle (reusing build-m3.sh's compile+link), then for each frontend/TEST/m7/*.py assert
# `nerror (after tread3a) = 0`.
#
# Fixtures:
#   m7_tuptype.py : def fst2(p: (Int, Bool)) -> Int + let xy: (Int, Int) = (1, 2) (tuple types)
#   m7_funtype.py : def apply(f: (Int)->Int, x: Int) -> Int + apply(double, 5)     (fun types + HOF)
#   m7_aspat.py   : enum Tree + match with `case Node(l, x, r) as whole: whole`    (as-pattern binds)
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-m7.sh                 # (re)build the M3 driver + run + verify M7 tests
#   bash frontend/build-m7.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/m7"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the M7 tuple/fun-type + as-pattern lowerings ride the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/m7-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — M7 cannot proceed (see BUILD/m7-driverbuild.log)" >&2
    tail -30 "$BUILD/m7-driverbuild.log" >&2
    exit 1
  fi
  # build-m3.sh also runs its own 4a/4b — surface their verdict (M7 must not regress M3).
  if ! grep -q ">> M3: PASS" "$BUILD/m7-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — M7 would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/m7-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the M7 tuple/fun-type + as-pattern lowering + typecheck over frontend/TEST/m7/*.py"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "m7_tuptype"   # (A) tuple-type annotation `(Int, Bool)` + `let xy: (Int, Int) = (1, 2)`
  "m7_funtype"   # (B) function-type annotation `(Int) -> Int`, applied + a named-function HOF call
  "m7_aspat"     # (C) as-pattern `case Node(l, x, r) as whole: whole` — `whole` BINDS (bug fix)
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
    echo ">> PASS  ($base LOWERS + TYPECHECKS, nerror=0)"
  else
    echo "!! FAIL  ($base expected nerror=0; got ${n:-<none>})" >&2
    echo "-- f3perr0 diagnostics (stock reporter) --" >&2
    $NODE "$BUNDLE" "$py" 2>&1 | grep -E "F3PERR0-ERROR" | head -8 >&2
    FAIL=1
  fi
done

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> M7: FAIL (see failures above)"; exit 1; fi
echo ">> M7: PASS (tuple types -> S2Etrcd int-labels, function types -> S2Efun1 (F2CLfun),"
echo "            and as-pattern 'p as x' -> D2Prfpt with 'x' usable in the arm body — all"
echo "            LOWER + TYPECHECK nerror=0)"
exit 0
