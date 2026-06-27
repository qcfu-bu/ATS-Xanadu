#!/usr/bin/env bash
########################################################################
# build-cz.sh — Python surface ALL THE WAY to Chez Scheme (the bootstrap "emit chez").
#
# Fuses the two proven halves:
#   FRONTEND (build-m3.sh): Pythonic .pdats -> L2 -> L3 (typechecked d3parsed)
#   BACKEND  (xats2cz)     : d3parsed -> trxd3i0 -> intrep0 -> cz0emit -> Chez Scheme
#
# Reuses the xats2cz prebuilt, already-namespaced libs (no 20-min lib rebuild):
#   opt.js1.js      = lib2xatsopt   (frontend/compiler, js1)
#   js.js2.js       = lib2xats2js   (xats2js srcgen1 intrep0 + trxd3i0, js2)
#   lib2xats2cz.js  = cz0emit       (js3 after sed)
# + the cached frontend-pass JS in frontend/BUILD (reused; --retranspile to force).
#
# Then RUNS the bundle on a .pdats, extracts the Scheme between the
# ;;==XATS2CZ-BEGIN==/;;==XATS2CZ-END== sentinels, prepends the xats2cz Chez
# runtime, runs it on Chez, and asserts the expected stdout.
#
# Usage:
#   bash frontend/build-cz.sh                 # build (reuse caches) + run cz_hello + verify
#   bash frontend/build-cz.sh --retranspile   # force re-transpile of the frontend passes
#   bash frontend/build-cz.sh FILE.pdats EXPECTED   # run a specific file, assert stdout
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"
XATS2CZ="$SRCGEN2/xats2cz"
CZBUILD="$XATS2CZ/BUILD"

JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
BUILD="$HERE/BUILD"
mkdir -p "$BUILD"
NODE="node --stack-size=8801"

RETRANSPILE=0
TEST_FILE="$HERE/TEST/cz/cz_hello.pdats"
EXPECTED=$'42\n'
ARGS=()
for a in "$@"; do
  case "$a" in
    --retranspile) RETRANSPILE=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
if [ "${#ARGS[@]}" -ge 1 ]; then TEST_FILE="${ARGS[0]}"; fi
if [ "${#ARGS[@]}" -ge 2 ]; then EXPECTED="${ARGS[1]}"; fi

########################################################################
echo ">> [1/4] prebuilt, pre-namespaced backend libs (from xats2cz/BUILD)"
########################################################################
OPT_JS1="$CZBUILD/opt.js1.js"     # js1 (lib2xatsopt)
JS_JS2="$CZBUILD/js.js2.js"       # js2 (xats2js srcgen1 intrep0 + trxd3i0)
LIB2CZ="$CZBUILD/lib2xats2cz.js"  # js3-pending (cz0emit; sed below)
for f in "$OPT_JS1" "$JS_JS2" "$LIB2CZ"; do
  if [ ! -s "$f" ]; then
    echo "!! missing prebuilt lib: $f" >&2
    echo "   build it first:  (cd $XATS2CZ && make bundle)" >&2
    exit 1
  fi
  echo "   reuse $(basename "$f") ($(wc -l < "$f") lines)"
done

########################################################################
echo ">> [2/4] transpile the cz driver (+ frontend passes if needed)"
########################################################################
# Frontend pass DATS (same set+order as build-m3.sh), then OUR driver.
FE_DATS=(
  "pylexing_token" "pylayout"
  "pyparsing_util" "pyparsing_staexp" "pyparsing_dynexp" "pyparsing_decl00" "pyparsing_print"
  "pyelab_util" "pyelab_diag" "pyelab_lint" "pyelab_core" "pyelab_loop" "pyelab_decl" "pyelab_print"
  "pylower_staexp" "pylower_dynexp" "pylower_decl00"
)
DRIVER="pyfront_cz"

transpile() {
  local base="$1" src="$HERE/DATS/$1.dats" tj="$BUILD/$1_dats.js"
  $NODE "$JSEMIT" "$src" > "$tj" 2>"$BUILD/$1.err"
  local lines; lines="$(wc -l < "$tj")"
  if [ "$lines" -lt 5 ]; then
    echo "!! transpile of $base produced too little ($lines lines); see BUILD/$base.err" >&2
    tail -50 "$BUILD/$base.err" >&2; return 1
  fi
  if grep -qE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/$base.err" 2>/dev/null; then
    echo "!! transpile of $base reported errck/F?PERR0-ERROR — see BUILD/$base.err" >&2
    grep -nE "F2PERR0-ERROR|F3PERR0-ERROR" "$BUILD/$base.err" | head -20 >&2; return 1
  fi
  echo "   - $base ($lines lines)"
  return 0
}

FE_JS=()
for base in "${FE_DATS[@]}"; do
  tj="$BUILD/${base}_dats.js"
  if [ "$RETRANSPILE" -eq 1 ] || [ ! -s "$tj" ]; then
    transpile "$base" || exit 1
  else
    echo "   - $base (cached, $(wc -l < "$tj") lines)"
  fi
  FE_JS+=("$tj")
