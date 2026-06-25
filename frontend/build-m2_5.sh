#!/usr/bin/env bash
########################################################################
# M2.5 — Python-surface frontend: ELABORATOR build + PyCore golden harness.
#
# ONE command (mirrors build-m2.sh):
#   - transpiles the M1 lexer/layout + M2 parser DATS (the elaborator CALLS the
#     parser) AND the M2.5 elaborator DATS (jsemit00, --stack-size 8801):
#       pylexing_token / pylayout            (lexer — reused from M1)
#       pyparsing_util/staexp/dynexp/decl00  (parser — reused from M2)
#       pyparsing_print                      (PyAST printer — reused from M2; pyelab_print
#                                             reuses pytyp_fprint for surface types)
#       pyelab_util                          (PyCore loctn accessors + nameset ops)
#       pyelab_diag / pyelab_lint            (poison harvest / pyrt scan / §6 tail-lint)
#       pyelab_core / pyelab_loop / pyelab_decl   (the elaborator: §4 analysis, §5 rules,
#                                             two modes, the loop combinators, the driver)
#       pyelab_print                         (PyCore pretty-printer)
#       pyelab_harness                       (parse -> elaborate -> dump PyCore)
#   - cat-links: runtime + lib2xatsopt.js (SED-namespaced) + .cats glue + DATS
#     (harness LAST, it owns the entry point).
#   - runs the harness once PER snippet in frontend/TEST/m2_5/*.py, dumping the
#     PyCore, and diffs against the checked-in golden (.golden).
#   - ASSERTS no TAIL-LINT VIOLATION appears in any dump (the §6 invariant is a hard
#     build failure if a generated loop's self-call is not in tail position).
#   - ASSERTS the 10.1 (control-pure) dump contains NO `flow` (the fast-path proof).
#
# Mirrors build-m2.sh (same runtime list, sed namespacing, jsemit00, --stack-size=8801).
# REUSES srcgen2/lib/lib2xatsopt.js (~171MB). Touches NO M0/M1/M2 file (M2.5 snippets
# live in TEST/m2_5/, so M1/M2 globs never reach them).
#
# Usage:
#   bash frontend/build-m2_5.sh            # build + run + diff goldens (FAIL on diff)
#   bash frontend/build-m2_5.sh --accept   # build + run + (RE)WRITE goldens
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"

ACCEPT=0
if [ "${1:-}" = "--accept" ]; then ACCEPT=1; fi

GLUE="$HERE/CATS/pylexing.cats"
OUTJS="$HERE/BUILD/pyelab-m2_5.js"
TESTDIR="$HERE/TEST/m2_5"

JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2="$SRCGEN2/lib/lib2xatsopt.js"

DATS=(
  "$HERE/DATS/pylexing_token.dats"
  "$HERE/DATS/pylayout.dats"
  "$HERE/DATS/pyparsing_util.dats"
  "$HERE/DATS/pyparsing_staexp.dats"
  "$HERE/DATS/pyparsing_dynexp.dats"
  "$HERE/DATS/pyparsing_decl00.dats"
  "$HERE/DATS/pyparsing_print.dats"
  "$HERE/DATS/pyelab_util.dats"
  "$HERE/DATS/pyelab_diag.dats"
  "$HERE/DATS/pyelab_lint.dats"
  "$HERE/DATS/pyelab_core.dats"
  "$HERE/DATS/pyelab_loop.dats"
  "$HERE/DATS/pyelab_decl.dats"
  "$HERE/DATS/pyelab_print.dats"
  "$HERE/DATS/pyelab_harness.dats"
)

S2R="$SRCGEN2/xats2js/srcgenx/xshared/runtime"
S1R="$SRCGEN1/xats2js/srcgenx/xshared/runtime"
RUNTIME=(
  "$S2R/xats2js_js1emit.js"
  "$S2R/srcgen2_precats.js"
  "$S1R/srcgen1_prelude.js"
  "$S1R/srcgen1_prelude_node.js"
  "$S1R/srcgen1_xatslib_node.js"
)

mkdir -p "$HERE/BUILD"
if [ ! -f "$LIB2" ]; then
  echo "!! $LIB2 missing — build it once via language-server/server/build-lib2xatsopt.sh" >&2
  exit 1
fi

