#!/usr/bin/env bash
########################################################################
# convert-py.sh — generate the PYTHONIC MIRROR of the ATS3 compiler.
#
# Phase A of the self-host: pyprint every bootstrap component into frontend/PY/,
# preserving the source tree structure, mapping .sats -> .psats and .dats -> .pdats.
#
# Component set = the xats2cz bootstrap list:
#   - 162 frontend SRCDATS         (srcgen2/DATS/*.dats; from srcgen2/Makefile_xjsemit)
#   - 7  xats2js srcgen1 backend   (intrep0 + trxd3i0 family)
#   - cz0emit + the cz driver
#   - ALL .sats interfaces those depend on (srcgen2/SATS, xats2js/srcgen1/SATS, xats2cz/SATS)
#
# pyprint emits EXTENSION-AGNOSTIC import stems (`from "srcgen2/SATS/x" import *`), so the
# mirror's import lines don't bake in .sats vs .psats — that's a compile-time decision (Phase B).
#
# Usage:
#   bash frontend/convert-py.sh                # build bundle (reuse if cached) + mirror all
#   bash frontend/convert-py.sh --rebuild-pp   # force-rebuild the pyprint bundle
#   bash frontend/convert-py.sh --force        # re-pyprint even already-generated files
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"
BUILD="$HERE/BUILD"
PY="$HERE/PY"
JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2OPT="$SRCGEN2/lib/lib2xatsopt.js"
NODE="node --stack-size=8801"
mkdir -p "$BUILD" "$PY"

REBUILD_PP=0; FORCE=0
for a in "$@"; do case "$a" in --rebuild-pp) REBUILD_PP=1;; --force) FORCE=1;; esac; done

########################################################################
echo ">> [1/3] pyprint bundle"
########################################################################
PP_BUNDLE="$BUILD/pp-corpus.js"
build_pp_bundle() {
  echo "   building pyprint bundle ..."
  $NODE "$JSEMIT" "$HERE/DATS/pyprint.dats"      > "$BUILD/pyprint_dats.js"      2>"$BUILD/pyprint.err"
  $NODE "$JSEMIT" "$HERE/DATS/pyprint_main.dats" > "$BUILD/pyprint_main_dats.js" 2>"$BUILD/pyprint_main.err"
  [ "$(wc -l < "$BUILD/pyprint_dats.js")" -ge 5 ] || { echo "!! pyprint.dats transpile failed"; tail -30 "$BUILD/pyprint.err"; exit 1; }
  local s2r="$SRCGEN2/xats2js/srcgenx/xshared/runtime"
  local s1r="$SRCGEN1/xats2js/srcgenx/xshared/runtime"
  local raw="$BUILD/pp-corpus.raw.js"
  cat "$s2r/xats2js_js1emit.js" "$s2r/srcgen2_precats.js" \
      "$s1r/srcgen1_prelude.js" "$s1r/srcgen1_prelude_node.js" "$s1r/srcgen1_xatslib_node.js" > "$raw"
  sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$raw"
  cat "$HERE/CATS/pyprint.cats" "$BUILD/pyprint_dats.js" "$BUILD/pyprint_main_dats.js" >> "$raw"
  echo "   linked $(wc -l < "$raw") lines; closure-minify ..."
  if npx --yes google-closure-compiler -W QUIET --compilation_level SIMPLE \
       --js="$raw" --js_output_file="$PP_BUNDLE" 2>"$BUILD/pp-corpus-closure.err"; then
    echo "   [closure] ok: $(du -h "$PP_BUNDLE" | cut -f1)"
  else echo "!! closure failed; raw bundle" >&2; cp "$raw" "$PP_BUNDLE"; fi
}
if [ "$REBUILD_PP" -eq 1 ] || [ ! -s "$PP_BUNDLE" ]; then build_pp_bundle; else echo "   reuse $PP_BUNDLE ($(du -h "$PP_BUNDLE"|cut -f1))"; fi

