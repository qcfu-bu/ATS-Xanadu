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
go1emit_decl00 — the declaration-level IR walk for the Go backend (M1).
Mirrors xats2js/srcgen2/DATS/js1emit_decl00.dats's i1dcl/i1valdcl
dispatch, emitting Go. Only the constructors the M1 walking skeleton
(test01) needs are handled; the rest are emitted as Go line comments and
[prerrln]'d to stderr (never silently-wrong Go).
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
#staload // SYM =
"./../../../SATS/xsymbol.sats"
#staload // LOC =
"./../../../SATS/locinfo.sats"
#staload // BAS =
"./../../../SATS/xbasics.sats"
#staload // LEX =
"./../../../SATS/lexing0.sats"
#staload // D2E =
"./../../../SATS/dynexp2.sats"
//
(* ****** ****** *)
//
#staload ".\
/../../xats2cc\
/srcgen1/SATS/intrep0.sats"//...
//
#staload "./../SATS/intrep1.sats"
#staload "./../SATS/xats2go.sats"
#staload "./../SATS/go1emit.sats"
#staload "./../SATS/go1emit_byref0.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#symload filr with envx2go_filr$get
#symload nind with envx2go_nind$get
#symload node with token_get_node
#symload node with dimpl_get_node
#symload name with d2cst_get_name
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
(*
i1dcl_go1emit: dispatch on the top-level declaration.  For test01 only
I1Dvaldclst carries executable code; the staload/include/none markers
(I1Di0dcl / I1Dinclude / I1Dnone1 / ...) are emitted as a one-line Go
comment recording the location, exactly like js1emit's f0_otherwise.
*)
#implfun
i1dcl_go1emit
(dcl0, env0) =
let
val filr = env0.filr()
val nind = env0.nind()
in//let
//
case+
dcl0.node() of
//
|I1Dvaldclst _ =>
(
  f0_valdclst(dcl0, env0))
//
// M2.6c: a MUTABLE local `var x = init` -> a Go `var goxtnm<x> <T> = <init>`
// (addressable, so its fields are assignable).  Surfaces as a local decl
// inside an I1INSlet0 block (verified: `let var p = @(1,2) in ... end`).
|I1Dvardclst _ =>
(
  f0_vardclst(dcl0, env0))
//
// A TOP-LEVEL function is emitted at PACKAGE level in PASS 1
// (i1dcl_go1emit_fun); this in-main / top-level PASS-2 walk SKIPS a bare
// I1Dfundclst (no Go output -> no duplication).  A top-level fun usually
// surfaces here WRAPPED (I1Ddclenv(I1Dfundclst,..)) and falls into
// [f0_otherwise] -> a harmless `// (skipped ..)` comment (it was already
// hoisted).  A NESTED function does NOT come through [i1dcl_go1emit] -- it
// comes through [i1dcl_go1emit_local] (the I1INSlet0 decl walk), which routes
// a (wrapped) I1Dfundclst to [f0_localfun] (a local Go closure).  So nested vs
// top-level is distinguished by the ENTRY POINT, never double-emitted.
|I1Dfundclst _ => ((*void*))
|I1Dimplmnt0 _ => ((*void*))
//
| _(*otherwise*) =>
(
  f0_otherwise(dcl0, env0))
//
end where//endof[i1dcl_go1emit(dcl0,env0)]
{
//
fun
f0_valdclst
(
dcl0: i1dcl,
env0: !envx2go): void =
let
//
val filr = env0.filr()
val nind = env0.nind()
val loc0 = dcl0.lctn()
//
val-
I1Dvaldclst
(tknd, i1vs) = dcl0.node()
//
val () =
(
nindfpr(filr, nind);
strnfpr(filr, "// I1Dvaldclist(");
loctn_fprint(loc0, filr); strnfpr(filr, ")"); strnfpr(filr, "\n"))
//
val () =
(
  i1valdclist_go1emit(i1vs, env0))
//
in//let
((*void*)) end//endof[f0_valdclst(dcl0,env0)]
//
(* ****** ****** *)
//
fun
f0_vardclst
(
dcl0: i1dcl,
env0: !envx2go): void =
let
val-
I1Dvardclst
(tknd, i1vs) = dcl0.node()
in//let
  i1vardclist_go1emit(i1vs, env0)
end//endof[f0_vardclst(dcl0,env0)]
//
(* ****** ****** *)
//
fun
f0_otherwise
(
dcl0: i1dcl,
env0: !envx2go): void =
let
val filr = env0.filr()
val nind = env0.nind()
val loc0 = dcl0.lctn()
in//let
(
nindfpr(filr, nind);
strnfpr(filr, "// (skipped non-val dcl @ ");
loctn_fprint(loc0, filr); strnfpr(filr, ")"); strnfpr(filr, "\n")) end
//endof[f0_otherwise(dcl0,env0)]
//
}(*where*)//endof[i1dcl_go1emit(dcl0,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== GAP-1: NESTED (LOCAL) FUNCTIONS as Go LOCAL CLOSURES               ==
=======================================================================
//
A NESTED function -- a `fun` declared inside a function body / `let .. in ..
end` / `where { .. }` -- surfaces (in the let-block decl list) as an
I1Ddclenv(I1Dfundclst(..), freevars) (or I1Dtmpsub/I1Dstatic wrapper).  It
CAPTURES surrounding locals and is often self-recursive, so it must NOT be
hoisted to package level (M2.2 hoisting can't see the captured locals).
Instead it is emitted RIGHT AT ITS DECLARATION POINT as a Go LOCAL CLOSURE --
the M2.5 fix0 idiom `var f F; f = func(..){..}` (the pre-declared `var` enables
self/mutual recursion; Go's lexical capture handles the surrounding locals,
the IR having already rewritten each captured free var to its outer Go local).
//
The routing is split from the top-level pass: a nested decl comes through
[i1dcl_go1emit_local] (the I1INSlet0 decl walk, see [i1dclist_go1emit_local]),
which sends a (wrapped) I1Dfundclst to [f0_localfun] and everything else back
to the normal [i1dcl_go1emit].  A TOP-LEVEL fun does NOT come through here (it
is hoisted in PASS 1 and SKIPPED by [i1dcl_go1emit] in PASS 2), so it is never
double-emitted.
//
[dcl_is_fundclst]: does this decl reduce (under the env/template wrappers) to
an I1Dfundclst?  (Used both by [i1dcl_go1emit]'s top-level SKIP guards and by
[i1dcl_go1emit_local]'s local-closure routing.)
*)
fun
dcl_is_fundclst
(dcl1: i1dcl): bool =
(
case+ dcl1.node() of
|I1Dfundclst _ => true
|I1Ddclenv(idcl2, _) => dcl_is_fundclst(idcl2)
|I1Dtmpsub(_, idcl2) => dcl_is_fundclst(idcl2)
|I1Dstatic(_, idcl2) => dcl_is_fundclst(idcl2)
| _(*else*) => false
)//endof[dcl_is_fundclst(dcl1)]
//
(*
[localfun_unwrap]: strip the env/template wrappers down to the bare
I1Dfundclst (the caller already checked [dcl_is_fundclst]).
*)
fun
localfun_unwrap
(dcl1: i1dcl): i1dcl =
(
case+ dcl1.node() of
|I1Dfundclst _ => dcl1
|I1Ddclenv(idcl2, _) => localfun_unwrap(idcl2)
|I1Dtmpsub(_, idcl2) => localfun_unwrap(idcl2)
|I1Dstatic(_, idcl2) => localfun_unwrap(idcl2)
| _(*else: unreachable -- guarded by dcl_is_fundclst*) => dcl1
)//endof[localfun_unwrap(dcl1)]
//
(*
[localfun_funty]: the Go function-TYPE `func(T0,T1) Tret` for one local
fundcl, recovered from its parallel d2cst's static type (the SAME signature
source a top-level fun uses, [gotypes_of_funstyp]); a missing d2cst falls back
to the fundcl's own param d2vars + body inference.  This is the type of the
pre-declared `var <name> <funty>` self-reference target.
*)
fun
localfun_funty
( ifun: i1fundcl
, dcopt: optn(d2cst)): strn =
let
  val (argtys, retty) =
  (
  case+ dcopt of
  |optn_cons(dcst) => gotypes_of_funstyp(d2cst_get_styp(dcst))
  |optn_nil() =>
    let
      val fjas = i1fundcl_farg$get(ifun)
    in
      @(gotypes_of_fjarglst(fjas), "any")
    end)
