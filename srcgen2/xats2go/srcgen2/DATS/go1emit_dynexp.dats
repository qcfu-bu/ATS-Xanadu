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
#staload // LOC =
"./../../../SATS/locinfo.sats"
#staload // FP0 =
"./../../../SATS/filpath.sats"
#staload // LAB =
"./../../../SATS/xlabel0.sats"
#staload // SYM =
"./../../../SATS/xsymbol.sats"
#staload // STMP =
"./../../../SATS/xstamp0.sats"
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
//
(*
GAP A1: the by-REFERENCE-parameter STAMP SET -- read here at the
read/write/call emit sites to deref (`*p`) / pass (`p`) a `*T` pointer param.
*)
#staload "./../SATS/go1emit_byref0.sats"
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
strnfpr(filr, "\n"))//endfun
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
let
fun
loop
( i1vs: i1valist
, i0: sint): void =
(
case+ i1vs of
|list_nil() => ()
|list_cons(i1v, i1vs) =>
 (
 if
 (i0 >= 1)
 then strnfpr(filr, ", ");
 i1valgo1(filr, i1v);
 loop(i1vs, i0+1)))
in
loop(i1vs, 0)
end//endof[i1valgo1_list(...)]
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
let
fun
loop
( i1vs: i1valist
, i0: sint): void =
(
case+ i1vs of
|list_nil() => ()
|list_cons(i1v, i1vs) =>
 (
 if (i0 >= 1) then strnfpr(filr, ", ");
 i1valgo1(filr, i1v);
 loop(i1vs, i0+1)))
in
loop(i1vs, 0)
end//endof[i1trcd_emit_litvals(filr,i1vs)]
//
fun
i1trcd_emit_rcdvals
( filr: FILR
, livs: l1i1vlst): void =
let
fun
loop
( livs: l1i1vlst
, i0: sint): void =
(
case+ livs of
|list_nil() => ()
|list_cons(lv0, livs) =>
let
  val-I1LAB(_, iv1) = lv0
in
  (if (i0 >= 1) then strnfpr(filr, ", "); i1valgo1(filr, iv1); loop(livs, i0+1))
end)
in
loop(livs, 0)
end//endof[i1trcd_emit_rcdvals(filr,livs)]
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
(*
[d2con_is_excptn]: is this constructor an EXCEPTION constructor (excptcon)?
The front-end assigns EVERY excptcon the sentinel ctag -1 (exceptions are an
OPEN/extensible sum), whereas a closed datatype's constructors get distinct
ctags 0,1,...  So a ctag < 0 IS the excptcon marker.  An excptcon's runtime
value carries its NAME (so two exception types are distinguished -- mirrors the
JS backend's XATSCTAG(name, ctag) comparing BOTH).
*)
fun
d2con_is_excptn
(dcon: d2con): bool = (d2con_get_ctag(dcon) < 0)
//
(*
[i1con_emit_name]: emit `, Name: "<conname>"` for an EXCEPTION constructor
(nothing for an ordinary datatype con, keeping its struct literal byte-identical
to M2.7).  [d2con_get_name] is a sym_t whose [prints] is its textual name (the
same the JS backend quotes).
*)
fun
i1con_emit_name
( filr: FILR
, dcon: d2con): void =
(
if d2con_is_excptn(dcon)
then
let
  val nm = d2con_get_name(dcon)
  #impltmp g_print$out<>() = filr
in
  strnfpr(filr, ", Name: ");
  prints('"'); prints(nm); prints('"')
end
else ((*ordinary datatype con -- no Name*))
)//endof[i1con_emit_name(filr,dcon)]
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
  // EXCEPTIONS: an excptcon also stores its NAME (so a try/with handler can
  // distinguish exception types that all share ctag -1).
  i1con_emit_name(filr, dcon);
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
strnfpr(filr, "xatsgo.Xats_as_con(");
i1valgo1(filr, iroot);
strnfpr(filr, ").Args["); i0i00go1(filr, idx); strnfpr(filr, "]");
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
// a POLYMORPHIC con pattern (e.g. prelude [list_cons]/[list_nil]) wraps the
// [I0Pcon] in a template-application-with-type-args node [I0Ptapq]; unwrap it
// transparently (the type args are runtime-erased -- they do not affect the
// tag test or the field projection).  Without this, every prelude-datatype
// case collapsed to `false /* UNHANDLED I0Pdapp (non-con head) */`.
|I0Ptapq(ip1, _) => dcon_of_i0pat(ip1)
| _(*else*) => optn_nil()
)//endof[dcon_of_i0pat(ipat)]
//
fun
drop_pf_i0ps_for_proj
(npf: sint, i0ps: i0patlst): i0patlst =
(
if (npf <= 0) then i0ps else
(
case+ i0ps of
|list_nil() => i0ps
|list_cons(_, i0ps1) => drop_pf_i0ps_for_proj(npf-1, i0ps1))
)
//
fun
list_nth_i0pat
(i0ps: i0patlst, n: sint): optn(i0pat) =
(
case+ i0ps of
|list_nil() => optn_nil()
|list_cons(i0p1, i0ps1) =>
  (if (n <= 0) then optn_cons(i0p1) else list_nth_i0pat(i0ps1, n-1))
)
//
fun
goty_of_ipat_value
(ipat: i0pat): strn =
(
case+ ipat.node() of
|I0Pvar(d2v) => gotype_of_styp(d2var_get_styp(d2v))
|I0Pint _ => "int"
|I0Pbtf _ => "bool"
|I0Pchr _ => "rune"
|I0Pflt _ => "float64"
|I0Pstr _ => "string"
|I0Pbang(ip1) => goty_of_ipat_value(ip1)
|I0Pflat(ip1) => goty_of_ipat_value(ip1)
|I0Pfree(ip1) => goty_of_ipat_value(ip1)
|I0Ptapq(ip1, _) => goty_of_ipat_value(ip1)
|I0Pcon _ => "*xatsgo.XatsCon"
|I0Pdap1 _ => "*xatsgo.XatsCon"
|I0Pdapp _ => "*xatsgo.XatsCon"
| _(*else*) => "any"
)
//
fun
goty_of_p1cn_subpat
(ipat: i0pat, pind: sint): strn =
(
case+ ipat.node() of
|I0Pdapp(_, npf1, i0ps) =>
  (
  case+ list_nth_i0pat(drop_pf_i0ps_for_proj(npf1, i0ps), pind) of
  |optn_nil() => "any"
  |optn_cons(ip1) => goty_of_ipat_value(ip1))
|I0Pbang(ip1) => goty_of_p1cn_subpat(ip1, pind)
|I0Pflat(ip1) => goty_of_p1cn_subpat(ip1, pind)
|I0Pfree(ip1) => goty_of_p1cn_subpat(ip1, pind)
|I0Ptapq(ip1, _) => goty_of_p1cn_subpat(ip1, pind)
| _(*else*) => "any"
)
//
(*
[goty_of_p1cn]: the Go field type for an [I1Vp1cn(i0pat, _, pind)].
When lowering can preserve the full applied parent pattern, recover the field
type from its [pind]-th value subpattern first (for example, the payload in
`optn_cons(dcls)` is typed from [dcls]'s [d2var] static type).  This is the
critical polymorphic-constructor case: the bare constructor type only says the
field has type `a`, but the subpattern still knows the instantiated type.  If
the carried pattern is only the constructor head, fall back to the constructor
static type.
*)
fun
goty_of_p1cn
(ipat: i0pat, pind: sint): strn =
let
  val gt0 = goty_of_p1cn_subpat(ipat, pind)
in
if (gt0 = "any") then
(
case+ dcon_of_i0pat(ipat) of
|optn_nil() => "any"
|optn_cons(dcon) => gotype_of_dcon_field(dcon, pind)
)
else gt0
end//endof[goty_of_p1cn(ipat,pind)]
//
(*
[tup_proj_go1emit]: a FLAT-tuple / record field projection `<root>.F<pind>`.
When the ROOT is an ERASED-`any` value -- a tuple stored as a `list`/datacon
field whose element type was the erased type variable (so the field projection
[I1Vp1cn] recovers "any") -- a direct `<root>.F<pind>` is invalid Go (an `any`
has no fields).  Project the field GENERICALLY by reflection
([xatsgo.Xats_tup_get]) instead.  A typed root keeps the direct field-name
projection (flat value struct or boxed pointer; Go auto-derefs the pointer).
This is the read-path twin of the [I1Vp1cn] arg-assertion: both bottom out at a
datacon-field projection whose element type is the erased `a`.
*)
fun
tup_proj_go1emit
( filr: FILR
, iroot: i1val
, pind: sint): void =
let
  val erasedq =
  (
  case+ iroot.node() of
  |I1Vp1cn(ipat0, _, pind0) => (goty_of_p1cn(ipat0, pind0) = "any")
  | _(*else*) => false)
in//let
  if erasedq
  then
    (
    strnfpr(filr, "xatsgo.Xats_tup_get(");
    i1valgo1(filr, iroot);
    strnfpr(filr, ", "); i0i00go1(filr, pind); strnfpr(filr, ")"))
  else
    (
    i1valgo1(filr, iroot);
    strnfpr(filr, "."); strnfpr(filr, gofield_of_label(LABint(pind))))
end//endof[tup_proj_go1emit(filr,iroot,pind)]
//
(*
[i1val_emitted_anyq]: does [i1valgo1] emit this value as a Go `any` (interface)?
TRUE for a temp recorded emitted-`any` (goemit_ty), an ERASED datacon-field
projection ([I1Vp1cn] whose field type is "any" -> `.Args[i]`), and a tuple field
off such an erased root (emitted via [tup_proj_go1emit]'s reflective `Xats_tup_get`
-> `any`).  Used by the ARG / value boundaries to decide a `.(T)` assertion: a
genuine `any` value passed where a CONCRETE Go type is expected needs the assert,
and keying on the EMITTED form means a concretely-emitted value is never
mis-asserted.
*)
fun
i1val_erased_p1cn_rootq
(iroot: i1val): bool =
(
case+ iroot.node() of
|I1Vp1cn(ipat0, _, pind0) => (goty_of_p1cn(ipat0, pind0) = "any")
| _(*else*) => false)
//
fun
i1val_emitted_anyq
(ival: i1val): bool =
(
case+ ival.node() of
|I1Vtnm(t) => (goemit_ty_get(i1tnm_stmp$get(t)) = "any")
|I1Vp1cn(ipat, _, pind) => (goty_of_p1cn(ipat, pind) = "any")
|I1Vp0rj(iroot, _) => i1val_erased_p1cn_rootq(iroot)
|I1Vp1rj(_, iroot, _) => i1val_erased_p1cn_rootq(iroot)
| _(*else*) => false)
//
(*
[i1valgo1_list_argtyped]: emit an ARGUMENT list, inserting a `.(T)` assertion on
each arg that is emitted-`any` but whose corresponding callee PARAM type [pty] is
CONCRETE.  [ptys] is the callee's Go param-type list (gotypes_of_funstyp of the
callee d2var's styp); when it is shorter / empty the extra args emit untyped (the
fallback that preserves the prior behavior for callees with no recoverable
signature).
*)
fun
i1valgo1_list_argtyped
( filr: FILR
, ivs: i1valist
, ptys: list(strn)): void =
let
  fun
  loop
  (ivs: i1valist, ptys: list(strn), first: bool): void =
  (
  case+ ivs of
  |list_nil() => ((*void*))
  |list_cons(iv1, ivs1) =>
    let
      val () = (if first then ((*void*)) else strnfpr(filr, ", "))
      val (pty, ptys1) =
      (
      case+ ptys of
      |list_cons(p1, ps1) => @(p1, ps1)
      |list_nil() => @("", list_nil<strn>()))
    in
      i1valgo1(filr, iv1);
      (if (strn_length(pty) = 0) then ((*void*)) else
       if (pty = "any") then ((*void*)) else
       if i1val_emitted_anyq(iv1)
       then (strnfpr(filr, ".("); strnfpr(filr, pty); strnfpr(filr, ")"))
       else ((*void*)));
      loop(ivs1, ptys1, false)
    end)
