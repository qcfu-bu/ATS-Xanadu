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
(* ****** ****** *)
//
(*
Author: Hongwei Xi
(*
Thu Nov  9 13:21:34 EST 2023
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
(*
#include
"./../HATS/xatsopt_dats.hats"
*)
#include
"./../HATS/xatsopt_dpre.hats"
//
(* ****** ****** *)
(* ****** ****** *)
#staload "./../SATS/xstamp0.sats"
(* ****** ****** *)
#staload "./../SATS/xsymmap.sats"
(* ****** ****** *)
#staload "./../SATS/staexp2.sats"
#staload "./../SATS/statyp2.sats"
(* ****** ****** *)
#staload "./../SATS/dynexp2.sats"
#staload "./../SATS/dynexp3.sats"
(* ****** ****** *)
#staload "./../SATS/trtmp3c.sats"
(* ****** ****** *)
#symload stmp with timpl_get_stmp
#symload node with timpl_get_node
(* ****** ****** *)
(* ****** ****** *)
//
(*
CLAUDE-2026-08 (zztic): the template-INSTANCE CACHE (see trtmp3c.sats).
Two instantiations of the same impl at EQUAL type arguments whose bodies
resolved against NO embedded (where-block) impls are observationally
identical under the copy-per-instantiation model -- one walked body is
shared, carrying a FRESH D3Cimplmnt0 stamp (every walked instance gets a
fresh stamp: shared entries reuse ONE, so the backend can recognize
sharing by stamp equality; unshared walks each get their own, so stamp
equality can never lie).  Each entry records the d2csts its body's
resolution QUERIED (transitively): the entry is neither created nor
reused while an embedded impl for any traced cst is in scope -- that is
exactly the g_print$out hook-sensitivity class.
*)
//
datatype
zztce =
ZZTCE of
( d3ecl(*head: D3Ctmpsub, for tmpequal*)
, d3ecl(*shared walked body*)
, d2cstlst(*resolution trace*))
//
#typedef zztcelst = list(zztce)
//
local
//
val
zzticstamper = stamper_new((*void*))
//
val
zzticmap =
a0ref_make_1val
<tmpmap(zztcelst)>(tmpmap_make_nil{zztcelst}())
//
val
zztictrc =
a0ref_make_1val
<list(d2cstlst)>(list_nil())
//
val zzticwalks = a0ref_make_1val<sint>(0)
val zztichits = a0ref_make_1val<sint>(0)
val zzticblkd = a0ref_make_1val<sint>(0)
//
in//local
//
#implfun
trtmp3c_zztic_clear
  ((*void*)) =
(
a0ref_set<tmpmap(zztcelst)>
(zzticmap, tmpmap_make_nil{zztcelst}()))
//
#implfun
trtmp3c_zztic_report
  ((*void*)) =
let
val () =
prerrsln
("ZZTIC: walks = ", a0ref_get<sint>(zzticwalks))
val () =
prerrsln
("ZZTIC: hits = ", a0ref_get<sint>(zztichits))
val () =
prerrsln
("ZZTIC: blocked = ", a0ref_get<sint>(zzticblkd))
in//let
  ((*void*))
end//let
//
fun
zztic_walkinc((*void*)): void =
a0ref_set<sint>
(zzticwalks, a0ref_get<sint>(zzticwalks) + 1)
fun
zztic_hitinc((*void*)): void =
a0ref_set<sint>
(zztichits, a0ref_get<sint>(zztichits) + 1)
fun
zztic_blkinc((*void*)): void =
a0ref_set<sint>
(zzticblkd, a0ref_get<sint>(zzticblkd) + 1)
//
fun
zztic_trcpush((*void*)): void =
a0ref_set<list(d2cstlst)>
( zztictrc
, list_cons
  (list_nil(), a0ref_get<list(d2cstlst)>(zztictrc)))
//
fun
zztic_trcadd(d2c0: d2cst): void =
(
case+
a0ref_get<list(d2cstlst)>(zztictrc) of
|
list_nil() => ((*no active frame*))
|
list_cons(top, rest) =>
a0ref_set<list(d2cstlst)>
(zztictrc, list_cons(list_cons(d2c0, top), rest)))
//
fun
zztic_trcaddlst(cs: d2cstlst): void =
(
case+
a0ref_get<list(d2cstlst)>(zztictrc) of
|
list_nil() => ((*no active frame*))
|
list_cons(top, rest) =>
a0ref_set<list(d2cstlst)>
(zztictrc, list_cons(list_append(cs, top), rest)))
//
fun
zztic_trcpop((*void*)): d2cstlst =
(
case+
a0ref_get<list(d2cstlst)>(zztictrc) of
|
list_nil() => list_nil()
|
list_cons(top, rest) =>
let
val () =
(
case+ rest of
|
list_nil() =>
a0ref_set<list(d2cstlst)>(zztictrc, list_nil())
|
list_cons(par, rr) =>
a0ref_set<list(d2cstlst)>
(zztictrc, list_cons(list_append(top, par), rr)))
in//let
  top
end//let
)(*case+*)//end-of-[zztic_trcpop()]
//
fun
zztic_memberq
(embs: d2cstlst, d2c0: d2cst): bool =
let
val s0 = d2cst_get_stmp(d2c0)
fun
loop(cs: d2cstlst): bool =
(
case+ cs of
|list_nil() => false
|list_cons(c1, cs) =>
 if
 (stamp_cmp(d2cst_get_stmp(c1), s0) = 0)
 then true else loop(cs))
in//let
  loop(embs)
end//let
//
fun
zztic_overlapq
(embs: d2cstlst, trc: d2cstlst): bool =
(
case+ trc of
|list_nil() => false
|list_cons(c1, trc) =>
 if
 zztic_memberq(embs, c1)
 then true else zztic_overlapq(embs, trc))
//
fun
zztic_lookup
( embs: d2cstlst
, ikey: stamp
, t2js: t2jaglst): optn(zztce) =
let
fun
scan(ents: zztcelst): optn(zztce) =
(
case+ ents of
|
list_nil() => optn_nil()
|
list_cons(ent1, ents) =>
let
val+ZZTCE(head, _, trc) = ent1
in//let
if
tmpequal_d3cl_t2js(head, t2js)
then
(
if
zztic_overlapq(embs, trc)
then
let
val () = zztic_blkinc() in scan(ents)
end
else optn_cons(ent1))
else scan(ents)
end//let
)(*case+*)//end-of-[scan(ents)]
in//let
case+
tmpmap_search$opt
(a0ref_get<tmpmap(zztcelst)>(zzticmap), ikey) of
| ~optn_vt_nil() => optn_nil()
| ~optn_vt_cons(ents) => scan(ents)
end//let//end-of-[zztic_lookup(...)]
//
fun
zztic_freshen(dcl2: d3ecl): d3ecl =
(
case+
dcl2.node() of
|
D3Cimplmnt0
( tknd, _
, sqas, tqas
, dimp
, tias, f3as
, sres, dexp) =>
d3ecl_make_node
( d3ecl_get_lctn(dcl2)
, D3Cimplmnt0
  ( tknd
  , zzticstamper.getinc()
  , sqas, tqas, dimp, tias, f3as, sres, dexp))
|
_(*non-implmnt0*) => dcl2
)(*case+*)//end-of-[zztic_freshen(dcl2)]
//
fun
zztic_insert
( embs: d2cstlst
, ikey: stamp
, head: d3ecl
, body: d3ecl
, trc: d2cstlst): void =
(
case+
body.node() of
|
D3Cimplmnt0 _ =>
if
zztic_overlapq(embs, trc)
then ((*hook-sensitive: not cacheable*))
else
let
val map0 =
a0ref_get<tmpmap(zztcelst)>(zzticmap)
val ents =
(
case+
tmpmap_search$opt(map0, ikey) of
| ~optn_vt_nil() => list_nil()
| ~optn_vt_cons(ents) => ents): zztcelst
in//let
tmpmap_insert$any
(map0, ikey, list_cons(ZZTCE(head, body, trc), ents))
end//let
|
_(*non-implmnt0*) => ((*not cacheable*))
)(*case+*)//end-of-[zztic_insert(...)]
//
end(*local*)//end-of-[local(zztic state)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
tr3cenv_timpl_process
  (  env0, timp  ) =
(
case+
timp.node() of
|
TIMPLallx _ => (timp)
|
TIMPLall1 _ =>
(
if
nimp >= NIMP
then timp else
(
  f0_all1(env0, timp) )
) where//end-(TIMPLall1)
{
//
(*
val NIMP = 10
*)
val NIMP = 99//HX: FIXME?!
val nimp = tr3cenv_getnimp(env0)
//
(*
val (  ) =
prerrsln("\
tr3cenv_timpl_process: nimp = ", nimp)
*)
//
}(*whr*)//end-of-[TIMPLall1(d2c0,...)]
//
) where //end-of-(case-of(timp.node()))
{
//
fun
f0_all1
( env0:
! tr3cenv
, timp: timpl): timpl =
let
//
val
stmp = timp.stmp((*0*))
//
val-
TIMPLall1
(d2c0
,t2js, dcls) = timp.node()
//
in//in
case+ dcls of
|
list_nil
((*void*)) =>
(  timp  ) // HX: ~found
|
list_cons
(dcl1, dcls) =>
let
//
val-
D3Ctmpsub
(svts, dcl2) = dcl1.node()
//
(*
CLAUDE-2026-08 (zztic): consult the instance cache BEFORE walking.
[ikey] = the chosen impl's stamp (embedded impls are re-stamped at
registration, so their instances can never collide with cached
top-level ones); a hit requires EQUAL type arguments (tmpequal) and
no embedded impl in scope for any cst the cached body's resolution
queried.  On a hit the SHARED walked body is attached under this
site's tmpsub and its trace merges into the enclosing frame.
*)
val ikey = d3imp_get_stmp(dcl1)
val embs = tr3cenv_embcsts(env0)
//
in//let
case+
zztic_lookup(embs, ikey, t2js) of
|
optn_cons
(ent1) =>
let
val+ZZTCE(_, body, trc) = ent1
val () = zztic_hitinc()
val () = zztic_trcaddlst(trc)
val dcl1 =
(
  d3ecl_tmpsub(svts, body))
val dcls = list_cons(dcl1, dcls)
in//let
(
timpl
(stmp, TIMPLallx(d2c0,t2js,dcls)))
end//let//end-of-[optn_cons(...)]
|
optn_nil() =>
let
//
val () = zztic_walkinc()
val () = zztic_trcpush()
//
val () =
tr3cenv_pshsvts(env0, svts)
//
val dcl2 =
let
val
dcl3 =
d3ecl_impsub//stamp as is
(0, svts, dcl2)//val(dcl2)
val () =
tr3cenv_insert_timp
(env0 , stmp , dcl3)//val()
in//let
trtmp3c_tmpd3ecl(env0, dcl2)
end//let//end-of-[val(dcl2)]
//
val () = tr3cenv_popsvts(env0)
//
val trc = zztic_trcpop()
val dcl2 = zztic_freshen(dcl2)
val () =
zztic_insert(embs, ikey, dcl1, dcl2, trc)
//
in//let
//
let
//
val dcl1 =
(
  d3ecl_tmpsub(svts, dcl2))
//
val dcls = list_cons(dcl1, dcls)
//
in//let
(
timpl
(stmp, TIMPLallx(d2c0,t2js,dcls)))
end//let
//
end//let//end-of-[optn_nil()]
end//let//end-of-[list_cons( ... )]
end//let//end-of-[f0_all1(env0,timp)]
//
(*
val () =
prerrsln("\
tr3cenv_timpl_process: timp = ", timp)
*)
//
}(*where*)//end-of-[tr3cenv_timpl_process]
//
(* ****** ****** *)
//
local
//
(* ****** ****** *)
(*
HX-2023-11-17:
It is implemented in
[dynexp3_utils0.dats]:
tmpmatch_d3cl_t2js(d3cl,t2js)
*)
(* ****** ****** *)
//
fn0
s2typlst_subst0
( t2ps
: s2typlst
, svts: s2vts): s2typlst =
(
case+ svts of
|
list_nil
( (*nil*) ) => t2ps
|
list_cons _ =>
s2typlst_subst0(t2ps, svts))
(*case+*) // end of [s2typlst_subst0]
//
(* ****** ****** *)
//
fun
t2jaglst_subst0
( t2js
: t2jaglst
, svts: s2vts): t2jaglst =
(
case+ svts of
|
list_nil
( (*nil*) ) => t2js
|
list_cons _ =>
(
  list_map(t2js)) where

{
//
#typedef x0 = t2jag
#typedef y0 = t2jag
//
#impltmp
map$fopr
<x0><y0>(x0) =
(
t2jag_make_t2ps
( loc0 , t2ps )) where
{
val loc0 =
t2jag_get_lctn(x0)
val t2ps =
t2jag_get_t2ps(x0)
val t2ps =
s2typlst_subst0(t2ps, svts) }
//
}
)(*case+*) // end of [t2jaglst_subst0]
//
(* ****** ****** *)
in//local
(* ****** ****** *)
//
#implfun
tr3cenv_t3apq_resolve
 ( env0, d2c0, t2js ) =
let
//
(*
CLAUDE-2026-08 (zztic): record every query into the ACTIVE instance's
resolution trace -- reuse of that instance is sound only while no
embedded impl for any queried cst is in scope.
*)
val () = zztic_trcadd(d2c0)
//
val
dcls = implfilter(dcls)
//
val
dcls =
(
  impltmprec(env0, dcls))
//
val dcls = list_vt2t(dcls)
//
in//let
//
(
timpl_make_node(stmp, node)
) where
{
//
val node =
(
case+ dcls of
|list_nil
((*nil*)) =>
(
  TIMPLall1(d2c0, t2js, dcls))
|
list_cons
(dcl1, _) =>
(
case+
dcl1.node() of
|
D3Cimpltmpr _ =>
(
  TIMPLallx(d2c0, t2js, dcls))
|
_(*non-tmpr*) =>
(
  TIMPLall1(d2c0, t2js, dcls)))
)
//
(*
val () = prerrsln("\
tr3cenv_t3apq_resolve: dcls = ", dcls)
*)
//
}//endwhr
//
end where // end-of-let
{
//
fun
implfilter
( dcls
: d3eclist_vt
)
: d3eclist_vt =
(
//
case+ dcls of
| ~
list_vt_nil
( (*nil*) ) =>
list_vt_nil((*nil*))
| ~
list_vt_cons
(dcl1, dcls) =>
let
//
val
opt1 =
tmpmatch_d3cl_t2js
(dcl1(*imp*),t2js(*arg*))
//
in//let
//
case+ opt1 of
//
|
optn_nil
( (*0*) ) =>
implfilter(dcls)
//
|
optn_cons(tsub) =>
if
not(
s2vts_stleq(tsub))
then
(
  implfilter(dcls))
else let // if-else
//
val
dcl1 =
(
case+
dcl1.node() of
|D3Ctmpsub(_, dcl1) =>
(
  d3ecl_tmpsub(tsub,dcl1) )
|_(*non-D3Ctmpsub*) =>
(
  d3ecl_tmpsub(tsub,dcl1) ) )
//
(*
val (  ) =
prerr("tr3cenv_t3apq_resolve:")
val (  ) =
prerrsln("implfilter: dcl1 = ", dcl1)
*)
//
in//let
(
list_vt_cons(dcl1, implfilter(dcls)))
end//let
end//let // end-of-[list_vt_cons(...)]
//
)(*case+*) // end of [implfilter(dcls)]
//
(* ****** ****** *)
//
fun
impltmprec
( env0:
! tr3cenv
, dcls
: d3eclist_vt): d3eclist_vt =
(
case+ dcls of
//
| ~
list_vt_nil
( (*nil*) ) =>
list_vt_nil( (*nil*) )
//
| ~
list_vt_cons
(dcl1, dcls) =>
(
if
stamp_nilq(test)
then
list_vt_cons(dcl1, dcls)
else
(
if
(
  d3ecl_impltmprq(dcl1))
then
(
list_vt_cons(dcl1, dcls)
) where {
val dcl1 =
d3ecl_impltmpr(test, dcl1)
}(*where*)//end-of-then
else
(
  impltmprec( env0, dcls )))
) where {
//
val
test = // test: stamp
(
tr3cenv_impltmprecq(env0,dcl1,t2js))
//
(*
val () =
prerrsln("impltmprec: test = ", test)
*)
//
}(*where*) // end of [ list_cons(...) ]
//
)(*case+*) // end of [impltmprec(dcls)]
//
(* ****** ****** *)
//
} where {
//
(*
val () =
prerrsln("\
tr3cenv_t3apq_resolve: d2c0 = ", d2c0)
val () =
prerrsln("\
tr3cenv_t3apq_resolve: t2js = ", t2js)
*)
//
(*
HX:
The stamp is for the
stack of tmplt resolution
*)
val
stmp = tr3cenv_getstmp(env0)//val(stmp)
(*
HX:
[trtmp3b]
guarantees [svts] to exist
*)
val
svts = tr3cenv_getsvts(env0)//val(svts) 
//
(*
val () =
prerrsln("\
tr3cenv_t3apq_resolve: stmp = ", stmp)
val () =
prerrsln("\
tr3cenv_t3apq_resolve: svts = ", svts)
*)
//
val t2js =
(
t2jaglst_subst0(t2js, svts))//val(t2js)
//
(*
val () =
(
prerrsln
("tr3cenv_t3apq_resolve: t2js = ", t2js))
*)
//
val dcls =
(
 tr3cenv_search_dcst(env0, d2c0))//val(dcls)
//
(*
val (  ) =
prerrsln("tr3cenv_t3apq_resolve: dcls = ", dcls)
*)
//
} (*where*)//end-of-[tr3cenv_t3apq_resolve(env0,...)]
//
(* ****** ****** *)
//
end(*loc*)//end-of-[local(implfun(tr3cenv_t3apq_resolve))]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XATSOPT_srcgen2_DATS_trtmp3c_utils0.dats] *)
(***********************************************************************)
