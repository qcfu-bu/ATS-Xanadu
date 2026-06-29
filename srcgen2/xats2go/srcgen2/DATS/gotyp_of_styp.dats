(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2026 Hongwei Xi, ATS Trustful Software, Inc.
** All rights reserved
*)

(* ****** ****** *)
//
(*
gotyp_of_styp.dats — the type-translation engine (s2typ / i0typ -> gotyp).
A faithful structured port of go1emit_styp0.dats's [gotype_of_styp] /
[gotype_of_i0typ] string family; see the .sats for the rationale and layering.
*)
//
(* ****** ****** *)
//
#include
"./../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../..\
/HATS/xatsopt_dpre.hats"
//
(* ****** ****** *)
//
#staload
"./../../../SATS/xbasics.sats"
#staload
"./../../../SATS/xsymbol.sats"
#staload
"./../../../SATS/xlabel0.sats"
#staload
"./../../../SATS/staexp2.sats"
#staload
"./../../../SATS/statyp2.sats"
#staload
"./../../../SATS/dynexp2.sats"
//
#staload ".\
/../../xats2cc\
/srcgen1/SATS/intrep0.sats"
//
#staload "./../SATS/gotyp.sats"
#staload "./../SATS/gotyp_of_styp.sats"
//
(* ****** ****** *)
//
#symload node with s2typ_get_node
#symload node with i0typ_node$get
#symload name with s2cst_get_name
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
[gotyp_of_symname]: a bare ATS scalar type name -> its Go type.  The prelude
scalar abstypes surface either as the applied form ([gint_type(KIND,i)] etc.,
handled by [gtx_i0t_apps]) or, at datacon-field/record positions, as their
bare abstype name ([sint], [dflt], ...).  All integer widths -> Go `int`,
all floats -> `float64` (matching the JS backend's single number type).
*)
fun
gotyp_of_symname
(nm: strn): gotyp =
(
case+ nm of
| "int" => GOTint()
| "intGt" => GOTint()
| "intGte" => GOTint()
| "intLt" => GOTint()
| "intLte" => GOTint()
| "size" => GOTint()
| "ssize" => GOTint()
| "bool" => GOTbool()
| "char" => GOTrune()
| "schar" => GOTrune()
| "uchar" => GOText("byte")
| "double" => GOTflt()
| "float" => GOTflt()
| "string" => GOTstr()
| "strn" => GOTstr()
| "strptr" => GOTstr()
| "strnptr" => GOTstr()
| "nint" => GOTint()
//
| "bool_type" => GOTbool()
| "char_type" => GOTrune()
| "gflt_type" => GOTflt()
//
| "sint" => GOTint()
| "uint" => GOTint()
| "lint" => GOTint()
| "ulint" => GOTint()
| "llint" => GOTint()
| "ullint" => GOTint()
| "dflt" => GOTflt()
| "sflt" => GOTflt()
| "ldflt" => GOTflt()
| _(*else*) => GOTany()
)
//
(*
[gotyp_of_textnm]: a C-level $extype name (the gint/gflt KIND, a T2Ptext /
I0Ttext) -> its Go scalar.
*)
fun
gotyp_of_textnm
(nm: strn): gotyp =
(
case+ nm of
| "xats_sint_t"   => GOTint()
| "xats_uint_t"   => GOTint()
| "xats_slint_t"  => GOTint()
| "xats_ulint_t"  => GOTint()
| "xats_ssize_t"  => GOTint()
| "xats_usize_t"  => GOTint()
| "xats_sllint_t" => GOTint()
| "xats_ullint_t" => GOTint()
| "xats_bool_t"   => GOTbool()
| "xats_char_t"   => GOTrune()
| "xats_double_t" => GOTflt()
| "xats_float_t"  => GOTflt()
| "xats_ldouble_t"=> GOTflt()
| _(*else*) => GOTany()
)
//
(* ****** ****** *)
//
(*
[gtx_text_in_args_s] / [gtx_text_in_args_i]: find the FIRST [T2Ptext] /
[I0Ttext] among the args (the gint/gflt KIND) and map it; [GOTany] if none.
*)
fun
gtx_text_in_args_s
(args: s2typlst): gotyp =
(
case+ args of
|list_nil() => GOTany()
|list_cons(a1, args1) =>
  (
  case+ s2typ_get_node(a1) of
  |T2Ptext(nm, _) => gotyp_of_textnm(nm)
  | _(*else*) => gtx_text_in_args_s(args1))
)
//
fun
gtx_text_in_args_i
(args: i0typlst): gotyp =
(
case+ args of
|list_nil() => GOTany()
|list_cons(a1, args1) =>
  (
  case+ i0typ_node$get(a1) of
  |I0Ttext(nm, _) => gotyp_of_textnm(nm)
  | _(*else*) => gtx_text_in_args_i(args1))
)
//
(* ****** ****** *)
//
(*
[gtx_is_datatype]: does this [s2cst] name a DATATYPE (have a constructor
list)?  [gtx_boxed_head]: a prelude datatype head that may surface without
its constructor list attached but still has the uniform boxed runtime shape.
[gtx_is_boxed_datatype]: either of the above.
*)
fun
gtx_is_datatype
(s2c0: s2cst): bool =
let
  val opt0 = s2cst_get_d2cs(s2c0)
