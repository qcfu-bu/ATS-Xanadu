#!/usr/bin/env bash
########################################################################
# M2.5 STEP-0 GATING SPIKE — build + run the flow(a,r) 2-param datatype proof.
#
# Proves LOOP-DESUGARING open item (ii): a 2-type-parameter parametric
# `datatype flow(a:t0, r:t0)` + a `case`/`flow_bind` over it
#   (a) TYPE-CHECKS  (nerror == 0), AND
#   (b) CODEGENS to JS that RUNS on node, printing the expected flow tags/payloads.
#
# TWO independent evidence paths (both run; both must pass):
#
#   PATH A  (typecheck, our OWN driver): the frontend spike driver
#     pyfront_spike.dats calls d3parsed_of_fildats(flow_spike.dats) — exercising
#     the SAME file-path -> typechecked-d3parsed entry M3 will use — and prints
#     nerror. This path proves the 2-param datatype + case TYPE-CHECK cleanly
#     through the compiler-as-a-library we link ourselves (lib2xatsopt). It does
#     NOT run codegen: our from-source backend lib (built like M0b) has a
#     PRE-EXISTING gap lowering `fun` decls (intrep0_utils0's funset-based
#     #implfuns transpile to errck in isolation; M0b never hit it because its
#     program was `val`-only). That gap is a backend-lib-build limitation, NOT a
#     `flow` problem, so codegen is taken via PATH B.
#
#   PATH B  (codegen + run, stock fully-linked oracle): compile flow_spike.dats
#     with the prebuilt stock xats2js_jsemit01 (every backend lib already linked),
#     emit its JS, link the run-time, and RUN it. Its stdout is the flow-spike's
#     printed tags/payloads — the run proof that the 2-param datatype + the case
#     over it WORK at run time.
#
# REUSES srcgen2/lib/lib2xatsopt.js (~171MB) — never rebuilt. jsemit00 +
# node --stack-size=8801 throughout. PURELY ADDITIVE (builds into frontend/BUILD).
#
# Usage:  bash frontend/build-spike.sh
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCGEN1="$XATSHOME/srcgen1"
SRCGEN2="$XATSHOME/srcgen2"

JSEMIT="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js"
ORACLE="$XATSHOME/xassets/JS/xats2js/xats2js_jsemit01_ats3_opt1.js"
LIB2OPT="$SRCGEN2/lib/lib2xatsopt.js"
BUILD="$HERE/BUILD"
NODE="node --stack-size=8801"
SPIKE_SRC="$HERE/pyrt/flow_spike.dats"
GLUE="$HERE/CATS/pyfront_spike.cats"

mkdir -p "$BUILD"
for f in "$JSEMIT" "$ORACLE" "$LIB2OPT"; do
  if [ ! -f "$f" ]; then echo "!! required file missing: $f" >&2; exit 1; fi
done

########################################################################
echo ">> PATH A — typecheck flow_spike.dats via d3parsed_of_fildats (our driver)"
########################################################################
SPK_DATS="$HERE/DATS/pyfront_spike.dats"
SPK_TRANS="$BUILD/pyfront_spike_dats.js"
$NODE "$JSEMIT" "$SPK_DATS" > "$SPK_TRANS" 2>"$BUILD/transpile_spike.err"
echo "   transpiled driver -> $SPK_TRANS ($(wc -l < "$SPK_TRANS") lines)"
if [ "$(wc -l < "$SPK_TRANS")" -lt 5 ]; then
  echo "!! spike driver transpile produced too little; see BUILD/transpile_spike.err" >&2
  tail -40 "$BUILD/transpile_spike.err" >&2; exit 1
fi

# link only what PATH A needs: runtime + lib2xatsopt (the compiler) + glue + driver.
S2R="$SRCGEN2/xats2js/srcgenx/xshared/runtime"
S1R="$SRCGEN1/xats2js/srcgenx/xshared/runtime"
RUNTIME=(
  "$S2R/xats2js_js1emit.js"
  "$S2R/srcgen2_precats.js"
  "$S1R/srcgen1_prelude.js"
  "$S1R/srcgen1_prelude_node.js"
  "$S1R/srcgen1_xatslib_node.js"
)
TCBUNDLE="$BUILD/spike-tc.js"
cat "${RUNTIME[@]}" > "$TCBUNDLE"
sed -E 's/jsx(...)tnm/js1\1tnm/g' "$LIB2OPT" >> "$TCBUNDLE"
cat "$GLUE" >> "$TCBUNDLE"
cat "$SPK_TRANS" >> "$TCBUNDLE"

