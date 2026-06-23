(* ****** ****** *)
(*
HX-2026-06-23:
Walking-skeleton ("Hello World") input for xats2chez milestone M1.
A single [strn_print] of a string literal through the print store, then a
flush via [the_print_store_log]. Lowers (frontend -> trxd3i0 -> tryd3i0) to
a top-level [val () = ...] whose body is an application of a prelude dynamic
constant ([strn_print]/[the_print_store_log]) to a string literal.
*)
(* ****** ****** *)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
(* ****** ****** *)
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_JS_dats.hats"
(* ****** ****** *)
(* ****** ****** *)
//
val () =
strn_print("Hello from [test01_xats2chez]!\n")
//
(* ****** ****** *)
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test01_xats2chez.dats] *)
(***********************************************************************)
