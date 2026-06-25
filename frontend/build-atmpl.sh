#!/usr/bin/env bash
########################################################################
# A-TEMPLATE SURFACE — template operations plus explicit static application, wired end-to-end through the
# real frontend pipeline (lex -> parse -> elab -> lower -> trans2a/trsym2b/t2read0/
# trans23/tread3a) + TYPECHECKED. These are DECORATORS whose `[…]` carry type-args:
#
#   declare      @template[A] def foo[C](…)[: body]  ->  extern fun{A} foo{C}(…)  (+impl if inline)
#   implement    @impl[Int] def foo(…): body         ->  implement{Int} foo(…) = body
#   instantiate  @inst[Int] foo(x)                    ->  foo<Int>(x)
#   static app   @sapp[Int] foo(x)                    ->  foo{Int}(x)
#
# What this proves (real typecheck — resolution deferred to trtmp3b/3c, AFTER tread3a, so a
# DECLARED+INSTANTIATED template reaches nerror=0 structurally; the SPIKE T1-T5 proved this):
#   * at_decl_impl_inst.pdats — declare+inline-body + instantiate           (nerror=0)
#   * at_separate_impl.pdats  — bodyless declare + separate @impl[Int]       (nerror=0)
#   * at_impl_alias_nodarg.pdats — farg-less @impl[Int] alias body           (nerror=0)
#   * at_both_brackets.pdats  — @template[A] AND foo[C] polymorphic coexist  (nerror=0)
#   * at_sapp_empty_call.pdats — explicit static `{Int}` call-site app       (nerror=0)
#   * at_neg_inst.pdats       — NEGATIVE control: @inst[Int] id("hi")        (nerror>0 — REAL check)
# The negative control MUST fail to typecheck — if it reaches nerror=0 the wiring is fake.
#
# Rides the M3 driver path exactly like build-dep.sh: build (reuse) the M3 driver bundle, then
# for each frontend/TEST/atmpl/*.pdats assert the expected nerror.
#
# PURELY ADDITIVE: builds only into frontend/BUILD; reuses the M3 backend libs + driver.
#
# Usage:
#   bash frontend/build-atmpl.sh                 # (re)build the M3 driver + run + verify
#   bash frontend/build-atmpl.sh --reuse-bundle  # skip the rebuild, reuse BUILD/pyfront-m3.js
########################################################################
set -uo pipefail

export XATSHOME="${XATSHOME:-/Users/qcfu/Projects/ATS-Xanadu}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/BUILD"
BUNDLE="$BUILD/pyfront-m3.js"
TESTDIR="$HERE/TEST/atmpl"
NODE="node --stack-size=8801"

REUSE=0
[ "${1:-}" = "--reuse-bundle" ] && REUSE=1

########################################################################
echo ">> [1/2] M3 driver bundle (the A-TEMPLATE lowering rides the M3 pipeline)"
########################################################################
if [ "$REUSE" -eq 1 ] && [ -s "$BUNDLE" ]; then
  echo "   reusing $BUNDLE ($(wc -l < "$BUNDLE") lines)"
else
  echo "   building via build-m3.sh (reuses cached backend libs) ..."
  if ! bash "$HERE/build-m3.sh" > "$BUILD/atmpl-driverbuild.log" 2>&1; then
    echo "!! the M3 driver build FAILED — ATMPL cannot proceed (see BUILD/atmpl-driverbuild.log)" >&2
    tail -40 "$BUILD/atmpl-driverbuild.log" >&2
    exit 1
  fi
  if ! grep -q ">> M3: PASS" "$BUILD/atmpl-driverbuild.log"; then
    echo "!! build-m3.sh did not end with 'M3: PASS' — ATMPL would be riding a broken driver" >&2
    grep -E "4a |4b |M3:" "$BUILD/atmpl-driverbuild.log" >&2
    exit 1
  fi
  echo "   driver built + M3 self-test PASS ($(wc -l < "$BUNDLE") lines)"
fi

if [ ! -s "$BUNDLE" ]; then
  echo "!! $BUNDLE missing — run without --reuse-bundle to build it" >&2; exit 1
fi

########################################################################
echo ">> [2/2] run the A-TEMPLATE lowering + typecheck over frontend/TEST/atmpl/*.pdats"
########################################################################
FAIL=0

# the `nerror` line the driver prints AFTER running tread3a (the only authoritative count).
nerror_of() {
  $NODE "$BUNDLE" "$1" 2>&1 | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1
}