NDATS="${#DATS[@]}"
echo ">> [1/5] transpile M2.5 DATS (jsemit00)  ($NDATS files)"
TRANS_LIST=()
for d in "${DATS[@]}"; do
  base="$(basename "$d" .dats)"
  tj="$HERE/BUILD/${base}_dats.js"
  echo "   - $base"
  node --stack-size=8801 "$JSEMIT" "$d" > "$tj" 2>"$HERE/BUILD/${base}.err"
  lines="$(wc -l < "$tj")"
  if [ "$lines" -lt 5 ]; then
    echo "!! transpile of $base produced too little ($lines lines); see BUILD/${base}.err" >&2
    tail -60 "$HERE/BUILD/${base}.err" >&2
    exit 1
  fi
  if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$HERE/BUILD/${base}.err" 2>/dev/null; then
    echo "!! transpile of $base reported errck/F?PERR0-ERROR — see BUILD/${base}.err" >&2
    grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$HERE/BUILD/${base}.err" | head -10 >&2
    exit 1
  fi
  TRANS_LIST+=("$tj")
done

echo ">> [2/5] link runtime + lib2xatsopt(SED-namespaced) + glue + DATS -> $OUTJS"
cat "${RUNTIME[@]}" > "$OUTJS"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2" >> "$OUTJS"
if [ -f "$GLUE" ]; then cat "$GLUE" >> "$OUTJS"; fi
for tj in "${TRANS_LIST[@]}"; do cat "$tj" >> "$OUTJS"; done
echo "   linked $(wc -l < "$OUTJS") lines ($(du -h "$OUTJS" | awk '{print $1}'))"

echo ">> [3/5] run the elaborator harness over frontend/TEST/m2_5/*.py"
echo "----------------------------------------------------------------------"
FAIL=0
shopt -s nullglob
HAVE_TESTS=0
for py in "$TESTDIR"/m25_*.py; do
  HAVE_TESTS=1
  base="$(basename "$py" .py)"
  gold="$TESTDIR/${base}.golden"
  got="$HERE/BUILD/${base}.got"
  node --stack-size=8801 "$OUTJS" "$py" > "$got" 2>"$HERE/BUILD/${base}.run.err"
  if [ "$ACCEPT" -eq 1 ]; then
    cp "$got" "$gold"
    echo "   [accept] $base.golden  ($(wc -l < "$gold") lines)"
  else
    if [ ! -f "$gold" ]; then
      echo "   [MISSING GOLDEN] $base — run with --accept to create" >&2
      FAIL=1
    elif diff -u "$gold" "$got" > "$HERE/BUILD/${base}.diff" 2>&1; then
      echo "   [ok]   $base"
    else
      echo "   [DIFF] $base — see BUILD/${base}.diff" >&2
      cat "$HERE/BUILD/${base}.diff" >&2
      FAIL=1
    fi
  fi
done
echo "----------------------------------------------------------------------"
if [ "$HAVE_TESTS" -eq 0 ]; then
  echo "!! no frontend/TEST/m2_5/m25_*.py snippets found" >&2
  exit 1
fi

echo ">> [4/5] assert the §6 TAIL-POSITION invariant + the §3.1 fast-path"
INVFAIL=0
# (a) NO generated loop may have a non-tail self-call (a hard build failure).
for got in "$HERE"/BUILD/m25_*.got; do
  if grep -q "TAIL-LINT VIOLATION" "$got" 2>/dev/null; then
    echo "!! TAIL-LINT VIOLATION in $(basename "$got") — a generated loop self-call is NOT in tail position" >&2
    grep -n "TAIL-LINT VIOLATION" "$got" >&2
    INVFAIL=1
  fi
done
# (b) the control-pure while (10.1) MUST take the fast path: NO `flow` ctor in its dump.
PURE="$HERE/BUILD/m25_while_pure.got"
if [ -f "$PURE" ]; then
  if grep -qE "flow_next|flow_cont|flow_break|flow_return|staload pyrt" "$PURE"; then
    echo "!! 10.1 control-pure while did NOT take the fast path -- flow appears in its dump" >&2
    grep -nE "flow_next|flow_cont|flow_break|flow_return|staload pyrt" "$PURE" >&2
    INVFAIL=1
  else
    echo "   [ok]   10.1 control-pure while: NO flow built (fast path) + no staload pyrt"
  fi
