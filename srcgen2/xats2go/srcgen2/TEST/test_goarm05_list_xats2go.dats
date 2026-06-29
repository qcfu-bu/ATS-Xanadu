(* ****** ****** *)
(* test_goarm05 — the PRELUDE list type through CATS/GO (test79 logic). *)
(* ****** ****** *)
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_GO_dats.hats"
(* ****** ****** *)
fun mk(): list(sint) = list_cons(1, list_cons(2, list_cons(3, list_nil())))
fun run0(): sint = list_length<sint>(list_reverse<sint>(mk()))
val () = (sint_print(run0()); the_print_store_log())
(* ****** ****** *)
