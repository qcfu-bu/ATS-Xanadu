#!/usr/bin/env bash
########################################################################
# ROBUSTNESS GATE — the frontend must NEVER CRASH on malformed / edge input;
# it must DEGRADE to a clean diagnostic (a parse diagnostic and/or nerror>0).
#
# Two hardening fixes are gated here (frontend-only; the stock srcgen2 passes are
# NOT touched — we validate/normalize BEFORE handing bad L2 to the stock compiler):
#
#   Bug #41 — deeply/badly nested @-args overflowed the recursive-descent parser's
#             NATIVE stack and SEGFAULTED (EXIT 139) instead of recovering. The parser
#             now bounds the bracket-/expr-descent depth (ps_depth_* in pyparsing_util)
#             and, on crossing the cap, emits a clean parse diagnostic + a survivable
#             error node + resync. ASSERT: does NOT segfault; reports a "nesting too deep"
#             parse diagnostic AND nerror>0.
#               * r41_deep_inst.pdats     : `@inst[@inst[@inst[…` (expr-position decorator).
#               * r41_deep_callarg.pdats  : `foo(@inst[@inst[…`   (call-arg expr decorator).
#
#   Bug #32 — a FLAT (`@unboxed`) `Type` param at a BOXED instantiation is a latent
#             tflt-vs-tbox sort inconsistency our lowering used to emit. On a BOXED
#             datatype the frontend now NORMALIZES the flat Type param to boxed
#             (psort2_of_dt/psort2_of_rcd in pylower_decl00) -> consistently-sorted L2 the
#             stock type passes tolerate; the flat-param-at-boxed shape on a `def` is caught
#             as a clean type error. ASSERT: does NOT crash the type passes — it reaches the
#             tread3a nerror line gracefully (the def form reports a clean nerror>0).
#               * r32_flat_def_boxed.pdats   : `def idf[A: Type @unboxed]` at boxed arg
#                                              -> clean nerror>0 TYPE-ERROR (no crash).
#               * r32_flat_param_boxed.pdats : `enum Box[A: Type @unboxed]` + `Box[Int]`
#                                              -> TYPECHECK is graceful (reaches the nerror
#                                              line). NB: a SEPARATE, PRE-EXISTING, GENERIC
#                                              backend codegen gap (`i0varfst_mklst` undefined
#                                              in the M3 driver's trxd3i0 lib) crashes the
#                                              CODEGEN of *every* parametric datatype equally
#                                              and lives in srcgen2 (out of scope; cannot be
#                                              fixed from the frontend) — so this fixture only
#                                              asserts the TYPECHECK stage is crash-free.
#
# Rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full lex -> parse ->
# elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a pipeline): build the
# M3 driver bundle (reusing build-m3.sh's compile+link), then run each fixture under the
# bundle and assert the no-crash / nerror>0 conditions.
#
# A SEGFAULT shows up as bundle exit code 139 (128 + SIGSEGV 11); we assert exit != 139.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-robust.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-robust.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/robust"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the robustness fixes ride the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/robust-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — ROBUST cannot proceed (see BUILD/robust-driverbuild.log)" >&2
    tail -40 "$BUILD/robust-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/robust-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — ROBUST would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/robust-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the malformed/edge fixtures over frontend/TEST/robust/*.pdats"
########################################################################
FAIL=0

# run a fixture; capture exit code + stderr (progress + diagnostics).
run_fixture() {
  local py="$1" err="$2"
  $NODE "$BUNDLE" "$py" > /dev/null 2>"$err"
  echo $?
}

# ---- Bug #41 : deeply nested malformed @-args must NOT segfault; they degrade to a clean
#                "nesting too deep" parse diagnostic AND nerror>0 ----------------------------
B41=(
  "r41_deep_inst"     # @inst[@inst[@inst[…  (expr-position decorator)
  "r41_deep_callarg"  # foo(@inst[@inst[…    (call-arg expr decorator)
)
for base in "${B41[@]}"; do
  py="$TESTDIR/${base}.pdats"
  err="$BUILD/robust_${base}.stderr"
  echo "----------------------------------------------------------------------"
  echo ">> [#41] $py  (deeply nested malformed @-args)"
  if [ ! -f "$py" ]; then echo "!! missing $py" >&2; FAIL=1; continue; fi
  echo "-- source (head) --"; head -c 90 "$py"; echo " …(${#base} fixture)"
  rc="$(run_fixture "$py" "$err")"
  diags="$(grep -cE 'nesting too deep' "$err" 2>/dev/null || echo 0)"
  nerr="$(grep -oE 'nerror \(after tread3a\) = [0-9]+' "$err" 2>/dev/null | grep -oE '[0-9]+$' | head -1)"
  echo ">> bundle exit code: $rc  (139 = SIGSEGV)"
  echo ">> 'nesting too deep' parse diagnostics: $diags ;  nerror (after tread3a) = ${nerr:-<none>}"
  if [ "$rc" -eq 139 ]; then
    echo "!! FAIL ($base SEGFAULTED — exit 139; the depth guard did not catch it)" >&2; FAIL=1
  elif [ "${diags:-0}" -lt 1 ]; then
    echo "!! FAIL ($base did not emit a 'nesting too deep' parse diagnostic)" >&2
    grep -vE 'd0parsed_from_fpath|MYCDIR' "$err" | tail -8 >&2; FAIL=1
  elif [ "${nerr:-0}" = "0" ] || [ -z "${nerr:-}" ]; then
    echo "!! FAIL ($base did not report nerror>0 after the parse diagnostic)" >&2; FAIL=1
  else
    echo ">> PASS  ($base: no crash; ${diags} parse diagnostic(s) + nerror=${nerr} > 0)"
  fi
