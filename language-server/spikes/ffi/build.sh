#!/usr/bin/env bash
########################################################################
# WS-0a  Toolchain & FFI spike  -  build.sh
#
# Implements the primer S10.3 "a .dats -> runnable node program" recipe,
# with the deviations documented in README.md (notably: the primer's
# runtime file `srcgen2_xatslib_node.js` does NOT exist; and our own
# ffi_spike.cats must be cat-linked into app.js).
#
# Usage:
#   bash build.sh            # produces ./app.js
#   node app.js <somefile>   # run it
########################################################################
set -euo pipefail

# --- locate XATSHOME (the ATS-Xanadu repo root) ----------------------
export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# prebuilt JS-emit compiler (primer S10.4) and the JS runtime pieces
XATS2JS="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit01_ats2_opt1.js"
R="$XATSHOME/srcgen2/xats2js/srcgenx/xshared/runtime"

SRC="ffi_spike.dats"
GLUE="ffi_spike.cats"
TRANSPILED="ffi_spike_dats.js"
APP="app.js"

echo ">> [1/3] transpile $SRC -> $TRANSPILED"
# --stack-size=8801 is required WHEN COMPILING (the compiler is deeply
# recursive); the produced program needs no such flag.  The heavy debug
# trace goes to stderr, so stdout is the clean JS we want.
node --stack-size=8801 "$XATS2JS" "$SRC" > "$TRANSPILED"
echo "   transpiled $(wc -l < "$TRANSPILED") lines"

echo ">> [2/3] link (concatenate) runtime + glue + compiled output -> $APP"
# Runtime file order matters: definitions before users.
#   xats2js_js1emit.js     - low-level JS1 emit runtime helpers
#   srcgen2_precats.js     - core runtime (boxing, tags, ...)
#   srcgen2_prelude.js     - the JS prelude .cats (g_print, strn ops, ...)
#   srcgen2_prelude_node.js- NODE-specific .cats (console, fs, argv, ...)  REQUIRED here
#   srcgen2_xatslib.js     - xatslib .cats
# NOTE: the primer also lists srcgen2_xatslib_node.js, but that file
#       DOES NOT EXIST in the runtime dir (only a _hd header stub does);
#       it is omitted here.  See README.md "Deviations".
# Our own ffi_spike.cats is appended LAST among the glue (so its
# require()'d consts exist), then the compiled program which runs on load.
cat \
  "$R/xats2js_js1emit.js" \
  "$R/srcgen2_precats.js" \
  "$R/srcgen2_prelude.js" \
  "$R/srcgen2_prelude_node.js" \
  "$R/srcgen2_xatslib.js" \
  "$GLUE" \
  "$TRANSPILED" \
  > "$APP"
echo "   linked $(wc -l < "$APP") lines into $APP"

echo ">> [3/3] done.  Run:  node app.js <somefile>"
echo "   (run from this dir so node_modules/vscode-jsonrpc resolves,"
echo "    or set NODE_PATH=$HERE/node_modules)"
