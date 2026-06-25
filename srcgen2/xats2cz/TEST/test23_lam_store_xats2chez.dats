(* ****** ****** *)
(*
M2.5: a lambda STORED in a val and CALLED LATER (no capture).  `val sqr =
lam(x) => x*x` then `sqr(7)` => 49.  Exercises a lambda bound to a top-level
val (the func-literal value flows through I1Vtnm), then applied at a later
point -- the "closure stored and called later" shape, here capture-free so it
is JS-ORACLE-validated (the JS backend's lam0 env-capture bug is not on this
path).  Prints `sqr(7)=49`.  Must be byte-equal-vs-JS.
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
mksqr((*void*)): sint -> sint = lam(x: sint): sint => x * x
//
val sqr = mksqr()
//
val () = strn_print("sqr(7)=")
val () = sint_print(sqr(7))    // 49
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test23_lam_store.dats] *)
(***********************************************************************)
