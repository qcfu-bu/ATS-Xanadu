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
go1emit_dynexp — the dynamic-expression IR walk for the Go backend (M1).
Mirrors xats2js/srcgen2/DATS/js1emit_dynexp.dats's i1val/i1ins/i1cmp/i1let
dispatch, but emits Go. Only the constructors the M1 walking skeleton
(test01) needs are handled with real code; every other constructor emits
"// UNHANDLED: <ctor>" to the output AND a [prerrln] to stderr (PLAN.md
step 4: never silently emit wrong/uncompilable Go).
//
The chosen program lowers (verified via the IR dump) to, per [val]:
  I1CMPcons(
    [ I1LETnew1(tnmF, I1INStimp(_, timp))        // resolve prelude fn
    , I1LETnew1(tnmR, I1INSdapp(I1Vtnm(tnmF), [I1Vstr(...)])) ]  // call it
  , I1Vtnm(tnmR))                                 // result (unit)
We emit, for each let:
  goxtnmF := <timp-as-runtime-fn>
  goxtnmR := goxtnmF(<args>)
and the I1CMPcons result ival as a final  goxtnmX := <ival>; _ = goxtnmX.
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
#staload // LEX =
"./../../../SATS/lexing0.sats"
#staload // LAB =
"./../../../SATS/xlabel0.sats"
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
#symload node with token_get_node
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
//
(*
unhandled: emit a visible, COMPILE-SAFE marker to the output (a Go line
comment) and a loud stderr note. Used for any IR node outside test01's
M1 surface so we never silently emit wrong Go (PLAN.md step 4).
*)
fun
unhandled_ins
(filr: FILR, tag: strn, iins: i1ins): void =
let
val () =
(
strnfpr(filr, "/* UNHANDLED: ");
strnfpr(filr, tag); strnfpr(filr, " */ nil"))
val () =
(
prerrsln("[go1emit] UNHANDLED i1ins: ", tag))
in//let
((*void*)) end
//
fun
unhandled_val
(filr: FILR, tag: strn, ival: i1val): void =
let
val () =
(
strnfpr(filr, "/* UNHANDLED: ");
strnfpr(filr, tag); strnfpr(filr, " */ nil"))
val () =
(
prerrsln("[go1emit] UNHANDLED i1val: ", tag))
in//let
((*void*)) end
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
i1valgo1_list: emit a comma-separated argument list (the i1valist of an
I1INSdapp). Mirrors i1valjs1_list.
*)
fun
i1valgo1_list
( filr: FILR
, i1vs: i1valist): void =
(
list_iforitm(i1vs)) where
{
#typedef x0 = i1val
#typedef xs = i1valist
#impltmp
iforitm$work<x0>(i0, x0) =
(
if
(i0 >= 1)
then strnfpr(filr, ", ");
i1valgo1(filr, x0))
}(*where*)//endof[i1valgo1_list(...)]
//
(* ****** ****** *)
//
(*
M2.2 staged an [i1valgo1_lst2] (args first, then the captured-env values
appended, mirroring the JS backend's [lst2] order) for a future closure
call site.  M2.5 REMOVED it: Go func literals capture lexically, so a
closure is called with its plain args ONLY -- there is no env-passing
calling convention to append values for (the [I1INSdapp]/[I1Vfenv] paths
now ignore [envs] and use [i1valgo1_list]).  See the I1INSdapp doc above.
*)
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== M2.6b LAYOUT-AWARE TUPLES / RECORDS: construction (READ path)     ==
=======================================================================
//
A flat tuple/record is a Go VALUE struct literal `struct{...}{v0, v1}`; a
boxed one is a HEAP POINTER `&struct{...}{v0, v1}`.  The struct TYPE is
recovered from the construction's RESULT temp via the M2.6a side-table
([gotrcd_of_tnm]: the temp's recorded [I0Ttrcd] -> (isFlat, structBody)) --
the SAME translation a projection root gets from [gotype_of_i0typ], so the
constructed value's Go type matches every `v.F<lab>` use exactly.
//
CRUCIAL: flat-vs-boxed is decided by the [trcdknd] in the recorded type
(NOT by the [I1INStup0] vs [I1INStup1] constructor split -- the front-end
lowers even a FLAT `@(..)` to [I1INStup1] with a flat-kind token, verified
via the IR dump).  So [isFlat] from [gotrcd_of_tnm] is the authority.
//
[i1trcd_construct_go1emit]: emit a tuple/record construction bound to result
temp [otnm].  Drives the struct type from [otnm]'s side-table entry; emits
the values via [i1valgo1] (tuple = positional [i1valist]; record = the
[l1i1vlst] field values in declaration order, which the front-end already
ordered to match the struct fields).  Falls back to [i1valgo1] of the raw
ctor only if the type is somehow unrecoverable (documented; the oracle would
catch a wrong layout).
*)
fun
i1trcd_emit_litvals
( filr: FILR
, i1vs: i1valist): void =
(
list_iforitm(i1vs)) where
{
#typedef x0 = i1val
#typedef xs = i1valist
#impltmp
iforitm$work<x0>(i0, x0) =
(
if (i0 >= 1) then strnfpr(filr, ", ");
i1valgo1(filr, x0))
}(*where*)//endof[i1trcd_emit_litvals(filr,i1vs)]
//
fun
i1trcd_emit_rcdvals
( filr: FILR
, livs: l1i1vlst): void =
(
list_iforitm(livs)) where
{
#typedef x0 = l1i1v
#typedef xs = l1i1vlst
#impltmp
iforitm$work<x0>(i0, lv0) =
let
  val-I1LAB(_, iv1) = lv0
in
  (if (i0 >= 1) then strnfpr(filr, ", "); i1valgo1(filr, iv1))
end
}(*where*)//endof[i1trcd_emit_rcdvals(filr,livs)]
//
(*
i1ins_is_construct: is this ins a tuple/record CONSTRUCTION?  (See the SATS
doc -- such an ins routes through [i1trcd_construct_go1emit] with its result
temp, not the generic [i1insgo1].)
*)
#implfun
i1ins_is_construct
(iins) =
(
case+ iins of
|I1INStup0(_) => true
|I1INStup1(_, _) => true
|I1INSrcd2(_, _) => true
| _(*else*) => false
)//endof[i1ins_is_construct(iins)]
//
(* ****** ****** *)
//
(*
FALLBACK struct-type construction (side-table MISS).
//
When the result temp's recorded [i0typ] is NOT a tuple/record (the temp had
no source [i0exp], or the type is otherwise unrecoverable), we STILL must emit
a correctly-SHAPED struct literal -- flat (VALUE) vs boxed (POINTER) per the
token's [trcdknd], with the right field COUNT/NAMES -- so the construction is
not a `nil` guess.  We recover the per-field Go TYPE from each field VALUE
([gotype_of_ival]: a literal carries its type; a temp falls back to `any`).
The flat/boxed flag comes from the token int payload ([T_TRCD10]/[T_TRCD20]:
0 = flat `@(/@{`, nonzero = boxed `#(/#{`), verified in the IR dump.
//
[gotok_is_flat]: the token int payload -> isFlat (0 == flat).
*)
fun
gotok_is_flat
(tok: token): bool =
(
case+ tok.node() of
|T_TRCD10(i0) => (i0 = 0)
|T_TRCD20(i0) => (i0 = 0)
| _(*else: be conservative -> flat (value)*) => true
)//endof[gotok_is_flat(tok)]
//
(*
[gostruct_body_of_tupvals]: build `struct{F0 T0; F1 T1; ...}` for a positional
TUPLE from its value list -- field names are positional (F0,F1,...), field
types from each value via [gotype_of_ival] (any-fallback).  Used ONLY on the
side-table miss path; the hit path uses the recorded [i0typ]'s precise types.
*)
fun
gostruct_body_of_tupvals
(i1vs: i1valist): strn =
let
  fun
  fields
  (i0: sint, vs: i1valist): strn =
  (
  case+ vs of
  |list_nil() => ""
  |list_cons(v1, vs1) =>
    let
      val fnm = gofield_of_label(LABint(i0))
      val fty = gotype_of_ival(v1)
      val one = strn_append(strn_append(fnm, " "), fty)
      val sep = (if (i0 >= 1) then "; " else "")
    in
      strn_append(strn_append(sep, one), fields(i0+1, vs1))
    end
  )
