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
gotyp_of_styp — the TYPE-TRANSLATION engine for the typed intrep1.  Maps an
ATS static type ([s2typ]) or a layout-bearing intrep0 type ([i0typ]) to a
native Go type ([gotyp]).  This is the structured form of the emitter's
[gotype_of_styp]/[gotype_of_i0typ] string family (go1emit_styp0.dats); the
difference is it runs in the LOWERING (so the result is stored ON the temp,
not recovered at emit time) and returns structured [gotyp] (so the emitter
renders rather than re-derives).
//
LAYERING.  Depends only on staexp2/statyp2/dynexp2 (the type API) + intrep0
([i0typ]) + gotyp.  It does NOT depend on intrep1 or go1emit, so it can sit
below trxi0i1 in the build and be called from the lowering.  (A few tiny
datatype predicates are duplicated from go1emit_styp0.dats for self-
containment; staging step S3 dedups by making this the canonical engine and
deleting the emitter's string copies.)
//
FAITHFULNESS.  The case structure mirrors [gotype_of_i0typ]/[gotype_of_styp]
1:1 so that, once the emitter reads the temp's [gotyp] (S3), the emitted Go
is byte-identical to today's (the differential-vs-JS oracle gates that step).
Polymorphic [I0Tvar]/[T2Pxtv-unsolved] -> [GOTany], faithful to ATS's uniform
representation.
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
#staload "./gotyp.sats"
//
(* ****** ****** *)
//
(*
[gotyp_of_styp(t2p0)]: the Go type of an ATS static type.
[gotyp_of_i0typ(ityp)]: the Go type of a (layout-bearing) intrep0 type --
the form the lowering has in hand at each [i0exp] ([i0exp_ityp$get]).
*)
fun
gotyp_of_styp(t2p0: s2typ): gotyp
//
fun
gotyp_of_i0typ(ityp: i0typ): gotyp
//
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_SATS_gotyp_of_styp.sats] *)
(***********************************************************************)
