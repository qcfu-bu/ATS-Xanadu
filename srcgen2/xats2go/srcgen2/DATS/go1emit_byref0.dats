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
go1emit_byref0 — self-hosting GAP A1 — the IMPLEMENTATION of the
by-reference-parameter STAMP SET.  See go1emit_byref0.sats for the design
rationale (what/Go-mapping/population/ordering).
//
The store is a PROCESS-GLOBAL [a0ref] holding a [list(stamp)] used as a set
-- the exact module-level mutable-ref idiom used for the tytab side-table
([go1emit_tytab0.dats]) and [the_i1tnm_stamp_new]'s stamper (intrep1.dats),
so it is transpiler-safe (the JS backend the emitter runs on already
supports [a0ref_make_1val]/[a0ref_get]/[a0ref_set]).  A linear list is fine:
the set is small (only the by-ref params of the functions being emitted) and
the membership test runs only at the read/write/call sites that mention a
param temp.
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
#staload "./../SATS/go1emit_byref0.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#typedef stamplst = list(stamp)
//
(* ****** ****** *)
//
fun
stmp_eqb
(s1: stamp, s2: stamp): bool =
(
  stamp_cmp(s1, s2) = 0)
//
fun
stmp_mem
(stps: stamplst, stmp: stamp): bool =
(
case+ stps of
|list_nil() => false
|list_cons(s1, stps1) =>
  (if stmp_eqb(stmp, s1) then true else stmp_mem(stps1, stmp))
)//endof[stmp_mem(stps,stmp)]
//
(* ****** ****** *)
(* ****** ****** *)
//
local
//
(*
The process-global by-ref param stamp set.  Initialized empty; populated as
each function/closure's params are emitted; read at the body's read/write/
call sites (same process, same in-order traversal -- see the SATS ORDERING
argument).
*)
val
the_go_byref_ref =
a0ref_make_1val<stamplst>(list_nil(*void*))
//
in//local
//
(* ****** ****** *)
//
#implfun
byref_add
(stmp) =
let
  val stps = a0ref_get<stamplst>(the_go_byref_ref)
in//let
  // de-dup defensively: skip if already present.
  if stmp_mem(stps, stmp)
  then ((*void*))
  else a0ref_set<stamplst>(the_go_byref_ref, list_cons(stmp, stps))
end//let//endof[byref_add(stmp)]
//
(* ****** ****** *)
//
#implfun
byref_has
(stmp) =
let
  val stps = a0ref_get<stamplst>(the_go_byref_ref)
in//let
  stmp_mem(stps, stmp)
end//let//endof[byref_has(stmp)]
//
(* ****** ****** *)
//
#implfun
byref_reset
((*void*)) =
  a0ref_set<stamplst>(the_go_byref_ref, list_nil(*void*))
//
(* ****** ****** *)
//
end(*local*)//endof[local(the_go_byref_ref)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_go1emit_byref0.dats] *)
(***********************************************************************)
