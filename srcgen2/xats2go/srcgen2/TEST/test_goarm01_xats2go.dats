(* ****** ****** *)
(*
test_goarm01 — the first program compiled through the CATS/GO prelude arm
(not the JS arm + shortcut).  It #includes prelude_GO_dats.hats, so sint_print
and the_print_store_log resolve to the GO arm; with the emitter in --go-arm
mode their template bodies are EMITTED, bottoming at the typed XATS2GO_*
primitives of the linked CATS/GO .cats floor (gint000 + xtop000).
//
Expected stdout: "42\n123\n".
*)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_GO_dats.hats"
(* ****** ****** *)
//
val () = sint_print(42)
val () = the_print_store_log( (*void*) )
//
val () = sint_print(sint_add$sint(100, 23))
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test_goarm01_xats2go.dats] *)
