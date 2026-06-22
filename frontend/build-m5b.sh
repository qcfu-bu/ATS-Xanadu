#!/usr/bin/env bash
########################################################################
# M5b — Python-surface frontend: DATATYPE (enum) lowering + match TYPECHECK.
#
# Slice 3: PCCdata -> a real L2 D2Cdatatype, so a monomorphic `enum` declares a type
# + its data constructors, and a `match` over that enum TYPECHECKS end-to-end. Also
# exercises the nullary-con-pattern fix (#21: a nullary con pattern wrapped in D2Pdap0).
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse ->
# elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the
# M3 driver bundle (reusing build-m3.sh's compile+link), then for each frontend/TEST/m5b/*.py
# assert `nerror (after tread3a) = 0`.
#
# Fixtures (monomorphic; enum FIRST so it registers before the matcher):
#   m5b_enum_nullary.py : enum Color { Red, Green, Blue } + rank(c) matches all-nullary cons
#   m5b_enum_payload.py : enum Opt { Nothing, Just(Int) } + unwrap(o) matches nullary + n-ary
#   m5b_enum_payload_wild.py : n-ary con matched by wildcard payload (`Both(_)` -> D2Pdap1)
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-m5b.sh                 # (re)build the M3 driver + run + verify M5b tests
#   bash frontend/build-m5b.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/m5b"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the M5b enum lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/m5b-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — M5b cannot proceed (see BUILD/m5b-driverbuild.log)" >&2
    tail -30 "$BUILD/m5b-driverbuild.log" >&2
    exit 1
  fi
  # build-m3.sh also runs its own 4a/4b — surface their verdict (M5b must not regress M3).
  if ! grep -q ">> M3: PASS" "$BUILD/m5b-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — M5b would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/m5b-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the M5b enum lowering + typecheck over frontend/TEST/m5b/*.py"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "m5b_enum_nullary"  # enum Color { Red, Green, Blue } + match over all-NULLARY cons (#21 fix)
  "m5b_enum_payload"  # enum Opt { Nothing, Just(Int) } + match over a nullary + an n-ary con
  "m5b_enum_payload_wild" # enum Duo { Empty, Both(Int, Int) } + wildcard-payload con match
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
if [ "$FAIL" -ne 0 ]; then echo ">> M5b: FAIL (see failures above)"; exit 1; fi
echo ">> M5b: PASS (monomorphic enum decl (D2Cdatatype) + match over its cons LOWER + TYPECHECK"
echo "           nerror=0; nullary cons exercise D2Pdap0 and wildcard payloads exercise D2Pdap1)"
exit 0