in
  case+ opt0 of
  | ~optn_vt_nil() => false
  | ~optn_vt_cons(_) => true
end
//
fun
gtx_boxed_head
(nm: strn): bool =
(
case+ nm of
| "optn" => true
| "optn_t0_i0_tx" => true
| "list" => true
| "list_t0_i0_tx" => true
| "optn_vt" => true
| "optn_vt_i0_vx" => true
| "list_vt" => true
| "list_vt_i0_vx" => true
| _(*else*) => false
)
//
fun
gtx_is_boxed_datatype
(s2c0: s2cst): bool =
let
  val nm = symbl_get_name(s2cst_get_name(s2c0))
in
  if gtx_boxed_head(nm) then true else gtx_is_datatype(s2c0)
end
//
(* ****** ****** *)
//
(*
[gtx_s2cst_head]: the canonical "head s2cst -> gotyp" mapper (the [gotyp]
analog of [goty_of_s2cst_head]).  Scalar name -> scalar; else a boxed
datatype -> [GOTcon]; else chase a one-step typedef expansion ([s2cst_get_styp]),
guarding the name=name self-loop -> [GOTany].
*)
fun
gtx_s2cst_head
(s2c0: s2cst): gotyp =
let
  val nm0 = symbl_get_name(s2cst_get_name(s2c0))
  val gt = gotyp_of_symname(nm0)
in
  if gotyp_is_any(gt)
  then
    (
    if gtx_is_boxed_datatype(s2c0)
    then GOTcon(s2cst_get_name(s2c0))
    else
      let
        val opt0 = s2cst_get_styp(s2c0)
      in
        case+ opt0 of
        | ~optn_vt_nil() => GOTany()
        | ~optn_vt_cons(t2p1) =>
          (
          case+ s2typ_get_node(t2p1) of
          |T2Pcst(s2c1) =>
            let
              val nm1 = symbl_get_name(s2cst_get_name(s2c1))
            in
              if (nm0 = nm1) then GOTany() else gotyp_of_styp(t2p1)
            end
          | _(*expanded typedef*) => gotyp_of_styp(t2p1))
      end)
  else gt
