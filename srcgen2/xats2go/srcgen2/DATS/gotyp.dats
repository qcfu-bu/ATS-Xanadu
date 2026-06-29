(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2026 Hongwei Xi, ATS Trustful Software, Inc.
** All rights reserved
**
** ATS is free software;  you can  redistribute it and/or modify it under
** the terms of  the GNU GENERAL PUBLIC LICENSE (GPL) as published by the
** Free Software Foundation; either version 3, or (at  your  option)  any
** later version.
*)

(* ****** ****** *)
//
(*
gotyp.dats — the self-contained part of the Go type language: a structural
[gotyp_fprint] (IR diagnostics) + the small predicates [gotyp_is_any] /
[gotyp_is_ptr] / [gotyp_unptr].  The Go SOURCE-TEXT renderer [gotyp_emit]
lives in the emitter layer (go1emit_styp0.dats, staging S3) since it shares
that layer's field-naming / int-formatting utilities.
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
"./../../../SATS/xsymbol.sats"
#staload
"./../../../SATS/xlabel0.sats"
//
#staload "./../SATS/gotyp.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
gotyp_fprint
(gty, out0) =
let
//
#impltmp
g_print$out<>() = out0
//
in//let
//
case+ gty of
//
| GOTint()  => prints("int")
| GOTflt()  => prints("float64")
| GOTbool() => prints("bool")
| GOTrune() => prints("rune")
| GOTstr()  => prints("string")
| GOTany()  => prints("any")
| GOTunit() => prints("unit")
//
| GOTptr(t1)   => (prints("*");  gotyp_fprint(t1, out0))
| GOTslice(t1) => (prints("[]"); gotyp_fprint(t1, out0))
//
| GOTstruct(fts) =>
  let
    fun
    loop
    (i0: sint, xs: labgotyplst): void =
    (
    case+ xs of
    | list_nil() => ()
    | list_cons(ft1, xs1) =>
      let
        val @(lab1, ty1) = ft1
      in
        (if (i0 >= 1) then prints("; "));
        label_fprint(lab1, out0);
        prints(" ");
        gotyp_fprint(ty1, out0);
        loop(i0+1, xs1)
      end)
  in
    prints("struct{"); loop(0, fts); prints("}")
  end
//
| GOTfunc(args, res) =>
  let
    fun
    loop
    (i0: sint, xs: gotyplst): void =
    (
    case+ xs of
    | list_nil() => ()
    | list_cons(a1, xs1) =>
      (
        (if (i0 >= 1) then prints(", "));
        gotyp_fprint(a1, out0);
        loop(i0+1, xs1)
      ))
  in
    prints("func("); loop(0, args); prints(") "); gotyp_fprint(res, out0)
  end
//
| GOTcon(nm) => prints("con(", nm, ")")
//
| GOText(s) => prints(s)
//
end // end-of-[gotyp_fprint(gty, out0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
gotyp_is_any
  (gty) =
(
case+ gty of
| GOTany() => true
| _(*else*) => false)
//
#implfun
gotyp_is_ptr
  (gty) =
(
case+ gty of
| GOTptr(_) => true
| _(*else*) => false)
//
#implfun
gotyp_unptr
  (gty) =
(
case+ gty of
| GOTptr(t1) => t1
| _(*else*) => gty)
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_gotyp.dats] *)
(***********************************************************************)
