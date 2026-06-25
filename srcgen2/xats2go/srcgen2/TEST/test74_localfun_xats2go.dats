(* ****** ****** *)
(*
test74_localfun — GAP-1 (self-hosting): a NESTED (local) function emitted as a
Go LOCAL CLOSURE.
//
[fact] is the task's canonical GAP-1 shape: a `fun loop` declared inside
[fact]'s `where { var res ... }` that (a) CAPTURES the surrounding `var res`
and MUTATES it, and (b) is SELF-RECURSIVE.  It must emit as
    var res int = 1
    var loop func(int) ...
    loop = func(i int) ... { ... res = res * (i+1); loop(i+1) ... }
i.e. a local closure (`var f F; f = func(){..}`) -- NOT a hoisted package-level
func (which could not see [res]).  The pre-declared `var loop` gives the
self-reference; Go's lexical capture shares [res].
//
[summ] is a second local fun (no capture) computing 0+1+..+n by a captured
accumulator -- a tail-recursive local closure (the TCO `for{..continue}` loop).
Output is deterministic + byte-equal-vs-JS (the differential oracle).
*)
(* ****** ****** *)
//
#include
"prelude/HATS/prelude_dats.hats"
//
#include
"prelude/HATS/prelude_JS_dats.hats"
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
fact(n: sint): sint =
(
  loop(0); res ) where
{
var res: sint = 1
fun loop(i: sint): void =
if i < n then
(res := res * (i+1); loop(i+1))
}
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
summ(n: sint): sint =
(
  aux(0, 0)) where
{
fun
aux(i: sint, acc: sint): sint =
if (i > n) then acc else aux(i+1, acc+i)
}
//
(* ****** ****** *)
(* ****** ****** *)
//
val () =
prints("fact(5) = ", fact(5), "\n")
val () =
prints("summ(100) = ", summ(100), "\n")
//
(* ****** ****** *)
(* ****** ****** *)
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [test74_localfun_xats2go.dats] *)
(***********************************************************************)
