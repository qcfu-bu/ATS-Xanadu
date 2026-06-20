#!/usr/bin/env bash
########################################################################
# M0b — Python-surface frontend: CODEGEN-spine build + emit + run.
#
# Closes the "compile to JS" tracer bullet end-to-end, in ONE command:
#
#   [1] build the xats2js BACKEND libs from source (jsemit00), namespaced and
#       concatenated exactly like the stock Makefiles:
#         lib2xats2cc.js  <- srcgen2/xats2cc/srcgen1/DATS/*  (intrep0 + trxd3i0/tryd3i0)
#         lib2xats2js.js  <- srcgen2/xats2js/srcgen2/DATS/*  (intrep1 + trxi0i1 + js1emit)
#       (these prebuilt libs do NOT ship; srcgen2/xats2js/.../lib/ holds only .keeper)
#   [2] transpile the M0b driver (jsemit00)         -> pyfront_m0b_dats.js
#       transpile the reused M0a driver (jsemit00)  -> pyfront_dats.js
#   [3] LINK the compiler bundle, mirroring xats2js/srcgen2/UTIL/Makefile_xjsemit
#       (the recipe that builds xats2js_jsemit01):
#         runtime
#         + lib2xatsopt.js  (sed jsx -> js1)   [REUSED prebuilt, ~171MB]
#         + lib2xats2cc.js  (sed jsx -> js2)   [built in step 1]
#         + lib2xats2js.js  (sed jsx -> js3)   [built in step 1]
#         + frontend .cats glue + M0a driver + M0b driver
#   [4] RUN the bundle on node: it emits the USER PROGRAM's JS to stdout,
#       bracketed by //==PYF2-JS-BEGIN==/ //==PYF2-JS-END== sentinels.
#   [5] EXTRACT the emitted user JS, PREPEND the ATS->JS runtime, and RUN it on
#       node — proving the emitted program executes cleanly (exit 0).
#
# PURELY ADDITIVE: builds only into frontend/BUILD and the stock (gitignored,
# .keeper-only) backend lib/ dirs; never edits tracked srcgen2/ sources. M0a's
# build-m0a.sh is untouched and still passes.
#
# REUSES the prebuilt srcgen2/lib/lib2xatsopt.js (~171MB) — never rebuilt here.
# Uses jsemit00 (NOT jsemit01), node --stack-size=8801 throughout.
#
# Usage:   bash frontend/build-m0b.sh
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"
XATS2CC="$SRCGEN2/xats2cc/srcgen1"
XATS2JS="$SRCGEN2/xats2js/srcgen2"

# jsemit00 (NOT jsemit01) — same transpiler lib2xatsopt.js was built with.
JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
LIB2OPT="$SRCGEN2/lib/lib2xatsopt.js"

BUILD="$HERE/BUILD"
mkdir -p "$BUILD"

NODE="node --stack-size=8801"

if [ ! -f "$LIB2OPT" ]; then
  echo "!! $LIB2OPT missing — build it once via language-server/server/build-lib2xatsopt.sh" >&2
  exit 1
fi

########################################################################
# helper: build one backend lib from a DATS source set.
#   $1 = lib output path
#   $2 = DATS source dir
#   $3.. = DATS file names (in dependency order, from the stock Makefile)
# Mirrors {xats2cc,xats2js}/.../Makefile_xjsemit: transpile each .dats via
# jsemit00, sed the per-file namespace jsxtnm -> jsx<NNN>tnm, then concat.
########################################################################
build_backend_lib() {
  local out="$1"; shift
  local dir="$1"; shift
  : > "$out"
  # per-file counter STARTS AT 100, exactly like the stock Makefile_xjsemit
  # (NFILE = N064 N032 N004 = 100). This makes the per-file token 3 DIGITS
  # (jsx100tnm, jsx101tnm, ...), which is REQUIRED: the final link sed below is
  # `jsx(...)tnm` (exactly 3 chars), so 1-/2-digit tokens would NOT be remapped
  # into the js2/js3 namespace and would collide with lib2xatsopt (jsx100..) and
  # between the two backend libs. (Verified: with a 1-based counter, js2/js3 were
  # empty and jsx1tnm collided across libs.)
  local idx=100 f base trans
  for f in "$@"; do
    base="${f%.dats}"
    trans="$BUILD/$(basename "$dir")__${base}_dats_out0.js"
    $NODE "$JSEMIT" "$dir/$f" > "$trans" 2>"$trans.err"
    if [ "$(wc -l < "$trans")" -lt 3 ]; then
      echo "!! transpile FAILED for $dir/$f (see $trans.err)" >&2
      tail -30 "$trans.err" >&2
      return 1
    fi
    # per-file namespacing inside this lib (jsxtnm -> jsx<NNN>tnm), 3-digit.
    sed -e "s/jsxtnm/jsx${idx}tnm/g" "$trans" >> "$out"
    idx=$((idx + 1))
  done
  echo "   -> $out ($(wc -l < "$out") lines, $((idx - 100)) files)"
  return 0
}

