(* ****** ****** *)
(*
M2.3 conformance: an if-BODIED function (RETURN position).  [clamp]'s body
is `if n > 100 then 100 else n` -- each branch carries its own I1INSrturn,
so go1emit must emit `if <test> { return X } else { return Y }`.  Exercises
I1INSift0 in return mode (the same path the recursive factorial needs).
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
clamp(n: sint): sint =
if (n > 100) then 100 else n
//
val () = sint_print(clamp(250))   // 100
val () = strn_print("\n")
val () = sint_print(clamp(42))    // 42
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test12_if_ret.dats] *)
(***********************************************************************)