# ---- VALID programs: each must LOWER + TYPECHECK to nerror=0 -----------------
VALID=(
  "at_decl_impl_inst"   # @template[A] def id(x:A)->A: x ; @inst[Int] id(5)       (declare+inline+inst)
  "at_separate_impl"    # bodyless @template + @impl[Int] def pick + @inst[Int]    (separate impl)
  "at_impl_alias_nodarg" # bodyless @template + farg-less @impl[Int] alias body    (no dynamic farg)
  "at_both_brackets"    # @template[A] def foo[C](x:A,y:C)->C: y ; @inst[Int]       (BOTH brackets)
  "at_sapp_empty_call"   # def zero[A](); @sapp[Int] zero() -> zero{Int}()          (empty dapp)
  "at_inst_infix_operand" # @inst binds to call operand before infix equality
)
for base in "${VALID[@]}"; do
  py="$TESTDIR/${base}.pdats"
  echo "----------------------------------------------------------------------"
  echo ">> [valid] $py"
  if [ ! -f "$py" ]; then echo "!! missing $py" >&2; FAIL=1; continue; fi
  echo "-- source --"; cat "$py"
  n="$(nerror_of "$py")"
  echo ">> nerror (after tread3a) = ${n:-<none>}"
  if [ "${n:-X}" = "0" ]; then
    echo ">> PASS  ($base LOWERS + TYPECHECKS, nerror=0)"
  else
    echo "!! FAIL  ($base expected nerror=0; got ${n:-<none>})" >&2
    echo "-- f3perr0 diagnostics (stock reporter) --" >&2
    $NODE "$BUNDLE" "$py" 2>&1 | grep -E "F3PERR0-ERROR" | head -8 >&2
    FAIL=1
  fi
done

# ---- INVALID program (NEGATIVE control): @inst[Int] id("hi") -> nerror>0 -----
# The instantiated arg is a STRING where the template expects an Int — the type error must land on
# the `"hi"` argument's span. This proves the instantiation is REALLY typechecked (so the valid
# fixtures' nerror=0 is meaningful, not a silent no-op). If it reaches nerror=0 the wiring is FAKE.
echo "----------------------------------------------------------------------"
E_PY="$TESTDIR/at_neg_inst.pdats"
echo ">> [invalid] $E_PY  (NEG control: @inst[Int] id(\"hi\") — string vs Int)"
if [ ! -f "$E_PY" ]; then echo "!! missing $E_PY" >&2; FAIL=1; else
  echo "-- source --"; cat "$E_PY"
  EOUT="$($NODE "$BUNDLE" "$E_PY" 2>&1)"
  EN="$(echo "$EOUT" | grep -oE "nerror \(after tread3a\) = [0-9]+" | grep -oE "[0-9]+$" | head -1)"
  echo ">> nerror (after tread3a) = ${EN:-<none>}"
  echo "-- the f3perr0 diagnostic on the .pdats span (the \"hi\" arg) --"
  echo "$EOUT" | grep -oE "at_neg_inst\.pdats\)@\([0-9]+\(line=[0-9]+,offs=[0-9]+\)--[0-9]+\(line=[0-9]+,offs=[0-9]+\)" | head -2
  if [ -n "${EN:-}" ] && [ "${EN:-0}" -gt 0 ] 2>/dev/null; then
    echo ">> PASS  (NEG control correctly REJECTS the string-vs-Int instantiation, nerror=${EN}>0)"
  else
    echo "!! FAIL  (expected nerror>0; got ${EN:-<none>} — the instantiation is NOT really typechecked!)" >&2
    FAIL=1
  fi
fi

echo "======================================================================"
if [ "$FAIL" -ne 0 ]; then echo ">> ATMPL: FAIL (see failures above)"; exit 1; fi
echo ">> ATMPL: PASS (the template operations — @template[A] declare (+inline-body implement),"
echo "            @impl[Int] separate implement, @inst[Int] instantiate — plus @sapp[Int]"
echo "            explicit static application — all LOWER + TYPECHECK"
echo "            structurally at nerror=0; the NEG control @inst[Int] id(\"hi\") correctly fails"
echo "            (nerror>0), proving the instantiation is REALLY typechecked. Resolution/monomorph-"
echo "            ization is deferred to trtmp3b/3c, AFTER tread3a — same as stock ATS templates.)"
exit 0
