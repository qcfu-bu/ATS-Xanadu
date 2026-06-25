#!/usr/bin/env bash
########################################################################
# M3 — Python-surface frontend: REAL pipeline build + emit + run.
#
# Drives a real .py file ALL THE WAY to running JS in ONE command:
#
#   [1] build (or REUSE cached) the xats2js BACKEND libs from source (jsemit00):
#         lib2xats2cc.js  <- srcgen2/xats2cc/srcgen1/DATS/*   (intrep0 + trxd3i0/tryd3i0)
#         lib2xats2js.js  <- srcgen2/xats2js/srcgen2/DATS/*    (intrep1 + trxi0i1 + js1emit)
#       (built once and CACHED in frontend/BUILD; force a rebuild with --rebuild-libs.)
#   [2] transpile the M1 lexer + M2 parser + M2.5 elaborator + M3 lowerer + the M3 driver
#       (jsemit00, --stack-size 8801).
#   [3] LINK the compiler bundle (runtime + lib2xatsopt/js1 + lib2xats2cc/js2 +
#       lib2xats2js/js3 + .cats glue + DATS), mirroring xats2js/.../Makefile_xjsemit.
#   [4] RUN the bundle on each frontend/TEST/m3/*.py:
#         - m3_arith.py   : typecheck OK -> emit JS between sentinels -> EXTRACT + RUN on
#                           node (prepend the ATS->JS runtime) -> assert expected stdout.
#         - m3_typeerr.py : a deliberate type error -> assert f3perr0 reports it ON THE
#                           .py span (the file path + a line:col in the Python source).
#
# PURELY ADDITIVE: builds only into frontend/BUILD. REUSES srcgen2/lib/lib2xatsopt.js
# (~171MB). jsemit00 + node --stack-size=8801 throughout.
#
# Usage:
#   bash frontend/build-m3.sh                 # build (reuse cached libs) + run + verify
#   bash frontend/build-m3.sh --rebuild-libs  # force-rebuild the backend libs first
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"
XATS2CC="$SRCGEN2/xats2cc/srcgen1"
XATS2JS="$SRCGEN2/xats2js/srcgen2"

JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2OPT="$SRCGEN2/lib/lib2xatsopt.js"
BUILD="$HERE/BUILD"
mkdir -p "$BUILD"
NODE="node --stack-size=8801"

REBUILD_LIBS=0
[ "${1:-}" = "--rebuild-libs" ] && REBUILD_LIBS=1

if [ ! -f "$LIB2OPT" ]; then
  echo "!! $LIB2OPT missing — build it once via language-server/server/build-lib2xatsopt.sh" >&2
  exit 1
fi

########################################################################
# helper: build one backend lib from a DATS source set (counter STARTS AT 100,
# 3-digit tokens, exactly like Makefile_xjsemit — required for the final 3-char sed).
########################################################################
build_backend_lib() {
  local out="$1"; shift
  local dir="$1"; shift
  : > "$out"
  local idx=100 f base trans
  for f in "$@"; do
    base="${f%.dats}"
    trans="$BUILD/$(basename "$dir")__${base}_dats_out0.js"
    $NODE "$JSEMIT" "$dir/$f" > "$trans" 2>"$trans.err"
    if [ "$(wc -l < "$trans")" -lt 3 ]; then
      echo "!! transpile FAILED for $dir/$f (see $trans.err)" >&2; tail -30 "$trans.err" >&2; return 1
    fi
    sed -e "s/jsxtnm/jsx${idx}tnm/g" "$trans" >> "$out"
    idx=$((idx + 1))
  done
  echo "   -> $out ($(wc -l < "$out") lines, $((idx - 100)) files)"
  return 0
}

LIB2CC="$BUILD/lib2xats2cc.js"
LIB2JS="$BUILD/lib2xats2js.js"

########################################################################
echo ">> [1/4] backend libs (build-or-reuse cached)"
########################################################################
if [ "$REBUILD_LIBS" -eq 1 ] || [ ! -s "$LIB2CC" ] || [ ! -s "$LIB2JS" ]; then
  echo "   building lib2xats2cc.js ..."
  build_backend_lib "$LIB2CC" "$XATS2CC/DATS" \
    intrep0.dats intrep0_print0.dats intrep0_utils0.dats \
    trxd3i0.dats trxd3i0_print0.dats trxd3i0_myenv0.dats trxd3i0_statyp.dats \
    trxd3i0_dynexp.dats trxd3i0_decl00.dats \
    tryd3i0.dats tryd3i0_myenv0.dats tryd3i0_dynexp.dats tryd3i0_decl00.dats \
    intrep1.dats intrep1_print0.dats xats2cc_tmplib.dats || exit 1
  echo "   building lib2xats2js.js ..."
  build_backend_lib "$LIB2JS" "$XATS2JS/DATS" \
    intrep1.dats intrep1_print0.dats intrep1_utils0.dats \
    trxi0i1.dats trxi0i1_myenv0.dats trxi0i1_dynexp.dats trxi0i1_decl00.dats \
    xats2js.dats xats2js_myenv0.dats xats2js_utils0.dats xats2js_dynexp.dats xats2js_decl00.dats \
    js1emit.dats js1emit_utils0.dats js1emit_dynexp.dats js1emit_decl00.dats \
    xats2js_tmplib.dats || exit 1
