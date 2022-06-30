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
//
(*
Author: Hongwei Xi
Start Time: June 19th, 2022
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
#include
"./../HATS/xatsopt_sats.hats"
#include
"./../HATS/xatsopt_dats.hats"
(* ****** ****** *)
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
#staload "./lexing0_print0.dats"
(* ****** ****** *)
#staload "./../SATS/lexing0.sats"
(* ****** ****** *)
#staload "./../SATS/staexp0.sats"
#staload "./../SATS/dynexp0.sats"
(* ****** ****** *)
#symload node with d0exp_get_node
#symload node with d0pat_get_node
#symload node with d0ecl_get_node
(* ****** ****** *)

#implfun
d0pat_fprint
(out, d0p) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
d0p.node() of
//
|
D0Pid0(id0) =>
print("D0Pid0(",id0,")")
//
|
D0Pint(int) =>
print("D0Pint(",int,")")
|
D0Pchr(chr) =>
print("D0Pchr(",chr,")")
|
D0Pflt(flt) =>
print("D0Pflt(",flt,")")
|
D0Pstr(str) =>
print("D0Pstr(",str,")")
//
|
D0Papps(d0ps) =>
print("D0Papps(", d0ps, ")")
//
|
D0Ptkerr(tok) => print("D0Ptkerr(",tok,")")
//
end (*let*) // end of [d0pat_fprint(out,d0p)]

(* ****** ****** *)

#implfun
d0exp_fprint
(out, d0e) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
d0e.node() of
//
|
D0Eid0(id0) =>
print("D0Eid0(",id0,")")
//
|
D0Eint(int) =>
print("D0Eint(",int,")")
|
D0Echr(chr) =>
print("D0Echr(",chr,")")
|
D0Eflt(flt) =>
print("D0Eflt(",flt,")")
|
D0Estr(str) =>
print("D0Estr(",str,")")
//
|
D0Eapps(d0es) =>
print("D0Eapps(", d0es, ")")
//
|
D0Etkerr(tok) => print("D0Etkerr(",tok,")")
//
|
D0Eerrck(lvl(*err-level*),d0e) => print("D0Eerrck(",lvl,";",d0e,")")
//
end (*let*) // end of [d0exp_fprint(out,d0e)]

(* ****** ****** *)

#implfun
d0ecl_fprint
(out, dcl) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
dcl.node() of
//
|
D0Ctkerr(tok) =>
print("D0Ctkerr(",tok,")")
|
D0Ctkskp(tok) =>
print("D0Ctkskp(",tok,")")
//
|
D0Cextern
(tknd,dcl1) =>
print
("D0Cextern(",tknd,";",dcl1,")")
|
D0Cstatic
(tknd,dcl1) =>
print
("D0Cstatic(",tknd,";",dcl1,")")
//
|
D0Cnonfix
(tknd,dnts) =>
print
("D0Cnonfix(",tknd,";",dnts,")")
|
D0Cfixity
(tknd,dnts,prec) =>
print
("D0Cfixity(",tknd,";",dnts,";",prec,")")
//
|
D0Clocal
(tknd,head,tin1,body,tend) =>
(
print("D0Clocal(",tknd,";");
print(head,";",tin1,";");print(body,";",tend,")"))
//
|
D0Cabssort
(tknd,tid0) =>
print
("D0Cabssort(",tknd,";",tid0,")")
|
D0Cstacst0
(tknd
,seid,tmas,tcln,s0t0) =>
(
print("D0Cstacst0(",tknd,";");
print(seid,";",tmas,";");print(tcln,";",s0t0,")"))
|
D0Csortdef
(tknd,tid0,teq1,def2) =>
(
print("D0Csortdef(",tknd,";");
print(tid0,";",teq1,";",def2,")"))
//
|
D0Csexpdef
(tknd,sid0,smas,tres,teq1,def2) =>
(
print("D0Csexpdef(",tknd,";");
print(sid0,";",smas,";",tres,";");print(teq1,";",def2,")"))
//
|
D0Cabstype
(tknd,sid0,tmas,tres,def2) =>
(
print("D0Cabstype(",tknd,";");
print
(sid0,";",tmas,";",tres,";",def2,")"))
|
D0Cabsopen(tknd, sqid) =>
print("D0Cabsopen(",tknd,";",sqid,")")
|
D0Cabsimpl
(tknd,sid0,smas,tres,teq1,def2) =>
(
print("D0Cabsimpl(",tknd,";");
print(sid0,";",smas,";",tres,";");print(teq1,";",def2,")"))
//
|
D0Cinclude(tknd,g0e1) =>
print("D0Cinclude(",tknd,";",g0e1,")")
|
D0Cstaload(tknd,g0e1) =>
print("D0Cstaload(",tknd,";",g0e1,")")
//
|
D0Csymload
(tknd,symb,twth,dqid,prec) =>
(
print("D0Csymload(",tknd,";");
print
(symb,";",twth,";",dqid,";",prec,")"))
//
|
D0Cdatasort(tknd,dtcs) =>
print("D0Cdatasort(",tknd,";",dtcs,")")
|
D0Cdatatype(tknd,dtps,wdcs) =>
print("D0Cdatatype(",tknd,";",dtps,";",wdcs,")")
//
|
D0Cerrck(lvl(*err-level*),dcl) => print("D0Cerrck(",lvl,";",dcl,")")
//
end (*let*) // end of [d0ecl_fprint(out,dcl)]

(* ****** ****** *)

#implfun
a0tdf_fprint
(out, tdf) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+ tdf of
|
A0TDFsome() =>
print("A0TDFsome(", ")")
|
A0TDFlteq(tok,s0e) =>
print("A0TDFlteq(",tok,";",s0e,")")
|
A0TDFeqeq(tok,s0e) =>
print("A0TDFeqeq(",tok,";",s0e,")")
//
end (*let*) // end of [a0tdf_fprint(out,tdf)]

(* ****** ****** *)
//
#implfun
precopt_fprint
  (out, opt) =
(
case+ opt of
|
PRECnil0() =>
print("PRECnil0()")
|
PRECint1(int) =>
print("PRECint1(", int, ")")
|
PRECopr2(opr, pmd) =>
print("PRECopr2(", opr, ";", pmd, ")")
) where
{
  #impltmp g_print$out<>() = out
} (*where*) // end of [precopt_fprint]
//
#implfun
precint_fprint
  (out, int) =
(
case+ int of
|
PINTint1(int) =>
print("PINTint1(", int, ")")
|
PINTopr2(opr, int) =>
print("PINTopr2(", opr, ";", int, ")")
) where
{
  #impltmp g_print$out<>() = out
} (*where*) // end of [precint_fprint]
//
#implfun
precmod_fprint
  (out, pmd) =
let
#impltmp g_print$out<>() = out
in
case+ pmd of
|
PMODnone() => print("PRECMODnone(", ")")
|
PMODsome(tkb, int, tke) =>
print
("PMODsome(", tkb, ";", int, ";", tke, ")")
end (*let*) // end of [precmod_fprint]
//
(* ****** ****** *)
//
#implfun
wd0eclseq_fprint
  (out, wdcs) =
(
case+ wdcs of
|
WD0CSnone() =>
print("WD0CSnone(", ")")
|
WD0CSsome(tbeg, topt, dcls, tend) =>
(
print
("WD0CSsome(",tbeg,";",topt,";",dcls,";",tend,")"))
) (*case*) // end of [ wd0eclseq_fprint(out,wdcs) ]
//
(* ****** ****** *)

(* end of [ATS3/XATSOPT_dynexp0_print0.dats] *)
