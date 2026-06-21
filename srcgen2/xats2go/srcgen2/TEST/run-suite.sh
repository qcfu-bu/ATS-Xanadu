#!/usr/bin/env bash
########################################################################
# xats2go — CONFORMANCE RUNNER  (milestone M2.0)
#
#   run-suite.sh [test1.dats test2.dats ...]
#
# Runs build-go.sh (the differential-vs-JS oracle) over a list of ATS3
# sources and prints a per-test PASS/FAIL summary, exiting nonzero if any
# test fails.  With no args it runs the DEFAULT suite (below) -- the set of
# conformance cases the current milestone is expected to pass.  Future M2
# chunks EXTEND this list as new constructs land.
#
# Paths may be absolute or relative to the repo's xats2go TEST dir.
########################################################################
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"          # .../srcgen2/TEST
XATS2GO_ROOT="$(cd "$HERE/../.." && pwd)"                     # .../xats2go
BUILD_GO="$XATS2GO_ROOT/build-go.sh"
[ -x "$BUILD_GO" ] || { echo "!! build-go.sh not found/executable at $BUILD_GO" >&2; exit 2; }

# DEFAULT suite.  test00 (`val theAnswer=42`, a non-unit val pattern) is
# NOT yet emittable by go1emit, so it is left out until M2.x handles
# non-unit val patterns.
#   M2.0: test01 (hello-world print path).
#   M2.1: scalar literals + primops -- integer arithmetic/compare, boolean
#         logic, float arithmetic/compare, char literals/compare.  Each
#         prints a deterministic result and is byte-equal-vs-JS.
#   M2.2: user-defined NON-recursive functions + calls.  test07 (one arg,
#         one call), test08 (one fn called multiple times + result feeds
#         arithmetic), test09 (a fn calling another fn), test10 (multiple
#         args, mixed scalar types int+float64).  Each emits concrete-typed
#         Go func signatures (Regime B) and is byte-equal-vs-JS.
DEFAULT_SUITE=(
  "$HERE/test01_xats2go.dats"
  "$HERE/test02_arith_xats2go.dats"
  "$HERE/test03_compare_xats2go.dats"
  "$HERE/test04_logic_xats2go.dats"
  "$HERE/test05_float_xats2go.dats"
  "$HERE/test06_char_xats2go.dats"
  "$HERE/test07_fun1_xats2go.dats"
  "$HERE/test08_fun_multi_xats2go.dats"
  "$HERE/test09_fun_call_fun_xats2go.dats"
  "$HERE/test10_fun_args_xats2go.dats"
  #   M2.3: control flow -- if / let-in / case (simple patterns).
  #     test12 if-bodied fn (RETURN mode), test13 if in VALUE position,
  #     test14 the HEADLINE recursive factorial (if + return + self-recursion),
  #     test15 case over int/char literals + default, test16 case with guards,
  #     test17 let-in-end nested expression.  Each byte-equal-vs-JS.
  "$HERE/test12_if_ret_xats2go.dats"
  "$HERE/test13_if_val_xats2go.dats"
  "$HERE/test14_fact_xats2go.dats"
  "$HERE/test15_case_lit_xats2go.dats"
  "$HERE/test16_case_guard_xats2go.dats"
  "$HERE/test17_let_xats2go.dats"
  #   M2.4: tail-call optimization.  test18 the HEADLINE deep tail loop
  #     (sum 1..50_000_000 via tail recursion -- a for{...continue} loop that
  #     does NOT stack-overflow; would crash a non-TCO recursive version),
  #     test19 a tail-recursive accumulator (factorial via accumulator,
  #     fac(10)=3628800).  Each byte-equal-vs-JS (the JS backend also does TCO).
  "$HERE/test18_tail_loop_xats2go.dats"
  "$HERE/test19_tail_acc_xats2go.dats"
  #   M2.5: closures (lambdas + captured environments) + local recursion.
  #     test20 a HIGHER-ORDER fn taking a lambda arg (apply(f,x)=f(x) with
  #     `lam x => x+1`); test21 the HEADLINE capturing closure
  #     (adder(n)=lam x => x+n; add5=adder(5); add5(10)=15 -- REAL lexical
  #     capture; JS-oracle-deferred via golden, the JS backend's lam0 env
  #     capture has a pre-existing `env1`-undefined bug); test22 a LOCAL
  #     recursive closure via `fix` (I1INSfix0, Go's `var f F; f=func(){..f()..}`
  #     self-ref idiom; non-tail so the JS oracle is usable); test23 a lambda
  #     STORED in a val and called later (capture-free, JS-oracle-validated).
  "$HERE/test20_lam_apply_xats2go.dats"
  "$HERE/test21_closure_cap_xats2go.dats"
  "$HERE/test22_fix_local_xats2go.dats"
  "$HERE/test23_lam_store_xats2go.dats"
  #   M2.5 BUG-1 fix (lambda return-type recovery for captures / nested
  #     lambdas).  These capture an enclosing value and so trip the JS
  #     backend's pre-existing `env1`-undefined lam0-capture bug -- they are
  #     GOLDEN-validated (the golden encodes the HAND-COMPUTED-correct value,
  #     not "whatever Go emits"), EXCEPT test33 (non-capturing `fix`) which is
  #     byte-equal-vs-JS.  test30 nested 2-level (123); test31 shadowing (108);
  #     test32 multi-independent closures (105/110/15); test33 fix recursion
  #     (tri 0 1 15 55); test34 capture-by-value timing (7/42/7); test35 const-
  #     fn MWE (9); test36 captured FLOAT64 (3.5 -> func(int) float64, anti-
  #     overfit vs int); test37 3-level nested capture (1234, anti-overfit).
  "$HERE/test30_nested_cap_xats2go.dats"
  "$HERE/test31_shadow_xats2go.dats"
  "$HERE/test32_multi_clos_xats2go.dats"
  "$HERE/test33_fix_multi_xats2go.dats"
  "$HERE/test34_cap_timing_xats2go.dats"
  "$HERE/test35_const_xats2go.dats"
  "$HERE/test36_cap_float_xats2go.dats"
  "$HERE/test37_nest3_xats2go.dats"
  #   M2.6a: the [i1tnm -> i0typ] SIDE-TABLE.  test38 exercises a VALUE-POSITION
  #     result temp bound from a USER-FUNCTION CALL (`(let val a = sq(n) in a
  #     end) + 1`) -- typed concretely (`var goxtnm<N> int`) ONLY via the side-
  #     table; before M2.6a it was `any` and `(goxtnm<N> + 1)` failed `go vet`.
  #     Byte-equal-vs-JS.
  "$HERE/test38_tytab_xats2go.dats"
  #   M2.6a side-table backstops (anti-overfit) + the I1INSlet0 return-mode fix.
  #     test39 a FLOAT-returning user-fn result temp typed float64 via the side-
  #     table (`(let val a = sqf(n) in a end) + 1.0`); test40 a BOOL-returning
  #     user-fn result temp as an if-test (`let val b = isPos(n) in (if b then 1
  #     else 0) end`) -- a let whose body is a returning `if` in a FUNCTION BODY;
  #     before the fix the value-mode let scaffold left an UNREACHABLE trailing
  #     `return` (`go vet` fail).  test41 the GENERAL fix: a let whose body is a
  #     returning `case` (`let val k = n in case k of 0 => 10 | _ => 20 end`).
  #     Each byte-equal-vs-JS, `go vet` clean.
  "$HERE/test39_tytab_float_xats2go.dats"
  "$HERE/test40_tytab_bool_xats2go.dats"
  "$HERE/test41_let_case_xats2go.dats"
  #   M2.6b: layout-aware tuples/records.  A FLAT tuple/record is a Go VALUE
  #     struct `struct{...}{...}`; a BOXED one is a `&struct{...}{...}` POINTER
  #     (provably tracking the trcdknd).  Construction + projection + a tuple
  #     passed-to/returned-from a function all drive the SAME struct type from
  #     the M2.6a side-table.  test42 flat tuple build+proj; test43 boxed tuple
  #     (POINTER); test44 flat record (named fields); test45 boxed record;
  #     test46 a NESTED tuple (struct-typed field); test47 a tuple PASSED TO +
  #     RETURNED FROM a function (struct param/result signature).  Each
  #     byte-equal-vs-JS, gofmt-clean, `go vet` OK.
  "$HERE/test42_tup_flat_xats2go.dats"
  "$HERE/test43_tup_boxed_xats2go.dats"
  "$HERE/test44_rec_flat_xats2go.dats"
  "$HERE/test45_rec_boxed_xats2go.dats"
  "$HERE/test46_nested_xats2go.dats"
  "$HERE/test47_tup_fun_xats2go.dats"
  "$HERE/test48_tup_float_xats2go.dats"
  "$HERE/test49_tup_mixed_xats2go.dats"
  "$HERE/test50_var_flat_xats2go.dats"
  "$HERE/test51_var_boxed_alias_xats2go.dats"
  "$HERE/test52_var_rec_xats2go.dats"
  "$HERE/test53_var_seq_xats2go.dats"
)