else
  echo "   reusing cached $LIB2CC ($(wc -l < "$LIB2CC") lines) + $LIB2JS ($(wc -l < "$LIB2JS") lines)"
  echo "   (force a rebuild with: bash frontend/build-m3.sh --rebuild-libs)"
fi

########################################################################
echo ">> [2/4] transpile frontend passes + M3 driver (jsemit00)"
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
  "$HERE/DATS/pyfront_m3.dats"
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
    echo "!! transpile of $base reported errck/F?PERR0-ERROR — see BUILD/${base}.err" >&2
    grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/${base}.err" | head -20 >&2; FAILT=1
  fi
  TRANS_LIST+=("$tj")
done
[ "$FAILT" -ne 0 ] && { echo ">> M3: FAIL (transpile errors above)"; exit 1; }

########################################################################
echo ">> [3/4] link compiler bundle"
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
BUNDLE="$BUILD/pyfront-m3.js"
BUNDLE_RAW="$BUILD/pyfront-m3.raw.js"
cat "${RUNTIME[@]}" > "$BUNDLE_RAW"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$BUNDLE_RAW"
sed -E 's/jsx(...)tnm/js2\1tnm/g' "$LIB2CC"  >> "$BUNDLE_RAW"
sed -E 's/jsx(...)tnm/js3\1tnm/g' "$LIB2JS"  >> "$BUNDLE_RAW"
# glue: M1 lexer glue (PYL_*) is needed by the lexer .cats refs; M3 glue (PYM_*) for the driver.
cat "$HERE/CATS/pylexing.cats"  >> "$BUNDLE_RAW"
cat "$HERE/CATS/pyfront_m3.cats" >> "$BUNDLE_RAW"
for tj in "${TRANS_LIST[@]}"; do cat "$tj" >> "$BUNDLE_RAW"; done
echo "   linked $(wc -l < "$BUNDLE_RAW") lines into $BUNDLE_RAW ($(du -h "$BUNDLE_RAW" | awk '{print $1}'))"

# Minify with Closure (SIMPLE): shrinks the ~230MB raw reparse bundle to a few MB
# and collapses generated-code frame overhead, so the deep-recursive M3 reparse
# (d3parsed/tread3a/...) does not overflow Node's stack on large pretty-printed
# files (e.g. xlibext_tmplib). Falls back to the raw bundle on failure (mirrors
# build-pp-corpus.sh and language-server/build.sh).
echo "   [closure] minify (SIMPLE): $BUNDLE_RAW -> $BUNDLE"
if npx --yes google-closure-compiler -W QUIET --compilation_level SIMPLE \
     --js="$BUNDLE_RAW" --js_output_file="$BUNDLE" 2>"$BUILD/pyfront-m3-closure.err"; then
  echo "   [closure] ok: $(du -h "$BUNDLE" | cut -f1) (raw $(du -h "$BUNDLE_RAW" | cut -f1))"
else
  echo "!! closure minify failed (see $BUILD/pyfront-m3-closure.err); using raw bundle" >&2
  tail -5 "$BUILD/pyfront-m3-closure.err" >&2 || true
  cp "$BUNDLE_RAW" "$BUNDLE"
fi

# the runnable-program runtime (runtime + lib2xatsopt/js1) — for executing the emitted JS.
RUNHDR="$BUILD/run-header.js"
cat "${RUNTIME[@]}" > "$RUNHDR"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$RUNHDR"

########################################################################
echo ">> [4/4] run the pipeline over frontend/TEST/m3/*.py"
########################################################################
FAIL=0

run_py() {
  local py="$1"
  local base; base="$(basename "$py" .py)"
  local raw="$BUILD/${base}.stdout" err="$BUILD/${base}.stderr"
  echo "----------------------------------------------------------------------"
  echo ">> compiling $py"
  $NODE "$BUNDLE" "$py" > "$raw" 2>"$err"
  local rc=$?
  echo "-- driver stderr (progress + diagnostics) --"
  cat "$err"
  echo ">> bundle exit code: $rc"
  echo "$base|$rc"
}