in//let
  loop(ivs, ptys, true)
end//endof[i1valgo1_list_argtyped(filr,ivs,ptys)]
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
(*
I1Vtnm: a temp reference.  GAP A1: if the temp is a by-REFERENCE PARAMETER
(a Go `*T` pointer -- in the byref set), a plain VALUE use of it must
DEREFERENCE: `*goxtnm<p>`.  (A read of a `&`-param surfaces wrapped in
I1INSflat, which forwards to this i1val, so the deref happens here; the
POINTER itself is needed only at I1Vaddr / call-arg / assignment-LHS sites,
which special-case the byref param and so never reach this deref path.)
A non-byref temp is its plain Go name.
*)
|I1Vtnm
( itnm ) =>
  (
  if byref_has(i1tnm_stmp$get(itnm))
  then (strnfpr(filr, "*"); i1tnmgo1(filr, itnm))
  else i1tnmgo1(filr, itnm))
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
M2.6c / GAP A1 ADDR: address-of a left-value root.
//
GAP A1 (by-reference args): `I1Vaddr(I1Vtnm(v))` is how a `&`-argument is
passed (the source `&cell` / the onward pass of a `&`-param).  Two cases by
whether [v] is itself a by-ref POINTER param:
  - [v] is a by-ref param (already a Go `*T` pointer): emit `goxtnm<v>` (the
    POINTER itself -- NO `&`, NO deref).  This is the onward pass of a `&`-
    param to a nested `&`-call (e.g. `auxlp(x, r)` inside `auxlp`'s body), and
    the value position must NOT deref it here (i1valgo1's I1Vtnm deref is
    bypassed precisely so the raw pointer flows).
  - [v] is a plain addressable Go `var` (a source `var x`): emit `&goxtnm<v>`
    (take its address -> a `*T` to pass by reference).  Go vars are
    addressable, so `&` yields the cell the callee mutates through.
For any OTHER inner expression (M2.6c lvalue paths -- a var is already
addressable in Go) we keep the identity behavior (emit the inner).
*)
|I1Vaddr(iv1) =>
  (
  case+ iv1.node() of
  |I1Vtnm(itnm) =>
    (
    if byref_has(i1tnm_stmp$get(itnm))
    then i1tnmgo1(filr, itnm)            // already a pointer -> pass as-is
    else (strnfpr(filr, "&"); i1tnmgo1(filr, itnm)))  // &<addressable var>
  | _(*else*) => i1valgo1(filr, iv1))
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
GAP A2 (tuple-PATTERN function params).  A tuple-pattern parameter
`fun loop@(x, r) = ...` binds the param's i1tnm to the WHOLE tuple (a Go
struct), and each destructured field use (`x`, `r`) is inlined by the
front-end as a TUPLE PROJECTION value node on the param temp -- NOT a fresh
binding (mirrors the JS backend's `XATSP0RJ`/`XATSP1RJ`).  We emit
`<root>.F<pind>` (the SAME field-name scheme [gofield_of_label] every
tuple/record construction + projection uses), so a flat-value-struct or
boxed-pointer param both project correctly (Go auto-derefs a pointer root).
  I1Vp0rj(root, pind)        : FLAT  tuple projection -> `<root>.F<pind>`
  I1Vp1rj(token, root, pind) : BOXED tuple projection -> `<root>.F<pind>`
*)
|I1Vp0rj(iroot, pind) =>
  tup_proj_go1emit(filr, iroot, pind)
|I1Vp1rj(_tok, iroot, pind) =>
  tup_proj_go1emit(filr, iroot, pind)
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
  strnfpr(filr, "xatsgo.Xats_as_con(");
  i1valgo1(filr, iroot);
  strnfpr(filr, ").Args["); i0lab_int_go1(filr, lab0); strnfpr(filr, "]"))
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
I1Vtop(sym): the "topmost"/omitted value `_` in value position (isTOP =
WCARD_symbl).  The JS backend emits the constant `XATSTOP0` (= undefined); the
Go analog is `xatsgo.XATSTOP0()` (returns nil/unit -- a placeholder the type
checker filled, only valid where ATS proved the value is never demanded).
*)
|I1Vtop(_sym) => strnfpr(filr, "xatsgo.XATSTOP0()")
//
(*
I1Vextnam(token, innerVal, g1nam): a `$extnam(..)` external-name reference.
The carried [innerVal] is the RESOLVED i1val for the external name (from
[envi0i1_exnm$search]); the [g1nam] is the FFI name spec.  The JS backend does
NOT special-case this in value position (it only appears inside a prelude
`$extnam` function impl, which the Go decl emitter skips -- prelude functions are
runtime-provided).  When it DOES reach value position we emit the inner resolved
value (the same name the impl would bind), which is the observable content.
*)
|I1Vextnam(_tk, ivin, _gnam) => i1valgo1(filr, ivin)
//
(*
I1Vp2rj(token, root, label): a labelled BOXED projection variant.  Like the
other p*rj projections (I1Vp0rj/I1Vp1rj), this reads `<root>.F<label>` (Go
auto-derefs a boxed *struct root).  NOT produced by the current trxi0i1 (no
constructor call exists -- it is defined in intrep1 but never built), so this
case is here for completeness/totality and the layout-correct shape.
*)
|I1Vp2rj(_tok, iroot, lab2) =>
  (
  i1valgo1(filr, iroot);
  strnfpr(filr, "."); strnfpr(filr, gofield_of_label(lab2)))
