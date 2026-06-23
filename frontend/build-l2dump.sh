#!/usr/bin/env bash
########################################################################
# L2DUMP — Pythonic-ATS round-trip FIDELITY harness: build the raw-L2 dumper.
#
# Transpiles + links the L2DUMP driver (frontend/DATS/pyfront_l2dump.dats) into
# BUILD/pyfront-l2dump.js. The driver has two modes:
#
#   node --stack-size=8801 BUILD/pyfront-l2dump.js stock   <F.dats>  <stadyn>
#       -> the STOCK raw-L2 dump: d2parsed_fprint(trans02_from_fpath(stadyn, F)).
#   node --stack-size=8801 BUILD/pyfront-l2dump.js pyfront <P.pdats> <stadyn>
#       -> OUR raw-L2 dump: d2parsed_fprint(pyfront_d2parsed_of_fpath(...)).
#
# Both serialize with the SAME printer (d2parsed_fprint), so the two dumps are
# byte-comparable after normalization (see build-l2diff.sh). Compares the RAW
# lowered d2parsed BEFORE the post-passes — exactly what our lowering produces.
#
# UNLIKE build-m3.sh, NO xats2js backend libs are needed (we never run codegen):
# only the runtime + lib2xatsopt + the frontend passes + this driver. Same
# transpile/link/Closure-minify recipe as build-m3.sh otherwise.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; REUSES srcgen2/lib/lib2xatsopt.js.
# jsemit00 + node --stack-size=8801 throughout. Nothing under srcgen2/ is modified.
#
# Usage:
#   bash frontend/build-l2dump.sh        # build BUILD/pyfront-l2dump.js + smoke-test
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"

JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2OPT="$SRCGEN2/lib/lib2xatsopt.js"
BUILD="$HERE/BUILD"
mkdir -p "$BUILD"
NODE="node --stack-size=8801"

for f in "$JSEMIT" "$LIB2OPT"; do
  if [ ! -f "$f" ]; then
    echo "!! required file missing: $f" >&2
    echo "   (build lib2xatsopt once via language-server/server/build-lib2xatsopt.sh)" >&2
    exit 1
  fi
done

########################################################################
echo ">> [1/3] transpile frontend passes + L2DUMP driver (jsemit00)"
########################################################################
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
  "$HERE/DATS/pylower_staexp.dats"
  "$HERE/DATS/pylower_dynexp.dats"
  "$HERE/DATS/pylower_decl00.dats"
  "$HERE/DATS/pyfront_l2dump.dats"
)
TRANS_LIST=()
FAILT=0
for d in "${DATS[@]}"; do
  base="$(basename "$d" .dats)"
  tj="$BUILD/${base}_l2dump.js"
  $NODE "$JSEMIT" "$d" > "$tj" 2>"$BUILD/${base}_l2dump.err"
  lines="$(wc -l < "$tj")"
  echo "   - $base ($lines lines)"
  if [ "$lines" -lt 5 ]; then
    echo "!! transpile of $base produced too little; see BUILD/${base}_l2dump.err" >&2
    tail -50 "$BUILD/${base}_l2dump.err" >&2; FAILT=1
  fi
  if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/${base}_l2dump.err" 2>/dev/null; then
    echo "!! transpile of $base reported errck/F?PERR0-ERROR — see BUILD/${base}_l2dump.err" >&2
    grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/${base}_l2dump.err" | head -20 >&2; FAILT=1
  fi
  TRANS_LIST+=("$tj")
done
[ "$FAILT" -ne 0 ] && { echo ">> L2DUMP: FAIL (transpile errors above)"; exit 1; }

########################################################################
echo ">> [2/3] link the L2DUMP bundle (runtime + lib2xatsopt + glue + DATS)"
########################################################################
S2R="$SRCGEN2/xats2js/srcgenx/xshared/runtime"
S1R="$SRCGEN1/xats2js/srcgenx/xshared/runtime"
RUNTIME=(
  "$S2R/xats2js_js1emit.js"
  "$S2R/srcgen2_precats.js"
  "$S1R/srcgen1_prelude.js"
  "$S1R/srcgen1_prelude_node.js"
  "$S1R/srcgen1_xatslib_node.js"
)
BUNDLE="$BUILD/pyfront-l2dump.js"
BUNDLE_RAW="$BUILD/pyfront-l2dump.raw.js"
cat "${RUNTIME[@]}" > "$BUNDLE_RAW"
# only lib2xatsopt (js1) is needed — no xats2cc/xats2js backend libs (no codegen).
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$BUNDLE_RAW"
# glue: M1 lexer glue (PYL_*) for the lexer .cats refs; L2DUMP glue (PYL2_*) for ours.
# (No PYM_* glue: we do NOT link the M3 driver — we implement pyfront_d2parsed_of_fpath
# locally so the M3 main's codegen path is never reached.)
cat "$HERE/CATS/pylexing.cats"     >> "$BUNDLE_RAW"
cat "$HERE/CATS/pyfront_l2dump.cats" >> "$BUNDLE_RAW"
for tj in "${TRANS_LIST[@]}"; do cat "$tj" >> "$BUNDLE_RAW"; done
echo "   linked $(wc -l < "$BUNDLE_RAW") lines into $BUNDLE_RAW ($(du -h "$BUNDLE_RAW" | awk '{print $1}'))"

# Minify with Closure (SIMPLE): collapses generated-code frame overhead so the
# deep-recursive parse/trans12 spine does not overflow Node's stack on large files.
# Falls back to the raw bundle on failure (mirrors build-m3.sh).
echo "   [closure] minify (SIMPLE): $BUNDLE_RAW -> $BUNDLE"
if npx --yes google-closure-compiler -W QUIET --compilation_level SIMPLE \
     --js="$BUNDLE_RAW" --js_output_file="$BUNDLE" 2>"$BUILD/pyfront-l2dump-closure.err"; then
  echo "   [closure] ok: $(du -h "$BUNDLE" | cut -f1) (raw $(du -h "$BUNDLE_RAW" | cut -f1))"
else
  echo "!! closure minify failed (see $BUILD/pyfront-l2dump-closure.err); using raw bundle" >&2
  tail -5 "$BUILD/pyfront-l2dump-closure.err" >&2 || true
  cp "$BUNDLE_RAW" "$BUNDLE"
fi

########################################################################
echo ">> [3/3] smoke-test: stock dump of a tiny green file"
########################################################################
SMOKE="srcgen2/SATS/xstamp0.sats"
SMOKEOUT="$BUILD/l2dump-smoke.stock.txt"
( cd "$XATSHOME" && $NODE "$BUNDLE" stock "$SMOKE" 0 > "$SMOKEOUT" 2>"$BUILD/l2dump-smoke.err" )
echo "-- driver stderr --"; cat "$BUILD/l2dump-smoke.err"
if grep -q "^D2PARSED(" "$SMOKEOUT"; then
  echo ">> L2DUMP: PASS (built $BUNDLE; stock dump of $SMOKE produced a D2PARSED(...) tree, $(wc -c < "$SMOKEOUT") bytes)"
  exit 0
else
  echo "!! L2DUMP: smoke-test produced no D2PARSED( tree; see $SMOKEOUT" >&2
  head -5 "$SMOKEOUT" >&2
  exit 1
fi
