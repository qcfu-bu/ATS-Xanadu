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
bst =
| bnil of ()
| bnode of (bst, sint, bst)
//
fun
insert(t: bst, k: sint): bst =
(
case+ t of
| bnil() => bnode(bnil(), k, bnil())
| bnode(l, v, r) =>
  (
  if (k < v)
  then bnode(insert(l, k), v, r)
  else (if (k > v) then bnode(l, v, insert(r, k)) else t)
  )
)
//
fun
sumt(t: bst): sint =
(
case+ t of
| bnil() => 0
| bnode(l, v, r) => sumt(l) + v + sumt(r)
)
//
fun
fill(i: sint, x: sint, t: bst): bst =
if (i <= 0) then t else fill(i - 1, imod(x * 75, 65537), insert(t, x))
//
fun
sumrep(k: sint, t: bst, acc: sint): sint =
if (k <= 0) then acc else sumrep(k - 1, t, acc + sumt(t))
//
val t0 = fill(200000, 12345, bnil())
val () = strn_print("bstsum=")
val () = sint_print(sumrep(10, t0, 0))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