in
  gofunctype_of_fjarglst(argtys, retty)
end//endof[localfun_funty(ifun,dcopt)]
//
(*
[localfun_predecl]: PASS A -- pre-declare `var <name> <funty>` for EVERY
fundcl in the group BEFORE any assignment, so a self-recursive call (and a
mutually-recursive call to a sibling in the same `fun .. and ..` group)
resolves to the in-scope `var`.  [d2cs] is the parallel d2cst list (positional
with [i1fs]); a desync yields optn_nil() -> `any`-typed func.
*)
fun
localfun_predecl
( i1fs: i1fundclist
, d2cs: d2cstlst
, env0: !envx2go): void =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
in//let
  case+ i1fs of
  |list_nil() => ((*void*))
  |list_cons(i1f1, i1fs1) =>
    let
      val (dcopt, d2cs1) =
      (
      case+ d2cs of
      |list_nil() => (optn_nil(): optn(d2cst), list_nil(): d2cstlst)
      |list_cons(d2c1, d2cs1) => (optn_cons(d2c1), d2cs1))
      val dvar = i1fundcl_dpid$get(i1f1)
      val funty = localfun_funty(i1f1, dcopt)
      val () =
      (
      nindfpr(filr, nind);
      strnfpr(filr, "var "); d2vargo1(filr, dvar);
      strnfpr(filr, " "); strnfpr(filr, funty); strnfpr(filr, "\n"))
    in
      localfun_predecl(i1fs1, d2cs1, env0)
    end
end//let//endof[localfun_predecl(i1fs,d2cs,env0)]
//
(*
[localfun_emit_params]: emit the local closure's `<p0> <T0>, <p1> <T1>` param
list (zip the param i1tnms with the recovered Go types; "any" fallback).  A
self-contained copy of the M2.5 fjarglst_go1emit_typed_params (which lives in a
different where-block, hence not reusable here).
*)
fun
localfun_emit_params
( filr: FILR
, fjas: fjarglst
, ptys: list(strn)): void =
let
  val ptnms = params_of_fjarglst(fjas)
  //
  fun
  loop
  (need_sep: bool, ts: i1tnmlst, gs: list(strn)): void =
  (
  case+ ts of
  |list_nil() => ((*void*))
  |list_cons(p1, ts1) =>
    let
      val (goty, gs1) =
      (
      case+ gs of
      |list_nil() => @("any", list_nil())
      |list_cons(g1, gs1) => @(g1, gs1))
      val () =
      (
      if need_sep then strnfpr(filr, ", ");
      i1tnmgo1(filr, p1); strnfpr(filr, " "); strnfpr(filr, goty))
      // EMITTED-TYPE: record this closure param's emitted Go type (see
      // fjarglst_go1emit_params).
      val () = goemit_ty_add(i1tnm_stmp$get(p1), goty)
    in
      loop(true, ts1, gs1)
    end
  )
in
  loop(false, ptnms, ptys)
