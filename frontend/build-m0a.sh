#!/usr/bin/env bash
########################################################################
# M0a — Python-surface frontend: typecheck-spine build + run.
#
# ONE command builds and runs the hand-built L2 -> L3 typecheck spine:
#   - transpile frontend/DATS/pyfront.dats -> JS via jsemit00 (NOT jsemit01)
#   - cat-link: runtime + lib2xatsopt.js (SED-namespaced) + .cats glue + driver
#   - run on node --stack-size=8801, capturing stdout (proves nerror=0 twice).
#
# Mirrors language-server/server/resident/build.sh (link order + sed + jsemit00),
# trimmed to the M0a spine (no minify, no xats2js backend — that is M0b).
#
# REUSES the pre-built srcgen2/lib/lib2xatsopt.js (~171MB). Never rebuilt here.
#
# Usage:   bash frontend/build-m0a.sh
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"

SRC_DATS="$HERE/DATS/pyfront.dats"
GLUE="$HERE/CATS/pyfront.cats"
OUTJS="$HERE/BUILD/pyfront-m0a.js"

# jsemit00 (NOT jsemit01) — the same transpiler lib2xatsopt.js was built with.
JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2="$SRCGEN2/lib/lib2xatsopt.js"

# compiler-linking runtime list (verbatim from server/resident/build.sh).
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
  echo "   (takes 6-9 min; do NOT rebuild if it already exists)" >&2
  exit 1
fi

echo ">> [1/3] transpile driver (jsemit00): $SRC_DATS"
TRANS="$HERE/BUILD/pyfront_dats.js"
node --stack-size=8801 "$JSEMIT" "$SRC_DATS" > "$TRANS" 2>"$HERE/BUILD/transpile.err"
echo "   -> $TRANS ($(wc -l < "$TRANS") lines)"
if [ "$(wc -l < "$TRANS")" -lt 5 ]; then
  echo "!! driver transpile produced too little output; see BUILD/transpile.err" >&2
  tail -40 "$HERE/BUILD/transpile.err" >&2
  exit 1
fi

echo ">> [2/3] link runtime + lib2xatsopt(SED-namespaced) + glue + driver -> $OUTJS"
cat "${RUNTIME[@]}" > "$OUTJS"
# link-time namespacing of the compiler library (same SED as the resident build).
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2" >> "$OUTJS"
# the .cats glue must precede the driver.
if [ -f "$GLUE" ]; then cat "$GLUE" >> "$OUTJS"; fi
cat "$TRANS" >> "$OUTJS"
echo "   linked $(wc -l < "$OUTJS") lines into $OUTJS ($(du -h "$OUTJS" | awk '{print $1}'))"

echo ">> [3/3] run: node --stack-size=8801 $OUTJS"
echo "----------------------------------------------------------------------"
node --stack-size=8801 "$OUTJS"
RC=$?
echo "----------------------------------------------------------------------"
echo ">> node exit code: $RC"
exit $RC
