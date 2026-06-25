(* ****** ****** *)
(*
Self-hosting GAP A3 conformance: TYPE ANNOTATION `(e : T)`.
//
An ascribed expression `(e : T)` is a TYPE-ONLY annotation -- the runtime
value is just the inner expression `e` -- so the Go backend FORWARDS it to
`e`'s emitted value.  Exercised inside a function body (annotations on
sub-expressions) and on a function argument, so the annotation node is on a
runnable value path.  Each result is printed so stdout is deterministic and
the differential-vs-JS oracle gates correctness.
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
addone
(x: sint): sint = (x : sint) + (1 : sint)
//
val () = sint_print(addone((41 : sint)))   // 42
val () = strn_print(" ")
val () = sint_print(((2 + 3) : sint) * 2)   // 10
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test75_annot.dats] *)
(***********************************************************************)
