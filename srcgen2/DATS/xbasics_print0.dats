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
Start Time: May 28th, 2022
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
#include
"./../HATS/xatsopt_sats.hats"
#include
"./../HATS/xatsopt_dats.hats"
(* ****** ****** *)
#staload "./../SATS/xbasics.sats"
(* ****** ****** *)

#implfun
//<>(*tmp*)
dctkind_fprint
  (out, dck) =
(
case+ dck of
|
DCKfun() => print("DCKfun")
|
DCKval() => print("DCKval")
|
DCKpraxi() => print("DCKpraxi")
|
DCKprfun() => print("DCKprfun")
|
DCKprval() => print("DCKprval")
//
|
DCKfcast() => print("DCKfcast")
//
|
DCKnspec() => print("DCKnspec")
) where
{
  #impltmp g_print$out<>() = out
}(*where*)//end-of(dctkind_fprint)

(* ****** ****** *)

#implfun
//<>(*tmp*)
valkind_fprint
  (out, vlk) = let
//
#impltmp
g_print$out<>() = out
//
in//let
//
case+ vlk of
| VLKval() => print("VLKval")
//
| VLKvlp() => print("VLKvlp")
| VLKvln() => print("VLKvln")
//
| VLKprval() => print("VLKprval")
//
end(*let*)//end-of(valkind_fprint)

(* ****** ****** *)

#implfun
//<>(*tmp*)
funkind_fprint
  (out, fnk) = let
//
#impltmp
g_print$out<>() = out
//
in//let
//
case+ fnk of
| FNKfn0() => print("FNKfn0")
| FNKfn1() => print("FNKfn1")
| FNKfn2() => print("FNKfn2")
| FNKfnx() => print("FNKfnx")
| FNKfun() => print("FNKfun")
//
| FNKpraxi() => print("FNKpraxi")
//
| FNKprfn0() => print("FNKprfn0")
| FNKprfn1() => print("FNKprfn1")
| FNKprfun() => print("FNKprfun")
//
| FNKfcast() => print("FNKfcast")
//
end(*let*)//end-of(funkind_fprint)

(* ****** ****** *)
//
#impltmp
g_print
<dctkind>(dck) =
dctkind_fprint(g_print$out<>(), dck)
//
#impltmp
g_print
<valkind>(vlk) =
valkind_fprint(g_print$out<>(), vlk)
//
#impltmp
g_print
<funkind>(fnk) =
funkind_fprint(g_print$out<>(), fnk)
//
(* ****** ****** *)

(* end of [ATS3/XATSOPT_xbasics_print0.dats] *)
