(* ****** ****** *)
(*
Self-host: prelude list_length runtime. Build a list and length it.
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
mklist(): list(sint) =
list_cons(10, list_cons(20, list_cons(30, list_nil())))
//
val () = sint_print(list_length<sint>(mklist()))   // 3
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
