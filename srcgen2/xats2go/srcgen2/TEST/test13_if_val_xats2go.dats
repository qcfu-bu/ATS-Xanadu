(* ****** ****** *)
(*
M2.3 conformance: an if-expression in VALUE position.  [f]'s body uses the
if-result in further arithmetic, so the if surfaces as I1LETnew1(tnm,
I1INSift0(...)) whose branches each yield a value -- go1emit pre-declares
`var goxtnm<tnm> int` and the branches ASSIGN to it (value-position mode),
then the result feeds the `+ 10`.  Distinct from test12's RETURN mode.
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
f(n: sint): sint =
(if (n > 0) then 1 else 2) + 10
//
val () = sint_print(f(5))    // 11
val () = strn_print("\n")
val () = sint_print(f(0 - 3))  // 12
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test13_if_val.dats] *)
(***********************************************************************)
