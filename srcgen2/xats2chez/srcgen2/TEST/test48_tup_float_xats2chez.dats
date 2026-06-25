(* ****** ****** *)
(*
M2.6b ADVERSARIAL: a FLAT tuple with NON-INT (float) fields must emit a
value struct with float64 fields (not int / not any). p.0 + p.1.
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
addf(n: dflt): dflt =
let val p = @(n, n + 0.5) in p.0 + p.1 end
//
val () = dflt_print(addf(1.5))    // 1.5 + 2.0 = 3.5
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
