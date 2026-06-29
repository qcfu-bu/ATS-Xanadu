(* ****** ****** *)
(*
test_goarm04 — a USER datatype + recursion + pattern matching through the
CATS/GO arm.  Datatypes/pattern-matching are emitter machinery (not prelude),
so this checks the boxed-datatype path coexists with go-arm prelude-body
emission.  Expected stdout: "3\n60\n"
*)
(* ****** ****** *)
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_GO_dats.hats"
(* ****** ****** *)
datatype mylist =
| mynil of () | mycons of (sint, mylist)
//
fun
mylen(xs: mylist): sint =
case+ xs of
| mynil() => 0 | mycons(_, xs1) => 1 + mylen(xs1)
//
fun
mysum(xs: mylist): sint =
case+ xs of
| mynil() => 0 | mycons(x, xs1) => x + mysum(xs1)
//
val xs =
mycons(10, mycons(20, mycons(30, mynil())))
//
val () = sint_print(mylen(xs))
val () = the_print_store_log()
val () = sint_print(mysum(xs))
val () = the_print_store_log()
(* ****** ****** *)
