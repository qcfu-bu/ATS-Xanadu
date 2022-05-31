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
// Author: Hongwei Xi
// Start Time: May 28th, 2022
// Authoremail: gmhwxiATgmailDOTcom
//
(* ****** ****** *)
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
#typedef int0 = sint
#typedef btf0 = bool
#typedef chr0 = char
#typedef str0 = string
(* ****** ****** *)
//
datatype funkind =
//
| FNKfn0 // nonrec fun
| FNKfn1 // genrec fun
| FNKfn2 // tailrec fun
| FNKfnx // tailopt fun
| FNKfun // ex-specified
//
| FNKpraxi // proof axiom
//
| FNKprfn0 // nonrec prfun
| FNKprfn1 // genrec prfun
| FNKprfun // ex-specified
//
| FNKfcast // no-op casting
//
(* ****** ****** *)

(* end of [xatsopt_xbasics.sats] *)