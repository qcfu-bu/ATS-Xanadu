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
Sun Jul 24 18:07:52 EDT 2022
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
#staload
_(*?*) = "./lexing0_print0.dats"
(* ****** ****** *)
#staload "./../SATS/lexing0.sats"
(* ****** ****** *)
#staload "./../SATS/staexp0.sats"
(* ****** ****** *)
#staload "./../SATS/staexp1.sats"
(* ****** ****** *)
(* ****** ****** *)
#symload lctn with g1arg_get_lctn
#symload node with g1arg_get_node
(* ****** ****** *)
#symload lctn with g1mag_get_lctn
#symload node with g1mag_get_node
(* ****** ****** *)
#symload lctn with g1exp_get_lctn
#symload node with g1exp_get_node
(* ****** ****** *)
#symload lctn with sort1_get_lctn
#symload node with sort1_get_node
(* ****** ****** *)
#symload lctn with s1exp_get_lctn
#symload node with s1exp_get_node
(* ****** ****** *)
#symload lctn with s1tcn_get_lctn
#symload node with s1tcn_get_node
(* ****** ****** *)
#symload lctn with d1tst_get_lctn
#symload node with d1tst_get_node
(* ****** ****** *)
#symload lctn with s1tdf_get_lctn
#symload node with s1tdf_get_node
(* ****** ****** *)
#symload lctn with s1arg_get_lctn
#symload node with s1arg_get_node
#symload lctn with t1arg_get_lctn
#symload node with t1arg_get_node
(* ****** ****** *)
#symload lctn with s1mag_get_lctn
#symload node with s1mag_get_node
#symload lctn with t1mag_get_lctn
#symload node with t1mag_get_node
(* ****** ****** *)
#symload lctn with s1qua_get_lctn
#symload node with s1qua_get_node
(* ****** ****** *)
#symload lctn with s1uni_get_lctn
#symload node with s1uni_get_node
#symload lctn with d1tcn_get_lctn
#symload node with d1tcn_get_node
#symload lctn with d1typ_get_lctn
#symload node with d1typ_get_node
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
g1arg_fprint
( g1a, out ) =
(
case+
g1a.node() of
G1ARGnode(tok) =>
(print("G1ARGnode("); print(tok); print(")"))
) where
{
  #impltmp g_print$out<>() = out
} (*where*) // end of [g1arg_fprint]
//
(* ****** ****** *)
//
#implfun
s1qid_fprint
( qid, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+ qid of
|
S1QIDnone(id1) =>
(print("S1QIDnone("); print(id1); print(")"))
|
S1QIDsome(tok, id1) =>
(print("S1QIDsome("); print(tok); print(";"); print(id1); print(")"))
end (*let*) // end of [s1qid_fprint]
//
#implfun
d1qid_fprint
( qid, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+ qid of
|
D1QIDnone(id1) =>
(print("D1QIDnone("); print(id1); print(")"))
|
D1QIDsome(tok, id1) =>
(print("D1QIDsome("); print(tok); print(";"); print(id1); print(")"))
end (*let*) // end of [d1qid_fprint]
//
(* ****** ****** *)
//
#implfun
g1mag_fprint
( gma, out ) =
(
case+
gma.node() of
|
G1MAGsarg(g1as) =>
(print("G1MAGsarg("); print(g1as); print(")"))
|
G1MAGdarg(g1as) =>
(print("G1MAGdarg("); print(g1as); print(")"))
) where
{
  #impltmp g_print$out<>() = out
} (*where*) // end of [g1mag_fprint]
//
(* ****** ****** *)
//
#implfun
g1nam_fprint
( g1n, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+ g1n of
//
| G1Nnil() =>
  (print("G1Nnil("); print(")"))
//
| G1Nid0(id0) =>
  (print("G1Nid0("); print(id0); print(")"))
//
| G1Nint(int) =>
  (print("G1Nint("); print(int); print(")"))
| G1Nchr(chr) =>
  (print("G1Nchr("); print(chr); print(")"))
| G1Nflt(flt) =>
  (print("G1Nflt("); print(flt); print(")"))
| G1Nstr(str) =>
  (print("G1Nstr("); print(str); print(")"))
//
| G1Nlist(g1ns) =>
  (print("G1Nlist("); print(g1ns); print(")"))
//
(*
| G1Nnone0() =>
  prints("G1Nnone0(",")")
*)
| G1Nnone1(g1n1) =>
  (print("G1Nnone1("); print(g1n1); print(")"))
//
end (*let*) // end of [g1nam_fprint(g1n,out)]
//
(* ****** ****** *)
//
#implfun
g1exp_fprint
( g1e, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
g1e.node() of
//
|G1Eint(tok) =>
(print("G1Eint("); print(tok); print(")"))
(*
|G1Ebtf(tok) =>
prints("G1Ebtf(",tok,")")
*)
|G1Echr(tok) =>
(print("G1Echr("); print(tok); print(")"))
|G1Eflt(tok) =>
(print("G1Eflt("); print(tok); print(")"))
|G1Estr(tok) =>
(print("G1Estr("); print(tok); print(")"))
//
|G1Eid0(id0) =>
(print("G1Eid0("); print(id0); print(")"))
//
|
G1Eb0sh(   ) =>
(print("G1Eb0sh("); print(")"))
|
G1Eb1sh(g1e) =>
(print("G1Eb1sh("); print(g1e); print(")"))
//
|
G1Ea0pp(   ) =>
(print("G1Ea0pp("); print(")"))
|
G1Ea1pp
(g1f0, g1e1) =>
(print("G1Ea1pp("); print(g1f0); print(";"); print(g1e1); print(")"))
|
G1Ea2pp
(g1f0, g1e1, g1e2) =>
(print("G1Ea2pp("); print(g1f0); print(";"); print(g1e1); print(";"); print(g1e2); print(")"))
//
|
G1Elist(g1es) =>
(print("G1Elist("); print(g1es); print(")"))
//
|
G1Eift0
(g1e1, g1e2, g1e3) =>
(print("G1Eift0("); print(g1e1); print(";"); print(g1e2); print(";"); print(g1e3); print(")"))
//
|
G1Enone0() => (print("G1Enone0("); print(")"))
|
G1Enone1(g0e1) => (print("G1Enone1("); print(g0e1); print(")"))
//
|
G1Eerrck
(lvl(*err*),g1e1) => (print("G1Eerrck("); print(lvl); print(";"); print(g1e1); print(")"))
//
end (*let*) // end of [g1exp_fprint(g1e,out)]
//
(* ****** ****** *)
//
#implfun
sort1_fprint
( s1t, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
s1t.node() of
|
S1Tid0(id0) =>
(print("S1Tid0("); print(id0); print(")"))
//
|
S1Tint(int) =>
(print("S1Tint("); print(int); print(")"))
//
// HX-2018-08: operators
//
|
S1Ta0pp(   ) =>
(
  (print("S1Ta0pp("); print(")"))
)
//
(*
| S1Ttype of int(*kind*)
  (*prop/view/type/tbox/vwtp/vtbx*)
*)
//
|
S1Ta1pp
(s1f0, s1t1) =>
(print("S1Ta1pp("); print(s1f0); print(";"); print(s1t1); print(")"))
|
S1Ta2pp
( s1f0
, s1t1, s1t2) =>
(print("S1Ta2pp("); print(s1f0); print(";"); print(s1t1); print(";"); print(s1t2); print(")"))
|
S1Tlist(s1ts) =>
(print("S1Tlist("); print(s1ts); print(")"))
//
|
S1Tqual0(tok1,s1t2) =>
(print("S1Tqual0("); print(tok1); print(";"); print(s1t2); print(")"))
//
|
S1Tnone0() => (print("S1Tnone0("); print(")"))
|
S1Tnone1(s0t1) => (print("S1Tnone1("); print(s0t1); print(")"))
//
|
S1Terrck
(lvl(*err*),s1t1) => (print("S1Terrck("); print(lvl); print(";"); print(s1t1); print(")"))
//
end (*let*) // end of [sort1_fprint(s1t,out)]
//
(* ****** ****** *)
//
#implfun
s1tcn_fprint
( tcn, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
tcn.node() of
|
S1TCNnode(id0, stq) =>
(print("S1TCNnode("); print(id0); print(";"); print(stq); print(")"))
end (*let*) // end of [s1tcn_fprint]
//
(* ****** ****** *)
//
#implfun
d1tst_fprint
( dst, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
dst.node() of
|
D1TSTnode(tid0,stcs) =>
(
(print("D1TSTnode("); print(tid0); print(";"); print(stcs); print(")")))
end (*let*) // end of [d1tst_fprint(...)]
(* ****** ****** *)
//
#implfun
s1arg_fprint
( s1a, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
s1a.node() of
|
S1ARGsome(sid0, tres) =>
(print("S1ARGsome("); print(sid0); print(";"); print(tres); print(")"))
//
end (*let*) // end of [s1arg_fprint(...)]
//
(* ****** ****** *)
//
#implfun
s1mag_fprint
( s1m, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
s1m.node() of
|
S1MAGlist(s1as) =>
(print("S1MAGlist("); print(s1as); print(")"))
//
end (*let*)//end of [s1mag_fprint(s1m,out)]
//
(* ****** ****** *)
//
#implfun
t1arg_fprint
( t1a, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
t1a.node() of
|
T1ARGsome(s1t1, topt) =>
(print("T1ARGsome("); print(s1t1); print(";"); print(topt); print(")"))
//
end (*let*) // end of [t1arg_fprint(...)]
//
(* ****** ****** *)
//
#implfun
t1mag_fprint
( t1m, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
t1m.node() of
|
T1MAGlist(t1as) =>
(print("T1MAGlist("); print(t1as); print(")"))
//
end (*let*)//end of [t1mag_fprint(t1m,out)]
//
(* ****** ****** *)
//
#implfun
s1qua_fprint
( s1q, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+
s1q.node() of
|
S1QUAprop
(  s1e  ) =>
(print("S1QUAprop("); print(s1e); print(")"))
|
S1QUAvars
(toks, topt) =>
(print("S1QUAvars("); print(toks); print(";"); print(topt); print(")"))
end (*let*) // end-of-[s1qua_fprint(err,out)]
//
(* ****** ****** *)
//
#implfun
s1exp_fprint
( s1e, out ) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
s1e.node() of
//
|
S1Eid0(id0) =>
(print("S1Eid0("); print(id0); print(")"))
//
|
S1Eint(int) =>
(print("S1Eint("); print(int); print(")"))
|
S1Echr(chr) =>
(print("S1Echr("); print(chr); print(")"))
|
S1Eflt(flt) =>
(print("S1Eflt("); print(flt); print(")"))
|
S1Estr(str) =>
(print("S1Estr("); print(str); print(")"))
//
|
S1Eb0sh(   ) =>
(print("S1Eb0sh("); print(")"))
|
S1Eb1sh(s1e) =>
(print("S1Eb1sh("); print(s1e); print(")"))
//
|
S1Earrw(ses) =>
(print("S1Earrw("); print(ses); print(")"))
//
|
S1Ea0pp(   ) =>
(print("S1Ea0pp("); print(")"))
|
S1Ea1pp
(s1f0, s1e1) =>
(print("S1Ea1pp("); print(s1f0); print(";"); print(s1e1); print(")"))
|
S1Ea2pp
(s1f0, s1e1, s1e2) =>
(print("S1Ea2pp("); print(s1f0); print(";"); print(s1e1); print(";"); print(s1e2); print(")"))
|
S1El1st(s1es) =>
(print("S1El1st("); print(s1es); print(")"))
|
S1El2st(ses1, ses2) =>
(print("S1El2st("); print(ses1); print(";"); print(ses2); print(")"))
//
|
S1Et1up(tknd, s1es) =>
(print("S1Et1up("); print(tknd); print(";"); print(s1es); print(")"))
|
S1Et2up(tknd,ses1,ses2) =>
(print("S1Et2up("); print(tknd); print(";"); print(ses1); print(";"); print(ses2); print(")"))
//
|
S1Er1cd(tknd, lses) =>
(print("S1Er1cd("); print(tknd); print(";"); print(lses); print(")"))
|
S1Er2cd(tknd,lss1,lss2) =>
(print("S1Er2cd("); print(tknd); print(";"); print(lss1); print(";"); print(lss2); print(")"))
//
|
S1Elams(smas,tres,s1e1) =>
(print("S1Elams("); print(smas); print(";"); print(tres); print(";"); print(s1e1); print(")"))
//
|
S1Euni0(s1qs) =>
(print("S1Euni0("); print(s1qs); print(")"))
|
S1Eexi0(tknd, s1qs) =>
(print("S1Eexi0("); print(tknd); print(";"); print(s1qs); print(")"))
//
|
S1Eannot(s1e1,s1t2) =>
(
(print("S1Eannot("); print(s1e1); print(";"); print(s1t2); print(")"))
)
|
S1Equal0(tok1,s1e2) =>
(
(print("S1Equal0("); print(tok1); print(";"); print(s1e2); print(")"))
)
//
|
S1Enone0() => (print("S1Enone0("); print(")"))
|
S1Enone1(s0e1) => (print("S1Enone1("); print(s0e1); print(")"))
//
|
S1Eerrck
(lvl(*err*),s1e1) => (print("S1Eerrck("); print(lvl); print(";"); print(s1e1); print(")"))
//
end (*let*) // end of [s1exp_fprint(s1e,out)]
//
(* ****** ****** *)
//
#implfun
s1uni_fprint
( s1u, out ) =
let
#impltmp
g_print$out<>() = out
in//let
case+
s1u.node() of
|
S1UNIsome(s1qs) =>
(print("S1UNIsome("); print(s1qs); print(")"))
end (*let*) // end-of-[s1uni_fprint(err,out)]
//
(* ****** ****** *)
//
#implfun
s1tdf_fprint
(stdf, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
stdf.node() of
|
S1TDFsort(s1t1) =>
(
  (print("S1TDFsort("); print(s1t1); print(")"))
)
|
S1TDFtsub(s1a1,s1es) =>
(
  (print("S1TDFtsub("); print(s1a1); print(";"); print(s1es); print(")"))
)
//
end (*let*) // end of [s1tdf_fprint(stdf,out)]
//
(* ****** ****** *)
//
#implfun
d1tcn_fprint
(dtcn, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
dtcn.node() of
|
D1TCNnode
(s1us
,deid,s1es,sres) =>
(
print("D1TCNnode(");
(print(s1us); print(";"); print(deid); print(";"); print(s1es); print(";"); print(sres); print(")")))
//
end (*let*) // end of [d1tcn_fprint(dtcn,out)]
//
(* ****** ****** *)
//
#implfun
d1typ_fprint
(dtyp, out0) =
let
#impltmp
g_print$out<>() = out0
in//let
//
case+
dtyp.node() of
|
D1TYPnode
(deid
,tmas,tres,tcns) =>
(
print("D1TYPnode(");
(print(deid); print(";"); print(tmas); print(";"); print(tres); print(";"); print(tcns); print(")")))
//
end (*let*) // end of [d1typ_fprint(dtyp,out)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XATSOPT_srcgen2_DATS_staexp1_print0.dats] *)
(***********************************************************************)
