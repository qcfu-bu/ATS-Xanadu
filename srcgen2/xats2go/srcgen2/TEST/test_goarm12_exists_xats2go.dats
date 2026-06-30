(* ****** ****** *)
(*
go-arm rung 12: list_exists with a template-method predicate (exists$test).
Probes whether go-arm body-emission inlines a TEMPLATE-METHOD prelude prim
(the family the emitter's own sources use: exists/sortedq/map/mergesort).
*)
(* ****** ****** *)
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_GO_dats.hats"
(* ****** ****** *)
//
fun
has_big
(xs: list(sint)): bool =
(
list_exists(xs)) where
{
#impltmp
exists$test<sint>(x0) =
(x0 >= 10)
}
//
val xs = list_cons(1, list_cons(20, list_cons(3, list_nil())))
val ys = list_cons(1, list_cons(2, list_nil()))
//
val () = (bool_print(has_big(xs)); strn_print(" "))
val () = (bool_print(has_big(ys)); strn_print("\n"))
val () = console_log(the_print_store_flush( (*void*) ))
//
(* ****** ****** *)
(* end of [test_goarm12_exists_xats2go.dats] *)
(* ****** ****** *)
