(* ****** ****** *)
(*
ADVERSARIAL M2.5: SHADOWING.  An outer `n` is captured by an OUTER lambda,
but an INNER lambda's PARAMETER is also named `n` and must SHADOW the
capture.  If the divergence's outer-binding resolution wrongly bound the
inner `n` to the captured outer `n`, the answer would change.
  shdw(n) = lam k => (lam n => n + 1)(k) + n
  shdw(100) called with k=7:
    inner (lam n => n+1) applied to 7  = 8
    + outer captured n (=100)          = 108
HAND-COMPUTED EXPECTED: shadow=108
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
shdw(n: sint): sint -> sint =
  lam(k: sint): sint =>
    (lam(n: sint): sint => n + 1)(k) + n
//
val f108 = shdw(100)
//
val () = strn_print("shadow=")
val () = sint_print(f108(7))    // 108
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test31_shadow_xats2chez.dats] *)
(***********************************************************************)
