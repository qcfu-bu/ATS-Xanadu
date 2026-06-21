(* ****** ****** *)
(*
M2.6a ADVERSARIAL: side-table must type a FLOAT-returning user-fn result temp
as float64 (NOT int). [a] is bound from [sqf(n)] (user-fn call -> local
recovery fails -> backstop). A WRONG int entry would make `a + 1.0` a
float64+int go-build error. Byte-equal-vs-JS.
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
sqf(x: dflt): dflt = x * x
//
fun
gf(n: dflt): dflt =
(let val a = sqf(n) in a end) + 1.0
//
val () = dflt_print(gf(3.0))    // 9.0 + 1.0 = 10
val () = strn_print(" ")
val () = dflt_print(gf(0.5))    // 0.25 + 1.0 = 1.25
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test39_tytab_float_xats2go.dats] *)
(***********************************************************************)
