(* Regression: finite local type aliases must not shadow later public aliases. *)

#typedef key = bool

fun
local_alias_public_before
(x0: key): key = x0

local
#typedef key = sint
in
fun
local_alias_private_use
(x0: key): key = x0
end

fun
local_alias_public_after
(x0: key): key = x0
