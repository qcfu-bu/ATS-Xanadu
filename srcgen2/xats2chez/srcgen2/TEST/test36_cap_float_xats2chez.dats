(* ****** ****** *)
(*
ADVERSARIAL M2.5 (anti-overfit): a closure that CAPTURES a float64 (NOT int).
Guards the BUG-1 return-type recovery against being hard-wired to `int`: the
captured `a` is a `double`, so the lambda body `lam u => a` must recover the
result Go type from the param's static type (double -> float64) via the SAME
d2var_get_styp path, emitting `func(int) float64` (NOT `func(int) any` and NOT
`func(int) int`).
  mkf(a: double) = lam u => a
  k35 = mkf(3.5) ; k35(0) = 3.5
HAND-COMPUTED EXPECTED: kf=3.5
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
mkf(a: double): sint -> double = lam(u: sint): double => a
//
val k35 = mkf(3.5)
//
val () = strn_print("kf=")
val () = dflt_print(k35(0))    // 3.5
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test36_cap_float_xats2chez.dats] *)
(***********************************************************************)