end//endof[localfun_emit_params(filr,fjas,ptys)]
//
(*
[localfun_assign]: PASS B -- emit `<name> = func(<typed params>) <ret> {
<body> }` for each fundcl, binding the (already-declared) `var`.  The body is
emitted in RETURN mode exactly like a top-level fun: if it has a reachable
TAIL self-call (i1cmp_body_has_tailcall) it is wrapped in a Go `for { ...
param=newval; continue }` loop (O(1) stack -- the local-closure TCO the task
asked for); otherwise a plain recursive call.  The self-call lowers to
I1INSdapp(I1Vfenv(<this fundcl's dvar>),..) whose callee emits [d2vargo1] = the
same `<name>` -- resolving to the pre-declared `var`.  Captured surrounding
locals are read directly via Go's lexical closure (the IR already rewrote each
captured free var to its outer Go local).
*)
fun
localfun_assign
( i1fs: i1fundclist
, d2cs: d2cstlst
, env0: !envx2go): void =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
in//let
  case+ i1fs of
  |list_nil() => ((*void*))
  |list_cons(i1f1, i1fs1) =>
    let
      val (dcopt, d2cs1) =
      (
      case+ d2cs of
      |list_nil() => (optn_nil(): optn(d2cst), list_nil(): d2cstlst)
      |list_cons(d2c1, d2cs1) => (optn_cons(d2c1), d2cs1))
      //
      val dvar = i1fundcl_dpid$get(i1f1)
      val fjas = i1fundcl_farg$get(i1f1)
      val tdxp = i1fundcl_tdxp$get(i1f1)
      //
      // param Go types: the SAME signature [gotypes_of_funstyp] gives a
      // top-level fun; fall back to the param d2vars when no d2cst.
      val argtys =
      (
      case+ dcopt of
      |optn_cons(dcst) =>
        let val (ats, _) = gotypes_of_funstyp(d2cst_get_styp(dcst)) in ats end
      |optn_nil() => gotypes_of_fjarglst(fjas))
      //
      // GAP A1: register this LOCAL closure's by-REFERENCE params (`&T` -> Go
      // `*T`) BEFORE emitting its body (so the body's read/write/call emitters
      // deref/pass each pointer param).  Uses the d2cst styp when present (the
      // SAME source [argtys] came from); falls back to the fix-var's own styp.
      val () = byref_register_params
        (fjas,
         (case+ dcopt of
          |optn_cons(dcst) => d2cst_get_styp(dcst)
          |optn_nil() => d2var_get_styp(dvar)))
      //
      // `<name> = func(<p0> <T0>, ..) <ret> {`
      val () =
      (
      nindfpr(filr, nind);
      d2vargo1(filr, dvar); strnfpr(filr, " = func("))
      val () = localfun_emit_params(filr, fjas, argtys)
      val retty =
      (
      case+ dcopt of
      |optn_cons(dcst) =>
        let val (_, rt) = gotypes_of_funstyp(d2cst_get_styp(dcst)) in rt end
      |optn_nil() => goretty_of_funvar(dvar))
      val () =
      (
      strnfpr(filr, ") "); strnfpr(filr, retty);
      strnfpr(filr, " {"); strnfpr(filr, "\n"))
      //
      // body: return mode, TCO-loop when it has a reachable tail self-call.
      val () =
      (
      case+ tdxp of
      |TEQI1CMPnone() =>
        (
        envx2go_incnind(env0, 1(*++*));
        nindfpr(filr, envx2go_nind$get(env0));
        strnfpr(filr, "panic(\"xats2go: local function with no body\")");
        strnfpr(filr, "\n");
        envx2go_decnind(env0, 1(*--*)))
      |TEQI1CMPsome(_, icmp) =>
        let
          val hastc = i1cmp_body_has_tailcall(icmp)
          val bnds  = binds_of_fjarglst(fjas)
        in
        if hastc then
          let
            val params = params_of_fjarglst(fjas)
            val () = envx2go_incnind(env0, 1(*++*))
            val () = (nindfpr(filr, envx2go_nind$get(env0)); strnfpr(filr, "for {\n"))
            val () = envx2go_incnind(env0, 1(*++*))
            val () = i1cmp_go1emit_ret(icmp, params, bnds, env0)
            val () = envx2go_decnind(env0, 1(*--*))
            val () = (nindfpr(filr, envx2go_nind$get(env0)); strnfpr(filr, "}\n"))
            val () = envx2go_decnind(env0, 1(*--*))
          in ((*void*)) end
        else
          (
          envx2go_incnind(env0, 1(*++*));
          i1cmp_go1emit_ret(icmp, list_nil(), bnds, env0);
          envx2go_decnind(env0, 1(*--*)))
        end)
      //
      // closing `}` of the func literal.
      val () = (nindfpr(filr, nind); strnfpr(filr, "}"); strnfpr(filr, "\n"))
    in
      localfun_assign(i1fs1, d2cs1, env0)
    end
end//let//endof[localfun_assign(i1fs,d2cs,env0)]
//
(*
[f0_localfun]: emit a NESTED function group (a `fun ..` / `fun .. and ..`
inside a body / let / where) as Go LOCAL CLOSURES at this declaration point:
  var f F                       (PASS A -- all `var`s first, for self/mutual rec)
  var g G
  f = func(..){ ..f(..)..g(..).. }   (PASS B -- the assignments)
  g = func(..){ .. }
A TEMPLATE local fun (non-empty t2qaglst) is reported UNHANDLED (M3), matching
the top-level path.  The [dcl1] passed in may be a (wrapped) I1Dfundclst --
[localfun_unwrap] strips to the bare node.
*)
fun
f0_localfun
(dcl1: i1dcl, env0: !envx2go): void =
let
  val filr = env0.filr()
  val dclF = localfun_unwrap(dcl1)
  val-I1Dfundclst(_, _, tqas, d2cs, i1fs) = dclF.node()
in//let
  case+ tqas of
  |list_nil() =>
    (
    localfun_predecl(i1fs, d2cs, env0);
    localfun_assign(i1fs, d2cs, env0))
  |list_cons _ =>
    (
    nindfpr(filr, envx2go_nind$get(env0));
    strnfpr(filr, "// unsupported template local fundclst"); strnfpr(filr, "\n"))
end//let//endof[f0_localfun(dcl1,env0)]
//
(* ****** ****** *)
//
(*
[i1dcl_go1emit_local]: the per-decl entry for the decls INSIDE a function body
/ let-in / where block (the I1INSlet0 decl list).  A (wrapped) I1Dfundclst is a
NESTED function -> emit it as a LOCAL Go closure ([f0_localfun]); everything
else routes to the normal [i1dcl_go1emit].  This is what keeps nested funs OUT
of the package-level hoisting (and a TOP-level fun -- handled by the two-pass
walk -- never reaches here).
*)
(*
[impl_name_of_idcl]: the name of the d2cst an I1Dimplmnt0 implements (unwrapping
env/template wrappers); "" for a non-impl decl.  Used to recognize the
`foritm$work` `$work`-hook so it can be emitted as a typed Go closure (the
selective-monomorphized foritm/$work path) instead of being skipped.
*)
fun
impl_name_of_idcl
(idcl: i1dcl): strn =
(
case+ idcl.node() of
|I1Dimplmnt0(_, _, _, dimp, _, _) =>
  (
  case+ dimp.node() of
  |DIMPLone1(dcst) => symbl_get_name(dcst.name())
  |DIMPLone2(dcst, _) => symbl_get_name(dcst.name())
  |DIMPLnon1(_) => "")
|I1Ddclenv(idcl2, _) => impl_name_of_idcl(idcl2)
|I1Dtmpsub(_, idcl2) => impl_name_of_idcl(idcl2)
|I1Dstatic(_, idcl2) => impl_name_of_idcl(idcl2)
| _(*else*) => ""
)//endof[impl_name_of_idcl(idcl)]
//
(*
[unwrap_idcl]: strip env/template wrappers to the inner bare decl.
*)
fun
unwrap_idcl
(idcl: i1dcl): i1dcl =
(
case+ idcl.node() of
|I1Ddclenv(idcl2, _) => unwrap_idcl(idcl2)
|I1Dtmpsub(_, idcl2) => unwrap_idcl(idcl2)
|I1Dstatic(_, idcl2) => unwrap_idcl(idcl2)
| _(*else*) => idcl
)//endof[unwrap_idcl(idcl)]
//
(*
[foritm_work_emit]: emit the in-scope `#impltmp foritm$work<char>` body as a
TYPED, NAMED Go closure `XATS_foritm_work := func(c0 rune) <ret> { <body> }`.
The element type (char -> rune) is threaded via [gotypes_of_fjarglst] (the param
d2var's styp), so the body's char comparisons typecheck natively; the closure
captures surrounding locals (e.g. a `var n`) by Go lexical capture.  Paired with
the loop emitted at the `strn_foritm` call site (go1emit_dynexp).  ASSUMPTION: at
most one foritm$work per Go block (the common case); nested foritm would need a
stamp-disambiguated name.
*)
fun
foritm_work_emit
( filr: FILR
, dcl0: i1dcl
, env0: !envx2go): void =
let
  val-
  I1Dimplmnt0
  (_, _, _, _, fjas, icmp) = unwrap_idcl(dcl0).node()
  val bnds = binds_of_fjarglst(fjas)
  val argtys = gotypes_of_fjarglst(fjas)
  val retty = gotype_of_lam_ret(icmp, bnds)
in
  nindfpr(filr, env0.nind());
  strnfpr(filr, "XATS_foritm_work := func(");
  localfun_emit_params(filr, fjas, argtys);
  strnfpr(filr, ") ");
  strnfpr(filr, retty);
  strnfpr(filr, " {\n");
  envx2go_incnind(env0, 1(*++*));
  i1cmp_go1emit_ret(icmp, list_nil(), bnds, env0);
  envx2go_decnind(env0, 1(*--*));
  nindfpr(filr, env0.nind());
  strnfpr(filr, "}\n")
end//endof[foritm_work_emit(filr,dcl0,env0)]
//
(*
[tmpw_hook_suffix]: the Go-identifier suffix for a recognized template-method
WORKER hook ("map$fopr" -> "map_fopr"); "" for a non-hook impl name.  This set
is the Task-#8 worker-forwarding family: template methods whose prelude body the
self-hosted frontend fails to attach (F3PERR0-TIMQ1), leaving the worker
`#impltmp` as a separate local decl that would otherwise be skipped while the
call shortcuts to a worker-less 1-arg runtime prim.
*)
fun
tmpw_hook_suffix
(iname: strn): strn =
(
if (iname = "map$fopr") then "map_fopr" else
if (iname = "exists$test") then "exists_test" else
""
)//endof[tmpw_hook_suffix(iname)]
//
(*
[tmpworker_go1emit]: emit a recognized worker `#impltmp` as a NAMED local Go
closure `XATS_tmpw_<suffix> := func(<params>) <ret> { <body> }` (+ a `_ =` keep-
alive so a block whose template call DID resolve -- and thus inlines the body,
never referencing the closure -- still compiles), and record the hook + param-0
Go type in the tmpworker table for the I1INStimp wrapper emission.  Mirrors
[foritm_work_emit]; same one-per-block assumption.
*)
fun
tmpworker_go1emit
( filr: FILR
, iname: strn
, sfx: strn
, dcl0: i1dcl
, env0: !envx2go): void =
let
  val-
  I1Dimplmnt0
  (_, _, _, _, fjas, icmp) = unwrap_idcl(dcl0).node()
  val bnds = binds_of_fjarglst(fjas)
  val argtys = gotypes_of_fjarglst(fjas)
  val retty = gotype_of_lam_ret(icmp, bnds)
  // an ETA-CONTRACTED worker impl (`#impltmp map$fopr = s2var_get_sort`) has NO
  // value params: the emitted closure is a 0-param THUNK returning the worker
  // FUNCTION.  Record the "@nullary" marker so the call-site adapter invokes the
  // thunk and asserts the returned function (`XATS_tmpw().(func(any) any)(x)`)
  // instead of applying the thunk directly with the element arg.
  val p0ty =
  (
  case+ bnds of
  |list_nil() => "@nullary"
  | _(*cons*) =>
    (
    case+ argtys of
    |list_cons(t1, _) => t1
    |list_nil() => "any"))
  val () = tmpworker_add(iname, p0ty)
in
  nindfpr(filr, env0.nind());
  strnfpr(filr, "XATS_tmpw_"); strnfpr(filr, sfx);
  strnfpr(filr, " := func(");
  localfun_emit_params(filr, fjas, argtys);
  strnfpr(filr, ") ");
  strnfpr(filr, retty);
  strnfpr(filr, " {\n");
  envx2go_incnind(env0, 1(*++*));
  i1cmp_go1emit_ret(icmp, list_nil(), bnds, env0);
  envx2go_decnind(env0, 1(*--*));
  nindfpr(filr, env0.nind());
  strnfpr(filr, "}\n");
  nindfpr(filr, env0.nind());
  strnfpr(filr, "_ = XATS_tmpw_"); strnfpr(filr, sfx); strnfpr(filr, "\n")
end//endof[tmpworker_go1emit(filr,iname,sfx,dcl0,env0)]
//
#implfun
i1dcl_go1emit_local
(dcl0, env0) =
(
if dcl_is_fundclst(dcl0)
then f0_localfun(dcl0, env0)
else
if (impl_name_of_idcl(dcl0) = "foritm$work")
then foritm_work_emit(env0.filr(), dcl0, env0)
else
let
  val iname = impl_name_of_idcl(dcl0)
  val sfx = tmpw_hook_suffix(iname)
in
  if (strn_length(sfx) > 0)
  then tmpworker_go1emit(env0.filr(), iname, sfx, dcl0, env0)
  else i1dcl_go1emit(dcl0, env0)
end
)//endof[i1dcl_go1emit_local(dcl0,env0)]
//
(*
[i1dclist_go1emit_local]: walk a let-block's decl list with the local-closure
routing ([i1dcl_go1emit_local]).  Used by the I1INSlet0 emitter (go1emit_dynexp)
in place of the plain [i1dclist_go1emit] so a nested `fun` becomes a local
closure instead of being skipped.
*)
#implfun
i1dclist_go1emit_local
(dcls, env0) =
(
list_foritm$e1nv<x0><e1>(dcls, env0)
) where
{
#vwtpdef e1 = envx2go
#typedef x0 = i1dcl
#impltmp
foritm$e1nv$work
<x0><e1>(dcl1, env0) =
(
  i1dcl_go1emit_local(dcl1, env0))
}(*where*)//endof[i1dclist_go1emit_local(dcls,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
i1valdcl_go1emit: a single [val PAT = CMP].
  - UNIT pattern `()` (I0Ptup0 with no fields): no binding -- just emit the
    computation (its lets + a discarded result).  (test01 etc.)
  - VARIABLE pattern `val x = ...` (I0Pvar) -- M2.3, needed by let-in's inner
    decls: bind the cmp result to the bind's OWN i1tnm (the body references
    [x] through that SAME tnm), i.e. emit the cmp lets then
    `goxtnm<itnm> := <result>`.  A trailing `_ = goxtnm<itnm>` suppressor
    guarantees Go's "declared and not used" never trips (harmless if the body
    later reads it).  WILDCARD `val _ = ...` (I0Pany): emit as effect (no bind).
  - STRUCTURAL patterns (tuples/records/datacons): bind the pattern ROOT temp
    to the initializer result.  The intrep1 binder already maps sub-pattern
    variables to projection values rooted at that temp.
