(* ****** ****** *)
#staload UN =
"prelude/SATS/unsafex.sats"
(* ****** ****** *)
//
#include
"prelude/HATS/prelude_dats.hats"
//
(* ****** ****** *)
//
fun
fact(n: int): int =
glseq_mul0(strm_vt_range_lte(1, n))
//
(* ****** ****** *)

(* end of [DATA/trans34_001.dats] *)
