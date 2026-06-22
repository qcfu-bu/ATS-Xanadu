#!/usr/bin/env bash
########################################################################
# DYN (DYNAMIC-side gaps, bootstrap P1 feature 5) — gaps a real `.dats`
# round-trip surfaced, wired through the real frontend pipeline:
#
#   GAP A — `private:` (D2Clocal0 capture-rest) with a NON-`def` head (an `enum`
#           + a module `let`) + a public def using it. VERDICT: TYPECHECK-CLEAN
#           (nerror=0); the later `i0varfst_mklst` ReferenceError is a stock srcgen2
#           CODEGEN-LIB gap that hits ANY def codegen (NOT private-specific, NOT ours).
#           So the fixture asserts the TYPECHECK count (printed BEFORE codegen).
#   GAP B — first-class ref CELL: `r[]` deref (-> a0ref_get) + `r[] := e` (-> a0ref_set)
#           + a cell built via a0ref_make_1val. The prelude ref API, re-exported in
#           pyrt.sats; the surface `[]`/`[]:=` wired in the parser/elaborator. nerror=0.
#   GAP C — crash-safety: `case list_cons(a,b):` (lowercase con-app PATTERN) used to
#           loop -> SIGSEGV; now it reaches a COUNTED type error (rc != 139, nerror>0).
#   GAP D — expression-position `_` is ATS top/omitted value, not unit. It must be
#           contextually typed in annotation and constructor-argument positions.
#   GAP E — statement `if` branch bodies sequence into the following suite tail; a
#           final void expression in the branch must not replace the function value.
#   GAP F — dotted qualified static type heads (`MAP.topmap[T]`) must lower like
#           ATS `$MAP.topmap(T)` instead of degrading the constructor field type to none0.
#
# Each fixture rides the SAME M3 driver path (frontend/DATS/pyfront_m3.dats = the full
# lex -> parse -> elab -> lower -> trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a
# pipeline): build the M3 driver bundle (reusing build-m3.sh's compile+link), then run +
# verify each frontend/TEST/dyn/*.pdats against ITS OWN assert.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-dyn.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-dyn.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/dyn"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the DYN gaps ride the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/dyn-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — DYN cannot proceed (see BUILD/dyn-driverbuild.log)" >&2
    tail -40 "$BUILD/dyn-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/dyn-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — DYN would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/dyn-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the DYN fixtures over frontend/TEST/dyn/*.pdats"
########################################################################
FAIL=0

# the `nerror (after tread3a)` line the driver prints AFTER tread3a (the authoritative
# TYPECHECK count, printed BEFORE codegen). We capture stderr + rc separately so GAP C can
# assert the process did NOT crash (rc != 139 / SIGSEGV).
run_fixture() {  # $1 = path ; writes $RC, $NE, $ERRF
  ERRF="$BUILD/dyn-$(basename "$1" .pdats).err"
  timeout 60 $NODE "$BUNDLE" "$1" > /dev/null 2>"$ERRF"
  RC=$?
  NE="$(grep -oE "nerror \(after tread3a\) = [0-9]+" "$ERRF" | grep -oE "[0-9]+$" | head -1)"
}

# ---- GAP B: dyn_refcell — r[] / r[] := / a0ref_make_1val typecheck nerror=0 -------------
echo "----------------------------------------------------------------------"
py="$TESTDIR/dyn_refcell.pdats"
echo ">> [GAP B] $py  (r[] deref + r[] := e ; expect nerror=0)"
echo "-- source --"; cat "$py"
run_fixture "$py"
echo ">> rc=$RC  nerror (after tread3a) = ${NE:-<none>}"
if [ "${NE:-X}" = "0" ]; then
  echo ">> PASS  (GAP B: the ref cell deref/assign LOWER + TYPECHECK, nerror=0)"
else
  echo "!! FAIL  (GAP B expected nerror=0; got ${NE:-<none>})" >&2
  grep -E "F3PERR0-ERROR|elab-diag" "$ERRF" | head -8 >&2
  FAIL=1
fi

# ---- GAP A: dyn_local_head — private head w/ enum+let typechecks nerror=0 ---------------
echo "----------------------------------------------------------------------"
py="$TESTDIR/dyn_local_head.pdats"
echo ">> [GAP A] $py  (private: head with enum + let ; expect TYPECHECK nerror=0)"
echo "-- source --"; cat "$py"
run_fixture "$py"
echo ">> rc=$RC  nerror (after tread3a) = ${NE:-<none>}"
if [ "${NE:-X}" = "0" ]; then
  echo ">> PASS  (GAP A: D2Clocal0(non-def-head, rest) TYPECHECKS, nerror=0 — the boundary verdict)"
  echo "         NOTE: codegen may then hit the stock srcgen2 i0varfst_mklst gap (NOT private-specific,"
  echo "               hits any def codegen; OUT OF SCOPE) — the deliverable is the typecheck-clean count."