*)
#implfun
i1valdcl_go1emit
(idcl, env0) =
let
//
val filr = env0.filr()
val nind = env0.nind()
//
val dpat = i1valdcl_dpat$get(idcl)
val tdxp = i1valdcl_tdxp$get(idcl)
//
val (itnm, ipat) =
(
case+ dpat of
|I1BNDcons(itnm, ipat, _) => @(itnm, ipat))
//
val isunit =
(
case+ ipat.node() of
|I0Ptup0(_, i0ps) =>
(
case+ i0ps of
|list_nil() => true | list_cons _ => false)
| _(*else*) => false)
//
fun
i0pat_dataconq
(ipat: i0pat): bool =
(
case+ ipat.node() of
|I0Pcon _ => true
|I0Pdap1(ip1) => i0pat_dataconq(ip1)
|I0Pdapp(ip1, _, _) => i0pat_dataconq(ip1)
|I0Ptapq(ip1, _) => i0pat_dataconq(ip1)
| _(*else*) => false)
//
in//let
//
case+ tdxp of
//
|TEQI1CMPnone
( (*void*) ) => ((*void*))
//
|TEQI1CMPsome
(teq1, icmp) =>
let
  // A val-decl's computation is NEVER in function-tail position (the let-body's
  // result is what returns), so a trailing fully-returning if/case in it must
  // emit in VALUE mode -- not `return` (which would escape the enclosing func:
  // the go-arm gseq `beg; iterate; end` suffix-print bug).  GATED on go-arm so
  // the byte-frozen JS suite + rungs 1-8 are untouched.
  val saved_bfv = block_force_value_get()
  // A val-decl's computation is never in function-tail position, so force VALUE
  // mode for its trailing block-forms.  UNGATED from go_arm: the fix is correct
  // in general, and the ONLY non-go-arm Go consumer is the self-host assembly
  // (which needs it -- else a non-tail case-arg leaks `return` and its result
  // temp goes undefined).  go-arm rungs already ran with go_arm=true so their
  // emission is unchanged; the JS suite uses a different emitter.
  val () = block_force_value_set(true)
  val () =
  (
if
isunit
then//then
(
  i1cmp_go1emit(icmp, env0))
else//else
(
case+ ipat.node() of
//
// `val x = CMP`: bind the result to [x]'s i1tnm, then suppress.
|I0Pvar _ =>
  let
    val-I1CMPcons(ilts, ival) = icmp
    val () = i1letlst_go1emit(ilts, icmp, env0)
  in
    // not already-returning (a val initializer is a value), so always bind.
    nindfpr(filr, nind);
    i1tnmgo1(filr, itnm); strnfpr(filr, " := ");
    i1valgo1(filr, ival); strnfpr(filr, "\n");
    nindfpr(filr, nind);
    strnfpr(filr, "_ = "); i1tnmgo1(filr, itnm); strnfpr(filr, "\n")
  end
//
// `val _ = CMP`: a wildcard binding -- emit as a discarded effect.
|I0Pany _ =>
  (
  i1cmp_go1emit(icmp, env0))
//
// Structural pattern: bind the pattern root temp; sub-pattern vars are
// projections rooted at this temp.
| _(*else*) =>
  let
    val-I1CMPcons(ilts, ival) = icmp
    val () = i1letlst_go1emit(ilts, icmp, env0)
    val gty = gotype_of_ival(ival)
    val dcq = i0pat_dataconq(ipat)
    // datacon-scrutinee coercion: bind the matched value as the uniform boxed
    // datatype *xatsgo.XatsCon.  Use [Xats_as_con] (an `any`->*XatsCon helper)
    // rather than a bare `.(*xatsgo.XatsCon)` assert: the assert is INVALID Go
    // when [ival] already has concrete *XatsCon type (e.g. the value is a node
    // accessor result whose recovered emitted type is conservatively "any"),
    // whereas [Xats_as_con] accepts BOTH an interface and a concrete *XatsCon
    // (the concrete value auto-boxes to the `any` param), so the coercion is
    // idempotent.  Same runtime value either way -> program output unchanged.
    val wrapq = (if dcq then (gty = "any") else false)
  in
    nindfpr(filr, nind);
    i1tnmgo1(filr, itnm); strnfpr(filr, " := ");
    (if wrapq then strnfpr(filr, "xatsgo.Xats_as_con(") else ((*void*)));
    i1valgo1(filr, ival);
    (if wrapq then strnfpr(filr, ")") else ((*void*)));
    strnfpr(filr, "\n");
    nindfpr(filr, nind);
    strnfpr(filr, "_ = "); i1tnmgo1(filr, itnm); strnfpr(filr, "\n")
  end
))
  val () = block_force_value_set(saved_bfv)
