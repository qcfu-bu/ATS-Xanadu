#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_JS_dats.hats"
//
datatype
mytree =
| myleaf of ()
| mynode of (mytree, sint, mytree)
//
fun
mktree(d: sint): mytree =
if (d <= 0) then myleaf() else mynode(mktree(d-1), d, mktree(d-1))
//
fun
sumtree(t: mytree): sint =
(
case+ t of
| myleaf() => 0
| mynode(l, v, r) => sumtree(l) + v + sumtree(r)
)
//
val t0 = mktree(24)
val () = strn_print("treesum=")
val () = sint_print(sumtree(t0) + sumtree(t0))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
