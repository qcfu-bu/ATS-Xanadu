(* ****** ****** *)
(*
M2.6b conformance: a BOXED tuple `#(a,b)` is a Go HEAP POINTER
`&struct{F0 T0; F1 T1}{...}` (the `&` distinguishes it from the flat VALUE
struct of test42 -- provably tracking the [trcdknd] in the recorded type:
flat = no `&`, boxed = `&`).  Projection through the pointer uses the SAME
`p.F<lab>` syntax (Go auto-derefs).  Byte-equal-vs-JS.
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
// boxed tuple build + project: #(n, n+1) -> p.0 + p.1
fun
bt(n: sint): sint =
let val p = #(n, n+1) in p.0 + p.1 end
//
val () = sint_print(bt(3))   // 3 + 4 = 7
val () = strn_print("\n")
val () = sint_print(bt(10))  // 10 + 11 = 21
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