//
(*
I1Vaexp(i0exp): a FLAT expression value -- arises ONLY as the lvalue-path
fallback ([i0lft_trxi0i1]'s `_ => i1val_aexp`), i.e. for an inner expression the
lvalue machinery did not otherwise lower (e.g. a type-ascribed lvalue).  The JS
backend emits `XATSAEXP(<i0exp>)`.  Go has no generic i0exp emitter at the i1val
level, so this remains UNHANDLED (a documented gap: a flat-expr lvalue is not on
the value-emit surface).  Kept distinct from the generic fallthrough so the note
is specific.
*)
|I1Vaexp(_iexp) => unhandled_val(filr, "I1Vaexp(flat-expr lvalue)", ival)
//
(*
I1Venv(i1env): an environment-slot value (a captured-env record).  Produced
during closure capture ([envi0i1_i0ws$insert]), but the Go backend DIVERGES on
closures -- Go func literals capture lexically, so the env-slot threading is
bypassed entirely (see the I1Vfenv / M2.5 capture notes).  An I1Venv therefore
never reaches a Go value-emit site on the supported surface; mark UNHANDLED with
a specific note rather than emit a meaningless env handle.
*)
|I1Venv(_ienv) => unhandled_val(filr, "I1Venv(env-slot; Go captures lexically)", ival)
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
fun
tnm_bound_by_pconq
(stmp: stamp, ilts: i1letlst): bool =
(
case+ ilts of
|list_nil() => false
|list_cons(ilt1, ilts1) =>
  (
  case+ ilt1 of
  |I1LETnew1(itnm, iins) =>
    (
    if
    (stamp_cmp(stmp, i1tnm_stmp$get(itnm)) = 0)
    then
      (
      case+ iins of
      |I1INSpcon(_, _) => true
      |I1INSflat(iv1) =>
        (
        case+ iv1.node() of
        |I1Vlpcn(_, _) => true
        | _(*else*) => false)
      | _(*else*) => false)
    else tnm_bound_by_pconq(stmp, ilts1))
  |I1LETnew0(_) => tnm_bound_by_pconq(stmp, ilts1))
)
//
fun
i1val_pcon_tempq
(ival: i1val, scp: i1cmp): bool =
(
case+ ival.node() of
|I1Vtnm(itnm) =>
  let val-I1CMPcons(ilts, _) = scp in
    tnm_bound_by_pconq(i1tnm_stmp$get(itnm), ilts)
  end
| _(*else*) => false
)
//
(* ****** ****** *)
//
(*
SELECTIVE MONOMORPHIZED foritm/$work: a `strn_foritm(s)` call is recognized by
scope-walking the callee temp's binding [I1INStimp] for the resolved d2cst name
"strn_foritm" -- the same scope-walk pattern as [i1val_pcon_tempq] above.  When
matched, [I1INSdapp] emits a TYPED Go loop over the string that calls the
[XATS_foritm_work] closure (emitted from the in-scope `foritm$work` #impltmp by
go1emit_decl00), instead of the undefined `xatsgo.Xats_strn_foritm` runtime name.
This adopts js1emit's effect (iterate + call the work body) but in concrete typed
Go, scoped to this one template family so the conformance suite is untouched.
*)
fun
tnm_is_strn_foritm
(stmp: stamp, ilts: i1letlst): bool =
(
case+ ilts of
|list_nil() => false
|list_cons(ilt1, ilts1) =>
  (
  case+ ilt1 of
  |I1LETnew1(itnm, iins) =>
    (
    if
    (stamp_cmp(stmp, i1tnm_stmp$get(itnm)) = 0)
    then
      (
      case+ iins of
      |I1INStimp(_, timp) =>
        (symbl_get_name(d2cst_get_name(t1imp_dcst$get(timp))) = "strn_foritm")
      | _(*else*) => false)
    else tnm_is_strn_foritm(stmp, ilts1))
  |I1LETnew0(_) => tnm_is_strn_foritm(stmp, ilts1))
)
//
fun
callee_strn_foritm_q
(ival: i1val, scp: i1cmp): bool =
(
case+ ival.node() of
|I1Vtnm(itnm) =>
  let val-I1CMPcons(ilts, _) = scp in
    tnm_is_strn_foritm(i1tnm_stmp$get(itnm), ilts)
  end
| _(*else*) => false
)
//
(*
[foritm_loop_emit]: the typed Go loop for `strn_foritm(s)`.  Emitted inline as an
IIFE (so it is an expression usable as an ANF temp's RHS):
  func() any { XATS_n0 := strn_length(s); for i:=0; i<XATS_n0; i++ {
    XATS_foritm_work(strn_get_at(s,i).(int32)) }; return XATSNIL() }()
The char element is `int32` (strn_get_at returns it boxed as `any`); the closure
param is typed `rune` (== int32), so the assertion `.(int32)` feeds it directly.
*)
fun
foritm_loop_emit
(filr: FILR, i1vs: i1valist): void =
let
  val-list_cons(sarg, _) = i1vs
in
  strnfpr(filr, "func() any { XATS_n0 := xatsgo.Xats_strn_length(");
  i1valgo1(filr, sarg);
  strnfpr(filr, "); for XATS_i := 0; XATS_i < XATS_n0; XATS_i++ { XATS_foritm_work(xatsgo.Xats_strn_get_at(");
  i1valgo1(filr, sarg);
  strnfpr(filr, ", XATS_i).(int32)) }; return xatsgo.XATSNIL() }()")
end//endof[foritm_loop_emit(filr,i1vs)]
//
fun
i1valgo1_binop_arg
(filr: FILR, scp: i1cmp, ival: i1val, goty: strn): void =
(
  i1valgo1(filr, ival);
  if (goty = "") then ((*void*)) else
  (
  if (goty = "any") then ((*void*)) else
  (
  if i1val_pcon_tempq(ival, scp)
  then
    (
    strnfpr(filr, ".("); strnfpr(filr, goty); strnfpr(filr, ")"))
  else ((*void*))))
)
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
i1valgo1_varrhs
(filr: FILR, irgt: i1val): void =
(
case+ irgt.node() of
|I1Vtnm(rtnm) =>
  (
  case+ gotrcd_of_tnm(i1tnm_stmp$get(rtnm)) of
  |optn_cons(@(isFlat, _body)) =>
    (
    // A mutable aggregate var is stored as a pointer cell.  Assigning a flat
    // tuple/record value into that cell needs its address; boxed values are
    // already pointers and flow through unchanged.
    if isFlat then strnfpr(filr, "&") else ((*void*));
    i1valgo1(filr, irgt))
  |optn_nil() => i1valgo1(filr, irgt))
| _(*else*) => i1valgo1(filr, irgt)
)//endof[i1valgo1_varrhs(filr,irgt)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
M3 rung: [I1INStimp] may carry the already-resolved user [#impltmp] body in
its [t1imp].  When that payload is an [I1Dimplmnt0], emit it as an inline Go
function literal instead of falling back to a runtime d2cst name.  This keeps
the existing ANF shape:

    goxtnmF := func(...) ... { ... }
    goxtnmR := goxtnmF(args...)

and proves that intrep1 does carry enough information for at least this class
of polymorphic/user-template instantiation.
*)
fun
t1imp_paramlst_go1emit
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
      // go-arm general ARG boundary: record this param's EMITTED Go type so a
      // CALL passing it (an `any` param into a typed slot) can be asserted.
      val () = (if go_arm_getq() then goemit_ty_add(i1tnm_stmp$get(p1), goty))
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
end//endof[t1imp_paramlst_go1emit(filr,fjas,ptys)]
//
fun
t1imp_xats2js_runtimeq
(timp: t1imp): bool =
let
  val dcst = t1imp_dcst$get(timp)
  val name = symbl_get_name(d2cst_get_name(dcst))
in//let
  if
  (strn_length(name) >= 8)
  then
    (
    if name[0] != 'X' then false else
    if name[1] != 'A' then false else
    if name[2] != 'T' then false else
    if name[3] != 'S' then false else
    if name[4] != '2' then false else
    if name[5] != 'J' then false else
    if name[6] != 'S' then false else
    (name[7] = '_'))
  else false
end//endof[t1imp_xats2js_runtimeq(timp)]
//
(*
[t1imp_anyret_accessorq]: is this instance one of the GENERIC `any`-returning
runtime accessors -- [a0ref_get] (read a side-table ref) / [p2tr_get] (deref a
pointer) -- whose Go leaf (xatsgo.Xats_a0ref_get / _p2tr_get) returns `any`
because its result type is the erased type variable?  When such an accessor is
materialized as a function VALUE (`goxtnm := xatsgo.Xats_a0ref_get`) and later
APPLIED, the application result is `any`; recording the value temp's emitted
return type as "any" makes the existing RESULT-BOUNDARY assertion
(`tmp(args).(T)`) fire for a CONCRETE result temp -- the load-bearing coercion
for the side-table modules in the emitter's OWN (non-go-arm) self-emission.
This is a NAME match (the dynamic value is genuinely a T boxed in `any`, so
`.(T)` is always sound), distinct from the go-arm inst_retty population.
*)
fun
t1imp_anyret_accessorq
(timp: t1imp): bool =
let
  val dcst = t1imp_dcst$get(timp)
  val name = symbl_get_name(d2cst_get_name(dcst))
in//let
  if (name = "a0ref_get") then true else
  if (name = "p2tr_get") then true else false
end//endof[t1imp_anyret_accessorq(timp)]
//
fun
strn_contains_go1
(hay: strn, needle: strn): bool =
let
  val nhay = strn_length(hay)
  val nndl = strn_length(needle)
  //
  fun
  match_at
  (i0: sint, j0: sint): bool =
  (
  if
  (j0 >= nndl)
  then true
  else
    let
      val c1: cgtz = hay[i0+j0]
      val c2: cgtz = needle[j0]
    in
    (
    if
    (c1 = c2)
    then match_at(i0, j0+1) else false)
    end)
  //
  fun
  loop
  (i0: sint): bool =
  (
  if
  (nndl <= 0)
  then true
  else
  if
  (i0 + nndl > nhay)
  then false
  else
    (
    if match_at(i0, 0) then true else loop(i0+1)))
in//let
  loop(0)
end//endof[strn_contains_go1(hay,needle)]
//
fun
i1dcl_preludeq
(idcl: i1dcl): bool =
let
  val loc0 = idcl.lctn()
  val lsrc = loctn_get_lsrc(loc0)
in//let
  case+ lsrc of
  |LCSRCsome1(path) =>
    strn_contains_go1(path, "prelude/")
  |LCSRCfpath(fpx) =>
    strn_contains_go1(fpath_get_fnm1(fpx), "prelude/")
  |_(*else*) => false
end//endof[i1dcl_preludeq(idcl)]
//
fun
t1imp_func_literal_go1emit
( filr: FILR
, ostmp: stamp
, timp: t1imp
, env0: !envx2go): bool =
(
if
t1imp_xats2js_runtimeq(timp)
then false
else
case+ t1imp_i1dclq(timp) of
|optn_nil() => false
|optn_cons(idcl) =>
  // GO-ARM PIVOT: a prelude body is shortcut to xatsgo.Xats_* ONLY when NOT in
  // go-arm mode.  In go-arm mode we EMIT the prelude body so it reaches the
  // typed XATS2GO_* leaves of the linked CATS/GO .cats floor (the leaf, an
  // $extnam with no body, has optn_nil i1dclq -> falls to d2cstgo1's bare-name
  // emission).  Default-off keeps the JS-arm suite byte-identical.
  if
  (if i1dcl_preludeq(idcl) then (if go_arm_getq() then false else true) else false)
  then false
  else
  (
  case+ idcl.node() of
  |I1Dimplmnt0(_, _, _, _, fjas, icmp) =>
    let
      val bnds = binds_of_fjarglst(fjas)
      val argtys = gotypes_of_fjarglst(fjas)
      val retty = gotype_of_lam_ret(icmp, bnds)
      // RESULT BOUNDARY (go-arm): record this instance func's EMITTED return type
      // keyed by its bound temp, so an application whose result temp is concretely
      // typed can assert an `any`-returning forwarder (e.g. a0rf_get).
      val () = (if go_arm_getq() then inst_retty_add(ostmp, retty))
      // ARG BOUNDARY (go-arm): record this func temp's own emitted Go func type
      // so a CALL `tmp(arg)` can recover [tmp]'s concrete first param type.
      val () = (if go_arm_getq() then goemit_ty_add(ostmp, gofunctype_of_fjarglst(argtys, retty)))
      val () =
      (
      strnfpr(filr, "func(");
      t1imp_paramlst_go1emit(filr, fjas, argtys);
      strnfpr(filr, ") ");
      strnfpr(filr, retty);
      strnfpr(filr, " {\n"))
      val () = envx2go_incnind(env0, 1(*++*))
      val () = i1cmp_go1emit_ret(icmp, list_nil(), bnds, env0)
      val () = envx2go_decnind(env0, 1(*--*))
      val () =
      (
      nindfpr(filr, envx2go_nind$get(env0));
      strnfpr(filr, "}"))
    in
      true
    end
  | _(*not a direct impl body*) => false
  )
)//endof[t1imp_func_literal_go1emit(...)]
//
(* ****** ****** *)
//
(*
[t1imp_nullaryq]: is this template instance VALUE-LIKE (an I1Dimplmnt0 with no
value params)?  Such an instance is emitted by [t1imp_func_literal_go1emit] as
a 0-param Go thunk `func() T {..}`; the go-arm dispatch records its bound temp
(nullary_inst_add) so a later application with args becomes `tmp()(args)`.
*)
fun
t1imp_nullaryq
(timp: t1imp): bool =
(
case+ t1imp_i1dclq(timp) of
|optn_nil() => false
|optn_cons(idcl) =>
  (
  case+ idcl.node() of
  |I1Dimplmnt0(_, _, _, _, fjas, _) =>
    (case+ binds_of_fjarglst(fjas) of list_nil() => true | _ => false)
  | _(*else*) => false)
)//endof[t1imp_nullaryq(timp)]
//
(* ****** ****** *)
//
(*
[t1imp_hook_paramty]: the Go type of the FIRST param of a value-like instance's
RESULT function -- i.e. for a nullary instance whose body is `let f = lam(x:T)..
in f`, return T's Go type.  Used to assert an `any`-typed arg at the hook
application (`tmp()(arg.(T))`).  "" if the result is not a (let-bound) lambda.
*)
(*
[go_first_param]: parse the FIRST parameter Go-type out of a function-type
string like "func(bool) any" -> "bool", "func(int, string) any" -> "int",
"func(func(int) bool) any" -> "func(int) bool" (paren-depth tracked so a
NESTED func type's inner comma/paren does not terminate the scan).  Returns
"" when [s] is not a "func(...)..." type or has no parameters ("func() any").
*)
fun
go_first_param
(s: strn): strn =
let
  val n = strn_length(s)
  //
  fun
  char1(c: cgtz): strn = strn_make_list(list_cons(c, list_nil()))
  //
  // scan from just after the "func(" prefix, accumulating the first param's
  // chars; a top-level (depth 0) ',' or ')' ENDS the first param.
  fun
  scan(i0: sint, depth: sint): strn =
  (
  if (i0 >= n) then ""
  else
    let val c: cgtz = s[i0] in
    (
    if (c = ')')
    then (if (depth <= 0) then "" else strn_append(char1(c), scan(i0+1, depth-1)))
    else if (c = ',')
    then (if (depth <= 0) then "" else strn_append(char1(c), scan(i0+1, depth)))
    else if (c = '(')
    then strn_append(char1(c), scan(i0+1, depth+1))
    else strn_append(char1(c), scan(i0+1, depth)))
    end
  )//endof[scan]
in
  if (n < 5) then ""
  else
  if s[0] != 'f' then "" else
  if s[1] != 'u' then "" else
  if s[2] != 'n' then "" else
  if s[3] != 'c' then "" else
  if s[4] != '(' then "" else
  scan(5, 0)
end//endof[go_first_param(s)]
//
(*
[go_return_type]: parse the RESULT Go-type out of a function-type string --
"func(bool) any" -> "any", "func(int, int) int" -> "int", "func() float64" ->
"float64".  Skips past the matching ")" of the param list (paren-depth tracked)
and returns the remainder (one leading space trimmed).  "" when [s] is not a
"func(...)..." type.  Used at the RESULT BOUNDARY: an `any`-returning call bound
to a concretely-typed temp must be asserted.
*)
fun
go_return_type
(s: strn): strn =
let
  val n = strn_length(s)
  //
  fun
  char1(c: cgtz): strn = strn_make_list(list_cons(c, list_nil()))
  //
  // collect s[i0..n) verbatim (the return-type tail).
  fun
  rest(i0: sint): strn =
  (
  if (i0 >= n) then ""
  else strn_append(char1(s[i0]), rest(i0+1))
  )//endof[rest]
  //
  // index just PAST the param-list ")" (entered at depth 1 after "func(").
  fun
  findclose(i0: sint, depth: sint): sint =
  (
  if (i0 >= n) then n
  else
    let val c: cgtz = s[i0] in
    (
    if (c = '(') then findclose(i0+1, depth+1)
    else if (c = ')')
    then (if (depth <= 1) then (i0+1) else findclose(i0+1, depth-1))
    else findclose(i0+1, depth))
    end
  )//endof[findclose]
in
  if (n < 5) then ""
  else
  if s[0] != 'f' then "" else
  if s[1] != 'u' then "" else
  if s[2] != 'n' then "" else
  if s[3] != 'c' then "" else
  if s[4] != '(' then "" else
  let
    val j = findclose(5, 1)
    // trim one leading space between ")" and the return type.
    val k = (if (j < n) then (if (s[j] = ' ') then j+1 else j) else j)
  in
    rest(k)
  end
end//endof[go_return_type(s)]
//
(*
[go_is_nullary_thunk]: does [s] start with "func()" -- a NULLARY thunk type
(empty param list)?  A value-like template instance is emitted as such a thunk;
when one instance's body returns ANOTHER (g_print's nested hooks), the type is
`func() func() ...`, and the application must peel one `()` per nullary layer
before applying the real args.
*)
fun
go_is_nullary_thunk
(s: strn): bool =
let
  val n = strn_length(s)
in
  if (n < 6) then false
  else
  if s[0] != 'f' then false else
  if s[1] != 'u' then false else
  if s[2] != 'n' then false else
  if s[3] != 'c' then false else
  if s[4] != '(' then false else
  (s[5] = ')')
end//endof[go_is_nullary_thunk(s)]
//
(*
[go_peel_thunks(filr, s)]: while [s] is a nullary thunk `func() X`, EMIT one
`()` (invoking that layer) and recurse on its return type [X]; return the first
NON-nullary type (`func(P) R` or a non-func).  Used at a nullary-instance
application to peel every nested-thunk layer (g_print's `func() func() ...`)
before applying the real args.
*)
fun
go_peel_thunks
(filr: FILR, s: strn): strn =
(
if go_is_nullary_thunk(s)
then (strnfpr(filr, "()"); go_peel_thunks(filr, go_return_type(s)))
else s
)//endof[go_peel_thunks(filr,s)]
//
(*
[t1imp_hook_paramty]: the Go type of the FIRST param of a value-like instance's
RESULT function.  Computed from the SAME [gotype_of_lam_ret] string the emitter
prints for the thunk's result (e.g. "func(bool) any"), then [go_first_param]'d
-- so it is guaranteed consistent with the emitted `func(<pty>) ...` signature.
"" when the result is not a function type.
*)
fun
t1imp_hook_paramty
(timp: t1imp): strn =
(
case+ t1imp_i1dclq(timp) of
|optn_nil() => ""
|optn_cons(idcl) =>
  (
  case+ idcl.node() of
  |I1Dimplmnt0(_, _, _, _, fjas, icmp) =>
    let
      val bnds = binds_of_fjarglst(fjas)
      val retty = gotype_of_lam_ret(icmp, bnds)
    in
      go_first_param(retty)
    end
  | _(*else*) => "")
)//endof[t1imp_hook_paramty(timp)]
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
(_, timp) =>
let
val dcst = t1imp_dcst$get(timp)
in//let
(
// [strn_foritm] is handled at its I1INSdapp call site (a typed Go loop, see
// [foritm_loop_emit]); its timp-temp is dead, so emit a DEFINED placeholder
// instead of the undefined `xatsgo.Xats_strn_foritm` runtime name.  The
// op-aware liveness ([strn_foritm_callee_q], go1emit_styp0) drops this binding
// to `_ = xatsgo.XATSNIL`.
if (symbl_get_name(d2cst_get_name(dcst)) = "strn_foritm")
then strnfpr(filr, "xatsgo.XATSNIL")
else d2cstgo1(filr, dcst)) end
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
  val goty0 = gotype_of_ival(a0)
  val goty1 = gotype_of_ival(a1)
  val targ0 = (if (goty0 = "any") then goty1 else goty0)
  val targ1 = (if (goty1 = "any") then goty0 else goty1)
in
  strnfpr(filr, "(");
  i1valgo1_binop_arg(filr, scp, a0, targ0);
  strnfpr(filr, " "); strnfpr(filr, gop); strnfpr(filr, " ");
  i1valgo1_binop_arg(filr, scp, a1, targ1);
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
if callee_strn_foritm_q(i1f0, scp)
then foritm_loop_emit(filr, i1vs)
else
(
case+ i1f0.node() of
|I1Vfenv(d2f0, _envs) =>
  (
  d2vargo1(filr, d2f0);
  strnfpr(filr, "(");
  // ARG BOUNDARY: recover the callee's Go param types from its d2var styp and
  // assert each emitted-`any` arg into a CONCRETE param (`f(arg.(T))`).  Empty
  // param list (unrecoverable signature) -> untyped emission (prior behavior).
  (
  let val (ptys, _) = gotypes_of_funstyp(d2var_get_styp(d2f0)) in
    i1valgo1_list_argtyped(filr, i1vs, ptys)
  end);
  strnfpr(filr, ")"))
| _(*otherwise*) =>
  // go-arm higher-order: applying a value-like (nullary) instance thunk WITH
  // args -> `tmp()(args)` (invoke the thunk to get the function, then apply).
  // A 0-arg application is left as `tmp()`.  When the thunk's result-func param
  // is concretely typed (e.g. a `func(bool)` print hook) and the single arg is
  // an `any`-typed value (a generic instance param), assert it: `tmp()(arg.(T))`.
  (
  case+ i1f0.node() of
  |I1Vtnm(tnm) =>
    (
    case+ i1vs of
    |list_nil() =>
      // 0-arg application: the generic thunk-invocation form `tmp()`.
      (i1valgo1(filr, i1f0); strnfpr(filr, "()"))
    |list_cons(a1, ar1) =>
      if nullary_inst_has(i1tnm_stmp$get(tnm))
      then
        // nullary hook applied with args -> `tmp()...()(args)`.  The instance
        // is a thunk; its body may RETURN another nullary instance (g_print's
        // nested hooks), so peel one `()` per nullary-thunk layer (driven by the
        // recorded emitted return type) before applying.  [pty] is the FIRST
        // param of the final (non-thunk) hook -- assert a single `any` arg to it.
        let
          val restype = inst_retty_get(i1tnm_stmp$get(tnm))
          val () = i1valgo1(filr, i1f0)
          val () = strnfpr(filr, "()")           // invoke the instance's own thunk
          val finaltype = go_peel_thunks(filr, restype)  // peel nested thunk layers
          val pty = go_first_param(finaltype)
        in
          strnfpr(filr, "(");
          // assert a single `any`-typed arg to the hook's concrete param type.
          (
          case+ ar1 of
          |list_nil() =>
            (if (strn_length(pty) > 0)
             then
               (if not(pty = "any")
                then
                  (if (gotype_of_ival(a1) = "any")
                   then (i1valgo1(filr, a1); strnfpr(filr, ".("); strnfpr(filr, pty); strnfpr(filr, ")"))
                   else i1valgo1_list(filr, i1vs))
                else i1valgo1_list(filr, i1vs))
             else i1valgo1_list(filr, i1vs))
          | _(*many*) => i1valgo1_list(filr, i1vs));
          strnfpr(filr, ")")
        end
      else
        // generic call `tmp(args)`.  ARG BOUNDARY: a single arg EMITTED as `any`
        // (a generic-dispatch param, per the goemit_ty table) passed to a callee
        // whose recorded first param type is CONCRETE must be asserted
        // (`tmp(arg.(T))`) -- e.g. an `any` optn arg into a `*XatsCon` print
        // worker.  Keying arg-is-`any` on the EMITTED type avoids mis-asserting a
        // concretely-emitted value (which Go rejects as a non-interface assert).
        let
          val pty = go_first_param(goemit_ty_get(i1tnm_stmp$get(tnm)))
        in
          i1valgo1(filr, i1f0); strnfpr(filr, "(");
          (
          case+ i1vs of
          |list_cons(a1, list_nil()) =>
            (if (strn_length(pty) > 0)
             then
               (if not(pty = "any")
                then
                  (case+ a1.node() of
                   |I1Vtnm(atnm) =>
                     (if (goemit_ty_get(i1tnm_stmp$get(atnm)) = "any")
                      then (i1valgo1(filr, a1); strnfpr(filr, ".("); strnfpr(filr, pty); strnfpr(filr, ")"))
                      else i1valgo1_list(filr, i1vs))
                   // a POLYMORPHIC datacon-field projection (e.g. the head `x` of
                   // `cons(x, xs)` on a `list(sint)`) is emitted as a bare `.Args[i]`
                   // (`any`) because its field type is the erased `a`.  Passed to a
                   // concrete-param hook (an inlined template-method prim like
                   // exists$test : sint -> bool), it needs `<proj>.(T)`.  Only when
                   // the projection's own recovered field type IS "any" (else it
                   // already self-asserts -- a double assert would be invalid Go).
                   |I1Vp1cn(ipat, _, pind) =>
                     (if (goty_of_p1cn(ipat, pind) = "any")
                      then (i1valgo1(filr, a1); strnfpr(filr, ".("); strnfpr(filr, pty); strnfpr(filr, ")"))
                      else i1valgo1_list(filr, i1vs))
                   | _(*non-tnm arg*) => i1valgo1_list(filr, i1vs))
                else i1valgo1_list(filr, i1vs))
             else i1valgo1_list(filr, i1vs))
          | _(*0 or many args*) => i1valgo1_list(filr, i1vs));
          strnfpr(filr, ")")
        end
    )
  | _(*non-tnm callee*) =>
    (i1valgo1(filr, i1f0);
     strnfpr(filr, "("); i1valgo1_list(filr, i1vs); strnfpr(filr, ")"))
  )(*otherwise-arm*)
)(*else callee_strn_foritm_q*))(*else binop*)
end(*let val gop*)//let
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
  strnfpr(filr, "xatsgo.Xats_as_con(");
  i1valgo1(filr, i1v1);
  strnfpr(filr, ").Args["); i0lab_int_go1(filr, lab0); strnfpr(filr, "]"))
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
(*
GAP A1: an assignment whose LHS is `I1Vaddr(I1Vtnm(p))` where [p] is a
by-REFERENCE pointer param is a WRITE THROUGH THE POINTER: emit `*p = <rhs>`
(NOT `p = <rhs>`, which would overwrite the pointer).  The asymmetry vs the
call-arg site (where the SAME `I1Vaddr(I1Vtnm(p))` passes the bare pointer
`p`) mirrors the JS backend's `XATS000_assgn(XATSADDR(p), v)` (write the box)
vs passing `XATSADDR(p)` (pass the box).  Any other LHS keeps the plain
addressable-Go-lvalue assignment.
*)
|I1INSassgn(ilft, irgt) =>
  (
  case+ ilft.node() of
  |I1Vaddr(ivin) =>
    (
    case+ ivin.node() of
    // GAP A1: write THROUGH a by-ref pointer param: `*p = <rhs>`.
    |I1Vtnm(itnm) when byref_has(i1tnm_stmp$get(itnm)) =>
      (
      strnfpr(filr, "*"); i1tnmgo1(filr, itnm);
      strnfpr(filr, " = "); i1valgo1(filr, irgt))
    // M2.5/M2.6c: a direct mutation of an addressable Go `var` (a captured
    // local, or a `var x`): the LVALUE IS the var itself -- `goxtnm<v> = <rhs>`
    // (NOT `&goxtnm<v>`, which is not assignable).  We must emit the var NAME
    // here, NOT route through [i1valgo1] of the I1Vaddr (whose CALL-ARG rule
    // would prepend `&` -- correct for passing by reference, WRONG for an
    // assignment target).  This is the assignment-vs-call-arg asymmetry of
    // I1Vaddr (mirrors the JS backend's XATS000_assgn(XATSADDR(v), .) writing
    // the box vs passing XATSADDR(v)).
    |I1Vtnm(itnm) =>
      (
      i1tnmgo1(filr, itnm);
      strnfpr(filr, " = "); i1valgo1_varrhs(filr, irgt))
    // any other I1Vaddr inner (an lvalue PATH -- I1Vlpft/I1Vlpbx already
    // emit `<root>.F<lab>`, addressable in Go) -> emit the inner lvalue.
    | _(*else*) =>
      (
      i1valgo1(filr, ivin);
      strnfpr(filr, " = "); i1valgo1(filr, irgt)))
  // DP2TR deref-assign: `$eval(p) := x` -> Go `*p = x`.  The lvalue forwards to
  // the bare pointer temp [p]; [dp2tr_ptr_has] (populated at trxi0i1 [f0_dp2tr])
  // marks it as a `$eval` pointer, so we deref on the LHS (NOT overwrite the
  // pointer).  The deref READ already emits `*p` structurally (I1INSdp2tr).
  |I1Vtnm(itnm) when dp2tr_ptr_has(i1tnm_stmp$get(itnm)) =>
    (
    strnfpr(filr, "*"); i1tnmgo1(filr, itnm);
    strnfpr(filr, " = "); i1valgo1(filr, irgt))
  | _(*else*) =>
    (
    i1valgo1(filr, ilft);
    strnfpr(filr, " = "); i1valgo1(filr, irgt)))
|I1INSflat(iv1) =>
  (
  i1valgo1(filr, iv1))
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
LAZY FORCE / no-ops (single-expression instructions).
//
NOTE (reachability): NONE of these five are produced by the current trxi0i1 on
the supported surface -- the upstream intrep0 has no I0El0azy/I0El1azy
constructor (so `$lazy` lowers to an ERROR node, not a lazy ins), and the
dl0az/dl1az/fold/free producer funcs ([i1val_dl0az] etc.) are defined but never
called (no dispatch arm for I0Edl0az/I0Edl1az/I0Efold/I0Efree in
[i0exp_trxi0i1]).  These cases are therefore COMPILE-CORRECT-READY: they emit
real, runnable Go matching the JS runtime's observable semantics, so the day the
front-end lowers lazy/fold/free they are handled (no UNHANDLED).
//
  I1INSdl0az(v) : force a MEMOIZED cell -> Xats_dl0az(<v> asserted to the lazy
                  pointer type); the cell forces once + caches.
  I1INSdl1az(v) : call a call-by-name thunk -> Xats_dl1az(<v> asserted to a thunk).
  I1INSfold(v)  : open-con folding no-op -> just the value <v> (mirrors the JS
                  XATS000_fold whose only observable is yielding v's slot;
                  emitting <v> keeps the bound temp well-typed).
  I1INSfree(v)  : malloc-free no-op -> Xats_free(<v>) (GC makes it a no-op
                  returning nil, exactly as XATS000_free).
*)
|I1INSdl0az(iv1) =>
  (
  strnfpr(filr, "xatsgo.Xats_dl0az(");
  i1valgo1(filr, iv1);
  strnfpr(filr, ".(*xatsgo.XatsLazy))"))
