(* Regression: local #impltmp instantiations must type their implementation parameter. *)

#staload "./../../../srcgen2/SATS/staexp2.sats"

#symload name with s2cst_get_name
#symload lctn with s2cst_get_lctn

#extern
fun
local_impltmp_inst_fnp
( s2cs: list(s2cst) ): void

#implfun
local_impltmp_inst_fnp
  ( s2cs ) =
(
prints("S2Ecsts(", s2cs, ")")
) where
{
#impltmp
g_print<s2cst>(x) =
prints(x.name(), "(", x.lctn(), ")")
}