else
  echo "!! FAIL  (GAP A expected TYPECHECK nerror=0; got ${NE:-<none>})" >&2
  grep -E "F3PERR0-ERROR|elab-diag" "$ERRF" | head -8 >&2
  FAIL=1
fi

# ---- GAP C: dyn_lcpat_safe — lowercase con-app pattern: NO crash + nerror>0 -------------
echo "----------------------------------------------------------------------"
py="$TESTDIR/dyn_lcpat_safe.pdats"
echo ">> [GAP C] $py  (lowercase con-app pattern ; expect NO crash rc!=139 + nerror>0)"
echo "-- source --"; cat "$py"
run_fixture "$py"
echo ">> rc=$RC  nerror (after tread3a) = ${NE:-<none>}"
if [ "$RC" -eq 139 ]; then
  echo "!! FAIL  (GAP C CRASHED — rc=139/SIGSEGV; the parser still loops)" >&2
  FAIL=1
elif [ "${NE:-0}" -gt 0 ] 2>/dev/null; then
  echo ">> PASS  (GAP C: NO crash (rc=$RC != 139), counted nerror=${NE} > 0)"
else
  echo "!! FAIL  (GAP C: expected no-crash + nerror>0; rc=$RC nerror=${NE:-<none>})" >&2
  grep -E "elab-diag" "$ERRF" | head -8 >&2
  FAIL=1
fi

# ---- GAP D: dyn_top_expr — expression-position `_` is top, not unit --------------------
echo "----------------------------------------------------------------------"
py="$TESTDIR/dyn_top_expr.pdats"
echo ">> [GAP D] $py  (expression underscore as ATS top ; expect nerror=0)"
echo "-- source --"; cat "$py"
run_fixture "$py"
echo ">> rc=$RC  nerror (after tread3a) = ${NE:-<none>}"
if [ "${NE:-X}" = "0" ]; then
  echo ">> PASS  (GAP D: expression underscore LOWERS as ATS top and TYPECHECKS, nerror=0)"
else
  echo "!! FAIL  (GAP D expected nerror=0; got ${NE:-<none>})" >&2
  grep -E "F3PERR0-ERROR|elab-diag" "$ERRF" | head -8 >&2
  FAIL=1
fi

# ---- GAP E: dyn_stmt_if_continue — statement-if branches continue to suite tail --------
echo "----------------------------------------------------------------------"
py="$TESTDIR/dyn_stmt_if_continue.pdats"
echo ">> [GAP E] $py  (statement if branch continues to suite tail ; expect nerror=0)"
echo "-- source --"; cat "$py"
run_fixture "$py"
echo ">> rc=$RC  nerror (after tread3a) = ${NE:-<none>}"
if [ "${NE:-X}" = "0" ]; then
  echo ">> PASS  (GAP E: statement if branch SEQUENCES into the following tail, nerror=0)"
else
  echo "!! FAIL  (GAP E expected nerror=0; got ${NE:-<none>})" >&2
  grep -E "F3PERR0-ERROR|elab-diag" "$ERRF" | head -8 >&2
  FAIL=1
fi

# ---- GAP F: dyn_qualified_static_type — MAP.topmap[T] qualified type head --------------
echo "----------------------------------------------------------------------"
py="$TESTDIR/dyn_qualified_static_type.pdats"
echo ">> [GAP F] $py  (dotted qualified static type head ; expect nerror=0)"
echo "-- source --"; cat "$py"
run_fixture "$py"
echo ">> rc=$RC  nerror (after tread3a) = ${NE:-<none>}"
if [ "${NE:-X}" = "0" ]; then
  echo ">> PASS  (GAP F: MAP.topmap[...] LOWERS through qualified static lookup, nerror=0)"
  echo "         NOTE: codegen may then hit the stock srcgen2 i0varfst_mklst gap after typecheck;"
  echo "               the regression asserts the frontend/typecheck boundary."
else
  echo "!! FAIL  (GAP F expected nerror=0; got ${NE:-<none>})" >&2
  grep -E "F3PERR0-ERROR|elab-diag" "$ERRF" | head -8 >&2
  FAIL=1
fi

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> DYN: FAIL (see failures above)"; exit 1; fi
echo ">> DYN: PASS (GAP A private-head TYPECHECKS nerror=0 [codegen-lib gap noted];"
echo "            GAP B r[]/r[]:=  LOWER+TYPECHECK nerror=0;  GAP C lowercase con-app pattern"
echo "            is crash-safe with counted nerror>0; GAP D expression underscore"
echo "            LOWERS as ATS top; GAP E statement if continues to the suite tail;"
echo "            GAP F dotted qualified static type heads lower through namespace lookup;"
echo "            all expected-success fixtures TYPECHECK nerror=0.)"
exit 0
