#!/usr/bin/env bash
########################################################################
# M7-import (multi-file) GATING SPIKE — build + run the user-module-load proof.
#
# Determines the LOAD+ENV-MERGE recipe for `import M` / `from M import x`: does
# loading an ARBITRARY user `.sats` module via the SAME pervasive loader the pyrt
# prelude uses (filpath_pvsload -> f0_pvsload) make its exported `fun` RESOLVE and
# TYPECHECK at a call site in a separately-built L2 program?
#
#   PROBE I1 (GO/NO-GO) : filpath_pvsload(0, frontend/TEST/m7imp/lib.sats), then
#                         build `def f(x:Int)->Int: lib_double(x)` at L2 and run the
#                         full L2->L3 typecheck. nerror=0 => GO.
#   PROBE I0 (control)  : SAME program WITHOUT the load — lib_double UNRESOLVED ->
#                         nerror>0. Confirms the I1 pass is due to the load.
#
# Typecheck-only (no codegen): links runtime + lib2xatsopt (compiler-as-library) +
# glue + driver, exactly like build-m5b6-spike.sh. REUSES the prebuilt
# srcgen2/lib/lib2xatsopt.js (never rebuilt). jsemit00 + node --stack-size=8801.
# PURELY ADDITIVE (builds into frontend/BUILD).
#
# Usage:  bash frontend/build-import-spike.sh
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
DRV_DATS="$HERE/DATS/pyfront_import_spike.dats"
GLUE="$HERE/CATS/pyfront_import_spike.cats"

mkdir -p "$BUILD"
for f in "$JSEMIT" "$LIB2OPT" "$DRV_DATS" "$GLUE"; do
  if [ ! -f "$f" ]; then echo "!! required file missing: $f" >&2; exit 1; fi
done
if [ ! -f "$HERE/TEST/m7imp/lib.sats" ]; then
  echo "!! the user module frontend/TEST/m7imp/lib.sats is missing" >&2; exit 1
fi

########################################################################
echo ">> [1/3] transpile the import spike driver (jsemit00)"
########################################################################
DRV_TRANS="$BUILD/pyfront_import_spike_dats.js"
$NODE "$JSEMIT" "$DRV_DATS" > "$DRV_TRANS" 2>"$BUILD/import-transpile.err"
echo "   transpiled driver -> $DRV_TRANS ($(wc -l < "$DRV_TRANS") lines)"
if [ "$(wc -l < "$DRV_TRANS")" -lt 5 ]; then
  echo "!! import driver transpile produced too little; see BUILD/import-transpile.err" >&2
  tail -80 "$BUILD/import-transpile.err" >&2; exit 1
fi
# a transpile-time errck (un-instantiated template / bad node) shows as F?PERR0-ERROR.
if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/import-transpile.err" 2>/dev/null; then
  echo "!! import driver transpile reported errck — see BUILD/import-transpile.err" >&2
  grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/import-transpile.err" | head -20 >&2
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
BUNDLE="$BUILD/import-spike.js"
cat "${RUNTIME[@]}" > "$BUNDLE"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$BUNDLE"
cat "$GLUE" >> "$BUNDLE"
cat "$DRV_TRANS" >> "$BUNDLE"
echo "   linked $(wc -l < "$BUNDLE") lines into $BUNDLE"

########################################################################
echo ">> [3/3] run the spike — EACH probe in its OWN node process (so a hard"
echo "         XATS000_cfail in one is ISOLATED, not masking the other)"
########################################################################
run_probe () {
  local name="$1"
  local err="$BUILD/import-spike-$name.err"
  PROBE="$name" $NODE "$BUNDLE" > /dev/null 2>"$err"
  local rc=$?
  echo "----------------------------------------------------------------------"
  echo "== PROBE $name == (exit=$rc)"
  grep -E 'nerror=|XATS000_cfail|^Error:|RangeError|TypeError|---- PROBE|\[I[01]\]|ERROR' "$err" | head -40
  if [ $rc -ne 0 ]; then
    echo "   !! PROBE $name CRASHED (exit=$rc) — characterized NO-GO; trace:"
    grep -nE 'XATS000_cfail|unify00_s2typ|unify2a_s2typ|d2exp_t2pckify|trans2a_d2exp_tpck|^Error:' "$err" | head -10
  fi
}

for p in I0 I1; do run_probe "$p"; done

echo "======================================================================"
echo ">> M7-import SPIKE summary (I1 nerror=0 = GO ; I0 expects nerror>0):"
for p in I0 I1; do
  err="$BUILD/import-spike-$p.err"
  line="$(grep -E 'nerror=' "$err" | head -1)"
  if grep -q "XATS000_cfail" "$err"; then
    echo "   $p : CRASH (XATS000_cfail)"
  elif [ -n "$line" ]; then
    echo "   $p : $line"
  else
    echo "   $p : (no nerror line — see $err)"
  fi
done

# GO/NO-GO verdict.
I1_LINE="$(grep -E 'nerror=' "$BUILD/import-spike-I1.err" | head -1)"
I0_LINE="$(grep -E 'nerror=' "$BUILD/import-spike-I0.err" | head -1)"
I1_N="$(echo "$I1_LINE" | grep -oE 'nerror= *[0-9]+' | grep -oE '[0-9]+')"
I0_N="$(echo "$I0_LINE" | grep -oE 'nerror= *[0-9]+' | grep -oE '[0-9]+')"
echo "======================================================================"
if [ "${I1_N:-X}" = "0" ] && [ "${I0_N:-0}" != "0" ]; then
  echo ">> VERDICT: GO  (I1 nerror=0 with the load ; I0 nerror=$I0_N without it)"
  exit 0
else
  echo ">> VERDICT: NO-GO / INCONCLUSIVE  (I1 nerror=${I1_N:-?} ; I0 nerror=${I0_N:-?})"
  echo "   see BUILD/import-spike-I1.err for the errck text"
  exit 1
fi
