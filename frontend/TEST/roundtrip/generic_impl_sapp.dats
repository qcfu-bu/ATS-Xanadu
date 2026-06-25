(* Regression: #implfun after-name static binders must scope local helper annotations. *)

#extern
fun
list_generic_impl_fnp
{syn:tx}
( lst: list(syn)
, fpr: (syn) -> (syn)): list(syn)

#implfun
list_generic_impl_fnp
{ syn:tx }
( lst, fpr ) =
(
  auxlst(lst)) where
{
fun
auxlst
( lst: list(syn)): list(syn) =
case+ lst of
| list_nil() => list_nil()
| list_cons(x0, xs) => list_cons(fpr(x0), auxlst(xs))
}
