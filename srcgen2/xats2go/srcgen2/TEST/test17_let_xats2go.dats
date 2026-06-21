(* ****** ****** *)
(*
M2.3 conformance: a `let ... in ... end` NESTED expression (value position).
[g]'s body `(let val a = n + 1 in a * a end) + 100` lowers to I1INSlet0(dcls,
cmp): go1emit pre-declares `var goxtnm<tnm> int` (the let-in result type,
recovered from the body's native `*`), emits the inner `val a` as a local Go
decl, assigns the inner result, then the `+ 100` consumes it.  Byte-equal-vs-JS.
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
g(n: sint): sint =
(let val a = n + 1 in a * a end) + 100
//
val () = sint_print(g(3))    // (4*4)+100 = 116
val () = strn_print("\n")
val () = sint_print(g(0))    // (1*1)+100 = 101
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test17_let.dats] *)
(***********************************************************************)
