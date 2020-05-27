(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2020 Hongwei Xi, ATS Trustful Software, Inc.
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
// Start Time: October, 2018
// Authoremail: gmhwxiATgmailDOTcom
//
(* ****** ****** *)
//
#include
"share/atspre_staload.hats"
#staload
UN = "prelude/SATS/unsafe.sats"
//
(* ****** ****** *)

#staload "./../SATS/locinfo.sats"

(* ****** ****** *)

#staload "./../SATS/statyp2.sats"
#staload "./../SATS/staexp2.sats"
#staload "./../SATS/dynexp2.sats"
#staload "./../SATS/dynexp3.sats"

(* ****** ****** *)

#staload "./../SATS/trans3x.sats"

(* ****** ****** *)

#staload
_(*TMP*) = "./statyp2_util0.dats"

(* ****** ****** *)

#define
LOC0 the_location_dummy

(* ****** ****** *)

implement
fprint_val<t2ype> = fprint_t2ype

(* ****** ****** *)
//
datavtype
tr3xenv =
TR3XENV of tr3xstk
//
and
tr3xstk =
//
| tr3xstk_nil of ()
//
| tr3xstk_lam0 of tr3xstk
| tr3xstk_fix0 of (d2var, tr3xstk)
//
| tr3xstk_let1 of tr3xstk
(*
| tr3xstk_loc1 of tr3xstk
| tr3xstk_loc2 of tr3xstk
*)
//
| tr3xstk_dpat of (d3pat, tr3xstk)
| tr3xstk_farg of (f3arg, tr3xstk)
//
(* ****** ****** *)

local

absimpl
tr3xenv_vtype = tr3xenv

in(*in-of-local*)

(* ****** ****** *)

implement
tr3xenv_add_let1
  (env) =
( fold@(env) ) where
{
//
val+
@TR3XENV(xs) = env
val () =
(xs := tr3xstk_let1(xs))
//
} (* end of [tr3xenv_add_let1] *)

(* ****** ****** *)

implement
tr3xenv_add_loc1
  (env) =
( fold@(env) ) where
{
//
val+
@TR3XENV(xs) = env
(*
val () =
(xs := tr3xstk_loc1(xs))
*)
//
} (* end of [tr3xenv_add_loc1] *)

(* ****** ****** *)

implement
tr3xenv_add_loc2
  (env) =
( fold@(env) ) where
{
//
val+
@TR3XENV(xs) = env
(*
val () =
(xs := tr3xstk_loc2(xs))
*)
//
} (* end of [tr3xenv_add_loc2] *)

(* ****** ****** *)

implement
tr3xenv_pop_let1
  (env) =
( fold@(env) ) where
{
//
val+
@TR3XENV(xs) = env
val () = (xs := auxstk(xs))
//
} where
{
//
fun
auxstk
(xs: tr3xstk): tr3xstk =
(
case- xs of
|
~tr3xstk_let1(xs) => xs
|
~tr3xstk_dpat(_, xs) => auxstk(xs)
) (* end of [auxstk] *)
//
} (* end of [tr3xenv_pop_let1] *)

(* ****** ****** *)

implement
tr3xenv_pop_loc12
  (env) =
( fold@(env) ) where
{
//
val+
@TR3XENV(xs) = env
val () = (xs := auxstk(xs))
//
} where
{
fun
auxstk(xs: tr3xstk): tr3xstk = xs
} (* end of [tr3xenv_pop_loc12] *)

(* ****** ****** *)
//
implement
tr3xenv_make_nil
  ((*void*)) =
(
  TR3XENV(tr3xstk_nil())
)
//
(* ****** ****** *)

implement
tr3xenv_add_dpat
  (env, d3p) =
( fold@(env) ) where
{
//
val+
@TR3XENV(xs) = env
val () =
(xs := tr3xstk_dpat(d3p, xs))
//
} (* end of [tr3xenv_add_dpat] *)

(* ****** ****** *)
//
implement
tr3xenv_free_top
  (env0) =
(
  auxstk(stk0)
) where
{
//
val-
~TR3XENV(stk0) = env0
//
fun
auxstk
(xs: tr3xstk): void =
(
case- xs of
|
~tr3xstk_nil() => ()
|
~tr3xstk_dpat(_, xs) => auxstk(xs)
|
~tr3xstk_farg(_, xs) => auxstk(xs)
)
//
} (* end of [tr3xstk_free_all] *)
//
(* ****** ****** *)

implement
tr3xenv_dvar_locq
  (env0, d2v0) =
(
  auxstk(stk0)
) where
{
//
val-
TR3XENV(stk0) = env0
//
fun
auxstk
(xs: !tr3xstk): bool =
(
case- xs of
|
tr3xstk_nil() => false
|
tr3xstk_lam0 _ => false
|
tr3xstk_fix0 _ => false
|
tr3xstk_let1(xs) => auxstk(xs)
|
tr3xstk_dpat(d3p0, xs) =>
(
if test then true else auxstk(xs)
) where
{
  val test = d3pat_memq_dvar(d3p0, d2v0)
}
|
tr3xstk_farg(f3a0, xs) =>
(
if test then true else auxstk(xs)
) where
{
  val test = f3arg_memq_dvar(f3a0, d2v0)
}
)
//
} (* end of [tr3xstk_free_all] *)
//
(* ****** ****** *)

end // end of [local]

(* ****** ****** *)

(* end of [xats_trans3x_envmap.dats] *)
