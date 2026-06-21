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
xats2go — minimal [envx2go] implementation for milestone M0.
Mirrors xats2js/srcgen2/DATS/xats2js_myenv0.dats.
*)
//
(* ****** ****** *)
(* ****** ****** *)
//
#include
"./../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../..\
/HATS/xatsopt_dpre.hats"
(* ****** ****** *)
(* ****** ****** *)
//
#staload ".\
/../../../xats2cc\
/srcgen1/SATS/intrep0.sats"//...
//
#staload "./../SATS/intrep1.sats"
#staload "./../SATS/trxi0i1.sats"
#staload "./../SATS/xats2go.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
(* ****** ****** *)
// local
(* ****** ****** *)
//
datavwtp
envx2go =
ENVX2GO of
( FILR(*output*)
, sint(*level0*)
, sint(*indent*))
//
#absimpl envx2go_vtbx = envx2go
//
(* ****** ****** *)
// in//local
(* ****** ****** *)
//
#implfun
envx2go_filr$get
  ( env0 ) =
let
val+
ENVX2GO
(filr
,lvl0, nind) = env0 in filr end
//
#implfun
envx2go_lvl0$get
  ( env0 ) =
let
val+
ENVX2GO
(filr
,lvl0, nind) = env0 in lvl0 end
//
#implfun
envx2go_nind$get
  ( env0 ) =
let
val+
ENVX2GO
(filr
,lvl0, nind) = env0 in nind end
//
(* ****** ****** *)
//
#implfun
envx2go_make_out
  ( filr ) = ENVX2GO(filr, 0, 0)
//
(* ****** ****** *)
//
#implfun
envx2go_free_nil
  (  env0  ) =
(
case+ env0 of
| ~
ENVX2GO
(filr, lvl0, nind) => ((*void*)))
(*case+*)//end-of-(envx2go_free_nil(env0))
//
(* ****** ****** *)
//
#implfun
envx2go_incnind
(  env0, ninc  ) = let
//
val+
@ENVX2GO
(filr, lvl0, !nind) = env0
//
in//let
//
(
nind := nind + ninc; $fold(env0))
//
end (*let*)//end-of-(envx2go_incnind(env0))
//
#implfun
envx2go_decnind
(  env0, ndec  ) = let
//
val+
@ENVX2GO
(filr, lvl0, !nind) = env0
//
in//let
//
(
nind := nind - ndec; $fold(env0))
//
end (*let*)//end-of-(envx2go_decnind(env0))
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
strnfpr(
filr, strn) =
(
strn_fprint(strn, filr))
//
#implfun
nindfpr(
filr, nind) =
// emit one TAB per indent level so emitted Go is gofmt-clean (Go is
// whitespace-insensitive, so this is cosmetic, but it keeps `gofmt -l`
// quiet and makes review diffs match canonical Go).
if nind > 0 then
(
strn_fprint
("\t", filr); nindfpr(filr, nind-1))
//
#implfun
nindstrnfpr
(filr
,nind, strn) =
(
nindfpr(filr, nind);strnfpr(filr, strn))
//
(* ****** ****** *)
(* ****** ****** *)
// end (*local*) // end of [local(envx2go_vtbx)]
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_xats2go_myenv0.dats] *)
(***********************************************************************)
