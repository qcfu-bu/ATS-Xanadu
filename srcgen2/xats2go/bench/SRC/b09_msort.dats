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
// runlist: the worklist of sorted runs for BOTTOM-UP mergesort.
datatype
runlist =
| rnil of ()
| rcons of (mylist, runlist)
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
// singleton runs from the input (reverses order; sort output is unaffected).
fun
runs(xs: mylist, acc: runlist): runlist =
(
case+ xs of
| mynil() => acc
| mycons(x, xs1) => runs(xs1, rcons(mycons(x, mynil()), acc))
)
//
// one bottom-up pass: merge ADJACENT pairs of runs (halves the run count).
fun
pairup(rs: runlist): runlist =
(
case+ rs of
| rnil() => rnil()
| rcons(a, rs1) =>
  (
  case+ rs1 of
  | rnil() => rcons(a, rnil())
  | rcons(b, rs2) => rcons(merge(a, b), pairup(rs2))
  )
)
//
// iterate passes until a single run remains.
fun
mergeall(rs: runlist): mylist =
(
case+ rs of
| rnil() => mynil()
| rcons(a, rs1) =>
  (
  case+ rs1 of
  | rnil() => a
  | rcons(_, _) => mergeall(pairup(rs))
  )
)
//
fun
msort(xs: mylist): mylist = mergeall(runs(xs, rnil()))
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
val s0 = msort(build(1000000, 12345, mynil()))
val () = strn_print("msort=")
val () = sint_print(chk(s0, 0 - 1, 0, 0 - 1))
val () = strn_print("\n")
val () = the_print_store_log((*void*))
