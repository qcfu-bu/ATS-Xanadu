#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_JS_dats.hats"
//
datatype
mylist =
| mynil of ()
| mycons of (sint, mylist)
//
fun
build(i: sint, acc: mylist): mylist =
if (i <= 0) then acc else build(i - 1, mycons(i, acc))
//
fun
sumlist(xs: mylist): sint =
(
case+ xs of
| mynil() => 0
| mycons(x, rest) => x + sumlist(rest)
)
//
fun
sumrep(k: sint, xs: mylist, acc: sint): sint =
if (k <= 0) then acc else sumrep(k - 1, xs, acc + sumlist(xs))
//
val xs = build(300000, mynil())
val () = strn_print("listsum=")
val () = sint_print(sumrep(20, xs, 0))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
