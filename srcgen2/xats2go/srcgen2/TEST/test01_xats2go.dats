(* ****** ****** *)
(*
HX-2026-06-20:
Walking-skeleton ("Hello World") input source for xats2go milestone M1.
//
It exercises the SIMPLEST real prelude print path that routes through the
print store: a single [strn_print] of a string literal, then a flush via
[the_print_store_log]. This lowers (through the shared frontend ->
trxd3i0 -> trxi0i1 spine) to a top-level [val () = ...] whose i1cmp body
is an [I1INSdapp] of an [I1Vcst] (the prelude [strn_print]/[the_print_store_log])
applied to an [I1Vs00]/[I1Vstr] string literal. M1's [go1emit] traverses
exactly those IR nodes and emits real, runnable Go.
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
strn_print("Hello from [test01_xats2go]!\n")
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
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test01_xats2go.dats] *)
(***********************************************************************)
