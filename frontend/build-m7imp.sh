#!/usr/bin/env bash
########################################################################
# M7-import (task #34) — multi-file `import` build + the SCOPED-merge no-leak GATE.
#
# Builds the M7-import driver (frontend passes incl. the new import lowering in
# pylower_decl00 + a 2-file driver pyfront_m7imp.dats), then in ONE node process checks:
#
#   PROBE U (import-resolve) : TEST/m7imp/m7imp_use.pdats  — `from frontend.TEST.m7imp.lib
#       import lib_double` then `def f(x:Int)->Int: lib_double(x)`. The SCOPED merge of lib.sats's
#       f2env into THIS file's tr12env must make `lib_double` RESOLVE -> nerror=0.
#   PROBE N (NO-LEAK, the CRITICAL gate) : TEST/m7imp/m7imp_noleak.pdats — references
#       `lib_double` but does NOT import lib. Checked in the SAME process AFTER U. The merge is
#       SCOPED (per-file tr12env), NOT the global `filpath_pvsload` pervasive merge, so it must
#       NOT leak -> `lib_double` UNRESOLVED here -> nerror>0. If N resolves, the merge LEAKED and
#       the implementation is WRONG (STOP).
#
# Typecheck-only (no codegen): links runtime + lib2xatsopt (compiler-as-library) + glue + the
# frontend passes + driver — like build-import-spike.sh / build-m5b6-spike.sh. REUSES the prebuilt
# srcgen2/lib/lib2xatsopt.js. jsemit00 + node --stack-size=8801. PURELY ADDITIVE (frontend/BUILD).
#
# Usage:  bash frontend/build-m7imp.sh
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
TESTDIR="$HERE/TEST/m7imp"

mkdir -p "$BUILD"
for f in "$JSEMIT" "$LIB2OPT"; do
  [ -f "$f" ] || { echo "!! required file missing: $f" >&2; exit 1; }
done
for f in "$TESTDIR/lib.sats" "$TESTDIR/m7imp_use.pdats" "$TESTDIR/m7imp_noleak.pdats"; do
  [ -f "$f" ] || { echo "!! required test file missing: $f" >&2; exit 1; }
done

########################################################################
echo ">> [1/3] transpile frontend passes + the M7-import driver (jsemit00)"
########################################################################
DATS=(
  "$HERE/DATS/pylexing_token.dats"
  "$HERE/DATS/pylayout.dats"
  "$HERE/DATS/pyparsing_util.dats"
  "$HERE/DATS/pyparsing_staexp.dats"
  "$HERE/DATS/pyparsing_dynexp.dats"
  "$HERE/DATS/pyparsing_decl00.dats"
  "$HERE/DATS/pyparsing_print.dats"
  "$HERE/DATS/pyelab_util.dats"
  "$HERE/DATS/pyelab_diag.dats"
  "$HERE/DATS/pyelab_lint.dats"
  "$HERE/DATS/pyelab_core.dats"
  "$HERE/DATS/pyelab_loop.dats"
  "$HERE/DATS/pyelab_decl.dats"
  "$HERE/DATS/pyelab_print.dats"
  "$HERE/DATS/pylower_staexp.dats"
  "$HERE/DATS/pylower_dynexp.dats"
  "$HERE/DATS/pylower_decl00.dats"
  "$HERE/DATS/pyfront_m7imp.dats"
)
TRANS_LIST=()
FAILT=0
for d in "${DATS[@]}"; do
  base="$(basename "$d" .dats)"
  tj="$BUILD/${base}_dats.js"
  $NODE "$JSEMIT" "$d" > "$tj" 2>"$BUILD/${base}.err"
  lines="$(wc -l < "$tj")"
  echo "   - $base ($lines lines)"
  if [ "$lines" -lt 5 ]; then
    echo "!! transpile of $base produced too little; see BUILD/${base}.err" >&2
    tail -50 "$BUILD/${base}.err" >&2; FAILT=1
  fi
  if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/${base}.err" 2>/dev/null; then
    echo "!! transpile of $base reported errck — see BUILD/${base}.err" >&2
    grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/${base}.err" | head -20 >&2; FAILT=1
  fi
  TRANS_LIST+=("$tj")
done
[ "$FAILT" -ne 0 ] && { echo ">> M7-import: FAIL (transpile errors above)"; exit 1; }

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
BUNDLE="$BUILD/pyfront-m7imp.js"
cat "${RUNTIME[@]}" > "$BUNDLE"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$BUNDLE"
cat "$HERE/CATS/pylexing.cats"      >> "$BUNDLE"   # PYL_* lexer glue (the lexer .cats refs it)
cat "$HERE/CATS/pyfront_m7imp.cats" >> "$BUNDLE"   # PYI_* driver glue
for tj in "${TRANS_LIST[@]}"; do cat "$tj" >> "$BUNDLE"; done
echo "   linked $(wc -l < "$BUNDLE") lines into $BUNDLE ($(du -h "$BUNDLE" | awk '{print $1}'))"

########################################################################
echo ">> [3/3] run BOTH probes in ONE process (the re-entrancy / no-leak gate)"
########################################################################
ERR="$BUILD/m7imp.stderr"
$NODE "$BUNDLE" "$TESTDIR/m7imp_use.pdats" "$TESTDIR/m7imp_noleak.pdats" > "$BUILD/m7imp.stdout" 2>"$ERR"
RC=$?
echo "----------------------------------------------------------------------"
echo "-- driver output (stderr) --"
grep -vE "d0parsed_from_fpath|MYCDIR" "$ERR" | grep -E "PROBE|nerror|M7-import|UNRESOLVED|----|F3PERR0-ERROR.*m7imp_noleak" | head -30
echo ">> bundle exit code: $RC"

# the two authoritative nerror lines.
U_N="$(grep -oE "\[U:use\][^=]*= *[0-9]+" "$ERR" | grep -oE "[0-9]+$" | head -1)"
N_N="$(grep -oE "\[N:noleak\][^=]*= *[0-9]+" "$ERR" | grep -oE "[0-9]+$" | head -1)"

echo "======================================================================"
echo ">> RESULTS:"
echo "   PROBE U (import-resolve): nerror = ${U_N:-<none>}   (expect 0)"
echo "   PROBE N (no-leak)       : nerror = ${N_N:-<none>}   (expect >0)"
echo "======================================================================"

FAIL=0
if [ "${U_N:-X}" != "0" ]; then
  echo "!! PROBE U FAILED: import did not resolve (nerror=${U_N:-?}; expected 0)." >&2
  echo "   The scoped merge did not make lib_double resolve. f3perr0:" >&2
  grep -E "F3PERR0-ERROR.*m7imp_use" "$ERR" | head -5 >&2
  FAIL=1
fi
if [ -z "${N_N:-}" ] || [ "${N_N:-0}" -le 0 ]; then
  echo "!! PROBE N FAILED (CRITICAL): the no-leak file resolved lib_double (nerror=${N_N:-?})." >&2
  echo "   The merge LEAKED into the global pervasive env — this is the pervasive bug. WRONG." >&2
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then echo ">> M7-import: FAIL"; exit 1; fi
echo ">> M7-import: PASS"
echo "   (U import-resolve nerror=0 — the SCOPED merge resolves the export;"
echo "    N no-leak nerror>0 — the merge is per-file, NOT the leaking global pervasive merge.)"
exit 0
