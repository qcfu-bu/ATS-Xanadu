#!/usr/bin/env bash
########################################################################
# A-TEMPLATE GATING SPIKE — build + run the direct-L2 template construction probes.
#
# Probes (each constructed DIRECTLY at level-2, no lexer/parser/L1, then run
# through the stock passes trans2a/trsym2b/t2read0/trans23/tread3a):
#   T1  template DECLARATION    extern fun{a:t@ype} id(x:a):a
#   T2  template DECL + BODY     T1 + implement{a} id(x) = x
#   T3  DECL + BODY + INSTANTIATION  T1 + T2 + def main()=id<int>(5)
#   T4  BOTH brackets coexist    extern fun{a} foo{c}(x:a,y:c):c + foo<int>(5,7)
# Per-probe nerror after tread3a is printed; each probe runs in its OWN node
# process (PROBE env) so a hard XATS000_cfail in one is ISOLATED.
#
# The make-or-break question: template RESOLUTION happens in trtmp3b/trtmp3c, which
# run AFTER tread3a. So a declared+instantiated-but-not-codegen'd template should
# reach nerror=0 structurally — this spike proves it.
#
# Typecheck-only (no codegen): links runtime + lib2xatsopt (compiler-as-library)
# + glue + driver. REUSES the prebuilt srcgen2/lib/lib2xatsopt.js (never rebuilt).
# jsemit00 + node --stack-size=8801. PURELY ADDITIVE (builds into frontend/BUILD).
#
# Usage:  bash frontend/build-atmpl-spike.sh
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
DRV_DATS="$HERE/DATS/pyfront_atmpl_spike.dats"
GLUE="$HERE/CATS/pyfront_atmpl_spike.cats"

mkdir -p "$BUILD"
for f in "$JSEMIT" "$LIB2OPT" "$DRV_DATS" "$GLUE"; do
  if [ ! -f "$f" ]; then echo "!! required file missing: $f" >&2; exit 1; fi
done

########################################################################
echo ">> [1/3] transpile the atmpl spike driver (jsemit00)"
########################################################################
DRV_TRANS="$BUILD/pyfront_atmpl_spike_dats.js"
$NODE "$JSEMIT" "$DRV_DATS" > "$DRV_TRANS" 2>"$BUILD/atmpl-transpile.err"
echo "   transpiled driver -> $DRV_TRANS ($(wc -l < "$DRV_TRANS") lines)"
if [ "$(wc -l < "$DRV_TRANS")" -lt 5 ]; then
  echo "!! atmpl driver transpile produced too little; see BUILD/atmpl-transpile.err" >&2
  tail -80 "$BUILD/atmpl-transpile.err" >&2; exit 1
fi
# a transpile-time errck (bad node / wrong maker) shows as F?PERR0-ERROR.
if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/atmpl-transpile.err" 2>/dev/null; then
  echo "!! atmpl driver transpile reported errck — see BUILD/atmpl-transpile.err" >&2
  grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/atmpl-transpile.err" | head -20 >&2
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
BUNDLE="$BUILD/atmpl-spike.js"
cat "${RUNTIME[@]}" > "$BUNDLE"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$BUNDLE"
cat "$GLUE" >> "$BUNDLE"
cat "$DRV_TRANS" >> "$BUNDLE"
echo "   linked $(wc -l < "$BUNDLE") lines into $BUNDLE"

########################################################################
echo ">> [3/3] run the spike — EACH probe in its OWN node process (so a hard"
echo "         XATS000_cfail in one probe is ISOLATED, not masking the others)"
########################################################################
run_probe() {
  local name="$1"
  local err="$BUILD/atmpl-spike-$name.err"
  PROBE="$name" $NODE "$BUNDLE" > /dev/null 2>"$err"
  local rc=$?
  echo "----------------------------------------------------------------------"
  echo "== PROBE $name == (exit=$rc)"
  grep -E 'nerror \(after tread3a\) =|XATS000_cfail|^Error:|RangeError|TypeError|---- T|F3PERR0-ERROR' "$err" | head -40
  if [ $rc -ne 0 ]; then
    echo "   !! PROBE $name CRASHED (exit=$rc) — characterized NO-GO; trace:"
    grep -nE 'XATS000_cfail|unify00_s2typ|unify2a_s2typ|d2exp_t2pckify|^Error:|^    at ' "$err" | head -15
  fi
}

for p in T1 T2 T3 T4 T5; do run_probe "$p"; done

echo "======================================================================"
echo ">> A-TEMPLATE SPIKE per-probe summary (T1-T4: nerror=0 = structural GO;"
echo "                                       T5 NEG CONTROL: nerror>0 = GO):"
ALLGO=1
# T1-T4 expect nerror=0 (structural GO).
for p in T1 T2 T3 T4; do
  err="$BUILD/atmpl-spike-$p.err"
  line="$(grep -E 'nerror \(after tread3a\) =' "$err" | head -1)"
  n="$(echo "$line" | grep -oE '[0-9]+$')"
  if grep -q "XATS000_cfail" "$err"; then
    echo "   $p : CRASH (XATS000_cfail — see $err)"; ALLGO=0
  elif [ "${n:-X}" = "0" ]; then
    echo "   $p : GO   ($line)"
  elif [ -n "$line" ]; then
    echo "   $p : NO-GO ($line)"; ALLGO=0
  else
    echo "   $p : (no nerror line — see $err)"; ALLGO=0
  fi
done
# T5 is the NEGATIVE control: it MUST produce nerror>0 (proving tread3a actually checks
# the instantiated arg type — so T3's nerror=0 is meaningful, not a silent no-op).
err5="$BUILD/atmpl-spike-T5.err"
line5="$(grep -E 'nerror \(after tread3a\) =' "$err5" | head -1)"
n5="$(echo "$line5" | grep -oE '[0-9]+$')"
if grep -q "XATS000_cfail" "$err5"; then
  echo "   T5 : CRASH (XATS000_cfail — see $err5)"; ALLGO=0
elif [ -n "$n5" ] && [ "$n5" -gt 0 ] 2>/dev/null; then
  echo "   T5 : GO   ($line5 — NEG control correctly REJECTS the mismatch)"
else
  echo "   T5 : NO-GO ($line5 — NEG control did NOT reject; T3 nerror=0 would be a no-op!)"; ALLGO=0
fi
echo "======================================================================"
if [ "$ALLGO" -eq 1 ]; then
  echo ">> A-TEMPLATE SPIKE: PASS (T1-T4 all reach nerror=0 through tread3a — templates"
  echo "      DECLARE + BODY + INSTANTIATE structurally; resolution deferred to trtmp3b/3c)."
  exit 0
else
  echo "!! A-TEMPLATE SPIKE: see per-probe NO-GO/CRASH above + BUILD/atmpl-spike-*.err"
  exit 1
fi
