(* ****** ****** *)
(*
M2.7 conformance: a binary TREE (leaf/node) built then recursively SUMMED.
Exercises a datatype with a constructor of arity 3 (left, value, right) where
TWO fields are the datatype itself -- so a `node` case projects+asserts BOTH
sub-trees to a boxed XatsCon pointer and recurses through them, and the middle
field is an int.  Monomorphic so field Go types are recoverable.  Byte-eq-vs-JS.
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
mytree =
| myleaf of ()
| mynode of (mytree, sint, mytree)
//
// recursive sum of all node values.
fun
treesum(t: mytree): sint =
(
case+ t of
| myleaf() => 0
| mynode(lft, v, rgt) => treesum(lft) + v + treesum(rgt)
)
//
//        5
//       / \
//      3   8
//     / \
//    1   4
val e = myleaf()
val n1 = mynode(e, 1, e)
val n4 = mynode(e, 4, e)
val n3 = mynode(n1, 3, n4)
val n8 = mynode(e, 8, e)
val n5 = mynode(n3, 5, n8)
//
val () = sint_print(treesum(n5))   // 5+3+8+1+4 = 21
val () = strn_print("\n")
val () = sint_print(treesum(e))    // empty -> 0
val () = strn_print("\n")
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
