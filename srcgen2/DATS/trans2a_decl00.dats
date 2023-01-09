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
(*
Sun 20 Nov 2022 11:06:32 AM EST
*)
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
#staload
_(*TRANS2a*) = "./trans2a.dats"
(* ****** ****** *)
#staload "./../SATS/xbasics.sats"
(* ****** ****** *)
#staload "./../SATS/staexp2.sats"
#staload "./../SATS/statyp2.sats"
#staload "./../SATS/dynexp2.sats"
(* ****** ****** *)
#staload "./../SATS/trans2a.sats"
(* ****** ****** *)
#symload name with s2cst_get_name
#symload name with s2var_get_name
(* ****** ****** *)
#symload node with s2typ_get_node
(* ****** ****** *)
#symload styp with d2pat_get_styp
#symload styp with d2exp_get_styp
(* ****** ****** *)
//
fun
s2typ_new0_x2tp
( loc0: loc_t ): s2typ =
s2typ_xtv(x2t2p_make_lctn(loc0))
//
(* ****** ****** *)
//
fun
s2typ_fun1
( f2cl
: f2clknd
, npf1: sint
, t2ps
: s2typlst, tres: s2typ): s2typ =
let
val s2t0 =
(
case f2cl of
|
F2CLfun() =>
the_sort2_tbox
|
F2CLclo(knd) =>
(
case+ knd of
| 0 => the_sort2_type
| 1 => the_sort2_vtbx
| _ => the_sort2_tbox))
val f2cl = s2typ_f2cl(f2cl)
in//let
s2typ_make_node
(s2t0, T2Pfun1(f2cl,npf1,t2ps,tres))
end (*let*) // end of [s2typ_fun1(...)]
//
(* ****** ****** *)
//
#implfun
trans2a_d2ecl
( env0, d2cl ) = let
//
// (*
val
loc0 = d2cl.lctn()
val () =
prerrln
("trans2a_d2ecl: d2cl = ", d2cl)
// *)
//
in//let
//
case+
d2cl.node() of
//
| D2Cd1ecl _ => d2cl
//
| D2Cstatic _ =>
(
f0_static(env0, d2cl))
| D2Cextern _ =>
(
f0_extern(env0, d2cl))
//
| D2Clocal0 _ =>
(
f0_local0(env0, d2cl))
//
| D2Cabssort _ => d2cl
| D2Cstacst0 _ => d2cl
//
| D2Csortdef _ => d2cl
| D2Csexpdef _ => d2cl
//
| D2Cabstype _ => d2cl
(*
| D2Cabsopen _ => d2cl
*)
|
D2Cabsimpl _ => f0_absimpl(env0, d2cl)
//
|
D2Cvaldclst _ => f0_valdclst(env0, d2cl)
|
D2Cvardclst _ => f0_vardclst(env0, d2cl)
|
D2Cfundclst _ => f0_fundclst(env0, d2cl)
//
|
D2Cimplmnt0 _ => f0_implmnt0(env0, d2cl)
//
| _(*otherwise*) =>
let
  val loc0 = d2cl.lctn()
in//let
  d2ecl_make_node(loc0, D2Cnone2( d2cl ))
