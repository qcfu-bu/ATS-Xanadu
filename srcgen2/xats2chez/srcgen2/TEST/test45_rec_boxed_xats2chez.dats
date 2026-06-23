(* ****** ****** *)
(*
M2.6b conformance: a BOXED record `#{x=,y=}` is a Go HEAP POINTER
`&struct{Fx T; Fy T}{...}` -- the `&` (vs the flat record of test44) provably
tracks the [trcdknd].  Projection through the pointer (`r.x`/`r.y`) uses the
SAME `r.F<lab>` field syntax.  Byte-equal-vs-JS.
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
// boxed record build + project: #{x= n, y= n+1} -> r.x + r.y
fun
br(n: sint): sint =
let val r = #{x= n, y= n+1} in r.x + r.y end
//
val () = sint_print(br(3))   // 3 + 4 = 7
val () = strn_print("\n")
val () = sint_print(br(10))  // 10 + 11 = 21
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