########################################################################
echo ">> [2/3] assemble the component file list (relpaths under XATSHOME)"
########################################################################
LIST="$BUILD/py-mirror.files"
: > "$LIST"
# 162 frontend SRCDATS (.dats)
awk '/^SRCDATS[ ]*:?=/{c=1} c{print; if(!/\\$/)exit}' "$SRCGEN2/Makefile_xjsemit" \
  | grep -oE '[a-z0-9_]+\.dats' | while read -r f; do echo "srcgen2/DATS/$f"; done >> "$LIST"
# 7 xats2js srcgen1 backend (.dats)
for f in intrep0 intrep0_print0 intrep0_utils0 trxd3i0 trxd3i0_myenv0 trxd3i0_dynexp trxd3i0_decl00; do
  echo "srcgen2/xats2js/srcgen1/DATS/$f.dats" >> "$LIST"; done
# cz0emit + driver
echo "srcgen2/xats2cz/DATS/cz0emit.dats" >> "$LIST"
echo "srcgen2/xats2cz/UTIL/xats2cz_czemit01.dats" >> "$LIST"
# ALL .sats interfaces (full mirror)
( cd "$XATSHOME" && ls srcgen2/SATS/*.sats srcgen2/xats2js/srcgen1/SATS/*.sats srcgen2/xats2cz/SATS/*.sats 2>/dev/null ) >> "$LIST"
ndats=$(grep -c '\.dats$' "$LIST"); nsats=$(grep -c '\.sats$' "$LIST")
echo "   components: $ndats .dats + $nsats .sats = $(wc -l < "$LIST") files"

########################################################################
echo ">> [3/3] pyprint each -> PY/ mirror (.dats->.pdats, .sats->.psats)"
########################################################################
REPORT="$BUILD/py-mirror.report"
: > "$REPORT"
ok=0; todo=0; crash=0; skip=0; n=0
total=$(wc -l < "$LIST")
while read -r rel; do
  [ -z "$rel" ] && continue
  n=$((n+1))
  src="$XATSHOME/$rel"
  [ -f "$src" ] || { echo "MISSING-SRC $rel" >> "$REPORT"; continue; }
  case "$rel" in
    *.sats) stadyn=0; out="$PY/${rel%.sats}.psats";;
    *.dats) stadyn=1; out="$PY/${rel%.dats}.pdats";;
    *) continue;;
  esac
  if [ "$FORCE" -eq 0 ] && [ -s "$out" ]; then skip=$((skip+1)); continue; fi
  mkdir -p "$(dirname "$out")"
  errf="$BUILD/pp-$(echo "$rel" | tr '/.' '__').err"
  # pyprint resolves the source path relative to CWD and needs XATSHOME exported for the
  # prelude load, so run from XATSHOME (out/errf/bundle paths are absolute).
  ( cd "$XATSHOME" && $NODE "$PP_BUNDLE" "$rel" "$stadyn" ) > "$out" 2>"$errf"
  rc=$?
  lines=$(wc -l < "$out" 2>/dev/null || echo 0)
  tmark=$(grep -c "TODO(pp)" "$out" 2>/dev/null || echo 0)
  if [ "$rc" -ne 0 ] || [ "$lines" -lt 1 ]; then
    crash=$((crash+1)); echo "CRASH    $rel (rc=$rc lines=$lines) -> $errf" >> "$REPORT"
  elif [ "$tmark" -gt 0 ]; then
    todo=$((todo+1)); echo "TODO($tmark) $rel ($lines lines)" >> "$REPORT"
  else
    ok=$((ok+1)); echo "OK       $rel ($lines lines)" >> "$REPORT"
  fi
  [ $((n % 20)) -eq 0 ] && echo "   ... $n/$total (ok=$ok todo=$todo crash=$crash skip=$skip)"
done < "$LIST"

echo "======================================================================"
echo ">> PY mirror generated under: $PY"
echo ">> OK=$ok  TODO=$todo  CRASH=$crash  SKIP=$skip  (of $total)"
echo ">> report: $REPORT  (CRASH/TODO lines:)"
grep -E "^CRASH|^TODO|^MISSING" "$REPORT" | head -40
echo "======================================================================"
