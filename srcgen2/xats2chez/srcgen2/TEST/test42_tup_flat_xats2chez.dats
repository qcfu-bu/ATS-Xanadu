(* ****** ****** *)
(*
M2.6b conformance: a FLAT tuple `@(a,b)` is a Go VALUE struct
`struct{F0 T0; F1 T1}{...}` (stack-allocated, NOT a `[]any` / NOT a pointer),
built and then field-PROJECTED (`p.0 + p.1`).  The construction struct type and
the projection field access (`p.F0`/`p.F1`) are driven from the SAME recorded
[i0typ] (the M2.6a side-table), so Go's structural typing accepts both sites.
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
// flat tuple build + project: @(n, n+1) -> p.0 + p.1
fun
ft(n: sint): sint =
let val p = @(n, n+1) in p.0 + p.1 end
//
val () = sint_print(ft(3))   // 3 + 4 = 7
val () = strn_print("\n")
val () = sint_print(ft(10))  // 10 + 11 = 21
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
