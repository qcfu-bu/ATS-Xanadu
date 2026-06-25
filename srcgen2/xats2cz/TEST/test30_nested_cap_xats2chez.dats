(* ****** ****** *)
(*
ADVERSARIAL M2.5: MULTI-LEVEL capture.  f(a) = lam b => lam c => a + b + c.
The INNERMOST lambda captures BOTH `b` (1 level out) AND `a` (2 levels out).
This stresses the diverged outer-binding resolution: each captured var must
resolve to its OWN enclosing Go local, across two lambda-marker frames.
  f(100)(20)(3) = 123.
HAND-COMPUTED EXPECTED: nest=123
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
f(a: sint): sint -> (sint -> sint) =
  lam(b: sint): (sint -> sint) =>
    lam(c: sint): sint => a + b + c
//
val g  = f(100)
val h  = g(20)
val r  = h(3)
//
val () = strn_print("nest=")
val () = sint_print(r)    // 123
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test30_nested_cap_xats2chez.dats] *)
(***********************************************************************)