in
  strn_append(strn_append("struct{", fields(0, i1vs)), "}")
end//endof[gostruct_body_of_tupvals(i1vs)]
//
(*
[gostruct_body_of_rcdvals]: build `struct{Fx Tx; Fy Ty; ...}` for a RECORD
from its labelled value list -- field names from each [I1LAB] label via
[gofield_of_label], field types from each value via [gotype_of_ival].
*)
fun
gostruct_body_of_rcdvals
(livs: l1i1vlst): strn =
let
  fun
  fields
  (i0: sint, vs: l1i1vlst): strn =
  (
  case+ vs of
  |list_nil() => ""
  |list_cons(lv1, vs1) =>
    let
      val-I1LAB(lab1, v1) = lv1
      val fnm = gofield_of_label(lab1)
      val fty = gotype_of_ival(v1)
      val one = strn_append(strn_append(fnm, " "), fty)
      val sep = (if (i0 >= 1) then "; " else "")
    in
      strn_append(strn_append(sep, one), fields(i0+1, vs1))
    end
  )
in
  strn_append(strn_append("struct{", fields(0, livs)), "}")
end//endof[gostruct_body_of_rcdvals(livs)]
//
(*
[i1trcd_emit_fallback]: emit the construction from the TOKEN (flat/boxed) +
value-derived field types, when the side-table had no tuple/record type.  The
struct SHAPE (flat value vs boxed pointer, field count/names) is always correct
per the [trcdknd]; only an unrecoverable field TYPE degrades to `any` (the
documented fallback, not a layout error).
*)
fun
i1trcd_emit_fallback
( filr: FILR
, iins: i1ins): void =
let
  val () = prerrsln("[go1emit] NOTE: tuple/record construct typed from token+values (side-table miss; any-field fallback possible)")
in
  case+ iins of
  |I1INStup0(i1vs) =>
    (
    // a bare flat tuple (no token) -> VALUE struct.
    strnfpr(filr, gostruct_body_of_tupvals(i1vs));
    strnfpr(filr, "{"); i1trcd_emit_litvals(filr, i1vs); strnfpr(filr, "}"))
  |I1INStup1(tok, i1vs) =>
    let
      val isFlat = gotok_is_flat(tok)
      val () = (if isFlat then () else strnfpr(filr, "&"))
    in
      strnfpr(filr, gostruct_body_of_tupvals(i1vs));
      strnfpr(filr, "{"); i1trcd_emit_litvals(filr, i1vs); strnfpr(filr, "}")
    end
  |I1INSrcd2(tok, livs) =>
    let
      val isFlat = gotok_is_flat(tok)
      val () = (if isFlat then () else strnfpr(filr, "&"))
    in
      strnfpr(filr, gostruct_body_of_rcdvals(livs));
      strnfpr(filr, "{"); i1trcd_emit_rcdvals(filr, livs); strnfpr(filr, "}")
    end
  | _(*unreachable: only construction ins reach here*) =>
    (
    strnfpr(filr, "/* UNHANDLED: trcd-construct (non-construction ins) */ nil");
    prerrsln("[go1emit] UNHANDLED tuple/record construct (non-construction ins)"))
end//endof[i1trcd_emit_fallback(filr,iins)]
//
(*
[i1trcd_construct_go1emit]: emit a tuple/record construction `[&]<body>{...}`
bound to result temp [otnm] -- a flat value struct literal `struct{...}{...}`
or a boxed heap pointer `&struct{...}{...}`, per [isFlat] (the layout payoff
made visible: same field values, value-vs-pointer per the [trcdknd]).
*)
#implfun
i1trcd_construct_go1emit
( filr, otnm, iins ) =
let
  val ostmp = i1tnm_stmp$get(otnm)
in//let
  case+ gotrcd_of_tnm(ostmp) of
  //
  // GOT the struct type from the side-table -> emit the typed value/pointer
  // struct literal (the Regime-B layout payoff: NOT a []any).  `&` prefix iff
  // boxed; then `<body>{ <values> }`.  This is the PRIMARY path -- the struct
  // type is byte-identical to what every projection root computes from the
  // SAME recorded [i0typ], so Go's structural typing accepts both sites.
  |optn_cons(@(isFlat, body)) =>
    let
      val () = (if isFlat then () else strnfpr(filr, "&"))
      val () = strnfpr(filr, body)
      val () = strnfpr(filr, "{")
      val () =
      (
      case+ iins of
      |I1INStup0(i1vs)    => i1trcd_emit_litvals(filr, i1vs)
      |I1INStup1(_, i1vs) => i1trcd_emit_litvals(filr, i1vs)
      |I1INSrcd2(_, livs) => i1trcd_emit_rcdvals(filr, livs)
      | _(*unreachable: only construction ins reach here*) => ())
      val () = strnfpr(filr, "}")
    in
      ((*void*))
    end
  //
  // side-table miss (the result temp was not recorded, or its type is not a
  // tuple/record) -> FALL BACK to a token + value-typed struct (shape always
  // correct per [trcdknd]; an unrecoverable field type degrades to `any`).
  // Not expected on the READ-path surface (every tuple/record construction's
  // result temp IS recorded at its mint site), but robust if it ever happens.
  |optn_nil() =>
    i1trcd_emit_fallback(filr, iins)
end//let//endof[i1trcd_construct_go1emit(filr,otnm,iins)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1valgo1
(filr, ival) =
(
case+
ival.node() of
//
(* ****** ****** *)
//
|I1Vnil
( (*0*) ) => strnfpr(filr, "xatsgo.XATSNIL()")
//
(* ****** ****** *)
//
(* scalar literals -> concrete Go literals (M2.1) *)
//
|I1Vint
( tint ) => i0intgo1(filr, tint)
|I1Vi00
( int0 ) => i0i00go1(filr, int0)
//
|I1Vbtf
( btf0 ) => i0btfgo1(filr, btf0)
|I1Vb00
( btf0 ) => i0b00go1(filr, btf0)
//
|I1Vchr
( tchr ) => i0chrgo1(filr, tchr)
|I1Vc00
( chr0 ) => i0c00go1(filr, chr0)
//
|I1Vflt
( tflt ) => i0fltgo1(filr, tflt)
|I1Vf00
( flt0 ) => i0f00go1(filr, flt0)
//
(* ****** ****** *)
//
|I1Vstr
( tstr ) => i0strgo1(filr, tstr)
|I1Vs00
( str0 ) => i0s00go1(filr, str0)
//
(* ****** ****** *)
//
|I1Vtnm
( itnm ) => i1tnmgo1(filr, itnm)
//
(* ****** ****** *)
//
|I1Vcst
( dcst ) => d2cstgo1(filr, dcst)
|I1Vfid
( dvar ) => d2vargo1(filr, dvar)
//
(* ****** ****** *)
//
(*
I1Vfenv(d2var, envs): a function VALUE (its d2var + captured-env values).
Used standalone (e.g. as a fn argument, or a local recursive closure's
self-call callee), and special-cased in I1INSdapp as a direct callee.
//
M2.5: we emit the function's Go IDENTIFIER ([d2vargo1]) and IGNORE [envs].
For a top-level/hoisted `fun` that name is the package-level Go func; for a
local recursive closure (I1INSfix0) it is the FIX-VAR's name, which the
fix0 emitter pre-declares as `var <name> <functype>` (the self-reference
target).  The captured env is NOT threaded -- Go's func literals capture
the surrounding locals lexically (our [envi0i1_i0ws$insert] divergence
already rewrote each captured var to its outer Go local), so the [envs]
list carries no information the emitted Go needs.
*)
|I1Vfenv
( d2f0, _envs ) => d2vargo1(filr, d2f0)
//
(* ****** ****** *)
(* ****** ****** *)
//
| _(*otherwise*) =>
unhandled_val(filr, "i1val", ival)
//
)(*case+*)//endof[i1valgo1(filr,ival)]
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
i1insgo1
(filr, scp, iins) =
(
case+ iins of
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
I1INStimp: the pipeline RESOLVED a template instance to a prelude
constant (its d2cst). We emit a reference to the matching xatsgo runtime
function value (d2cstgo1). This is the real, pipeline-resolved call --
the dcst comes straight out of [trxi0i1], not from an FFI shortcut.
For a native-able scalar op (sint_add$sint, ...) this reference is only
EVER reached when the op-temp was kept live for a non-inlined (value /
higher-order) use; the inlined-call case routes through I1INSdapp below
and never touches the d2cst, so the op-temp drops to `_ = <this>`.
*)
|I1INStimp
(i0f1, timp) =>
let
val dcst = t1imp_dcst$get(timp)
in//let
(
  d2cstgo1(filr, dcst)) end