in//let
  ((*void*))
end//let
//
end//let//endof[i1valdcl_go1emit(idcl,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== MUTABLE LOCAL VARIABLES  (milestone M2.6c)                        ==
=======================================================================
//
A `var x = init` (an I1Dvardclst -> i1vardcl) becomes a Go
    var goxtnm<x> <T> = <init>
where [T] is the var's Go type and [init] is the init cmp's RESULT.  A Go
`var` is ADDRESSABLE, so its fields are valid lvalues: for a FLAT tuple/record
[T] is a value struct and `goxtnm<x>.F0 = v` mutates the local IN PLACE (ATS
value semantics -- a copy is unaffected); for a BOXED one [T] is a `*struct`
and the assignment mutates through the pointer (ATS shared semantics).  This is
the addressable ROOT every I1Vlpft/I1Vlpbx lvalue path bottoms out at.
//
The var's own i1tnm (the dpid bind's i1tnm) IS the Go var name (goxtnm<stamp>),
and the body references the var through that SAME i1tnm (a read is
I1INSflat(I1Vtnm(x)) -> emitted as just `goxtnm<x>`), so decl and use agree by
construction -- no XATSVAR box indirection (unlike the JS backend's
`XATSVAR1(...)` runtime box).
*)
#implfun
i1vardclist_go1emit
(i1vs, env0) =
(
list_foritm$e1nv<x0><e1>(i1vs, env0)
) where
{
#vwtpdef e1 = envx2go
#typedef x0 = i1vardcl
#impltmp
foritm$e1nv$work
<x0><e1>(idcl, env0) =
(
  i1vardcl_go1emit(idcl, env0))
}(*where*)//endof[i1vardclist_go1emit(i1vs,env0)]
//
#implfun
i1vardcl_go1emit
(idcl, env0) =
let
//
val filr = env0.filr()
val nind = env0.nind()
//
val dpid = i1vardcl_dpid$get(idcl)
val tdxp = i1vardcl_dini$get(idcl)
//
val itnm =
(
case+ dpid of
|I1BNDcons(itnm, _, _) => itnm)
//
fun
trcdopt_of_dpid
(dpid: i1bnd): optn(@(bool, strn)) =
(
case+ dpid of
|I1BNDcons(_, ipat, _) =>
  (
  case+ ipat.node() of
  |I0Pvar(dvar) => gotrcd_of_styp(d2var_get_styp(dvar))
  | _(*else*) => optn_nil())
)
//
fun
goty_of_dpid
(dpid: i1bnd): strn =
(
case+ dpid of
|I1BNDcons(_, ipat, _) =>
  (
  case+ ipat.node() of
  |I0Pvar(dvar) => gotype_of_styp(d2var_get_styp(dvar))
  | _(*else*) => "any")
)
//
in//let
//
case+ tdxp of
//
// `var x` WITHOUT initialization -> a zero-valued Go var.  When the variable's
// inferred/static type is a tuple/record, store a POINTER cell (`*struct{...}`)
// just like the initialized aggregate-var path below; the later assignment of
// a flat value will take its address, and assignment of an already boxed value
// stores the pointer directly.  If no aggregate type is recoverable, fall back
// to the declared scalar/static Go type, then `any`.
|TEQI1CMPnone() =>
  (
  case+ trcdopt_of_dpid(dpid) of
  |optn_cons(@(_, body)) =>
    (
    nindfpr(filr, nind);
    strnfpr(filr, "var "); i1tnmgo1(filr, itnm);
    strnfpr(filr, " *"); strnfpr(filr, body); strnfpr(filr, "\n"))
  |optn_nil() =>
    let
      val goty = goty_of_dpid(dpid)
    in
      nindfpr(filr, nind);
      strnfpr(filr, "var "); i1tnmgo1(filr, itnm);
      strnfpr(filr, " "); strnfpr(filr, goty); strnfpr(filr, "\n");
      if (goty = "any")
      then prerrsln("[go1emit] NOTE: var without initializer -> `var goxtnm<x> any`")
      else ((*void*))
    end)
//
// `var x = init` -> emit the init cmp's lets, then
//   `var goxtnm<x> <T> = <init-result>`
//
// MUTATION SEMANTICS (the M2.6c crux): the ATS var-box gives a tuple/record
// REFERENCE semantics -- reading the var (`I1INSflat`) and then mutating a
// field is visible on every subsequent read of the SAME var (the JS oracle's
// `XATSVAR1` box + reference-array model; verified: `p.0:=10` then `p.0` reads
// 10).  A Go VALUE struct would give COPY semantics (a read copies; mutating
// the copy is invisible) -- WRONG vs the oracle.  So a tuple/record var is
// stored as a Go POINTER (`*struct{...}`): reading it (`I1INSflat` -> the
// pointer) ALIASES the var's storage, and `<deref>.F<lab> = v` mutates the
// shared struct -- matching the box.  We therefore:
//   - if the init's recovered type is a flat VALUE struct (`struct{...}`),
//     store a POINTER to it: `var goxtnm<x> *struct{...} = &(<init>)`
//     (the init result is an addressable temp / a composite literal, both
//     addressable with `&` in Go);
//   - if it is already a boxed POINTER (`*struct{...}`), keep it as-is
//     (the init is already a heap pointer -- shared by construction);
//   - a non-aggregate (scalar) var keeps its value type (no `&`): a scalar
//     var's mutation is a whole-var reassignment, not a field path, so value
//     storage is correct (and matches the JS number-by-value box).
|TEQI1CMPsome(_, icmp) =>
  let
    val-I1CMPcons(ilts, ival) = icmp
    val () = i1letlst_go1emit(ilts, icmp, env0)
    //
    // Is the init a tuple/record?  Recover (isFlat, structBody) from the init
    // RESULT temp's recorded type (the SAME side-table lookup the construction
    // used), so the var's pointer type matches the constructed struct exactly.
    val trcdopt =
    (
    case+ ival.node() of
    |I1Vtnm(rtnm) => gotrcd_of_tnm(i1tnm_stmp$get(rtnm))
    | _(*else*) => optn_nil())
  in
    case+ trcdopt of
    //
    // TUPLE/RECORD var -> store a Go POINTER (`*struct{body}`) so reads ALIAS
    // and field mutations are shared (matches the ATS var-box reference
    // semantics / the JS oracle).  A FLAT init is a value struct -> prefix the
    // value with `&` to get an addressable pointer; a BOXED init is ALREADY a
    // `*struct` pointer -> use it directly (no extra `&`).  Either way the var
    // TYPE is `*<body>`.
    |optn_cons(@(isFlat, body)) =>
      (
      nindfpr(filr, nind);
      strnfpr(filr, "var "); i1tnmgo1(filr, itnm);
      strnfpr(filr, " *"); strnfpr(filr, body);
      strnfpr(filr, " = ");
      (if isFlat then strnfpr(filr, "&"));   // &<value-struct> -> *struct
      i1valgo1(filr, ival); strnfpr(filr, "\n"))
    //
    // NON-aggregate (scalar / unrecoverable) var -> keep the value type.  A
    // scalar var's mutation is a whole-var reassignment (`x = v`), not a field
    // path, so value storage is correct (matches the JS number-by-value box).
    |optn_nil() =>
      let
        val goty = gotype_of_init_cmp(icmp)
      in
        nindfpr(filr, nind);
        strnfpr(filr, "var "); i1tnmgo1(filr, itnm);
        strnfpr(filr, " "); strnfpr(filr, goty);
        strnfpr(filr, " = ");
        i1valgo1(filr, ival); strnfpr(filr, "\n")
      end
  end
