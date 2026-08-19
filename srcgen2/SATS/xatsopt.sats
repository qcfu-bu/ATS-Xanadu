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
Sat 15 Jul 2023 12:01:12 AM EDT
*)
Authoremail: gmhwxiATgmailDOTcom
*)
//
(* ****** ****** *)
(* ****** ****** *)
#staload
S0E = "./staexp0.sats"
#staload
S1E = "./staexp1.sats"
#staload
S2E = "./staexp2.sats"
#staload
T2P = "./statyp2.sats"
(* ****** ****** *)
#staload
D0E = "./dynexp0.sats"
#staload
D1E = "./dynexp1.sats"
#staload
D2E = "./dynexp2.sats"
#staload
D3E = "./dynexp3.sats"
(* ****** ****** *)
(* ****** ****** *)
#include
"./../HATS/xatsopt_sats.hats"
(* ****** ****** *)
(* ****** ****** *)
#define
ATS_PACKNAME
"ATS3.XANADU.xatsopt-20220500"
(* ****** ****** *)
(* ****** ****** *)
//
#absvwtp
argv_i0_vx(n:i0) <= p0tr
#vwtpdef
argv(n:i0) = argv_i0_vx(n:i0)
//
(* ****** ****** *)
//
#typedef d0parsed = $D0E.d0parsed
#typedef d1parsed = $D1E.d1parsed
#typedef d2parsed = $D2E.d2parsed
#typedef d3parsed = $D3E.d3parsed
//
(* ****** ****** *)
//
(*
HX-2025-04-21:
a flag of the form
--$(key)=$(val)
splits into ($(key), $(val))
*)
fun
xatsopt_flag$split
  (arg0: strn)
: optn_vt@(strn,optn_vt(strn))//fun
//
fun
xatsopt_flag$pvsadd0(arg0:strn):void
//
(* ****** ****** *)
//
(*
fun
xatsopt_main0
{n:int|n >= 1}
(argc: sint(n), argv: !argv(n)): void
*)
//
(* ****** ****** *)
//
(*
fun
echo_argc_argv
  {n:nat}
( out0: FILEref
, argc: sint(n), argv: !argv(n)): void
*)
//
(* ****** ****** *)
//
fun
xatsopt_version(): string
fun
xatsopt_fprint_version(out: FILEref): void
//
(* ****** ****** *)
//
fun
d2parsed_of_filsats(fpth: string): d2parsed
fun
d2parsed_of_fildats(fpth: string): d2parsed
//
fun
d2parsed_of_trans02(dpar: d0parsed): d2parsed
//
(* ****** ****** *)
//
fun
d3parsed_of_filsats(fpth: string): d3parsed
fun
d3parsed_of_fildats(fpth: string): d3parsed
//
fun
d3parsed_of_trans03(dpar: d0parsed): d3parsed
//
(* ****** ****** *)
//
fun
d3parsdz_of_filsats(fpth: string): d3parsed
fun
d3parsdz_of_fildats(fpth: string): d3parsed
//
fun
d3parsdz_of_trans03(dpar: d0parsed): d3parsed
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
HX-2026-06-25:
This one performs
(tread12+trans2a+trsym2b+t2read0)!
*)
//
fun
xatsopt_args$filxats_d2parsed
( args
: list(string), xats: sint, fpth: string): d2parsed
//
(* ****** ****** *)
//
(*
HX-2026-06-25:
This one performs (trans3a+tread3a)!
*)
fun
xatsopt_args$filxats_d3parsed
( args
: list(string), xats: sint, fpth: string): d3parsed
//
(*
HX-2026-06-25:
d3parsdz = d3parsed+trtmp3b/3c+t3read0
*)
fun
xatsopt_args$filxats_d3parsdz
( args
: list(string), xats: sint, fpth: string): d3parsed
//
(* ****** ****** *)
(* ****** ****** *)
//
//
(* ****** ****** *)
(*
CLAUDE-2026-08: CONCRETE printers for DIAGNOSTIC list/pair payloads (the
quantified prelude list/tuple print defaults are not instantiable by the
srcgen2 resolver; see DATS/xatsopt_utils0.dats for the implementations
and DATS/xatsopt_tmplib.dats for the g_print instances that route to
these).  Same bytes as the resolved generics on the jsemit00 path:
$list(e1,e2,...) and @(a,b) and S2LAB(l;t).
*)
(* ****** ****** *)
//
fun
zzel_fprint_l2t2p($T2P.l2t2p, FILR): void
fun
zzel_fprint_s2vtp($T2P.s2vtp, FILR): void
//
fun
zzlp_fprint_s2qaglst($D2E.s2qaglst, FILR): void
fun
zzlp_fprint_t2iaglst($D2E.t2iaglst, FILR): void
fun
zzlp_fprint_d2valdclist($D2E.d2valdclist, FILR): void
fun
zzlp_fprint_d3valdclist($D3E.d3valdclist, FILR): void
fun
zzlp_fprint_d2eclist($D2E.d2eclist, FILR): void
fun
zzlp_fprint_d3eclist($D3E.d3eclist, FILR): void
fun
zzlp_fprint_s2explst($S2E.s2explst, FILR): void
fun
zzlp_fprint_s2typlst($T2P.s2typlst, FILR): void
fun
zzlp_fprint_s2varlst($S2E.s2varlst, FILR): void
fun
zzlp_fprint_sort2lst($S2E.sort2lst, FILR): void
fun
zzlp_fprint_t2qaglst($D2E.t2qaglst, FILR): void
fun
zzlp_fprint_t2jaglst($D2E.t2jaglst, FILR): void
fun
zzlp_fprint_f3arglst($D3E.f3arglst, FILR): void
fun
zzlp_fprint_d3explst($D3E.d3explst, FILR): void
fun
zzlp_fprint_d2explst($D2E.d2explst, FILR): void
fun
zzlp_fprint_d3patlst($D3E.d3patlst, FILR): void
fun
zzlp_fprint_d2patlst($D2E.d2patlst, FILR): void
fun
zzlp_fprint_l2t2plst($T2P.l2t2plst, FILR): void
fun
zzlp_fprint_s2vtplst($T2P.s2vtplst, FILR): void
//
(***********************************************************************)
(* end of [ATS3/XATSOPT_srcgen2_SATS_xatsopt.sats] *)
(***********************************************************************)