|I1INSdl1az(iv1) =>
  (
  strnfpr(filr, "xatsgo.Xats_dl1az(");
  i1valgo1(filr, iv1);
  strnfpr(filr, ".(func() any))"))
|I1INSfold(iv1) =>
  (
  i1valgo1(filr, iv1))
|I1INSfree(iv1) =>
  (
  strnfpr(filr, "xatsgo.Xats_free(");
  i1valgo1(filr, iv1);
  strnfpr(filr, ")"))
//
(*
I1INSdp2tr(v): p2tr-DEREFERENCE `$eval(p)` -- READ through a pointer.  The JS
backend emits `XATS000_dp2tr(v)` (= XATS000_lvget(v), reading the box); Go has
REAL pointers, so this is `*<v>`.  [v] is the pointer i1val (a `$addr(x)` =
`&x`, or a by-ref `*T` param flowing onward), so a uniform `*<v>` derefs both.
Produced by the VALUE-path [f0_dp2tr_v] -> [i1val_dp2tr]; the prelude's gseq
counter (`$UN.p2tr_get(p0)`) is the first surface use.
*)
|I1INSdp2tr(iv1) =>
  (
  strnfpr(filr, "*"); i1valgo1(filr, iv1))
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
strnfpr(filr, "xatsgo.Xats_as_con(");
i1valgo1(filr, casval);
strnfpr(filr, ").Tag == ");
i0i00go1(filr, d2con_get_ctag(dcon));
// EXCEPTIONS: an excptcon's ctag is the shared sentinel -1, so the tag test
// alone is ambiguous between exception types -- AND in the NAME to disambiguate
// (mirrors the JS backend's XATSCTAG(name, ctag) comparing both).  Ordinary
// datatype cons (ctag >= 0) keep the pure `.Tag == <ctag>` test (their ctags are
// already distinct, so no Name field is set/compared).
(
if d2con_is_excptn(dcon)
then
let
  val nm = d2con_get_name(dcon)
  #impltmp g_print$out<>() = filr
in
  strnfpr(filr, " && xatsgo.Xats_as_con(");
  i1valgo1(filr, casval);
  strnfpr(filr, ").Name == ");
  prints('"'); prints(nm); prints('"')
end
else ((*ordinary datatype con -- tag suffices*))))
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
|I0Pstr(tstr) =>
  (
  i1valgo1(filr, casval); strnfpr(filr, " == ");
  i0strgo1(filr, tstr))
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
    // `<scrut>.Args[i]` and recurse.  The full parent pattern [ipat] is passed
    // so [goty_of_p1cn] can recover polymorphic field types from its subpattern.
    i0pck_con_tag(filr, casval, dcon);
    i0pck_args(filr, casval, ipat, 0, drop_pf_i0p(npf1, i0ps)))
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
sub-root is an [I1Vp1cn(ipat0, casval, i0)] i1val -- the SAME node the front-end
inlines for a sub-pattern variable -- so re-rooting [i0pckgo1] on it makes a
literal sub-pattern test `scrut.Args[i].(T) == lit` and a nested constructor
sub-pattern test that asserts the field to a boxed XatsCon pointer and then tests
its .Tag (recursing through the boxed datatype).  [ipat0] is the full parent
pattern when available; [i0] is the VALUE-field index (proof sub-patterns already
dropped).  This is the [and] continuation of [i0pckgo1] above (one
mutual-recursion group).
*)
and
i0pck_args
( filr: FILR
, casval: i1val
, ipat0: i0pat
, i0: sint
, i0ps: i0patlst): void =
(
case+ i0ps of
|list_nil() => ((*void*))
|list_cons(ip1, i0ps1) =>
  (
  if i0pat_allq(ip1)
  then i0pck_args(filr, casval, ipat0, i0+1, i0ps1)
  else
    let
      val loc0 = i1val_lctn$get(casval)
      val subroot = i1val_make_node(loc0, I1Vp1cn(ipat0, casval, i0))
      val () = strnfpr(filr, " && (")
      val () = i0pckgo1(filr, subroot, ip1)
      val () = strnfpr(filr, ")")
    in
      i0pck_args(filr, casval, ipat0, i0+1, i0ps1)
    end)
)//endof[i0pck_args(...)]
//
(* ****** ****** *)
//
(*
i1bnd_bind_go1: bind the pattern's temp [itnm] to [casval] before a clause
body runs, so the body's references to the bound variable resolve.  Mirrors
js1emit's `let jsxtnm<itnm> = <ival>` in f0_i1valgpt.  Emitted only when the
body actually USES the bind temp?  Older code skipped unused binds, but some
template-instantiated bodies project through the clause root in a way the local
liveness walk can miss.  So we always bind, and add `_ = <itnm>` when the walk
does not see a use; this keeps Go's unused-local rule happy without losing the
root needed by I1Vp1cn projections.
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
  val used = i1tnm_used_in_cmp(itnm, body)
in//let
  (
  nindfpr(filr, nind);
  i1tnmgo1(filr, itnm); strnfpr(filr, " := ");
  i1valgo1(filr, casval); strnfpr(filr, "\n");
  if used then ((*void*)) else
    (
    nindfpr(filr, nind);
    strnfpr(filr, "_ = "); i1tnmgo1(filr, itnm); strnfpr(filr, "\n")))
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
  i1valgo1(filr, casval); strnfpr(filr, "\n"))
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
    strnfpr(filr, ":"); strnfpr(filr, "\n"))
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
EXCEPTIONS (step 2/2): the try-IIFE result is a NAMED Go return [goxret] (so the
`defer`/`recover` handler can set it).  The body cmp + each handler clause must
therefore assign to the LITERAL identifier `goxret`, not to a `goxtnm<N>` temp.
These three helpers mirror [i1cmp_go1emit_tnm] / [i1cls_go1emit_g] /
[i1clslst_go1emit_g], but the result is written `goxret = <result>`.  Handlers are
plain value-position clauses (return mode + TCO loops do NOT apply inside a
recover handler -- a tail self-call would not be in scope here), so [params]/
[bnds] are not threaded and guards are still folded inline as `&&`-IIFEs (reusing
[i0pckgo1] / [emit_guard_iife] / [i1bnd_bind_go1] verbatim from the M2.7 case).
*)
fun
i1cmp_go1emit_goxret
( bodyCmp: i1cmp
, env0: !envx2go): void =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
  val-I1CMPcons(ilts, ival) = bodyCmp
  val () = i1letlst_go1emit(ilts, bodyCmp, env0)
