#!/usr/bin/env bash
########################################################################
# M5b.4/.5 GATING SPIKE — build + run the direct-L2 D2Csexpdef (type alias)
# + S2Etrcd (record/struct) construction proof.
#
# Proves (or characterizes the blocker for):
#   (.5) type X = <rhs>  -> a D2Csexpdef(s2cst, rhs) node  (probes A, B, B')
#   (.4) struct/record   -> a D2Csexpdef(Point, S2Etrcd…)  (probes C, C2)
# each constructed DIRECTLY at level-2 (no lexer/parser, no L1) and run through
# the stock passes (trans2a/trsym2b/t2read0/trans23/tread3a). Per-probe nerror
# after tread3a is printed.
#
# Typecheck-only (no codegen): links runtime + lib2xatsopt (compiler-as-library)
# + glue + driver, exactly like build-m5b-spike.sh. REUSES the prebuilt
# srcgen2/lib/lib2xatsopt.js (never rebuilt). jsemit00 + node --stack-size=8801.
# PURELY ADDITIVE (builds into frontend/BUILD).
#
# Usage:  bash frontend/build-m5b45-spike.sh
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
DRV_DATS="$HERE/DATS/pyfront_m5b45_spike.dats"
GLUE="$HERE/CATS/pyfront_m5b45_spike.cats"

mkdir -p "$BUILD"
for f in "$JSEMIT" "$LIB2OPT"; do
  if [ ! -f "$f" ]; then echo "!! required file missing: $f" >&2; exit 1; fi
done

########################################################################
echo ">> [1/3] transpile the M5b.4/.5 spike driver (jsemit00)"
########################################################################
DRV_TRANS="$BUILD/pyfront_m5b45_spike_dats.js"
$NODE "$JSEMIT" "$DRV_DATS" > "$DRV_TRANS" 2>"$BUILD/m5b45-transpile.err"
echo "   transpiled driver -> $DRV_TRANS ($(wc -l < "$DRV_TRANS") lines)"
if [ "$(wc -l < "$DRV_TRANS")" -lt 5 ]; then
  echo "!! M5b.4/.5 driver transpile produced too little; see BUILD/m5b45-transpile.err" >&2
  tail -80 "$BUILD/m5b45-transpile.err" >&2; exit 1
fi
# a transpile-time errck (un-instantiated template / bad node) shows as F?PERR0-ERROR.
if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/m5b45-transpile.err" 2>/dev/null; then
  echo "!! M5b.4/.5 driver transpile reported errck — see BUILD/m5b45-transpile.err" >&2
  grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/m5b45-transpile.err" | head -20 >&2
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
BUNDLE="$BUILD/m5b45-spike.js"
cat "${RUNTIME[@]}" > "$BUNDLE"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$BUNDLE"
cat "$GLUE" >> "$BUNDLE"
cat "$DRV_TRANS" >> "$BUNDLE"
echo "   linked $(wc -l < "$BUNDLE") lines into $BUNDLE"

########################################################################
echo ">> [3/3] run the spike — EACH probe in its OWN node process (so a hard"
echo "         XATS000_cfail in the HAZARD probe is ISOLATED, not masking others)"
########################################################################
run_probe () {
  local name="$1"
  local err="$BUILD/m5b45-spike-$name.err"
  PROBE="$name" $NODE "$BUNDLE" > /dev/null 2>"$err"
  local rc=$?
  echo "----------------------------------------------------------------------"
  echo "== PROBE $name == (exit=$rc)"
  # the probe's nerror line + any crash signature + the f3perr0 reporter.
  grep -E 'nerror=|XATS000_cfail|^Error:|RangeError|TypeError|---- PROBE' "$err" | head -20
  if [ $rc -ne 0 ]; then
    echo "   !! PROBE $name CRASHED (exit=$rc) — characterized NO-GO; trace:"
    grep -nE 'XATS000_cfail|unify00_s2typ|unify2a_s2typ|d2exp_t2pckify|trans2a_d2exp_tpck|^Error:' "$err" | head -10
  fi
}

for p in A B Bp C2 C C3 C4; do run_probe "$p"; done

echo "======================================================================"
echo ">> M5b.4/.5 SPIKE per-probe summary (nerror=0 = GO):"
for p in A B Bp C2 C C3 C4; do
  err="$BUILD/m5b45-spike-$p.err"
  line="$(grep -E 'nerror=' "$err" | head -1)"
  if grep -q "XATS000_cfail" "$err"; then
    echo "   $p : CRASH (XATS000_cfail in unify00_s2typ)"
  elif [ -n "$line" ]; then
    echo "   $p : $line"
  else
    echo "   $p : (no nerror line — see $err)"
  fi
done
