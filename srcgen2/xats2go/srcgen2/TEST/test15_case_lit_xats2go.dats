(* ****** ****** *)
(*
M2.3 conformance: `case` over INT and CHAR literals + a wildcard default.
[classify] cases an int over literal patterns; [grade] cases a char.  Each
lowers to I1INScas0 with I1CLScls(I1GPTpat(I0Pint/I0Pchr ...), body) clauses
+ a wildcard (I0Pany).  go1emit emits a Go expression-less `switch { case
<casval == lit>: ...; case true: ...; default: panic }`.  Return position
(each clause body returns).  Byte-equal-vs-JS.
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
classify(n: sint): sint =
case+ n of
| 0 => 100
| 1 => 200
| 2 => 300
| _ => 999
//
fun
grade(c: char): sint =
case+ c of
| 'a' => 1
| 'b' => 2
| _ => 0
//
val () = sint_print(classify(0))   // 100
val () = strn_print(" ")
val () = sint_print(classify(2))   // 300
val () = strn_print(" ")
val () = sint_print(classify(7))   // 999
val () = strn_print(" ")
val () = sint_print(grade('b'))    // 2
val () = strn_print(" ")
val () = sint_print(grade('z'))    // 0
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test15_case_lit.dats] *)
(***********************************************************************)
