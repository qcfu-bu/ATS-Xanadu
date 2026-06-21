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
go1emit_tytab0 — milestone M2.6a — the [i1tnm stamp -> i0typ] SIDE-TABLE
(the Regime-B enabler).
//
WHAT IT IS.  A PROCESS-GLOBAL mutable map recording, for each computed
ANF temp ([i1tnm]), the STATIC TYPE ([i0typ]) of the intrep0 expression
that the temp was bound from.  It is POPULATED during the intrep0->intrep1
lowering ([trxi0i1_dynexp.dats]: [i0exp_trxi0i1]), right where the typed
[i0exp] is in scope -- so the stored type is a CARRY-THROUGH of the
expression's own [i0exp_ityp$get], NOT a re-inference.  It is CONSULTED by
the Go emitter ([go1emit_styp0.dats]: [gotype_of_ins_local] fallback) to
concretely type a computed temp ([I1Vtnm] result) that the local
intrep1-level recovery cannot otherwise type (it would fall back to "any").
//
WHY [i0typ] (not [s2typ]).  At the mint site the cleanest reachable type
form is exactly [i0exp_ityp$get(iexp)] : [i0typ] -- a near-mirror of
[s2typ] that ALSO carries the layout-bearing nodes [I0Tcst]/[I0Ttcon]/
[I0Ttrcd] (see intrep0.sats).  Storing it verbatim is a zero-cost
carry-through (no conversion at lowering time, no loss of layout info for
M2.6b/M2.7).  The Go-type translation ([gotype_of_i0typ]) happens lazily at
EMIT time, only for the temps the emitter actually queries.
//
ORDERING (why a process-global is sound here).  The driver
([xats2go_goemit01.dats]) runs [i1parsed_of_trxi0i1(ipar)] to COMPLETION
(fully populating this table) and ONLY THEN calls [i1parsed_go1emit(ipar,
filr)] (which reads it).  Lowering fully precedes emission, in the SAME
process (the same JS bundle), so every entry the emitter could query is
already present.  A SINGLE source file is processed per emitter run, so no
cross-file staleness arises; [go_tytab_reset] is provided for defensiveness
should that ever change.
//
CORRECTNESS DISCIPLINE.  A wrong type here => a [go build] mismatch (the
oracle catches it).  So the table is populated BEST-EFFORT and CONSERVATIVE:
a temp is recorded ONLY when a clean source [i0typ] is in scope (the temp
flows out of [i0exp_trxi0i1] as the [i1val] of the producing [iexp]); temps
that [trxi0i1] invents with no source [i0exp] are simply NOT recorded, so
the emitter falls back to "any" exactly as before.  The reader
([gotype_of_i0typ]) is itself conservative: it returns a concrete Go type
ONLY for the SCALAR cases it can prove (int/bool/rune/float64/string) and
"any" for aggregates/datatypes/unknowns (M2.6b/M2.7 make those value-typed).
*)
//
(* ****** ****** *)
(* ****** ****** *)
//
#staload
".\
/../../../xats2cc\
/srcgen1/SATS/intrep0.sats"//for[i0typ]
//
(* ****** ****** *)
//
#typedef i0typopt = optn(i0typ)
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
[go_tytab_put(stmp, ityp)]: record that the temp with stamp [stmp] was
bound from an [i0exp] whose static type is [ityp].  Called at each mint
site during lowering.  Idempotent-ish: a later put for the same stamp
overwrites (does not happen in practice -- each [i1tnm_new0] stamp is
fresh -- but the last-writer-wins semantics is harmless).
*)
fun
go_tytab_put
(stmp: stamp, ityp: i0typ): void
//
(*
[go_tytab_get(stmp)]: the recorded [i0typ] for the temp with stamp [stmp],
or [optn_nil] if the temp was never recorded (a [trxi0i1]-invented temp
with no source [i0exp]).  Called by the emitter's type-recovery fallback.
*)
fun
go_tytab_get
(stmp: stamp): i0typopt
//
(*
[go_tytab_reset]: clear the table.  Not needed for the single-file-per-run
driver, but provided so a future multi-file emitter run cannot read stale
entries from a previous file.
*)
fun
go_tytab_reset((*void*)): void
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_SATS_go1emit_tytab0.sats] *)
(***********************************************************************)
