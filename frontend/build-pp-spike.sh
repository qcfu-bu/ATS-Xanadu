#!/usr/bin/env bash
########################################################################
# P2 PRETTY-PRINTER L0-ACCESS SPIKE — build + run.
#
# Proves we can OBTAIN the stock level-0 AST (d0parsed) from a real ATS file
# path and WALK the top-level d0ecl list, dumping each node's tag + name. This
# is the access recipe the whole L0->pythonic pretty-printer is built on.
#
# Typecheck-only link (runtime + lib2xatsopt + glue + driver), same recipe as
# build-abs-spike.sh. REUSES the prebuilt srcgen2/lib/lib2xatsopt.js — never
# rebuilt. PURELY ADDITIVE (builds into frontend/BUILD).
#
# Usage:  bash frontend/build-pp-spike.sh
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
DRV_DATS="$HERE/DATS/pyfront_pp_spike.dats"
GLUE="$HERE/CATS/pyfront_pp_spike.cats"

mkdir -p "$BUILD"
for f in "$JSEMIT" "$LIB2OPT"; do
  if [ ! -f "$f" ]; then echo "!! required file missing: $f" >&2; exit 1; fi
done

########################################################################
echo ">> [1/3] transpile the PP spike driver (jsemit00)"
########################################################################
DRV_TRANS="$BUILD/pyfront_pp_spike_dats.js"
$NODE "$JSEMIT" "$DRV_DATS" > "$DRV_TRANS" 2>"$BUILD/pp-spike-transpile.err"
echo "   transpiled driver -> $DRV_TRANS ($(wc -l < "$DRV_TRANS") lines)"
if [ "$(wc -l < "$DRV_TRANS")" -lt 5 ]; then
  echo "!! PP spike driver transpile produced too little; see BUILD/pp-spike-transpile.err" >&2
  tail -60 "$BUILD/pp-spike-transpile.err" >&2; exit 1
fi
if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/pp-spike-transpile.err" 2>/dev/null; then
  echo "!! PP spike driver transpile reported errck — see BUILD/pp-spike-transpile.err" >&2
  grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/pp-spike-transpile.err" | head -20 >&2
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
BUNDLE="$BUILD/pp-spike.js"
cat "${RUNTIME[@]}" > "$BUNDLE"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$BUNDLE"
cat "$GLUE" >> "$BUNDLE"
cat "$DRV_TRANS" >> "$BUNDLE"
echo "   linked $(wc -l < "$BUNDLE") lines into $BUNDLE"

########################################################################
echo ">> [3/3] run the spike (parse xstamp0.sats; walk d0ecl list; dump tags)"
########################################################################
OUT="$BUILD/pp-spike.out"
ERR="$BUILD/pp-spike.err"
# run FROM XATSHOME so the relative fpath "srcgen2/SATS/xstamp0.sats" resolves.
( cd "$XATSHOME" && $NODE "$BUNDLE" > "$OUT" 2>"$ERR" )
RC=$?
echo "----------------------------------------------------------------------"
echo "-- driver stderr (progress + GO line) --"
cat "$ERR"
echo "----------------------------------------------------------------------"
echo "-- driver stdout (the dumped d0ecl tags + names) --"
cat "$OUT"
echo "----------------------------------------------------------------------"
echo ">> driver exit code: $RC"

if grep -q "RESULT: GO" "$ERR"; then
  echo ">> PP-SPIKE: GO (obtained + walked the L0 d0ecl list)"
  exit 0
else
  echo "!! PP-SPIKE: NO-GO (could not walk the L0 AST)" >&2
  exit 1
fi