done

# ---- Bug #32 (def variant) : a flat @unboxed Type param at a boxed arg is caught as a CLEAN
#                              type error (nerror>0), never a crash --------------------------
echo "----------------------------------------------------------------------"
B32D="r32_flat_def_boxed"
py="$TESTDIR/${B32D}.pdats"; err="$BUILD/robust_${B32D}.stderr"
echo ">> [#32] $py  (flat @unboxed Type param on a def, instantiated at a boxed arg)"
if [ ! -f "$py" ]; then echo "!! missing $py" >&2; FAIL=1; else
  echo "-- source --"; cat "$py"
  rc="$(run_fixture "$py" "$err")"
  nerr="$(grep -oE 'nerror \(after tread3a\) = [0-9]+' "$err" 2>/dev/null | grep -oE '[0-9]+$' | head -1)"
  echo ">> bundle exit code: $rc  (139 = SIGSEGV)"
  echo ">> nerror (after tread3a) = ${nerr:-<none>}"
  if [ "$rc" -eq 139 ]; then
    echo "!! FAIL ($B32D SEGFAULTED — exit 139)" >&2; FAIL=1
  elif [ -z "${nerr:-}" ]; then
    echo "!! FAIL ($B32D crashed before the type passes finished — no nerror line)" >&2
    grep -vE 'd0parsed_from_fpath|MYCDIR' "$err" | tail -10 >&2; FAIL=1
  elif [ "${nerr}" = "0" ]; then
    echo "!! FAIL ($B32D expected nerror>0 — the flat tflt param must NOT unify with a boxed arg)" >&2; FAIL=1
  else
    echo ">> PASS  ($B32D: no crash; the flat-param-at-boxed mismatch is a clean type error, nerror=${nerr} > 0)"
  fi
fi

# ---- Bug #32 (enum variant) : the TYPECHECK of a flat @unboxed Type param on a BOXED enum is
#                               GRACEFUL (reaches the tread3a nerror line; no type-pass crash).
#      NB: a SEPARATE, pre-existing, GENERIC backend codegen gap (i0varfst_mklst, srcgen2/trxd3i0)
#      crashes the CODEGEN of EVERY parametric datatype equally — out of scope; we only assert the
#      type-pass stage is crash-free here. -----------------------------------------------------
echo "----------------------------------------------------------------------"
B32E="r32_flat_param_boxed"
py="$TESTDIR/${B32E}.pdats"; err="$BUILD/robust_${B32E}.stderr"
echo ">> [#32] $py  (flat @unboxed Type param on a BOXED enum, boxed-instantiated)"
if [ ! -f "$py" ]; then echo "!! missing $py" >&2; FAIL=1; else
  echo "-- source --"; cat "$py"
  rc="$(run_fixture "$py" "$err")"
  reached="$(grep -cE 'd3parsed nerror \(after tread3a\)' "$err" 2>/dev/null || echo 0)"
  nerr="$(grep -oE 'nerror \(after tread3a\) = [0-9]+' "$err" 2>/dev/null | grep -oE '[0-9]+$' | head -1)"
  echo ">> bundle exit code: $rc  (139 = SIGSEGV)"
  echo ">> reached tread3a nerror line: $reached ;  nerror = ${nerr:-<none>}"
  if [ "$rc" -eq 139 ]; then
    echo "!! FAIL ($B32E SEGFAULTED — exit 139; a type pass crashed)" >&2; FAIL=1
  elif [ "${reached:-0}" -lt 1 ]; then
    echo "!! FAIL ($B32E crashed a TYPE pass before reaching the nerror line)" >&2
    grep -vE 'd0parsed_from_fpath|MYCDIR' "$err" | tail -10 >&2; FAIL=1
  else
    echo ">> PASS  ($B32E: the flat-vs-boxed TYPECHECK is crash-free — reached nerror=${nerr:-?}."
    echo "          The codegen i0varfst_mklst gap is generic to all parametric enums & pre-existing.)"
  fi
fi

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> ROBUST: FAIL (see failures above)"; exit 1; fi
echo ">> ROBUST: PASS  (#41 deep nested @-args -> no segfault, clean parse diagnostic + nerror>0;"
echo "                  #32 flat @unboxed Type param at a boxed instantiation -> no type-pass crash,"
echo "                  the def form a clean nerror>0 type error. Both handled by the frontend.)"
exit 0
