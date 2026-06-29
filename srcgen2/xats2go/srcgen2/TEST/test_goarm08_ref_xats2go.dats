(* ****** ****** *)
(*
test_goarm08 — mutable REFERENCES (a0rf / ref) through the CATS/GO arm.
The compiler's side-tables (stampers, tytab, the byref set) are all built on
[a0rf_make_1val] / [a0rf_get] / [a0rf_set], so this rung proves the reference
floor (axrf000) under the typed Go pivot.  A ref holds an int; we read it,
mutate it, read again -- exercising the shared-box mutation semantics.
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
val r0 = a0rf_make_1val<sint>(10)
//
val () = sint_print(a0rf_get<sint>(r0))   // 10
val () = strn_print(" ")
val () = a0rf_set<sint>(r0, 42)
val () = sint_print(a0rf_get<sint>(r0))   // 42
val () = strn_print(" ")
val () = a0rf_set<sint>(r0, a0rf_get<sint>(r0) + 1)
val () = sint_print(a0rf_get<sint>(r0))   // 43
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test_goarm08_ref_xats2go.dats] *)
