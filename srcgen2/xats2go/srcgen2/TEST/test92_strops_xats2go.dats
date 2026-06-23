(* ****** ****** *)
(*
B1 conformance: STRING equality (`strn_eq`) + string char-at (`strn_get_at`).
[classify] uses `s = "lit"` in an `if`-chain -- string `=` lowers to a
`strn_eq` d2cst; go1emit inlines it to a NATIVE Go `==` (valid on Go strings,
XATSSTRN is identity), so the bool flows into `if` directly (an `any`-returning
runtime call would not type-check there).  [headcode] uses `strn_get$at(s, 0)`
(the byte-at-index char primitive go1emit_utils0 itself relies on) and compares
it with a char literal via native `char_eq`.  Byte-equal-vs-JS.
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
classify(s: string): sint =
if s = "add" then 1 else
if s = "sub" then 2 else
if s = "mul" then 3 else 0
//
fun
startsA(s: string): bool =
strn_get$at(s, 0) = 'A'
//
val () = sint_print(classify("add"))   // 1
val () = strn_print(" ")
val () = sint_print(classify("mul"))   // 3
val () = strn_print(" ")
val () = sint_print(classify("xyz"))   // 0
val () = strn_print(" ")
val () = bool_print(startsA("Apple"))  // true
val () = strn_print(" ")
val () = bool_print(startsA("apple"))  // false
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test92_strops.dats] *)
(***********************************************************************)
