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
=======================================================================
== M2.7 DATATYPES: datacon CONSTRUCTION                              ==
=======================================================================
//
A datatype value is a single boxed runtime type `*xatsgo.XatsCon`
(`XatsCon{Tag int; Args []any}`) -- datatypes are uniformly heap-boxed in ATS,
so a boxed pointer is the layout-correct choice (and mirrors the JS backend's
[ctag, ...args] array model, easing the differential oracle).
//
Construction is an [I1INSdapp(I1Vcon(dcon), vs)] (verified via the IR dump:
EVEN a nullary constructor like `myNone()` surfaces as a dapp on I1Vcon with an
EMPTY arg list -- so the SINGLE I1INSdapp/I1Vcon path covers both nullary and
applied constructors).  We emit
    &xatsgo.XatsCon{Tag: <d2con_get_ctag dcon>, Args: []any{<v0>, <v1>, ...}}
SKIPPING the proof args -- but they are ALREADY erased from [vs] at intrep1 (the
dapp's arg list is value-only, just like a tuple's [i1valist] skips npf), so no
explicit drop is needed (the JS backend likewise emits all of [vs] after the
ctag; XATSCAPP("optn_cons", [1, x0]) has no proof slot).  A nullary con emits
`Args: []any{}` (the empty composite literal -- gofmt-clean; Go treats it the
same as nil for indexing, which never happens for a 0-field con anyway).
*)
(*
[i0lab_int_go1]: emit a [label] as a Go integer index (for `.Args[<i>]`).  A
datacon field label is a positional [LABint(i)] -> `i`; a (non-occurring here)
symbol label falls back to 0 with a stderr note.
*)
fun
i0lab_int_go1
( filr: FILR
, lab0: label): void =
(
case+ lab0 of
|LABint(i0) => i0i00go1(filr, i0)
|LABsym(_) =>
  (
  strnfpr(filr, "0");
  prerrsln("[go1emit] NOTE: datacon lvalue with symbol label (unexpected)"))
)//endof[i0lab_int_go1(filr,lab0)]
//
fun
i1con_construct_go1emit
( filr: FILR
, dcon: d2con
, i1vs: i1valist): void =
let
  val ctag = d2con_get_ctag(dcon)
in//let
  strnfpr(filr, "&xatsgo.XatsCon{Tag: ");
  i0i00go1(filr, ctag);
  strnfpr(filr, ", Args: []any{");
  i1valgo1_list(filr, i1vs);
  strnfpr(filr, "}}")
