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
#staload // LOC =
"./../../../SATS/locinfo.sats"
#staload // D2E =
"./../../../SATS/dynexp2.sats"
//
(* ****** ****** *)
//
#staload ".\
/../../../xats2cc\
/srcgen1/SATS/intrep0.sats"//...
//
#staload "./../SATS/intrep1.sats"
#staload "./../SATS/xats2go.sats"
#staload "./../SATS/go1emit.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#symload filr with envx2go_filr$get
#symload nind with envx2go_nind$get
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
fprintln
(filr: FILR): void =
(
strn_fprint("\n", filr))//endfun
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
// I1Dfundclst is emitted at PACKAGE level in PASS 1 (i1dcl_go1emit_fun);
// the in-main pass skips it (no Go output) so it is not duplicated.
|I1Dfundclst _ => ((*void*))
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
loctn_fprint(loc0, filr); strnfpr(filr, ")"); fprintln(filr))
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
loctn_fprint(loc0, filr); strnfpr(filr, ")"); fprintln(filr)) end
//endof[f0_otherwise(dcl0,env0)]
//
}(*where*)//endof[i1dcl_go1emit(dcl0,env0)]
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
  - OTHER non-unit patterns (tuples/records/datacons): reported UNHANDLED
    (M2.6/M2.7 decompose them into projections).
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
in//let
//
case+ tdxp of
//
|TEQI1CMPnone
( (*void*) ) => ((*void*))
//
|TEQI1CMPsome
(teq1, icmp) =>
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
    i1valgo1(filr, ival); fprintln(filr);
    nindfpr(filr, nind);
    strnfpr(filr, "_ = "); i1tnmgo1(filr, itnm); fprintln(filr)
  end
//
// `val _ = CMP`: a wildcard binding -- emit as a discarded effect.
|I0Pany _ =>
  (
  i1cmp_go1emit(icmp, env0))
//
// tuples / records / datacons -> M2.6/M2.7.
| _(*else*) =>
  (
  nindfpr(filr, nind);
  strnfpr
  (filr, "// UNHANDLED: non-unit val pattern\n");
  prerrsln
  ("[go1emit] UNHANDLED: non-unit val pattern (tuple/record/datacon -> M2.6/M2.7)"))
))
//
end//let//endof[i1valdcl_go1emit(idcl,env0)]
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
  strnfpr(filr, "// UNHANDLED: template fundclst @ ");
  loctn_fprint(loc0, filr); fprintln(filr);
  prerrsln
    ("[go1emit] UNHANDLED: template I1Dfundclst (M3)"))
//
end//let//endof[f0_fundclst(dcl0,env0)]
//
}(*where*)//endof[i1dcl_go1emit_fun(dcl0,env0)]
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
( i0: sint
, fjas: fjarglst
, tys: list(strn)): @(sint, list(strn)) =
(
case+ fjas of
|list_nil() => @(i0, tys)
|list_cons(fja1, fjas1) =>
  let
    val-FJARGdarg(i1bs) = fja1.node()
    val (i1, tys1) = loop_bnds(i0, i1bs, tys)
  in
    loop_fjas(i1, fjas1, tys1)
  end
)
//
and
loop_bnds
( i0: sint
, i1bs: i1bndlst
, tys: list(strn)): @(sint, list(strn)) =
(
case+ i1bs of
|list_nil() => @(i0, tys)
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
      if (i0 >= 1) then strnfpr(filr, ", ");
      i1tnmgo1(filr, itnm);
      strnfpr(filr, " ");
      strnfpr(filr, goty))
  in
    loop_bnds(i0+1, i1bs1, tys1)
  end
)
//
val _ = loop_fjas(0, fjas, argtys)
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
  envx2go_decnind(env0, 1(*--*));
  prerrsln("[go1emit] NOTE: I1Dfundcl with no body (TEQI1CMPnone)"))
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
