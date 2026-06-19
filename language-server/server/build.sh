#!/usr/bin/env bash
########################################################################
# WS-1a  Checker build  -  build.sh
#
# Builds the ATS3 LSP diagnostics checker `xats-lsp-check.js`.
#
# This is the "COMPILER-LINKING build" (distinct from the WS-0a FFI-spike
# build): the driver calls the compiler front-end (d3parsed_of_fildats,
# f3perr0_*), so it must be linked TOGETHER WITH the whole compiler. The
# compiler is provided as the pre-compiled library srcgen2/lib/lib2xatsopt.js
# (built by ./build-lib2xatsopt.sh, ~6-8 min, one-time).
#
# Runtime link list and the lib2xatsopt link-time SED transform are taken
# verbatim from srcgen2/UTIL/Makefile_xjsemit (the stock tcheck driver's
# own build), NOT from the FFI-spike recipe. Key differences from spike:
#   * uses srcgen1_* runtime (prelude/prelude_node/xatslib_node), because
#     the compiler headers staload srcgen1/prelude;
#   * cats the compiled compiler (lib2xatsopt.js) with the link-time
#     's/jsx(...)tnm/js1\1tnm/g' namespacing transform;
#   * srcgen2_prelude*.js are NOT used here (that's the spike's path).
#
# Usage:
#   bash build.sh                  # builds BUILD/xats-lsp-check.js
#   (requires srcgen2/lib/lib2xatsopt.js to exist first)
#
# Run the result:
#   node --stack-size=8801 BUILD/xats-lsp-check.js \
#        <src.dats|sats> --uri <uri> --json-out <path.json>
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"

# Which driver .dats to build (default: the full Stage-2/3 checker).
SRC_DATS="${1:-$HERE/DATS/xats_lsp_check.dats}"
GLUE="${2:-$HERE/CATS/xats_lsp_check.cats}"
OUTJS="${3:-$HERE/BUILD/xats-lsp-check.js}"

# jsemit00 (NOT jsemit01): jsemit01_opt1 mis-emits some closure templates as
# invalid JS (see build-lib2xatsopt.sh). Use the same transpiler the lib was
# built with so driver+lib template emission is consistent.
JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2="$SRCGEN2/lib/lib2xatsopt.js"

# compiler-linking runtime list (srcgen2/UTIL/Makefile_xjsemit:34-47)
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
  echo "!! $LIB2 missing — run ./build-lib2xatsopt.sh first" >&2
  exit 1
fi

echo ">> [1/3] transpile driver: $SRC_DATS"
TRANS="$HERE/BUILD/$(basename "${SRC_DATS%.dats}")_dats.js"
node --stack-size=8801 "$JSEMIT" "$SRC_DATS" > "$TRANS" 2>"$HERE/BUILD/transpile.err"
echo "   -> $TRANS ($(wc -l < "$TRANS") lines)"
# The transpiler's stderr proofreads every staloaded dependency (prelude,
# compiler SATS) and prints their PERR0 lines; those are NOT our errors.
# A genuinely broken DRIVER transpile yields ~0 lines of JS — check that.
if [ "$(wc -l < "$TRANS")" -lt 5 ]; then
  echo "!! driver transpile produced too little output; see BUILD/transpile.err" >&2
  tail -20 "$HERE/BUILD/transpile.err" >&2
  exit 1
fi

echo ">> [2/3] link runtime + compiler(lib2xatsopt) + glue + driver -> $OUTJS"
cat "${RUNTIME[@]}" > "$OUTJS"
# link-time namespacing of the compiler library (Makefile_xjsemit UTIL:45)
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2" >> "$OUTJS"
# our hand-written FFI glue must precede the driver (its require()'d consts
# are used by the driver's top-level vals on load; require is not hoisted)
if [ -f "$GLUE" ]; then cat "$GLUE" >> "$OUTJS"; fi
cat "$TRANS" >> "$OUTJS"
echo "   linked $(wc -l < "$OUTJS") lines into $OUTJS"

echo ">> [3/3] done."
echo "   node --stack-size=8801 --max-old-space-size=8192 \\"
echo "        $OUTJS <src> --uri <uri> --json-out <path.json>"
echo "   (--max-old-space-size raises the V8 heap; the linked compiler is"
echo "    memory-heavy on large staload closures. Normal files run fine at the"
echo "    default ~4GB; the flag adds headroom for the heaviest inputs.)"
