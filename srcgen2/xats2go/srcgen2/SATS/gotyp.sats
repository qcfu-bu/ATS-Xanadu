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
**
** ATS is distributed in the hope that it will be useful, but WITHOUT ANY
** WARRANTY; without  even  the  implied  warranty  of MERCHANTABILITY or
** FITNESS FOR A PARTICULAR PURPOSE.  See the  GNU General Public License
** for more details.
*)

(* ****** ****** *)
//
(*
gotyp — the Go TYPE LANGUAGE, as data, carried BY the new typed intrep1.
//
THE POINT.  The first xats2go attempt copied an intrep1 from xats2js (a
TYPE-ERASED ANF IR, correct for a dynamically-typed target) and re-smuggled
the static types Go needs through a process-global side-table
([go1emit_tytab0]).  That is the wrong shape for a STATICALLY-typed target.
This module is the foundation of the fix: a typed intrep1 whose temps and
values carry a [gotyp] -- the concrete Go type -- so the emitter RENDERS the
type already on the node instead of RECOVERING it.
//
[gotyp] is the structured form of what [go1emit_styp0.dats] currently builds
as Go type STRINGS ([gotype_of_styp]/[gotype_of_i0typ] -> "int", "float64",
"*struct{...}", "any", ...).  It is computed ONCE during lowering, from the
source expression's type [i0exp_ityp$get : i0typ] (the xats2cc intrep0 keeps
that type on every node -- which is why xats2cc, not the type-erased
xats2js/xats2cz intrep0, is the basis for the Go backend).
//
See docs/00-typed-intrep1-redesign.md for the full design and the
[i0typ] -> [gotyp] mapping table.
*)
//
(* ****** ****** *)
//
#include
".\
/../../..\
/HATS/xatsopt_sats.hats"
//
(* ****** ****** *)
//
#staload
"./../../../SATS/xbasics.sats"
#staload
"./../../../SATS/xsymbol.sats"
#staload
"./../../../SATS/xlabel0.sats"
//
(* ****** ****** *)
//
#typedef sym_t = sym_t
#typedef label = label
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
The Go type language.  A plain recursive datatype (the style intrep1.sats
uses for [i1val_node]/[i1ins]) -- no allocator boilerplate needed.
//
SCALARS map a concrete ATS scalar to its native Go type:
  GOTint  -> int      GOTflt  -> float64   GOTbool -> bool
  GOTrune -> rune     GOTstr  -> string
//
GOTany  -> any (interface{}).  The FAITHFUL image of an [I0Tvar] (a
           universally-quantified type variable): ATS represents such values
           uniformly/boxed, so `any` is exact, NOT a fallback defect.
//
GOTunit -> the unit/void result (an ATS `()` computation has no Go value).
//
GOTptr(T)     -> *T.    Boxed-tuple/record layout, a by-`&ref` parameter,
                        and the cell behind an ATS `var` all lower to a Go
                        pointer.
GOTslice(T)   -> []T.
GOTstruct(fs) -> struct{ F<l0> T0; F<l1> T1; ... }.  A FLAT tuple/record
                 (value semantics); the proof fields ([npf]) are dropped
                 BEFORE building this list.
GOTfunc(as,r) -> func(a0, a1, ...) r.  The proof arguments are already
                 dropped; an effect-only result is GOTunit.
GOTcon(nm)    -> a datatype VALUE.  Today every datatype is the uniform
                 boxed runtime type `*xatsgo.XatsCon`; [nm] records the
                 parent datatype so a later milestone can graduate it to a
                 typed tagged struct.
GOText(s)     -> a runtime/external Go type name emitted VERBATIM (e.g. a
                 hand-written `xatsgo.*` type).
*)
//
datatype
gotyp =
//
| GOTint  of () // int
| GOTflt  of () // float64
| GOTbool of () // bool
| GOTrune of () // rune
| GOTstr  of () // string
//
| GOTany  of () // any (interface{})
| GOTunit of () // unit/void (no Go value)
//
| GOTptr   of (gotyp)        // *T
| GOTslice of (gotyp)        // []T
//
| GOTstruct of (labgotyplst) // struct{F<l> T; ...} (flat)
//
| GOTfunc of
  (gotyplst(*args*), gotyp(*res*)) // func(..) res
//
| GOTcon of (sym_t)          // datatype value (boxed: *xatsgo.XatsCon)
//
| GOText of (strn)           // verbatim runtime/external Go type name
//
where
{
//
  #typedef labgotyp = (label, gotyp)
//
  #typedef gotyplst = list(gotyp)
  #typedef gotypopt = optn(gotyp)
  #typedef labgotyplst = list(labgotyp)
//
} // end-of-[datatype(gotyp)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
The Go SOURCE-TEXT renderer [gotyp_emit(gty): strn] -- e.g.
  GOTint                       -> "int"
  GOTptr(GOTint)               -> "*int"
  GOTstruct[(0,int),(1,bool)]  -> "struct{F0 int; F1 bool}"
  GOTfunc([int],bool)          -> "func(int) bool"
  GOTcon("list")               -> "*xatsgo.XatsCon"
-- lives in the EMITTER layer (go1emit_styp0.dats, added at staging step S3),
because it shares the field-naming ([gofield_of_label]) and int-formatting
([gostr_of_uint]) utilities defined there, and must stay byte-identical to the
construction/projection sites.  It is intentionally NOT declared here so this
module stays self-contained (no go1emit dependency).  This module provides only
the DATA and its structural helpers.
*)
//
(*
[gotyp_fprint]: a human-readable dump (for IR diagnostics / [i1*_fprint]).
*)
fun
gotyp_fprint(gty: gotyp, out0: FILR): void
//
(* ****** ****** *)
//
(*
[gotyp_is_any]/[gotyp_is_ptr]: small structural predicates the lowering and
emitter need (e.g. "do I need a type assertion here?" / "is this already a
pointer?").
*)
fun
gotyp_is_any(gty: gotyp): bool
fun
gotyp_is_ptr(gty: gotyp): bool
//
(* ****** ****** *)
//
(*
[gotyp_unptr(gty)]: the pointee of a GOTptr, else [gty] unchanged.  Used to
read THROUGH a boxed/by-ref value.
*)
fun
gotyp_unptr(gty: gotyp): gotyp
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_SATS_gotyp.sats] *)
(***********************************************************************)
