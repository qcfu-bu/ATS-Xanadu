(* ****** ****** *)
(*
M2.1 conformance: INTEGER ARITHMETIC.
//
Exercises +, -, *, /, % over sint literals.  Each op lowers (verified via
the IR dump) to an I1INStimp resolving to a prelude d2cst (sint_add$sint,
sint_sub$sint, ...) applied via I1INSdapp; the go1emit primop pass emits
NATIVE Go operators `(a OP b)` since both operands are concretely-typed
int literals/temps.  Negative div/mod is included because Go `/` truncates
toward zero and `%` takes the sign of the dividend -- matching the JS
backend (Math.trunc + remainder), which the differential oracle confirms.
Each result is printed via sint_print so stdout is deterministic.
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
val () = sint_print(1 + 2 * 3)     // 7   (precedence: 1 + (2*3))
val () = strn_print(" ")
val () = sint_print(20 - 4 - 3)    // 13
val () = strn_print(" ")
val () = sint_print(6 * 7)         // 42
val () = strn_print(" ")
val () = sint_print(7 / 2)         // 3   (trunc)
val () = strn_print(" ")
val () = sint_print(7 % 2)         // 1
val () = strn_print(" ")
val () = sint_print((0 - 7) / 2)   // -3  (trunc toward 0)
val () = strn_print(" ")
val () = sint_print((0 - 7) % 2)   // -1  (sign of dividend)
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test02_arith.dats] *)
(***********************************************************************)