in//let
  // assign the result to the named return UNLESS the cmp already terminated
  // (a fully-returning trailing if/case, or a trailing `$raise` -> panic):
  // then `goxret = <r>` would read an unassigned temp / be unreachable.
  if i1cmp_tail_returns(bodyCmp) then () else
  (
  nindfpr(filr, nind);
  strnfpr(filr, "goxret = ");
  i1valgo1(filr, ival); strnfpr(filr, "\n"))
end//let//endof[i1cmp_go1emit_goxret(bodyCmp,env0)]
//
fun
i1cls_go1emit_goxret
( casval: i1val, icl0: i1cls
, env0: !envx2go): void =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
in//let
case+ icl0.node() of
|I1CLSgpt(_) =>
  prerrsln("[go1emit] NOTE: I1CLSgpt (guard-only handler clause) skipped")
|I1CLScls(igpt, body) =>
  let
    val (ibnd, guaopt) =
    (
    case+ igpt.node() of
    |I1GPTpat(ibnd) => @(ibnd, optn_nil(): optn(i1gualst))
    |I1GPTgua(ibnd, iguas) => @(ibnd, optn_cons(iguas)))
    val-I1BNDcons(_, ipat, _) = ibnd
    // `case <patcond>[ && <guard-IIFE>]:`  (the M2.7 datacon tag test + binds)
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "case ");
    i0pckgo1(filr, casval, ipat);
    (
    case+ guaopt of
    |optn_nil() => ()
    |optn_cons(iguas) =>
      (strnfpr(filr, " && "); emit_guard_iife(env0, iguas)));
    strnfpr(filr, ":"); strnfpr(filr, "\n"))
    val () = envx2go_incnind(env0, 1)
    val () = i1bnd_bind_go1(env0, casval, ibnd, body)
    // the handler body runs in VALUE mode, assigning to the named return.
    val () = i1cmp_go1emit_goxret(body, env0)
    val () = envx2go_decnind(env0, 1)
  in
    ((*void*))
  end
