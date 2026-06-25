(* ****** ****** *)
(*
M2.2 conformance: a function CALLING ANOTHER function.  [inc] adds one;
[inc2] calls [inc] twice.  Exercises a user-function call FROM WITHIN a
function body (the callee resolves to the package-level Go func emitted in
pass 1; both decl and call site agree on the mangled name).  Also confirms
that [inc]'s decl is emitted BEFORE / independently of [inc2]'s and the
package-level ordering is sound (Go resolves package funcs regardless of
textual order, so even forward references are fine).
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
inc(x: sint): sint = x + 1
//
fun
inc2(x: sint): sint = inc(inc(x))
//
val () = sint_print(inc2(40))   // 42
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test09_fun_call_fun.dats] *)
(***********************************************************************)