end (*let*) // end of [_(*otherwise*)] // temp
//
end where
{
//
(* ****** ****** *)
//
fun
f0_static
( env0:
! tr2aenv
, d2cl: d2ecl): d2ecl =
let
//
val
loc0 = d2cl.lctn()
val-
D2Cstatic
(tknd, dcl1) =  d2cl.node()
val
dcl1 = trans2a_d2ecl(env0, dcl1)
in//let
  d2ecl(loc0, D2Cstatic(tknd, dcl1))
end (*let*) // end of [f0_static(env0,d2cl)]
//
fun
f0_extern
( env0:
! tr2aenv
, d2cl: d2ecl): d2ecl =
let
//
val
loc0 = d2cl.lctn()
val-
D2Cextern
(tknd, dcl1) = d2cl.node()
val
dcl1 = trans2a_d2ecl(env0, dcl1)
in//let
  d2ecl(loc0, D2Cextern(tknd, dcl1))
end (*let*) // end of [f0_extern(env0,d2cl)]
//
(* ****** ****** *)
//
fun
f0_local0
( env0:
! tr2aenv
, d2cl: d2ecl): d2ecl =
let
//
val
loc0 = d2cl.lctn()
val-
D2Clocal0
(head, body) = d2cl.node()
//
val (  ) =
tr2aenv_pshloc1(env0)
val head =
trans2a_d2eclist(env0, head)
val (  ) =
tr2aenv_pshloc2(env0)
val body =
trans2a_d2eclist(env0, body)
//
val (  ) = tr2aenv_locjoin(env0)
//
in//let
  d2ecl(loc0, D2Clocal0(head, body))
end (*let*) // end of [f0_local0(env0,d2cl)]
//
(* ****** ****** *)
//
fun
f0_absimpl
( env0:
! tr2aenv
, d2cl: d2ecl): d2ecl =
let
//
val-
D2Cabsimpl
( tknd
, simp, sdef) = d2cl.node()
//
in//let
//
let
val () =
case+ simp of
|
SIMPLall1
(sqid, s2cs) => ()
|
SIMPLopt2
(sqid, scs1, scs2) =>
(
case+ scs2 of
|list_nil() => ()
|list_cons(s2c1, _) =>
let
val
sdef = s2exp_stpize(sdef)
val () =
tr2aenv_insert_any
(env0, s2c1.name(), sdef) end) in d2cl
end (*let*)
//
end (*let*) // end of [f0_absimpl(env0,d2cl)]
//
(* ****** ****** *)
//
fun
f0_valdclst
( env0:
! tr2aenv
, d2cl: d2ecl): d2ecl =
let
//
val
loc0 = d2cl.lctn()
val-
D2Cvaldclst
(tknd, d2vs) = d2cl.node()
//
val () =
prerrln
("f0_valdclst: d2cl = ", d2cl)
//
val
d2vs =
trans2a_d2valdclist(env0, d2vs)
//
in//let
  d2ecl(loc0, D2Cvaldclst(tknd, d2vs))
end (*let*) // end of [f0_valdclst(env0,d2cl)]
//
(* ****** ****** *)
//
fun
f0_vardclst
( env0:
! tr2aenv
, d2cl: d2ecl): d2ecl =
let
//
val
loc0 = d2cl.lctn()
val-
D2Cvardclst
(tknd, d2vs) = d2cl.node()
//
val () =
prerrln
("f0_vardclst: d2cl = ", d2cl)
//
val
d2vs =
trans2a_d2vardclist(env0, d2vs)
//
in//let
  d2ecl(loc0, D2Cvardclst(tknd, d2vs))
end (*let*) // end of [f0_vardclst(env0,d2cl)]
//
(* ****** ****** *)
//
fun
f0_fundclst
( env0:
! tr2aenv
, d2cl: d2ecl): d2ecl =
let
//
val
loc0 = d2cl.lctn()
val-
D2Cfundclst
(tknd
,tqas, d2fs) = d2cl.node()
//
val () =
prerrln
("f0_fundclst: d2cl = ", d2cl)
//
val
d2fs =
trans2a_d2fundclist(env0, d2fs)
//
in//let
d2ecl(loc0, D2Cfundclst(tknd, tqas, d2fs))
end (*let*) // end of [f0_fundclst(env0,d2cl)]
//
(* ****** ****** *)
//
fun
f0_implmnt0
( env0:
! tr2aenv
, d2cl: d2ecl): d2ecl =
let
//
val
loc0 = d2cl.lctn()
val-
D2Cimplmnt0
( tknd
, sqas, tqas
, dimp//dcst
, tias, f2as
, sres, dexp) = d2cl.node()
//
(*
val () =
prerrln
("f0_implmnt0: d2cl = ", d2cl)
*)
//
val
f2as = trans2a_f2arglst(env0, f2as)
//
val
dexp =
(
case+ sres of
|S2RESnone() =>
trans2a_d2exp(env0, dexp)
|S2RESsome(seff, sexp) =>
let
val
tres = s2exp_stpize(sexp) in
trans2a_d2exp_tpck(env0, dexp, tres)
end (*let*) // end of [S2RESsome(...)]
)
//
in
d2ecl
(
loc0,
D2Cimplmnt0
(tknd,sqas,tqas,dimp,tias,f2as,sres,dexp))
end (*let*) // end of [f0_implmnt0(env0,d2cl)]
//
(* ****** ****** *)
//
} (*where*) // end of [trans2a_d2ecl(env0,d2cl)]
//
(* ****** ****** *)

#implfun
trans2a_d2valdcl
  (env0, dval) = let
//
val loc0 =
d2valdcl_get_lctn(dval)
val dpat =
d2valdcl_get_dpat(dval)
val tdxp =
d2valdcl_get_tdxp(dval)
val wsxp =
d2valdcl_get_wsxp(dval)
//
val dpat =
trans2a_d2pat(env0, dpat)
//
in//let
d2valdcl_make_args(loc0,dpat,tdxp,wsxp)
end//let
(*let*)//end-of-[trans2a_d2valdcl(env0,dval)]

(* ****** ****** *)

#implfun
trans2a_d2vardcl
  (env0, dvar) = let