//
end//let//endof[i1vardcl_go1emit(idcl,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== USER-DEFINED FUNCTIONS  (milestone M2.2)                          ==
=======================================================================
//
A top-level [fun]/[fn] surfaces as
  I1Dfundclst(token, lvl0, t2qaglst, d2cstlst, i1fundclist)
where t2qaglst = $list() means an ordinary FUNCTION (a non-empty
t2qaglst would be a TEMPLATE -- out of M2.2 scope, reported).  Each
i1fundcl carries its d2var (dpid), its fjarglst (args), and its
teqi1cmp body.  The parallel d2cstlst is positional with the fundclist:
d2cs[i] is the d2cst (carrying the static TYPE) of fundcl i, so we pair
them to recover concrete Go arg/result types (gotypes_of_funstyp).
//
We emit, per fundcl:
    func <name>(<p0> <T0>, <p1> <T1>, ...) <Tret> {
        <body lets>
        return <result>
    }
The parameter name <pK> is the bind's own i1tnm (goxtnm<stamp>); the body
references each param through that SAME i1tnm, so the Go param name and
the body uses agree by construction (no arg<N> indirection needed).
*)
//
(*
i1dcl_go1emit_fun: PASS-1 entry.  UNWRAPS the env/template wrapper nodes
(I1Ddclenv carries a decl + its free-var set; I1Dtmpsub/I1Dstatic wrap a
decl) down to the inner I1Dfundclst, then emits the function group.  Any
non-function decl is skipped (no Go output) -- the in-main pass handles it.
//
A top-level [fun] surfaces as I1Ddclenv(I1Dfundclst(...), freevars), so
the unwrap is REQUIRED (a bare I1Dfundclst check would miss every real
top-level function).  The carried [i0varlst] is the i0varfst free-var set
(the shim's output); for a top-level non-closure fn it is empty, which is
why the function needs no captured-env Go params.
*)
#implfun
i1dcl_go1emit_fun
(dcl0, env0) =
(
case+ dcl0.node() of
|I1Dfundclst _ => f0_fundclst(dcl0, env0)
|I1Dimplmnt0 _ => f0_implmnt0(dcl0, env0)
|I1Dlocal0(head, body) =>
  (
  i1dclist_go1emit_funs(head, env0);
  i1dclist_go1emit_funs(body, env0))
|I1Ddclenv(idcl1, _) => i1dcl_go1emit_fun(idcl1, env0)
|I1Dtmpsub(_, idcl1) => i1dcl_go1emit_fun(idcl1, env0)
|I1Dstatic(_, idcl1) => i1dcl_go1emit_fun(idcl1, env0)
| _(*else*) => ((*void*))
) where
{
//
fun
f0_fundclst
(
dcl0: i1dcl,
env0: !envx2go): void =
let
//
val filr = env0.filr()
val loc0 = dcl0.lctn()
//
val-
I1Dfundclst
(_, _, tqas, d2cs, i1fs) = dcl0.node()
//
in//let
//
case+ tqas of
|list_nil() =>
  (
  // an ordinary (non-template) function group.
  i1fundclist_go1emit(i1fs, d2cs, env0))
|list_cons _ =>
  (
  // a TEMPLATE function group (has static template args) -- M3 scope.
  nindfpr(filr, env0.nind());
  strnfpr(filr, "// unsupported template fundclst @ ");
  loctn_fprint(loc0, filr); strnfpr(filr, "\n"))
//
end//let//endof[f0_fundclst(dcl0,env0)]
//
(* ****** ****** *)
//
fun
implfunq
(tknd: token): bool =
(
case+ tknd.node() of
|T_IMPLMNT(IMPLfun()) => true
| _(*else*) => false
)//endof[implfunq(tknd)]
//
fun
dimpl_dcstopt
(dimp: dimpl): optn(d2cst) =
(
case+ dimp.node() of
|DIMPLone1(dcst) => optn_cons(dcst)
|DIMPLone2(dcst, _) => optn_cons(dcst)
|DIMPLnon1(_) => optn_nil()
)//endof[dimpl_dcstopt(dimp)]
//
fun
f0_implmnt0
(
dcl0: i1dcl,
env0: !envx2go): void =
let
//
val filr = env0.filr()
val loc0 = dcl0.lctn()
//
val-
I1Dimplmnt0
(tknd, _, _, dimp, fjas, icmp) = dcl0.node()
//
fun
emit_comment
(msg: strn): void =
(
nindfpr(filr, env0.nind());
strnfpr(filr, "// "); strnfpr(filr, msg);
strnfpr(filr, " @ "); loctn_fprint(loc0, filr); strnfpr(filr, "\n"))
//
fun
emit_implfun
(dcst: d2cst): void =
let
  val (argtys, retty) = gotypes_of_funstyp(d2cst_get_styp(dcst))
  val bnds = binds_of_fjarglst(fjas)
  val () = byref_register_params(fjas, d2cst_get_styp(dcst))
  val () =
  (
  strnfpr(filr, "func ");
  d2cstimplgo1(filr, dcst);
  strnfpr(filr, "(");
  localfun_emit_params(filr, fjas, argtys);
  strnfpr(filr, ") ");
  strnfpr(filr, retty);
  strnfpr(filr, " {\n"))
  // RETURN BOUNDARY: pin this #implfun's emitted return type for its body.
  val saved_cfr = cur_funretty_get()
  val () = cur_funretty_set(retty)
  val () =
  (
  if i1cmp_body_has_tailcall(icmp)
  then
    let
      val params = params_of_fjarglst(fjas)
      val () = envx2go_incnind(env0, 1(*++*))
      val () = (nindfpr(filr, env0.nind()); strnfpr(filr, "for {\n"))
      val () = envx2go_incnind(env0, 1(*++*))
      val () = i1cmp_go1emit_ret(icmp, params, bnds, env0)
      val () = envx2go_decnind(env0, 1(*--*))
      val () = (nindfpr(filr, env0.nind()); strnfpr(filr, "}\n"))
      val () = envx2go_decnind(env0, 1(*--*))
    in
      ((*void*))
    end
  else
    (
    envx2go_incnind(env0, 1(*++*));
    i1cmp_go1emit_ret(icmp, list_nil(), bnds, env0);
    envx2go_decnind(env0, 1(*--*))))
  val () = cur_funretty_set(saved_cfr)
  val () = strnfpr(filr, "}\n\n")
in
  ((*void*))
end//endof[emit_implfun(dcst)]
//
in//let
//
if
dimpl_tempq(dimp)
then
  (
  emit_comment("unsupported template I1Dimplmnt0"))
else
if
implfunq(tknd)
then
  (
  case+ dimpl_dcstopt(dimp) of
  |optn_cons(dcst) => emit_implfun(dcst)
  |optn_nil() =>
    (
    emit_comment("unsupported unresolved I1Dimplmnt0")))
else
  (
  emit_comment("unsupported non-#implfun I1Dimplmnt0"))
//
end//let//endof[f0_implmnt0(dcl0,env0)]
//
}(*where*)//endof[i1dcl_go1emit_fun(dcl0,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
PASS-1.5: module-level GLOBALS.  Emit a NAMED top-level / local-head [val x =
init] as a Go PACKAGE-LEVEL `var goxtnm<x> <T>` plus its initialization in a
per-val `func init()`.  See the SATS.  An [a0ref] side-table global (the
[I1Dlocal0] head) is read/written by the package-level functions in the local
body; this is what DEFINES it (otherwise it is referenced but never emitted).
*)
#implfun
i1dclistopt_go1emit_globals
(dopt, env0) =
(
case+ dopt of
| optn_nil() => ((*void*))
| optn_cons(dcls) => i1dclist_go1emit_globals(dcls, env0))
//
#implfun
i1dclist_go1emit_globals
(dcls, env0) =
(
case+ dcls of
| list_nil() => ((*void*))
| list_cons(dcl1, dcls1) =>
  (i1dcl_go1emit_global(dcl1, env0);
   i1dclist_go1emit_globals(dcls1, env0)))
