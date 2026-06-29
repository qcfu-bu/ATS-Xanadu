(* ****** ****** *)
(*
test_goarm07 — the SCALAR FLOOR (bool / char / dflt) through the CATS/GO arm.
Exercises:
  - char literals + char_print (-> Go string(rune)), char comparison
    (char_lt / char_eq / char_neq -> native rune relational), and the
    sint<->char conversions (char_make_sint / sint_make_char).
  - bool_print (pure-ATS -> strn_print) and bool relational compare.
  - dflt: g_si<dflt> coercion, dflt_add / dflt_mul, dflt_print, dflt comparison.
All bottom out at the typed XATS2GO_* leaves of bool000/char000/gflt000.cats.

Expected stdout:
AZ0
true false true true
B 66
3.5 7.0 12.25 true
*)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_GO_dats.hats"
(* ****** ****** *)
//
// --- chars ---
val () = char_print('A')
val () = char_print('Z')
val () = char_print('0')
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
// --- bool relational ---
val () = bool_print('a' < 'b')   // true
val () = strn_print(" ")
val () = bool_print('b' < 'a')   // false
val () = strn_print(" ")
val () = bool_print('x' = 'x')   // true
val () = strn_print(" ")
val () = bool_print('x' != 'y')  // true
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
// --- char <-> sint round-trip: 'A'(65) + 1 = 'B'(66) ---
val cA = sint_make_char('A')          // 65
val cB = char_make_sint(cA + 1)       // 'B'
val () = char_print(cB)               // B
val () = strn_print(" ")
val () = sint_print(sint_make_char(cB)) // 66
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
// --- floats ---
val f1 = 3.5
val f2 = g_si<dflt>(2)                 // 2.0
val () = dflt_print(f1)                // 3.5
val () = strn_print(" ")
val () = dflt_print(f1 + f2 + 1.5)     // 7
val () = strn_print(" ")
val () = dflt_print(f1 * f1)           // 12.25
val () = strn_print(" ")
val () = bool_print(f1 < f2)           // false
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test_goarm07_scalar_xats2go.dats] *)
