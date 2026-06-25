(* ****** ****** *)
(*
M2.6a ADVERSARIAL: side-table must type a BOOL-returning user-fn result temp
as bool. [b] is bound from [isPos(n)] (user-fn call -> backstop) and used as
an if-test. A WRONG (e.g. int) entry would break `if b`. Byte-equal-vs-JS.
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
isPos(x: sint): bool = x > 0
//
fun
classify(n: sint): sint =
let val b = isPos(n) in (if b then 1 else 0) end
//
val () = sint_print(classify(5))      // 1
val () = strn_print(" ")
val () = sint_print(classify(0 - 3))  // 0
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test40_tytab_bool_xats2chez.dats] *)
(***********************************************************************)
