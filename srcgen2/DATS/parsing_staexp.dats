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
Start Time: June 16th, 2022
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
#staload "./../SATS/locinfo.sats"
(* ****** ****** *)
#staload "./../SATS/lexing0.sats"
(* ****** ****** *)
#staload "./../SATS/staexp0.sats"
(* ****** ****** *)
#staload "./../SATS/parsing.sats"
(* ****** ****** *)
#symload
lctn with token_get_lctn//lexing0
#symload
lctn with i0dnt_get_lctn//staexp0
#symload
lctn with l0abl_get_lctn//staexp0
#symload
lctn with sort0_get_lctn//staexp0
#symload
lctn with s0exp_get_lctn//staexp0
(* ****** ****** *)
#symload
node with token_get_node//lexing0
#symload
node with i0dnt_get_node//staexp0
#symload
node with l0abl_get_node//staexp0
(* ****** ****** *)
#symload
tnode with token_get_node//lexing0
(* ****** ****** *)
#symload + with add_loctn_loctn//locinfo
(* ****** ****** *)
//
#extern
fun p1_sort0_tid: p1_fun(sort0)
#extern
fun p1_sort0_atm: p1_fun(sort0)
#extern
fun p1_sort0seq_atm: p1_fun(sort0lst)
#extern
fun p1_sort0seq_CMA: p1_fun(sort0lst)
//
(* ****** ****** *)
#extern
fun pq_sort0_anno: pq_fun(sort0)
(* ****** ****** *)
#extern
fun p1_s0arg: p1_fun(s0arg)
#extern
fun p1_s0mag: p1_fun(s0mag)
#extern
fun p1_t0mag: p1_fun(t0mag)
(* ****** ****** *)
#extern
fun p1_s0argseq: p1_fun(s0arglst)
#extern
fun p1_s0magseq: p1_fun(s0maglst)
#extern
fun p1_t0magseq: p1_fun(t0maglst)
(* ****** ****** *)
#extern
fun p1_s0qua: p1_fun(s0qua)
(* ****** ****** *)
#extern
fun
p1_s0quaseq_BARSMCLN: p1_fun(s0qualst)
(* ****** ****** *)
//
#extern
fun p1_l0s0e: p1_fun(l0s0e)
//
#extern
fun p1_s0exp_atm: p1_fun(s0exp)
#extern
fun p1_s0expseq_atm: p1_fun(s0explst)
#extern
fun p1_s0expseq_CMA: p1_fun(s0explst)
//
#extern
fun p1_l0s0eseq_CMA: p1_fun(l0s0elst)
//
(* ****** ****** *)
//
#extern
fun
p1_s0exp_RPAREN: p1_fun(s0exp_RPAREN)
#extern
fun
p1_l0s0e_RBRACE: p1_fun(l0s0e_RBRACE)
//
#extern
fun
s0exp_RPAREN_lctn:(s0exp_RPAREN)->loc_t
#extern
fun
l0s0e_RBRACE_lctn:(l0s0e_RBRACE)->loc_t
//
(* ****** ****** *)

#implfun
p1_t0int(buf, err) =
let
val tok = buf.getk0()
val tnd = token_get_node(tok)
in//let
//
if
t0_t0int(tnd)
then
( buf.skip1()
; T0INTsome(tok)) else T0INTnone(tok)
//
end(*let*)//end-of-[p1_t0int(buf,err)]

(* ****** ****** *)

#implfun
p1_t0chr(buf, err) =
let
val tok = buf.getk0()
val tnd = token_get_node(tok)
in//let
//
if
t0_t0chr(tnd)
then
( buf.skip1()
; T0CHRsome(tok)) else T0CHRnone(tok)
//
end(*let*)//end-of-[p1_t0chr(buf,err)]

(* ****** ****** *)