//
(* ****** ****** *)
//
(*
I1INSdapp: apply fun0 to its args.
//
M2.1 PRIMOP RULE: if the callee resolves (in scope [scp]) to a native Go
binary operator and there are exactly two args, emit NATIVE INFIX
`(a OP b)` -- the Regime-B payoff (concrete scalar arithmetic/compare,
no boxed runtime call).  Otherwise emit a plain Go call `<f>(<args>)`
(the runtime-fallback path; also covers prelude prints, user calls).
*)
|I1INSdapp
(i1f0, i1vs) =>
let
val gop = i1binop_of_dapp(i1f0, i1vs, scp)
in//let
if
(strn_length(gop) > 0)
then
(
let
  val-list_cons(a0, ar1) = i1vs
  val-list_cons(a1, _) = ar1
in
  strnfpr(filr, "(");
  i1valgo1(filr, a0);
  strnfpr(filr, " "); strnfpr(filr, gop); strnfpr(filr, " ");
  i1valgo1(filr, a1);
  strnfpr(filr, ")")
end)
else
(
(*
M2.2 CALL: a user function call.  A top-level [fun]/[fn] call lowers to
I1INSdapp(I1Vfenv(d2var, envs), args) -- I1Vfenv is the function VALUE
(its d2var + a CAPTURED-ENV value list; for a top-level non-closure fn
[envs] is empty).  We emit  <fname>(<args>)  -- ONLY the regular args.
//
M2.5: the captured-env values [envs] are IGNORED (NOT appended, unlike the
JS backend's lst2).  Go func literals capture their surrounding locals
LEXICALLY, so a closure is called with its plain args only -- there is no
env-passing calling convention.  (Our [envi0i1_i0ws$insert] divergence
already rewrote every captured var to its outer Go local, so the closure
body reads its captures directly.)  The function NAME is [d2vargo1] on the
SAME d2var that the decl / fix-var `var` uses, so call site and decl agree
by construction.  Any other callee (a plain temp holding a fn value -- e.g.
a func-typed parameter, or a temp-bound lambda -- an I1Vcst/I1Vfid) falls
through to the generic `<f>(<args>)` form.
*)
case+ i1f0.node() of
|I1Vfenv(d2f0, _envs) =>
  (
  d2vargo1(filr, d2f0);
  strnfpr(filr, "(");
  i1valgo1_list(filr, i1vs);
  strnfpr(filr, ")"))
| _(*otherwise*) =>
  (
  i1valgo1(filr, i1f0);
  strnfpr(filr, "(");
  i1valgo1_list(filr, i1vs);
  strnfpr(filr, ")")))
end//let
//
(* ****** ****** *)
//
(*
M2.6b PROJECTION: read one field of a tuple/record.
  I1INSpflt(lab, v) : FLAT  tuple/record field -> `v.F<lab>` (value field).
  I1INSproj(lab, v) : BOXED tuple/record field -> `v.F<lab>` (Go auto-derefs
                      the *struct pointer, so the SAME `.F<lab>` syntax works).
The field name [gofield_of_label] is the SAME scheme the struct TYPE used at
construction, so `.F<lab>` resolves.  (Both flat and boxed render identically
here -- Go's pointer auto-deref unifies them -- which is exactly why a single
projection form is correct for both layouts.)
*)
|I1INSpflt(lab0, i1v1) =>
  (
  i1valgo1(filr, i1v1);
  strnfpr(filr, "."); strnfpr(filr, gofield_of_label(lab0)))
|I1INSproj(lab0, i1v1) =>
  (
  i1valgo1(filr, i1v1);
  strnfpr(filr, "."); strnfpr(filr, gofield_of_label(lab0)))
//
(* ****** ****** *)
//
(*
M2.6b CONSTRUCTION reaching [i1insgo1] without a result temp (an [I1LETnew0]
throwaway, or a construction nested as a sub-expression).  A tuple/record
construction needs its result temp's recorded type for the struct literal,
which is unavailable here -- the [I1LETnew1] path routes it to
[i1trcd_construct_go1emit] (which HAS the temp).  Reaching here means a
construction surfaced in a context M2.6b does not yet type; mark UNHANDLED
(never an untyped guess).  On the READ-path surface every construction is
[val p = @(..)] -> [I1LETnew1], so this is not hit.
*)
|I1INStup0(_) => unhandled_ins(filr, "I1INStup0(no-result-temp)", iins)
|I1INStup1(_, _) => unhandled_ins(filr, "I1INStup1(no-result-temp)", iins)
|I1INSrcd2(_, _) => unhandled_ins(filr, "I1INSrcd2(no-result-temp)", iins)
//
(* ****** ****** *)
//
(*
I1INSrturn(i0cal, innerCmp): a function-body RETURN.  The body of a
non-recursive [fun] surfaces as I1LETnew0(I1INSrturn(i0cal, innerCmp)).
This instruction appears ONLY in function-body (return) mode, where
[i1cmp_go1emit_ret] unwraps it directly (see go1emit_decl00) -- so when
we reach it here as a generic ins it means an rturn appeared in a non-
return context (e.g. a nested let-body), which M2.2 does not yet emit.
We mark it UNHANDLED rather than silently dropping the result.  (M2.4
recursion/TCO generalizes rturn handling.)
*)
|I1INSrturn(_, _) =>
  unhandled_ins(filr, "I1INSrturn(non-return-ctx)", iins)
//
(* ****** ****** *)
//
(*
I1INSlam0 / I1INSfix0: lambdas + local recursive closures.  As of M2.5
these are BLOCK-FORM (i1ins_is_blockform returns true), so a let binding
one routes through [i1ins_go1emit_block] (inline Go func literal with
lexical capture; fix0 uses the `var f F; f = func(){... f() ...}` self-ref
idiom).  Reaching them HERE means a lam0/fix0 surfaced in a context that
emits via the single-expression [i1insgo1] (not expected) -- mark UNHANDLED
rather than emit a half-formed func literal inline.
*)
|I1INSlam0(_, _, _) =>
  unhandled_ins(filr, "I1INSlam0(non-block-ctx)", iins)
|I1INSfix0(_, _, _, _) =>
  unhandled_ins(filr, "I1INSfix0(non-block-ctx)", iins)
//
(* ****** ****** *)
(* ****** ****** *)
//
| _(*otherwise*) =>
unhandled_ins(filr, "i1ins", iins)
//
)(*case+*)//endof[i1insgo1(filr,scp,iins)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== M2.3 CONTROL FLOW: if / let-in / case (SIMPLE patterns)           ==
=======================================================================
//
A VALUE-position if/case/let surfaces as I1LETnew1(tnm, ift0/cas0/let0)
whose result temp is read downstream; a RETURN-position one has every
branch body ending in an I1INSrturn (i1ins_fully_returnsq).  These emit as
MULTI-STATEMENT Go blocks, so they are handled in [i1let_go1emit] (not in
[i1insgo1], which only emits single expressions).
//
Two branch-emission modes (mirroring js1emit's f0_i1cmpret/f0_i1tnmcmp):
  - RETURN mode  -> i1cmp_go1emit_ret  (each branch emits its own `return`)
  - ASSIGN mode  -> i1cmp_go1emit_tnm  (each branch does goxtnm<tnm> = <r>)
All emitters below are top-level functions, so the (genuine) mutual
recursion across cmp/let/block/clause resolves through their SATS
declarations -- exactly as the original four cmp/let emitters did.
*)
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
i0pckgo1: emit a pattern as a Go BOOLEAN TEST against [casval].  Mirrors
js1emit's i0pckjs1 but for SIMPLE patterns only (M2.3 scope):
  - I0Pany / I0Pvar          -> "true"  (always matches; bind happens later)
  - I0Pint / I0Pchr / I0Pbtf -> `<casval> == <literal>` (native scalar ==)
  - I0Pbang/flat/free(p)     -> recurse into p (transparent wrappers)