end//let//endof[i1cls_go1emit_goxret(...)]
//
fun
i1clslst_go1emit_goxret
( casval: i1val, icls: i1clslst
, env0: !envx2go): void =
(
case+ icls of
|list_nil() => ((*void*))
|list_cons(ic1, ics1) =>
  (
  i1cls_go1emit_goxret(casval, ic1, env0);
  i1clslst_go1emit_goxret(casval, ics1, env0))
)//endof[i1clslst_go1emit_goxret(...)]
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
  nindfpr(filr, envx2go_nind$get(env0)); strnfpr(filr, "}"); strnfpr(filr, "\n")
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
    // RETURN-MODE GATE: a block-form in a NON-LAST let position (block_force_value)
    // must NOT return from the function -- emit it in VALUE mode so control reaches
    // the trailing lets (the gseq suffix-print bug).  Default-off elsewhere.
    val retq = (if block_force_value_get() then false else i1ins_fully_returnsq(iins))
    val live = i1tnm_used_in_cmp(itnm, scp)
    val nind = envx2go_nind$get(env0)
    //
    val () =
      if retq then () else
      (
      if live then
      let val gty = gotype_of_ift0type(iins) in
      (
      nindfpr(filr, nind);
      strnfpr(filr, "var "); i1tnmgo1(filr, itnm);
      strnfpr(filr, " "); strnfpr(filr, gty);
      strnfpr(filr, "\n");
      // EMITTED-TYPE: this result temp is declared `any` -> record it so a later
      // boundary (an assign/return into a CONCRETE target) asserts `.(T)`.
      goemit_ty_add(i1tnm_stmp$get(itnm), gty))
      end
      else ())
    //
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "if ");
    i1valgo1(filr, itst); strnfpr(filr, " {"); strnfpr(filr, "\n"))
    //
    val () = envx2go_incnind(env0, 1)
    val () = f0_branch(retq, live, itnm, othn, params, bnds, env0)
    val () = envx2go_decnind(env0, 1)
    //
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "} else {"); strnfpr(filr, "\n"))
    //
    val () = envx2go_incnind(env0, 1)
    val () = f0_branch(retq, live, itnm, oels, params, bnds, env0)
    val () = envx2go_decnind(env0, 1)
    //
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "}"); strnfpr(filr, "\n"))
  in
    ((*void*))
  end
//
(* ----- I1INScas0 : Go expression-less `switch` ----------------------- *)
|I1INScas0(_, casval, icls) =>
  let
    // RETURN-MODE GATE: a block-form in a NON-LAST let position (block_force_value)
    // must NOT return from the function -- emit it in VALUE mode so control reaches
    // the trailing lets (the gseq suffix-print bug).  Default-off elsewhere.
    val retq = (if block_force_value_get() then false else i1ins_fully_returnsq(iins))
    val live = i1tnm_used_in_cmp(itnm, scp)
    val nind = envx2go_nind$get(env0)
    //
    val () =
      if retq then () else
      (
      if live then
      let val gty = gotype_of_ift0type(iins) in
      (
      nindfpr(filr, nind);
      strnfpr(filr, "var "); i1tnmgo1(filr, itnm);
      strnfpr(filr, " "); strnfpr(filr, gty);
      strnfpr(filr, "\n");
      goemit_ty_add(i1tnm_stmp$get(itnm), gty))
      end
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
    nindfpr(filr, nind); strnfpr(filr, "switch {"); strnfpr(filr, "\n"))
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
    nindfpr(filr, nind); strnfpr(filr, "default:"); strnfpr(filr, "\n"))
    val () = envx2go_incnind(env0, 1)
    val () =
    (
    nindfpr(filr, envx2go_nind$get(env0));
    strnfpr(filr, "panic(\"xats2go: XATS000_cfail\")"); strnfpr(filr, "\n"))
    val () = envx2go_decnind(env0, 1)
    //
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "}"); strnfpr(filr, "\n"))
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
    // RETURN-MODE GATE: a block-form in a NON-LAST let position (block_force_value)
    // must NOT return from the function -- emit it in VALUE mode so control reaches
    // the trailing lets (the gseq suffix-print bug).  Default-off elsewhere.
    val retq = (if block_force_value_get() then false else i1ins_fully_returnsq(iins))
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
      let val gty = gotype_of_ift0type(iins) in
      (
      nindfpr(filr, nind);
      strnfpr(filr, "var "); i1tnmgo1(filr, itnm);
      strnfpr(filr, " "); strnfpr(filr, gty);
      strnfpr(filr, "\n");
      goemit_ty_add(i1tnm_stmp$get(itnm), gty))
      end
      else ())
    //
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "{"); strnfpr(filr, "\n"))
    val () = envx2go_incnind(env0, 1)
    //
    // emit the inner LOCAL declarations.  GAP-1: use the LOCAL decl walk so a
    // NESTED `fun` (in a `where`/`let`) is emitted as a Go LOCAL CLOSURE at its
    // declaration point (capturing surrounding locals + self-recursion) rather
    // than skipped/hoisted (the M2.2 top-level hoisting stays for top-level
    // funs, which never reach this let-block walk).
    val () = i1dclist_go1emit_local(dcls, env0)
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
    nindfpr(filr, nind); strnfpr(filr, "}"); strnfpr(filr, "\n"))
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
    strnfpr(filr, " {"); strnfpr(filr, "\n"))
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
    strnfpr(filr, " "); strnfpr(filr, ftype); strnfpr(filr, "\n"))
    // <fname> = func(<typed params>) <ret> {   (params typed from [argtys]
    // -- the SAME list as the `var` func type, so the signatures match).
    val () =
    (
    nindfpr(filr, nind);
    d2vargo1(filr, fvar); strnfpr(filr, " = func(");
    fjarglst_go1emit_typed_params(filr, fjas, argtys);
    strnfpr(filr, ") "); strnfpr(filr, retty);
    strnfpr(filr, " {"); strnfpr(filr, "\n"))
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
      d2vargo1(filr, fvar); strnfpr(filr, "\n"))
      else ()
  in
    ((*void*))
  end
//
(* ----- I1INSraise : Go `panic(<excval>)` ---------------------------- *)
(*
EXCEPTIONS (step 2/2).  `$raise e` lowers to I1INSraise(tk, excval) where
[excval] is the exception value (the I1Vtnm of an earlier datacon construction,
e.g. ErrmsgExn("boom") -> a `*xatsgo.XatsCon`).  We emit a bare Go
`panic(<excval>)` -- a TERMINATING statement -- regardless of value- vs
return-position: a panic binds NOTHING and nothing runs after it.  So we emit
NO `goxtnm<itnm> := ` prefix and NO `var` declaration (the bound temp [itnm] is
unreachable; [cmp_last_let_raises] suppresses the trailing result that would have
read it -- this is the M2.3 `default: panic(...)` discipline applied to `$raise`,
keeping `go vet` clean of "unreachable code"/"missing return").  Mirrors the JS
backend's `XATS000_raise(excval)` (js1emit_dynexp ~L1567), but Go uses `panic`.
*)
|I1INSraise(_, excval) =>
  let
    val nind = envx2go_nind$get(env0)
  in
  (
  nindfpr(filr, nind);
  strnfpr(filr, "panic("); i1valgo1(filr, excval); strnfpr(filr, ")");
  strnfpr(filr, "\n"))
  end