end//endof[i1con_construct_go1emit(filr,dcon,i1vs)]
//
(*
=======================================================================
== M2.7 DATATYPES: datacon PROJECTION (typed field read)            ==
=======================================================================
//
A datacon field read is `<root>.Args[<idx>]` -- the [idx]-th VALUE arg of the
boxed XatsCon (proof args were never stored).  Because [Args] is `[]any`, the
result is `any`; we RECOVER the concrete field type from the constructor's
static type ([gotype_of_dcon_field]) and emit a Go TYPE ASSERTION
`<root>.Args[<idx>].(<T>)` so the projected value is concretely typed (e.g. a
list's cons-tail asserts to `*xatsgo.XatsCon` for recursive traversal; an int
payload to `int`).  When the field type is unrecoverable ("any") we emit NO
assertion (leaving it `any`) -- a wrong assertion would PANIC at run time, so
"any" is the type-safe fallback (and the oracle would catch a wrong assertion as
a panic/mismatch).
//
[goty_of_dcon] maps a datatype-typed field to its Go type.  [gotype_of_dcon_field]
already returns "*xatsgo.XatsCon" for a recursive/datatype field?  -- NO: the
constructor's static type spells a datatype field as a non-scalar [s2typ] that
[gotype_of_styp] maps to "any" (datatypes are not in its scalar table).  So we
POST-PROCESS: a field type of "any" that the source knows is a DATATYPE is
emitted as `*xatsgo.XatsCon` ONLY when we can prove it (we cannot from "any"
alone), so the generic rule keeps "any" for non-scalar fields -- EXCEPT we make
the common recursive case work by recognizing the field type string directly.
//
[i1con_proj_go1emit]: emit `<root>.Args[<idx>]` with a `.(T)` assertion iff [gty]
is a concrete (non-"any") Go type.
*)
fun
i1con_proj_go1emit
( filr: FILR
, iroot: i1val
, idx: sint
, gty: strn): void =
(
i1valgo1(filr, iroot);
strnfpr(filr, ".Args["); i0i00go1(filr, idx); strnfpr(filr, "]");
(
if (gty = "any") then ()
else (strnfpr(filr, ".("); strnfpr(filr, gty); strnfpr(filr, ")"))))
//endof[i1con_proj_go1emit(filr,iroot,idx,gty)]
//
(*
[dcon_of_i0pat]: extract the [d2con] from a constructor pattern -- an
[I0Pcon(dcon)] directly, or the head pattern of an [I0Pdapp]/[I0Pdap1].  Used to
type an [I1Vp1cn] projection (whose carried [i0pat] is the constructor pattern).
[optn_nil] when the pattern is not a constructor (then the field type is "any").
*)
fun
dcon_of_i0pat
(ipat: i0pat): optn(d2con) =
(
case+ ipat.node() of
|I0Pcon(dcon) => optn_cons(dcon)
|I0Pdap1(ip1) => dcon_of_i0pat(ip1)
|I0Pdapp(ip1, _, _) => dcon_of_i0pat(ip1)
| _(*else*) => optn_nil()
)//endof[dcon_of_i0pat(ipat)]
//
(*
[goty_of_p1cn]: the Go field type for an [I1Vp1cn(i0pat, _, pind)] -- the [pind]-th
value field of the constructor [i0pat] names.  Returns the scalar Go type when
recoverable; for a DATATYPE-typed field (the recursive case, e.g. a list's
cons-tail), [gotype_of_dcon_field] yields "any" (datatypes are not scalars), so a
caller wanting `*xatsgo.XatsCon` recursion must assert at the use site -- BUT the
IR projection is consumed positionally and we cannot prove the datatype identity
here, so we conservatively keep "any" and let the value flow as `any`.  (A
recursive list-sum still works: the cons-tail flows as `any` into the recursive
call, whose datatype PARAMETER is typed `*xatsgo.XatsCon`, and Go's assignment
from `any` to `*xatsgo.XatsCon` is... NOT implicit.  So we DO need the assertion.
See [goty_of_dcon_field_rec].)
*)
fun
goty_of_p1cn
(ipat: i0pat, pind: sint): strn =
(
case+ dcon_of_i0pat(ipat) of
|optn_nil() => "any"
|optn_cons(dcon) => gotype_of_dcon_field(dcon, pind)
)//endof[goty_of_p1cn(ipat,pind)]
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
(*
M2.6c LEFT-VALUES: an addressable Go lvalue expression `<root>.F<lab>`.
//
  I1Vlpft(lab, root) : FLAT field of an addressable value (a `var` holding a
                       value struct, or a flat sub-field of one).  In Go the
                       lvalue is `<root>.F<lab>` and `<root>` is itself
                       addressable, so the field assignment mutates IN PLACE
                       (ATS flat / VALUE semantics).
  I1Vlpbx(lab, root) : BOXED field -- `<root>` is a pointer (`*struct`).  Go
                       auto-derefs for field assignment, so the SAME
                       `<root>.F<lab>` lvalue mutates the pointed-to struct =
                       SHARED (every alias sees it; ATS boxed semantics).
//
A `var p = @(t)` makes `p` a Go `var` (addressable), so `p.F0` is a valid
lvalue root; a field of a boxed tuple is a pointer field.  The field NAME
[gofield_of_label] is the SAME scheme the struct TYPE used at construction and
that every READ projection (I1INSpflt/proj) uses, so the lvalue resolves.  Both
flat and boxed render as `<root>.F<lab>` -- Go's pointer auto-deref unifies the
SYNTAX; the value-vs-pointer ROOT (M2.6b) realizes the flat/boxed semantics.
*)
|I1Vlpft(lab0, iroot) =>
  (
  i1valgo1(filr, iroot);
  strnfpr(filr, "."); strnfpr(filr, gofield_of_label(lab0)))
|I1Vlpbx(lab0, iroot) =>
  (
  i1valgo1(filr, iroot);
  strnfpr(filr, "."); strnfpr(filr, gofield_of_label(lab0)))
