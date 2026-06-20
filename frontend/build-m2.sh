#!/usr/bin/env bash
########################################################################
# M2 — Python-surface frontend: parser build + PyAST golden harness.
#
# ONE command:
#   - transpiles the M1 lexer/layout DATS (needed: the parser CALLS pylex_layout)
#     and the M2 parser DATS (jsemit00, stack-size 8801):
#       pylexing_token.dats   (raw scanner — reused from M1)
#       pylayout.dats         (off-side rule — reused from M1)
#       pyparsing_util.dats    (pstate cursor + recovery + node-loctn accessors)
#       pyparsing_staexp.dats  (type + pattern parser)
#       pyparsing_dynexp.dats  (expression Pratt + statement/suite parser)
#       pyparsing_decl00.dats  (declaration + module parser + public entries)
#       pyparsing_print.dats   (PyAST pretty-printer)
#       pyparsing_harness.dats (golden harness: parse argv[2], dump the PyAST)
#   - cat-links: runtime + lib2xatsopt.js (SED-namespaced) + .cats glue + the
#     transpiled DATS (harness LAST, since it has the top-level entry).
#   - runs the harness once PER snippet in frontend/TEST/m2_*.py, dumping the
#     PyAST, and diffs against the checked-in golden (.golden).
#
# Mirrors frontend/build-m1.sh exactly (same runtime list, same sed namespacing,
# same jsemit00, same --stack-size=8801). REUSES srcgen2/lib/lib2xatsopt.js (~171MB).
# Does NOT modify any M1 file or test (M2 snippets are named m2_*.py).
#
# Usage:
#   bash frontend/build-m2.sh            # build + run + diff goldens (FAIL on diff)
#   bash frontend/build-m2.sh --accept   # build + run + (RE)WRITE goldens
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"

ACCEPT=0
if [ "${1:-}" = "--accept" ]; then ACCEPT=1; fi

GLUE="$HERE/CATS/pylexing.cats"
OUTJS="$HERE/BUILD/pyparse-m2.js"
# M2 snippets live in TEST/m2/ (a subdirectory) so M1's build-m1.sh, which globs
# TEST/*.py non-recursively, does NOT pick them up. Purely additive; M1 untouched.
TESTDIR="$HERE/TEST/m2"

JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2="$SRCGEN2/lib/lib2xatsopt.js"

# the DATS to transpile, in link order (harness LAST — it owns the entry point).
DATS=(
  "$HERE/DATS/pylexing_token.dats"
  "$HERE/DATS/pylayout.dats"
  "$HERE/DATS/pyparsing_util.dats"
  "$HERE/DATS/pyparsing_staexp.dats"
  "$HERE/DATS/pyparsing_dynexp.dats"
  "$HERE/DATS/pyparsing_decl00.dats"
  "$HERE/DATS/pyparsing_print.dats"
  "$HERE/DATS/pyparsing_harness.dats"
)

# compiler-linking runtime list (verbatim from build-m1.sh / server resident build).
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
echo ">> [1/4] transpile M2 DATS (jsemit00)  ($NDATS files)"
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
  # surface any errck the transpiler emitted (these would mean an unresolved API).
  if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR|errck" "$HERE/BUILD/${base}.err" 2>/dev/null; then
    echo "!! transpile of $base reported errck/F?PERR0-ERROR — see BUILD/${base}.err" >&2
    grep -nE "F2PERR0-ERROR|F3PERR0-ERROR|errck" "$HERE/BUILD/${base}.err" | head -30 >&2
    exit 1
  fi
  TRANS_LIST+=("$tj")
done

echo ">> [2/4] link runtime + lib2xatsopt(SED-namespaced) + glue + DATS -> $OUTJS"
cat "${RUNTIME[@]}" > "$OUTJS"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2" >> "$OUTJS"
if [ -f "$GLUE" ]; then cat "$GLUE" >> "$OUTJS"; fi
for tj in "${TRANS_LIST[@]}"; do cat "$tj" >> "$OUTJS"; done
echo "   linked $(wc -l < "$OUTJS") lines ($(du -h "$OUTJS" | awk '{print $1}'))"

echo ">> [3/4] run the parser harness over frontend/TEST/m2_*.py"
echo "----------------------------------------------------------------------"
FAIL=0
shopt -s nullglob
HAVE_TESTS=0
for py in "$TESTDIR"/m2_*.py; do
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
  echo "!! no frontend/TEST/m2_*.py snippets found" >&2
  exit 1
fi

echo ">> [4/4] print the dump for evidence snippets (2 well-formed + the malformed case)"
for base in m2_def m2_match m2_malformed; do
  got="$HERE/BUILD/${base}.got"
  if [ -f "$got" ]; then
    echo "------ $base ------"
    cat "$got"
  fi
done

if [ "$ACCEPT" -eq 1 ]; then
  echo ">> goldens (re)written. Re-run without --accept to verify."
  exit 0
fi
if [ "$FAIL" -ne 0 ]; then
  echo ">> M2 GOLDEN: FAIL (see diffs above)"; exit 1
fi
echo ">> M2 GOLDEN: PASS (all snippets match)"
exit 0
