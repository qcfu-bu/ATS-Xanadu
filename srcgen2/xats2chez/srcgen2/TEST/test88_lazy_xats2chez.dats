(* ****** ****** *)
(*
Lazy stream forcing parity rung.

Adapted from xats2js/srcgen1/TEST/test10_xats2js.dats.  The key observable
is that forcing the same non-linear lazy stream twice evaluates the thunk only
once and returns the memoized head both times.
*)
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_JS_dats.hats"
#include
"prelude/HATS/prelude_NODE_dats.hats"
(* ****** ****** *)

fun
strm_sint$from
( n0
: sint): strm(sint) =
$lazy(
strmcon_cons
(n0, strm_sint$from(n0+1))
where
{
val () =
printsln("strm_sint$from: n0 = ", n0)
})

(* ****** ****** *)

val xs = strm_sint$from(101)

val () =
(
printsln("x1 = ", x1)
) where
{
val-strmcon_cons(x1, ys) = (!xs)
}

val () =
(
printsln("x1 = ", x1)
) where
{
val-strmcon_cons(x1, ys) = (!xs)
}

(* ****** ****** *)
(* end of [test88_lazy_xats2chez.dats] *)
