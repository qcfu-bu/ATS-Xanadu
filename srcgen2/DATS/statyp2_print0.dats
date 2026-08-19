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
Fri 04 Nov 2022 06:53:23 PM EDT
*)
Authoremail: gmhwxiATgmailDOTcom
*)
//
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
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
(* ****** ****** *)
#staload
_(*?*) = "./lexing0_print0.dats"
(* ****** ****** *)
#staload "./../SATS/lexing0.sats"
(* ****** ****** *)
#staload "./../SATS/staexp0.sats"
(* ****** ****** *)
#staload "./../SATS/staexp1.sats"
(* ****** ****** *)
#staload "./../SATS/staexp2.sats"
#staload "./../SATS/statyp2.sats"
(* ****** ****** *)
#symload node with s2typ_get_node
#symload sort with s2typ_get_sort
(* ****** ****** *)
//
#implfun
x2t2p_fprint
( xt2p, out ) =
let
val
t2p0 = xt2p.styp()
in//let
case+
t2p0.node() of
|
T2Pnone0() =>
(print("["); print(xt2p.stmp()); print("]"))
| _(*non-T2Pnone0*) =>
(print("["); print(xt2p.styp()); print("]"))
end where
{
  #impltmp g_print$out<>() = out
} (*where*) // end of [x2t2p_fprint(xt2p,out)]
//
(* ****** ****** *)
//
#implfun
s2typ_fprint
( t2p0, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
t2p0.node() of
//
(*
|
T2Pbas(sym1) =>
prints("T2Pbas(", sym1, ")")
*)
//
|
T2Pcst(s2c1) =>
(print("T2Pcst("); print(s2c1); print(")"))
|
T2Pvar(s2v1) =>
(print("T2Pvar("); print(s2v1); print(")"))
//
|
T2Plft(t2p1) =>
(print("T2Plft("); print(t2p1); print(")"))
//
|
T2Pxtv(xtp1) =>
(print("T2Pxtv("); print(xtp1); print(")"))
//
(* ****** ****** *)
|
T2Ptop0(t2p1) =>
(print("T2Ptop0("); print(t2p1); print(")"))
|
T2Ptop1(t2p1) =>
(print("T2Ptop1("); print(t2p1); print(")"))
//
(* ****** ****** *)
//
|
T2Parg1
(knd0, t2p1) =>
(print("T2Parg1("); print(knd0); print(";"); print(t2p1); print(")"))
|
T2Patx2
(tbef, taft) =>
(print("T2Patx2("); print(tbef); print(";"); print(taft); print(")"))
//
(* ****** ****** *)
//
|
T2Papps
(tfun, t2ps) =>
(print("T2Papps("); print(tfun); print(";"); print(t2ps); print(")"))
|
T2Plam1
(s2vs, tres) =>
(print("T2Plam1("); print(s2vs); print(";"); print(tres); print(")"))
//
(* ****** ****** *)
//
|
T2Pf2cl(f2cl) =>
(
  (print("T2Pf2cl("); print(f2cl); print(")")) )
|
T2Pfun1
( f2cl
, npf1, t2ps, tres) =>
let
val
s2t0 = t2p0.sort()
in//let
(*
prints
("T2Pfun1(", f2cl, ";");
*)
(print("T2Pfun1("); print(s2t0); print(";"); print(f2cl); print(";"));
(print(npf1); print(";"); print(t2ps); print(";"); print(tres); print(")"))
end//let//endof[T1Pfun1(f2cl,npf1,...)]
//
|
T2Ptext(name, t2ps) =>
(print("T2Ptext("); print(name); print(";"); print(t2ps); print(")"))
//
|
T2Pexi0(s2vs, t2p1) =>
(print("T2Pexi0("); print(s2vs); print(";"); print(t2p1); print(")"))
|
T2Puni0(s2vs, t2p1) =>
(print("T2Puni0("); print(s2vs); print(";"); print(t2p1); print(")"))
//
|
T2Ptrcd
(knd0, npf1, lses) =>
(print("T2Ptrcd("); print(knd0); print(";"); print(npf1); print(";"); print(lses); print(")"))
//
|
T2Pnone0() => (print("T2Pnone0("); print(")"))
|
T2Pnone1(t2p1) => (print("T2Pnone1("); print(t2p1); print(")"))
|
T2Ps2exp(s2e1) => (print("T2Ps2exp("); print(s2e1); print(")"))
//
|T2Perrck // HX: tread-error
(lvl0,t2p1) => (print("T2Perrck("); print(lvl0); print(";"); print(t2p1); print(")"))
//
end (*let*) // end of [s2typ_fprint(t2p0,out)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XATSOPT_srcgen2_DATS_statyp2_print0.dats] *)
(***********************************************************************)
