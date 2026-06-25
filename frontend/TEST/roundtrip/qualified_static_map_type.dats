(* Regression: ATS $MAP.topmap should pretty-print as Pythonic MAP.topmap
   and lower through qualified static lookup. *)

#staload "./../../../srcgen2/SATS/dynexp2.sats"

#extern
fun
qualified_static_map_wrap
(fenv: f2env): void

local
datatype qmap =
| QMAP of ($MAP.topmap(g1mac))
in

#implfun
qualified_static_map_wrap(fenv) =
let
val _ = QMAP(f2env_get_g1macenv(fenv))
in
()
end

end