DATACON patterns (I0Pcon / I0Pdapp / tuple / record) are DEFERRED to M2.7;
they emit a `false` test + a stderr NOTE so the clause is skipped rather
than silently mis-matched (the case still falls through to its default).
Because [casval] is a concretely-typed scalar (the case scrutinee), the
== is a native Go comparison -- the same semantics XATS000_inteq/chreq/
btfeq give in the JS backend (the oracle verifies byte-equality).
*)
fun
i0pckgo1
( filr: FILR
, casval: i1val
, ipat: i0pat): void =
(
case+ ipat.node() of
//
|I0Pany _ => strnfpr(filr, "true")
|I0Pvar _ => strnfpr(filr, "true")
//
|I0Pint(tint) =>
  (
  i1valgo1(filr, casval); strnfpr(filr, " == ");
  i0intgo1(filr, tint))
|I0Pchr(tchr) =>
  (
  i1valgo1(filr, casval); strnfpr(filr, " == ");
  i0chrgo1(filr, tchr))
|I0Pbtf(btf0) =>
  (
  i1valgo1(filr, casval); strnfpr(filr, " == ");
  i0btfgo1(filr, btf0))
|I0Pflt(tflt) =>
  (
  i1valgo1(filr, casval); strnfpr(filr, " == ");
  i0fltgo1(filr, tflt))
//
// transparent wrappers: test the inner pattern.
|I0Pbang(ip1) => i0pckgo1(filr, casval, ip1)
|I0Pflat(ip1) => i0pckgo1(filr, casval, ip1)
|I0Pfree(ip1) => i0pckgo1(filr, casval, ip1)
//
// DATACON / structural patterns -> M2.7.  Emit `false` (never matches) and
// a loud stderr NOTE, so the clause is skipped, never silently wrong.
| _(*deferred*) =>
  (
  strnfpr(filr, "false /* UNHANDLED pat: datacon -> M2.7 */");
  prerrsln("[go1emit] UNHANDLED case pattern (datacon -> M2.7)"))
)//endof[i0pckgo1(filr,casval,ipat)]
//
(* ****** ****** *)
//
(*
i1bnd_bind_go1: bind the pattern's temp [itnm] to [casval] before a clause
body runs, so the body's references to the bound variable resolve.  Mirrors
js1emit's `let jsxtnm<itnm> = <ival>` in f0_i1valgpt.  Emitted only when the
body actually USES the bind temp (Go errors on a declared-but-unused local);
a wildcard / unused bind is skipped.
*)
fun
i1bnd_bind_go1
( env0: !envx2go
, casval: i1val
, ibnd: i1bnd
, body: i1cmp): void =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
  val-I1BNDcons(itnm, _, _) = ibnd
in//let
  if i1tnm_used_in_cmp(itnm, body)
  then
  (
  nindfpr(filr, nind);
  i1tnmgo1(filr, itnm); strnfpr(filr, " := ");
  i1valgo1(filr, casval); fprintln(filr))
  else ((*unused bind -- skip*))
