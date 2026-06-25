(* ****** ****** *)
(*
M2.1 conformance: INTEGER COMPARISON.
//
Exercises <, >, <=, >=, =, != over sint.  Each lowers to an I1INStimp
resolving to sint_lt$sint / sint_gt$sint / sint_lte$sint / sint_gte$sint
/ sint_eq$sint / sint_neq$sint, emitted as the NATIVE Go relational
operator `(a OP b)` yielding a concrete Go bool, printed via bool_print.
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
val () = bool_print(1 < 2)    // true
val () = strn_print(" ")
val () = bool_print(2 < 1)    // false
val () = strn_print(" ")
val () = bool_print(3 > 2)    // true
val () = strn_print(" ")
val () = bool_print(2 <= 2)   // true
val () = strn_print(" ")
val () = bool_print(3 >= 4)   // false
val () = strn_print(" ")
val () = bool_print(5 = 5)    // true
val () = strn_print(" ")
val () = bool_print(5 != 5)   // false
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test03_compare.dats] *)
(***********************************************************************)
