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
(*
HX: Implementation in ATS3
*)
(* ****** ****** *)
//
// Author: Hongwei Xi
(*
Mon 11 Mar 2024 02:29:52 PM EDT
*)
// Authoremail: gmhwxiATgmailDOTcom
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
"share/atspre_staload.hats"
#staload
UN = "prelude/SATS/unsafe.sats"
//
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../..\
/HATS/xatsopt_dats.hats"
(* ****** ****** *)
#include
"./../HATS/xats2js_dats.hats"
(* ****** ****** *)
#staload
"./../../../SATS/xbasics.sats"
(* ****** ****** *)
#staload "./../SATS/intrep0.sats"
(* ****** ****** *)
#symload lctn with i0pat_get_lctn
#symload node with i0pat_get_node
(* ****** ****** *)
#symload lctn with i0exp_get_lctn
#symload node with i0exp_get_node
(* ****** ****** *)
#symload lctn with i0dcl_get_lctn
#symload node with i0dcl_get_node
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0pat_fprint
(out, i0p0) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
i0p0.node() of
//
|I0Pint(tok) =>
print("I0Pint(",tok,")")
|I0Pbtf(sym) =>
print("I0Pbtf(",sym,")")
|I0Pchr(tok) =>
print("I0Pchr(",tok,")")
|I0Pstr(tok) =>
print("I0Pstr(",tok,")")
//
|I0Pnone0() => print( "I0Pnone0(",")" )
|I0Pnone1(d3p1) => print("I0Pnone1(", d3p1, ")")
//
end(*let*)//end-of-[i0pat_fprint(out, i0p0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0exp_fprint
(out, i0e0) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
i0e0.node() of
//
|I0Evar(d2v) =>
(
 print("I0Evar(", d2v, ")"))
//
|I0Eint(int) =>
(
 print("I0Eint(", int, ")"))
|I0Ebtf(btf) =>
(
 print("I0Ebtf(", btf, ")"))
|I0Echr(chr) =>
(
 print("I0Echr(", chr, ")"))
|I0Estr(str) =>
(
 print("I0Estr(", str, ")"))
//
(* ****** ****** *)
//
|I0Elet0
( dcls, i0e1) =>
print("I0Elet0(", dcls, ";", i0e1, ")")
//
(* ****** ****** *)
//
|I0Enone0() => print( "I0Enone0(",")" )
|I0Enone1(d3e1) => print("I0Enone1(", d3e1, ")")
//
end(*let*)//end-of-[i0exp_fprint(out, i0e0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i0dcl_fprint
(out, dcl0) =
let
#impltmp
g_print$out<>() = out
in//let
//
case+
dcl0.node() of
//
|I0Dd3ecl
(  d3cl  ) =>
print("I0Dd3ecl(", d3cl, ")")
//
|I0Dlocal0
(head, body) =>
print
("I0Dlocal0(", head, ";", body, ")")
//
|I0Dnone0() => print( "I0Dnone0(",")" )
|I0Dnone1(d3cl) => print("I0Dnone1(", d3cl, ")")
//
end(*let*)//end-of-[i0dcl_fprint(out, dcl0)]
//
(* ****** ****** *)
(* ****** ****** *)

(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2js_srcgen1_DATS_intrep0_print0.sats] *)
(***********************************************************************)