########################################################################
echo ">> [1/5] build backend libs from source (jsemit00)"
########################################################################

# --- lib2xats2cc : intrep0 + trxd3i0 + tryd3i0 (source set from
#     xats2cc/srcgen1/Makefile_xjsemit SRCDATS) --------------------------------
LIB2CC="$BUILD/lib2xats2cc.js"
echo "   building lib2xats2cc.js ..."
build_backend_lib "$LIB2CC" "$XATS2CC/DATS" \
  intrep0.dats \
  intrep0_print0.dats \
  intrep0_utils0.dats \
  trxd3i0.dats \
  trxd3i0_print0.dats \
  trxd3i0_myenv0.dats \
  trxd3i0_statyp.dats \
  trxd3i0_dynexp.dats \
  trxd3i0_decl00.dats \
  tryd3i0.dats \
  tryd3i0_myenv0.dats \
  tryd3i0_dynexp.dats \
  tryd3i0_decl00.dats \
  intrep1.dats \
  intrep1_print0.dats \
  xats2cc_tmplib.dats \
  || exit 1

# --- lib2xats2js : intrep1 + trxi0i1 + xats2js + js1emit (source set from
#     xats2js/srcgen2/Makefile_xjsemit SRCDATS) --------------------------------
LIB2JS="$BUILD/lib2xats2js.js"
echo "   building lib2xats2js.js ..."
build_backend_lib "$LIB2JS" "$XATS2JS/DATS" \
  intrep1.dats \
  intrep1_print0.dats \
  intrep1_utils0.dats \
  trxi0i1.dats \
  trxi0i1_myenv0.dats \
  trxi0i1_dynexp.dats \
  trxi0i1_decl00.dats \
  xats2js.dats \
  xats2js_myenv0.dats \
  xats2js_utils0.dats \
  xats2js_dynexp.dats \
  xats2js_decl00.dats \
  js1emit.dats \
  js1emit_utils0.dats \
  js1emit_dynexp.dats \
  js1emit_decl00.dats \
  xats2js_tmplib.dats \
  || exit 1

########################################################################
echo ">> [2/5] transpile drivers (jsemit00)"
########################################################################
M0A_DATS="$HERE/DATS/pyfront.dats"
M0B_DATS="$HERE/DATS/pyfront_m0b.dats"
M0A_TRANS="$BUILD/pyfront_dats.js"
M0B_TRANS="$BUILD/pyfront_m0b_dats.js"

$NODE "$JSEMIT" "$M0A_DATS" > "$M0A_TRANS" 2>"$BUILD/transpile_m0a.err"
echo "   -> $M0A_TRANS ($(wc -l < "$M0A_TRANS") lines)"
$NODE "$JSEMIT" "$M0B_DATS" > "$M0B_TRANS" 2>"$BUILD/transpile_m0b.err"
echo "   -> $M0B_TRANS ($(wc -l < "$M0B_TRANS") lines)"
if [ "$(wc -l < "$M0B_TRANS")" -lt 5 ]; then
  echo "!! M0b driver transpile produced too little; see BUILD/transpile_m0b.err" >&2
  tail -40 "$BUILD/transpile_m0b.err" >&2
  exit 1
fi
# guard: the driver must not have left any unresolved template (errck) nodes.
if grep -q "D2Eerrck\|TIMPLall1\|F3PERR0-ERROR" "$M0B_TRANS"; then
  echo "!! M0b driver transpile contains errck/unresolved-template markers" >&2
  grep -n "D2Eerrck\|TIMPLall1\|F3PERR0-ERROR" "$M0B_TRANS" | head >&2
fi