#implfun
p1_t0flt(buf, err) =
let
val tok = buf.getk0()
val tnd = token_get_node(tok)
in//let
//
if
t0_t0flt(tnd)
then
( buf.skip1()
; T0FLTsome(tok)) else T0FLTnone(tok)
//
end(*let*)//end-of-[p1_t0flt(buf,err)]

(* ****** ****** *)

#implfun
p1_t0str(buf, err) =
let
val tok = buf.getk0()
val tnd = token_get_node(tok)
in//let
//
if
t0_t0str(tnd)
then
( buf.skip1()
; T0STRsome(tok)) else T0STRnone(tok)
//
end(*let*)//end-of-[p1_t0str(buf,err)]

(* ****** ****** *)

#implfun
p1_s0tid(buf, err) =
let
//
val e00 = err
val tok = buf.getk0()
//
in//let
//
case+
tok.node() of
//
|
T_IDALP _ =>
(buf.skip1(); i0dnt_some(tok))
|
T_IDSYM _ =>
(buf.skip1(); i0dnt_some(tok))
//
|
T_BSLSH _ =>
(buf.skip1(); i0dnt_some(tok))
//
|
_(*non-IDENT*) =>
(err := e00+1; i0dnt_none(tok))
//
end // end-of-let // end of [p1_s0tid]

(* ****** ****** *)

#implfun
p1_s0eid(buf, err) =
let
//
val e00 = err
val tok = buf.getk0()
val tnd = tok.tnode()
//
in//let
//
case+ tnd of
//
|
T_IDALP _ =>
(buf.skip1(); i0dnt_some(tok))
|
T_IDSYM _ =>
(buf.skip1(); i0dnt_some(tok))
|
T_IDDLR _ =>
(buf.skip1(); i0dnt_some(tok))
//
| T_AT0() =>
( buf.skip1()
; i0dnt_some(tok)) where
{
  val loc = tok.lctn((*void*))
  val tnd = T0IDENT_AT0(*void*)
  val tok = token_make_node(loc, tnd)
}
//
| T_EQ0() =>
( buf.skip1()
; i0dnt_some(tok)) where
{
  val loc = tok.lctn((*void*))
  val tnd = T0IDENT_EQ0(*void*)
  val tok = token_make_node(loc, tnd)
}
//
| T_LT0() =>
( buf.skip1()
; i0dnt_some(tok)) where
{
  val loc = tok.lctn((*void*))
  val tnd = T0IDENT_LT0(*void*)
  val tok = token_make_node(loc, tnd)
}
| T_GT0() =>
( buf.skip1()
; i0dnt_some(tok)) where
{
  val loc = tok.lctn((*void*))
  val tnd = T0IDENT_GT0(*void*)
  val tok = token_make_node(loc, tnd)
}
//
| T_LTGT() =>
( buf.skip1()
; i0dnt_some(tok)) where
{
  val loc = tok.lctn((*void*))
  val tnd = T0IDENT_LTGT(*void*)
  val tok = token_make_node(loc, tnd)
}
//
|
T_BSLSH() =>
( buf.skip1(); i0dnt_some(tok) )
//
|
_(*non-IDENT*) => (err := e00+1; i0dnt_none(tok))
//
end (*let*) // end of [p1_s0eid(buf, err)]

(* ****** ****** *)

#implfun
p1_i0dnt(buf, err) =
let
//
val e00 = err
val tok = buf.getk0()
val tnd = tok.tnode()
//
in//let
//
case+
tok.tnode() of
//
| _
when
t0_s0eid(tnd) => p1_s0eid(buf, err)
//
| _
when
t0_d0eid(tnd) => p1_d0eid(buf, err)
//
|
_(*non-i0dnt*) => (err := e00+1; i0dnt_none(tok))
//
end (*let*) // end of [p1_i0dnt(buf,err)]

(* ****** ****** *)

