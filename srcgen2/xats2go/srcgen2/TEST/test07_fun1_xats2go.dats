(* ****** ****** *)
(*
M2.2 conformance: a user-defined NON-recursive function with ONE arg,
called once.  [dbl] takes a sint and returns x + x; we call it and print
the result.  Exercises:
  - I1Dfundclst / i1fundcl (the function decl walk)
  - fjarglst / FJARGdarg / i1bnd (one parameter)
  - the function-body return mode (i1cmp -> lets then `return <result>`)
  - I1INSdapp on a user function value (I1Vfid), name-mangling agreement
    between the decl and the call site.
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
dbl(x: sint): sint = x + x
//
val () = sint_print(dbl(21))   // 42
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test07_fun1.dats] *)
(***********************************************************************)
