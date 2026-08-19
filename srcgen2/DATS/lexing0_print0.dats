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
Start Time: June 07th, 2022
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
#staload "./../SATS/lexing0.sats"
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
//<>(*tmp*)
token_fprint
( tok, out ) =
(
tnode_fprint(tok.node(), out)
)(*end-of-[token_fprint(...)]*)
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
//<>(*tmp*)
tnode_fprint
( tnd, out ) =
(
case+ tnd of
//
|
T_EOF() => print("T_EOF")
|
T_ERR() => print("T_ERR")
//
|
T_EOL() => print("T_EOL")
//
|
T_BLANK(rep) =>
(print("T_BLANK("); print(rep); print(")"))
|
T_CLNLT(rep) =>
(print("T_CLNLT("); print(rep); print(")"))
|
T_DOTLT(rep) =>
(print("T_DOTLT("); print(rep); print(")"))
//
|
T_SPCHR(rep) =>
(print("T_SPCHR("); print(rep); print(")"))
//
|
T_IDENT(rep) =>
(print("T_IDENT("); print(rep); print(")"))
|
T_IDALP(rep) =>
(print("T_IDALP("); print(rep); print(")"))
|
T_IDSYM(rep) =>
(print("T_IDSYM("); print(rep); print(")"))
//
|
T_IDDLR(rep) =>
(print("T_IDDLR("); print(rep); print(")"))
|
T_IDSRP(rep) =>
(print("T_IDSRP("); print(rep); print(")"))
//
|
T_IDQUA(rep) =>
(print("T_IDQUA("); print(rep); print(")"))
//
|
T_INT01(rep) =>
(print("T_INT01("); print(rep); print(")"))
|
T_INT02(bas, rep) =>
(print("T_INT02("); print(bas); print(";"); print(rep); print(")"))
|
T_INT03(bas, rep, sfx) =>
(print("T_INT03("); print(bas); print(";"); print(rep); print(";"); print(sfx); print(")"))
//
|
T_FLT01(rep) =>
(print("T_FLT01("); print(rep); print(")"))
|
T_FLT02(bas, rep) =>
(print("T_FLT02("); print(bas); print(";"); print(rep); print(")"))
|
T_FLT03(bas, rep, sfx) =>
(print("T_FLT03("); print(bas); print(";"); print(rep); print(";"); print(sfx); print(")"))
//
|
T_CHAR1_nil0(rep) =>
(print("T_CHAR1_nil0("); print(rep); print(")"))
|
T_CHAR2_char(rep) =>
(print("T_CHAR2_char("); print(rep); print(")"))
|
T_CHAR3_blsh(rep) =>
(print("T_CHAR3_blsh("); print(rep); print(")"))
//
|
T_STRN1_clsd(rep, len) =>
let
#impltmp
g_print<strn> = my_strn_print
in//let
(print("T_STRN1_clsd("); print(rep); print(";"); print(len); print(")"))
end//let//endof[T_STRN1_clsd(rep,len)]
|
T_STRN2_ncls(rep, len) =>
let
#impltmp
g_print<strn> = my_strn_print
in//let
(print("T_STRN2_ncls("); print(rep); print(";"); print(len); print(")"))
end//let//endof[T_STRN2_clsd(rep,len)]
//
|
T_CMNT1_line(ag1, ag2) =>
(print("T_CMNT1_line("); print(ag1); print(";"); print(ag2); print(")"))
|
T_CMNT2_rest(ag1, ag2) =>
(print("T_CMNT2_rest("); print(ag1); print(";"); print(ag2); print(")"))
|
T_CMNT3_ccbl(lvl, rep) =>
(print("T_CMNT3_ccbl("); print(lvl); print(";"); print(rep); print(")"))
|
T_CMNT4_mlbl(lvl, rep) =>
(print("T_CMNT4_mlbl("); print(lvl); print(";"); print(rep); print(")"))
//
(*
HX-2022-06-15:
The rest for secondary tokens that are
generated from the primary ones (that are
obtained directly from lexing some source)
*)
//
|T_AT0() =>
(print("T_AT0("); print(")"))
|T_BAR() =>
(print("T_BAR("); print(")"))
|T_CLN() =>
(print("T_CLN("); print(")"))
|T_DOT() =>
(print("T_DOT("); print(")"))
//
|T_EQ0() =>
(print("T_EQ0("); print(")"))
|T_LT0() =>
(print("T_LT0("); print(")"))
|T_GT0() =>
(print("T_GT0("); print(")"))
//
|T_DLR() =>
(print("T_DLR("); print(")"))
|T_SRP() =>
(print("T_SRP("); print(")"))
//
|T_EQLT() =>
(print("T_EQLT("); print(")"))
|T_EQGT() =>
(print("T_EQGT("); print(")"))
//
|T_LTGT() =>
(print("T_LTGT("); print(")"))
|T_GTLT() =>
(print("T_GTLT("); print(")"))
|T_MSLT() =>
(print("T_MSLT("); print(")"))
|T_MSGT() =>
(print("T_MSGT("); print(")"))
//
|T_GTDOT() =>
(print("T_GTDOT("); print(")"))
//
|T_COMMA() =>
(print("T_COMMA("); print(")"))
|T_SMCLN() =>
(print("T_SMCLN("); print(")"))
//
|T_BSLSH() =>
(print("T_BSLSH("); print(")"))
//
|T_LPAREN() =>
(
 (print("T_LPAREN("); print(")")))
|T_RPAREN() =>
(
 (print("T_RPAREN("); print(")")))
//
|T_LBRCKT() =>
(
 (print("T_LBRCKT("); print(")")))
|T_RBRCKT() =>
(
 (print("T_RBRCKT("); print(")")))
//
|T_LBRACE() =>
(
 (print("T_LBRACE("); print(")")))
|T_RBRACE() =>
(
 (print("T_RBRACE("); print(")")))
//
|
T_EXISTS(knd) =>
(print("T_EXISTS("); print(knd); print(")"))
//
|
T_TRCD10(knd) =>
(print("T_TRCD10("); print(knd); print(")"))
|
T_TRCD20(knd) =>
(print("T_TRCD20("); print(knd); print(")"))
//
|
T_AS0() =>
(print("T_AS0("); print(")"))
|
T_OF0() =>
(print("T_OF0("); print(")"))
//
|
T_OP1() =>
(print("T_OP1("); print(")"))
|
T_OP2(tok) =>
(print("T_OP2("); print(tok); print(")"))
|
T_OP3(tok) =>
(print("T_OP3("); print(tok); print(")"))
//
|
T_IN0() =>
(print("T_IN0("); print(")"))
//
|
T_AND() =>
(print("T_AND("); print(")"))
|
T_END() =>
(print("T_END("); print(")"))
//
|
T_IF0() =>
(print("T_IF0("); print(")"))
|
T_SIF() =>
(print("T_SIF("); print(")"))
//
|
T_THEN() =>
(print("T_THEN("); print(")"))
|
T_ELSE() =>
(print("T_ELSE("); print(")"))
//
|
T_WHEN() =>
(print("T_WHEN("); print(")"))
|
T_WITH() =>
(print("T_WITH("); print(")"))
//
|
T_SCAS() =>
(print("T_SCAS("); print(")"))
|
T_CASE(csk) =>
(print("T_CASE("); print(csk); print(")"))
//
|
T_ENDST() =>
(print("T_ENDST("); print(")"))
//
|
T_LAM(knd) =>
(print("T_LAM("); print(knd); print(")"))
|
T_FIX(knd) =>
(print("T_FIX("); print(knd); print(")"))
//
|
T_LET() =>
(print("T_LET("); print(")"))
|
T_TRY() =>
(print("T_TRY("); print(")"))
|
T_WHERE() =>
(print("T_WHERE("); print(")"))
//
|
T_LOCAL() =>
(print("T_LOCAL("); print(")"))
//
|
T_ENDIF0() =>
(print("T_ENDIF0("); print(")"))
|
T_ENDCAS() =>
(print("T_ENDCAS("); print(")"))
|
T_ENDLAM() =>
(print("T_ENDLAM("); print(")"))
|
T_ENDFIX() =>
(print("T_ENDFIX("); print(")"))
|
T_ENDLET() =>
(print("T_ENDLET("); print(")"))
|
T_ENDWHR() =>
(print("T_ENDWHR("); print(")"))
|
T_ENDLOC() =>
(print("T_ENDLOC("); print(")"))
|
T_ENDTRY() =>
(print("T_ENDTRY("); print(")"))
//
|
T_VAL(vlk) =>
(print("T_VAL("); print(vlk); print(")"))
|
T_VAR(vlk) =>
(print("T_VAR("); print(vlk); print(")"))
|
T_FUN(fnk) =>
(print("T_FUN("); print(fnk); print(")"))
//
|
T_IMPLMNT(knd) =>
(print("T_IMPLMNT("); print(knd); print(")"))
//
|
T_STACST0() =>
(print("T_STACST0("); print(")"))
//
|
T_ABSSORT() =>
(print("T_ABSSORT("); print(")"))
|
T_SORTDEF() =>
(print("T_SORTDEF("); print(")"))
|
T_SEXPDEF(knd) =>
(print("T_SEXPDEF("); print(knd); print(")"))
//
|
T_ABSIMPL() =>
(print("T_ABSIMPL("); print(")"))
|
T_ABSOPEN() =>
(print("T_ABSOPEN("); print(")"))
|
T_ABSTYPE(knd) =>
(print("T_ABSTYPE("); print(knd); print(")"))
//
|
T_DATASORT() =>
(print("T_DATASORT("); print(")"))
//
|
T_EXCPTCON() =>
(print("T_EXCPTCON("); print(")"))
//
|
T_DATATYPE(knd) =>
(print("T_DATATYPE("); print(knd); print(")"))
|
T_WITHTYPE(knd) =>
(print("T_WITHTYPE("); print(knd); print(")"))
//
|
T_DLR_RAISE() =>
(print("T_DLR_RAISE("); print(")"))
//
|
T_DLR_EXTNAM() =>
(print("T_DLR_EXTNAM("); print(")"))
|
T_DLR_EXISTS() =>
(print("T_DLR_EXISTS("); print(")"))
//
(* ****** ****** *)
|
T_DLR_SYNEXT() =>
(print("T_DLR_SYNEXT("); print(")"))
//
(* ****** ****** *)
//
|T_SRP_THEN0() =>
(
(print("T_SRP_THEN0("); print(")")))
|T_SRP_ELSE1() =>
(
(print("T_SRP_ELSE1("); print(")")))
|T_SRP_ENDIF() =>
(
(print("T_SRP_ENDIF("); print(")")))
|T_SRP_IFEXP() =>
(
(print("T_SRP_IFEXP("); print(")")))
|T_SRP_ELSIF() =>
(
(print("T_SRP_ELSIF("); print(")")))
//
(* ****** ****** *)
//
|
T_SRP_NONFIX() =>
(
(print("T_SRP_NONFIX("); print(")")))
|
T_SRP_FIXITY(knd) =>
(print("T_SRP_FIXITY("); print(knd); print(")"))
//
(* ****** ****** *)
//
|T_SRP_STATIC() =>
(
(print("T_SRP_STATIC("); print(")")))
|T_SRP_EXTERN() =>
(
(print("T_SRP_EXTERN("); print(")")))
|T_SRP_STAVAL() =>
(
(print("T_SRP_STAVAL("); print(")")))
|T_SRP_EXTVAL() =>
(
(print("T_SRP_EXTVAL("); print(")")))
//
(* ****** ****** *)
//
|T_SRP_DEFINE() =>
(
(print("T_SRP_DEFINE("); print(")")))
|T_SRP_MACDEF() =>
(
(print("T_SRP_MACDEF("); print(")")))
//
(* ****** ****** *)
//
|
T_SRP_SYMLOAD() =>
(print("T_SRP_SYMLOAD("); print(")"))
//
|
T_SRP_STALOAD() =>
(print("T_SRP_STALOAD("); print(")"))
//
|
T_SRP_DYNINIT() =>
(print("T_SRP_DYNINIT("); print(")"))
(*
|
T_SRP_DYNXGEN() =>
prints("T_SRP_DYNXGEN(", ")")
*)
//
|
T_SRP_INCLUDE() =>
(print("T_SRP_INCLUDE("); print(")"))
(*
|
T_SRP_INPASTE() =>
prints("T_SRP_INPASTE(", ")")
*)
//
|
T_SRP_EXTCODE() =>
(print("T_SRP_EXTCODE("); print(")"))
//
(* ****** ****** *)
//
) where
{
//
#impltmp
g_print$out
< (*nil*) >((*void*)) = out
//
} where
{
//
fun
my_strn_print
(rep: strn): void =
let
//
val n0 =
strn_length(rep)
//
fnx
loop1
(i0: nint): void =
if
(i0 >= n0)
then ((*0*)) else
let
//
  val c0 = rep[i0]
//
in//let
//
if
(c0 = '\\')
then loop2(i0+1) else
(
char_fprint
(c0 , out ); loop1(i0+1))
end//let//end-of-[loop1(i0)]
//
and
loop2
(i1: nint): void =
if
(i1 >= n0)
then
(
char_fprint
('\\', out)) else
let
  val c1 = rep[i1]
in (*let*)
if
(c1 = '\n')
then loop1(i1+1) else
(
char_fprint
('\\', out);
char_fprint
( c1 , out); loop1(i1+1))
end//let//end-of-[loop1(i1)]
//
in
  let val i0 = 0 in loop1(i0) end
end(*let*)//end-of-(my_strn_print(rep))
//
}(*where*)//end-of(tnode_fprint(node,out))
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XATSOPT_srcgen2_DATS_lexing0_print0.dats] *)
(***********************************************************************)
