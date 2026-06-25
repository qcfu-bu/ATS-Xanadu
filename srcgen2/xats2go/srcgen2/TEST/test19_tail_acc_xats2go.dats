(* ****** ****** *)
(*
M2.4: a tail-recursive ACCUMULATOR at a moderate, checkable n.
`fun fac(n, acc) = if n <= 0 then acc else fac(n-1, acc*n)` -- factorial via
a tail-recursive accumulator.  fac(10, 1) = 3628800.  This exercises the
SAME TCO loop emission as the deep-loop test but with a result that is easy
to check by hand (and against the JS oracle).  The tail self-call's args
(`n-1`, `acc*n`) are pre-bound to ANF temps before the call, so the
parameter reassignment (goxtnm<p1>=t1; goxtnm<p2>=t2; continue) is
simultaneity-safe.
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
fac(n: sint, acc: sint): sint =
if (n <= 0) then acc else fac(n - 1, acc * n)
//
val () = strn_print("fac(10)=")
val () = sint_print(fac(10, 1))    // 3628800
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test19_tail_acc.dats] *)
(***********************************************************************)
