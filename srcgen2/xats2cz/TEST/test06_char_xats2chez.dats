(* ****** ****** *)
(*
M2.1 conformance: CHAR LITERALS + COMPARISON.
//
Exercises char literals (emitted as Go rune literals) printed via
char_print (-> string(rune)), and char comparison (char_lt / char_gt /
char_eq ...), which lowers to a native Go relational over rune (int32).
Includes an escaped char ('\n' is exercised separately via strn_print to
keep the rune-literal escaping path covered without ambiguous output).
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
val () = char_print('A')        // A
val () = char_print('Z')        // Z
val () = char_print('0')        // 0
val () = strn_print("\n")
val () = bool_print('a' < 'b')  // true
val () = strn_print(" ")
val () = bool_print('b' < 'a')  // false
val () = strn_print(" ")
val () = bool_print('x' = 'x')  // true
val () = strn_print(" ")
val () = bool_print('x' != 'y') // true
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test06_char.dats] *)
(***********************************************************************)