#implfun
p1_l0abl(buf, err) =
let
//
val e00 = err
val tok = buf.getk0()
val tnd = tok.tnode()
//
(*
val ( ) =
prerrln("p1_l0abl: tok = ", tok)
*)
//
in
//
case+ tnd of
|
T_INT01 _ =>
(
buf.skip1(); l0abl_make_int1(tok)
)
|
T_IDALP _ =>
(
buf.skip1(); l0abl_make_name(tok)
)
|
_(*non-INT-IDENT*) =>
(
  err := e00 + 1; l0abl_make_none(tok)
) (* end of [non-INT-IDALP] *)
//
end (*let*) // end of [p1_l0abl(buf,err)]

(* ****** ****** *)
//
(*
idsort0::
  | s0tid
//
atmsort0::
//
  | s0tid
  | qualid atmsort0
  | ( sort0seq_COMMA )
//
atmsort0seq::
  | {atmsort0}+
//
sort0seq_COMMA::
  | sort0, ... , sort0
//
*)
//
(* ****** ****** *)

local
//
fun
p1_napps
( buf: !tkbf0
, err: &int >> _): sort0 =
let
  val e00 = err
  val tok = buf.getk0()
in
err := e00 + 1;
sort0(tok.lctn(),S0Ttkerr(tok))
end (*let*) // end of [p1_napps]
//
in//local

(* ****** ****** *)

#implfun
p1_sort0(buf, err) =
let
//
val s0ts =
p1_sort0seq_atm(buf, err)
//
in//let
//
case+ s0ts of
|
list_nil
((*void*)) =>
p1_napps(buf, err)
|
list_cons
(s0t0, sts1) =>
(
case+ sts1 of
|
list_nil() => s0t0
|
list_cons _ =>
let
  val loc0 =
  s0t0.lctn()+s0t1.lctn()
in
  sort0(loc0, S0Tapps(s0ts))
end where
{
val s0t1 =
gseq_last_ini<sort0lst><sort0>(sts1, s0t0)
} (*where*) // end of [list_cons]
)
//
end(*let*)//end-of-[p1_sort0(buf,err)]

(* ****** ****** *)

#implfun
p1_sort0_tid
  (buf, err) = let
//
val e00 = err
val tok = buf.getk0()
val tnd = tok.tnode()
//
(*
val () =
println!
("p1_sort0_tid: e00 = ", e00)
val () =
println!
("p1_sort0_tid: tok = ", tok)
*)
//
in//let
//
case+ tnd of
//
| _
when
t0_s0tid(tnd) =>
let
val id0 = p1_s0tid(buf, err)
in//let
err := e00;
sort0(id0.lctn(), S0Tid0(id0))
end (*let*) // end of [t_s0tid]
| _
(*otherwise*) =>
let
  val () = (err := e00 + 1)
in//let
  sort0(tok.lctn(), S0Ttkerr(tok))
endlet(*HX:this-is-a-case-of-error*)
//
end (*let*) // end of [p1_sort0_tid]

(* ****** ****** *)

#implfun
p1_sort0_atm
  (buf, err) = let
//
val e00 = err
val tok = buf.getk0()
val tnd = tok.tnode()
//
(*
val () =
println!
("p1_sort0_atm: e00 = ", e00)
val () =
println!
("p1_sort0_atm: tok = ", tok)
*)
//
in
//
case+ tnd of
//
| _
when t0_s0tid(tnd) =>
let
  val id0 = p1_s0tid(buf, err)
in
  err := e00
; sort0(id0.lctn(), S0Tid0(id0))
end (*let*) // end of [t_s0tid]
//
| _
when t0_t0int(tnd) =>
let
  val i00 = p1_t0int(buf, err)
in
  err := e00
; sort0(i00.lctn(), S0Tint(i00))
end (*let*) // end of [t_t0int]
|
T_LPAREN() =>
let
val tbeg = tok
val (  ) = buf.skip1()
val s0ts =
p1_sort0seq_CMA(buf, err)
val tend = p1_RPAREN(buf, err)
val loc0 = tbeg.lctn()+tend.lctn()
in
  err := e00
