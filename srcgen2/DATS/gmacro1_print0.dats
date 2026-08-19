(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2022 Hongwei Xi, ATS Trustful Software, Inc.
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
(* ****** ****** *)
//
(*
Author: Hongwei Xi
(*
Sun 04 Dec 2022 02:09:43 AM EST
*)
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
(* ****** ****** *)
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
(* ****** ****** *)
//
#include
"./../HATS/xatsopt_sats.hats"
#include
"./../HATS/xatsopt_dpre.hats"
//
(* ****** ****** *)
(* ****** ****** *)
#staload "./../SATS/gmacro1.sats"
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
g1mac_fprint
( g1m0, out ) =
let
//
#impltmp
g_print$out<>() = out
//
in//let
case+ g1m0 of
//
|G1Mint(i0) =>
(
 (print("G1Mint("); print(i0); print(")")))
|G1Mbtf(b0) =>
(
 (print("G1Mbtf("); print(b0); print(")")))
|G1Mchr(c0) =>
(
 (print("G1Mchr("); print(c0); print(")")))
|G1Mflt(f0) =>
(
 (print("G1Mflt("); print(f0); print(")")))
|G1Mstr(s0) =>
(
 (print("G1Mstr("); print(s0); print(")")))
//
|G1Mid0(gid) =>
(
 (print("G1Mid0("); print(gid); print(")")))
//
|G1Msexp(g1m) =>
(
 (print("G1Msexp("); print(g1m); print(")")))
|G1Mdpat(g1m) =>
(
 (print("G1Mdpat("); print(g1m); print(")")))
|G1Mdexp(g1m) =>
(
 (print("G1Mdexp("); print(g1m); print(")")))
//
|
G1Mift0
(g1m1,g1m2,g1m3) =>
(print("G1Mift0("); print(g1m1); print(";"); print(g1m2); print(";"); print(g1m3); print(")"))
//
|
G1Mlam0(gids,gmac) =>
(print("G1Mlam0("); print(gids); print(";"); print(gmac); print(")"))
|
G1Mapps(g1f0,g1ms) =>
(print("G1Mapps("); print(g1f0); print(";"); print(g1ms); print(")"))
//
|
G1Mlist(g1ms) =>
(
  (print("G1Mlist("); print(g1ms); print(")")))
//
|
G1Msubs
(g1e1,genv) =>
(print("G1Msubs("); print(g1e1); print(";"); print(genv); print(")"))
//
|
G1Mnone0() => (print("G1Mnone0("); print(")"))
|
G1Mnone1(g1e1) => (print("G1Mnone1("); print(g1e1); print(")"))
//
end (*let*) // end of [ g1mac_fprint( g1m0,out ) ]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XATSOPT_srcgen2_DATS_gmacro1_print0.dats] *)
(***********************************************************************)
