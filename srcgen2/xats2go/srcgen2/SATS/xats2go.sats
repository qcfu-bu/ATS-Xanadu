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
(* ****** ****** *)
//
(*
xats2go — Go backend for ATS3.
Minimal driver/env interface for milestone M0.
Mirrors xats2js/srcgen2/SATS/xats2js.sats but trimmed to the
[envx2go] vtype + getters + make/free + indent helpers that the
M0 [go1emit] stub needs. (No IR-traversal entrypoints yet.)
*)
//
(* ****** ****** *)
(* ****** ****** *)
//
#include
"./../../..\
/HATS/xatsopt_sats.hats"
//
(* ****** ****** *)
//
#staload "./intrep1.sats"
//
#staload
".\
/../../xats2cc\
/srcgen1/SATS/intrep0.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#absvwtp envx2go_vtbx // p0tr
#vwtpdef envx2go = envx2go_vtbx
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
envx2go_filr$get
(env0: !envx2go): FILEref
//
fun
envx2go_lvl0$get
(env0: !envx2go): ( sint )
//
fun
envx2go_nind$get
(env0: !envx2go): ( sint )
//
(* ****** ****** *)
//
fun
envx2go_make_out
(  out0: FILR  ): envx2go
fun
envx2go_free_nil
(  env0: ~envx2go  ): void
//
(* ****** ****** *)
//
fun
envx2go_incnind
( env0:
! envx2go, ninc: sint): void
fun
envx2go_decnind
( env0:
! envx2go, ndec: sint): void
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
nindfpr
(filr: FILR, nind: sint): void
//
fun
strnfpr
(filr: FILR, strn: strn): void
//
fun
chrfpr
(filr: FILR, c0: char): void
//
fun
nindstrnfpr
(filr: FILR
,nind: sint, strn: strn): void
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_SATS_xats2go.sats] *)
(***********************************************************************)
