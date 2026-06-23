(* Regression: a `local val .. in val .. end` INSIDE a function body must keep the
   local-head binding visible to the local-body (ATS `local D1 in D2 end` scoping). The
   Pythonic lowering emits a `private:` head whose binders must reach the rest of the
   suite via D2Ewhere — NOT be dropped (which left `s2td`-style binders unbound). *)

#implfun
local_value_body_scope
( x0: sint ) =
let
local
val y0 = x0 + 1
in
val z0 = y0 + 1
end
in
z0
end
