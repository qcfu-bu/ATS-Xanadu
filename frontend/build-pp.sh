#!/usr/bin/env bash
########################################################################
# BOOTSTRAP PRETTY-PRINTER (P2) — build + run.
#
# Builds `pyprint`: parses a real canonical-ATS file to the stock L0 AST and
# emits our PYTHONIC surface text. Runs it on srcgen2/SATS/xstamp0.sats and
# writes the pythonic to BUILD/xstamp0.pp.psats. Then RE-PARSES that emitted
# file through the M3 driver and reports nerror (target 0 = the tracer success
# criterion: real ATS -> auto-pythonic -> our frontend -> nerror=0).
#
# Typecheck/transpile link (runtime + lib2xatsopt + glue + drivers), same recipe
# as build-abs-spike.sh. REUSES the prebuilt srcgen2/lib/lib2xatsopt.js. PURELY
# ADDITIVE (builds into frontend/BUILD). REUSES BUILD/pyfront-m3.js for re-parse.
#
# Usage:  bash frontend/build-pp.sh [optional-input-file]
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"

JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2OPT="$SRCGEN2/lib/lib2xatsopt.js"
BUILD="$HERE/BUILD"
NODE="node --stack-size=8801"
PP_DATS="$HERE/DATS/pyprint.dats"
DRV_DATS="$HERE/DATS/pyprint_main.dats"
GLUE="$HERE/CATS/pyprint.cats"
INPUT="${1:-srcgen2/SATS/xstamp0.sats}"
OUTPP="$BUILD/xstamp0.pp.psats"

mkdir -p "$BUILD"
for f in "$JSEMIT" "$LIB2OPT"; do
  if [ ! -f "$f" ]; then echo "!! required file missing: $f" >&2; exit 1; fi
done

transpile() {
  local src="$1"; local dst="$2"; local errf="$3"
  $NODE "$JSEMIT" "$src" > "$dst" 2>"$errf"
  echo "   transpiled $(basename "$src") -> $dst ($(wc -l < "$dst") lines)"
  if [ "$(wc -l < "$dst")" -lt 5 ]; then
    echo "!! transpile of $(basename "$src") produced too little; see $errf" >&2
    tail -60 "$errf" >&2; exit 1
  fi
  if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$errf" 2>/dev/null; then
    echo "!! transpile of $(basename "$src") reported errck — see $errf" >&2
    grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$errf" | head -20 >&2
    exit 1
  fi
}

########################################################################
echo ">> [1/4] transpile the pretty-printer module + driver (jsemit00)"
########################################################################
PP_TRANS="$BUILD/pyprint_dats.js"
DRV_TRANS="$BUILD/pyprint_main_dats.js"
transpile "$PP_DATS"  "$PP_TRANS"  "$BUILD/pp-transpile.err"
transpile "$DRV_DATS" "$DRV_TRANS" "$BUILD/pp-main-transpile.err"

########################################################################
echo ">> [2/4] link the bundle (runtime + lib2xatsopt + glue + module + driver)"
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
BUNDLE="$BUILD/pp.js"
cat "${RUNTIME[@]}" > "$BUNDLE"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$BUNDLE"
cat "$GLUE" >> "$BUNDLE"
cat "$PP_TRANS" >> "$BUNDLE"
cat "$DRV_TRANS" >> "$BUNDLE"
echo "   linked $(wc -l < "$BUNDLE") lines into $BUNDLE"

########################################################################
echo ">> [3/4] run pyprint on $INPUT -> $OUTPP"
########################################################################
PPERR="$BUILD/pp.err"
( cd "$XATSHOME" && $NODE "$BUNDLE" "$INPUT" > "$OUTPP" 2>"$PPERR" )
RC=$?
echo "-- driver stderr --"; cat "$PPERR"
echo ">> driver exit code: $RC"
echo "----------------------------------------------------------------------"
echo "-- emitted pythonic ($OUTPP, $(wc -l < "$OUTPP") lines) --"
cat -n "$OUTPP"
echo "----------------------------------------------------------------------"

########################################################################
echo ">> [4/4] RE-PARSE the emitted pythonic through the M3 driver (nerror)"
########################################################################
M3BUNDLE="$BUILD/pyfront-m3.js"
if [ ! -s "$M3BUNDLE" ]; then
  echo "!! $M3BUNDLE missing — run 'bash frontend/build-m3.sh' first." >&2
  echo ">> (pretty-printer output is in $OUTPP; re-parse skipped)" >&2
  exit 1
fi
RPLOG="$BUILD/pp-reparse.log"
$NODE "$M3BUNDLE" "$OUTPP" > "$RPLOG" 2>&1
echo "-- re-parse salient lines --"
grep -E "nerror \(after tread3a\)|RESULT:|parse:|elab-diag" "$RPLOG" | head -40
NERR="$(grep -oE "nerror \(after tread3a\) = [0-9]+" "$RPLOG" | grep -oE "[0-9]+$" | tail -1)"
echo "----------------------------------------------------------------------"
echo ">> PRETTY-PRINTER RE-PARSE nerror (after tread3a) = ${NERR:-?}"
if [ "${NERR:-1}" = "0" ]; then
  echo ">> BUILD-PP: PASS (real ATS -> auto-pythonic -> our frontend -> nerror=0)"
  exit 0
else
  echo "!! BUILD-PP: re-parse nerror != 0 (see $RPLOG)"
  exit 1
fi