done
# the driver is new — ALWAYS transpile it.
transpile "$DRIVER" || exit 1
DRV_JS="$BUILD/${DRIVER}_dats.js"

########################################################################
echo ">> [3/4] link bundle (runtime + js1.opt + js2.js + js3.cz + glue + frontend + driver)"
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
BUNDLE="$BUILD/pyfront-cz.js"
BUNDLE_RAW="$BUILD/pyfront-cz.raw.js"
cat "${RUNTIME[@]}" "$OPT_JS1" "$JS_JS2" > "$BUNDLE_RAW"
sed -E 's/jsx(...)tnm/js3\1tnm/g' "$LIB2CZ" >> "$BUNDLE_RAW"
# glue: M1 lexer glue (PYL_*) + M3 driver glue (PYM_*) — both reused verbatim.
cat "$HERE/CATS/pylexing.cats"   >> "$BUNDLE_RAW"
cat "$HERE/CATS/pyfront_m3.cats" >> "$BUNDLE_RAW"
for tj in "${FE_JS[@]}"; do cat "$tj" >> "$BUNDLE_RAW"; done
cat "$DRV_JS" >> "$BUNDLE_RAW"
echo "   linked $(wc -l < "$BUNDLE_RAW") lines ($(du -h "$BUNDLE_RAW" | cut -f1))"

echo "   [closure] minify (SIMPLE) -> $BUNDLE"
if npx --yes google-closure-compiler -W QUIET --compilation_level SIMPLE \
     --js="$BUNDLE_RAW" --js_output_file="$BUNDLE" 2>"$BUILD/pyfront-cz-closure.err"; then
  echo "   [closure] ok: $(du -h "$BUNDLE" | cut -f1)"
else
  echo "!! closure minify failed (see $BUILD/pyfront-cz-closure.err); using raw bundle" >&2
  tail -5 "$BUILD/pyfront-cz-closure.err" >&2 || true
  cp "$BUNDLE_RAW" "$BUNDLE"
fi

########################################################################
echo ">> [4/4] run $TEST_FILE  (.pdats -> Chez -> run -> verify)"
########################################################################
echo "-- the .pdats source --"; cat "$TEST_FILE"
RAW="$BUILD/cz_run.stdout"; ERR="$BUILD/cz_run.stderr"
$NODE "$BUNDLE" "$TEST_FILE" > "$RAW" 2>"$ERR"
RC=$?
echo "-- driver stderr (pipeline progress) --"
grep -vE "d0parsed_from_fpath|MYCDIR" "$ERR" | tail -25
echo ">> bundle exit code: $RC"
FAIL=0
[ "$RC" -ne 0 ] && { echo "!! bundle did not exit 0" >&2; FAIL=1; }
grep -q "RESULT: PASS" "$ERR" || { echo "!! did not reach RESULT: PASS (typecheck must be clean)" >&2; FAIL=1; }

SCM_BODY="$BUILD/cz_run.body.scm"
awk '/^;;==XATS2CZ-BEGIN==/{f=1;next} /^;;==XATS2CZ-END==/{f=0} f' "$RAW" > "$SCM_BODY"
echo ">> emitted Scheme body -> $SCM_BODY ($(wc -l < "$SCM_BODY") lines)"
echo "-- emitted Chez Scheme --"; cat "$SCM_BODY"
if [ "$(wc -c < "$SCM_BODY")" -lt 2 ]; then
  echo "!! no Scheme captured between sentinels" >&2; FAIL=1
elif grep -q 'UNHANDLED\|BODILESS' "$SCM_BODY"; then
  echo "!! emitter produced UNHANDLED/BODILESS nodes" >&2
  grep -n 'UNHANDLED\|BODILESS' "$SCM_BODY" | head >&2; FAIL=1
else
  RUNSCM="$BUILD/cz_run.scm"
  cat "$XATS2CZ/runtime/xats2cz_runtime.scm" "$SCM_BODY" > "$RUNSCM"
  echo "-- RUN emitted program on Chez --"
  chez --script "$RUNSCM" > "$BUILD/cz_run.chezout" 2>"$BUILD/cz_run.chezerr"
  CRC=$?
  echo "chez stdout:"; cat "$BUILD/cz_run.chezout"
  echo ">> chez exit code: $CRC"
  GOT="$(cat "$BUILD/cz_run.chezout")"
  if [ "$CRC" -eq 0 ] && [ "$GOT" = "$(printf '%s' "$EXPECTED")" ]; then
    echo ">> cz PASS  (.pdats -> Chez Scheme -> chez, stdout matches expected)"
  else
    echo "!! cz FAIL  (expected:)" >&2; printf '%s' "$EXPECTED" | cat -A >&2
    echo "got:" >&2; printf '%s' "$GOT" | cat -A >&2
    [ -s "$BUILD/cz_run.chezerr" ] && { echo "-- chez stderr --" >&2; cat "$BUILD/cz_run.chezerr" >&2; }
    FAIL=1
  fi
fi

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> build-cz: FAIL"; exit 1; fi
echo ">> build-cz: PASS (Pythonic source -> Chez Scheme -> runs with correct output)"
exit 0