//
val loc0 =
d2vardcl_get_lctn(dvar)
val dpid =
d2vardcl_get_dpid(dvar)
val vpid =
d2vardcl_get_vpid(dvar)
val sres =
d2vardcl_get_sres(dvar)
val dini =
d2vardcl_get_dini(dvar)
//
val tres =
(
case+ sres of
|optn_nil
((*void*)) =>
s2typ_new0_x2tp(loc0)
|optn_cons
(  s2e1  ) =>
s2typ_hnfiz0(s2exp_stpize(s2e1))
) : s2typ // end-of-[ val(tres) ]
val (  ) =
let
val tlft =
s2typ_lft(tres) in dpid.styp(tlft)
end (*let*)
//
val dini =
(
case+ dini of
|
TEQD2EXPnone
( (*void*) ) =>
TEQD2EXPnone((*void*))
|
TEQD2EXPsome
(teq1, d2e2) =>
(
TEQD2EXPsome
(teq1, d2e2)) where
{
val d2e2 =
trans2a_d2exp_tpck(env0,d2e2,tres)
}
) : teqd2exp // end of [val(dini)]
//
in//let
d2vardcl(loc0, dpid, vpid, sres, dini)
end//let
(*let*)//end-of-[trans2a_d2vardcl(env0,dvar)]

(* ****** ****** *)

#implfun
trans2a_d2fundcl
  (env0, dfun) = let
//
val loc0 =
d2fundcl_get_lctn(dfun)
//
val dvar =
d2fundcl_get_dpid(dfun)
val f2as =
d2fundcl_get_farg(dfun)
val sres =
d2fundcl_get_sres(dfun)
val tdxp =
d2fundcl_get_tdxp(dfun)
val wsxp =
d2fundcl_get_wsxp(dfun)
//
val f2as =
trans2a_f2arglst(env0, f2as)
//
val tres =
(
case+ sres of
|
S2RESnone() =>
s2typ_new0_x2tp(loc0)
|
S2RESsome(seff,s2e1) =>
s2typ_hnfiz0(s2exp_stpize(s2e1))
) : s2typ // end of [ val(tres) ]
//
val tfun =
f0_f2as(f2as, f1_ndyn(f2as), tres)
val (  ) =
prerrln
("trans2a_d2fundcl: tfun = ", tfun)
//
in//let
//
let
val (  ) =
d2var_set_styp(dvar, tfun) in//let
d2fundcl(loc0,dvar,f2as,sres,tdxp,wsxp)
end
//
end where
{
//
fun
f0_f2as
( f2as
: f2arglst
, ndyn: sint
, tres: s2typ): s2typ =
(
case+ f2as of
|
list_nil() => tres
|
list_cons(f2a1, f2as) =>
(
case+
f2a1.node() of
|
F2ARGmet0 _ =>
f0_f2as(f2as, ndyn, tres)
|
F2ARGsta0
(s2vs, s2ps) =>
let
val s2t0 = tres.sort()
in//let
s2typ
(s2t0,T2Puni0(s2vs, tres))
end where
{
val
tres =
f0_f2as(f2as, ndyn, tres) }
|
F2ARGdyn0(npf1, d2ps) =>
(
s2typ_fun1
(f2cl,npf1,t2ps,tres)) where
{
val ndyn = ndyn - 1
val tres =
f0_f2as(f2as, ndyn, tres)
val t2ps =
s2typlst_of_d2patlst(d2ps)
val f2cl =
if
(ndyn <= 0)
then F2CLfun() else F2CLclo(1) } )
)(*case+*)//end-of-[f0_f2as(f2as,...)]
//
and
f1_ndyn(xs: f2arglst): sint =
(
case+ xs of
|
list_nil() => 0
|
list_cons(x1, xs) =>
(
case+ x1.node() of
|F2ARGdyn0 _ =>
 f1_ndyn(xs) + 1 | _ => f1_ndyn(xs)))
//
(*
val () =
prerrln("trans2a_d2fundcl: dfun = ", dfun)
*)
//
}(*where*)//end-of-[trans2a_d2fundcl(env0,dfun)]

(* ****** ****** *)
//
#implfun
trans2a_d2eclist
  (env0, dcls) =
(
  list_trans2a_fnp(env0, dcls, trans2a_d2ecl))
//
(* ****** ****** *)
//
#implfun
trans2a_s2qaglst
  (env0, sqas) =
(
  list_trans2a_fnp(env0, sqas, trans2a_s2qag))
#implfun
trans2a_t2qaglst
  (env0, tqas) =
(
  list_trans2a_fnp(env0, tqas, trans2a_t2qag))
//
#implfun
trans2a_t2iaglst
  (env0, tias) =
(
  list_trans2a_fnp(env0, tias, trans2a_t2iag))
//
(* ****** ****** *)
//
#implfun
trans2a_d2arglst
  (env0, d2as) =
