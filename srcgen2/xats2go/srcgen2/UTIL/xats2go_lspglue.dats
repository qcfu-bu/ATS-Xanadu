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
xats2go_lspglue — see the .sats header.  Runs the shared check core
(xats2go_tchecklib) inside the runtime's capture window and deposits
the two result texts in the runtime stash.
*)
(* ****** ****** *)
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../..\
/HATS/xatsopt_dpre.hats"
(* ****** ****** *)
(* ****** ****** *)
#include
"./../HATS/libxatsopt.hats"
(* ****** ****** *)
#include
"./../HATS/mytmplib00.hats"
(* ****** ****** *)
(* ****** ****** *)
//
#staload "./xats2go_tchecklib.sats"
#staload "./xats2go_lspglue.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
the runtime capture/stash leaves (runtime/xatsgo/xatsgo.go): the
capture window collects every stderr-destined byte of the check (the
report-channel prints included); the buffer-FILR collects the index
records; the stash carries both strings across the prelude fence to
the server floor.
*)
#extern
fun
XATS2GO_capture_begin((*void*)): void = $extnam()
#extern
fun
XATS2GO_capture_end((*void*)): strn = $extnam()
#extern
fun
XATS2GO_buffilr_make((*void*)): FILR = $extnam()
#extern
fun
XATS2GO_buffilr_take(b0: FILR): strn = $extnam()
#extern
fun
XATS2GO_lsp_stash_rep(s0: strn): void = $extnam()
#extern
fun
XATS2GO_lsp_stash_idx(s0: strn): void = $extnam()
//
(* ****** ****** *)
//
#implfun
tchkglue_prelude_load
  ((*void*)) = tchk_prelude_load((*void*))
//
(* ****** ****** *)
//
#implfun
tchkglue_prelude_reload
  ((*void*)) =
let
val ( ) = xglobal_reset((*void*))
in//let
tchk_prelude_load((*void*))
end//endof[tchkglue_prelude_reload]
//
(* ****** ****** *)
//
#implfun
tchkglue_check
(fpth, txt, stdinq) =
let
//
val idxout = XATS2GO_buffilr_make()
val ( ) = XATS2GO_capture_begin()
val ( ) =
tchk_check
(fpth, txt, stdinq, 1(*idxq*), g_stderr((*0*)), idxout)
val ( ) =
XATS2GO_lsp_stash_rep(XATS2GO_capture_end())
val ( ) =
XATS2GO_lsp_stash_idx(XATS2GO_buffilr_take(idxout))
//
in//let
((*void*))
end//endof[tchkglue_check]
//
(* ****** ****** *)
(* ****** ****** *)

(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_UTIL_xats2go_lspglue.dats] *)
(***********************************************************************)
