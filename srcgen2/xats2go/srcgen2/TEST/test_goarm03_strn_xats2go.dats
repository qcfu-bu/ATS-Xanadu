(* ****** ****** *)
(*
test_goarm03 — strings through the CATS/GO arm: strn_print of a literal,
strn_length, an int derived from the string, all flushed via the_print_store_log.
Expected stdout: "hello, go!\n10\n"
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
val () = strn_print("hello, go!\n")
val () = the_print_store_log( (*void*) )
//
val () = sint_print(strn_length<>("hello, go!"))
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test_goarm03_strn_xats2go.dats] *)
