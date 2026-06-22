(* Regression: local ATS #vwtpdef aliases must print as scoped Pythonic type aliases. *)

#implfun
local_type_alias_use
( x0: sint ) =
let
#vwtpdef sint_alias = sint
fun go(x1: sint_alias): sint_alias = x1
in
go(x0)
end