fi
# (c) the control-bearing examples MUST build flow + a tail-recursive loop.
for base in m25_while_break m25_nested_return; do
  g="$HERE/BUILD/${base}.got"
  if [ -f "$g" ]; then
    if grep -qE "flow_next|flow_break|flow_return" "$g" && grep -q "(loop " "$g"; then
      echo "   [ok]   ${base}: flow path + tail-recursive (loop ...) present"
    else
      echo "!! ${base}: expected a flow path + a generated (loop ...) but did not find both" >&2
      INVFAIL=1
    fi
  fi
done
# (d) the THREADED `for` (architect ruling i): the iterator state `it` MUST be the loop's
#     first parameter and the advanced iterator `it1` MUST be pattern-bound from
#     iter_more(x, it1) AND threaded as the loop self-call's first tuple element. NO cell.
FR="$HERE/BUILD/m25_for_range.got"
if [ -f "$FR" ]; then
  ok_param=0; ok_more=0; ok_thread=0
  grep -q "(loop loop@.*(params it acc cnt)" "$FR" && ok_param=1
  grep -qE "Pcon iter_more@.* \(Pvar i@.*\) \(Pvar it1@" "$FR" && ok_more=1
  grep -qE "Evar loop@.*\(args \(Etup@.* \(Evar it1@" "$FR" && ok_thread=1
  if [ "$ok_param" -eq 1 ] && [ "$ok_more" -eq 1 ] && [ "$ok_thread" -eq 1 ]; then
    echo "   [ok]   m25_for_range: THREADED iterator (it in params; it1 from iter_more; it1 threaded in tail self-call)"
  else
    echo "!! m25_for_range: threaded-iterator shape missing (param=$ok_param more=$ok_more thread=$ok_thread)" >&2
    INVFAIL=1
  fi
fi
# (e) the guarded `match` (architect ruling iv): the guard MUST be PRESERVED on the arm
#     (printed `... if (...) => ...`) and NOT desugared to an inner `if ... then b else b`.
GM="$HERE/BUILD/m25_guard_match.got"
if [ -f "$GM" ]; then
  if grep -qE "\(arm@.* if \(Eapp" "$GM"; then
    echo "   [ok]   m25_guard_match: surface guard PRESERVED on the arm (not desugared to inner-if)"
  else
    echo "!! m25_guard_match: expected a preserved arm guard ('(arm ... if (...) => ...')" >&2
    INVFAIL=1
  fi
fi
# (f) TASK #14: a SINGLE-accumulator, no-else `for` whose body contains a `break` MUST take the
#     iterator/flow path (control-bearing), NOT the list_foldleft fast path. The fast path uses
#     elab_pure, which poisons a break to "break outside a loop"; the fix routes on the body's
#     control-flow flags. Assert: NO poison, a flow_break IS built, and the threaded `loop` runs.
FB="$HERE/BUILD/m25_for_break.got"
if [ -f "$FB" ]; then
  if ! grep -q "break outside a loop" "$FB" \
     && grep -q "flow_break" "$FB" \
     && grep -q "(loop loop@" "$FB"; then
    echo "   [ok]   m25_for_break: single-acc for+break takes the flow path (no 'break outside a loop' poison)"
  else
    echo "!! m25_for_break: a single-accumulator for+break did NOT take the flow path (task #14)" >&2
    grep -n "break outside a loop" "$FB" >&2
    INVFAIL=1
  fi
fi

echo ">> [5/5] print evidence dumps (10.1 fast-path + 10.2 flow path)"
for base in m25_while_pure m25_while_break; do
  got="$HERE/BUILD/${base}.got"
  if [ -f "$got" ]; then echo "------ $base ------"; cat "$got"; fi
done

if [ "$ACCEPT" -eq 1 ]; then
  echo ">> goldens (re)written. Re-run without --accept to verify."
  exit 0
fi
if [ "$FAIL" -ne 0 ] || [ "$INVFAIL" -ne 0 ]; then
  echo ">> M2.5: FAIL (golden diffs and/or invariant violations above)"; exit 1
fi
echo ">> M2.5 GOLDEN: PASS (all snippets match; §6 tail-lint clean; §3.1 fast-path verified)"
exit 0