end//let//endof[i1bnd_bind_go1(...)]
//
(* ****** ****** *)
//
(*
i1gua_emit_lets: emit ONE guard's let-bindings (the comparison computation)
and return its boolean RESULT i1val.  A guard I1GUAexp(icmp) has the shape
I1CMPcons(lets, resultBool).  We emit [lets] inside the clause arm and use
[resultBool] as the gate (joined with the pattern via [f0_guards_cond]).
*)
fun
i1gua_emit_lets
( env0: !envx2go
, igua: i1gua): i1val =
(
case+ igua.node() of
|I1GUAexp(icmp) =>
  let
    val-I1CMPcons(ilts, ival) = icmp
    val () = i1letlst_go1emit(ilts, icmp, env0)
  in
    ival
  end
|I1GUAmat(icmp, _) =>
  let
    val-I1CMPcons(ilts, ival) = icmp
    val () = i1letlst_go1emit(ilts, icmp, env0)
    val () = prerrsln("[go1emit] NOTE: I1GUAmat guard (M2.3 best-effort)")
  in
    ival
  end
)//endof[i1gua_emit_lets(env0,igua)]
//
fun
i1gualst_emit_lets
( iguas: i1gualst
, env0: !envx2go): i1valist =
(
case+ iguas of
|list_nil() => list_nil()
|list_cons(ig1, igs1) =>
  let
    val v1 = i1gua_emit_lets(env0, ig1)
    val vs1 = i1gualst_emit_lets(igs1, env0)
  in
    list_cons(v1, vs1)
  end
)//endof[i1gualst_emit_lets(...)]
//
(* ****** ****** *)
//
(*
f0_branch: emit ONE if-branch body (the optn(i1cmp) for then/else).
RETURN mode -> the branch cmp via i1cmp_go1emit_ret (each branch returns).
VALUE mode  -> i1cmp_go1emit_tnm (assign to result temp) when live, else
the cmp's effect form.  A missing branch (optn_nil) emits nothing.
*)
fun
f0_branch
( retq: bool
, live: bool
, itnm: i1tnm
, ocmp: i1cmpopt
, params: i1tnmlst
, bnds: i1bndlst
, env0: !envx2go): void =
(
case+ ocmp of
|optn_nil() => ((*void*))
|optn_cons(icmp) =>
  (
  if retq then i1cmp_go1emit_ret(icmp, params, bnds, env0)
  else
  (
  if live then i1cmp_go1emit_tnm(itnm, icmp, env0)
  else i1cmp_go1emit(icmp, env0)))
)//endof[f0_branch(...)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
GUARD HANDLING (Go's expression-less switch == if-else chain).
//
A guarded clause `| p when g => body` must, on a FAILED guard, retry the
NEXT clause -- exactly Go's `case <cond>:` fall-through when <cond> is false.
So we FOLD the guard into the case CONDITION: `case <patcond> && <g>:`.  The
catch: a guard `g` is a CMP (op-resolution timps + a comparison dapp), not a
bare expression.  But its lets are side-effect-free and (for the M2.3 native-
scalar surface) compute op-temps that the native-op path renders INLINE -- so
the guard RESULT i1val (e.g. I1Vtnm bound to the comparison) renders as
`(n > 0)` with the op-temps dropping to dead `_ = ...`.  We therefore PRE-EMIT
every guarded clause's guard-lets ABOVE the switch and fold the result i1val
into the case condition.  The guard references the SCRUTINEE temp directly
(verified in the IR: `dapp(op, [I1Vtnm(scrutinee), ...])`), already in scope,
so no pre-switch pattern bind is needed.
//
[i1clslst_emit_guards] does the pre-pass: it emits each guarded clause's
guard-lets (in clause order, BEFORE `switch {`) and returns a parallel list of
`optn(i1val)` -- the &&-joined guard result for each clause (optn_nil for an
unguarded clause).  [i1clslst_go1emit] then consumes that list to emit each
`case <patcond>[ && <guard>]:` arm.
*)
//
fun
i1cls_guard_emit
( icl0: i1cls
, env0: !envx2go): optn(i1val) =
(
case+ icl0.node() of
|I1CLSgpt(igpt) => i1gpt_guard_emit(igpt, env0)
|I1CLScls(igpt, _) => i1gpt_guard_emit(igpt, env0)
)
//
and
i1gpt_guard_emit
( igpt: i1gpt
, env0: !envx2go): optn(i1val) =
(
case+ igpt.node() of
|I1GPTpat(_) => optn_nil()
|I1GPTgua(_, iguas) =>
  let
    // emit the guard lets (above the switch); the result i1val drives the
    // case condition (`case <pat> && <g>:`).  M2.3 guards are a single
    // comparison, so we use the head guard's result; a (rare) multi-guard
    // clause uses its first guard and is reported (the others are conjuncts
    // that would need &&-joining at the case site -- a small M2.x follow-up).
    val gvals = i1gualst_emit_lets(iguas, env0)
  in
    (
    case+ gvals of
    |list_nil() => optn_nil()
    |list_cons(g1, list_nil()) => optn_cons(g1)
    |list_cons(g1, _) =>
      (
      prerrsln("[go1emit] NOTE: multi-guard clause -- using first guard (M2.3)");
      optn_cons(g1)))
  end
)//endof[i1gpt_guard_emit(igpt,env0)]
//
fun
i1clslst_emit_guards
( icls: i1clslst
, env0: !envx2go): list(optn(i1val)) =
(
case+ icls of
|list_nil() => list_nil()
|list_cons(ic1, ics1) =>
  let
    val g1 = i1cls_guard_emit(ic1, env0)
    val gs1 = i1clslst_emit_guards(ics1, env0)
  in
    list_cons(g1, gs1)
  end
)//endof[i1clslst_emit_guards(...)]
//
(* ****** ****** *)
//
(*
i1cls_go1emit_g: the guard-aware clause emitter ([gopt] = this clause's
pre-emitted guard result, optn_nil if unguarded).  A guarded clause emits
`case <patcond> && <gresult>:`; the pattern test is [i0pckgo1] ("true" for
var/wildcard).
*)
fun
i1cls_go1emit_g
( retq: bool, live: bool, itnm: i1tnm
, casval: i1val, icl0: i1cls, gopt: optn(i1val)
, params: i1tnmlst, bnds: i1bndlst, env0: !envx2go): void =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
in//let
case+ icl0.node() of
//
// a guard-only clause (no body) -- rare; skip (next clause / default
// covers it).  Reported for visibility.
|I1CLSgpt(_) =>
  (
  prerrsln("[go1emit] NOTE: I1CLSgpt (guard-only clause) skipped"))
//
|I1CLScls(igpt, body) =>
  let
    // the bind is whatever I1GPTpat/I1GPTgua carries.
    val ibnd =
    (
    case+ igpt.node() of
    |I1GPTpat(ibnd) => ibnd
    |I1GPTgua(ibnd, _) => ibnd)
    val-I1BNDcons(_, ipat, _) = ibnd
    //
    // `case <patcond>[ && <guardresult>]:`
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "case ");
    i0pckgo1(filr, casval, ipat);
    (
    case+ gopt of
    |optn_nil() => ()
    |optn_cons(gv) =>
      (
      strnfpr(filr, " && "); i1valgo1(filr, gv)));
    strnfpr(filr, ":"); fprintln(filr))
    //
    val () = envx2go_incnind(env0, 1)
    val () = i1bnd_bind_go1(env0, casval, ibnd, body)
    val () =
      if retq then i1cmp_go1emit_ret(body, params, bnds, env0)
      else
      (
      if live then i1cmp_go1emit_tnm(itnm, body, env0)
      else i1cmp_go1emit(body, env0))
    val () = envx2go_decnind(env0, 1)
  in
    ((*void*))
  end
//
end//let//endof[i1cls_go1emit_g(...)]
//
fun
i1clslst_go1emit_g
( retq: bool, live: bool, itnm: i1tnm
, casval: i1val, icls: i1clslst, gopts: list(optn(i1val))
, params: i1tnmlst, bnds: i1bndlst, env0: !envx2go): void =
(
case+ icls of
|list_nil() => ((*void*))
|list_cons(ic1, ics1) =>
  let
    val (g1, gs1) =
    (
    case+ gopts of
    |list_nil() => @(optn_nil(), list_nil())
    |list_cons(g1, gs1) => @(g1, gs1))
  in
    i1cls_go1emit_g(retq, live, itnm, casval, ic1, g1, params, bnds, env0);
    i1clslst_go1emit_g(retq, live, itnm, casval, ics1, gs1, params, bnds, env0)
  end
)//endof[i1clslst_go1emit_g(...)]
//
(*
The SATS-declared clause entries (i1cls_go1emit / i1clslst_go1emit) delegate
to the guard-aware variants with an empty guard list -- they are the entries
the rest of the emitter / a future caller would use without the pre-pass.
*)
#implfun
i1cls_go1emit
(retq, live, itnm, casval, icl0, params, bnds, env0) =
  i1cls_go1emit_g(retq, live, itnm, casval, icl0, optn_nil(), params, bnds, env0)
//
#implfun
i1clslst_go1emit
(retq, live, itnm, casval, icls, params, bnds, env0) =
  i1clslst_go1emit_g(retq, live, itnm, casval, icls, list_nil(), params, bnds, env0)
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== M2.5 CLOSURES: lambdas + local recursive closures                 ==
=======================================================================
//
A lambda [I1INSlam0(knd, fjas, body)] emits as an INLINE Go func literal
bound to its temp:
    goxtnm<itnm> := func(<p0> <T0>, <p1> <T1>) <Tret> {
        <body in return mode>
    }
CRUCIAL (vs the M2.2 top-level `fun`, which is HOISTED to package level): a
lambda is emitted IN PLACE at its definition point, so the func literal
captures the surrounding locals by Go's lexical closure.  The IR already
rewrote each captured free variable to its OUTER binding (our
[envi0i1_i0ws$insert] divergence), so the body references the enclosing
[goxtnm<...>] directly -- no env struct, no closure conversion, exactly as
the PLAN intends.
//
A local recursive closure [I1INSfix0(knd, fvar, fjas, body)] needs Go's
self-reference idiom (a `:=` func literal cannot name itself):
    var <fname> func(<T0>, <T1>) <Tret>
    <fname> = func(<p0> <T0>, <p1> <T1>) <Tret> { ... <fname>(...) ... }
    goxtnm<itnm> := <fname>
