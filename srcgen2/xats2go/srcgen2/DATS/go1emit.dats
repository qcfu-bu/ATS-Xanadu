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
go1emit — intrep1 -> Go text emitter (milestone M1, REAL EMISSION).
//
[i1parsed_go1emit] now genuinely TRAVERSES the IR: it consumes the real
[i1parsed] (so the frontend -> trxd3i0 -> trxi0i1 spine is exercised) and
walks i1dclistopt -> i1dclist -> i1dcl (-> I1Dvaldclst -> i1valdcl ->
i1cmp -> i1let -> i1ins -> i1val) emitting Go between the
//==XATS2GO-BEGIN==/ //==XATS2GO-END== sentinels. The emitted program
imports the hand-written [xatsgo] runtime and, run via [go build]/[go
run], prints the SAME BYTES as the JS backend for the same source.
//
This file holds the top-level entry + the list/optn iterators; the
per-node walk lives in go1emit_decl00.dats + go1emit_dynexp.dats +
go1emit_utils0.dats (mirroring the js1emit file split).
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
(* ****** ****** *)
(* ****** ****** *)
//
#staload ".\
/../../xats2cc\
/srcgen1/SATS/intrep0.sats"//...
//
#staload "./../SATS/intrep1.sats"
#staload "./../SATS/xats2go.sats"
#staload "./../SATS/go1emit.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
fprintln
(filr: FILR): void =
(
strnfpr(filr, "\n"))//endfun
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1dclist_go1emit
  (dcls, env0) = let
fun
loop
( dcls: i1dclist
, env0: !envx2go): void =
(
case+ dcls of
| list_nil() => ()
| list_cons(dcl1, dcls) =>
  (
  i1dcl_go1emit(dcl1, env0);
  loop(dcls, env0)))
in
loop(dcls, env0)
end//endof[i1dclist_go1emit(dcls,env0)]
//
(* ****** ****** *)
//
#implfun
i1valdclist_go1emit
  (i1vs, env0) = let
fun
loop
( i1vs: i1valdclist
, env0: !envx2go): void =
(
case+ i1vs of
| list_nil() => ()
| list_cons(idcl, i1vs) =>
  (
  i1valdcl_go1emit(idcl, env0);
  loop(i1vs, env0)))
in
loop(i1vs, env0)
end//endof[i1valdclist_go1emit(i1vs,env0)]
//
(* ****** ****** *)
//
#implfun
i1dclistopt_go1emit
  (dopt, env0) =
(
case+ dopt of
| optn_nil() => ((*void*))
| optn_cons(dcls) => i1dclist_go1emit(dcls, env0))
//endof[i1dclistopt_go1emit(dopt,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
PASS-1 walk (M2.2): emit ONLY the user-defined function declarations
(I1Dfundclst) at PACKAGE level.  Every other decl is skipped here (it is
emitted by the in-main pass).  This is how Go's "func at package scope"
constraint is satisfied while still walking the single flat i1dclist.
*)
#implfun
i1dclistopt_go1emit_funs
  (dopt, env0) =
(
case+ dopt of
| optn_nil() => ((*void*))
| optn_cons(dcls) => i1dclist_go1emit_funs(dcls, env0))
//endof[i1dclistopt_go1emit_funs(dopt,env0)]
//
#implfun
i1dclist_go1emit_funs
  (dcls, env0) = let
fun
loop
( dcls: i1dclist
, env0: !envx2go): void =
(
case+ dcls of
| list_nil() => ()
| list_cons(dcl1, dcls) =>
  (
  // delegate EVERY decl: i1dcl_go1emit_fun unwraps the env/wrapper nodes
  // (I1Ddclenv / I1Dtmpsub) and emits ONLY the function group inside (if
  // any), skipping everything else.  (Top-level functions surface wrapped
  // as I1Ddclenv(I1Dfundclst(...), freevars), so a bare I1Dfundclst check
  // would miss them.)
  i1dcl_go1emit_fun(dcl1, env0);
  loop(dcls, env0)))
in
loop(dcls, env0)
end//endof[i1dclist_go1emit_funs(dcls,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1parsed_go1emit
  (ipar, filr) = let
//
// The parsed declaration list is the IR payload consumed by the two emission
// passes below.
//
val parsed = i1parsed_parsed$get(ipar)
//
// M1 IR-DUMP (debug aid): print the whole i1parsed to stderr so the emitted
// Go can be checked against the EXACT IR nodes it came from.  DISABLED as of
// M2.6c: [i1parsed_fprint] routes through this build's LOCAL [i1val_fprint]
// (intrep1_print0.dats), which (a) has NO case for the M2.6c lvalue nodes
// [I1Vlpft]/[I1Vlpbx]/[I1Vlpcn] -> falls through to XATS000_cfail, and (b) is
// errck'd-to-a-comment in the prebuilt bundle so a fix that adds a directly-
// reachable call to it surfaces as an unbound reference (a pre-existing
// libbundle defect, same class as i0varfst/tokenfpr).  So the dump crashed on
// EVERY `var`+`:=` program -- which is exactly the M2.6c surface.  The dump is
// a debug nicety, NOT part of the emit contract; turning it off keeps the
// emitter working for mutation programs.  (Re-enable for a non-`var` program
// by uncommenting if you need the spec dump.)
//
(*
val () = prerrsln("[go1emit] IR-DUMP-BEGIN")
val () =
let
val out0 = g_stderr((*0*))
in i1parsed_fprint(ipar, out0); prerrsln("") end
val () = prerrsln("[go1emit] IR-DUMP-END")
*)
//
val env0 = envx2go_make_out(filr)
//
in//let
(
  envx2go_free_nil(env0)) where
{
//
// --- Go file preamble (between the extraction sentinels) ---------------
//
val () = strnfpr(filr, "//==XATS2GO-BEGIN==\n")
//
val () = strnfpr(filr, "package main\n")
val () = strnfpr(filr, "\n")
val () = strnfpr(filr, "import \"xatsgo\"\n")
val () = strnfpr(filr, "\n")
val () =
strnfpr
(filr, "// keep the xatsgo import live even if main is trivial.\n")
val () = strnfpr(filr, "var _ = xatsgo.XATSNIL\n")
val () = strnfpr(filr, "\n")
//
// --- PASS 1: user-defined functions at PACKAGE level (M2.2) ------------
// Go requires `func name(...) {...}` declarations at package scope, not
// inside main; hoisting them here also lets recursion resolve naturally.
// This pass emits ONLY I1Dfundclst nodes (nind = 0); the in-main pass
// below SKIPS them.  (Functions never reference main-local temps -- they
// close only over their own params + captured env -- so order is safe.)
//
val () = i1dclistopt_go1emit_funs(parsed, env0)
//
val () = strnfpr(filr, "func main() {\n")
//
// --- PASS 2: the top-level effect cmps inside func main ---------------
// (indented one level; SKIPS I1Dfundclst, already emitted in pass 1).
//
val () = envx2go_incnind(env0, 1(*++*))
val () = i1dclistopt_go1emit(parsed, env0)
val () = strnfpr(filr, "\txatsgo.XATS2GO_flush_pending()\n")
val () = envx2go_decnind(env0, 1(*--*))
//
val () = strnfpr(filr, "}\n")
//
val () = strnfpr(filr, "//==XATS2GO-END==\n")
//
}(*where*)
end(*let*)//endof[i1parsed_go1emit(ipar,filr)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_go1emit.dats] *)
(***********************************************************************)
