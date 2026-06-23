(* Regression: `list_vt` is registered at TWO arities under one name (the #vwtpdef
   `list_vt(a)` AND the datavtype `list_vt(a, n)`). An APPLIED `list_vt(elt, n)` must
   select the arity-2 member (stock's f0_a1pp_els2 / s2cst_selects_list), not the bare
   head (which cast the stray index arg to S2Tnone0). *)

#vwtpdef
inner_vt = list_vt(sint)

#implfun
list_vt_dual_arity_free
{n: int}
( xss: list_vt(inner_vt, n) ): void =
(
case+ xss of
| ~list_vt_nil() => ()
| ~list_vt_cons(xs1, rest) => let
    val () = list_vt_free<sint>(xs1)
  in
    list_vt_dual_arity_free(rest)
  end
)
