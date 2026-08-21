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
// two-list functional queue: front (deq order) + back (enq order, reversed).
fun
rev(xs: mylist, acc: mylist): mylist =
(
case+ xs of
| mynil() => acc
| mycons(x, xs1) => rev(xs1, mycons(x, acc))
)
//
// enqueue i, then dequeue one; carry the dequeued sum.  2M rounds.
fun
loop(i: sint, n: sint, f: mylist, b: mylist, acc: sint): sint =
if (i > n)
then acc
else
(
case+ f of
| mycons(x, f1) => loop(i + 1, n, f1, mycons(i, b), acc + x)
| mynil() =>
  (
  case+ rev(b, mynil()) of
  | mycons(x, f1) => loop(i + 1, n, f1, mycons(i, mynil()), acc + x)
  | mynil() => loop(i + 1, n, mynil(), mycons(i, mynil()), acc)
  )
)
//
val () = strn_print("qsum=")
val () = sint_print(loop(1, 2000000, mynil(), mynil(), 0))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
