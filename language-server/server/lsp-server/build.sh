#!/usr/bin/env bash
########################################################################
# WS-1b  LSP server core  -  build.sh
#
# Produces ./xats-lsp-server.js, a standalone ATS3 -> JS node program
# (NOT a compiler-linking build; a normal program like the WS-0a spike).
#
# Implements the primer S10.3 "a .dats -> runnable node program" recipe,
# with the VERIFIED WS-0a deviations folded in:
#   - link exactly FIVE runtime files (srcgen2_xatslib_node.js does NOT exist).
#   - srcgen2_prelude_node.js is REQUIRED (node IO).
#   - our own xats-lsp-server.cats must be cat-linked, BEFORE the compiled
#     output (its `const X = require(...)` lines are not hoisted).
#   - transpile exit code is 0 even on type errors; detect a bad transpile by
#     grepping the transpiler's STDERR for `PERR0-ERROR` (the bare header
#     `F3PERR0_D3PARSED:` always prints and is NOT an error).
#
# Usage:
#   bash build.sh                 # produces ./xats-lsp-server.js
#   node xats-lsp-server.js --stdio   # run it (over stdio)
########################################################################
set -euo pipefail

# --- locate XATSHOME (the ATS-Xanadu repo root) ----------------------
export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# prebuilt JS-emit compiler (primer S10.4) and the JS runtime pieces.
XATS2JS="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit01_ats2_opt1.js"
R="$XATSHOME/srcgen2/xats2js/srcgenx/xshared/runtime"

SRC="xats-lsp-server.dats"
GLUE="xats-lsp-server.cats"
TRANSPILED="xats-lsp-server_dats.js"
APP="xats-lsp-server.js"
STDERR_LOG="$(mktemp -t xats-lsp-build-stderr.XXXXXX)"

echo ">> [1/3] transpile $SRC -> $TRANSPILED"
# --stack-size=8801 is required WHEN COMPILING (the compiler is deeply
# recursive); the produced program needs no such flag. Heavy debug trace goes
# to stderr (captured), so stdout is the clean JS we want.
node --stack-size=8801 "$XATS2JS" "$SRC" > "$TRANSPILED" 2> "$STDERR_LOG"

# Build-error detection: do NOT trust $? (transpile exits 0 even on errors).
# A real error prints `F2PERR0-ERROR` / `F3PERR0-ERROR` (the bare header
# `F3PERR0_D3PARSED:` is not an error).
if grep -q 'PERR0-ERROR' "$STDERR_LOG"; then
  echo "!! transpile reported type errors:" >&2
  grep 'PERR0-ERROR' "$STDERR_LOG" >&2 || true
  echo "   (full transpiler stderr: $STDERR_LOG)" >&2
  exit 1
fi
rm -f "$STDERR_LOG"
echo "   transpiled $(wc -l < "$TRANSPILED") lines"

echo ">> [2/3] link (concatenate) runtime + glue + compiled output -> $APP"
# Runtime file order matters: definitions before users. FIVE files (WS-0a).
#   xats2js_js1emit.js      - low-level JS1 emit runtime helpers
#   srcgen2_precats.js      - core runtime (boxing, tags, ...)
#   srcgen2_prelude.js      - the JS prelude .cats (g_print, strn ops, ...)
#   srcgen2_prelude_node.js - NODE-specific .cats (console, fs, argv, ...) REQUIRED
#   srcgen2_xatslib.js      - xatslib .cats
# Our own xats-lsp-server.cats is appended LAST among the glue (so its
# require()'d consts exist), then the compiled program which runs main() on load.
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

echo ">> [3/3] done.  Run:  node xats-lsp-server.js --stdio"
echo "   (run from a dir where node_modules/vscode-languageserver resolves;"
echo "    xats-lsp-server.js is shipped next to this dir's node_modules.)"