where <fname> = the FIX-VAR's Go name (d2vargo1(fvar)).  The body's
self-call lowers to [I1INSdapp(I1Vfenv(fvar, _), args)] whose callee
[I1Vfenv(fvar)] already emits [d2vargo1(fvar)] (= <fname>), so the
self-reference resolves to the pre-declared `var`.  The outer temp
[goxtnm<itnm>] is bound to <fname> so any later use of the closure VALUE
(I1Vtnm(itnm)) still works.  TCO of the fix0 self-call (a `for` loop) is a
follow-up; M2.5 emits a correct stack-using recursive self-call.
*)
//
(*
fjarglst_go1emit_typed_params: emit the Go parameter list
`<p0> <T0>, <p1> <T1>` for a lambda/fix between the parens the caller
opened.  Zips the param i1tnms (params_of_fjarglst) with the recovered Go
types (gotypes_of_fjarglst); a missing type falls back to "any".  (Go does
not error on unused params, so a captured-only lambda's unread params need
no `_ =`.)  Mirrors the M2.2 fjarglst_go1emit_params but reusable here.
*)
fun
fjarglst_go1emit_typed_params
( filr: FILR
, fjas: fjarglst
, ptys: list(strn)): void =
let
  val ptnms = params_of_fjarglst(fjas)
  //
  fun
  loop
  (i0: sint, ts: i1tnmlst, gs: list(strn)): void =
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
      if (i0 >= 1) then strnfpr(filr, ", ");
      i1tnmgo1(filr, p1); strnfpr(filr, " "); strnfpr(filr, goty))
    in
      loop(i0+1, ts1, gs1)
    end
  )
in
  loop(0, ptnms, ptys)
end//endof[fjarglst_go1emit_typed_params(filr,fjas,ptys)]
//
(*
emit_lam_body: emit a lambda/fix BODY cmp in return mode + the closing `}`.
The body is the canonical I1CMPcons([I1LETnew0(I1INSrturn(_, inner))], nil);
[i1cmp_go1emit_ret] unwraps it -> inner lets + `return`.  We pass
params=list_nil() so NO tail-loop is generated for the closure body (local-
closure TCO is a documented follow-up); a tail self-call therefore stays a
correct stack-using recursive call.
*)
fun
emit_lam_body
( body: i1cmp
, bnds: i1bndlst
, env0: !envx2go): void =
let
  val filr = env0.filr()
in
  envx2go_incnind(env0, 1(*++*));
  // params=list_nil() => NO tail-loop for the closure body (local-closure TCO
  // is a follow-up); [bnds] = the in-scope param binds (this lambda's own
  // params + enclosing captures) so a NESTED lambda emitted inside this body
  // recovers its return type (M2.5).
  i1cmp_go1emit_ret(body, list_nil(), bnds, env0);
  envx2go_decnind(env0, 1(*--*));
  nindfpr(filr, envx2go_nind$get(env0)); strnfpr(filr, "}"); fprintln(filr)
end//endof[emit_lam_body(body,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
i1ins_go1emit_block: emit a BLOCK-FORM instruction (if / case / let-in /
lambda / local-rec-closure) bound to result temp [itnm].  For if/case it
dispatches on RETURN position (all branches end in rturn -> each emits its
own `return`, no pre-declared temp) vs VALUE position (pre-declare `var
goxtnm<itnm> <T>`; branches assign).  For a lambda/fix it emits an inline Go
func literal (capturing surrounding locals lexically).  [scp] is the
enclosing liveness scope.
*)
#implfun
i1ins_go1emit_block
(scp, itnm, iins, params, bnds, env0) =
let
  val filr = env0.filr()
in//let
case+ iins of
//
(* ----- I1INSift0 : Go `if` ------------------------------------------- *)
|I1INSift0(itst, othn, oels) =>
  let
    val retq = i1ins_fully_returnsq(iins)
    val live = i1tnm_used_in_cmp(itnm, scp)
    val nind = envx2go_nind$get(env0)
    //
    val () =
      if retq then () else
      (
      if live then
      (
      nindfpr(filr, nind);
      strnfpr(filr, "var "); i1tnmgo1(filr, itnm);
      strnfpr(filr, " "); strnfpr(filr, gotype_of_ift0type(iins));
      fprintln(filr))
      else ())
    //
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "if ");
    i1valgo1(filr, itst); strnfpr(filr, " {"); fprintln(filr))
    //
    val () = envx2go_incnind(env0, 1)
    val () = f0_branch(retq, live, itnm, othn, params, bnds, env0)
    val () = envx2go_decnind(env0, 1)
    //
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "} else {"); fprintln(filr))
    //
    val () = envx2go_incnind(env0, 1)
    val () = f0_branch(retq, live, itnm, oels, params, bnds, env0)
    val () = envx2go_decnind(env0, 1)
    //
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "}"); fprintln(filr))
  in
    ((*void*))
  end
//
(* ----- I1INScas0 : Go expression-less `switch` ----------------------- *)
|I1INScas0(_, casval, icls) =>
  let
    val retq = i1ins_fully_returnsq(iins)
    val live = i1tnm_used_in_cmp(itnm, scp)
    val nind = envx2go_nind$get(env0)
    //
    val () =
      if retq then () else
      (
      if live then
      (
      nindfpr(filr, nind);
      strnfpr(filr, "var "); i1tnmgo1(filr, itnm);
      strnfpr(filr, " "); strnfpr(filr, gotype_of_ift0type(iins));
      fprintln(filr))
      else ())
    //
    // GUARD pre-pass: emit each guarded clause's guard-lets ABOVE the switch
    // (so the guard result is in scope for the case condition); collect the
    // per-clause guard results (optn_nil for unguarded clauses).  Folding the
    // guard into `case <pat> && <g>:` makes a failed guard fall through to the
    // NEXT clause -- matching the JS backend's retry-next-clause semantics.
    val gopts = i1clslst_emit_guards(icls, env0)
    //
    // expression-less switch == if-else chain with implicit break.
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "switch {"); fprintln(filr))
    //
    val () = i1clslst_go1emit_g(retq, live, itnm, casval, icls, gopts, params, bnds, env0)
    //
    // a `default:` arm for match failure, mirroring the JS backend's
    // XATS000_cfail() fall-through.  We emit a literal `panic(...)` -- a Go
    // TERMINATING statement -- rather than only a runtime call, so a return-
    // position switch (every real case returns) is seen by Go's flow
    // analysis as exhaustive (else: "missing return").  Observable behavior
    // matches the JS backend's XATS000_cfail throw; in a passing program the
    // default is never reached (oracle-checked).
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "default:"); fprintln(filr))
    val () = envx2go_incnind(env0, 1)
    val () =
    (
    nindfpr(filr, envx2go_nind$get(env0));
    strnfpr(filr, "panic(\"xats2go: XATS000_cfail\")"); fprintln(filr))
    val () = envx2go_decnind(env0, 1)
    //
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "}"); fprintln(filr))
  in
    ((*void*))
  end
