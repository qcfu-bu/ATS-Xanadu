#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_JS_dats.hats"
//
fun
imod(a: sint, b: sint): sint = a - (a / b) * b
//
datatype
mylist =
| mynil of ()
| mycons of (sint, mylist)
//
fun
merge(xs: mylist, ys: mylist): mylist =
(
case+ xs of
| mynil() => ys
| mycons(x, xs1) =>
  (
  case+ ys of
  | mynil() => xs
  | mycons(y, ys1) =>
    if (x <= y)
    then mycons(x, merge(xs1, ys))
    else mycons(y, merge(xs, ys1))
  )
)
//
fun
msort(xs: mylist): mylist =
(
case+ xs of
| mynil() => xs
| mycons(x, xs1) =>
  (
  case+ xs1 of
  | mynil() => xs
  | mycons(y, xs2) => split(xs, mynil(), mynil())
  )
) where
{
fun
split(xs: mylist, a: mylist, b: mylist): mylist =
(
case+ xs of
| mynil() => merge(msort(a), msort(b))
| mycons(x, xs1) => split(xs1, mycons(x, b), a)
)
}
//
fun
build(i: sint, x: sint, acc: mylist): mylist =
if (i <= 0) then acc else build(i - 1, imod(x * 75, 65537), mycons(x, acc))
//
fun
chk(xs: mylist, prev: sint, ok: sint, last: sint): sint =
(
case+ xs of
| mynil() => ok * 100000 + last
| mycons(x, xs1) =>
  chk(xs1, x, (if (prev <= x) then ok + 1 else ok), x)
)
//
val s0 = msort(build(200000, 12345, mynil()))
val () = strn_print("msort=")
val () = sint_print(chk(s0, 0 - 1, 0, 0 - 1))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
