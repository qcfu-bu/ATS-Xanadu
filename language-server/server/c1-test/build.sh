#!/usr/bin/env bash
########################################################################
# c1-test/build.sh  —  build the C1 xglobal_reset() test driver.
#
# Compiler-linking build (mirrors language-server/server/build.sh): the
# driver calls the compiler front-end (d3parsed_of_fildats) AND the new
# xglobal_reset(), so it is linked together with the whole compiler
# (srcgen2/lib/lib2xatsopt.js, built by build-lib2xatsopt-par.sh).
#
# Runtime link list + the lib2xatsopt link-time SED transform are taken
# verbatim from the server build (which took them from Makefile_xjsemit).
#
# Usage:  XATSHOME=/path bash build.sh
# Run:    node --stack-size=8801 --max-old-space-size=8192 \
#           BUILD/c1-reset-test.js <fileA.dats> <fileB.dats>
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"

SRC_DATS="$HERE/DATS/c1_reset_test.dats"
GLUE="$HERE/CATS/c1_reset_test.cats"
OUTJS="$HERE/BUILD/c1-reset-test.js"

# jsemit00 (the transpiler the lib was built with — keep emission consistent).
JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2="$SRCGEN2/lib/lib2xatsopt.js"

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
  echo "!! $LIB2 missing — run build-lib2xatsopt-par.sh first" >&2
  exit 1
fi

echo ">> [1/3] transpile driver: $SRC_DATS"
TRANS="$HERE/BUILD/c1_reset_test_dats.js"
node --stack-size=8801 "$JSEMIT" "$SRC_DATS" > "$TRANS" 2>"$HERE/BUILD/transpile.err"
echo "   -> $TRANS ($(wc -l < "$TRANS") lines)"
if [ "$(wc -l < "$TRANS")" -lt 5 ]; then
  echo "!! driver transpile produced too little output; see BUILD/transpile.err" >&2
  tail -30 "$HERE/BUILD/transpile.err" >&2
  exit 1
fi

echo ">> [2/3] link runtime + compiler(lib2xatsopt) + glue + driver -> $OUTJS"
cat "${RUNTIME[@]}" > "$OUTJS"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2" >> "$OUTJS"
if [ -f "$GLUE" ]; then cat "$GLUE" >> "$OUTJS"; fi
cat "$TRANS" >> "$OUTJS"
echo "   linked $(wc -l < "$OUTJS") lines into $OUTJS"

echo ">> [3/3] done."
echo "   node --stack-size=8801 --max-old-space-size=8192 $OUTJS <fileA.dats> <fileB.dats>"
