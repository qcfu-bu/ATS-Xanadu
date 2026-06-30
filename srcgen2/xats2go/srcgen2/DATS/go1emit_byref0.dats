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
  s1 = s2)
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
fun
the_go_byref_get
((*void*)): stamplst =
(
case+ a0ref_get<stamplst>(the_go_byref_ref) of
|list_nil() => list_nil()
|list_cons(s1, stps1) => list_cons(s1, stps1)
)
//
in//local
//
(* ****** ****** *)
//
#implfun
byref_add
(stmp) =
let
  val stps = the_go_byref_get((*void*))
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
  val stps = the_go_byref_get((*void*))
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
local
//
// GO-ARM MODE flag (CATS/GO prelude pivot).  Default false; set by the driver
// for a `--go-arm` build.  See the SATS.
val
the_go_arm_ref =
a0ref_make_1val<bool>(false)
//
in//local
//
#implfun
go_arm_set
((*void*)) =
  a0ref_set<bool>(the_go_arm_ref, true)
//
#implfun
go_arm_getq
((*void*)) =
  a0ref_get<bool>(the_go_arm_ref)
//
end(*local*)//endof[local(the_go_arm_ref)]
//
(* ****** ****** *)
(* ****** ****** *)
//
local
//
// BLOCK-FORM RETURN-MODE GATE.  Default false (genuine-tail behavior); set true
// by [i1letlst_go1emit_p] around a NON-LAST let.  See the SATS.
val
the_block_force_value_ref =
a0ref_make_1val<bool>(false)
//
in//local
//
#implfun
block_force_value_set
(b) =
  a0ref_set<bool>(the_block_force_value_ref, b)
//
#implfun
block_force_value_get
((*void*)) =
  a0ref_get<bool>(the_block_force_value_ref)
//
end(*local*)//endof[local(the_block_force_value_ref)]
//
(* ****** ****** *)
(* ****** ****** *)
//
local
//
// the nullary-instance temp -> result-func-param-type map (go-arm higher-order
// path).  A linear assoc list of (stamp, paramty-string).  See SATS.
#typedef nient = @(stamp, strn)
#typedef nientlst = list(nient)
//
val
the_nullary_inst_ref =
a0ref_make_1val<nientlst>(list_nil(*void*))
//
fun
nient_memq
(ents: nientlst, stmp: stamp): bool =
(
case+ ents of
|list_nil() => false
|list_cons(@(s1, _), ents1) =>
  if (stamp_cmp(s1, stmp) = 0) then true else nient_memq(ents1, stmp)
)
//
fun
nient_find
(ents: nientlst, stmp: stamp): strn =
(
case+ ents of
|list_nil() => ""
|list_cons(@(s1, p1), ents1) =>
  if (stamp_cmp(s1, stmp) = 0) then p1 else nient_find(ents1, stmp)
)
//
in//local
//
#implfun
nullary_inst_add
(stmp, paramty) =
let
  val ents = a0ref_get<nientlst>(the_nullary_inst_ref)
in
  if nient_memq(ents, stmp)
  then ((*void*))
  else a0ref_set<nientlst>(the_nullary_inst_ref, list_cons(@(stmp, paramty), ents))
end
//
#implfun
nullary_inst_has
(stmp) =
  nient_memq(a0ref_get<nientlst>(the_nullary_inst_ref), stmp)
//
#implfun
nullary_inst_paramty
(stmp) =
  nient_find(a0ref_get<nientlst>(the_nullary_inst_ref), stmp)
//
(* ****** ****** *)
//
// the instance-func emitted-return-type map (go-arm RESULT boundary).  Same
// linear assoc-list shape as the nullary-instance map.  See SATS.
val
the_inst_retty_ref =
a0ref_make_1val<nientlst>(list_nil(*void*))
//
#implfun
inst_retty_add
(stmp, retty) =
let
  val ents = a0ref_get<nientlst>(the_inst_retty_ref)
in
  if nient_memq(ents, stmp)
  then ((*void*))
  else a0ref_set<nientlst>(the_inst_retty_ref, list_cons(@(stmp, retty), ents))
end
//
#implfun
inst_retty_get
(stmp) =
  nient_find(a0ref_get<nientlst>(the_inst_retty_ref), stmp)
//
(* ****** ****** *)
//
// the FUNCTION emitted-return-type map (self-emission RESULT boundary), keyed by
// a function's d2var stamp.  Same linear assoc-list shape.  See the SATS.
val
the_funretty_ref =
a0ref_make_1val<nientlst>(list_nil(*void*))
//
#implfun
funretty_add
(stmp, retty) =
let
  val ents = a0ref_get<nientlst>(the_funretty_ref)
in
  if nient_memq(ents, stmp)
  then ((*void*))
  else a0ref_set<nientlst>(the_funretty_ref, list_cons(@(stmp, retty), ents))
end
//
#implfun
funretty_get
(stmp) =
  nient_find(a0ref_get<nientlst>(the_funretty_ref), stmp)
//
// the CURRENT-FUNCTION return type (self-emission return boundary).  A single
// process-global string.  See the SATS.
val
the_cur_funretty_ref =
a0ref_make_1val<strn>("")
//
#implfun
cur_funretty_set
(ty) =
  a0ref_set<strn>(the_cur_funretty_ref, ty)
//
#implfun
cur_funretty_get
((*void*)) =
  a0ref_get<strn>(the_cur_funretty_ref)
//
(* ****** ****** *)
//
// the emitted-Go-type map (go-arm general ARG boundary).  Same assoc-list shape.
// See the SATS.  Keyed by temp stamp -> its emitted Go type (a param's `any`, a
// func temp's `func(...)...`).
val
the_goemit_ty_ref =
a0ref_make_1val<nientlst>(list_nil(*void*))
//
#implfun
goemit_ty_add
(stmp, ty) =
let
  val ents = a0ref_get<nientlst>(the_goemit_ty_ref)
in
  if nient_memq(ents, stmp)
  then ((*void*))
  else a0ref_set<nientlst>(the_goemit_ty_ref, list_cons(@(stmp, ty), ents))
end
//
#implfun
goemit_ty_get
(stmp) =
  nient_find(a0ref_get<nientlst>(the_goemit_ty_ref), stmp)
//
end(*local*)//endof[local(the_nullary_inst_ref)]
//
(* ****** ****** *)
(* ****** ****** *)
//
local
//
// the dp2tr-pointer stamp set ($eval/p2tr deref).  Same linear-list-as-set
// idiom as the byref set.  See the SATS.
val
the_dp2tr_ptr_ref =
a0ref_make_1val<stamplst>(list_nil(*void*))
//
in//local
//
#implfun
dp2tr_ptr_add
(stmp) =
let
  val stps = a0ref_get<stamplst>(the_dp2tr_ptr_ref)
in
  if stmp_mem(stps, stmp)
  then ((*void*))
  else a0ref_set<stamplst>(the_dp2tr_ptr_ref, list_cons(stmp, stps))
end
//
#implfun
dp2tr_ptr_has
(stmp) =
  stmp_mem(a0ref_get<stamplst>(the_dp2tr_ptr_ref), stmp)
//
end(*local*)//endof[local(the_dp2tr_ptr_ref)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_go1emit_byref0.dats] *)
(***********************************************************************)