//
(* ----- I1INSlet0 : Go local-decl block ------------------------------- *)
|I1INSlet0(dcls, icmp) =>
  let
    // RETURN position iff the let BODY [icmp] fully returns (its inner if/
    // case branches end in I1INSrturn) -- i1ins_fully_returnsq(I1INSlet0) =
    // i1cmp_tail_returns(icmp).  This is the SAME return-vs-value decision the
    // M2.3 if/case use, now threaded through I1INSlet0's body (the bug fix):
    // in return mode the body emits its OWN returns (via i1cmp_go1emit_ret),
    // so NO result temp is pre-declared and NO trailing `return goxtnm<N>` is
    // appended -- which would be UNREACHABLE (`go vet`: "unreachable code").
    val retq = i1ins_fully_returnsq(iins)
    val live = i1tnm_used_in_cmp(itnm, scp)
    val nind = envx2go_nind$get(env0)
    //
    // VALUE mode (body does NOT fully return): pre-declare the result var
    // [goxtnm<itnm>], then a `{ <local decls>; goxtnm = <cmp result> }`
    // block.  In RETURN mode NO result var is pre-declared.
    val () =
      if retq then () else
      (
      if live then
      (
      nindfpr(filr, nind);
      strnfpr(filr, "var "); i1tnmgo1(filr, itnm);
      strnfpr(filr, " "); strnfpr(filr, gotype_of_ift0type(iins));
      fprintln(filr))
      else ())
    //
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "{"); fprintln(filr))
    val () = envx2go_incnind(env0, 1)
    //
    // emit the inner LOCAL declarations (reuse the decl walk).
    val () = i1dclist_go1emit(dcls, env0)
    //
    // emit the let BODY:
    //  - RETURN mode -> i1cmp_go1emit_ret (the body's inner if/case branches
    //    emit their own `return`; [params]/[bnds] threaded so a tail self-call
    //    inside a branch still becomes a loop `continue`, and a nested lambda
    //    recovers its return type -- exactly the if/case branch contract).
    //  - VALUE mode  -> assign the inner cmp's result to [itnm] (or discard).
    val () =
      if retq then i1cmp_go1emit_ret(icmp, params, bnds, env0)
      else
      (
      if live
      then i1cmp_go1emit_tnm(itnm, icmp, env0)
      else i1cmp_go1emit(icmp, env0))
    //
    val () = envx2go_decnind(env0, 1)
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "}"); fprintln(filr))
  in
    ((*void*))
  end
//
(* ----- I1INSlam0 : inline Go func literal (lexical capture) ---------- *)
|I1INSlam0(_, fjas, body) =>
  let
    val nind = envx2go_nind$get(env0)
    val argtys = gotypes_of_fjarglst(fjas)
    // M2.5: the return type is recovered with THIS lambda's own params PLUS the
    // enclosing in-scope binds [bnds] -- so a body that returns a captured/param
    // var (`lam u => a`) or a nested lambda is typed concretely (NOT "any",
    // which collides with the enclosing func's signature).  The same augmented
    // binds [bnds1] are threaded into the body emit so a nested lambda inside
    // this body recovers ITS return type too.
    val bnds1  = list_append(binds_of_fjarglst(fjas), bnds)
    val retty  = gotype_of_lam_ret(body, bnds1)
    val live = i1tnm_used_in_cmp(itnm, scp)
    //
    // goxtnm<itnm> := func(<typed params>) <ret> {   (or `_ =` if dead, so
    // a never-used lambda does not trip Go's "declared and not used").
    val () =
    (
    nindfpr(filr, nind);
    if live
      then (i1tnmgo1(filr, itnm); strnfpr(filr, " := func("))
      else strnfpr(filr, "_ = func(");
    fjarglst_go1emit_typed_params(filr, fjas, argtys);
    strnfpr(filr, ") "); strnfpr(filr, retty);
    strnfpr(filr, " {"); fprintln(filr))
    // <body in return mode> + closing `}`
    val () = emit_lam_body(body, bnds1, env0)
  in
    ((*void*))
  end
//
(* ----- I1INSfix0 : self-referential local recursive closure ---------- *)
|I1INSfix0(_, fvar, fjas, body) =>
  let
    val nind = envx2go_nind$get(env0)
    // the param/result Go types come from the FIX-VAR's declared function
    // signature (d2var_get_styp -> T2Pfun1) -- more reliable than inferring
    // from the if/case-bodied recursive body (whose branches return computed
    // temps the i1val level cannot type).  Fall back to the param patterns'
    // own d2var styps / body inference only when the fix-var has no fun type.
    val vargtys = goargtys_of_funvar(fvar)
    val argtys  =
      (case+ vargtys of
       |list_nil() => gotypes_of_fjarglst(fjas)
       |list_cons _ => vargtys)
    val vretty = goretty_of_funvar(fvar)
    // M2.5: in-scope binds for the body = this fix's own params + enclosing
    // captures; used both for the return-type fallback and the body emit.
    val bnds1  = list_append(binds_of_fjarglst(fjas), bnds)
    val retty  =
      (if (vretty = "any") then gotype_of_lam_ret(body, bnds1) else vretty)
    val ftype  = gofunctype_of_fjarglst(argtys, retty)
    //
    // var <fname> <functype>           (so the func literal can name itself)
    val () =
    (
    nindfpr(filr, nind);
    strnfpr(filr, "var "); d2vargo1(filr, fvar);
    strnfpr(filr, " "); strnfpr(filr, ftype); fprintln(filr))
    // <fname> = func(<typed params>) <ret> {   (params typed from [argtys]
    // -- the SAME list as the `var` func type, so the signatures match).
    val () =
    (
    nindfpr(filr, nind);
    d2vargo1(filr, fvar); strnfpr(filr, " = func(");
    fjarglst_go1emit_typed_params(filr, fjas, argtys);
    strnfpr(filr, ") "); strnfpr(filr, retty);
    strnfpr(filr, " {"); fprintln(filr))
    // <body in return mode; self-call I1Vfenv(fvar) -> <fname>> + `}`
    val () = emit_lam_body(body, bnds1, env0)
    // bind the OUTER temp to the closure value, so a later I1Vtnm(itnm) use
    // (e.g. the application `(i,1)`) resolves to the same Go func.
    val live = i1tnm_used_in_cmp(itnm, scp)
    val () =
      if live then
      (
      nindfpr(filr, nind);
      i1tnmgo1(filr, itnm); strnfpr(filr, " := ");
      d2vargo1(filr, fvar); fprintln(filr))
      else ()
  in
    ((*void*))
  end
//
| _(*non-block*) =>
  unhandled_ins(filr, "i1ins_go1emit_block(non-block)", iins)
//
end//let//endof[i1ins_go1emit_block(scp,itnm,iins,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
i1letlst_go1emit / i1let_go1emit: walk a flat let-list.  An I1LETnew1
binding to a BLOCK-FORM instruction (if/case/let-in) routes to
[i1ins_go1emit_block]; everything else keeps the M2.0/M2.1 single-line
liveness rule (live tnm -> `goxtnm := <expr>`, dead -> `_ = <expr>`).
//
The SATS entries thread NO TCO params (list_nil): they cover value-position
and effect contexts where a block-form's branches are NOT in return mode.
The params-aware [_p] workers (used by [emit_ret_plain]) thread [params] so
a trailing return-position if/case in a FUNCTION BODY gets the TCO loop
context down to its branches.
*)
#implfun
i1letlst_go1emit
(ilts, scp, env0) = i1letlst_go1emit_p(ilts, scp, list_nil(), list_nil(), env0)
//
#implfun
i1let_go1emit
(ilet, scp, env0) = i1let_go1emit_p(ilet, scp, list_nil(), list_nil(), env0)
//
#implfun
i1letlst_go1emit_p
(ilts, scp, params, bnds, env0) =
(
case+ ilts of
|list_nil() => ((*void*))
|list_cons(ilt1, ilts1) =>
  (
  i1let_go1emit_p(ilt1, scp, params, bnds, env0);
  i1letlst_go1emit_p(ilts1, scp, params, bnds, env0))
)//endof[i1letlst_go1emit_p(ilts,scp,params,bnds,env0)]
//
#implfun
i1let_go1emit_p
(ilet, scp, params, bnds, env0) =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
in//let
case+ ilet of
//
|I1LETnew1(itnm, iins) =>
  (
  if i1ins_is_blockform(iins)
  then i1ins_go1emit_block(scp, itnm, iins, params, bnds, env0)
  else
  if i1ins_is_construct(iins)
  then
    // M2.6b: a tuple/record CONSTRUCTION emits as a single-line struct literal
    // whose TYPE comes from THIS binding temp [itnm] (its recorded i0typ) --
    // so we route to [i1trcd_construct_go1emit] (which has the temp) for the
    // RHS, after emitting the live/dead binding prefix as usual.
    let
      val live = i1tnm_used_in_cmp(itnm, scp)
    in
    (
    nindfpr(filr, nind);
    if live
      then (i1tnmgo1(filr, itnm); strnfpr(filr, " := "))
      else strnfpr(filr, "_ = ");
    i1trcd_construct_go1emit(filr, itnm, iins); fprintln(filr))
    end
  else
  let
    val live = i1tnm_used_in_cmp(itnm, scp)
  in
  (
  nindfpr(filr, nind);
  if live
    then (i1tnmgo1(filr, itnm); strnfpr(filr, " := "))
    else strnfpr(filr, "_ = ");
  i1insgo1(filr, scp, iins); fprintln(filr))
  end)
