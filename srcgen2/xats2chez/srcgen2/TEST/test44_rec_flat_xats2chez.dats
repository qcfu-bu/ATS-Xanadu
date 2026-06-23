(* ****** ****** *)
(*
M2.6b conformance: a FLAT record `@{x=,y=}` is a Go VALUE struct with NAMED
fields `struct{Fx T; Fy T}{...}`, built + field-PROJECTED (`r.x + r.y`).  The
record label `x` maps to Go field `Fx` at BOTH the construction struct type and
the projection (`r.Fx`), via the single [gofield_of_label] scheme.
Byte-equal-vs-JS.
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
// flat record build + project: @{x= n, y= n+1} -> r.x + r.y
fun
fr(n: sint): sint =
let val r = @{x= n, y= n+1} in r.x + r.y end
//
val () = sint_print(fr(3))   // 3 + 4 = 7
val () = strn_print("\n")
val () = sint_print(fr(10))  // 10 + 11 = 21
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
