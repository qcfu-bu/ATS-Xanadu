(* ****** ****** *)
(*
M2.6c conformance: RECORD field mutation in a mutable `var`.
//
`var p = @{x=1,y=2}` is an addressable Go pointer-to-value-struct with NAMED
fields; `p.x := 10` emits `<deref>.Fx = 10` (the SAME `F<sym>` field-name scheme
the record construction + read projections use, so the lvalue resolves).  Reads
the mutated value back.  Byte-equal-vs-JS.
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
// record var: build @{x=n, y=n*2}, mutate x, read both.
fun
rc(n: sint): sint =
let
  var p = @{ x= n, y= n*2 }
in
  p.x := 50;
  p.x + p.y
end
//
val () = sint_print(rc(3))    // 50 + 6 = 56
val () = strn_print("\n")
val () = sint_print(rc(10))   // 50 + 20 = 70
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