//
|I1LETnew0(iins) =>
  (
  if i1ins_is_blockform(iins)
  then
    // a block-form in statement position (no binding): drive it as a value-
    // position block with a throwaway temp (its result is unit/discarded).
    let val tmp = i1tnm_new0() in i1ins_go1emit_block(scp, tmp, iins, params, bnds, env0) end
  else
  if i1ins_is_construct(iins)
  then
    // a construction whose result is discarded -- mint a throwaway temp for the
    // (unused) struct type lookup, emit it as `_ = <struct literal>`.
    let
      val tmp = i1tnm_new0()
    in
    (
    nindfpr(filr, nind); strnfpr(filr, "_ = ");
    i1trcd_construct_go1emit(filr, tmp, iins); fprintln(filr))
    end
  else
  (
  nindfpr(filr, nind);
  i1insgo1(filr, scp, iins); fprintln(filr)))
//
end//let//endof[i1let_go1emit_p(ilet,scp,params,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
i1cmp_go1emit / _ret / _tnm: the three cmp result modes.  All share the
let-list walk; they differ only in how the cmp RESULT value is emitted:
  - effect : `_ = <result>`         (top-level val; result discarded)
  - return : `return <result>`      (function body) -- SUPPRESSED when the
             cmp already returns (i1cmp_retq: a trailing fully-returning
             if/case means every path returned, so a dangling `return
             goxtnm` would reference an unassigned var -- skip it).
  - tnm    : `goxtnm<itnm> = <result>` (value-position branch) -- SUPPRESSED
             when the cmp already returns (the branch returned instead).
*)
#implfun
i1cmp_go1emit
(icmp, env0) =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
  val-I1CMPcons(ilts, ival) = icmp
  val () = i1letlst_go1emit(ilts, icmp, env0)
in//let
  // discard the result UNLESS the cmp already returned (a fully-returning
  // trailing if/case): then no `_ = <ival>` is emitted (it would read an
  // unassigned temp / be unreachable).
  if i1cmp_tail_returns(icmp) then () else
  (
  nindfpr(filr, nind);
  strnfpr(filr, "_ = ");
  i1valgo1(filr, ival); fprintln(filr))
end//let//endof[i1cmp_go1emit(icmp,env0)]
//
#implfun
i1cmp_go1emit_ret
(icmp, params, bnds, env0) =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
in//let
  //
  // The canonical function-body / branch-body shape is a single
  // [I1LETnew0(I1INSrturn(ical, innerCmp))].  M2.4 TCO: when [innerCmp] is a
  // TAIL self-call (rturn_tail_args) AND [params] is active (the function
  // body was wrapped in a `for {}` loop), emit the call as a LOOP CONTINUE --
  // the arg pre-computation lets first (so each new param value is already in
  // its own temp: simultaneity-safe), then `goxtnm<p_i> = <newarg_i>` for each
  // param, then `continue`.  Otherwise fall back to the plain return path.
  //
  case+ icmp of
  |I1CMPcons
    (list_cons(I1LETnew0(I1INSrturn(ical, innerCmp)), list_nil()), _) =>
    (
    case+ rturn_tail_args(ical, innerCmp) of
    |optn_cons(@(pre, args)) when list_consq(params) =>
      (
      // 1. emit the lets that PRECEDE the tail call (pre-compute the new args
      //    into their own temps -- references the OLD params, simultaneity-safe).
      i1letlst_go1emit(pre, innerCmp, env0);
      // 2. reassign each parameter from the (already pre-computed) new value.
      emit_param_reassign(params, args, env0);
      // 3. continue the enclosing function loop.
      nindfpr(filr, nind); strnfpr(filr, "continue"); fprintln(filr))
    | _(*not a tail self-call, or TCO disabled*) =>
      emit_ret_plain(innerCmp, params, bnds, env0))
  //
  | _(*otherwise: a multi-let body (e.g. lets + a trailing if/case)*) =>
    emit_ret_plain(icmp, params, bnds, env0)
  //
end//let//endof[i1cmp_go1emit_ret(icmp,params,bnds,env0)]
//
(*
emit_param_reassign: emit `goxtnm<p_i> = <arg_i>` for each (param, newarg)
pair, in order.  The args are the tail call's argument i1vals -- pre-bound
ANF temps (or literals), so reading them does NOT depend on the assignment
order (the simultaneity guarantee).  [params] and [args] are positional and
equal-length (the IR builds the self-call with one arg per parameter).
*)
#implfun
emit_param_reassign
(params, args, env0) =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
in//let
  case+ (params, args) of
  |(list_cons(p1, ps1), list_cons(a1, as1)) =>
    (
    nindfpr(filr, nind);
    i1tnmgo1(filr, p1); strnfpr(filr, " = ");
    i1valgo1(filr, a1); fprintln(filr);
    emit_param_reassign(ps1, as1, env0))
  | _(*exhausted*) => ((*void*))
end//let//endof[emit_param_reassign(...)]
//
(*
emit_ret_plain: the M2.3 plain-return path -- unwrap the canonical single
[I1LETnew0(I1INSrturn(_, innerCmp))] to its inner cmp (the real compute), emit
the inner lets, then `return <result>` UNLESS the cmp already returned via a
trailing fully-returning if/case (i1cmp_tail_returns).  Threads [params] so a
tail self-call nested INSIDE a trailing if/case branch still becomes a loop
continue (the branch bodies are emitted in return mode with [params] live).
*)
#implfun
emit_ret_plain
(icmp, params, bnds, env0) =
let
  val cmp1 =
  (
  case+ icmp of
  |I1CMPcons(ilts, _) =>
    (
    case+ ilts of
    |list_cons(I1LETnew0(I1INSrturn(_, innerCmp)), list_nil()) => innerCmp
    | _(*otherwise*) => icmp)
  )
  val-I1CMPcons(ilts1, ival1) = cmp1
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
  val () = i1letlst_go1emit_p(ilts1, cmp1, params, bnds, env0)
in//let
  if i1cmp_tail_returns(cmp1) then () else
  (
  nindfpr(filr, nind);
  strnfpr(filr, "return ");
  i1valgo1(filr, ival1); fprintln(filr))
end//let//endof[emit_ret_plain(icmp,params,bnds,env0)]
//
#implfun
i1cmp_go1emit_tnm
(itnm, icmp, env0) =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
  val-I1CMPcons(ilts, ival) = icmp
  val () = i1letlst_go1emit(ilts, icmp, env0)
in//let
  // assign the result to the binding temp UNLESS the cmp already returned
  // (then the branch emitted its own return; no assignment).
  if i1cmp_tail_returns(icmp) then () else
  (
  nindfpr(filr, nind);
  i1tnmgo1(filr, itnm); strnfpr(filr, " = ");
  i1valgo1(filr, ival); fprintln(filr))
end//let//endof[i1cmp_go1emit_tnm(itnm,icmp,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_go1emit_dynexp.dats] *)
(***********************************************************************)