//
#implfun
i1dcl_go1emit_global
(dcl0, env0) =
(
case+ dcl0.node() of
|I1Dvaldclst(_, i1vs) => g0_valdclst(i1vs, env0)
|I1Dlocal0(head, body) =>
  (i1dclist_go1emit_globals(head, env0);
   i1dclist_go1emit_globals(body, env0))
|I1Ddclenv(idcl1, _) => i1dcl_go1emit_global(idcl1, env0)
|I1Dtmpsub(_, idcl1) => i1dcl_go1emit_global(idcl1, env0)
|I1Dstatic(_, idcl1) => i1dcl_go1emit_global(idcl1, env0)
| _(*else*) => ((*void*))
) where
{
//
fun
g0_valdclst
(i1vs: i1valdclist, env0: !envx2go): void =
(
case+ i1vs of
| list_nil() => ((*void*))
| list_cons(iv1, ivs1) =>
  (g0_valdcl(iv1, env0); g0_valdclst(ivs1, env0)))
//
and
g0_valdcl
(idcl: i1valdcl, env0: !envx2go): void =
let
  val filr = env0.filr()
  val dpat = i1valdcl_dpat$get(idcl)
  val tdxp = i1valdcl_tdxp$get(idcl)
  val (itnm, ipat) =
  (case+ dpat of |I1BNDcons(itnm, ipat, _) => @(itnm, ipat))
  val namedq =
  (case+ ipat.node() of |I0Pvar _ => true | _(*else*) => false)
in//let
case+ tdxp of
|TEQI1CMPsome(_, icmp) =>
  if namedq
  then
    let
      val gty0 = gotyp_emit(i1tnm_gotyp$get(itnm))
      val gty = (if (strn_length(gty0) = 0) then "any" else gty0)
    in
      // package-level declaration `var goxtnm<x> <T>`
      strnfpr(filr, "var "); i1tnmgo1(filr, itnm);
      strnfpr(filr, " "); strnfpr(filr, gty); strnfpr(filr, "\n");
      // its init in a per-val `func init()` (Go runs each before main).
      strnfpr(filr, "func init() {\n");
      envx2go_incnind(env0, 1(*++*));
      i1cmp_go1emit_tnm(itnm, icmp, env0);
      envx2go_decnind(env0, 1(*--*));
      strnfpr(filr, "}\n")
    end
  else ((*void*)) // effect / structural -> emitted by the in-main pass
|TEQI1CMPnone() => ((*void*))
end//let//endof[g0_valdcl(idcl,env0)]
//
}(*where*)//endof[i1dcl_go1emit_global(dcl0,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
PASS-2 (in-main) TOP-LEVEL walk.  Emit the program's top-level EFFECT
computations inside `func main`.  Mirrors [i1dcl_go1emit] BUT: a NAMED top-level
val is SKIPPED (already a package global from PASS-1.5), and an [I1Dlocal0] is
RECURSED (head globalized + body functions hoisted, so only its body EFFECTS
remain).  Nested let-block vals still use the shared [i1dcl_go1emit] (a local
`:=`), unaffected.
*)
#implfun
i1dclistopt_go1emit_main
(dopt, env0) =
(
case+ dopt of
| optn_nil() => ((*void*))
| optn_cons(dcls) => i1dclist_go1emit_main(dcls, env0))
//
#implfun
i1dclist_go1emit_main
(dcls, env0) =
(
case+ dcls of
| list_nil() => ((*void*))
| list_cons(dcl1, dcls1) =>
  (i1dcl_go1emit_main(dcl1, env0);
   i1dclist_go1emit_main(dcls1, env0)))
