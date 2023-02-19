(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2023 Hongwei Xi, ATS Trustful Software, Inc.
** All rights reserved
**
** ATS is free software;  you can  redistribute it and/or modify it under
** the terms of  the GNU GENERAL PUBLIC LICENSE (GPL) as published by the
** Free Software Foundation; either version 3, or (at  your  option)  any
** later version.
** 
** ATS is distributed in the hope that it will be useful, but WITHOUT ANY
** WARRANTY; without  even  the  implied  warranty  of MERCHANTABILITY or
** FITNESS FOR A PARTICULAR PURPOSE.  See the  GNU General Public License
** for more details.
** 
** You  should  have  received  a  copy of the GNU General Public License
** along  with  ATS;  see the  file COPYING.  If not, please write to the
** Free Software Foundation,  51 Franklin Street, Fifth Floor, Boston, MA
** 02110-1301, USA.
*)

(* ****** ****** *)
//
(*
Author: Hongwei Xi
(*
Tue 14 Feb 2023 12:03:53 PM EST
*)
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
#include
"./../HATS/xatsopt_sats.hats"
(* ****** ****** *)
#define
ATS_PACKNAME // namespace
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
#absvtbx
tr23env_vtbx
#vwtpdef
tr23env = tr23env_vtbx
(* ****** ****** *)
//
#staload
SYM = "./xsymbol.sats"
#staload
MAP = "./xsymmap.sats"
//
(* ****** ****** *)
#typedef sym_t = $SYM.sym_t
(* ****** ****** *)
//
#staload
LAB = "./xlabel0.sats"
#staload
LOC = "./locinfo.sats"
#staload
LEX = "./lexing0.sats"
//
#typedef lab_t = $LAB.lab_t
#typedef label = $LAB.label
//
#typedef loc_t = $LOC.loc_t
//
#typedef token = $LEX.token
//
(* ****** ****** *)
#staload S2E = "./staexp2.sats"
#staload D2E = "./dynexp2.sats"
(* ****** ****** *)
#staload D3E = "./dynexp3.sats"
(* ****** ****** *)
#typedef s2exp = $S2E.s2exp
#typedef s2typ = $S2E.s2typ
(* ****** ****** *)
#typedef d2pat = $D2E.d2pat
#typedef l2d2p = $D2E.l2d2p
#typedef d2exp = $D2E.d2exp
#typedef l2d2e = $D2E.l2d2e
(* ****** ****** *)
#typedef d2ecl = $D2E.d2ecl
(* ****** ****** *)
#typedef d3pat = $D3E.d3pat
#typedef l3d3p = $D3E.l3d3p
#typedef d3exp = $D3E.d3exp
#typedef l3d3e = $D3E.l3d3e
(* ****** ****** *)
#typedef d3ecl = $D3E.d3ecl
(* ****** ****** *)
//
#typedef s2explst = $S2E.s2explst
#typedef s2typlst = $S2E.s2typlst
//
(* ****** ****** *)
//
#typedef d2patlst = $D2E.d2patlst
#typedef d2explst = $D2E.d2explst
#typedef l2d2plst = $D2E.l2d2plst
#typedef l2d2elst = $D2E.l2d2elst
//
(* ****** ****** *)
//
#typedef d3patlst = $D3E.d3patlst
#typedef d3explst = $D3E.d3explst
#typedef l3d3plst = $D3E.l3d3plst
#typedef l3d3elst = $D3E.l3d3elst
//
(* ****** ****** *)
//
fun
<x0:t0>
<y0:t0>
list_trans23_fnp
( e1:
! tr23env
, xs: list(x0)
, (!tr23env, x0) -> y0): list(y0)
fun
<x0:t0>
<y0:t0>
optn_trans23_fnp
( e1:
! tr23env
, xs: optn(x0)
, (!tr23env, x0) -> y0): optn(y0)
//
(* ****** ****** *)
//
fun
trans23_d2pat
(env0: !tr23env, d2p0: d2exp): d3pat
fun
trans23_l2d2p
(env0: !tr23env, ld2p: l2d2p): l3d3p
//
(* ****** ****** *)
//
fun
trans23_d2exp
(env0: !tr23env, d2e0: d2exp): d3exp
fun
trans23_l2d2e
(env0: !tr23env, ld2e: l2d2e): l3d3e
//
(* ****** ****** *)
//
fun
trans23_d2ecl
(env0: !tr23env, d3cl: d2ecl): d3ecl
//
(* ****** ****** *)
//
fun
trans23_d2eclist
(env0: !tr23env, dcls: d2eclist): d3eclist
//
(* ****** ****** *)

(* end of [ATS3/XATSOPT_srcgen2_trans23.sats] *)
