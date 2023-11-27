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
//
Fri Nov 24 03:22:05 EST 2023
//
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
//
(*
HX-2023-11-24:
level-0 intermediate representation
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
(* ****** ****** *)
//
#staload
"./../../../SATS/xbasics.sats"
#staload
"./../../../SATS/xsymbol.sats"
#staload
"./../../../SATS/xlabel0.sats"
//
(* ****** ****** *)
//
#staload
"./../../../SATS/locinfo.sats"
//
(* ****** ****** *)
//
#staload
"./../../../SATS/lexing0.sats"
//
(* ****** ****** *)
#staload S2E =
"./../../../SATS/staexp2.sats"
#staload T2P =
"./../../../SATS/statyp2.sats"
#staload D2E =
"./../../../SATS/dynexp2.sats"
(* ****** ****** *)
#staload D3E =
"./../../../SATS/dynexp3.sats"
(* ****** ****** *)
(* ****** ****** *)
#typedef stamp = stamp
#typedef sym_t = sym_t
#typedef label = label
#typedef loctn = loctn
#typedef loc_t = loctn
(* ****** ****** *)
#typedef s2exp = $S2E.s2exp
#typedef s2typ = $S2E.s2typ
(* ****** ****** *)
#typedef d2con = $D2E.d2con
#typedef d2cst = $D2E.d2cst
#typedef d2var = $D2E.d2var
#typedef d2pat = $D2E.d2pat
#typedef d2exp = $D2E.d2exp
(* ****** ****** *)
#typedef d3pat = $D3E.d3pat
#typedef d3exp = $D3E.d3exp
(* ****** ****** *)
#typedef l3d3p = $D3E.l3d3p
#typedef l3d3e = $D3E.l3d3e
(* ****** ****** *)
#typedef d3ecl = $D3E.d3ecl
(* ****** ****** *)
//
#typedef d3patlst = $D3E.d3patlst
//
#typedef d3explst = $D3E.d3explst
#typedef d3expopt = $D3E.d3expopt
//
(* ****** ****** *)
#typedef l3d3plst = $D3E.l3d3plst
#typedef l3d3elst = $D3E.l3d3elst
(* ****** ****** *)
#typedef d3eclist = $D3E.d3eclist
(* ****** ****** *)
#typedef d3valdcl = $D3E.d3valdcl
#typedef d3vardcl = $D3E.d3vardcl
#typedef d3fundcl = $D3E.d3fundcl
(* ****** ****** *)
#typedef d3valdclist = $D3E.d3valdclist
#typedef d3vardclist = $D3E.d3vardclist
#typedef d3fundclist = $D3E.d3fundclist
(* ****** ****** *)
#typedef d3parsed = $D3E.d3parsed
(* ****** ****** *)
#typedef d3explstopt = $D3E.d3explstopt
#typedef d3eclistopt = $D3E.d3eclistopt
(* ****** ****** *)
datatype
irlab(x0:type) =
|
IRLAB of (label, x0(*elt*))
(* ****** ****** *)
#abstbox irpat_tbox // p0tr
#typedef irpat = irpat_tbox
(* ****** ****** *)
#abstbox irexp_tbox // p0tr
#typedef irexp = irexp_tbox
(* ****** ****** *)
#abstbox irdcl_tbox // p0tr
#typedef irdcl = irdcl_tbox
(* ****** ****** *)
//
#abstbox irvaldcl_tbox//p0tr
#abstbox irvardcl_tbox//p0tr
#abstbox irfundcl_tbox//p0tr
//
(* ****** ****** *)
//
#abstbox irparsed_tbox//p0tr
//
(* ****** ****** *)
#typedef l0irp = irlab(irpat)
#typedef l0ire = irlab(irexp)
(* ****** ****** *)
#typedef irpatlst = list(irpat)
#typedef l0irplst = list(l0irp)
(* ****** ****** *)
#typedef irexpopt = optn(irexp)
#typedef irexplst = list(irexp)
#typedef l0irelst = list(l0ire)
(* ****** ****** *)
#typedef irdclist = list(irdcl)
(* ****** ****** *)
#typedef irvaldcl = irvaldcl_tbox
#typedef irvardcl = irvardcl_tbox
#typedef irfundcl = irfundcl_tbox
(* ****** ****** *)
#typedef irparsed = irparsed_tbox
(* ****** ****** *)
#typedef irvaldclist = list(irvaldcl)
#typedef irvardclist = list(irvardcl)
#typedef irfundclist = list(irfundcl)
(* ****** ****** *)
#typedef irdclistopt = optn(irdclist)
(* ****** ****** *)
//
datatype
irpat_node =
//
|IRPnil of ()
|IRPany of ()
//
|IRPvar of d2var
//
|IRPint of token
|IRPbtf of sym_t
|IRPchr of token
|IRPstr of token
//
|IRPbang of (irpat)
|IRPflat of (irpat)
|IRPfree of (irpat)
//
|IRPcapp of (d2con, irpatlst)
//
|IRPtup0 of
(sint(*npf*), irpatlst)
|IRPtup1 of
(token(*knd*), sint(*npf*), irpatlst)
|IRPrcd2 of
(token(*knd*), sint(*npf*), l0irplst)
//
|IRPnone0 of ((*0*)) | IRPnone1 of (d3pat)
//
(* ****** ****** *)
//
fun
irpat_fprint
(out: FILR, irp0: irpat): void
//
(* ****** ****** *)
//
fun
irpat_get_lctn(irpat):( loc_t )
fun
irpat_get_node(irpat):irpat_node
//
(* ****** ****** *)
#symload lctn with irpat_get_lctn
#symload node with irpat_get_node
(* ****** ****** *)
fun
irpat_none0(loc0: loctn): irpat
fun
irpat_none1(d3p0: d3pat): irpat
(* ****** ****** *)
fun
irpat_make_node
(loc: loctn, nod: irpat_node):irpat
(* ****** ****** *)
#symload irpat with irpat_make_node
(* ****** ****** *)
//
datatype
irexp_node =
//
|IREint of token
|IREbtf of sym_t
|IREchr of token
|IREflt of token
|IREstr of token
//
|IREi00 of (sint) // sint
|IREb00 of (bool) // bool
|IREc00 of (char) // char
|IREf00 of (dflt) // float
|IREs00 of (strn) // string
//
|IREtop of (sym_t)
//
|IREvar of (d2var)
//
|IREcon of (d2con)
|IREcst of (d2cst)
//
|
IREdapp of
(irexp, sint, irexplst)
//
|IRElet0 of
(irdclist, irexp(*scope*))
//
|IREift0 of
(irexp, irexpopt, irexpopt)
//
|IREseqn of
(irexplst(*init*), irexp(*last*))
//
|IREtup0 of
(sint(*npf*), irexplst)
|IREtup1 of
(
token(*knd*), sint(*npf*), irexplst)
|IRErcd2 of
(
token(*knd*), sint(*npf*), l0irelst)
//
|IREnone0 of ((*0*)) |IREnone1 of (d3exp)
//
// HX-2023-??-??: end-of-[datatype(irexp_node)]
//
(* ****** ****** *)
//
fun
irexp_fprint
(out: FILR, ire0: irexp): void
//
(* ****** ****** *)
//
fun
irexp_get_lctn(irexp):( loc_t )
fun
irexp_get_node(irexp):irexp_node
//
(* ****** ****** *)
#symload lctn with irexp_get_lctn
#symload node with irexp_get_node
(* ****** ****** *)
fun
irexp_none0(loc0: loctn): irexp
fun
irexp_none1(d3e0: d3exp): irexp
(* ****** ****** *)
fun
irexp_make_node
(loc:loctn, nod:irexp_node):irexp
(* ****** ****** *)
#symload irexp with irexp_make_node
(* ****** ****** *)
//
datatype
irdcl_node =
//
|IRDlocal0 of
( irdclist(*local-head*)
, irdclist(*local-body*))
//
|
IRDvaldclst of
(token(*VAL(vlk)*), irvaldclist)
|
IRDvardclst of
(token(*VAL(vlk)*), irvardclist)
|
IRDfundclst of
(token(*VAL(vlk)*), irfundclist)
//
|IRDnone0 of ((*0*)) |IRDnone1 of (d3ecl)
//
(* ****** ****** *)
//
fun
irdcl_fprint
(out: FILR, ird0: irdcl): void
//
(* ****** ****** *)
//
fun
irdcl_get_lctn(irdcl):( loc_t )
fun
irdcl_get_node(irdcl):irdcl_node
//
(* ****** ****** *)
fun
irdcl_none1(d3cl: d3ecl): irdcl
(* ****** ****** *)
fun
irdcl_make_node
(loc:loctn, nod:irdcl_node):irdcl
(* ****** ****** *)
#symload irdcl with irdcl_make_node
(* ****** ****** *)
//
fun
irparsed_of_trxd3ir
( dpar : d3parsed ): (irparsed)
//
(* ****** ****** *)
//
fun
irparsed_make_args
( stadyn:sint
, nerror:sint
, source:lcsrc
, parsed:irdclistopt): irparsed//end-fun
//
#symload irparsed with irparsed_make_args
//
(* ****** ****** *)
(* ****** ****** *)
#absvtbx
trdienv_vtbx
#vwtpdef
trdienv = trdienv_vtbx
(* ****** ****** *)
(* ****** ****** *)
//
fun
<x0:t0>
<y0:t0>
list_trxd3ir_fnp
( e1:
! trdienv
, xs: list(x0)
, (!trdienv, x0) -> y0): list(y0)
fun
<x0:t0>
<y0:t0>
optn_trxd3ir_fnp
( e1:
! trdienv
, xs: optn(x0)
, (!trdienv, x0) -> y0): optn(y0)
//
(* ****** ****** *)
(* ****** ****** *)
fun
trdienv_make_nil(): trdienv
fun
trdienv_free_top(trdienv): void
(* ****** ****** *)
fun
trxd3ir_d3pat
(env0: !trdienv, d3p0: d3pat): irpat
fun
trxd3ir_d3exp
(env0: !trdienv, d3e0: d3exp): irexp
(* ****** ****** *)
fun
trxd3ir_l3d3p
(env0: !trdienv, ld3p: l3d3p): l0irp
fun
trxd3ir_l3d3e
(env0: !trdienv, ld3e: l3d3e): l0ire
(* ****** ****** *)
fun
trxd3ir_d3ecl
(env0: !trdienv, d3cl: d3ecl): irdcl
(* ****** ****** *)
fun
trxd3ir_d3patlst
(env0: !trdienv, d3ps: d3patlst): irpatlst
(* ****** ****** *)
//
fun
trxd3ir_d3explst
(env0: !trdienv, d3es: d3explst): irexplst
fun
trxd3ir_d3expopt
(env0: !trdienv, dopt: d3expopt): irexpopt
//
(* ****** ****** *)
fun
trxd3ir_l3d3plst
(env0: !trdienv, ldps: l3d3plst): l0irplst
fun
trxd3ir_l3d3elst
(env0: !trdienv, ldes: l3d3elst): l0irelst
(* ****** ****** *)
fun
trxd3ir_d3eclist
(env0: !trdienv, dcls: d3eclist): irdclist
(* ****** ****** *)
fun
trxd3ir_d3valdcl
(env0: !trdienv, dval: d3valdcl): irvaldcl
fun
trxd3ir_d3vardcl
(env0: !trdienv, dvar: d3vardcl): irvardcl
(* ****** ****** *)
fun
trxd3ir_d3fundcl
(env0: !trdienv, dfun: d3fundcl): irfundcl
(* ****** ****** *)
fun
trxd3ir_d3valdclist
(env0: !trdienv, d3vs: d3valdclist): irvaldclist
fun
trxd3ir_d3vardclist
(env0: !trdienv, d3vs: d3vardclist): irvardclist
(* ****** ****** *)
fun
trxd3ir_d3fundclist
(env0: !trdienv, d3fs: d3fundclist): irfundclist
(* ****** ****** *)
fun
trxd3ir_d3eclistopt
(env0: !trdienv, dcls: d3eclistopt): irdclistopt
(* ****** ****** *)
(* ****** ****** *)

(* end of [ATS3/XANADU_srcgen2_xinterp_srcgen1_intrep0.sats] *)