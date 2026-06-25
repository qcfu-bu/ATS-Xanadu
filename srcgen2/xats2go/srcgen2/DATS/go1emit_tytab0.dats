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
(* ****** ****** *)
//
(*
go1emit_tytab0 — milestone M2.6a — the IMPLEMENTATION of the
[i1tnm stamp -> i0typ] side-table.  See go1emit_tytab0.sats for the design
rationale (what/why-i0typ/ordering/correctness).
//
The store is a PROCESS-GLOBAL [a0ref] holding an association list
[list(@(stamp, i0typ))] keyed by the temp's stamp -- the exact module-level
mutable-ref idiom used for [the_drpth_ref] (filpath_drpth0.dats) and
[the_i1tnm_stamp_new]'s [stamper] (intrep1.dats), so it is transpiler-safe
(the JS backend the emitter runs on already supports [a0ref_make_1val] /
[a0ref_get] / [a0ref_set]).
//
An assoc list is intentional: the table is WRITE-MANY (every recorded mint)
but READ-FEW (only the temps the emitter's "any"-fallback actually queries),
and the per-source-file temp count is small for the M2.6a surface.  A
[stamp]-keyed hashmap is a drop-in optimization if a large program ever
makes the linear scan hot (the SATS interface would not change).  We
PREPEND new entries, so a (never-occurring) duplicate stamp resolves
last-writer-wins on lookup.
*)
//
(* ****** ****** *)
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
#staload // STMP =
"./../../../SATS/xstamp0.sats"
//
#staload ".\
/../../xats2cc\
/srcgen1/SATS/intrep0.sats"//for[i0typ]
//
#staload "./../SATS/go1emit_tytab0.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#typedef tyent = @(stamp, i0typ)
#typedef tyentlst = list(tyent)
//
(* ****** ****** *)
//
fun
stmp_eq0
(s1: stamp, s2: stamp): bool =
(
  stamp_cmp(s1, s2) = 0)
//
(*
[assoc_find]: first entry whose key equals [stmp], as an [i0typopt].
Linear scan (see file header); the list is short for the M2.6a surface.
*)
fun
assoc_find
(ents: tyentlst, stmp: stamp): i0typopt =
(
case+ ents of
|list_nil() => optn_nil()
|list_cons(ent1, ents1) =>
  let
    val (k1, t1) = ent1
  in
    if stmp_eq0(stmp, k1)
    then optn_cons(t1)
    else assoc_find(ents1, stmp)
  end
)//endof[assoc_find(ents,stmp)]
//
(* ****** ****** *)
(* ****** ****** *)
//
local
//
(*
The process-global association list.  Initialized empty; populated during
[trxi0i1] lowering; read during [go1emit] emission (same process, lowering
fully precedes emission -- see the SATS header's ORDERING argument).
*)
val
the_go_tytab_ref =
a0ref_make_1val<tyentlst>(list_nil(*void*))
//
in//local
//
(* ****** ****** *)
//
#implfun
go_tytab_put
(stmp, ityp) =
let
  val ents = a0ref_get<tyentlst>(the_go_tytab_ref)
in//let
  a0ref_set<tyentlst>
  (the_go_tytab_ref, list_cons(@(stmp, ityp), ents))
end//let//endof[go_tytab_put(stmp,ityp)]
//
(* ****** ****** *)
//
#implfun
go_tytab_get
(stmp) =
let
  val ents = a0ref_get<tyentlst>(the_go_tytab_ref)
in//let
  assoc_find(ents, stmp)
end//let//endof[go_tytab_get(stmp)]
//
(* ****** ****** *)
//
#implfun
go_tytab_reset
((*void*)) =
  a0ref_set<tyentlst>(the_go_tytab_ref, list_nil(*void*))
//
(* ****** ****** *)
//
end(*local*)//endof[local(the_go_tytab_ref)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_go1emit_tytab0.dats] *)
(***********************************************************************)
