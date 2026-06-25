(* ****** ****** *)
(*
ADVERSARIAL M2.5 (anti-overfit): a 3-LEVEL nested capture (one deeper than
test30).  g(a) = lam b => lam c => lam d => a + b + c + d.  The innermost
lambda captures b, c (1 and 2 levels out) AND a (3 levels out).  This stresses
the return-type recovery's NESTED-lambda recursion at depth 3: g returns
`func(int) func(int) func(int) int`, and each intermediate lambda's return type
must recurse one more level (NOT degrade to `any` at the 2nd/3rd nesting, which
would collide with the enclosing concrete signature -> go vet failure).
  g(1000)(200)(30)(4) = 1234.
HAND-COMPUTED EXPECTED: nest3=1234
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
g(a: sint): sint -> (sint -> (sint -> sint)) =
  lam(b: sint): (sint -> (sint -> sint)) =>
    lam(c: sint): (sint -> sint) =>
      lam(d: sint): sint => a + b + c + d
//
val g1 = g(1000)
val g2 = g1(200)
val g3 = g2(30)
val r  = g3(4)
//
val () = strn_print("nest3=")
val () = sint_print(r)    // 1234
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test37_nest3_xats2chez.dats] *)
(***********************************************************************)