if [ "$#" -gt 0 ]; then
  TESTS=("$@")
else
  TESTS=("${DEFAULT_SUITE[@]}")
fi

pass=0; fail=0
declare -a FAILED
echo "======================================================================"
echo ">> xats2go conformance suite: ${#TESTS[@]} test(s)"
echo "======================================================================"
for t in "${TESTS[@]}"; do
  # resolve relative paths against the TEST dir
  [ -f "$t" ] || t="$HERE/$t"
  name="$(basename "$t" .dats)"
  printf '>> %-32s ... ' "$name"
  log="$XATS2GO_ROOT/srcgen2/BUILD/${name}.suite.log"
  if bash "$BUILD_GO" "$t" > "$log" 2>&1; then
    echo "PASS"
    pass=$((pass + 1))
  else
    echo "FAIL  (see $log)"
    fail=$((fail + 1))
    FAILED+=("$name")
    tail -8 "$log" | sed 's/^/      | /'
  fi
done
echo "======================================================================"
echo ">> SUMMARY: $pass passed, $fail failed (of ${#TESTS[@]})"
if [ "$fail" -ne 0 ]; then
  echo ">> FAILED: ${FAILED[*]}"
  echo "======================================================================"
  exit 1
fi
echo ">> ALL GREEN"
echo "======================================================================"
exit 0
