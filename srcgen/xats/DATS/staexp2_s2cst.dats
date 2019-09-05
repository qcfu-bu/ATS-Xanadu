(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2018 Hongwei Xi, ATS Trustful Software, Inc.
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
// Start Time: December, 2018
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
//
#staload "./../SATS/stamp0.sats"
//
#staload "./../SATS/symbol.sats"
#staload "./../SATS/lexing.sats"
//
#staload "./../SATS/trans01.sats"
//
#staload "./../SATS/staexp2.sats"
#staload "./../SATS/statyp2.sats"
//
(* ****** ****** *)

#define NS2CST 1*1024

(* ****** ****** *)
//
implement
s2cstnul_none
((*void*)) =
$UN.cast(the_null_ptr)
implement
s2cstnul_some(s2c) = $UN.cast(s2c)
//
(* ****** ****** *)
//
local
//
extern
castfn
_s2c2ptr_
{l:addr}(s2cstnul(l)):<> ptr(l)
//
in (*in-of-local*)
//
implement
s2cstnul_iseqz
  (s2c) =
  (_s2c2ptr_(s2c) = the_null_ptr)
implement
s2cstnul_isneqz
  (s2c) =
  (_s2c2ptr_(s2c) > the_null_ptr)
//
end // end of [local]
//
(* ****** ****** *)

local
//
#staload
"libats/SATS/dynarray.sats"
#staload _ =
"libats/DATS/dynarray.dats"
//
typedef itm = s2cst
vtypedef dynarray = dynarray(itm)
//
val
theDynarr = 
dynarray_make_nil<itm>(i2sz(NS2CST))
val
theDynarr = $UN.castvwtp0{ptr}(theDynarr)
//
in (* in-of-local *)

implement
stamp_s2cst
  (s2c) = let
  val s0 =
  s2c.stamp()
  val i0 =
  stamp2uint(s0)
  val i0 =
  u2sz(g1ofg0(i0))
  val A0 =
  $UN.castvwtp0{dynarray}(theDynarr)
  val-
  ~None_vt() =
  dynarray_insert_at_opt(A0, i0, s2c)
  prval ((*void*)) = $UN.cast2void(A0)
in
  // nothing
end // end of [stamp_s2cst]

end // end of [local]

(* ****** ****** *)

local

absimpl
s2cst_tbox = $rec{
//
  s2cst_loc= loc_t // loc
, s2cst_sym= sym_t // name
, s2cst_sort= sort2 // sort
//
, s2cst_stamp= stamp // unicity
//
} (* end of [s2cst_tbox] *)

in (* in-of-local *)

implement
s2cst_make_idst
  (tok, s2t) =
(
let
val
s2c = 
$rec{
  s2cst_loc= loc
, s2cst_sym= sid
, s2cst_sort= s2t
//
, s2cst_stamp= stamp
//
} (* end-of-val *)
val
abs = ABSTDF2none()
val
def1 =
the_s2exp_none0(*void*)
val
def2 =
the_t2ype_none0(*void*)
in
s2c where
{
val () = stamp_s2cst(s2c)
val () = stamp_s2cst_abs(s2c, abs)
val () = stamp_s2cst_sexp(s2c, def1)
val () = stamp_s2cst_type(s2c, def2)
}
end
) where
{
//
  val loc = tok.loc()
  val sid = sexpid_sym(tok)
//
  val
  stamp = s2cst_stamp_new((*void*))
//
} (* end of [s2cst_make_idst] *)

(* ****** ****** *)

implement
s2cst_get_loc(x0) = x0.s2cst_loc
implement
s2cst_get_sym(x0) = x0.s2cst_sym
implement
s2cst_get_sort(x0) = x0.s2cst_sort
implement
s2cst_get_stamp(x0) = x0.s2cst_stamp

(* ****** ****** *)

end // end of [local]

(* ****** ****** *)

local
//
#staload
"libats/SATS/dynarray.sats"
#staload _ =
"libats/DATS/dynarray.dats"
//
typedef itm = abstdf2
vtypedef dynarray = dynarray(itm)
//
val
theDynarr = 
dynarray_make_nil<itm>(i2sz(NS2CST))
val
theDynarr = $UN.castvwtp0{ptr}(theDynarr)
//
in (* in-of-local *)

implement
s2cst_get_abs
  (s2c) = let
  val s0 =
  s2c.stamp()
  val i0 =
  stamp2uint(s0)
  val i0 =
  u2sz(g1ofg0(i0))
  val A0 =
  $UN.castvwtp0{dynarray}(theDynarr)
  val cp = dynarray_getref_at(A0, i0)
  prval ((*void*)) = $UN.cast2void(A0)
in
  if
  isneqz(cp)
  then $UN.cptr_get(cp) else ABSTDF2none()
end // end of [s2cst_get_abs]

(* ****** ****** *)

implement
stamp_s2cst_abs
  (s2c, abs) = let
  val s0 =
  s2c.stamp()
  val i0 =
  stamp2uint(s0)
  val i0 =
  u2sz(g1ofg0(i0))
  val A0 =
  $UN.castvwtp0{dynarray}(theDynarr)
  val-
  ~None_vt() =
  dynarray_insert_at_opt(A0, i0, abs)
  prval ((*void*)) = $UN.cast2void(A0)
in
  // nothing
end // end of [stamp_s2cst_abs]

end // end of [local]

(* ****** ****** *)

local
//
#staload
"libats/SATS/dynarray.sats"
#staload _ =
"libats/DATS/dynarray.dats"
//
typedef itm = s2exp
vtypedef dynarray = dynarray(itm)
//
val
theDynarr = 
dynarray_make_nil<itm>(i2sz(NS2CST))
val
theDynarr = $UN.castvwtp0{ptr}(theDynarr)
//
in (* in-of-local *)

implement
s2cst_get_sexp
  (s2c) = let
  val s0 =
  s2c.stamp()
  val i0 =
  stamp2uint(s0)
  val i0 =
  u2sz(g1ofg0(i0))
  val A0 =
  $UN.castvwtp0{dynarray}(theDynarr)
  val cp = dynarray_getref_at(A0, i0)
  prval ((*void*)) = $UN.cast2void(A0)
in
  if
  isneqz(cp)
  then $UN.cptr_get(cp) else the_s2exp_none0
end // end of [s2cst_get_sexp]

(* ****** ****** *)

implement
stamp_s2cst_sexp
  (s2c, def) = let
  val s0 =
  s2c.stamp()
  val i0 =
  stamp2uint(s0)
  val i0 =
  u2sz(g1ofg0(i0))
  val A0 =
  $UN.castvwtp0{dynarray}(theDynarr)
  val-
  ~None_vt() =
  dynarray_insert_at_opt(A0, i0, def)
  prval ((*void*)) = $UN.cast2void(A0)
in
  // nothing
end // end of [stamp_s2cst_sexp]

end // end of [local]

(* ****** ****** *)

local
//
#staload
"libats/SATS/dynarray.sats"
#staload _ =
"libats/DATS/dynarray.dats"
//
typedef itm = t2ype
vtypedef dynarray = dynarray(itm)
//
val
theDynarr = 
dynarray_make_nil<itm>(i2sz(NS2CST))
val
theDynarr = $UN.castvwtp0{ptr}(theDynarr)
//
in (* in-of-local *)

implement
s2cst_get_type
  (s2c) = let
  val s0 =
  s2c.stamp()
  val i0 =
  stamp2uint(s0)
  val i0 =
  u2sz(g1ofg0(i0))
  val A0 =
  $UN.castvwtp0{dynarray}(theDynarr)
  val cp = dynarray_getref_at(A0, i0)
  prval ((*void*)) = $UN.cast2void(A0)
in
  if
  isneqz(cp)
  then $UN.cptr_get(cp) else the_t2ype_none0
end // end of [s2cst_get_type]

(* ****** ****** *)

implement
stamp_s2cst_type
  (s2c, def) = let
//
val () =
println!
("stamp_s2cst_type: s2c = ", s2c)
val () =
println!
("stamp_s2cst_type: def = ", def)
//
  val s0 =
  s2c.stamp()
  val i0 =
  stamp2uint(s0)
  val i0 =
  u2sz(g1ofg0(i0))
  val A0 =
  $UN.castvwtp0{dynarray}(theDynarr)
  val-
  ~None_vt() =
  dynarray_insert_at_opt(A0, i0, def)
  prval ((*void*)) = $UN.cast2void(A0)
in
  // nothing
end // end of [stamp_s2cst_type]

end // end of [local]

(* ****** ****** *)

(* end of [xats_staexp2_s2cst.dats] *)
