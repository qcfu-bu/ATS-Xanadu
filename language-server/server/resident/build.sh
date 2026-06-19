#!/usr/bin/env bash
########################################################################
# RESIDENT LSP server build  -  build.sh   (workstream R1)
#
# Builds ONE resident artifact: xats-lsp-resident.js — a long-running ATS3->JS
# node program that bundles the compiler front-end and checks IN-PROCESS.
#
# This is the "compiler-linking" build (same shape as the existing
# server/build.sh and the reference server/Makefile): the driver calls the
# front-end (d3parsed_of_fil*, the_d?parenv_pvstmap, env_reset over the
# topmaps), so it links against the whole compiler — provided as the pre-built
# library srcgen2/lib/lib2xatsopt.js (~171MB; we REUSE it, never rebuild here).
#
# Link order (matches server/build.sh): runtime + lib2xatsopt(SED-namespaced) +
# our .cats glue (vscode-languageserver + env_reset + depgraph JS) + transpiled
# server DATS -> Closure SIMPLE.
#
# Usage:   bash build.sh                 # -> BUILD/xats-lsp-resident.opt1.js (minified)
#          MINIFY=0 bash build.sh        # skip closure (fast dev; raw bundle only)
#
# Run:     node --stack-size=8801 BUILD/xats-lsp-resident.opt1.js --stdio
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"

SRC_DATS="${1:-$HERE/DATS/xats_lsp_resident.dats}"
GLUE="${2:-$HERE/CATS/xats_lsp_resident.cats}"
OUTJS="${3:-$HERE/BUILD/xats-lsp-resident.js}"

# jsemit00 (NOT jsemit01) — same transpiler the lib was built with (see the
# existing server/build.sh note); keeps driver+lib template emission consistent.
JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2="$SRCGEN2/lib/lib2xatsopt.js"

MINIFY="${MINIFY:-1}"
OPTJS="${OUTJS%.js}.opt1.js"

# compiler-linking runtime list (verbatim from server/build.sh)
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
  echo "!! $LIB2 missing — build it once with ../build-lib2xatsopt.sh" >&2
  exit 1
fi

echo ">> [1/4] transpile driver: $SRC_DATS"
TRANS="$HERE/BUILD/$(basename "${SRC_DATS%.dats}")_dats.js"
node --stack-size=8801 "$JSEMIT" "$SRC_DATS" > "$TRANS" 2>"$HERE/BUILD/transpile.err"
echo "   -> $TRANS ($(wc -l < "$TRANS") lines)"
if [ "$(wc -l < "$TRANS")" -lt 5 ]; then
  echo "!! driver transpile produced too little output; see BUILD/transpile.err" >&2
  tail -30 "$HERE/BUILD/transpile.err" >&2
  exit 1
fi

echo ">> [2/4] link runtime + compiler(lib2xatsopt) + glue + driver -> $OUTJS"
cat "${RUNTIME[@]}" > "$OUTJS"
# link-time namespacing of the compiler library (same SED as server/build.sh)
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2" >> "$OUTJS"
# the .cats glue must precede the driver (its require()'d consts are used by the
# driver's top-level vals on load; require is not hoisted)
if [ -f "$GLUE" ]; then cat "$GLUE" >> "$OUTJS"; fi
cat "$TRANS" >> "$OUTJS"
echo "   linked $(wc -l < "$OUTJS") lines into $OUTJS ($(du -h "$OUTJS" | awk '{print $1}'))"

if [ "$MINIFY" = "1" ]; then
  echo ">> [3/4] minify (Closure SIMPLE): $OUTJS -> $OPTJS"
  if npx --yes google-closure-compiler -W QUIET --compilation_level SIMPLE \
       --js="$OUTJS" --js_output_file="$OPTJS" 2>"$HERE/BUILD/closure.err"; then
    echo "   -> $OPTJS ($(du -h "$OPTJS" | awk '{print $1}'), was $(du -h "$OUTJS" | awk '{print $1}'))"
  else
    echo "!! closure minify failed (see BUILD/closure.err); the raw $OUTJS still works" >&2
    tail -12 "$HERE/BUILD/closure.err" >&2
  fi
else
  echo ">> [3/4] minify skipped (MINIFY=0); use the raw $OUTJS"
fi

echo ">> [4/4] done."
echo "   node --stack-size=8801 $OPTJS --stdio"
