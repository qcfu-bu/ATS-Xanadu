#!/usr/bin/env bash
########################################################################
# M5b.6a — Python-surface frontend: TYPE-DECLARATION DECORATORS select the ATS
# memory/representation MODE (boxed / linear / flat) on `enum` / `struct`.
#
# Slice 6a (the decorator delta on the proven boxed M5b.3/.4/.5 constructions): a
#   * `@viewtype enum`   -> a LINEAR datatype (s2cst sort the_sort2_vtbx, vs boxed tbox),
#   * `@unboxed struct`  -> a FLAT record   (S2Etrcd(TRCDflt0,...), sort the_sort2_tflt),
#   * `@viewtype struct` -> a LINEAR record (S2Etrcd(TRCDbox1,...), sort the_sort2_vtbx),
#   * a bare/`@boxed` enum/struct -> BOXED (the proven default; tbox / TRCDbox0), unchanged.
# (`@unboxed enum` has NO stock unboxed-datatype primitive -> pinned to BOXED tbox.)
#
# EVIDENCE MODEL (M5b.6 spike finding): the frontend typecheck path does NOT enforce
# linearity (the compiler erases it — statyp2.sats:43). So nerror=0 alone CANNOT distinguish
# the modes; a positive `nerror=0` proves the mode-selected construction TYPECHECKS, and the
# M2.5 PyCore dump (`mode=linear`/`mode=flat`/`mode=boxed`) PROVES the decorator was HONORED
# (the elaborator carries it). Both are asserted here:
#   (A) M3 TYPECHECK: each fixture LOWERS (mode-selected sort/trcdknd) + typechecks nerror=0.
#   (B) M2.5 PyCore DUMP: each decorated fixture's `(data ...)/(record ...)` carries the
#       expected `mode=` word (linear/flat/boxed) — the decorator is NOT silently boxed.
#
# Rides the SAME two driver bundles the rest of M5b uses:
#   * BUILD/pyfront-m3.js   (full lex->parse->elab->lower->...->tread3a) for (A) nerror,
#   * BUILD/pyelab-m2_5.js  (parse->elaborate->dump PyCore)              for (B) the mode dump.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 + M2.5 driver bundles.
#
# Usage:
#   bash frontend/build-m5b6.sh                 # (re)build both driver bundles + run + verify
#   bash frontend/build-m5b6.sh --reuse-bundle  # skip the rebuilds, reuse the existing bundles
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
M3BUNDLE="$BUILD/pyfront-m3.js"
M25BUNDLE="$BUILD/pyelab-m2_5.js"
TESTDIR="$HERE/TEST/m5b6"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/3] M3 driver bundle (the M5b.6a mode-selected lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$M3BUNDLE" ]; then
  echo "   reusing $M3BUNDLE ($(wc -l < "$M3BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/m5b6-m3build.log" 2>&1; then
    echo "!! the M3 driver build FAILED — M5b.6a cannot proceed (see BUILD/m5b6-m3build.log)" >&2
    tail -30 "$BUILD/m5b6-m3build.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/m5b6-m3build.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — M5b.6a would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/m5b6-m3build.log" >&2
    exit 1
  fi
  echo "   M3 driver built + self-test PASS ($(wc -l < "$M3BUNDLE") lines)"
fi
[ -s "$M3BUNDLE" ] || { echo "!! $M3BUNDLE missing — run without --reuse-bundle" >&2; exit 1; }

########################################################################
echo ">> [2/3] M2.5 harness bundle (parse->elaborate->dump PyCore; for the mode evidence)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$M25BUNDLE" ]; then
  echo "   reusing $M25BUNDLE ($(wc -l < "$M25BUNDLE") lines)"
else
  echo "   building via build-m2_5.sh (also re-diffs the M2.5 goldens — must not drift) ..."
  if ! bash "$HERE/build-m2_5.sh" > "$BUILD/m5b6-m25build.log" 2>&1; then
    echo "!! the M2.5 harness build/golden-diff FAILED — see BUILD/m5b6-m25build.log" >&2
    tail -40 "$BUILD/m5b6-m25build.log" >&2
    exit 1
  fi
  echo "   M2.5 harness built + goldens green ($(wc -l < "$M25BUNDLE") lines)"
fi
[ -s "$M25BUNDLE" ] || { echo "!! $M25BUNDLE missing — run without --reuse-bundle" >&2; exit 1; }

########################################################################
echo ">> [3/3] run M5b.6a over frontend/TEST/m5b6/*.py — (A) nerror=0 + (B) mode dump"
########################################################################
FAIL=0

# (A) the `nerror` line the M3 driver prints AFTER tread3a (the only authoritative count).
nerror_of() {
  $NODE "$M3BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# (B) the M2.5 PyCore dump lines that carry a `mode=` word (one per `enum`/`struct` decl).
mode_lines_of() {
  $NODE "$M25BUNDLE" "$1" 2>&1 | grep -oE "\((data|record) [A-Za-z0-9_]+.* mode=(boxed|linear|flat)" | sed -E 's/@\([^)]*\)//g'
}

# fixture  ->  expected mode word that PROVES the decorator was honored.
declare -a FIX=(
  "m5b_viewtype_enum:linear"    # @viewtype enum  -> linear datatype  (sort vtbx)
  "m5b_unboxed_struct:flat"     # @unboxed  struct-> flat record      (TRCDflt0, tflt)
  "m5b_viewtype_struct:linear"  # @viewtype struct-> linear record    (TRCDbox1, vtbx)
  "m5b_boxed_default:boxed"     # bare enum+struct-> boxed (regression; tbox / TRCDbox0)
)

for entry in "${FIX[@]}"; do
  base="${entry%%:*}"
  want="${entry##*:}"
  py="$TESTDIR/${base}.py"
  echo "----------------------------------------------------------------------"
  echo ">> [m5b6] $py   (expect nerror=0 + mode=$want honored)"
  if [ ! -f "$py" ]; then echo "!! missing $py" >&2; FAIL=1; continue; fi
  echo "-- source --"; cat "$py"

  # (A) typecheck -> nerror=0
  n="$(nerror_of "$py")"
  echo ">> (A) nerror (after tread3a) = ${n:-<none>}"
  if [ "${n:-X}" != "0" ]; then
    echo "!! FAIL  ($base expected nerror=0; got ${n:-<none>})" >&2
    echo "-- f3perr0 diagnostics (stock reporter) --" >&2
    $NODE "$M3BUNDLE" "$py" 2>&1 | grep -E "F3PERR0-ERROR" | head -8 >&2
    FAIL=1
  fi

  # (B) PyCore mode dump -> must contain the expected mode word
  echo ">> (B) PyCore mode-carrying decls:"
  ml="$(mode_lines_of "$py")"
  echo "$ml" | sed 's/^/     /'
  if echo "$ml" | grep -q "mode=$want"; then
    echo ">> PASS  ($base typechecks nerror=0 AND PyCore dump shows mode=$want — decorator HONORED)"
  else
    echo "!! FAIL  ($base PyCore dump does NOT show the expected mode=$want)" >&2
    FAIL=1
  fi
done

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> M5b6: FAIL (see failures above)"; exit 1; fi
echo ">> M5b6: PASS (@viewtype/@unboxed/@boxed on enum/struct SELECT the ATS memory mode:"
echo "            @viewtype->linear (vtbx/TRCDbox1), @unboxed->flat (TRCDflt0/tflt),"
echo "            bare/@boxed->boxed (tbox/TRCDbox0); every mode TYPECHECKS nerror=0 and the"
echo "            PyCore dump PROVES the decorator is honored — NOT silently boxed)"
exit 0
