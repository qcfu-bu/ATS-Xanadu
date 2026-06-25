(* ****** ****** *)
(*
M2.5 conformance: a HIGHER-ORDER function taking a lambda argument.
`apply(f, x) = f(x)` called with `lam x => x + 1`.  Exercises:
  - I1INSlam0  (the lambda -> inline Go func literal)
  - I1Vfenv as a function value (passing a top-level fn / a temp-bound
    lambda as an argument)
  - I1INSdapp where the callee is a PARAMETER (a func-typed param), not a
    named top-level fn.
Prints `apply(succ,41)=42`.  Must be byte-equal-vs-JS.
*)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_JS_dats.hats"
(* ****** ****** *)
//
fun
apply(f: sint -> sint, x: sint): sint = f(x)
//
val () = strn_print("apply(succ,41)=")
val () = sint_print(apply(lam(x: sint): sint => x + 1, 41))   // 42
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test20_lam_apply.dats] *)
(***********************************************************************)