//
(* ----- I1INStry0 : IIFE + defer/recover + datacon handler switch ----- *)
(*
EXCEPTIONS (step 2/2).  `try BODY with HANDLERS` lowers to
I1INStry0(tk, bodyCmp, exnBinder, handlers) where [exnBinder] is the I1Vtnm the
handler clauses project the caught exception from, and [handlers] is the SAME
i1clslst structure I1INScas0 uses (so we REUSE the M2.7 datacon-case clause
emitter [i1clslst_go1emit_g] verbatim, with [exnBinder] as the scrutinee).
//
We emit an immediately-invoked Go func literal with a NAMED return + a
defer/recover (the Go idiom for try/catch -- JS uses try/catch, js1emit_dynexp
~L2701; the WALK is the same, the SHAPE differs):
    goxtnm<itnm> := func() (goxret <RETTYPE>) {        // (or `_ = func()...` if dead)
        defer func() {
            if goxrec := recover(); goxrec != nil {
                goxtnm<exnBinder> := goxrec.( ptr-to-xatsgo.XatsCon )   // caught exn
                switch {                                         // <- the M2.7 datacon case
                case goxtnm<exnBinder>.Tag == <ctag1>: <binds>; goxret = <handler1 body>
                ...
                default: panic(goxrec)                           // re-raise unhandled
                }
            }
        }()
        goxret = <bodyCmp in VALUE mode>                         // may panic
        return
    }()
[RETTYPE] is the try's result Go type ([gotype_of_ift0type]: the body result
joined with the handler results; "any" for a unit `val () = try ..`, where the
body/handler results are unit -> xatsgo.XATSNIL(), itself `any`-typed, so the
named return + both assignments agree).  The handler clauses run in VALUE mode
(each `goxret = <result>`); a non-exhaustive handler set re-raises via the
`default: panic(goxrec)` arm.
*)
|I1INStry0(_, bodyCmp, exnBinder, handlers) =>
  let
    val nind = envx2go_nind$get(env0)
    // [RETTYPE]: the try result type (body joined with handlers).  A unit try
    // (`val () = try ..`) yields "" / "any" (the body result is I1Vnil and the
    // handler results are unit `prints` calls -> any); coerce BOTH to a concrete
    // `any` so the named return is well-formed Go (`func() (goxret any)`) and the
    // body/handler `goxret = ..` assignments -- xatsgo.XATSNIL() (any) and the
    // any-returning handler call -- both type-check against it.  A typed try
    // keeps its recovered concrete type.
    val retty0 = gotype_of_ift0type(iins)
    val retty =
      (
      if (retty0 = "") then "any" else
      if (retty0 = "any") then "any" else retty0)
    val live = i1tnm_used_in_cmp(itnm, scp)
    //
    // goxtnm<itnm> := func() (goxret <RETTYPE>) {   (or `_ = func()...` if dead)
    val () =
    (
    nindfpr(filr, nind);
    if live
      then (i1tnmgo1(filr, itnm); strnfpr(filr, " := func() (goxret "))
      else strnfpr(filr, "_ = func() (goxret ");
    strnfpr(filr, retty); strnfpr(filr, ") {"); strnfpr(filr, "\n"))
    //
    val () = envx2go_incnind(env0, 1)
    val nind1 = envx2go_nind$get(env0)
    //
    // defer func() { if goxrec := recover(); goxrec != nil { ... } }()
    val () =
    (
    nindfpr(filr, nind1);
    strnfpr(filr, "defer func() {"); strnfpr(filr, "\n"))
    val () = envx2go_incnind(env0, 1)
    val nind2 = envx2go_nind$get(env0)
    val () =
    (
    nindfpr(filr, nind2);
    strnfpr(filr, "if goxrec := recover(); goxrec != nil {"); strnfpr(filr, "\n"))
    val () = envx2go_incnind(env0, 1)
    val nind3 = envx2go_nind$get(env0)
    //
    // goxtnm<exnBinder> := goxrec.(*xatsgo.XatsCon)   -- the caught exception.
    // The handler clauses project its fields via I1Vp1cn(<i0pat>, exnBinder, i)
    // (the SAME node a case clause uses), so binding [exnBinder] here makes those
    // projections resolve.  We bind ONLY when a handler references it (Go errors
    // on an unused local) -- but a handler ALWAYS reads the binder (it is the
    // scrutinee of every clause's tag test), so this is effectively always live.
    val () =
    (
    nindfpr(filr, nind3);
    i1valgo1(filr, exnBinder);
    strnfpr(filr, " := goxrec.(*xatsgo.XatsCon)"); strnfpr(filr, "\n"))
    //
    // the handler clauses, as a datacon switch over [exnBinder] -- REUSING the
    // M2.7 [i1clslst_go1emit_g] (tag tests + field binds + clause body), in VALUE
    // mode assigning to [goxret] (retq=false; the result temp is [goxret], routed
    // through the dedicated [goxret] assignment via [i1cmp_go1emit_goxret]).
    val () =
    (
    nindfpr(filr, nind3); strnfpr(filr, "switch {"); strnfpr(filr, "\n"))
    val () =
      i1clslst_go1emit_goxret(exnBinder, handlers, env0)
    // default: panic(goxrec) -- re-raise an exception no handler matched (a Go
    // TERMINATING statement, so a return-position handler switch stays exhaustive).
    val () =
    (
    nindfpr(filr, nind3); strnfpr(filr, "default:"); strnfpr(filr, "\n"))
    val () = envx2go_incnind(env0, 1)
    val () =
    (
    nindfpr(filr, envx2go_nind$get(env0));
    strnfpr(filr, "panic(goxrec)"); strnfpr(filr, "\n"))
    val () = envx2go_decnind(env0, 1)
    val () =
    (
    nindfpr(filr, nind3); strnfpr(filr, "}"); strnfpr(filr, "\n"))
    //
    val () = envx2go_decnind(env0, 1)  // close `if goxrec != nil`
    val () =
    (
    nindfpr(filr, nind2); strnfpr(filr, "}"); strnfpr(filr, "\n"))
    val () = envx2go_decnind(env0, 1)  // close `defer func() {`
    val () =
    (
    nindfpr(filr, nind1); strnfpr(filr, "}()"); strnfpr(filr, "\n"))
    //
    // goxret = <bodyCmp in VALUE mode> -- the normal path; may panic (caught by
    // the defer above).  We assign the body's result to [goxret] via the
    // dedicated emitter, then `return` (the named result) -- UNLESS the body
    // ALREADY terminates on every path (it unconditionally `$raise`s -> a Go
    // `panic(..)`, or returns via a fully-returning if/case): then the body's own
    // terminator is the last statement and a trailing `return` would be
    // UNREACHABLE (`go vet`: "unreachable code").  [i1cmp_tail_returns] (extended
    // for `$raise` via [cmp_last_let_raises]) decides this.
    val () = i1cmp_go1emit_goxret(bodyCmp, env0)
    val () =
      if i1cmp_tail_returns(bodyCmp) then () else
      (
      nindfpr(filr, nind1); strnfpr(filr, "return"); strnfpr(filr, "\n"))
    //
    val () = envx2go_decnind(env0, 1)  // close the IIFE body
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "}()"); strnfpr(filr, "\n"))
  in
    ((*void*))
  end
//
(* ----- I1INSl0azy / I1INSl1azy : lazy thunk constructors ------------- *)
(*
LAZY CONSTRUCTION (block form -- the thunk body is a CMP emitted as a Go func
literal, mirroring the JS backend's `XATS000_l0azy(function(){ ... })`).
//
  I1INSl0azy(dknd, thunkCmp) : a MEMOIZED cell ->
      goxtnm<itnm> := xatsgo.Xats_l0azy(func() any { <thunkCmp in return mode> })
  I1INSl1azy(dknd, thunkCmp, frees) : a CALL-BY-NAME thunk ->
      goxtnm<itnm> := xatsgo.Xats_l1azy(func() any { <thunkCmp in return mode> })
The [frees] of l1azy is the linear-cleanup list -- IGNORED (Go is GC'd, exactly
as the JS backend treats free as a no-op).  The thunk body is emitted in RETURN
mode (params=list_nil() so no TCO loop is generated inside the thunk), so it
`return`s the thunk's result value -- the SAME f0_i1cmpret shape the JS backend
uses.  A dead [itnm] binds to `_` (Go's unused-var rule).
//
NOTE (reachability): NOT produced on the current surface -- the upstream intrep0
has NO I0El0azy/I0El1azy constructor, so `$lazy` lowers to an error node and
[i1val_l0azy]/[i1val_l1azy] are dead code.  These cases are compile-correct-ready
(real Go matching the runtime), handled the day the front-end lowers lazy.
*)
|I1INSl0azy(_dknd, thunkCmp) =>
  let
    val nind = envx2go_nind$get(env0)
    val live = i1tnm_used_in_cmp(itnm, scp)
    val () =
    (
    nindfpr(filr, nind);
    if live
      then (i1tnmgo1(filr, itnm); strnfpr(filr, " := xatsgo.Xats_l0azy(func() any {"))
      else strnfpr(filr, "_ = xatsgo.Xats_l0azy(func() any {");
    strnfpr(filr, "\n"))
    val () = envx2go_incnind(env0, 1)
    val () = i1cmp_go1emit_ret(thunkCmp, list_nil(), bnds, env0)
    val () = envx2go_decnind(env0, 1)
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "})"); strnfpr(filr, "\n"))
  in
    ((*void*))
  end
|I1INSl1azy(_dknd, thunkCmp, _frees) =>
  let
    val nind = envx2go_nind$get(env0)
    val live = i1tnm_used_in_cmp(itnm, scp)
    val () =
    (
    nindfpr(filr, nind);
    if live
      then (i1tnmgo1(filr, itnm); strnfpr(filr, " := xatsgo.Xats_l1azy(func() any {"))
      else strnfpr(filr, "_ = xatsgo.Xats_l1azy(func() any {");
    strnfpr(filr, "\n"))
    val () = envx2go_incnind(env0, 1)
    val () = i1cmp_go1emit_ret(thunkCmp, list_nil(), bnds, env0)
    val () = envx2go_decnind(env0, 1)
    val () =
    (
    nindfpr(filr, nind); strnfpr(filr, "})"); strnfpr(filr, "\n"))
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
fun
i1tnm_same
(t1: i1tnm, t2: i1tnm): bool =
(
  stamp_cmp(i1tnm_stmp$get(t1), i1tnm_stmp$get(t2)) = 0)
