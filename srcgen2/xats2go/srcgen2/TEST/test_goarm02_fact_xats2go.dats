(* ****** ****** *)
(*
test_goarm02 — recursion + control flow through the CATS/GO prelude arm.
A recursive factorial: exercises the emitter's fun/if/recursion machinery
TOGETHER with the go-arm prelude-body path (sint_print + the_print_store_log
-> XATS2GO_* floor).  Native ops (sint_lte/sint_mul/sint_sub) stay Go infix.
//
Expected stdout: "120\n3628800\n"  (fact(5)=120, fact(10)=3628800)
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
fun
fact(n: sint): sint =
if (n <= 0) then 1 else n * fact(n-1)
//
val () = sint_print(fact(5))
val () = the_print_store_log( (*void*) )
//
val () = sint_print(fact(10))
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test_goarm02_fact_xats2go.dats] *)