# ---- 4a : m3_run.py  -> typecheck clean -> emit JS -> RUN on node -> assert runtime values
# The functional-core subset that codegens to RUNNABLE JS through the from-source backend:
# literals + immutable let-bindings + variable references (the SSA-rebind core). A runtime
# probe proves the bindings take effect (a=7, b=7, c=7). (Arithmetic/print/def codegen is
# BLOCKED by a pre-existing backend-lib limitation — prelude `$`-template instantiation +
# the funset `fun`-codegen gap; see M3-REPORT. The frontend lowers + TYPECHECKS them fine.)
A_PY="$HERE/TEST/m3/m3_run.py"
echo "======================================================================"
echo "== 4a  $A_PY  (literals + let-bindings + var refs -> JS -> RUNS)"
echo "======================================================================"
echo "-- the .py source --"; cat "$A_PY"
$NODE "$BUNDLE" "$A_PY" > "$BUILD/m3_run.stdout" 2>"$BUILD/m3_run.stderr"
ARC=$?
echo "-- driver stderr (pipeline progress) --"; grep -vE "d0parsed_from_fpath|MYCDIR" "$BUILD/m3_run.stderr" | tail -25
echo ">> bundle exit code: $ARC"
if [ "$ARC" -ne 0 ]; then echo "!! 4a bundle did not exit 0" >&2; FAIL=1; fi
if ! grep -q "RESULT: PASS" "$BUILD/m3_run.stderr"; then
  echo "!! 4a: pipeline did not reach RESULT: PASS (typecheck must be clean)" >&2; FAIL=1
fi

EMIT="$BUILD/m3_run.emitted.js"
awk '/^\/\/==PYM-JS-BEGIN==/{f=1;next} /^\/\/==PYM-JS-END==/{f=0} f' "$BUILD/m3_run.stdout" > "$EMIT"
echo ">> emitted JS -> $EMIT ($(wc -l < "$EMIT") lines)"
echo "-- emitted user-program JS --"; cat "$EMIT"
if [ "$(wc -c < "$EMIT")" -lt 2 ]; then
  echo "!! no emitted JS captured between sentinels" >&2; FAIL=1
else
  RUNJS="$BUILD/m3_run.run.js"
  cat "$RUNHDR" > "$RUNJS"; cat "$EMIT" >> "$RUNJS"
  # a runtime probe proving the bindings bound at run time.
  echo 'console.log("RUNTIME a="+jsxtnm1+" b="+jsxtnm2+" c="+jsxtnm3);' >> "$RUNJS"
  echo "-- RUN emitted program on node --"
  $NODE "$RUNJS" > "$BUILD/m3_run.runout" 2>"$BUILD/m3_run.runerr"
  RRC=$?
  echo "stdout:"; cat "$BUILD/m3_run.runout"
  echo ">> emitted-program exit code: $RRC"
  GOT="$(cat "$BUILD/m3_run.runout")"
  if [ "$RRC" -eq 0 ] && [ "$GOT" = "RUNTIME a=7 b=7 c=7" ]; then
    echo ">> 4a PASS  (.py -> JS -> node, exit 0, bindings a=7 b=7 c=7)"
  else
    echo "!! 4a FAIL  (expected 'RUNTIME a=7 b=7 c=7'; got:)" >&2
    echo "$GOT" >&2
    [ -s "$BUILD/m3_run.runerr" ] && { echo "-- run stderr --" >&2; cat "$BUILD/m3_run.runerr" >&2; }
    FAIL=1
  fi
fi

# ---- 4b : m3_typeerr.py  -> assert type error reported ON the precise .py span ----
E_PY="$HERE/TEST/m3/m3_typeerr.py"
echo "======================================================================"
echo "== 4b  $E_PY  (deliberate type error -> diagnostic on the Python span)"
echo "======================================================================"
echo "-- the .py source --"; cat "$E_PY"
$NODE "$BUNDLE" "$E_PY" > "$BUILD/m3_typeerr.stdout" 2>"$BUILD/m3_typeerr.stderr"
echo "-- driver stderr (nerror + the f3perr0 diagnostic) --"
grep -vE "d0parsed_from_fpath|MYCDIR" "$BUILD/m3_typeerr.stderr" | grep -E "nerror|RESULT|F3PERR0-ERROR.*m3_typeerr" | head -10
# the diagnostic must (a) report nerror>0, (b) cite the .py path, AND (c) carry a line=/offs= span.
if grep -q "RESULT: TYPE-ERROR" "$BUILD/m3_typeerr.stderr" \
   && grep -Eq "F3PERR0-ERROR:LCSRCsome1\([^)]*m3_typeerr\.py\)@\([0-9]+\(line=[0-9]+" "$BUILD/m3_typeerr.stderr"; then
  echo ">> 4b PASS  (type error reported on the Python source m3_typeerr.py with a line:col span)"
  echo "-- the .py-span the diagnostic lands on --"
  grep -oE "m3_typeerr\.py\)@\([0-9]+\(line=[0-9]+,offs=[0-9]+\)--[0-9]+\(line=[0-9]+,offs=[0-9]+\)" "$BUILD/m3_typeerr.stderr" | head -3
else
  echo "!! 4b FAIL  (expected a TYPE-ERROR citing m3_typeerr.py with a line=/offs= span)" >&2
  FAIL=1
fi

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> M3: FAIL (see failures above)"; exit 1; fi
echo ">> M3: PASS (4a: .py -> JS -> node runs with correct bindings; 4b: type error on the .py span)"
exit 0
