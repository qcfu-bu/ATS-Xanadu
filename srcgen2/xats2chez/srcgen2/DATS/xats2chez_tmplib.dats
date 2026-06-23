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
xats2chez_tmplib — g_print template instances for the intrep0 IR nodes.
Adapted from xats2go/srcgen2/DATS/xats2go_tmplib.dats, but STRIPPED to the
intrep0 i0-node instances only: this backend emits from intrep0 and never
staloads intrep1, so all the intrep1 / teqi1cmp / i1parsed instances are gone.
These mirror the i0 instances xats2go staloads (proven to typecheck against
the same xats2cc/srcgen1/SATS/intrep0.sats).
*)
(* ****** ****** *)
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
(* ****** ****** *)
(* ****** ****** *)
//
#staload ".\
/../../../xats2cc\
/srcgen1/SATS/intrep0.sats"//...
//
(* ****** ****** *)
(* ****** ****** *)
//
#impltmp
g_print
<i0cal>(ical) =
i0cal_fprint(ical, g_print$out<>())
//
(* ****** ****** *)
//
#impltmp
g_print
<i0var>(ivar) =
i0var_fprint(ivar, g_print$out<>())
//
#impltmp
g_print
<i0exp>(iexp) =
i0exp_fprint(iexp, g_print$out<>())
//
#impltmp
g_print
<i0dcl>(idcl) =
i0dcl_fprint(idcl, g_print$out<>())
//
(* ****** ****** *)
//
#impltmp
g_print<i0valdcl>(ival) =
i0valdcl_fprint(ival, g_print$out<>())
#impltmp
g_print<i0vardcl>(ivar) =
i0vardcl_fprint(ivar, g_print$out<>())
#impltmp
g_print<i0fundcl>(ifun) =
i0fundcl_fprint(ifun, g_print$out<>())
//
(* ****** ****** *)
//
#impltmp
g_print
<teqi0exp>(tdxp) =
let
in//let
(
case+ tdxp of
|
TEQI0EXPnone() =>
prints("TEQI0EXPnone(", ")")
|
TEQI0EXPsome(tok0, i0e1) =>
prints("TEQI0EXPsome(",tok0,";",i0e1,")"))
endlet // end-of-[g_print<teqi0exp>(tdxp)]
//
(* ****** ****** *)
//
#impltmp
g_print
<i0parsed>(ipar) =
let
val () =
i0parsed_fprint(ipar, g_print$out<>())end
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2chez_srcgen2_DATS_xats2chez_tmplib.dats] *)
(***********************************************************************)