; sort0
  (loc0,S0Tlpar(tbeg, s0ts, tend))
end (*let*) // end of [T_LPAREN]
//
|
T_IDQUA(qid) =>
let
val tqua = tok
val (  ) = buf.skip1()
val s0t0 = p1_sort0_atm(buf, err)
val loc0 = tqua.lctn()+s0t0.lctn()
in//let
  err := e00
; sort0(loc0, S0Tqid(tqua, s0t0))
end (*let*) // end of [ T_IDQUA ]
//
| _ (* error *) =>
let
  val () = (err := e00 + 1)
in//let
  sort0(tok.lctn(), S0Ttkerr(tok))
endlet // HX:this-is-a-case-of-error
//
end (*let*) // end of [ p1_sort0_atm ]
//
(* ****** ****** *)
//
#implfun
p1_sort0seq_atm
(  buf, err  ) =
list_vt2t
(
ps_p1fun{sort0}(buf, err, p1_sort0_atm)
)
#implfun
p1_sort0seq_CMA
(  buf, err  ) =
list_vt2t
(
ps_COMMA_p1fun{sort0}(buf, err, p1_sort0)
)
//
(* ****** ****** *)

endloc (*local*) // end of [local(p1_sort0)]

(* ****** ****** *)
fun
s0exp_anno_opt
( s0e: s0exp
, opt: sort0opt): s0exp =
(
case+ opt of
|
optn_nil() => s0e
|
optn_cons(s0t) =>
let
val loc =
s0e.lctn()+s0t.lctn()
in
s0exp(loc, S0Eanno(s0e, s0t))
end
) (*case*)//end(s0exp_anno_opt)
(* ****** ****** *)

local
//
fun
p1_napps
( buf: !tkbf0
, err: &int >> _): s0exp =
let
//
val e00 = err
val tok = buf.getk0()
val tnd = tok.tnode()
//
in//let
//
case+ tnd of
|
T_LAM(k0) =>
let
val tok0 = tok
val (  ) = buf.skip1()
val s0ms = p1_s0magseq(buf, err)
val anno = pq_sort0_anno(buf, err)
val tok1 = p1_EQGT(buf, err)
val s0e0 = p1_s0exp(buf, err)
val opt2 = pq_ENDLAM(buf, err)
val lres =
(
case+ opt2 of
|
optn_nil() =>
tok0.lctn() + s0e0.lctn()
|
optn_cons(tok2) =>
tok0.lctn() + tok2.lctn()): loc_t
//
in//let
err := e00;
s0exp
(lres
,S0Elam0(tok0, s0ms, anno, tok1, s0e0, opt2))
end (*let*) // end of [T_LAM(k0)]
//
|
_(*non-T_LAM*) =>
(err := e00 + 1; s0exp(tok.lctn(), S0Etkerr(tok)))
//
end (*let*) // end of [p1_napps(buf,err)]
//
in//local

(* ****** ****** *)

#implfun
p1_s0exp(buf, err) =
let
//
val e00 = err
//
val s0es =
p1_s0expseq_atm(buf, err)
//
in//let
//
case+ s0es of
|
list_nil() =>
p1_napps(buf, err)
|
list_cons
(s0e1, ses1) =>
let
val opt =
pq_sort0_anno(buf, err)
in//let
case+ ses1 of
|
list_nil _ =>
(
  s0exp_anno_opt(s0e1, opt)
)
|
list_cons _ =>
(
  s0exp_anno_opt(s0e0, opt)
) where
{
  val s0e2 = list_last(ses1)
  val loc0 = s0e1.lctn()+s0e2.lctn()
  val s0e0 = s0exp(loc0, S0Eapps(ses1))
} (*where*) // end of [list_cons]
end (*let*) // end of [list_cons]
end (*let*) // end of [p1_s0exp(buf,err)]

