(* ****** ****** *)
(*
M2.5 HEADLINE: a closure CAPTURING a local.  `adder(n) = lam x => x + n`
returns a closure over [n].  `val add5 = adder(5)` then `add5(10)` => 15,
proving REAL lexical capture (the lambda's body reads [n] from the
enclosing function's parameter, not from an argument).  Exercises:
  - I1INSlam0 with a NON-empty captured free-var set ([n])
  - lexical Go capture (the inline func literal reads the surrounding `n`)
  - a closure RETURNED from a function and stored, then called later.
Prints `add5(10)=15`.  Must be byte-equal-vs-JS.
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
adder(n: sint): sint -> sint = lam(x: sint): sint => x + n
//
val add5 = adder(5)
//
val () = strn_print("add5(10)=")
val () = sint_print(add5(10))    // 15
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test21_closure_cap.dats] *)
(***********************************************************************)
