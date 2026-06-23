(* ****** ****** *)
(*
P1 conformance: `case` over STRING literals + a wildcard default.  [optag]
cases a string over string-literal patterns (I0Pstr) and returns a sint code;
[opname] cases a string and returns a string.  Each lowers to I1INScas0 with
I1CLScls(I1GPTpat(I0Pstr ...), body) clauses + a wildcard (I0Pany).  go1emit
emits a Go expression-less `switch { case <casval == "lit">: ...; default:
... }`.  XATSSTRN is identity on the Go string, so the == is a native Go
string comparison.  Byte-equal-vs-JS (the JS backend handles I0Pstr via
f0_str0).
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
optag(s: string): sint =
case+ s of
| "add" => 1
| "sub" => 2
| "mul" => 3
| "div" => 4
| _ => 0
//
fun
opname(s: string): string =
case+ s of
| "+" => "plus"
| "-" => "minus"
| "*" => "times"
| _ => "other"
//
val () = sint_print(optag("add"))   // 1
val () = strn_print(" ")
val () = sint_print(optag("div"))   // 4
val () = strn_print(" ")
val () = sint_print(optag("xyz"))   // 0
val () = strn_print(" ")
val () = strn_print(opname("+"))    // plus
val () = strn_print(" ")
val () = strn_print(opname("*"))    // times
val () = strn_print(" ")
val () = strn_print(opname("?"))    // other
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test91_strpat.dats] *)
(***********************************************************************)