(
  list_trans2a_fnp(env0, d2as, trans2a_d2arg))
//
(* ****** ****** *)
//
local
//
fun
f0_d2valdcl
( env0:
! tr2aenv
, dval
: d2valdcl): d2valdcl =
let
//
val loc0 =
d2valdcl_get_lctn(dval)
val dpat =
d2valdcl_get_dpat(dval)
val tdxp =
d2valdcl_get_tdxp(dval)
//
val tdxp =
(
case+ tdxp of
|
TEQD2EXPnone
( (*void*) ) =>
TEQD2EXPnone((*void*))
|
TEQD2EXPsome
(teq1, d2e2) =>
(
TEQD2EXPsome
(teq1, d2e2)) where
{
//
val tres = dpat.styp()
//
val (  ) =
prerrln
("f0_d2valdcl: dpat = ", dpat)
val (  ) =
prerrln
("f0_d2valdcl: tres = ", tres)
//
val d2e2 =
trans2a_d2exp_tpck(env0,d2e2,tres)
}
) : teqd2exp // end-[val(tdxp)]
//
val wsxp = d2valdcl_get_wsxp(dval)
//
in//let
d2valdcl_make_args(loc0,dpat,tdxp,wsxp)
end//let//end-of-[f0_d2valdcl(env0,...)]
//
in//local
//
#implfun
trans2a_d2valdclist
  (env0, dcls) =
(
list_trans2a_fnp
(env0, dcls, f0_d2valdcl)) where
{
//
val dcls =
list_trans2a_fnp(env0,dcls,trans2a_d2valdcl)}
//
endloc // end of [local(trans2a_d2valdclist)]
//
(* ****** ****** *)
//
#implfun
trans2a_d2vardclist
  (env0, dcls) =
list_trans2a_fnp(env0, dcls, trans2a_d2vardcl)
//
(* ****** ****** *)
//
local
//
fun
f0_tres
( f2as
: f2arglst
, tres: s2typ): s2typ =
(
case+ f2as of
|list_nil() => tres
|list_cons(f2a1, f2as) =>
(
case+
f2a1.node() of
|F2ARGdyn0 _ =>
let
val-
T2Pfun1
(f2cl,npf1
,t2ps,tres) =
tres.node() in
f0_tres(f2as, tres) end//F2ARGdyn0
|F2ARGsta0 _ =>
let
val-
T2Puni0
(s2vs,tres) =
tres.node() in
f0_tres(f2as, tres) end//F2ARGsta0
|F2ARGmet0 _ => f0_tres(f2as, tres))
) (*case+*) // end-of-[f0_tres(...)]
//
fun
f0_d2fundcl
( env0:
! tr2aenv
, dfun
: d2fundcl): d2fundcl =
let
//
val loc0 =
d2fundcl_get_lctn(dfun)
val dvar =
d2fundcl_get_dpid(dfun)
val f2as =
d2fundcl_get_farg(dfun)
val tdxp =
d2fundcl_get_tdxp(dfun)
//
val tdxp =
(
case+ tdxp of
|
TEQD2EXPnone
( (*void*) ) =>
TEQD2EXPnone((*void*))
|
TEQD2EXPsome
(teq1, d2e2) =>
(
TEQD2EXPsome(teq1, d2e2)) where
{
val tres =
f0_tres(f2as, dvar.styp())
val (  ) =
prerrln
("f0_d2fundcl: dvar = ", dvar)
val (  ) =
prerrln
("f0_d2fundcl: tres = ", tres)
val d2e2 =
trans2a_d2exp_tpck(env0,d2e2,tres)
}
) : teqd2exp // end-[val(tdxp)]
//
val sres = d2fundcl_get_sres(dfun)
val wsxp = d2fundcl_get_wsxp(dfun)
//
in//let
d2fundcl(loc0,dvar,f2as,sres,tdxp,wsxp)
end//let//end-of-[f0_d2fundcl(env0,...)]
//
in//local
//
#implfun
trans2a_d2fundclist
  (env0, dcls) =
(
list_trans2a_fnp
(env0, dcls, f0_d2fundcl)) where
{
//
val dcls =
list_trans2a_fnp(env0,dcls,trans2a_d2fundcl)}
//
endloc // end of [local(trans2a_d2fundclist)]
//
(* ****** ****** *)
//
#implfun
trans2a_d2cstdclist
  (env0, dcls) =
list_trans2a_fnp(env0, dcls, trans2a_d2cstdcl)
//
(* ****** ****** *)
//
#implfun
trans2a_d2eclistopt
( env0, dopt ) =
optn_trans2a_fnp(env0, dopt, trans2a_d2eclist)
//
(* ****** ****** *)

(* end of [ATS3/XATSOPT_srcgen2_trans2a_decl00.dats] *)
