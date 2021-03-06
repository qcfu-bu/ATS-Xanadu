(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2019 Hongwei Xi, ATS Trustful Software, Inc.
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
// For casting of all sorts
//
(* ****** ****** *)
//
// Author: Hongwei Xi
// Start Time: October, 2019
// Authoremail: gmhwxiATgmailDOTcom
//
(* ****** ****** *)
//
castfn
cast{a0:t0}{a1:t0}(a0): (a1)
castfn
castlin{a0:vt}{a1:vt}(a0): (a1)
//
(* ****** ****** *)
//
castfn
optn_vt2t
{a:t0}{b:b0}
(xs: !optn_vt(a, b)): optn(a, b)
castfn
list_vt2t
{a:t0}{n:i0}
(xs: !list_vt(a, n)): list(a, n)
//
(* ****** ****** *)
//
fun
<a:vt>
p1tr_get(p0: p1tr): a
fun
<a:vt>
p1tr_set(p0: p1tr, x0: a): void
//
fun
<a:vt>
p2tr_get(p0: p2tr(a)): a
fun
<a:vt>
p2tr_set(p0: p2tr(a), x0: a): void
//
#symload ptr_get with p1tr_get
#symload ptr_set with p1tr_set
//
#symload ptr_get with p2tr_get
#symload ptr_set with p2tr_set
//
(* ****** ****** *)

fun
<x0:t0,xs:t0>
gseq_uncons(xs: &xs >> xs): x0

(* ****** ****** *)

(* end of [unsafe.sats] *)
