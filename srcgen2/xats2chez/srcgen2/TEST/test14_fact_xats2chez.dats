(* ****** ****** *)
(*
M2.3 HEADLINE: recursive factorial.  `fun fact(n) = if n <= 0 then 1 else
n * fact(n-1)` proves if (return mode) + self-recursion + the function-body
return path COMPOSE.  Non-tail recursion already works at package level (a
real Go recursive call `fact_<stamp>(n-1)`); M2.3 adds the if/return path.
Prints `fact(5)=120`.  Must be byte-equal-vs-JS.
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
fact(n: sint): sint =
if (n <= 0) then 1 else n * fact(n - 1)
//
val () = strn_print("fact(5)=")
val () = sint_print(fact(5))    // 120
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test14_fact.dats] *)
(***********************************************************************)
