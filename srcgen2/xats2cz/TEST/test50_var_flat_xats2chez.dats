(* ****** ****** *)
(*
M2.6c conformance: FLAT tuple field mutation in a mutable `var`.
//
`var p = @(1,2)` makes `p` an addressable Go pointer-to-value-struct; `p.0 := 10`
emits the addressable lvalue assignment `<deref>.F0 = 10` (NOT a path-encoding
runtime).  A subsequent read of the SAME var sees the mutation (the ATS var-box
reference semantics) -- so `p.0 + p.1` reads `10 + 2 = 12`.  Byte-equal-vs-JS:
the JS backend models the var as `XATSVAR1(...)` (a reference box), so the
mutation is visible on re-read -- exactly what the Go pointer-var reproduces.
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
// flat tuple var: build @(n, n+1), mutate field 0, read both.
fun
ft(n: sint): sint =
let
  var p = @(n, n+1)
in
  p.0 := 10;
  p.0 + p.1
end
//
val () = sint_print(ft(3))    // 10 + 4 = 14
val () = strn_print("\n")
val () = sint_print(ft(20))   // 10 + 21 = 31
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
