(* ****** ****** *)
(*
CONTROL-FLOW return-mode regression (the GENERAL I1INSlet0-propagates-return-
mode fix, not just `if`): a `let` whose BODY is a returning `case`, as a
FUNCTION BODY (return position).  [f]'s body `let val k = n in case k of 0 =>
10 | _ => 20 end` lowers to I1INSlet0(dcls, body) where [body] is a fully-
returning I1INScas0 (each clause ends in I1INSrturn).  Before the fix the let
emitted in VALUE mode (`var goxtnm<N> int` + trailing `return goxtnm<N>`),
making that trailing return UNREACHABLE after the switch's returns
(`go vet`: "unreachable code").  With the fix the let emits in RETURN mode:
`{ <val k>; switch { ... return ... } }` -- no result temp, no trailing
return.  Byte-equal-vs-JS.
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
f(n: sint): sint =
let val k = n in
  case+ k of
  | 0 => 10
  | _ => 20
end
//
val () = sint_print(f(0))     // 10
val () = strn_print(" ")
val () = sint_print(f(7))     // 20
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [test41_let_case_xats2go.dats] *)
(***********************************************************************)