(* ****** ****** *)

#implfun
p1_l0s0e(buf, err) =
let
//
val e00 = err
//
val lab =
p1_l0abl(buf, err)
val tok = p1_EQ0(buf, err)
val s0e = p1_s0exp(buf, err)
//
(*
val ((*void*)) =
println! ("p1_l0s0e: lab = ", lab)
val ((*void*)) =
println! ("p1_l0s0e: tok = ", tok)
val ((*void*)) =
println! ("p1_l0s0e: s0e = ", s0e)
*)
//
in
  (err := e00; S0LAB(lab, tok, s0e))
end (*let*) // end of [p1_l0s0e(buf,err)]

(* ****** ****** *)

#implfun
p1_s0exp_atm(buf, err) =
let
//
val e00 = err
val tok = buf.getk0()
val tnd = tok.tnode()
//
in//let
//
case+ tnd of
//
| _
when t0_s0eid(tnd) =>
let
  val id0 = p1_s0eid(buf, err)
in
  err := e00
; s0exp(id0.lctn(), S0Eid0(id0))
end (*let*) // end of [t_s0eid]
//
| _
when t0_t0int(tnd) =>
let
  val i00 = p1_t0int(buf, err)
in
  err := e00
; s0exp(i00.lctn(), S0Eint(i00))
end (*let*) // end of [t_t0int]
| _
when t0_t0chr(tnd) =>
let
  val c00 = p1_t0chr(buf, err)
in
  err := e00
; s0exp(c00.lctn(), S0Echr(c00))
end (*let*) // end of [t_t0chr]
| _
when t0_t0flt(tnd) =>
let
  val f00 = p1_t0flt(buf, err)
in
  err := e00
; s0exp(f00.lctn(), S0Eflt(f00))
end (*let*) // end of [t_t0flt]
| _
when t0_t0str(tnd) =>
let
  val s00 = p1_t0str(buf, err)
in
  err := e00
; s0exp(s00.lctn(), S0Estr(s00))
end (*let*) // end of [t_t0str]
//
|
T_OP1 _ =>
let
val tok0 = tok
val (  ) = buf.skip1()
in//let
  s0exp(tok0.lctn(), S0Eop1(tok0))
end (*let*) // end of [T_OP1(sym)]
|
T_OP2 _ =>
let
  val tbeg = tok
  val (  ) = buf.skip1()
  val opid = p1_s0eid(buf, err)
  val tend = p1_RPAREN(buf, err)
  val lres = tbeg.lctn()+tend.lctn()
in
  err := e00
; s0exp(lres, S0Eop2(tbeg, opid, tend))
end (*let*) // end of [T_OP2(par)]
//
|
T_MSLT() =>
let
  val tbeg = tok
  val (  ) = buf.skip1()
  val s0es =
  list_vt2t
  (
  ps_COMMA_p1fun{s0exp}
  (buf, err, p1_s0exp_app_NGT)
  )
  val tend = p1_GT0(buf, err)
  val lres = tbeg.lctn() + tend.lctn()
in
  err := e00
; s0exp(lres, S0Efimp(tbeg, s0es, tend))
end (*let*) // end of [ -< ... > ]
//
|
T_LBRACE() =>
let
val tbeg = tok
val (  ) = buf.skip1()
val s0qs =
p1_s0quaseq_BARSMCLN(buf, err)
val tend = p1_RBRACE(buf, err)
val lres = tbeg.lctn() + tend.lctn()
in//let
  err := e00
; s0exp(lres, S0Euni0(tbeg, s0qs, tend))
end (*let*) // end of [ { ... } ]
//
|
T_LBRCKT() =>
let
val tok0 = tok
val (  ) = buf.skip1()
val s0qs =
p1_s0quaseq_BARSMCLN(buf, err)
val tbeg =
token(tok0.lctn(),T_EXISTS(0))
val tend = p1_RBRCKT(buf, err)
val lres = tbeg.lctn() + tend.lctn()
in//let
  err := e00
