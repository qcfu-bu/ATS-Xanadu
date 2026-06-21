(* ****** ****** *)
(*
M2.3 conformance: a `case` with GUARDS.  [sgn]'s clauses use `when` guards
(I1GPTgua), so go1emit folds each guard into the Go case CONDITION
(`case <patcond> && <guard>:`), making a failed guard fall through to the
NEXT clause -- matching the JS backend's retry semantics.  Byte-equal-vs-JS.
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
sgn(n: sint): sint =
case+ n of
| _ when n > 0 => 1
| _ when n < 0 => 0
| _ => 5
//
val () = sint_print(sgn(7))       // 1
val () = strn_print(" ")
val () = sint_print(sgn(0 - 4))   // 0
val () = strn_print(" ")
val () = sint_print(sgn(0))       // 5
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test16_case_guard.dats] *)
(***********************************************************************)
