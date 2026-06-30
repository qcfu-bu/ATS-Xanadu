(* ****** ****** *)
(*
go-arm rung 10: prints(..., <list>, ...) — multi-element gseq print.
Based on prelude/TEST/CATS/JS/test06_list000.dats (minimal slice).
Exercises the gseq sep="," path (rung 9's single-element optn did not).
*)
(* ****** ****** *)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
(* ****** ****** *)
(* ****** ****** *)
//
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_GO_dats.hats"
//
(* ****** ****** *)
(* ****** ****** *)
//
val ns =
list_cons(1, list_cons(2, list_cons(3, list_nil())))
//
val () =
prints("ns = ", ns, "\n")
val () = prints
("|ns| = ", length(ns), "\n")
//
(* ****** ****** *)
(* ****** ****** *)
//
val () = console_log(the_print_store_flush( (*void*) ))
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [test_goarm10_list_xats2go.dats] *)
(***********************************************************************)