; s0exp(lres, S0Eexi0(tbeg, s0qs, tend))
end (*let*) // end of [ [ ... ] ]
|
T_EXISTS(k0) =>
let
val tbeg = tok
val () = buf.skip1()
val s0qs =
p1_s0quaseq_BARSMCLN(buf, err)
val tend = p1_RBRCKT(buf, err)
val lres = tbeg.lctn() + tend.lctn()
in//let
  err := e00
; s0exp(lres, S0Eexi0(tbeg, s0qs, tend))
end (*let*) // end of [ #[ ... ] ]
//
|
T_IDQUA(qid) =>
let
val tqua = tok
val (  ) = buf.skip1()
val s0e0 = p1_s0exp_atm(buf, err)
val loc0 = tqua.lctn()+s0e0.lctn()
in//let
  err := e00; s0exp(loc0, S0Equal(tqua, s0e0))
end (*let*) // end of [T_IDQUA(qid)]
//
|
T_LPAREN() =>
let
val tbeg = tok
val (  ) = buf.skip1()
val s0es = p1_s0expseq_CMA(buf, err)
val tend = p1_s0exp_RPAREN(buf, err)
val lres =
tbeg.lctn() + s0exp_RPAREN_lctn(tend)
in//let
  err := e00
; s0exp(lres, S0Elpar(tbeg, s0es, tend))
end (*let*) // end of [ ( ... ) ]
//
|
T_TRCD10(k0) =>
let
val tbeg = tok
val () = buf.skip1()
val topt =
(
if
(k0 <= 1)
then optn_nil()
else optn_cons(p1_LPAREN(buf, err))
) : tokenopt // end-of(val)
//
val s0es = p1_s0expseq_CMA(buf, err)
val tend = p1_s0exp_RPAREN(buf, err)
//
val lres =
(tbeg.lctn()+s0exp_RPAREN_lctn(tend))
//
in//let
  err := e00
; s0exp(lres, S0Etup1(tbeg, topt, s0es, tend))
//
end (*let*) // end of [T_TRCD10(...|...)]
//
|
T_TRCD20(k0) =>
let
val tbeg = tok
val (  ) = buf.skip1()
val topt =
( if
(k0 <= 1)
then optn_nil()
else optn_cons(p1_LBRACE(buf, err))
) : tokenopt // end-of(val)
val lses = p1_l0s0eseq_CMA(buf, err)
val tend = p1_l0s0e_RBRACE(buf, err)
//
val lres =
(tbeg.lctn()+l0s0e_RBRACE_lctn(tend))
//
in//let
  err := e00
; s0exp(lres, S0Ercd2(tbeg, topt, lses, tend))
end (*let*) // end of [T_TRCD20{...|...}]
//
| _ (* error *) =>
(err := e00 + 1; s0exp(tok.lctn(), S0Etkerr(tok)))
//
end(*let*)//end-of-[p1_s0exp_atm(buf,err)]

(* ****** ****** *)
//
#implfun
p1_s0expseq_atm
(  buf, err  ) =
list_vt2t
(
ps_p1fun{s0exp}(buf, err, p1_s0exp_atm)
)
#implfun
p1_s0expseq_CMA
(  buf, err  ) =
list_vt2t
(
ps_COMMA_p1fun{s0exp}(buf, err, p1_s0exp)
)
#implfun
p1_l0s0eseq_CMA
(  buf, err  ) =
list_vt2t
(
ps_COMMA_p1fun{l0s0e}(buf, err, p1_l0s0e)
)
//
(* ****** ****** *)

endloc (*local*) // end of [local(p1_s0exp)]

(* ****** ****** *)

(* end of [ATS3/XATSOPT_parsing_staexp.dats] *)