//
#implfun
i1dcl_go1emit_main
(dcl0, env0) =
(
case+ dcl0.node() of
|I1Dvaldclst(_, i1vs) => m0_valdclst(i1vs, env0)
|I1Dvardclst _ => i1dcl_go1emit(dcl0, env0)
|I1Dlocal0(head, body) =>
  (i1dclist_go1emit_main(head, env0);
   i1dclist_go1emit_main(body, env0))
|I1Ddclenv(idcl1, _) => i1dcl_go1emit_main(idcl1, env0)
|I1Dtmpsub(_, idcl1) => i1dcl_go1emit_main(idcl1, env0)
|I1Dstatic(_, idcl1) => i1dcl_go1emit_main(idcl1, env0)
|I1Dfundclst _ => ((*void*)) // hoisted in PASS-1
|I1Dimplmnt0 _ => ((*void*)) // hoisted in PASS-1
| _(*else*) => ((*void*))
) where
{
//
fun
m0_valdclst
(i1vs: i1valdclist, env0: !envx2go): void =
(
case+ i1vs of
| list_nil() => ((*void*))
| list_cons(iv1, ivs1) =>
  (m0_valdcl(iv1, env0); m0_valdclst(ivs1, env0)))
//
and
m0_valdcl
(idcl: i1valdcl, env0: !envx2go): void =
let
  val dpat = i1valdcl_dpat$get(idcl)
  val ipat =
  (case+ dpat of |I1BNDcons(_, ipat, _) => ipat)
  val namedq =
  (case+ ipat.node() of |I0Pvar _ => true | _(*else*) => false)
in//let
  // a NAMED val is a package GLOBAL (PASS-1.5); skip here.  Effect (`val () =`)
  // and structural vals stay top-level effects in main.
  if namedq then ((*void*)) else i1valdcl_go1emit(idcl, env0)
end//let//endof[m0_valdcl(idcl,env0)]
//
}(*where*)//endof[i1dcl_go1emit_main(dcl0,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
i1fundclist_go1emit: walk a function group, pairing each i1fundcl with its
positional d2cst (for signature typing).  When the lists desync (should
not happen) the missing d2cst becomes optn_nil() -> `any` signature.
*)
#implfun
i1fundclist_go1emit
(i1fs, d2cs, env0) =
(
case+ i1fs of
|list_nil() => ((*void*))
|list_cons(i1f1, i1fs1) =>
  let
    val (dcopt, d2cs1) =
      (
      case+ d2cs of
      |list_nil() => (optn_nil(), list_nil())
      |list_cons(d2c1, d2cs1) => (optn_cons(d2c1), d2cs1))
  in//let
    i1fundcl_go1emit(i1f1, dcopt, env0);
    i1fundclist_go1emit(i1fs1, d2cs1, env0)
  end//let
)//endof[i1fundclist_go1emit(i1fs,d2cs,env0)]
//
(* ****** ****** *)
//
(*
fjarglst_go1emit_params: emit the Go parameter list  <p0> <T0>, <p1> <T1>
between the parens the caller already opened.  Each i1bnd's i1tnm becomes
the Go parameter name (goxtnm<stamp>) -- the SAME name the body uses for
that param.  Types come positionally from [argtys] (the recovered Go
arg-type list); when a param has no recovered type (list shorter), it
falls back to "any".  Go does NOT error on unused params, so a param that
the body never reads is harmless (no `_ =` needed).
*)
fun
fjarglst_go1emit_params
( filr: FILR
, fjas: fjarglst
, argtys: list(strn)): void =
let
//
fnx
loop_fjas
( need_sep: bool
, fjas: fjarglst
, tys: list(strn)): @(bool, list(strn)) =
(
case+ fjas of
|list_nil() => @(need_sep, tys)
|list_cons(fja1, fjas1) =>
  let
    val-FJARGdarg(i1bs) = fja1.node()
    val (need_sep1, tys1) = loop_bnds(need_sep, i1bs, tys)
  in
    loop_fjas(need_sep1, fjas1, tys1)
  end
)
//
and
loop_bnds
( need_sep: bool
, i1bs: i1bndlst
, tys: list(strn)): @(bool, list(strn)) =
(
case+ i1bs of
|list_nil() => @(need_sep, tys)
|list_cons(ibnd, i1bs1) =>
  let
    val-I1BNDcons(itnm, _, _) = ibnd
    // pop the next recovered Go type ("any" if the list is exhausted).
    val (goty, tys1) =
      (
      case+ tys of
      |list_nil() => @("any", list_nil())
      |list_cons(t1, tys1) => @(t1, tys1))
    val () =
      (
      if need_sep then strnfpr(filr, ", ");
      i1tnmgo1(filr, itnm);
      strnfpr(filr, " ");
      strnfpr(filr, goty))
    // EMITTED-TYPE: record each param's emitted Go type, so a param emitted `any`
    // (a generic-erased arg) is asserted at a later CONCRETE boundary (assign /
    // return / arg).  Recording CONCRETE param types is also correct -- it only
    // PREVENTS a spurious assertion on a concretely-typed param.
    val () = goemit_ty_add(i1tnm_stmp$get(itnm), goty)
  in
    loop_bnds(true, i1bs1, tys1)
  end
)
//
val _ = loop_fjas(false, fjas, argtys)
//
in//let
((*void*)) end
//endof[fjarglst_go1emit_params(...)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
i1fundcl_go1emit: emit one function as a package-level Go func.  The
signature types come from [dcopt]'s static type (gotypes_of_funstyp);
unrecoverable types fall back to "any" (documented).
*)
#implfun
i1fundcl_go1emit
(ifun, dcopt, env0) =
let
//
val filr = env0.filr()
//
val dvar = i1fundcl_dpid$get(ifun)
val fjas = i1fundcl_farg$get(ifun)
val tdxp = i1fundcl_tdxp$get(ifun)
//
// recover the Go arg-type list + result type from the function's static
// type (Regime B).  Empty / unrecognized -> ($list(), "any").
val (argtys, retty) =
  (
  case+ dcopt of
  |optn_nil() => @(list_nil(), "any")
  |optn_cons(dcst) => gotypes_of_funstyp(d2cst_get_styp(dcst)))
//
// RESULT BOUNDARY (self-emission): record this function's EMITTED return type
// keyed by its d2var stamp, so a CALL `goxtnm := f(args)` whose result is used at
// a CONCRETE context can assert `f(args).(T)` when [f]'s recorded retty is "any".
val () = funretty_add(d2var_get_stmp(dvar), retty)
//
// GAP A1: register this function's by-REFERENCE params (`&T` -> Go `*T`) in
// the byref stamp set BEFORE emitting the body, so the body's read/write/
// call emitters deref (`*p`) / pass (`p`) each pointer param.  Uses the SAME
// styp the arg types came from (d2cst_get_styp), so a `*T` param type and its
// byref registration agree.
val () =
  (
  case+ dcopt of
  |optn_nil() => ((*void*))
  |optn_cons(dcst) => byref_register_params(fjas, d2cst_get_styp(dcst)))
//
// --- signature: func <name>(<params>) <ret> { -------------------------
val () =
(
strnfpr(filr, "func ");
d2vargo1(filr, dvar);
strnfpr(filr, "(");
fjarglst_go1emit_params(filr, fjas, argtys);
strnfpr(filr, ") ");
strnfpr(filr, retty);
strnfpr(filr, " {\n"))
//
// --- body: lets then `return <result>` (function-body mode) -----------
//
// M2.4 TCO: if the body contains a reachable TAIL self-call
// (i1cmp_body_has_tailcall), wrap it in a Go `for { ... }` loop and thread
// the function's PARAMETER temps (params_of_fjarglst) down the
// return-position chain.  A tail self-call then emits as `goxtnm<p_i> =
// <newarg_i>; continue` (O(1) stack) instead of a recursive call.  A
// non-tail-recursive (or non-recursive) body keeps the plain return path
// (params = list_nil(), no `for` wrapper) -- a plain Go recursive call for
// any non-tail self-call, exactly as M2.3.
//
// RETURN BOUNDARY: pin this function's emitted return type while its body is
// emitted, so a `return <r>` of an emitted-`any` value asserts to [retty].
val saved_cfr = cur_funretty_get()
val () = cur_funretty_set(retty)
val () =
(
case+ tdxp of
|TEQI1CMPnone() =>
  (
  // an abstract / declared-only function (no body) -- emit a stub that
  // panics so the Go still compiles; reported.  (Not expected for the
  // M2.2 surface; included for totality.)
  envx2go_incnind(env0, 1(*++*));
  nindfpr(filr, env0.nind());
  strnfpr(filr, "panic(\"xats2go: function with no body\")\n");
  envx2go_decnind(env0, 1(*--*)))
|TEQI1CMPsome(_, icmp) =>
  let
    val hastc = i1cmp_body_has_tailcall(icmp)
  in
  if hastc then
    let
      // TAIL-RECURSIVE: emit `for {` <body w/ params> `}`.  Go sees a `for {}`
      // whose every reachable path either `continue`s or `return`s as a
      // terminating statement, so no trailing `return` is needed after it.
      val params = params_of_fjarglst(fjas)
      // M2.5: seed the in-scope bind environment with THIS function's own param
      // binds, so a lambda emitted in the body can recover the Go type of a
      // body that returns a captured param (`f(a) = lam u => a`).
      val bnds = binds_of_fjarglst(fjas)
      val () = envx2go_incnind(env0, 1(*++*))
      val () = (nindfpr(filr, env0.nind()); strnfpr(filr, "for {\n"))
      val () = envx2go_incnind(env0, 1(*++*))
      val () = i1cmp_go1emit_ret(icmp, params, bnds, env0)
      val () = envx2go_decnind(env0, 1(*--*))
      val () = (nindfpr(filr, env0.nind()); strnfpr(filr, "}\n"))
      val () = envx2go_decnind(env0, 1(*--*))
    in
      ((*void*))
    end
  else
    (
    // not tail-recursive: plain return mode, no params (no `for` loop).  A
    // non-tail self-call stays a real Go recursive call (test14 factorial).
    // M2.5: bnds = the function's own param binds (so a body-level lambda
    // returning a captured param types concretely).
    envx2go_incnind(env0, 1(*++*));
    i1cmp_go1emit_ret(icmp, list_nil(), binds_of_fjarglst(fjas), env0);
    envx2go_decnind(env0, 1(*--*)))
  end
)
val () = cur_funretty_set(saved_cfr)
//
val () = strnfpr(filr, "}\n\n")
//
in//let
((*void*)) end
//endof[i1fundcl_go1emit(ifun,dcopt,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_go1emit_decl00.dats] *)
(***********************************************************************)
