(* ****** ****** *)
(*
M2.2 STOPGAP probe: a simple RECURSIVE function.  Full recursion + TCO is
M2.4; M2.2 only needs to NOT BREAK if a self-call appears.  Because the Go
backend emits user functions at PACKAGE level, a self-call resolves
naturally as a Go recursive call (no closure self-ref gymnastics needed).
[fact] is non-tail recursive; [sumto] is tail-ish.  If this passes
byte-equal-vs-JS it confirms the stopgap; if it surfaces an unhandled
recursion node it documents exactly what M2.4 must pick up.
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
fact(n: sint): sint =
if (n > 0) then n * fact(n - 1) else 1
//
val () = sint_print(fact(5))    // 120
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test11_fun_rec.dats] *)
(***********************************************************************)