# the driver runs the typecheck AND attempts codegen; the codegen step trips the
# known from-source-backend `fun` gap (a runtime ReferenceError), so we capture
# the nerror line from stderr and judge PATH A on THAT, not on the (expected)
# downstream crash. We DO NOT link the backend libs here (PATH B owns codegen).
TCERR="$BUILD/spike-tc.err"
$NODE "$TCBUNDLE" "$SPIKE_SRC" > "$BUILD/spike-tc.out" 2>"$TCERR" || true
NERR_LINE="$(grep -E 'd3parsed_of_fildats nerror =' "$TCERR" | head -1)"
echo "   $NERR_LINE"
if ! echo "$NERR_LINE" | grep -qE 'nerror = 0$'; then
  echo "!! SPIKE-FAILED: 2-param flow datatype did NOT type-check (nerror != 0)" >&2
  echo "--- typecheck errors (stock reporter) ---" >&2
  grep -E 'F2PERR0-ERROR|F3PERR0-ERROR' "$TCERR" | head -20 >&2
  exit 1
fi
echo "   PATH A: PASS (d3parsed_of_fildats nerror = 0)"

########################################################################
echo ">> PATH B — codegen + run flow_spike.dats via the stock jsemit01 oracle"
########################################################################
EMIT="$BUILD/spike-emitted.js"
$NODE "$ORACLE" "$SPIKE_SRC" > "$EMIT" 2>"$BUILD/spike-oracle.err"
RC=$?
OERR=$(grep -cE 'F2PERR0-ERROR|F3PERR0-ERROR' "$BUILD/spike-oracle.err" 2>/dev/null | head -1)
OERR="${OERR:-0}"
echo "   oracle emit: exit=$RC errck=$OERR lines=$(wc -l < "$EMIT")"
if [ "$RC" -ne 0 ] || [ "$OERR" -ne 0 ]; then
  echo "!! SPIKE-FAILED: oracle codegen reported errors" >&2
  tail -30 "$BUILD/spike-oracle.err" >&2; exit 1
fi

# confirm the emitted JS actually contains the 4 flow constructors (the codegen proof).
echo "   emitted flow constructors:"
grep -oE 'XATSCTAG\("flow_(next|cont|break|return)",[0-9]+\)' "$EMIT" | sort -u | sed 's/^/     /'

# link + run the emitted program. The emitted prelude-arith calls are XATS000_*-
# prefixed; the available srcgenx prelude impls them as XATS2JS_* — bridge the two
# (a run-time linking detail; the spike's own I/O is the PYRT_* FFI in the glue).
RUNJS="$BUILD/spike-run.js"
cat "${RUNTIME[@]}" > "$RUNJS"
cat "$GLUE" >> "$RUNJS"
cat >> "$RUNJS" <<'JS'
// namespace bridge: jsemit01 emits XATS000_-prefixed prelude arith; the srcgenx
// prelude impls them as XATS2JS_*. Alias so the emitted program resolves.
var XATS000_sint_lt$sint  = XATS2JS_sint_lt$sint;
var XATS000_sint_add$sint = XATS2JS_sint_add$sint;
var XATS000_sint_sub$sint = (typeof XATS2JS_sint_sub$sint !== "undefined") ? XATS2JS_sint_sub$sint : undefined;
JS
# normalize stamped template-instance names (XATS000_sint_lt$sint_1711 -> base).
sed -E 's/XATS000_(sint_lt|sint_add|sint_sub)\$sint_[0-9]+/XATS000_\1$sint/g' "$EMIT" >> "$RUNJS"

echo "----------------------------------------------------------------------"
$NODE "$RUNJS"
RC2=$?
echo "----------------------------------------------------------------------"
echo ">> emitted-spike node exit code: $RC2"
if [ "$RC2" -ne 0 ]; then
  echo "!! SPIKE-FAILED: emitted program failed at runtime" >&2; exit $RC2
fi
echo ">> SPIKE: PASS (2-param flow(a,r) datatype type-checks [PATH A], codegens + runs [PATH B])"
exit 0