########################################################################
echo ">> [3/5] link compiler bundle (runtime + lib2xatsopt/js1 + lib2xats2cc/js2 + lib2xats2js/js3 + glue + drivers)"
########################################################################
# runtime list — verbatim from xats2js/srcgen2/UTIL/Makefile_xjsemit
# (the recipe that links xats2js_jsemit01).
S2R="$SRCGEN2/xats2js/srcgenx/xshared/runtime"
S1R="$SRCGEN1/xats2js/srcgenx/xshared/runtime"
RUNTIME=(
  "$S2R/xats2js_js1emit.js"
  "$S2R/srcgen2_precats.js"
  "$S1R/srcgen1_prelude.js"
  "$S1R/srcgen1_prelude_node.js"
  "$S1R/srcgen1_xatslib_node.js"
)
BUNDLE="$BUILD/pyfront-m0b.js"
cat "${RUNTIME[@]}" > "$BUNDLE"
# the THREE compiler/backend libs, each with its own js{1,2,3} namespace
# (sed jsx(...)tnm -> js{N}\1tnm), exactly as Makefile_xjsemit does.
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$BUNDLE"
sed -E 's/jsx(...)tnm/js2\1tnm/g' "$LIB2CC"  >> "$BUNDLE"
sed -E 's/jsx(...)tnm/js3\1tnm/g' "$LIB2JS"  >> "$BUNDLE"
# frontend FFI glue must precede the drivers; M0a glue (PYF_*) for the reused
# pyfront.dats, M0b glue (PYF2_*) for pyfront_m0b.dats.
cat "$HERE/CATS/pyfront.cats"     >> "$BUNDLE"
cat "$HERE/CATS/pyfront_m0b.cats" >> "$BUNDLE"
# M0a driver first (its auto-run mymain prints to stdout, OUTSIDE the sentinels),
# then the M0b driver (which emits the user JS between the sentinels).
cat "$M0A_TRANS" >> "$BUNDLE"
cat "$M0B_TRANS" >> "$BUNDLE"
echo "   linked $(wc -l < "$BUNDLE") lines into $BUNDLE ($(du -h "$BUNDLE" | awk '{print $1}'))"

########################################################################
echo ">> [4/5] run compiler bundle: emit user-program JS to stdout"
########################################################################
RAWOUT="$BUILD/m0b-stdout.txt"
echo "----------------------------------------------------------------------"
$NODE "$BUNDLE" > "$RAWOUT" 2>"$BUILD/m0b-stderr.txt"
RC=$?
echo "-- compiler-bundle stderr (progress markers) --"
cat "$BUILD/m0b-stderr.txt"
echo "----------------------------------------------------------------------"
echo ">> compiler-bundle exit code: $RC"
if [ "$RC" -ne 0 ]; then
  echo "!! compiler bundle did not exit 0" >&2
  exit "$RC"
fi

# extract exactly the emitted user-program JS (between the sentinels).
EMIT="$BUILD/emitted-user.js"
awk '/^\/\/==PYF2-JS-BEGIN==/{f=1;next} /^\/\/==PYF2-JS-END==/{f=0} f' "$RAWOUT" > "$EMIT"
echo ">> extracted emitted user-program JS -> $EMIT ($(wc -l < "$EMIT") lines)"
if [ "$(wc -c < "$EMIT")" -lt 2 ]; then
  echo "!! no emitted JS captured between sentinels" >&2
  echo "--- raw stdout ---"; cat "$RAWOUT" >&2
  exit 1
fi
echo "-- emitted user-program JS (head) --"
head -40 "$EMIT"
echo "-- grep for x/y bindings in emitted JS --"
grep -nE '\b(x|y)\b|XATS' "$EMIT" | head -20 || true

########################################################################
echo ">> [5/5] RUN the emitted user-program JS on node (prepend ATS->JS runtime)"
########################################################################
# The emitted program references the same ATS->JS runtime the compiler bundle
# uses (XATS* combinators + the prelude). Prepend that runtime, then run.
RUNJS="$BUILD/run-emitted.js"
cat "${RUNTIME[@]}" > "$RUNJS"
# the emitted user program needs the srcgen1/srcgen2 prelude LIBRARY (the L2
# prelude's JS impls it calls into). Link lib2xatsopt's prelude the same way the
# compiler bundle does, namespaced js1, BEFORE the emitted program.
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$RUNJS"
cat "$EMIT" >> "$RUNJS"
echo "   built runnable program -> $RUNJS ($(du -h "$RUNJS" | awk '{print $1}'))"
echo "----------------------------------------------------------------------"
$NODE "$RUNJS"
RC2=$?
echo "----------------------------------------------------------------------"
echo ">> emitted-program node exit code: $RC2"
exit $RC2
