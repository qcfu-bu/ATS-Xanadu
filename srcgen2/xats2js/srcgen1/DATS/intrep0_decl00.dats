(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2024 Hongwei Xi, ATS Trustful Software, Inc.
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
//
Fri 15 Mar 2024 05:16:04 AM EDT
//
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
(*
#define
XATSOPT "./../../.."
*)
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../..\
/HATS/xatsopt_dats.hats"
(* ****** ****** *)
//
#include
"./../HATS/libxats2js.hats"
//
(* ****** ****** *)
//
#staload
"./../../../SATS/staexp2.sats"
#staload
"./../../../SATS/statyp2.sats"
//
(* ****** ****** *)
//
#staload
"./../../../SATS/dynexp3.sats"
//
(* ****** ****** *)
//
#staload "./../SATS/intrep0.sats"
//
(* ****** ****** *)
//
#staload
_(*DATS*)="./../DATS/intrep0.dats"
//
(* ****** ****** *)
(* ****** ****** *)
#symload lctn with d3ecl_get_lctn
#symload node with d3ecl_get_node
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
trxd3i0_d3ecl
(env0 , d3cl) =
(
case+
d3cl.node() of
//
|D3Clocal0 _ =>
(
  f0_local0(env0, d3cl))
//
|_(* otherwise *) => i0dcl_none1(d3cl)
//
) where
{
//
val
loc0 = d3cl.lctn()
//
(* ****** ****** *)
//
fun
f0_local0
( env0: 
! trdienv
, d3cl: d3ecl): i0dcl =
let
//
val-
D3Clocal0
(head, body) = d3cl.node()
//
val
head =
trxd3i0_d3eclist(env0, head)
val
body =
trxd3i0_d3eclist(env0, body)
//
in//let
//
i0dcl(loc0, I0Dlocal0(head, body))
//
end//let//end-of-[f0_local0(env0,d3cl)]
//
(* ****** ****** *)
//
val () =
(
  prerrln("trxd3i0_d3ecl: d3cl = ", d3cl) )
//
(* ****** ****** *)
//
} (*where*) // end of [trxd3i0_d3ecl(env0,...)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
trxd3i0_d3eclist
( env0, dcls ) =
(
  list_trxd3i0_fnp(env0, dcls, trxd3i0_d3ecl))
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xinterp_srcgen1_DATS_intrep0_decl00.dats] *)
(***********************************************************************)