//
(*
M2.6c ADDR / AEXP: a left-value root that is the var/value itself.
  I1Vaddr(v) : address-of -- in Go a `var` is already addressable, so taking
               its address for an lvalue path is a no-op at the syntax level
               (Go's `&` is implicit for field assignment through a value var);
               we emit the inner expression `<v>`.  (JS: XATSADDR = identity.)
*)
|I1Vaddr(iv1) =>
  (
  i1valgo1(filr, iv1))
//
(*
M2.7 DATACON PROJECTION (sub-pattern variable read).  A datacon sub-pattern
variable (e.g. `xs` in `cons(x, xs) => ... xs ...`) does NOT bind a temp -- the
front-end inlines its access as an [I1Vp1cn(i0pat, root, pind)] projection node
at EACH use site (verified via the IR dump, mirroring the JS backend's f0_dapp
-> proj -> I1Vp1cn, where the WHOLE-scrutinee bind is the only `let`).  We emit
`<root>.Args[<pind>].(<T>)`, recovering the field Go type [T] from the carried
constructor pattern [i0pat] (its [I0Pcon] d2con's [pind]-th field) -- a scalar
asserts to its concrete type, a datatype field asserts to `*xatsgo.XatsCon` (the
recursion case), a polymorphic field stays `any` (no assertion).
*)
|I1Vp1cn(ipat, iroot, pind) =>
  i1con_proj_go1emit(filr, iroot, pind, goty_of_p1cn(ipat, pind))
//
(*
M2.7 DATACON LEFT-VALUE.  I1Vlpcn(lab, root): a consed-datatype field as an
ASSIGNABLE lvalue (datacon field mutation, `v.Args[<lab>] = rhs`).  In Go the
boxed XatsCon's [Args] slice is addressable, so `<root>.Args[<lab>]` is a valid
assignment target; the value is stored as `any` (the slot type), so NO type
assertion is emitted on the LVALUE side (a `.(T)` is not addressable in Go).
[lab] is a LABint(i) -- the value-field index.
*)
|I1Vlpcn(lab0, iroot) =>
  (
  i1valgo1(filr, iroot);
  strnfpr(filr, ".Args["); i0lab_int_go1(filr, lab0); strnfpr(filr, "]"))
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
(
// M2.7 DATACON CONSTRUCTION: an I1INSdapp whose callee is an I1Vcon (the
// constructor value) builds a `*xatsgo.XatsCon{Tag, Args}` -- this covers BOTH
// applied (`mySome(42)`) and nullary (`myNone()`) constructors (the IR lowers
// both to a dapp on I1Vcon).  Checked FIRST so a constructor is never mistaken
// for a native op / plain call.
case+ i1f0.node() of
|I1Vcon(dcon) => i1con_construct_go1emit(filr, dcon, i1vs)
| _(*non-con callee*) =>
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
)//endof[I1INSdapp(i1f0,i1vs) -- datacon vs op vs call dispatch]
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
(*
M2.7 DATACON PROJECTION as an instruction: I1INSpcon(lab, v) -> `v.Args[<lab>]`.
Unlike the I1Vp1cn value node (which carries the constructor pattern, so the
field type is recoverable), I1INSpcon carries ONLY the label, so we cannot
recover the field's concrete type here -> emit NO type assertion (the value
flows as `any`).  [lab] is the value-field index (proof args erased).  On the
M2.7 surface sub-pattern reads surface as I1Vp1cn (typed); I1INSpcon is the
generic/untyped projection form kept for totality.
*)
|I1INSpcon(lab0, i1v1) =>
  (
  i1valgo1(filr, i1v1);
  strnfpr(filr, ".Args["); i0lab_int_go1(filr, lab0); strnfpr(filr, "]"))
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
(*
M2.6c MUTATION: assignment to an addressable lvalue + de-leftval (read).
//
  I1INSassgn(left, right) : Go statement `<lvalue-of-left> = <right>`.
                            The left is an lvalue i1val (I1Vlpft / I1Vlpbx /
                            a root I1Vtnm var); the right is the new value.
                            Emitted as a single Go assignment STATEMENT (it has
                            no value), so it always reaches i1insgo1 via an
                            I1LETnew0 (an effect let), never an I1LETnew1.
  I1INSflat(v)            : read an lvalue's CURRENT value -- in Go that is
                            simply the Go expression `<v>` (reading a var / a
                            field is the same expression).  So we emit `<v>`.
//
Go gives us REAL addressable lvalues: a flat tuple/record in a Go `var` is an
addressable value-struct (`p.F0 = v` mutates the local in place = ATS flat /
VALUE semantics -- a copy is unaffected); a boxed one is a `*struct` pointer
(`p.F0 = v` mutates through the pointer = ATS boxed / SHARED semantics, visible
through every alias).  Go's auto-deref makes the SAME `<root>.F<lab>` lvalue
syntax correct for both -- the value-vs-pointer choice (made at construction,
M2.6b) is what realizes the flat/boxed semantic difference.  No path-encoding
runtime (unlike the JS backend's XATSLPFT/lvget/lvset copy-on-write sim).
*)
|I1INSassgn(ilft, irgt) =>
  (
  i1valgo1(filr, ilft);
  strnfpr(filr, " = ");
  i1valgo1(filr, irgt))
|I1INSflat(iv1) =>
  (
  i1valgo1(filr, iv1))
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
[drop_pf_i0p]: drop the leading [npf] proof sub-patterns of a constructor
pattern (erased -- no runtime field).  [npf] = -1 (the "no proof prefix"
sentinel) or <= 0 drops nothing.  Mirrors the JS f0_dapp/f0_tup1 [f1_drop].
A standalone [fun] (no back-reference to the [i0pckgo1] group).
*)
fun
drop_pf_i0p
(npf: sint, i0ps: i0patlst): i0patlst =
(
if (npf <= 0) then i0ps else
(
case+ i0ps of
|list_nil() => i0ps
|list_cons(_, i0ps1) => drop_pf_i0p(npf-1, i0ps1))
)
//
(*
[i0pck_con_tag]: emit the TAG test `<casval>.Tag == <ctag>` for constructor
[dcon].  The Go analog of the JS backend's `XATS000_ctgeq(v, XATSCTAG(name,
ctag))` (which tests `v[0] == ctag`); here the tag is a separate field, so it is
`<casval>.Tag == <ctag>`.  A standalone [fun] defined BEFORE [i0pckgo1] (which
references it).
*)
fun
i0pck_con_tag
( filr: FILR
, casval: i1val
, dcon: d2con): void =
(
i1valgo1(filr, casval);
strnfpr(filr, ".Tag == ");
i0i00go1(filr, d2con_get_ctag(dcon)))
//
(*
i0pckgo1: emit a pattern as a Go BOOLEAN TEST against [casval].  Mirrors
js1emit's i0pckjs1:
  - I0Pany / I0Pvar          -> "true"  (always matches; bind happens later)
  - I0Pint / I0Pchr / I0Pbtf -> `<casval> == <literal>` (native scalar ==)
  - I0Pbang/flat/free(p)     -> recurse into p (transparent wrappers)
  - I0Pcon / I0Pdap1 / I0Pdapp -> DATACON tag test `<casval>.Tag == <ctag>`
    (M2.7), with non-trivial value sub-patterns recursively AND-tested against
    the projected `<casval>.Args[i]` (via [i0pck_args], mutual-recursion below).
Because a SCALAR [casval] is concretely typed, the == is a native Go comparison
-- the same semantics XATS000_inteq/chreq/btfeq give in the JS backend (the
oracle verifies byte-equality).  [i0pckgo1] and [i0pck_args] form a [fun]...[and]
MUTUAL-RECURSION group (a nested-constructor sub-pattern test re-roots [i0pckgo1]
on the projected sub-value).
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
// M2.7 DATACON patterns.  A constructor pattern tests the scrutinee's TAG and
// (for an applied con) recursively tests each non-trivial VALUE sub-pattern
// against the corresponding `<scrut>.Args[i]` projection -- mirroring the JS
// backend's f0_dapp (XATS000_ctgeq + f0_ipatlst).  See [i0pck_con] below.
//   I0Pcon(dcon)            : nullary con           -> `<scrut>.Tag == <ctag>`
//   I0Pdap1(I0Pcon)         : con with no sub-pats  -> `<scrut>.Tag == <ctag>`
//   I0Pdapp(I0Pcon, npf, ps): con with sub-patterns -> tag test && sub-tests
|I0Pcon(dcon) =>
  i0pck_con_tag(filr, casval, dcon)
|I0Pdap1(ip1) =>
  (
  case+ dcon_of_i0pat(ip1) of
  |optn_cons(dcon) => i0pck_con_tag(filr, casval, dcon)
  |optn_nil() =>
    (
    strnfpr(filr, "false /* UNHANDLED I0Pdap1 (non-con head) */");
    prerrsln("[go1emit] UNHANDLED I0Pdap1 with non-con head")))
|I0Pdapp(i0f0, npf1, i0ps) =>
  (
  case+ dcon_of_i0pat(i0f0) of
  |optn_cons(dcon) =>
    (
    // `<scrut>.Tag == <ctag>` then `&& <subtest_i>` for each non-trivial value
    // sub-pattern.  [npf1] proof sub-patterns are dropped (value index resets to
    // 0 post-drop), matching the IR's I1Vp1cn [pind].  Sub-pattern tests project
    // `<scrut>.Args[i]` (typed via the con's field type) and recurse.  [i0f0]
    // (the I0Pcon pattern) is passed so the sub-root I1Vp1cn carries it for the
    // field-type recovery (goty_of_p1cn).
    i0pck_con_tag(filr, casval, dcon);
    i0pck_args(filr, casval, i0f0, 0, drop_pf_i0p(npf1, i0ps)))
  |optn_nil() =>
    (
    strnfpr(filr, "false /* UNHANDLED I0Pdapp (non-con head) */");
    prerrsln("[go1emit] UNHANDLED I0Pdapp with non-con head")))
//
// any OTHER structural pattern (tuple/record pattern in a case -- the M2.6
// surface uses `val`-pattern destructuring, not case) -> deferred.
| _(*deferred*) =>
  (
  strnfpr(filr, "false /* UNHANDLED pat: non-datacon structural -> later */");
  prerrsln("[go1emit] UNHANDLED case pattern (non-datacon structural)"))
)//endof[i0pckgo1(filr,casval,ipat)]
//
(*
[i0pck_args]: recursively AND-in each VALUE sub-pattern's test.  A trivial
sub-pattern (var/wildcard -- [i0pat_allq]) matches unconditionally and is
SKIPPED (no `&& true` noise); a non-trivial one (a literal, or a NESTED
constructor) emits ` && (...test of scrut.Args[i].(T)...)`.  The projected
sub-root is an [I1Vp1cn(i0f0, casval, i0)] i1val -- the SAME node the front-end
inlines for a sub-pattern variable -- so re-rooting [i0pckgo1] on it makes a
literal sub-pattern test `scrut.Args[i].(T) == lit` and a nested constructor
sub-pattern test that asserts the field to a boxed XatsCon pointer and then tests
its .Tag (recursing through the boxed datatype).  [i0f0] is the constructor
pattern (carries the [d2con] for the field type); [i0] is the VALUE-field index
(proof sub-patterns already dropped).  This is the [and] continuation of
[i0pckgo1] above (one mutual-recursion group).
*)
and
i0pck_args
( filr: FILR
, casval: i1val
, i0f0: i0pat
, i0: sint
, i0ps: i0patlst): void =
(
case+ i0ps of
|list_nil() => ((*void*))
|list_cons(ip1, i0ps1) =>
  (
  if i0pat_allq(ip1)
  then i0pck_args(filr, casval, i0f0, i0+1, i0ps1)
  else
    let
      val loc0 = i1val_lctn$get(casval)
      val subroot = i1val_make_node(loc0, I1Vp1cn(i0f0, casval, i0))
      val () = strnfpr(filr, " && (")
      val () = i0pckgo1(filr, subroot, ip1)
      val () = strnfpr(filr, ")")
    in
      i0pck_args(filr, casval, i0f0, i0+1, i0ps1)
    end)
)//endof[i0pck_args(...)]
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
NOTE (M2.7): the M2.3 [i1gua_emit_lets]/[i1gualst_emit_lets] (which pre-emitted a
guard's lets ABOVE the switch and returned its result i1val) were REMOVED.  A
guard is now emitted INLINE as a short-circuited IIFE in the case condition (see
[emit_guard_iife]), so its lets -- and any datacon-field projections -- run only
when the clause's tag test already held.
*)
(*
[i1letlst_go1emit_inline]: emit a guard cmp's lets as `;`-separated Go statements
on ONE line (for the IIFE body).  Mirrors [i1let_go1emit]'s single-expression
rule (live tnm -> `goxtnm := <expr>; `, dead -> `_ = <expr>; `), but with no
indentation/newlines.  The guard surface is op-resolve timps + a comparison dapp
(all single-expression), so this stays a flat statement list.  Defined BEFORE
[emit_guard_iife] (which calls it).
*)
fun
i1letlst_go1emit_inline
( ilts: i1letlst
, scp: i1cmp
, env0: !envx2go): void =
let
  val filr = env0.filr()
in//let
  case+ ilts of
  |list_nil() => ((*void*))
  |list_cons(ilt1, ilts1) =>
    (
    (case+ ilt1 of
     |I1LETnew1(itnm, iins) =>
       (
       if i1tnm_used_in_cmp(itnm, scp)
       then (i1tnmgo1(filr, itnm); strnfpr(filr, " := "))
       else strnfpr(filr, "_ = ");
       i1insgo1(filr, scp, iins); strnfpr(filr, "; "))
     |I1LETnew0(iins) =>
       (i1insgo1(filr, scp, iins); strnfpr(filr, "; ")));
    i1letlst_go1emit_inline(ilts1, scp, env0))
end//let//endof[i1letlst_go1emit_inline(...)]
//
(*
[emit_guard_iife]: emit a guard (the head [i1gua] of a guarded clause) as an
INLINE Go IIFE `func() bool { <guard lets>; return <guard result> }()` -- so it
appears in the case condition after `&& ` and Go's short-circuit makes it run
ONLY when the tag test already held (datacon guard projections are then safe).
The IIFE body emits the guard cmp's lets then `return <result>`; the lets
reference the clause's pre-emitted scrutinee bind (captured lexically).  A
multi-guard clause uses its FIRST guard (reported; the rest are a follow-up).
*)
fun
emit_guard_iife
( env0: !envx2go
, iguas: i1gualst): void =
let
  val filr = env0.filr()
in//let
  case+ iguas of
  |list_nil() => strnfpr(filr, "true")
  |list_cons(ig1, igs1) =>
    let
      val () =
        (case+ igs1 of
         |list_nil() => ()
         |list_cons _ => prerrsln("[go1emit] NOTE: multi-guard clause -- using first guard"))
      val icmp =
        (case+ ig1.node() of
         |I1GUAexp(c) => c
         |I1GUAmat(c, _) => (prerrsln("[go1emit] NOTE: I1GUAmat guard (best-effort)"); c))
      val-I1CMPcons(ilts, ival) = icmp
    in
      // func() bool { <lets>; return <result> }()
      strnfpr(filr, "func() bool { ");
      i1letlst_go1emit_inline(ilts, icmp, env0);
      strnfpr(filr, "return "); i1valgo1(filr, ival);
      strnfpr(filr, " }()")
    end
end//let//endof[emit_guard_iife(env0,iguas)]
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
bare expression; AND -- crucially for DATACON guards (M2.7) -- the guard PROJECTS
fields (`scrut.Args[i]`) that exist ONLY for the matching constructor, so the
guard MUST NOT run for a non-matching scrutinee (else an out-of-range Args panic).
//
SOLUTION: emit the guard as an INLINE IIFE in the case condition:
    case <patcond> && func() bool { <guard lets>; return <guard result> }():
Go's `&&` SHORT-CIRCUITS, so the IIFE (hence the field projections) runs ONLY
when `<patcond>` (the tag test) already held -- safe.  The IIFE captures the
clause's whole-scrutinee bind temp lexically, so that bind is emitted ABOVE the
switch (iff the guard references it; see [i1bnd_bind_go1_guard]).  A failed guard
makes the case condition false -> Go falls through to the next clause (matching
the JS backend's retry-next-clause).
//
[i1clslst_emit_guards] does the pre-pass: it emits ONLY each guarded clause's
pre-switch scrutinee BIND (so the IIFE can capture it); the guard COMPUTATION
itself is emitted inline as the IIFE by [i1cls_go1emit_g] from the clause's own
guard cmp.  (The earlier M2.3 design pre-emitted the guard lets above the switch
and used a temp -- correct for a SCALAR guard on the scrutinee, but UNSOUND for a
datacon guard whose projections would then run unconditionally.)
*)
//
(*
[i1tnm_used_in_guards]: is the clause-bind temp [itnm] referenced anywhere in the
guard cmp list?  Wraps each guard's cmp in [i1tnm_used_in_cmp] (the liveness walk,
which descends into I1Vp1cn roots).  Used to decide whether to emit the pre-switch
bind for a guarded clause.  Defined BEFORE the guard-emit group (which calls it).
*)
fun
i1tnm_used_in_guards
( itnm: i1tnm
, iguas: i1gualst): bool =
(
case+ iguas of
|list_nil() => false
|list_cons(ig1, igs1) =>
  let
    val u1 =
    (
    case+ ig1.node() of
    |I1GUAexp(icmp) => i1tnm_used_in_cmp(itnm, icmp)
    |I1GUAmat(icmp, _) => i1tnm_used_in_cmp(itnm, icmp))
  in
    if u1 then true else i1tnm_used_in_guards(itnm, igs1)
  end
)//endof[i1tnm_used_in_guards(itnm,iguas)]
//
(*
[i1bnd_bind_go1_guard]: bind a guarded clause's whole-scrutinee temp [itnm] to
[casval] ABOVE the switch, iff the guard cmp(s) reference [itnm] (so a datacon
guard's I1Vp1cn projections -- rooted at [itnm] -- resolve).  Skipped when the
guard does not use the bind temp (Go errors on a declared-but-unused local).
*)
fun
i1bnd_bind_go1_guard
( env0: !envx2go
, casval: i1val
, ibnd: i1bnd
, iguas: i1gualst): void =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
  val-I1BNDcons(itnm, _, _) = ibnd
in//let
  if i1tnm_used_in_guards(itnm, iguas)
  then
  (
  nindfpr(filr, nind);
  i1tnmgo1(filr, itnm); strnfpr(filr, " := ");
  i1valgo1(filr, casval); fprintln(filr))
  else ((*unused -- skip*))
end//let//endof[i1bnd_bind_go1_guard(...)]
//
fun
i1cls_guard_emit
( casval: i1val
, icl0: i1cls
, env0: !envx2go): void =
(
case+ icl0.node() of
|I1CLSgpt(igpt) => i1gpt_guard_emit(casval, igpt, env0)
|I1CLScls(igpt, _) => i1gpt_guard_emit(casval, igpt, env0)
)
//
and
i1gpt_guard_emit
( casval: i1val
, igpt: i1gpt
, env0: !envx2go): void =
(
case+ igpt.node() of
|I1GPTpat(_) => ((*unguarded -- nothing to pre-emit*))
|I1GPTgua(ibnd, iguas) =>
  // M2.7: a datacon guard `rect(w,h) when w = h` reads `w`/`h` as I1Vp1cn
  // projections ROOTED at the clause's whole-scrutinee bind temp.  The guard
  // itself is emitted INLINE (as an IIFE in the case condition, see
  // [i1cls_go1emit_g]) so its projections short-circuit safely; but the IIFE
  // captures the bind temp LEXICALLY, so we emit that bind ABOVE the switch
  // here (iff the guard references it -- an unused bind is skipped).
  i1bnd_bind_go1_guard(env0, casval, ibnd, iguas)
)//endof[i1gpt_guard_emit(casval,igpt,env0)]
//
fun
i1clslst_emit_guards
( casval: i1val
, icls: i1clslst
, env0: !envx2go): void =
(
case+ icls of
|list_nil() => ((*void*))
|list_cons(ic1, ics1) =>
  (
  i1cls_guard_emit(casval, ic1, env0);
  i1clslst_emit_guards(casval, ics1, env0))
)//endof[i1clslst_emit_guards(...)]
//
(* ****** ****** *)
//
(*
i1cls_go1emit_g: the guard-aware clause emitter.  A guarded clause emits
`case <patcond> && <guard-IIFE>:` -- the pattern test [i0pckgo1] ("true" for
var/wildcard) AND, for a guarded clause, an inline `func() bool {...}()` IIFE so
the guard runs (and its datacon-field projections are reached) ONLY when the tag
test already held (Go `&&` short-circuit).  An unguarded clause emits just
`case <patcond>:`.
*)
fun
i1cls_go1emit_g
( retq: bool, live: bool, itnm: i1tnm
, casval: i1val, icl0: i1cls
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
    // the bind + (optional) guard come from I1GPTpat / I1GPTgua.
    val (ibnd, guaopt) =
    (
    case+ igpt.node() of
    |I1GPTpat(ibnd) => @(ibnd, optn_nil(): optn(i1gualst))
    |I1GPTgua(ibnd, iguas) => @(ibnd, optn_cons(iguas)))
    val-I1BNDcons(_, ipat, _) = ibnd
    //
    // `case <patcond>[ && <guard-IIFE>]:`
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "case ");
    i0pckgo1(filr, casval, ipat);
    (
    case+ guaopt of
    |optn_nil() => ()
    |optn_cons(iguas) =>
      (
      strnfpr(filr, " && "); emit_guard_iife(env0, iguas)));
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
, casval: i1val, icls: i1clslst
, params: i1tnmlst, bnds: i1bndlst, env0: !envx2go): void =
(
case+ icls of
|list_nil() => ((*void*))
|list_cons(ic1, ics1) =>
  (
  i1cls_go1emit_g(retq, live, itnm, casval, ic1, params, bnds, env0);
  i1clslst_go1emit_g(retq, live, itnm, casval, ics1, params, bnds, env0))
)//endof[i1clslst_go1emit_g(...)]
//
(*
The SATS-declared clause entries (i1cls_go1emit / i1clslst_go1emit) delegate to
the guard-aware variants -- each clause's guard (if any) is emitted inline as an
IIFE from its own [igpt], so no separate guard-result list is threaded.
*)
#implfun
i1cls_go1emit
(retq, live, itnm, casval, icl0, params, bnds, env0) =
  i1cls_go1emit_g(retq, live, itnm, casval, icl0, params, bnds, env0)
//
#implfun
i1clslst_go1emit
(retq, live, itnm, casval, icls, params, bnds, env0) =
  i1clslst_go1emit_g(retq, live, itnm, casval, icls, params, bnds, env0)
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
    // GUARD pre-pass: emit ONLY each guarded clause's pre-switch scrutinee BIND
    // (so the inline guard IIFE -- emitted in the case condition -- can capture
    // it lexically).  The guard COMPUTATION itself is emitted inline as a
    // short-circuited `&& func() bool {...}()` IIFE per clause (so a datacon
    // guard's field projections run only when its tag test held).  A failed
    // guard makes the case condition false -> Go falls through to the next
    // clause (matching the JS backend's retry-next-clause).
    val () = i1clslst_emit_guards(casval, icls, env0)
    //
    // expression-less switch == if-else chain with implicit break.
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "switch {"); fprintln(filr))
    //
    val () = i1clslst_go1emit_g(retq, live, itnm, casval, icls, params, bnds, env0)
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
  // M2.6c: a trailing (or any) I1LETnew0(I1INSrturn(ical, innercmp)) is the
  // canonical RETURN computation -- it appears as the LAST let of a function /
  // let-in BODY whose value is `return <innercmp result>`.  In the SINGLE-let
  // case [i1cmp_go1emit_ret] unwraps it directly, but a MULTI-let body (e.g. a
  // let-in `(p.0 := 10; p.0 + p.1)` -- a sequence whose lets PRECEDE the return)
  // reaches it HERE, where it must still emit in return mode (its own lets +
  // `return`/TCO continue), NOT via the single-expression [i1insgo1] (which has
  // no return context and marks rturn UNHANDLED).  Routing it through
  // [i1cmp_go1emit_ret] threads [params]/[bnds] so a tail self-call in this
  // position still becomes a loop continue.
  case+ iins of
  |I1INSrturn(ical, innercmp) =>
    i1cmp_go1emit_ret(innercmp, params, bnds, env0)
  | _(*else*) =>
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
  i1insgo1(filr, scp, iins); fprintln(filr))))
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
