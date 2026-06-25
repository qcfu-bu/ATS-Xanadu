(* ****** ****** *)
(*
M2.1 conformance: FLOAT ARITHMETIC + COMPARISON.
//
Exercises +, -, *, / and a comparison over dflt (float64) literals.  Each
lowers to an I1INStimp resolving to dflt_add$dflt / dflt_sub$dflt / ...,
emitted as the NATIVE Go float operator over float64.  Results are printed
via dflt_print, whose runtime (XatsFloatToString) reproduces JS
Number.toString() for these ordinary decimals -- so stdout is byte-equal
to the JS backend (oracle-confirmed).  Values are chosen to be exactly
representable so the shortest-round-trip text matches in both backends.
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
val () = dflt_print(1.5 + 2.25)    // 3.75
val () = strn_print(" ")
val () = dflt_print(5.5 - 2.25)    // 3.25
val () = strn_print(" ")
val () = dflt_print(1.5 * 3.0)     // 4.5
val () = strn_print(" ")
val () = dflt_print(7.5 / 2.0)     // 3.75
val () = strn_print(" ")
val () = bool_print(1.5 < 2.5)     // true
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test05_float.dats] *)
(***********************************************************************)
