(* ****** ****** *)
(*
M2.7 HEADLINE: a recursive INT LIST, built with cons/nil, then pattern-matched
RECURSIVELY to SUM it.  Exercises:
  - datacon construction through a *xatsgo.XatsCon chain (cons(1, cons(2, ...)));
  - a datacon `case` with a tag test (v.Tag == ctag) + typed projections, where
    the cons-TAIL field is the datatype itself -> projects + asserts to the boxed
    XatsCon pointer (the RECURSION case: v.Args[1] asserted to a XatsCon ptr), and
    the head field is an int;
  - recursion through the boxed datatype (mylist value flows as *XatsCon).
A monomorphic `mylist` (no type parameter) so the head/tail field Go types are
recoverable from the constructors.  Byte-equal-vs-JS.
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
mylist =
| mynil of ()
| mycons of (sint, mylist)
//
// recursive sum of a mylist.
fun
sumlist(xs: mylist): sint =
(
case+ xs of
| mynil() => 0
| mycons(x, rest) => x + sumlist(rest)
)
//
// build  cons(1, cons(2, cons(3, cons(4, nil))))
val l0 = mynil()
val l1 = mycons(4, l0)
val l2 = mycons(3, l1)
val l3 = mycons(2, l2)
val l4 = mycons(1, l3)
//
val () = sint_print(sumlist(l4))   // 1+2+3+4 = 10
val () = strn_print("\n")
val () = sint_print(sumlist(l0))   // empty -> 0
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
