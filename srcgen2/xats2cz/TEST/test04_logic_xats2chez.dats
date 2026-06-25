(* ****** ****** *)
(*
M2.1 conformance: BOOLEAN LOGIC.
//
The short-circuit forms `&&`/`||` are special syntactic forms (they do
NOT surface as simple d2cst calls when used directly), so this test drives
boolean logic through bool-valued COMPARISONS combined with bool equality
(bool_eq / bool_neq -> native Go `==`/`!=`).  This exercises the bool
scalar type end-to-end: comparison results are concrete Go bools, combined
with native `==`/`!=`, printed via bool_print.
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
// (1<2) is true, (3<2) is false; combine via bool eq/neq.
val () = bool_print((1 < 2) = (2 < 3))   // true  == true  -> true
val () = strn_print(" ")
val () = bool_print((1 < 2) = (3 < 2))   // true  == false -> false
val () = strn_print(" ")
val () = bool_print((1 < 2) != (3 < 2))  // true  != false -> true
val () = strn_print(" ")
val () = bool_print((3 < 2) != (4 < 2))  // false != false -> false
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test04_logic.dats] *)
(***********************************************************************)
