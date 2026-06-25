(* ****** ****** *)
(*
M2.6a conformance: the [i1tnm stamp -> i0typ] SIDE-TABLE drives a CONCRETE
Go type into a VALUE-POSITION result temp whose producer is a USER-FUNCTION
CALL (not a native scalar op).
//
[g]'s body `(let val a = sq(n) in a end) + 1` lowers to an I1INSlet0 whose
result temp is bound from `sq(n)` -- a [dapp] to the user function [sq],
which the intrep1-level local recovery CANNOT type (it is not a native op
and not a literal), so before M2.6a the emitter pre-declared `var goxtnm<N>
any`, then `(goxtnm<N> + 1)` failed to type-check (`any + int`).  With the
side-table, the temp's recorded [i0typ] (the result type of `sq`, an [sint])
types the var as `int`, so `(goxtnm<N> + 1)` is native Go `int` arithmetic.
Byte-equal-vs-JS.
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
sq(x: sint): sint = x * x
//
// the let-in result `a` is bound from `sq(n)` (a user-fn call) -- its Go type
// is recoverable ONLY via the M2.6a side-table.
fun
g(n: sint): sint =
(let val a = sq(n) in a end) + 1
//
val () = sint_print(g(3))    // sq(3)+1 = 10
val () = strn_print("\n")
val () = sint_print(g(5))    // sq(5)+1 = 26
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test38_tytab.dats] *)
(***********************************************************************)
