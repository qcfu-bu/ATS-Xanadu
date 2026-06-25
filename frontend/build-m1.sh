#!/usr/bin/env bash
########################################################################
# M1 — Python-surface frontend: lexer + layout build + golden harness.
#
# ONE command:
#   - transpiles the M1 lexer/layout DATS (jsemit00, stack-size 8801):
#       pylexing_token.dats   (raw scanner)
#       pylexing_print.dats   (token pretty-printer)
#       pylayout.dats         (off-side rule)
#       pylexing_harness.dats (golden harness: lex argv[2], dump token@span)
#   - cat-links: runtime + lib2xatsopt.js (SED-namespaced) + .cats glue + the
#     four transpiled DATS (harness LAST, since it has the top-level entry).
#   - runs the harness once PER snippet in frontend/TEST/*.py, dumping the
#     token+span stream, and diffs against the checked-in golden (.golden).
#
# Mirrors frontend/build-m0a.sh (same runtime list, same sed namespacing, same
# jsemit00, same --stack-size=8801), extended to multiple DATS + a golden loop.
#
# REUSES the pre-built srcgen2/lib/lib2xatsopt.js (~171MB). Never rebuilt here.
#
# Usage:
#   bash frontend/build-m1.sh            # build + run + diff goldens (FAIL on diff)
#   bash frontend/build-m1.sh --accept   # build + run + (RE)WRITE goldens
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"

ACCEPT=0
if [ "${1:-}" = "--accept" ]; then ACCEPT=1; fi

GLUE="$HERE/CATS/pylexing.cats"
OUTJS="$HERE/BUILD/pylex-m1.js"
TESTDIR="$HERE/TEST"

JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2="$SRCGEN2/lib/lib2xatsopt.js"

# the M1 DATS to transpile, in link order (harness LAST — it owns the entry point).
DATS=(
  "$HERE/DATS/pylexing_token.dats"
  "$HERE/DATS/pylexing_print.dats"
  "$HERE/DATS/pylayout.dats"
  "$HERE/DATS/pylexing_harness.dats"
)

# compiler-linking runtime list (verbatim from build-m0a.sh / server resident build).
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

echo ">> [1/4] transpile M1 DATS (jsemit00)"
TRANS_LIST=()
for d in "${DATS[@]}"; do
  base="$(basename "$d" .dats)"
  tj="$HERE/BUILD/${base}_dats.js"
  echo "   - $base"
  node --stack-size=8801 "$JSEMIT" "$d" > "$tj" 2>"$HERE/BUILD/${base}.err"
  lines="$(wc -l < "$tj")"
  if [ "$lines" -lt 5 ]; then
    echo "!! transpile of $base produced too little ($lines lines); see BUILD/${base}.err" >&2
    tail -40 "$HERE/BUILD/${base}.err" >&2
    exit 1
  fi
  # surface any errck the transpiler emitted (these would mean an unresolved API).
  if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR|errck" "$HERE/BUILD/${base}.err" 2>/dev/null; then
    echo "!! transpile of $base reported errck/F?PERR0-ERROR — see BUILD/${base}.err" >&2
    grep -nE "F2PERR0-ERROR|F3PERR0-ERROR|errck" "$HERE/BUILD/${base}.err" | head -20 >&2
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

echo ">> [3/4] run the golden harness over frontend/TEST/*.py"
echo "----------------------------------------------------------------------"
FAIL=0
shopt -s nullglob
for py in "$TESTDIR"/*.py; do
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

if [ "$ACCEPT" -eq 0 ]; then
  echo ">> [3b/4] large-layout stress smoke (guards generated-JS stack depth)"
  stress="$HERE/BUILD/m1_layout_stress.pdats"
  stress_got="$HERE/BUILD/m1_layout_stress.got"
  {
    for ((i=0; i<1800; i++)); do
      printf 'let stress_%04d = %d\n' "$i" "$i"
    done
  } > "$stress"
  if node --stack-size=8801 "$OUTJS" "$stress" > "$stress_got" 2>"$HERE/BUILD/m1_layout_stress.run.err"; then
    got_lines="$(wc -l < "$stress_got")"
    if [ "$got_lines" -eq 9002 ]; then
      echo "   [ok]   1800-line flat module layout ($got_lines token-dump lines)"
    else
      echo "   [FAIL] stress dump line count: got $got_lines, expected 9002" >&2
      FAIL=1
    fi
  else
    echo "   [FAIL] large-layout stress crashed; see BUILD/m1_layout_stress.run.err" >&2
    FAIL=1
  fi
fi

echo ">> [4/4] print the dump for two snippets (evidence: a def + a layout edge case)"
for base in t01_def t05_brackets t07_dedent_eof; do
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
  echo ">> M1 GOLDEN: FAIL (see diffs above)"; exit 1
fi
echo ">> M1 GOLDEN: PASS (all snippets match)"
exit 0
