#!/usr/bin/env bash
########################################################################
# ABS GATING SPIKE — build + run the direct-L2 DATATYPE-construction proof.
#
# Proves: a `D2Cdatatype` decl (enum Opt with Nothing/Just(Int)) + a function
# that pattern-matches over it can be CONSTRUCTED DIRECTLY at level-2 (no lexer/
# parser, no L1) and TYPECHECK to nerror=0 through the stock compiler passes
# (trans2a/trsym2b/t2read0/trans23/tread3a).
#
# Typecheck-only (no codegen): links runtime + lib2xatsopt (the compiler-as-a-
# library) + glue + driver, exactly like build-spike.sh PATH A. REUSES the
# prebuilt srcgen2/lib/lib2xatsopt.js (~171MB) — never rebuilt. jsemit00 +
# node --stack-size=8801. PURELY ADDITIVE (builds into frontend/BUILD).
#
# Usage:  bash frontend/build-abs-spike.sh
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
DRV_DATS="$HERE/DATS/pyfront_abs_spike.dats"
GLUE="$HERE/CATS/pyfront_abs_spike.cats"

mkdir -p "$BUILD"
for f in "$JSEMIT" "$LIB2OPT"; do
  if [ ! -f "$f" ]; then echo "!! required file missing: $f" >&2; exit 1; fi
done

########################################################################
echo ">> [1/3] transpile the ABS spike driver (jsemit00)"
########################################################################
DRV_TRANS="$BUILD/pyfront_abs_spike_dats.js"
$NODE "$JSEMIT" "$DRV_DATS" > "$DRV_TRANS" 2>"$BUILD/abs-transpile.err"
echo "   transpiled driver -> $DRV_TRANS ($(wc -l < "$DRV_TRANS") lines)"
if [ "$(wc -l < "$DRV_TRANS")" -lt 5 ]; then
  echo "!! ABS driver transpile produced too little; see BUILD/abs-transpile.err" >&2
  tail -60 "$BUILD/abs-transpile.err" >&2; exit 1
fi
# a transpile-time errck (un-instantiated template / bad node) shows as F?PERR0-ERROR.
if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/abs-transpile.err" 2>/dev/null; then
  echo "!! ABS driver transpile reported errck — see BUILD/abs-transpile.err" >&2
  grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/abs-transpile.err" | head -20 >&2
  exit 1
fi

########################################################################
echo ">> [2/3] link the typecheck bundle (runtime + lib2xatsopt + glue + driver)"
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
BUNDLE="$BUILD/abs-spike.js"
cat "${RUNTIME[@]}" > "$BUNDLE"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$BUNDLE"
cat "$GLUE" >> "$BUNDLE"
cat "$DRV_TRANS" >> "$BUNDLE"
echo "   linked $(wc -l < "$BUNDLE") lines into $BUNDLE"

########################################################################
echo ">> [3/3] run the spike (build the datatype+match at L2; typecheck)"
########################################################################
OUT="$BUILD/abs-spike.out"
ERR="$BUILD/abs-spike.err"
$NODE "$BUNDLE" > "$OUT" 2>"$ERR"
RC=$?
echo "----------------------------------------------------------------------"
echo "-- driver stderr (progress + nerror + f3perr0 diagnostics) --"
cat "$ERR"
echo "----------------------------------------------------------------------"
echo ">> driver exit code: $RC"

NERR_LINE="$(grep -E 'nerror \(after tread3a\) =' "$ERR" | head -1)"
echo "   $NERR_LINE"
if echo "$NERR_LINE" | grep -qE 'nerror \(after tread3a\) = 0$' && grep -q "RESULT: PASS" "$ERR"; then
  echo ">> ABS-SPIKE: PASS (direct-L2 datatype decl + match typecheck, nerror=0)"
  exit 0
else
  echo "!! ABS-SPIKE: FAIL (datatype/match did NOT typecheck nerror=0)" >&2
  echo "--- f3perr0 diagnostics (stock reporter) ---" >&2
  grep -E 'F2PERR0-ERROR|F3PERR0-ERROR' "$ERR" | head -30 >&2
  exit 1
fi
