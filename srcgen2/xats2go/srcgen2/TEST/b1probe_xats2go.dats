(* ****** ****** *)
(*
B1 PROBE: pattern-match a PRELUDE list(sint) DIRECTLY and recurse on the
cons-TAIL.  Unlike test76/79 (which call hand-written runtime helpers that
walk *XatsCon in Go), this forces the emitter to type the projected `rest`
itself.  Today the cons-tail projects as `any`, so `sumlist(rest)` passes an
`any` where a list/*XatsCon is expected -> the B1 typing gap.
*)
(* ****** ****** *)
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
(* ****** ****** *)
//
fun
sumlist(xs: list(sint)): sint =
(
case+ xs of
| list_nil() => 0
| list_cons(x, rest) => x + sumlist(rest)
)
//
val l0 = list_cons(1, list_cons(2, list_cons(3, list_nil())))
val () = sint_print(sumlist(l0))   // 1+2+3 = 6
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