//
fun
lvalue_field_on_tnm
(ilft: i1val): optn(@(i1tnm, label)) =
(
case+ ilft.node() of
|I1Vlpft(lab0, iroot) =>
  (
  case+ iroot.node() of
  |I1Vtnm(itnm) => optn_cons(@(itnm, lab0))
  | _(*else*) => optn_nil())
|I1Vlpbx(lab0, iroot) =>
  (
  case+ iroot.node() of
  |I1Vtnm(itnm) => optn_cons(@(itnm, lab0))
  | _(*else*) => optn_nil())
|I1Vaddr(iv1) => lvalue_field_on_tnm(iv1)
| _(*else*) => optn_nil()
)//endof[lvalue_field_on_tnm(ilft)]
//
fun
proj_binding
(ilt: i1let): optn(@(i1tnm, i1val, label)) =
(
case+ ilt of
|I1LETnew1(itnm, iins) =>
  (
  case+ iins of
  |I1INSpflt(lab0, iroot) => optn_cons(@(itnm, iroot, lab0))
  |I1INSproj(lab0, iroot) => optn_cons(@(itnm, iroot, lab0))
  | _(*else*) => optn_nil())
| _(*else*) => optn_nil()
)//endof[proj_binding(ilt)]
//
fun
try_emit_proj_lvalue_assign
( ilt1: i1let
, ilt2: i1let
, rest: i1letlst
, env0: !envx2go): bool =
(
case+ proj_binding(ilt1) of
|optn_nil() => false
|optn_cons(@(ptnm, proot, plab)) =>
  (
  case+ ilt2 of
  |I1LETnew0(I1INSassgn(ilft, irgt)) =>
    (
    case+ lvalue_field_on_tnm(ilft) of
    |optn_nil() => false
    |optn_cons(@(ltnm, llab)) =>
      (
      if
      i1tnm_same(ptnm, ltnm)
      then
        let
          val used_after =
            i1tnm_used_in_cmp(ptnm, I1CMPcons(rest, irgt))
        in
          if used_after
          then false
          else
            let
              val filr = env0.filr()
              val nind = envx2go_nind$get(env0)
              val () = nindfpr(filr, nind)
              val () = i1valgo1(filr, proot)
              val () = (strnfpr(filr, "."); strnfpr(filr, gofield_of_label(plab)))
              val () = (strnfpr(filr, "."); strnfpr(filr, gofield_of_label(llab)))
              val () = strnfpr(filr, " = ")
              val () = i1valgo1(filr, irgt)
              val () = strnfpr(filr, "\n")
            in
              true
            end
        end
      else false)
    )
  | _(*else*) => false)
)//endof[try_emit_proj_lvalue_assign(...)]
//
(*
A nested flat lvalue like `(xyz.2).0 := 20` can lower as two adjacent lets:
  tmp := xyz.F2      // flat field read would copy the struct
  tmp.F0 = 20        // mutating the copy is semantically wrong
When the projection temp is used only as the root of the immediately following
assignment, emit the addressable path directly (`xyz.F2.F0 = 20`) and skip the
copy temp.  Boxed fields still work through Go's automatic pointer dereference.
*)
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
|list_cons(ilt1, list_cons(ilt2, ilts2)) =>
  (
  if try_emit_proj_lvalue_assign(ilt1, ilt2, ilts2, env0)
  then i1letlst_go1emit_p(ilts2, scp, params, bnds, env0)
  else
    let
      // [ilt1] is NOT the last let (ilt2 follows), so a block-form if/case in it
      // must emit in VALUE mode -- never `return` from the function -- else the
      // trailing lets are dropped.  Restore the gate after (it may itself be set,
      // when this whole list is a non-last let's sub-block).  GATED on go-arm:
      // the JS suite + rungs 1-8 are byte-frozen, and this pattern (a non-last
      // fully-returning block-form) only arises in the go-arm gseq lowering.
      val saved = block_force_value_get()
    in
      (if go_arm_getq() then block_force_value_set(true) else ());
      i1let_go1emit_p(ilt1, scp, params, bnds, env0);
      block_force_value_set(saved);
      i1letlst_go1emit_p(list_cons(ilt2, ilts2), scp, params, bnds, env0)
    end
  )
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
    i1trcd_construct_go1emit(filr, itnm, iins); strnfpr(filr, "\n"))
    end
  else
  (
  case+ iins of
  |I1INStimp(_, timp) =>
    let
      val live = i1tnm_used_in_cmp(itnm, scp)
      // go-arm: a value-like (nullary) instance emits as a thunk bound to this
      // temp; record it so a later application with args becomes `tmp()(args)`.
      val () =
      (
      if (if go_arm_getq() then t1imp_nullaryq(timp) else false)
      then nullary_inst_add(i1tnm_stmp$get(itnm), t1imp_hook_paramty(timp)))
      // RESULT-BOUNDARY (emitter self-emission): a generic `any`-returning
      // accessor materialized as a value -> record its emitted return type "any"
      // so a later `tmp(args)` with a concrete result temp gets `tmp(args).(T)`.
      val () =
      (
      if t1imp_anyret_accessorq(timp)
      then inst_retty_add(i1tnm_stmp$get(itnm), "any"))
    in
    (
    nindfpr(filr, nind);
    if live
      then (i1tnmgo1(filr, itnm); strnfpr(filr, " := "))
      else strnfpr(filr, "_ = ");
    if
    t1imp_func_literal_go1emit(filr, i1tnm_stmp$get(itnm), timp, env0)
    then ((*void*))
    else i1insgo1(filr, scp, iins);
    strnfpr(filr, "\n"))
    end
  | _(*ordinary single-expression instruction*) =>
  let
    val live = i1tnm_used_in_cmp(itnm, scp)
  in
  (
  nindfpr(filr, nind);
  if live
    then (i1tnmgo1(filr, itnm); strnfpr(filr, " := "))
    else strnfpr(filr, "_ = ");
  case+ iins of
  |I1INSpcon(_, _) =>
    let
      // typed-intrep1 (S3): the projected value's Go type comes from the
      // temp's finalized gotyp (replaces the M2.6a side-table lookup).
      val goty = gotyp_emit(i1tnm_gotyp$get(itnm))
    in
      i1insgo1(filr, scp, iins);
      if (goty = "any") then ((*void*)) else
        (
        strnfpr(filr, ".("); strnfpr(filr, goty); strnfpr(filr, ")"))
    end
  | _(*otherwise*) =>
      (
      i1insgo1(filr, scp, iins);
      // RESULT BOUNDARY: a call whose Go form returns `any` (a prim/instance
      // whose leaf is `any`-typed -- e.g. XATS2GO_a0rf_get) bound to a temp with
      // a known CONCRETE gotyp must be asserted, else Go rejects the any->concrete
      // use downstream.  Assert ONLY when the callee's recovered return type is
      // provably "any" (so a natively-typed call / infix op is never mis-asserted,
      // which Go would reject as an assertion on a non-interface value).
      (case+ iins of
       |I1INSdapp(i1f0, _) =>
         let
           val goty = gotyp_emit(i1tnm_gotyp$get(itnm))
           // does the callee's emitted Go signature return `any`?  An instance-func
           // value temp (inst_retty) or a DIRECT call to a d2cst-less helper `fun`
           // whose signature defaults to `func(..) any` (funretty, keyed by the
           // callee d2var stamp, recorded at the function's definition).
           val retany =
           (
           case+ i1f0.node() of
           |I1Vtnm(ftnm) => (inst_retty_get(i1tnm_stmp$get(ftnm)) = "any")
           |I1Vfenv(fdvar, _) => (funretty_get(d2var_get_stmp(fdvar)) = "any")
           | _(*other callee*) => false)
         in
           if retany
           then
             // callee returns `any`.  A concretely-typed RESULT temp asserts HERE
             // (`f(args).(T)`).  An `any` result temp is RECORDED emitted-`any`
             // (goemit_ty) so a later CONCRETE boundary (e.g. `return <r>` where the
             // caller returns a concrete type) supplies the target T and asserts.
             (if not(goty = "any")
              then (strnfpr(filr, ".("); strnfpr(filr, goty); strnfpr(filr, ")"))
              else goemit_ty_add(i1tnm_stmp$get(itnm), "any"))
           else ()
         end
       | _(*non-dapp*) => ()));
  strnfpr(filr, "\n"))
  end)
  )
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
    if block_force_value_get()
    then
      // NON-LAST position (gseq `beg; iterate; end`): this is NOT the function
      // tail, so emit the inner cmp's lets (its EFFECTS) and DISCARD its result
      // (`_ = <result>`) instead of `return`-ing -- otherwise the trailing lets
      // (the suffix print) become dead code.
      let
        val-I1CMPcons(ilts, ival) = innercmp
        val () = i1letlst_go1emit_p(ilts, innercmp, params, bnds, env0)
      in
        nindfpr(filr, nind); strnfpr(filr, "_ = ");
        i1valgo1(filr, ival); strnfpr(filr, "\n")
      end
    else i1cmp_go1emit_ret(innercmp, params, bnds, env0)
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
    i1trcd_construct_go1emit(filr, tmp, iins); strnfpr(filr, "\n"))
    end
  else
  (
  nindfpr(filr, nind);
  i1insgo1(filr, scp, iins); strnfpr(filr, "\n"))))
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
  // unassigned temp / be unreachable).  When [block_force_value] is set
  // (go-arm non-tail context, e.g. a unit val-decl), the trailing block-form
  // was forced to VALUE mode -- it assigned its temp instead of returning --
  // so the discard MUST fire (else the temp is "declared and not used").
  if (if block_force_value_get() then false else i1cmp_tail_returns(icmp)) then () else
  (
  nindfpr(filr, nind);
  strnfpr(filr, "_ = ");
  i1valgo1(filr, ival); strnfpr(filr, "\n"))
end//let//endof[i1cmp_go1emit(icmp,env0)]
//
#implfun
i1cmp_go1emit_ret
(icmp, params, bnds, env0) =
let
  val filr = env0.filr()
  val nind = envx2go_nind$get(env0)
  // RETURN-MODE GATE reset: a function/branch BODY is a fresh tail context, so
  // clear [block_force_value] -- a non-last-let force from an ENCLOSING sequence
  // (e.g. a lambda nested in the gseq iteration) must NOT suppress this body's
  // own tail return.  Restored at the end.
  val saved_bfv = block_force_value_get()
  val () = block_force_value_set(false)
  val () =
  (
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
      nindfpr(filr, nind); strnfpr(filr, "continue"); strnfpr(filr, "\n"))
    | _(*not a tail self-call, or TCO disabled*) =>
      emit_ret_plain(innerCmp, params, bnds, env0))
  //
  | _(*otherwise: a multi-let body (e.g. lets + a trailing if/case)*) =>
    emit_ret_plain(icmp, params, bnds, env0)
  //
  )
  val () = block_force_value_set(saved_bfv)
in//let
  ((*void*))
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
    i1valgo1(filr, a1); strnfpr(filr, "\n");
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
  i1valgo1(filr, ival1);
  // RETURN BOUNDARY: the function returns a CONCRETE type ([cur_funretty]) but the
  // returned value is a temp recorded emitted-`any` (an any-returning call result
  // whose own gotyp was also `any`) -- assert `return <r>.(T)`.  Disabled when the
  // current retty is "" / "any" (e.g. inside a lambda whose retty is not pinned),
  // so a genuine `any` return is never mis-asserted.
  (
  let val cfr = cur_funretty_get() in
    if (cfr = "") then ((*void*)) else
    if (cfr = "any") then ((*void*)) else
    (case+ ival1.node() of
     |I1Vtnm(rtnm) =>
       (if (goemit_ty_get(i1tnm_stmp$get(rtnm)) = "any")
        then (strnfpr(filr, ".("); strnfpr(filr, cfr); strnfpr(filr, ")")) else ())
     | _(*non-tnm*) => ())
  end);
  strnfpr(filr, "\n"))
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
  // (then the branch emitted its own return; no assignment).  When
  // [block_force_value] is set (go-arm non-tail context), the trailing block-
  // form was forced to VALUE mode -- it assigned ITS OWN temp [ival] rather
  // than returning -- so the bridge assignment MUST fire (else [itnm] stays
  // unassigned and [ival]'s temp dangles "declared and not used").
  if (if block_force_value_get() then false else i1cmp_tail_returns(icmp)) then () else
  (
  nindfpr(filr, nind);
  i1tnmgo1(filr, itnm); strnfpr(filr, " = ");
  i1valgo1(filr, ival);
  // ASSIGN BOUNDARY: a value EMITTED as `any` (an inner if/case/let-in result
  // temp recorded "any" in goemit_ty) assigned to a result temp [itnm] DECLARED
  // with a CONCRETE Go type needs `<ival>.(T)`.  BOTH the target [T] and the
  // arg-is-`any` test read the EMITTED type table (goemit_ty -- the same type
  // the var was DECLARED with), so a concretely-emitted value is never
  // mis-asserted and the declared/asserted types always agree.
  (
  let val tgt = goemit_ty_get(i1tnm_stmp$get(itnm)) in
    if (tgt = "") then ((*void*)) else
    if (tgt = "any") then ((*void*)) else
    (case+ ival.node() of
     |I1Vtnm(vtnm) =>
       (if (goemit_ty_get(i1tnm_stmp$get(vtnm)) = "any")
        then (strnfpr(filr, ".("); strnfpr(filr, tgt); strnfpr(filr, ")")) else ())
     | _(*non-tnm*) => ())
  end);
  strnfpr(filr, "\n"))
end//let//endof[i1cmp_go1emit_tnm(itnm,icmp,env0)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_go1emit_dynexp.dats] *)
(***********************************************************************)
