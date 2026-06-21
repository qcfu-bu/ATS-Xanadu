#!/usr/bin/env bash
########################################################################
# ARROW-EFFECTS STAGE-0 SPIKE — build + run the direct-L2 arrow-class probes.
#
# Probes (each constructed DIRECTLY at level-2, no lexer/parser/L1, then run
# through the stock passes trans2a/trsym2b/t2read0/trans23/tread3a):
#   AR-CLOREF   (Int)-<F2CLfun>Int      cloref / bare `->` baseline
#   AR-CLOREFC  (Int)-<F2CLclo(~1)>Int  ref closure via F2CLclo
#   AR-CLO0     (Int)-<F2CLclo(0)>Int   flat closure
#   AR-CLO1     (Int)-<F2CLclo(1)>Int   ptr closure (cloptr)
#   AR-DIST     pass a cloptr value where a cloref param is expected (distinction)
# Per-probe nerror after tread3a is printed; each probe runs in its OWN node
# process (PROBE env) so a hard XATS000_cfail in one is ISOLATED.
#
# Typecheck-only (no codegen). REUSES the prebuilt srcgen2/lib/lib2xatsopt.js.
# PURELY ADDITIVE (builds into frontend/BUILD).
#
# Usage:  bash frontend/build-arrow-spike.sh
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
DRV_DATS="$HERE/DATS/pyfront_arrow_spike.dats"
GLUE="$HERE/CATS/pyfront_arrow_spike.cats"

mkdir -p "$BUILD"
for f in "$JSEMIT" "$LIB2OPT"; do
  if [ ! -f "$f" ]; then echo "!! required file missing: $f" >&2; exit 1; fi
done

########################################################################
echo ">> [1/3] transpile the arrow spike driver (jsemit00)"
########################################################################
DRV_TRANS="$BUILD/pyfront_arrow_spike_dats.js"
$NODE "$JSEMIT" "$DRV_DATS" > "$DRV_TRANS" 2>"$BUILD/arrow-spike-transpile.err"
echo "   transpiled driver -> $DRV_TRANS ($(wc -l < "$DRV_TRANS") lines)"
if [ "$(wc -l < "$DRV_TRANS")" -lt 5 ]; then
  echo "!! arrow driver transpile produced too little; see BUILD/arrow-spike-transpile.err" >&2
  tail -80 "$BUILD/arrow-spike-transpile.err" >&2; exit 1
fi
if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/arrow-spike-transpile.err" 2>/dev/null; then
  echo "!! arrow driver transpile reported errck — see BUILD/arrow-spike-transpile.err" >&2
  grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/arrow-spike-transpile.err" | head -20 >&2
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
BUNDLE="$BUILD/arrow-spike.js"
cat "${RUNTIME[@]}" > "$BUNDLE"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$BUNDLE"
cat "$GLUE" >> "$BUNDLE"
cat "$DRV_TRANS" >> "$BUNDLE"
echo "   linked $(wc -l < "$BUNDLE") lines into $BUNDLE"

########################################################################
echo ">> [3/3] run the spike — EACH probe in its OWN node process"
########################################################################
run_probe () {
  local name="$1"
  local err="$BUILD/arrow-spike-$name.err"
  PROBE="$name" $NODE "$BUNDLE" > /dev/null 2>"$err"
  local rc=$?
  echo "----------------------------------------------------------------------"
  echo "== PROBE $name == (exit=$rc)"
  grep -E 'nerror=|XATS000_cfail|^Error:|RangeError|TypeError|---- PROBE' "$err" | head -30
  if [ $rc -ne 0 ]; then
    echo "   !! PROBE $name CRASHED (exit=$rc) — characterized NO-GO; trace:"
    grep -nE 'XATS000_cfail|unify00_s2typ|unify2a_s2typ|d2exp_t2pckify|trans2a_d2exp_tpck|^Error:|^    at ' "$err" | head -15
  fi
}

for p in AR-CLOREF AR-CLOREFC AR-CLO0 AR-CLO1 AR-DIST; do run_probe "$p"; done

echo "======================================================================"
echo ">> ARROW SPIKE per-probe summary (nerror=0 = structural GO):"
for p in AR-CLOREF AR-CLOREFC AR-CLO0 AR-CLO1 AR-DIST; do
  err="$BUILD/arrow-spike-$p.err"
  line="$(grep -E 'nerror=' "$err" | head -1)"
  if grep -q "XATS000_cfail" "$err"; then
    echo "   $p : CRASH (XATS000_cfail — see $err)"
  elif [ -n "$line" ]; then
    echo "   $p : $line"
  else
    echo "   $p : (no nerror line — see $err)"
  fi
done
