(* ****** ****** *)
(*
Blocker-(a) regression: a NATIVE ordered/arith op consuming an `any`-returning
prelude-call result.  `strn_length(s)` is a scalar-QUERY prelude fn; its result
flows straight into native Go `>`/`-`/`+` operators.  Before the fix
`Xats_strn_length` returned `any`, so the emitted `(strn_length(s) > n)` was
`int > any` -- a Go COMPILE ERROR (`operator > not defined on interface`) that
the synthetic suite never hit (its operands were always concrete literals/
params).  Fix: scalar-query runtime fns return their CONCRETE Go scalar (here
`int`, like `Xats_sint_abs`/`Xats_list_length` already do), so `(a OP b)`
type-checks with zero emitter change.  [excess] also feeds the result through
both a comparison AND arithmetic; [pad] feeds it into `+`.  Byte-equal-vs-JS
(the JS backend has the same strn_length).
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
excess(s: string): sint =
if strn_length(s) > 3 then strn_length(s) - 3 else 0
//
fun
pad(s: string): sint =
strn_length(s) + 10
//
val () = sint_print(excess("hi"))        // len 2 -> 0
val () = strn_print(" ")
val () = sint_print(excess("hello"))     // len 5 -> 2
val () = strn_print(" ")
val () = sint_print(excess("abcdefgh"))  // len 8 -> 5
val () = strn_print(" ")
val () = sint_print(pad(""))             // 0 + 10 -> 10
val () = strn_print(" ")
val () = sint_print(pad("xyz"))          // 3 + 10 -> 13
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_TEST_test93_strlen_op.dats] *)
(***********************************************************************)
