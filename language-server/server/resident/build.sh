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

# ---- M6a: the Python-surface front-end (TYPECHECK-ONLY) -----------------------
# The resident now also validates .psats/.pdats by calling pyfront_d3parsed_of_
# fname/fpath (frontend/SATS/pyfront_lsp.sats). So we transpile + link the
# front-end PASS DATS too. This is the MINIMAL set: the M1 lexer + M2 parser + M2.5
# elaborator + M3 lowerer + the LEAN pyfront_lsp driver — NO codegen backend
# (intrep/trxd3i0/js1emit are only pulled by pyfront_m3's emit_js, which the LSP
# never calls), so we link ONLY lib2xatsopt (js1), exactly as the stock resident
# does — no lib2xats2cc/lib2xats2js, no extra namespace (no js2/js3 clash). The
# pyrt runtime prelude is loaded at RUNTIME from $XATSHOME (filpath_pvsload), not
# compiled in. Modeled on frontend/build-m3.sh's [2]+[3].
FRONTEND="$XATSHOME/frontend"
PYFRONT_DATS=(
  "$FRONTEND/DATS/pylexing_token.dats"
  "$FRONTEND/DATS/pylayout.dats"
  "$FRONTEND/DATS/pyparsing_util.dats"
  "$FRONTEND/DATS/pyparsing_staexp.dats"
  "$FRONTEND/DATS/pyparsing_dynexp.dats"
  "$FRONTEND/DATS/pyparsing_decl00.dats"
  "$FRONTEND/DATS/pyparsing_print.dats"
  "$FRONTEND/DATS/pyelab_util.dats"
  "$FRONTEND/DATS/pyelab_diag.dats"
  "$FRONTEND/DATS/pyelab_lint.dats"
  "$FRONTEND/DATS/pyelab_core.dats"
  "$FRONTEND/DATS/pyelab_loop.dats"
  "$FRONTEND/DATS/pyelab_decl.dats"
  "$FRONTEND/DATS/pyelab_print.dats"
  "$FRONTEND/DATS/pylower_staexp.dats"
  "$FRONTEND/DATS/pylower_dynexp.dats"
  "$FRONTEND/DATS/pylower_decl00.dats"
  "$FRONTEND/DATS/pyfront_lsp.dats"
)
# pyfront .cats glue: the lexer's byte-buffer FFI (PYL_*) + the LSP file-read.
PYFRONT_GLUE=(
  "$FRONTEND/CATS/pylexing.cats"
  "$FRONTEND/CATS/pyfront_lsp.cats"
)

echo ">> [1/4] transpile driver + pyfront passes: $SRC_DATS"
TRANS="$HERE/BUILD/$(basename "${SRC_DATS%.dats}")_dats.js"
node --stack-size=8801 "$JSEMIT" "$SRC_DATS" > "$TRANS" 2>"$HERE/BUILD/transpile.err"
echo "   - $(basename "${SRC_DATS%.dats}") ($(wc -l < "$TRANS") lines)"
if [ "$(wc -l < "$TRANS")" -lt 5 ]; then
  echo "!! driver transpile produced too little output; see BUILD/transpile.err" >&2
  tail -30 "$HERE/BUILD/transpile.err" >&2
  exit 1
fi

PYFRONT_TRANS=()
FAILT=0
for d in "${PYFRONT_DATS[@]}"; do
  base="$(basename "$d" .dats)"
  tj="$HERE/BUILD/${base}_dats.js"
  node --stack-size=8801 "$JSEMIT" "$d" > "$tj" 2>"$HERE/BUILD/${base}.err"
  lines="$(wc -l < "$tj")"
  echo "   - $base ($lines lines)"
  if [ "$lines" -lt 5 ]; then
    echo "!! transpile of $base produced too little; see BUILD/${base}.err" >&2
    tail -40 "$HERE/BUILD/${base}.err" >&2; FAILT=1
  fi
  if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$HERE/BUILD/${base}.err" 2>/dev/null; then
    echo "!! transpile of $base reported errck/F?PERR0-ERROR — see BUILD/${base}.err" >&2
    grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$HERE/BUILD/${base}.err" | head -20 >&2; FAILT=1
  fi
  PYFRONT_TRANS+=("$tj")
done
[ "$FAILT" -ne 0 ] && { echo ">> M6a: FAIL (pyfront transpile errors above)"; exit 1; }

echo ">> [2/4] link runtime + compiler(lib2xatsopt) + glue + driver + pyfront -> $OUTJS"
cat "${RUNTIME[@]}" > "$OUTJS"
# link-time namespacing of the compiler library (same SED as server/build.sh).
# Only lib2xatsopt (js1) — the pyfront typecheck path links NO codegen lib, so
# there is no js2/js3 and no namespace clash.
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2" >> "$OUTJS"
# the .cats glue must precede the drivers (its require()'d consts / FFI bodies are
# used by top-level vals on load; require is not hoisted). Resident glue first,
# then the pyfront lexer + file-read glue.
if [ -f "$GLUE" ]; then cat "$GLUE" >> "$OUTJS"; fi
for g in "${PYFRONT_GLUE[@]}"; do cat "$g" >> "$OUTJS"; done
# the resident driver, then the pyfront pass DATS (order within the front-end is
# the build-m3 order; the resident driver staloads pyfront_lsp.sats, so the
# symbols are bound at link by the appended pyfront DATS bodies).
cat "$TRANS" >> "$OUTJS"
for tj in "${PYFRONT_TRANS[@]}"; do cat "$tj" >> "$OUTJS"; done
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
