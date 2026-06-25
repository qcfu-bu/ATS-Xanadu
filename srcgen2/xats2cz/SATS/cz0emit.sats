(***********************************************************************)
(*                         Applied Type System                         *)
(***********************************************************************)
(*
xats2cz / cz0emit — the intrep0 -> Chez Scheme emitter (interface).

This backend emits Scheme DIRECTLY from the expression-shaped intrep0 (no
intrep1/ANF).  intrep0 is produced by the COMPLETE xats2js backend's trxd3i0
(NOT the incomplete xats2cc).  Template instances are emitted INLINE as nested
closures at each use site (no hoist/lift/seed); see srcgen2/xats2cz/docs/.

NOTE (stamp discipline): the JS transpiler numbers SATS functions by position;
adding a [fun] here shifts all later stamps, forcing a clean re-transpile.
Declare NEW helpers at the END.
*)
(* ****** ****** *)
#include
"./../../HATS/xatsopt_sats.hats"
(* ****** ****** *)
#staload
"./../../xats2js/srcgen1/SATS/intrep0.sats"
(* ****** ****** *)
(*
i0parsed_cz0emit: emit a whole compilation unit (the trxd3i0 output) as Chez
Scheme to [filr], wrapped between the ;;==XATS2CZ-BEGIN==/;;==XATS2CZ-END==
sentinels (the build harness extracts the body between them).
*)
fun
i0parsed_cz0emit
(ipar: i0parsed, filr: FILR): void
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2cz_SATS_cz0emit.sats] *)
(***********************************************************************)