end
//
(* ****** ****** *)
//
(*
[gtx_drop_styp]: drop the leading [npf] proof args (erased) from an
[s2typlst].  [gtx_argchase]: chase the per-arg wrappers [T2Parg1]/[T2Patx2]
to the underlying arg type.  [gtx_args_map]: map a (proof-dropped) arg list
to [gotyplst].
*)
fun
gtx_drop_styp
(npf: sint, xs: s2typlst): s2typlst =
(
if (npf <= 0) then xs else
(
case+ xs of
|list_nil() => xs
|list_cons(_, xs1) => gtx_drop_styp(npf-1, xs1))
)
//
fun
gtx_argchase
(t2p0: s2typ): gotyp =
(
case+ s2typ_get_node(t2p0) of
|T2Parg1(_, t2p1) => gtx_argchase(t2p1)
|T2Patx2(t2p1, _) => gtx_argchase(t2p1)
| _(*else*) => gotyp_of_styp(t2p0)
)
//
fun
gtx_args_map
(xs: s2typlst): gotyplst =
(
case+ xs of
|list_nil() => list_nil()
|list_cons(a1, xs1) =>
  list_cons(gtx_argchase(a1), gtx_args_map(xs1))
)
//
(* ****** ****** *)
//
(*
[gtx_drop_s2lab] / [gtx_s2lab_fields]: drop [npf] proof fields, then build
the [labgotyp] field list of a tuple/record [s2typ] ([T2Ptrcd]).  Each field
keeps its [label] (the Go field name is derived at render time) and recurses
through [gotyp_of_styp].
*)
fun
gtx_drop_s2lab
(npf: sint, xs: l2t2plst): l2t2plst =
(
if (npf <= 0) then xs else
(
case+ xs of
|list_nil() => xs
|list_cons(_, xs1) => gtx_drop_s2lab(npf-1, xs1))
)
//
fun
gtx_s2lab_fields
(xs: l2t2plst): labgotyplst =
(
case+ xs of
|list_nil() => list_nil()
|list_cons(lt1, xs1) =>
  let
    val-S2LAB(lab1, t2p1) = lt1
  in
    list_cons(@(lab1, gotyp_of_styp(t2p1)), gtx_s2lab_fields(xs1))
  end
)
//
(* ****** ****** *)
//
(*
[gtx_i0t_apps]: an applied intrep0 type-ctor.  gint_type -> KIND-derived int,
gflt_type -> float64, else the head [s2cst] mapper.
*)
fun
gtx_i0t_apps
( hd: i0typ
, args: i0typlst): gotyp =
(
case+ i0typ_node$get(hd) of
|I0Tcst(s2c0) =>
  let
    val hdnm = symbl_get_name(s2cst_get_name(s2c0))
  in
    (
    if (hdnm = "gint_type")
    then gtx_text_in_args_i(args)
    else
    (
    if (hdnm = "gflt_type")
    then
      let val gt = gtx_text_in_args_i(args)
      in if gotyp_is_any(gt) then GOTflt() else gt end
    else gtx_s2cst_head(s2c0)))
  end
| _(*non-cst head*) => GOTany()
)
//
(*
[gtx_drop_i0lab] / [gtx_i0lab_fields]: the [i0typ] analog of the [s2lab]
field helpers ([I0LAB] each).
*)
fun
gtx_drop_i0lab
(npf: sint, xs: l0i0tlst): l0i0tlst =
(
if (npf <= 0) then xs else
(
case+ xs of
|list_nil() => xs
|list_cons(_, xs1) => gtx_drop_i0lab(npf-1, xs1))
)
//
fun
gtx_i0lab_fields
(xs: l0i0tlst): labgotyplst =
(
case+ xs of
|list_nil() => list_nil()
|list_cons(f1, xs1) =>
  let
    val-I0LAB(lab1, ity1) = f1
  in
    list_cons(@(lab1, gotyp_of_i0typ(ity1)), gtx_i0lab_fields(xs1))
  end
)
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
gotyp_of_styp
(t2p0) =
(
case+ s2typ_get_node(t2p0) of
//
|T2Pcst(s2c0) => gtx_s2cst_head(s2c0)
//
// a FUNCTION type -> a Go func(...)... (proof args [npf] dropped).
|T2Pfun1(_, npf, args, res) =>
  let
    val args1 = gtx_drop_styp(npf, args)
    val gargs = gtx_args_map(args1)
    val gres  = gotyp_of_styp(res)
  in
    GOTfunc(gargs, gres)
  end
//
// a TUPLE / RECORD -> a Go struct (flat = value, boxed = *pointer).
|T2Ptrcd(knd, npf, ltps) =>
  let
    val ltps1 = gtx_drop_s2lab(npf, ltps)
    val flds  = gtx_s2lab_fields(ltps1)
    val stru  = GOTstruct(flds)
  in
    if trcdknd_fltq(knd) then stru else GOTptr(stru)
  end
//
// an APPLIED type-ctor: gint_type/gflt_type -> scalar; else head mapper.
|T2Papps(t2hd, args) =>
  (
  case+ s2typ_get_node(t2hd) of
  |T2Pcst(s2c0) =>
    let
      val hdnm = symbl_get_name(s2cst_get_name(s2c0))
    in
      (
      if (hdnm = "gint_type")
      then gtx_text_in_args_s(args)
      else
      (
      if (hdnm = "gflt_type")
      then
        let val gt = gtx_text_in_args_s(args)
        in if gotyp_is_any(gt) then GOTflt() else gt end
      else gtx_s2cst_head(s2c0)))
    end
  | _(*non-cst head*) => GOTany())
//
// trivial wrappers the front-end leaves around a scalar -> chase through.
|T2Ptop0(t2p1) => gotyp_of_styp(t2p1)
|T2Ptop1(t2p1) => gotyp_of_styp(t2p1)
|T2Plft (t2p1) => gotyp_of_styp(t2p1)
|T2Pnone1(t2p1) => gotyp_of_styp(t2p1)
|T2Parg1(_, t2p1) => gotyp_of_styp(t2p1)
|T2Pexi0(_, t2p1) => gotyp_of_styp(t2p1)
|T2Puni0(_, t2p1) => gotyp_of_styp(t2p1)
|T2Plam1(_, t2p1) => gotyp_of_styp(t2p1)
//
// an existential type variable -> chase its SOLVED static type; unsolved
// (solves to itself / another xtv) -> GOTany (faithful, and avoids a loop).
|T2Pxtv(xt2p) =>
  let
    val sln = x2t2p_get_styp(xt2p)
  in
    case+ s2typ_get_node(sln) of
    |T2Pxtv(_) => GOTany()
    | _(*solved*) => gotyp_of_styp(sln)
  end
//
// an external $extype directly -> by its name.
|T2Ptext(nm, _) => gotyp_of_textnm(nm)
//
| _(*otherwise*) => GOTany()
)
//
(* ****** ****** *)
//
#implfun
gotyp_of_i0typ
(ityp) =
(
case+ i0typ_node$get(ityp) of
//
|I0Tcst(s2c0) => gtx_s2cst_head(s2c0)
//
|I0Tapps(hd, args) => gtx_i0t_apps(hd, args)
//
|I0Ttext(nm, _) => gotyp_of_textnm(nm)
//
|I0Tlft(t1) => gotyp_of_i0typ(t1)
|I0Ttop0(t1) => gotyp_of_i0typ(t1)
|I0Ttop1(t1) => gotyp_of_i0typ(t1)
|I0Texi0(_, t1) => gotyp_of_i0typ(t1)
|I0Tuni0(_, t1) => gotyp_of_i0typ(t1)
|I0Tlam1(_, t1) => gotyp_of_i0typ(t1)
//
|I0Tnone1(t2p0) => gotyp_of_styp(t2p0)
//
|I0Ttrcd(knd, npf, fields) =>
  let
    val flds1 = gtx_drop_i0lab(npf, fields)
    val flds  = gtx_i0lab_fields(flds1)
    val stru  = GOTstruct(flds)
  in
    if trcdknd_fltq(knd) then stru else GOTptr(stru)
  end
//
| _(*datatype / polymorphic / unknown*) => GOTany()
)
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_gotyp_of_styp.dats] *)
(***********************************************************************)
