#!/usr/bin/env bash
########################################################################
# M5b.4/.5 — Python-surface frontend: TYPE ALIAS (`type`) + STRUCT (`struct`)
# lowering + TYPECHECK.
#
# Slice 4/5 (one unified path): both `type X = T` and `struct S { f: T ... }` lower to a
# SINGLE L2 D2Csexpdef (a static type-definition; a struct IS a record-type alias, §5.7.1).
# So an alias/struct declared BEFORE a function that USES it typechecks end-to-end:
#   * the alias name resolves + unfolds to its RHS,
#   * a struct's field projection `p.x` resolves through the record-type alias,
#   * a primitive alias (`type Count = Int`) hits the M5a hazard path, auto-mitigated by
#     resolve_typ (direct T2Pcst the_s2exp_*0, NOT the prelude sexpdef).
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse ->
# elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the
# M3 driver bundle (reusing build-m3.sh's compile+link), then for each
# frontend/TEST/m5b45/*.py assert `nerror (after tread3a) = 0`.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-m5b45.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-m5b45.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/m5b45"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the M5b.4/.5 alias/struct lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/m5b45-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — M5b.4/.5 cannot proceed (see BUILD/m5b45-driverbuild.log)" >&2
    tail -30 "$BUILD/m5b45-driverbuild.log" >&2
    exit 1
  fi
  # build-m3.sh also runs its own 4a/4b — surface their verdict (M5b.4/.5 must not regress M3).
  if ! grep -q ">> M3: PASS" "$BUILD/m5b45-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — M5b.4/.5 would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/m5b45-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the M5b.4/.5 alias/struct lowering + typecheck over frontend/TEST/m5b45/*.py"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "m5b_alias"         # type Ints = List[Int]  + total(xs: Ints) -> Int       (alias to a tycon-app)
  "m5b_struct"        # struct Point { x: Int, y: Int } + getx(p: Point): p.x (record alias + projection)
  "m5b_struct_alias"  # type Count = Int + bump(n: Count) -> Int              (HAZARD: primitive alias)
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
if [ "$FAIL" -ne 0 ]; then echo ">> M5b45: FAIL (see failures above)"; exit 1; fi
echo ">> M5b45: PASS (type alias + struct lower to ONE D2Csexpdef; alias use, struct field"
echo "            projection, and a primitive-alias hazard path all LOWER + TYPECHECK nerror=0)"
exit 0
