(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2026 Hongwei Xi, ATS Trustful Software, Inc.
** All rights reserved
*)

(* ****** ****** *)
(*
chez0emit — the intrep0 -> Chez Scheme emitter interface.
//
This backend emits Scheme DIRECTLY from intrep0 (the expression-shaped IR),
skipping intrep1/trxi0i1: Chez has native proper tail calls and native
lexical closures, so the imperative ANF lowering is unnecessary.
//
NOTE (stamp discipline): the JS transpiler numbers SATS functions by
position; adding a [fun] here shifts all later stamps.  ALWAYS declare new
helpers at the END of this file, and force a clean re-transpile of all
CHEZ_DATS + the driver after editing it.
*)
(* ****** ****** *)
(* ****** ****** *)
//
#include
"./../../..\
/HATS/xatsopt_sats.hats"
//
(* ****** ****** *)
//
#staload ".\
/../../../xats2cc\
/srcgen1/SATS/intrep0.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
i0parsed_chez0emit: emit a whole compilation unit (the tryd3i0 output) as
Chez Scheme text to [filr], bracketed by the
  ;;==XATS2CHEZ-BEGIN== / ;;==XATS2CHEZ-END==
sentinels (the build harness extracts between them).
*)
fun
i0parsed_chez0emit
(ipar: i0parsed, filr: FILR): void
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_SATS_chez0emit.sats] *)
(***********************************************************************)
