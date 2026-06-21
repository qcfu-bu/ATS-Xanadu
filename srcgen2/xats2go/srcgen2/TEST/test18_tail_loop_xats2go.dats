(* ****** ****** *)
(*
M2.4 HEADLINE: a DEEP tail-recursive loop.  `fun loop(i, acc) = if i <= 0
then acc else loop(i-1, acc+i)` is a TAIL self-call -- the recursive call
is in tail position (its result IS the function's result).  With TCO this
emits as a Go `for { ... goxtnm<p> = ...; continue }` loop, so the deep
iteration count (50_000_000) runs in O(1) stack and completes instantly.
WITHOUT TCO a plain Go recursive call would overflow the goroutine stack
("goroutine stack exceeds ...") at this depth -- so a green run PROVES the
loop was emitted.  The JS backend also does TCO (it won't overflow either),
so the byte-equal-vs-JS oracle holds.  sum(1..50_000_000) = 1250000025000000.
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
loop(i: sint, acc: sint): sint =
if (i <= 0) then acc else loop(i - 1, acc + i)
//
val () = strn_print("sum=")
val () = sint_print(loop(50000000, 0))    // 1250000025000000
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test18_tail_loop.dats] *)
(***********************************************************************)
