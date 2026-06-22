(* Regression: imported symload aliases must not be duplicated in overload buckets. *)

#staload "./../../../srcgen2/SATS/xstamp0.sats"
#staload "./../../../srcgen2/SATS/xsymbol.sats"

#extern
fun
import_symload_dedup_use
(u0: uint, name0: strn): strn

#implfun
import_symload_dedup_use
(u0, name0) =
let
val st0 = stamp(u0)
val _ = st0.uint()
val sym0 = symbl(name0)
val _ = sym0.stmp()
in
sym0.name()
end
