(* ****** ****** *)
(*
ADVERSARIAL M2.5: capture-by-VALUE-at-creation-time semantics.  Two closures
are built capturing the SAME source name `a`, but at points where `a` has
DIFFERENT values (a let-shadowed inner `a`).  ATS bindings are immutable, so
each closure must see the `a` that was in scope WHERE IT WAS CREATED, not a
single shared cell.
  mk(a) = lam u => a            (returns a constant-function over captured a)
  two(a0):
     let val c0 = mk(a0)        // captures a0
         val a  = a0 + 1000     // inner shadow
         val c1 = mk(a)         // captures a0+1000
     in c0(0) + c1(0) * 0  ...  -- we print both separately instead
  Driver: mk(7) -> k7 ; mk(42) -> k42 ; print k7(0), k42(0), k7(0) again.
  If capture were by a shared/last cell, k7(0) would change after k42 made.
HAND-COMPUTED EXPECTED:  t0=7 t1=42 t2=7
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
mk(a: sint): sint -> sint = lam(u: sint): sint => a
//
val k7  = mk(7)
val k42 = mk(42)
//
val () = strn_print("t0=")
val () = sint_print(k7(0))     // 7
val () = strn_print(" t1=")
val () = sint_print(k42(0))    // 42
val () = strn_print(" t2=")
val () = sint_print(k7(0))     // 7  (unchanged after k42 created)
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test34_cap_timing_xats2chez.dats] *)
(***********************************************************************)
