(* dep1.sats — a deliberately BROKEN dependency for the cross-file test *)
#include
"prelude/HATS/prelude_dats.hats"
//
fun dep_id(x0: sint): sint
fun dep_bad(x0: no_such_type_xyz): sint
//
