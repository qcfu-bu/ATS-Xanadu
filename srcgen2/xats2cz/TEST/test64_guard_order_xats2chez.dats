(* ****** ****** *)
(*
M2.7 ADVERSARIAL: a field-projecting GUARD clause placed FIRST, so a `mynil`
value is tested against `mycons(h,t) when h>5` (Tag==1 && h>5) BEFORE the
`mynil` clause. Only the Go `&&` short-circuit stops `nil.Args[0].(int)` from
panicking. f(nil)=0 proving the short-circuit holds. Byte-equal-vs-JS.
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
datatype
mylist = mynil of () | mycons of (sint, mylist)
//
fun
f(xs: mylist): sint =
(
case+ xs of
| mycons(h, t) when h > 5 => 100   // guard projects h, tested FIRST
| mynil() => 0
| mycons(h, t) => h
)
//
val () =
sint_print(f(mynil()) + f(mycons(3, mynil())) + f(mycons(9, mynil())))
// 0 + 3 + 100 = 103
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
