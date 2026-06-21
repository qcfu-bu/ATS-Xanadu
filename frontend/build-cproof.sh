#!/usr/bin/env bash
########################################################################
# C-PROOF (Area C — proof surface) — TERMINATION METRICS (@terminates[n])
# and EXISTENTIAL-UNPACK patterns (VCons{m}(x, rest)), wired through the
# real frontend pipeline + TYPECHECKED. (@with is DEFERRED — see report:
# there is no per-CASE-ARM withtype slot at L2; D2CLScls = (d2gpt, d2exp).)
#
# What this proves (each fixture nerror=0):
#   * cp_metric.pdats — `@terminates[n] def countdown[n: SInt](k: SInt[n]) -> SInt: 0`
#                       (a TERMINATION METRIC `.<n>.` -> an F2ARGmets f2arg on the def) typechecks.
#   * cp_unpack.pdats — an `enum Vec[A, n: SInt]` + `def headOr[A, n: SInt](d, v) -> A` whose
#                       match has a `case VCons{m}(x, rest): x` EXISTENTIAL-UNPACK (`{m}` -> a
#                       d2pat_sapp introducing the con's hidden index) typechecks.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse ->
# elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the
# M3 driver bundle (reusing build-m3.sh), then for each frontend/TEST/cproof/*.pdats
# assert `nerror (after tread3a) = 0`.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-cproof.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-cproof.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/cproof"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the C-proof metric + unpack lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/cproof-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — C-PROOF cannot proceed (see BUILD/cproof-driverbuild.log)" >&2
    tail -40 "$BUILD/cproof-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/cproof-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — C-PROOF would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/cproof-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the C-proof lowering + typecheck over frontend/TEST/cproof/*.pdats"
########################################################################
FAIL=0

nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "cp_metric"   # @terminates[n] def countdown[n: SInt](k: SInt[n]) -> SInt : 0   (F2ARGmets metric)
  "cp_unpack"   # case VCons{m}(x, rest): x  — EXISTENTIAL-UNPACK (d2pat_sapp)
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
if [ "$FAIL" -ne 0 ]; then echo ">> C-PROOF: FAIL (see failures above)"; exit 1; fi
echo ">> C-PROOF: PASS (termination metrics @terminates[n] -> F2ARGmets on the def, and"
echo "             existential-unpack patterns VCons{m}(x, rest) -> d2pat_sapp introducing the"
echo "             con's hidden index, both lower + typecheck structurally, nerror=0. @with is"
echo "             DEFERRED — no per-case-arm withtype slot at L2 (D2CLScls = (d2gpt, d2exp)).)"
exit 0
