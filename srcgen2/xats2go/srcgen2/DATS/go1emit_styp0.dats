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
go1emit_styp0 — milestone M2.0 — two scaffolds for the Go backend:

  (1) LIVENESS over intrep1.  [i1tnm_used_in_cmp(stmp, icmp)] answers
      "is the temp with stamp [stmp] referenced (as an [I1Vtnm]) anywhere
      inside [icmp]?".  The emitter uses this so each [I1LETnew1] binding
      is emitted cleanly: live tnm -> `goxtnm<N> := <ins>`; dead tnm ->
      `_ = <ins>` (assign-to-blank is legal Go for ANY expression, so the
      one rule kills both the dead decl AND the redundant suppressor M1
      emitted).  The walk descends into nested cmps / clauses / lets so it
      stays correct as M2.1+ lands if/case/let/lam.

  (2) `s2typ -> Go type` SCAFFOLD.  [gotype_of_styp]/[gotype_of_ival]
      return a Go type name for the scalar base cases recoverable today
      (int/bool/rune/float64/string) and `any` as the fallback.  M2.0 only
      stands the skeleton up; M2.1 wires it to concrete scalars.  See the
      BUILD-NOTES "type availability" section for what static type info
      actually survives into intrep1 (the answer gates Regime B).
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
#staload // BAS =
"./../../../SATS/xbasics.sats"
#staload // LAB =
"./../../../SATS/xlabel0.sats"
#staload // SYM =
"./../../../SATS/xsymbol.sats"
#staload // S2E =
"./../../../SATS/staexp2.sats"
#staload // S2T =
"./../../../SATS/statyp2.sats"
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
(*
M2.6a: the [i1tnm stamp -> i0typ] side-table, populated during lowering
([trxi0i1_dynexp.dats]) and consulted here (the emitter) to concretely type
computed temps that the local intrep1-level recovery cannot type.  See
go1emit_tytab0.sats.
*)
#staload "./../SATS/go1emit_tytab0.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#symload node with i1val_node$get
#symload node with i0typ_node$get
#symload node with s2typ_get_node
#symload name with s2cst_get_name
#symload name with d2cst_get_name
#symload dcst with t1imp_dcst$get
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== (1) LIVENESS ANALYSIS over intrep1                                 ==
=======================================================================
//
[i1tnm_used_in_cmp(stmp, icmp)]: does the temp with stamp [stmp] occur
as an [I1Vtnm] anywhere in [icmp] (its let-bindings' instructions, the
result value, and any nested cmps/clauses)?  The walk is mutually
recursive across ins / val / cmp / let / cls / gpt / gua.
//
A binding [I1LETnew1(tnm, ins)] is "live" iff [i1tnm_used_in_cmp] holds
for [tnm]'s stamp on the *enclosing* cmp.  Because intrep1 is ANF/SSA
(bindings only flow FORWARD), querying the whole cmp is a sound, simple
over-approximation: a binding can only ever be referenced AFTER its own
let, so a hit anywhere in the cmp means a real downstream use.
*)
//
(* ****** ****** *)
//
fun
stmp_eq
(s1: stamp, s2: stamp): bool =
(
  stamp_cmp(s1, s2) = 0)
//
(*
[lor]: strict logical-or.  The [used_in_*] walkers are PURE and structurally
decreasing, so strict (non-short-circuit) evaluation is correct; using a
named [lor] also sidesteps the dialect's parse trouble with bare nested
`if .. then .. else if ..` chains.
*)
fun
lor
(b1: bool, b2: bool): bool =
(
  if b1 then true else b2)
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== PRIMOP RECOGNITION  (milestone M2.1)                              ==
=======================================================================
//
Arithmetic / comparison ops do NOT surface as [I1INSopr] in this
pipeline.  They lower (verified via the IR dump) as:
    I1LETnew1(opT, I1INStimp(_, timp))    // resolve e.g. sint_add$sint
    I1LETnew1(rT,  I1INSdapp(I1Vtnm(opT), [a, b]))  // apply it
i.e. the operator is a RESOLVED prelude d2cst whose NAME identifies the
op (sint_add$sint, sint_lt$sint, dflt_add$dflt, ...).  When BOTH operands
are concretely-typed scalars, we emit the NATIVE Go infix operator
`(a OP b)` -- the Regime-B payoff -- instead of a boxed runtime call.

[goop_of_name] maps a d2cst NAME to its native Go binary operator, or
""(empty) when the op is not native-able (then we keep the runtime call
fallback).  The set below is exactly what M2.1's scalar tests exercise;
M2.2+ extends it.  Note: ALL these ops also have a runtime fallback
(xatsgo.Xats_<name>), so first-class / higher-order use stays correct.
*)
fun
goop_of_name
(nm: strn): strn =
(
case+ nm of
// --- integer (sint) arithmetic ---
| "sint_add$sint" => "+"
| "sint_sub$sint" => "-"
| "sint_mul$sint" => "*"
| "sint_div$sint" => "/"   // Go int / truncates toward 0 == JS Math.trunc
| "sint_mod$sint" => "%"   // Go int % == JS % (remainder, sign of dividend)
// --- integer (sint) comparison ---
| "sint_lt$sint"  => "<"
| "sint_gt$sint"  => ">"
| "sint_lte$sint" => "<="
| "sint_gte$sint" => ">="
| "sint_eq$sint"  => "=="
| "sint_neq$sint" => "!="
// --- float (dflt) arithmetic ---
| "dflt_add$dflt" => "+"
| "dflt_sub$dflt" => "-"
| "dflt_mul$dflt" => "*"
| "dflt_div$dflt" => "/"
// --- float (dflt) comparison ---
| "dflt_lt$dflt"  => "<"
| "dflt_gt$dflt"  => ">"
| "dflt_lte$dflt" => "<="
| "dflt_gte$dflt" => ">="
| "dflt_eq$dflt"  => "=="
| "dflt_neq$dflt" => "!="
// --- char comparison (rune is an int32 in Go); names have NO $ suffix ---
| "char_lt"  => "<"
| "char_gt"  => ">"
| "char_lte" => "<="
| "char_gte" => ">="
| "char_eq"  => "=="
| "char_neq" => "!="
// --- bool comparison (names have NO $ suffix) ---
| "bool_eq"  => "=="
| "bool_neq" => "!="
//
| _(*else*) => ""
)//endof[goop_of_name(nm)]
//
(* ****** ****** *)
//
(*
[goop_of_timp]: a resolved template instance -> its native Go operator
(""(empty) if not a native-able op).  The op is identified purely by the
d2cst NAME, which is robust to monomorphization stamps.
*)
fun
goop_of_timp
(timp: t1imp): strn =
(
  goop_of_name(symbl_get_name(timp.dcst().name())))
//
(*
[goop_of_ins]: an I1INStimp instruction -> its native Go operator
(""(empty) otherwise; non-timp ins are never native ops).
*)
fun
goop_of_ins
(iins: i1ins): strn =
(
case+ iins of
|I1INStimp(_, timp) => goop_of_timp(timp)
| _(*else*) => ""
)//endof[goop_of_ins(iins)]
//
(* ****** ****** *)
//
(*
[binop_of_tnm_in_lets]: search a let-list for [I1LETnew1(tnm, ins)] whose
[tnm] has the given stamp and whose [ins] is a native-able binary op;
return the Go operator (""(empty) if not found / not native).  Because the
op-temp's let always precedes its dapp use in ANF, scanning the enclosing
cmp's flat let-list finds it.
*)
fun
binop_of_tnm_in_lets
(stmp: stamp, ilts: i1letlst): strn =
(
case+ ilts of
|list_nil() => ""
|list_cons(ilt1, ilts1) =>
  (
  case+ ilt1 of
  |I1LETnew1(itnm, iins) =>
    (
    if
    stmp_eq(stmp, i1tnm_stmp$get(itnm))
    then goop_of_ins(iins)
    else binop_of_tnm_in_lets(stmp, ilts1))
  |I1LETnew0(_) =>
    binop_of_tnm_in_lets(stmp, ilts1))
)//endof[binop_of_tnm_in_lets(stmp,ilts)]
//
(*
[binop_of_callee]: the callee of an I1INSdapp -> its native Go operator
within scope [scp] (""(empty) if the callee is not a native-op temp).
*)
fun
binop_of_callee
(callee: i1val, scp: i1cmp): strn =
(
case+ callee.node() of
|I1Vtnm(itnm) =>
  let
    val-I1CMPcons(ilts, _) = scp
  in
    binop_of_tnm_in_lets(i1tnm_stmp$get(itnm), ilts)
  end
| _(*else*) => ""
)//endof[binop_of_callee(callee,scp)]
//
(*
[is_native_binop_dapp]: does this I1INSdapp inline to a native Go binary
operator?  True iff the callee resolves to a native op AND there are
exactly two arguments.  (Used both by the emitter -- to emit `(a OP b)`
-- and by the liveness walk -- so an inlined op-temp is NOT counted as a
use of its callee, which lets its binding drop to `_ = ...`.)
*)
fun
is_native_binop_dapp
(callee: i1val, args: i1valist, scp: i1cmp): bool =
let
  val gop = binop_of_callee(callee, scp)
in
  if (strn_length(gop) = 0) then false else
  (
  case+ args of
  |list_cons(_, list_cons(_, list_nil())) => true
  | _(*else*) => false)
end//endof[is_native_binop_dapp(callee,args,scp)]
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
used_in_val
(stmp: stamp, scp: i1cmp, ival: i1val): bool =
(
case+
ival.node() of
//
|I1Vtnm(itnm) =>
  stmp_eq(stmp, i1tnm_stmp$get(itnm))
//
|I1Vaddr(iv1) => used_in_val(stmp, scp, iv1)
//
|I1Vfenv(_, ivs) => used_in_vals(stmp, scp, ivs)
//
|I1Vp0rj(iv1, _) => used_in_val(stmp, scp, iv1)
|I1Vp1cn(_, iv1, _) => used_in_val(stmp, scp, iv1)
|I1Vp1rj(_, iv1, _) => used_in_val(stmp, scp, iv1)
|I1Vp2rj(_, iv1, _) => used_in_val(stmp, scp, iv1)
//
|I1Vlpft(_, iv1) => used_in_val(stmp, scp, iv1)
|I1Vlpbx(_, iv1) => used_in_val(stmp, scp, iv1)
|I1Vlpcn(_, iv1) => used_in_val(stmp, scp, iv1)
//
|I1Vextnam(_, iv1, _) => used_in_val(stmp, scp, iv1)
//
| _(*otherwise: leaves carry no tnm*) => false
)
//
and
used_in_vals
(stmp: stamp, scp: i1cmp, ivs: i1valist): bool =
(
case+ ivs of
|list_nil() => false
|list_cons(iv1, ivs1) =>
  lor(used_in_val(stmp, scp, iv1), used_in_vals(stmp, scp, ivs1))
)
//
(* ****** ****** *)
//
and
used_in_l1i1vs
(stmp: stamp, scp: i1cmp, lvs: l1i1vlst): bool =
(
case+ lvs of
|list_nil() => false
|list_cons(lv1, lvs1) =>
  let
    val-I1LAB(_, iv1) = lv1
  in
    lor(used_in_val(stmp, scp, iv1), used_in_l1i1vs(stmp, scp, lvs1))
  end
)
//
(* ****** ****** *)
//
and
used_in_ins
(stmp: stamp, scp: i1cmp, iins: i1ins): bool =
(
case+ iins of
//
|I1INSopr(_, ivs) => used_in_vals(stmp, scp, ivs)
//
(*
I1INSdapp: a function call.  KEY M2.1 LIVENESS RULE: when this dapp
inlines to a NATIVE Go binary operator (callee resolves to an op + 2
args, see [is_native_binop_dapp]), the emitted Go is `(a OP b)` and does
NOT reference the callee temp.  So we must NOT count the callee here --
otherwise the op-temp's binding would be emitted live (`opT := ...`) yet
go unused in Go (a "declared and not used" error).  Skipping the callee
lets the op-temp drop to `_ = xatsgo.Xats_<name>` (legal, and the runtime
fn exists as the fallback).  The two arg vals ARE still counted.
*)
|I1INSdapp(iv0, ivs) =>
  (
  if is_native_binop_dapp(iv0, ivs, scp)
  then used_in_vals(stmp, scp, ivs)
  else lor(used_in_val(stmp, scp, iv0), used_in_vals(stmp, scp, ivs)))
//
|I1INStimp(_, _) => false
//
|I1INSpcon(_, iv1) => used_in_val(stmp, scp, iv1)
|I1INSpflt(_, iv1) => used_in_val(stmp, scp, iv1)
|I1INSproj(_, iv1) => used_in_val(stmp, scp, iv1)
//
|I1INSlet0(_, icmp) => used_in_cmp(stmp, icmp)
//
|I1INSift0(iv0, ocmp1, ocmp2) =>
  lor(used_in_val(stmp, scp, iv0),
      lor(used_in_cmpopt(stmp, ocmp1), used_in_cmpopt(stmp, ocmp2)))
//
|I1INScas0(_, iv0, icls) =>
  lor(used_in_val(stmp, scp, iv0), used_in_clss(stmp, icls))
//
|I1INStup0(ivs) => used_in_vals(stmp, scp, ivs)
|I1INStup1(_, ivs) => used_in_vals(stmp, scp, ivs)
|I1INSrcd2(_, lvs) => used_in_l1i1vs(stmp, scp, lvs)
//
|I1INSlam0(_, _, icmp) => used_in_cmp(stmp, icmp)
|I1INSfix0(_, _, _, icmp) => used_in_cmp(stmp, icmp)
//
|I1INStry0(_, icmp, iv1, icls) =>
  lor(used_in_cmp(stmp, icmp),
      lor(used_in_val(stmp, scp, iv1), used_in_clss(stmp, icls)))
//
|I1INSflat(iv1) => used_in_val(stmp, scp, iv1)
|I1INSfold(iv1) => used_in_val(stmp, scp, iv1)
|I1INSfree(iv1) => used_in_val(stmp, scp, iv1)
//
|I1INSrturn(_, icmp) => used_in_cmp(stmp, icmp)
//
|I1INSdp2tr(iv1) => used_in_val(stmp, scp, iv1)
//
|I1INSdl0az(iv1) => used_in_val(stmp, scp, iv1)
|I1INSdl1az(iv1) => used_in_val(stmp, scp, iv1)
//
|I1INSl0azy(_, icmp) => used_in_cmp(stmp, icmp)
|I1INSl1azy(_, icmp, icmps) =>
  lor(used_in_cmp(stmp, icmp), used_in_cmps(stmp, icmps))
//
|I1INSraise(_, iv1) => used_in_val(stmp, scp, iv1)
//
|I1INSassgn(iv1, iv2) =>
  lor(used_in_val(stmp, scp, iv1), used_in_val(stmp, scp, iv2))
)
//
(* ****** ****** *)
//
and
used_in_let
(stmp: stamp, scp: i1cmp, ilet: i1let): bool =
(
case+ ilet of
|I1LETnew0(iins) => used_in_ins(stmp, scp, iins)
|I1LETnew1(_, iins) => used_in_ins(stmp, scp, iins)
)
//
and
used_in_lets
(stmp: stamp, scp: i1cmp, ilts: i1letlst): bool =
(
case+ ilts of
|list_nil() => false
|list_cons(ilt1, ilts1) =>
  lor(used_in_let(stmp, scp, ilt1), used_in_lets(stmp, scp, ilts1))
)
//
(* ****** ****** *)
//
(*
A NESTED cmp (let/if/case/lam body) becomes its OWN op-resolution scope:
op-temps are minted and consumed within the same flat let-list, so we
re-root [scp] at each cmp boundary.  This keeps native-op recognition
correct (and conservative -- worst case we count a callee we didn't need
to, which only ever keeps a temp alive, never drops a live one).
*)
and
used_in_cmp
(stmp: stamp, icmp: i1cmp): bool =
(
case+ icmp of
|I1CMPcons(ilts, ival) =>
  lor(used_in_lets(stmp, icmp, ilts), used_in_val(stmp, icmp, ival))
)
//
and
used_in_cmps
(stmp: stamp, icmps: i1cmplst): bool =
(
case+ icmps of
|list_nil() => false
|list_cons(ic1, ics1) =>
  lor(used_in_cmp(stmp, ic1), used_in_cmps(stmp, ics1))
)
//
and
used_in_cmpopt
(stmp: stamp, ocmp: i1cmpopt): bool =
(
case+ ocmp of
|optn_nil() => false
|optn_cons(icmp) => used_in_cmp(stmp, icmp)
)
//
(* ****** ****** *)
//
and
used_in_cls
(stmp: stamp, icls: i1cls): bool =
(
case+ icls.node() of
|I1CLSgpt(_) => false
|I1CLScls(_, icmp) => used_in_cmp(stmp, icmp)
)
//
and
used_in_clss
(stmp: stamp, icls: i1clslst): bool =
(
case+ icls of
|list_nil() => false
|list_cons(ic1, ics1) =>
  lor(used_in_cls(stmp, ic1), used_in_clss(stmp, ics1))
)
//
(* ****** ****** *)
//
#implfun
i1tnm_used_in_cmp
(itnm, icmp) =
(
  used_in_cmp(i1tnm_stmp$get(itnm), icmp))
//
(* ****** ****** *)
//
(*
[i1binop_of_dapp]: the PUBLIC entry the emitter calls on an I1INSdapp.
Returns the native Go binary operator string ("+","<",...) iff the call
should be emitted as native infix `(a OP b)` -- i.e. its callee resolves
(within scope [scp]) to a native-able scalar op AND it has exactly two
args; otherwise returns ""(empty) and the emitter keeps the runtime call.
*)
#implfun
i1binop_of_dapp
(callee, args, scp) =
(
if is_native_binop_dapp(callee, args, scp)
then binop_of_callee(callee, scp)
else ""
)//endof[i1binop_of_dapp(callee,args,scp)]
//
(*
[i1ins_is_native_op]: true iff an I1INStimp instruction resolves to a
native-able scalar op.  The emitter uses this at the I1LETnew1 site: such
an op-temp, when its only uses are native-inlined dapps, has already been
made dead by the liveness rule above, so its binding emits as
`_ = xatsgo.Xats_<name>` (harmless; the runtime fallback exists).
*)
#implfun
i1ins_is_native_op
(iins) =
(
  strn_length(goop_of_ins(iins)) > 0)
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== (2) `s2typ -> Go type` SCAFFOLD                                    ==
=======================================================================
//
M2.0 STUB.  [gotype_of_styp] recognizes the scalar base cases that the
static type spells out via [T2Pcst(s2cst)] (the s2cst's *name* is the
ATS sort/type symbol -- "int", "bool", "char", "double", "float",
"string", ...) and returns the matching Go type; everything else falls
back to "any".  [gotype_of_ival] additionally recovers a Go type from a
LITERAL i1val node (I1Vint/I1Vi00 -> int, etc.), which is the one place
intrep1 still carries enough signal locally.  M2.1 wires these to the
concrete-scalar emission.
*)
//
fun
gotype_of_symname
(nm: strn): strn =
(
case+ nm of
| "int" => "int"
| "intGt" => "int"
| "intGte" => "int"
| "intLt" => "int"
| "intLte" => "int"
| "size" => "int"
| "ssize" => "int"
| "bool" => "bool"
| "char" => "rune"
| "schar" => "rune"
| "uchar" => "byte"
| "double" => "float64"
| "float" => "float64"
| "string" => "string"
| "strptr" => "string"
| "strnptr" => "string"
//
// The PRELUDE scalar types are abstract type-constructors, not bare csts:
//   sint = gint_type(sint_k, i)   gint_type's name is "gint_type"
//   dflt = gflt_type(dflt_k)      gflt_type's name is "gflt_type"
//   bool = bool_type(b)           "bool_type"
//   char = char_type(c)           "char_type"
// (The gint/gflt KIND -- xats_sint_t / xats_double_t -- lives in the first
//  arg as a T2Ptext; see [goty_of_text]/[goty_of_apps].)  All int widths
//  map to Go `int` for M2.2 (the surface only exercises [sint]).
| "bool_type" => "bool"
| "char_type" => "rune"
| "gflt_type" => "float64"
| _(*else*) => "any"
)
//
(*
[goty_of_text]: map a C-level $extype name (the gint/gflt KIND, carried as
a T2Ptext) to a Go scalar type.  "xats_sint_t" -> int, "xats_double_t" ->
float64, etc.  All integer widths collapse to Go `int` (M2.2 surface).
*)
fun
goty_of_text
(nm: strn): strn =
(
case+ nm of
| "xats_sint_t"   => "int"
| "xats_uint_t"   => "int"
| "xats_slint_t"  => "int"
| "xats_ulint_t"  => "int"
| "xats_ssize_t"  => "int"
| "xats_usize_t"  => "int"
| "xats_sllint_t" => "int"
| "xats_ullint_t" => "int"
| "xats_bool_t"   => "bool"
| "xats_char_t"   => "rune"
| "xats_double_t" => "float64"
| "xats_float_t"  => "float64"
| "xats_ldouble_t"=> "float64"
| _(*else*) => "any"
)
//
(*
[goty_of_text_in_args]: find the FIRST T2Ptext among [args] (the gint/gflt
KIND) and map it to a Go type; "any" if none present.
*)
fun
goty_of_text_in_args
(args: s2typlst): strn =
(
case+ args of
|list_nil() => "any"
|list_cons(a1, args1) =>
  (
  case+ a1.node() of
  |T2Ptext(nm, _) => goty_of_text(nm)
  | _(*else*) => goty_of_text_in_args(args1))
)
//
(* ****** ****** *)
//
(*
[gorender_funty]: render a function static type's VALUE args + result as a Go
function type `func(T0, T1) Tret` (proof args [npf] dropped).  Used by
[gotype_of_styp]'s T2Pfun1 case so a function-TYPED value (a higher-order
parameter like `f: sint -> sint`, or a closure-returning result) is a callable
Go `func(...)...` rather than an opaque `any` (which Go cannot call/return as
the wrong type).  Recurses through [gotype_of_styp] (SATS-declared, so the
forward reference resolves).  [npf]/[args]/[res] mirror [chase_fun]; we inline
a tiny proof-arg drop + arg-render here to avoid a section-3 forward ref.
*)
fun
gorender_funty
(npf: sint, args: s2typlst, res: s2typ): strn =
let
  fun
  drop1
  (n: sint, xs: s2typlst): s2typlst =
  (
  if (n <= 0) then xs else
  (
  case+ xs of
  |list_nil() => xs
  |list_cons(_, xs1) => drop1(n-1, xs1)))
  //
  fun
  argchase
  (t2p0: s2typ): strn =
  (
  case+ t2p0.node() of
  |T2Parg1(_, t2p1) => argchase(t2p1)
  |T2Patx2(t2p1, _) => argchase(t2p1)
  | _(*else*) => gotype_of_styp(t2p0))
  //
  fun
  loop
  (i0: sint, xs: s2typlst): strn =
  (
  case+ xs of
  |list_nil() => ""
  |list_cons(a1, xs1) =>
    let val t1 = argchase(a1) in
      if (i0 >= 1)
      then strn_append(strn_append(", ", t1), loop(i0+1, xs1))
      else strn_append(t1, loop(i0+1, xs1))
    end)
  //
  val args1 = drop1(npf, args)
  val sargs = loop(0, args1)
  val sres  = gotype_of_styp(res)
in
  strn_append(strn_append(strn_append("func(", sargs), ") "), sres)
end//endof[gorender_funty(npf,args,res)]
//
(*
[gorender_trcd]: render a tuple/record STATIC type ([T2Ptrcd(knd,npf,ltps)]) as
a Go anonymous struct -- flat = a VALUE `struct{...}`, boxed = a `*struct{...}`
POINTER -- with per-field Go types via [gotype_of_styp].  The [s2typ] analog of
[goty_of_i0trcd] (the [i0typ] version), used so a function whose PARAMETER or
RESULT type is a tuple/record gets a concrete struct signature (not `any`).
Field names come from [gofield_of_label], matching every construction /
projection site.  Proof fields ([npf]) are dropped; [npf] = -1 drops nothing.
*)
(*
[gorender_trcd_body]: the bare Go `struct{F0 T0; ...}` BODY (no leading `*`)
of a tuple/record [s2typ] field list, proof prefix [npf] dropped.  Split out
of [gorender_trcd] so the construction-site companion ([gotrcd_struct_body_styp])
can return the SAME body WITHOUT slicing a `*` off a rendered string.
*)
fun
gorender_trcd_body
( npf: sint, ltps: l2t2plst): strn =
let
  fun
  drop1
  (n: sint, xs: l2t2plst): l2t2plst =
  (
  if (n <= 0) then xs else
  (
  case+ xs of
  |list_nil() => xs
  |list_cons(_, xs1) => drop1(n-1, xs1)))
  //
  fun
  fields
  (i0: sint, xs: l2t2plst): strn =
  (
  case+ xs of
  |list_nil() => ""
  |list_cons(lt1, xs1) =>
    let
      val-S2LAB(lab1, t2p1) = lt1
      val fnm = gofield_of_label(lab1)
      val fty = gotype_of_styp(t2p1)
      val one = strn_append(strn_append(fnm, " "), fty)
      val sep = (if (i0 >= 1) then "; " else "")
    in
      strn_append(strn_append(sep, one), fields(i0+1, xs1))
    end
  )
  //
  val ltps1 = drop1(npf, ltps)
  val body  = fields(0, ltps1)
in
  strn_append(strn_append("struct{", body), "}")
end//endof[gorender_trcd_body(npf,ltps)]
//
fun
gorender_trcd
( knd: trcdknd
, npf: sint, ltps: l2t2plst): strn =
let
  val stru = gorender_trcd_body(npf, ltps)
in
  if trcdknd_fltq(knd) then stru else strn_append("*", stru)
end//endof[gorender_trcd(knd,npf,ltps)]
//
#implfun
gotype_of_styp
(t2p0) =
(
case+ t2p0.node() of
|T2Pcst(s2c0) =>
  gotype_of_symname(symbl_get_name(s2c0.name()))
//
// a FUNCTION type -> a Go `func(...)...` type, so a higher-order parameter
// or a closure-returning result is callable/assignable (not opaque `any`).
|T2Pfun1(_, npf, args, res) => gorender_funty(npf, args, res)
//
// M2.6b: a TUPLE / RECORD type -> a Go anonymous struct (flat=value,
// boxed=pointer) so a tuple/record-typed parameter or result is concretely
// typed -- matching what the construction / projection sites emit.
|T2Ptrcd(knd, npf, ltps) => gorender_trcd(knd, npf, ltps)
//
// an APPLIED type-constructor:  gint_type(KIND, i) / gflt_type(KIND) /
// bool_type(b) / char_type(c) / string(...).  Map by the head cst name;
// for the gint/gflt family the precise Go width comes from the KIND arg's
// T2Ptext (goty_of_text), falling back to the head-name mapping.
|T2Papps(t2hd, args) =>
  (
  case+ t2hd.node() of
  |T2Pcst(s2c0) =>
    let
      val hdnm = symbl_get_name(s2c0.name())
    in
      (
      if (hdnm = "gint_type")
      then goty_of_text_in_args(args)
      else
      (
      if (hdnm = "gflt_type")
      then
        (
        // gflt KIND also distinguishes float/double, but all -> float64.
        let val gt = goty_of_text_in_args(args)
        in if (gt = "any") then "float64" else gt end)
      else gotype_of_symname(hdnm)))
    end
  | _(*else*) => "any")
//
// chase through the trivial type wrappers that the front-end leaves on
// scalars (top0/top1 = un/de-initialized; none1 = optional witness).
|T2Ptop0(t2p1) => gotype_of_styp(t2p1)
|T2Ptop1(t2p1) => gotype_of_styp(t2p1)
|T2Plft (t2p1) => gotype_of_styp(t2p1)
|T2Pnone1(t2p1) => gotype_of_styp(t2p1)
|T2Parg1(_, t2p1) => gotype_of_styp(t2p1)
//
// an external $extype directly (rare at this position) -> by its name.
|T2Ptext(nm, _) => goty_of_text(nm)
//
| _(*otherwise*) => "any"
)
//
(* ****** ****** *)
//
#implfun
gotype_of_ival
(ival) =
(
case+ ival.node() of
//
// literals: the node kind IS the type (the one local signal intrep1
// keeps after the styp is dropped from i1val).
|I1Vint(_) => "int"
|I1Vi00(_) => "int"
|I1Vbtf(_) => "bool"
|I1Vb00(_) => "bool"
|I1Vchr(_) => "rune"
|I1Vc00(_) => "rune"
|I1Vflt(_) => "float64"
|I1Vf00(_) => "float64"
|I1Vstr(_) => "string"
|I1Vs00(_) => "string"
//
// everything else: no recoverable static type at the i1val level (see
// BUILD-NOTES "type availability") -> the uniform Regime-A fallback.
| _(*otherwise*) => "any"
)
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== (2a) i0typ -> Go type  (milestone M2.6a -- the SIDE-TABLE reader)  ==
=======================================================================
//
[gotype_of_i0typ] translates a stored [i0typ] (the carry-through type the
side-table recorded at the temp's mint site) to a CONCRETE Go scalar type
where it can prove one, "any" otherwise.  This is the EMIT-time half of the
M2.6a side-table: the lowering stored [i0exp_ityp$get] verbatim; here we map
it -- lazily, only for the temps the emitter queries.
//
[i0typ] (intrep0.sats) is a near-mirror of [s2typ], so the SCALAR cases map
the same way [gotype_of_styp] maps [s2typ]:
  - I0Tcst(s2cst)            : a bare scalar type constant  -> by its name
  - I0Tapps(I0Tcst(nm), as)  : an APPLIED abstract type-ctor; the prelude
                               scalars are gint_type(KIND,i)/gflt_type(KIND)/
                               bool_type(b)/char_type(c) -> width from the
                               KIND [I0Ttext] for the gint/gflt family, else
                               by the head name.  (Same shape gotype_of_styp
                               handles for T2Papps.)
  - I0Ttext(nm, _)           : an external $extype name directly -> by name
  - I0Tlft/top0/top1/none1/  : trivial wrappers the front-end leaves on a
    exi0/uni0/apps-of-quant.   scalar -> chase through to the carried type
  - I0Tnone1(s2typ)          : carries an [s2typ] verbatim -> delegate to the
                               proven [gotype_of_styp]
//
DEFERRED to "any" (M2.6b/M2.7 make these value-typed -- recording a wrong
concrete type here would break [go build], so we are deliberately conservative):
  - I0Ttrcd(trcdknd, npf, _) : flat/boxed tuples + records (M2.6b)
  - I0Ttcon(d2con, _)        : datatype-constructor applications (M2.7)
  - I0Tvar(s2var)            : a polymorphic type variable (pre-monomorphization)
  - I0Tnone0 / anything else : unknown
//
[gotype_of_i0typ] is a top-level [fun] defined BEFORE the recovery
[and]-chain so [gotype_of_ins_local] (which consults it via the side-table)
can call it; it forward-references the SATS-declared [gotype_of_styp]
([#implfun]), which resolves.
*)
//
(* ****** ****** *)
//
(*
=======================================================================
== (2c) LAYOUT-AWARE TUPLES / RECORDS  (milestone M2.6b)             ==
=======================================================================
//
A flat tuple/record (trcdknd_fltq) is a Go VALUE struct
`struct{F0 T0; F1 T1; ...}`; a boxed one is a `*struct{...}` POINTER.  The
field TYPES come from the [i0typ]'s own field list ([l0i0tlst] inside
[I0Ttrcd]); the field NAMES are positional [F0,F1,...] for an integer label
([LABint]) and [F<sym>] for a record symbol label ([LABsym]).  The SAME
type-translation drives BOTH the construction site (the struct literal's
type) and every projection (`v.F<lab>`), so the anonymous struct is
identical everywhere (Go's structural typing then makes them assignable).
//
[gostr_of_uint]: a non-negative integer -> its decimal Go string.  Needed
to build positional field names ([F0],[F1],...) for tuple structs.  Built
from single-digit string literals + [ndiv]/[nmod] (no char arithmetic), so
it is dialect-safe.
*)
fun
godigit_str
(d: sint): strn =
(
case+ d of
| 0 => "0" | 1 => "1" | 2 => "2" | 3 => "3" | 4 => "4"
| 5 => "5" | 6 => "6" | 7 => "7" | 8 => "8" | _(*9*) => "9"
)
//
fun
gostr_of_uint
(n: sint): strn =
(
if (n < 10) then godigit_str(n)
else strn_append(gostr_of_uint(n / 10), godigit_str(n % 10))
)
//
(*
[gofield_of_label]: the Go FIELD NAME for a tuple/record label.  A positional
tuple label [LABint(i)] -> "F<i>" (F0, F1, ...); a record label [LABsym(s)] ->
"F<sanitized-s>" (the leading `F` keeps it a Go-EXPORTED identifier -- harmless
in the single `package main` -- and avoids clashing with Go keywords; the
symbol chars are sanitized to a valid Go identifier the same way [xsymgo1]
does so the field name a record projection emits matches its construction).
This is the ONE place the field-name scheme is defined, so type-translation,
construction, and projection cannot disagree.
*)
#implfun
gofield_of_label
(lab0) =
(
case+ lab0 of
|LABint(i0) => strn_append("F", gostr_of_uint(i0))
|LABsym(sym) => strn_append("F", symbl_get_name(sym))
)//endof[gofield_of_label(lab0)]
//
// NOTE: a record label symbol ([LABsym]) is an ordinary ATS identifier
// (letters/digits/underscore), so [symbl_get_name] is already a valid Go
// identifier fragment -- prefixing "F" keeps it a single, collision-free,
// Go-EXPORTED field name (harmless in the single `package main`).  A label
// with a non-identifier char would need the [xsymgo1]-style sanitization the
// FILR emitters apply; the READ-path surface here never produces one (the
// oracle would catch any divergence as a `go build` failure).
//
(* ****** ****** *)
//
fun
goty_of_i0t_apps
( hd: i0typ
, args: i0typlst): strn =
(
case+ hd.node() of
|I0Tcst(s2c0) =>
  let
    val hdnm = symbl_get_name(s2c0.name())
  in
    (
    if (hdnm = "gint_type")
    then goty_of_i0text_in_args(args)
    else
    (
    if (hdnm = "gflt_type")
    then
      (
      // gflt KIND distinguishes float/double, but both -> float64.
      let val gt = goty_of_i0text_in_args(args)
      in if (gt = "any") then "float64" else gt end)
    else gotype_of_symname(hdnm)))
  end
| _(*non-cst head*) => "any"
)//endof[goty_of_i0t_apps(hd,args)]
//
and
(*
[goty_of_i0text_in_args]: find the FIRST [I0Ttext] among [args] (the gint/gflt
KIND, carried as an external type name) and map it via [goty_of_text]; "any"
if none present.  Parallel to [goty_of_text_in_args] on [s2typlst].
*)
goty_of_i0text_in_args
(args: i0typlst): strn =
(
case+ args of
|list_nil() => "any"
|list_cons(a1, args1) =>
  (
  case+ a1.node() of
  |I0Ttext(nm, _) => goty_of_text(nm)
  | _(*else*) => goty_of_i0text_in_args(args1))
)//endof[goty_of_i0text_in_args(args)]
//
and
gotype_of_i0typ
(ityp: i0typ): strn =
(
case+ ityp.node() of
//
// a bare scalar type constant (the s2cst NAME is the ATS type symbol).
|I0Tcst(s2c0) =>
  gotype_of_symname(symbl_get_name(s2c0.name()))
//
// an applied abstract type-ctor: the prelude scalars (gint_type/gflt_type/
// bool_type/char_type/...) -- map by head + KIND-arg (see goty_of_i0t_apps).
|I0Tapps(hd, args) => goty_of_i0t_apps(hd, args)
//
// an external $extype name directly (rare at this position) -> by its name.
|I0Ttext(nm, _) => goty_of_text(nm)
//
// trivial wrappers the front-end leaves around a scalar -> chase through.
|I0Tlft(t1) => gotype_of_i0typ(t1)
|I0Ttop0(t1) => gotype_of_i0typ(t1)
|I0Ttop1(t1) => gotype_of_i0typ(t1)
|I0Texi0(_, t1) => gotype_of_i0typ(t1)
|I0Tuni0(_, t1) => gotype_of_i0typ(t1)
|I0Tlam1(_, t1) => gotype_of_i0typ(t1)
//
// an [i0typ] that just wraps an [s2typ] -> reuse the proven s2typ translator.
|I0Tnone1(t2p0) => gotype_of_styp(t2p0)
//
// M2.6b: a TUPLE / RECORD (the layout-bearing node) -> a Go anonymous struct
// (flat = a VALUE struct, boxed = a *struct POINTER), with per-field Go types
// from the field list.  Driving construction + projection from this SAME
// translation makes the anonymous struct identical at every site (Go's
// structural typing then makes them assignable).
|I0Ttrcd(knd, npf, fields) => goty_of_i0trcd(knd, npf, fields)
//
// DATATYPES / POLYMORPHIC / UNKNOWN -> "any" (M2.7).  A wrong concrete type
// here would break [go build]; deferring is the safe choice.
| _(*otherwise*) => "any"
)//endof[gotype_of_i0typ(ityp)]
//
(*
[goty_of_i0trcd]: translate a tuple/record [i0typ] -> a Go anonymous struct.
  flat (trcdknd_fltq)  -> `struct{F<l0> T0; F<l1> T1; ...}`     (VALUE)
  boxed                -> `*struct{F<l0> T0; F<l1> T1; ...}`    (POINTER)
The leading [npf] PROOF fields are erased (dropped, like a d2con's nprg), so
only the VALUE fields become struct fields.  Each field's Go type recurses
through [gotype_of_i0typ] (so a NESTED tuple/record field is itself a struct).
The field NAMES come from each field's own [label] via [gofield_of_label], so
they MATCH the projection sites' `v.F<lab>` exactly.
//
[npf] may be -1 (the front-end's "no proof prefix" sentinel) -- [drop_pf_i0t]
treats any n<=0 as "drop nothing", so -1 and 0 behave identically.
*)
and
goty_of_i0trcd
( knd: trcdknd
, npf: sint, fields: l0i0tlst): strn =
let
  val flds1 = drop_pf_i0t(npf, fields)
  val body  = goty_of_i0t_fields(0, flds1)
  val stru  = strn_append(strn_append("struct{", body), "}")
in
  if trcdknd_fltq(knd) then stru else strn_append("*", stru)
end
//
(*
[drop_pf_i0t]: drop the leading [npf] proof fields (erased) from a field list.
*)
and
drop_pf_i0t
(npf: sint, fields: l0i0tlst): l0i0tlst =
(
if (npf <= 0) then fields else
(
case+ fields of
|list_nil() => fields
|list_cons(_, flds1) => drop_pf_i0t(npf-1, flds1))
)
//
(*
[goty_of_i0t_fields]: render the `F<lab> <goty>; ...` body of a struct from a
field list ([I0LAB(label, i0typ)] each).  [i0] is just a separator counter so
fields are `; `-joined.  Each field type recurses through [gotype_of_i0typ].
*)
and
goty_of_i0t_fields
(i0: sint, fields: l0i0tlst): strn =
(
case+ fields of
|list_nil() => ""
|list_cons(f1, flds1) =>
  let
    val-I0LAB(lab1, ity1) = f1
    val fnm = gofield_of_label(lab1)
    val fty = gotype_of_i0typ(ity1)
    val one = strn_append(strn_append(fnm, " "), fty)
    val sep = (if (i0 >= 1) then "; " else "")
  in
    strn_append(strn_append(sep, one), goty_of_i0t_fields(i0+1, flds1))
  end
)//endof[goty_of_i0t_fields(i0,fields)]
//
(*
[gotype_of_tnm_from_tytab]: the SIDE-TABLE entry point the emitter's fallback
calls -- look up the temp's recorded [i0typ] by stamp and translate it.  "any"
when the temp was never recorded (a [trxi0i1]-invented temp with no source
[i0exp]) OR when its recorded type is an aggregate/datatype/unknown (M2.6b/M2.7).
*)
fun
gotype_of_tnm_from_tytab
(stmp: stamp): strn =
(
case+ go_tytab_get(stmp) of
|optn_nil() => "any"
|optn_cons(ityp) => gotype_of_i0typ(ityp)
)//endof[gotype_of_tnm_from_tytab(stmp)]
//
(* ****** ****** *)
//
(*
[gotrcd_struct_body]: if [ityp] is (or wraps) a tuple/record [I0Ttrcd], return
[optn_cons(@(isFlat, structBody))] where [structBody] is the Go `struct{...}`
type (WITHOUT the leading `*` -- the caller decides value-vs-pointer literal
syntax) and [isFlat] = [trcdknd_fltq(knd)].  [optn_nil] when [ityp] is not a
tuple/record.  This is the construction-site companion to [goty_of_i0trcd]
(which returns the full type with `*`): a flat literal is `struct{...}{...}`, a
boxed literal is `&struct{...}{...}`, both over the SAME [structBody], so the
constructed value's Go type is exactly what [gotype_of_i0typ] gives a projection
root -- the two sites cannot disagree.
*)
fun
gotrcd_struct_body
(ityp: i0typ): optn(@(bool, strn)) =
(
case+ ityp.node() of
|I0Ttrcd(knd, npf, fields) =>
  let
    val flds1 = drop_pf_i0t(npf, fields)
    val body  = goty_of_i0t_fields(0, flds1)
    val stru  = strn_append(strn_append("struct{", body), "}")
  in
    optn_cons(@(trcdknd_fltq(knd), stru))
  end
// chase the trivial wrappers (a tuple/record's recorded type is normally a
// bare I0Ttrcd, but be robust to a wrapper the front-end might leave).
|I0Tlft(t1) => gotrcd_struct_body(t1)
|I0Ttop0(t1) => gotrcd_struct_body(t1)
|I0Ttop1(t1) => gotrcd_struct_body(t1)
|I0Texi0(_, t1) => gotrcd_struct_body(t1)
|I0Tuni0(_, t1) => gotrcd_struct_body(t1)
|I0Tlam1(_, t1) => gotrcd_struct_body(t1)
// IMPORTANT (verified via the IR dump): a tuple/record's recorded type is
// NOT a native [I0Ttrcd] -- the side-table stores [I0Tnone1(s2typ)] where the
// [s2typ] is the layout-bearing [T2Ptrcd(knd,npf,ltps)].  So delegate to the
// [s2typ] companion, which recognizes [T2Ptrcd] (and uses the SAME field-name
// scheme + per-field translation as [goty_of_i0trcd]/[gorender_trcd], so the
// construction-site struct type is byte-identical to a projection root's).
|I0Tnone1(t2p0) => gotrcd_struct_body_styp(t2p0)
| _(*non-trcd*) => optn_nil()
)//endof[gotrcd_struct_body(ityp)]
//
(*
[gotrcd_struct_body_styp]: the [s2typ] companion of [gotrcd_struct_body].  If
[t2p0] is (or wraps) a tuple/record [T2Ptrcd(knd,npf,ltps)], return
[optn_cons(@(isFlat, structBody))] where [structBody] is the Go `struct{...}`
type WITHOUT the leading `*` and [isFlat] = [trcdknd_fltq(knd)].  Built from
[gorender_trcd]'s field renderer so the construction site's struct type is the
SAME text a projection root gets from [gotype_of_styp]'s [T2Ptrcd] arm.  Chases
the trivial [s2typ] wrappers the front-end leaves on a value's type.
*)
and
gotrcd_struct_body_styp
(t2p0: s2typ): optn(@(bool, strn)) =
(
case+ t2p0.node() of
|T2Ptrcd(knd, npf, ltps) =>
  // the bare `struct{...}` body (no `*`) -- the caller writes the value-vs-
  // pointer literal syntax (`x{}` vs `&x{}`) from [isFlat].
  optn_cons(@(trcdknd_fltq(knd), gorender_trcd_body(npf, ltps)))
|T2Ptop0(t1) => gotrcd_struct_body_styp(t1)
|T2Ptop1(t1) => gotrcd_struct_body_styp(t1)
|T2Plft (t1) => gotrcd_struct_body_styp(t1)
|T2Pnone1(t1) => gotrcd_struct_body_styp(t1)
|T2Parg1(_, t1) => gotrcd_struct_body_styp(t1)
| _(*non-trcd*) => optn_nil()
)//endof[gotrcd_struct_body_styp(t2p0)]
//
(*
[gotrcd_of_tnm]: the construction-site SIDE-TABLE entry point -- look up the
result temp's recorded [i0typ] by stamp and, if it is a tuple/record, return
its (isFlat, structBody).  [optn_nil] when the temp was not recorded or its type
is not a tuple/record (then the construction emitter falls back to a token- +
value-typed struct, see the emitter).
*)
#implfun
gotrcd_of_tnm
(stmp) =
(
case+ go_tytab_get(stmp) of
|optn_nil() => optn_nil()
|optn_cons(ityp) => gotrcd_struct_body(ityp)
)//endof[gotrcd_of_tnm(stmp)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== CONTROL-FLOW HELPERS  (milestone M2.3)                            ==
=======================================================================
//
A VALUE-position if/case/let binds its result to a temp [I1LETnew1(tnm,
ins)] whose Go must be:
    var goxtnm<tnm> <T>
    if/switch ... { goxtnm<tnm> = <result> } ...
So we must pick a Go type [T] for the pre-declared var.  intrep1 dropped
the styp, but the BRANCH RESULT i1vals are often literals, so
[gotype_of_ival] recovers a concrete scalar where the branches return a
literal of a known kind; otherwise we fall back to `any`.  We take the
type of the FIRST branch whose result types concretely (all branches of a
well-typed if/case share one type, so any concrete one is right); `any`
only if NONE is recoverable.
*)
//
fun
goty_join
(t1: strn, t2: strn): strn =
(
  if (t1 = "any") then t2 else t1)
//
(*
[op_result_goty]: the Go RESULT type of a native scalar op, by name.
Comparison/equality ops -> "bool"; arithmetic ops -> the OPERAND type
([opty], recovered from a literal/typed operand); "" if not a native op.
*)
fun
op_result_goty
(nm: strn, opty: strn): strn =
(
case+ nm of
// comparisons + equality -> bool (regardless of operand type)
| "sint_lt$sint" => "bool" | "sint_gt$sint" => "bool"
| "sint_lte$sint" => "bool" | "sint_gte$sint" => "bool"
| "sint_eq$sint" => "bool" | "sint_neq$sint" => "bool"
| "dflt_lt$dflt" => "bool" | "dflt_gt$dflt" => "bool"
| "dflt_lte$dflt" => "bool" | "dflt_gte$dflt" => "bool"
| "dflt_eq$dflt" => "bool" | "dflt_neq$dflt" => "bool"
| "char_lt" => "bool" | "char_gt" => "bool"
| "char_lte" => "bool" | "char_gte" => "bool"
| "char_eq" => "bool" | "char_neq" => "bool"
| "bool_eq" => "bool" | "bool_neq" => "bool"
// arithmetic -> the operand type (int / float64)
| "sint_add$sint" => "int" | "sint_sub$sint" => "int"
| "sint_mul$sint" => "int" | "sint_div$sint" => "int"
| "sint_mod$sint" => "int"
| "dflt_add$dflt" => "float64" | "dflt_sub$dflt" => "float64"
| "dflt_mul$dflt" => "float64" | "dflt_div$dflt" => "float64"
| _(*non-native*) => ""
)
//
(*
[gotype_of_tnm_in_lets]: type a result temp [stmp] by finding its binding
[I1LETnew1(tnm, ins)] in [ilts] and typing [ins]:
  - I1INSdapp inlining a native op -> [op_result_goty] (bool for compares,
    operand type for arithmetic; operand type from a literal arg);
  - I1INSdapp to a typed function (callee cst) -> its result Go type;
  - I1INSift0/cas0/let0 (nested block) -> its branch/result type;
  - otherwise "any".
This recovers the type of a COMPUTED value-position result (e.g. a let-in
whose body is `a * a`), which [gotype_of_ival] alone cannot.
*)
fun
gotype_of_dapp_args
(args: i1valist): strn =
(
case+ args of
|list_nil() => "any"
|list_cons(a1, args1) =>
  let val t1 = gotype_of_ival(a1)
  in if (t1 = "any") then gotype_of_dapp_args(args1) else t1 end
)
//
(*
[binds_of_fjarglst]: collect the parameter binds (the [i1bnd] of each
[I1BNDcons] across every [FJARGdarg]) of a lambda/fix's [fjarglst], so a body
result temp that is one of these params can be typed from its [I0Pvar(d2var)]
pattern via [gotype_of_capture_bnd].  Parallel to [params_of_fjarglst] /
[gotypes_of_fjarglst].  (SATS-declared so the emitter -- and the recovery
[and]-chain below -- can both call it; it is NOT chain-local because the chain
is mutually recursive and [#implfun] cannot sit in an [and] group.)
*)
#implfun
binds_of_fjarglst
(fjas) =
(
case+ fjas of
|list_nil() => list_nil()
|list_cons(fja1, fjas1) =>
  let
    val-FJARGdarg(i1bs) = fja1.node()
  in
    list_append(i1bs, binds_of_fjarglst(fjas1))
  end
)
//
(*
[gotype_of_capture_bnd]: type a bare result temp [stmp] that is NOT bound in
the cmp's lets -- i.e. a FREE parameter or CAPTURE from an enclosing
function/lambda.  [bnds] is the list of in-scope parameter binds (the
function's own params + every enclosing lambda's params, accumulated as the
emitter descends).  When [stmp] matches a bind's i1tnm, we read the param's
declared/inferred static type from its [I0Pvar(d2var)] pattern via
[d2var_get_styp] and map it through [gotype_of_styp].  This is the M2.5 BUG-1
fix for `lam u => a` (body returns the captured `a`): without it the result
temp is not in the lets, so the recovery returned "any" and the func literal
was emitted as `func(...) any`, colliding with the enclosing function's
concrete `func(...) int` signature (go vet failure).
*)
fun
gotype_of_capture_bnd
(stmp: stamp, bnds: i1bndlst): strn =
(
case+ bnds of
|list_nil() => "any"
|list_cons(ibnd, bnds1) =>
  let
    val-I1BNDcons(itnm, ipat, _) = ibnd
  in
    if stmp_eq(stmp, i1tnm_stmp$get(itnm))
    then
      (
      case+ ipat.node() of
      |I0Pvar(d2v) => gotype_of_styp(d2var_get_styp(d2v))
      | _(*else*) => "any")
    else gotype_of_capture_bnd(stmp, bnds1)
  end
)
//
fun
gotype_of_ins_local
(ilts: i1letlst, iins: i1ins, bnds: i1bndlst): strn =
(
case+ iins of
|I1INSdapp(callee, args) =>
  (
  case+ callee.node() of
  // native-op callee (a temp bound to an op timp): result by op name.
  |I1Vtnm(opt) =>
    let
      val opnm = name_of_op_tnm_in_lets(i1tnm_stmp$get(opt), ilts)
    in
      if (strn_length(opnm) = 0) then "any"
      else op_result_goty(opnm, gotype_of_dapp_args(args))
    end
  | _(*else*) => "any")
|I1INSift0(_, _, _) => gotype_of_ift0type2(iins, bnds)
|I1INScas0(_, _, _) => gotype_of_ift0type2(iins, bnds)
|I1INSlet0(_, _) => gotype_of_ift0type2(iins, bnds)
// M2.5 BUG-1: a result temp whose producer is itself a NESTED lambda / local
// recursive closure (a curried `lam b => lam c => ...`) -- recurse to recover
// the inner closure's Go func type, so the enclosing lambda's RETURN type is
// the concrete `func(...) ...` (NOT "any", which would collide with the outer
// function's concrete signature).  The inner lambda's OWN params are added to
// [bnds] so the inner body's captures/params still resolve.
|I1INSlam0(_, fjas, body) =>
  let
    val argtys = gotypes_of_fjarglst(fjas)
    val bnds1  = list_append(binds_of_fjarglst(fjas), bnds)
    val retty  = gotype_of_lam_ret2(body, bnds1)
  in
    gofunctype_of_fjarglst(argtys, retty)
  end
|I1INSfix0(_, fvar, fjas, body) =>
  let
    // prefer the FIX-VAR's declared signature (more reliable than inferring
    // from an if/case-bodied recursive body), as the fix0 emit site does.
    val vargtys = goargtys_of_funvar(fvar)
    val argtys  =
      (case+ vargtys of
       |list_nil() => gotypes_of_fjarglst(fjas)
       |list_cons _ => vargtys)
    val vretty = goretty_of_funvar(fvar)
    val bnds1  = list_append(binds_of_fjarglst(fjas), bnds)
    val retty  =
      (if (vretty = "any") then gotype_of_lam_ret2(body, bnds1) else vretty)
  in
    gofunctype_of_fjarglst(argtys, retty)
  end
| _(*else*) => "any"
)
//
and
name_of_op_tnm_in_lets
(stmp: stamp, ilts: i1letlst): strn =
(
case+ ilts of
|list_nil() => ""
|list_cons(ilt1, ilts1) =>
  (
  case+ ilt1 of
  |I1LETnew1(itnm, iins) =>
    (
    if stmp_eq(stmp, i1tnm_stmp$get(itnm))
    then goop_name_of_ins(iins)
    else name_of_op_tnm_in_lets(stmp, ilts1))
  |I1LETnew0(_) => name_of_op_tnm_in_lets(stmp, ilts1))
)
//
and
goop_name_of_ins
(iins: i1ins): strn =
(
case+ iins of
|I1INStimp(_, timp) => symbl_get_name(timp.dcst().name())
| _(*else*) => ""
)
//
(*
[gotype_of_tnm_in_lets2]: find the binding of [stmp] in [search] (a suffix of
the full let-list) and type its ins via [full] (the WHOLE let-list, needed so
[gotype_of_ins_local] can resolve an op-temp callee that appears EARLIER than
the binding being typed).  Keeping [full] constant across the search is the
fix for the op-temp-precedes-its-use ANF shape.  [bnds] (in-scope param binds)
is threaded so a nested block's own result temp that is itself a free
param/capture can still be typed (M2.5).  When [stmp] is NOT bound in the lets
at all, we fall back to [gotype_of_capture_bnd] -- the temp is a free
parameter/capture (the M2.5 BUG-1 case: `lam u => a`).
*)
and
gotype_of_tnm_in_lets2
(stmp: stamp, full: i1letlst, search: i1letlst, bnds: i1bndlst): strn =
(
case+ search of
//
// [stmp] is NOT bound in this cmp's lets -> it is a free parameter / capture.
// Try the in-scope param binds first (M2.5); if THOSE don't type it, fall back
// to the M2.6a SIDE-TABLE (the temp's source [i0exp] type carried at lowering).
|list_nil() =>
  let
    val tyb = gotype_of_capture_bnd(stmp, bnds)
  in
    if (tyb = "any") then gotype_of_tnm_from_tytab(stmp) else tyb
  end
|list_cons(ilt1, ilts1) =>
  (
  case+ ilt1 of
  |I1LETnew1(itnm, iins) =>
    (
    if stmp_eq(stmp, i1tnm_stmp$get(itnm))
    then
      // type the producing instruction locally (native-op result, nested
      // block, nested lambda, ...).  When the LOCAL recovery yields "any" (the
      // M2.6 debt: a [dapp] to a user function / an opaque-callee result), fall
      // back to the SIDE-TABLE -- the temp's stamp keys the source [i0exp]'s
      // recorded static type, which types user-function-call results that the
      // intrep1-level recovery cannot.  (Local recovery FIRST so an
      // already-concrete answer -- e.g. native-op bool/int -- is preferred and
      // the table is only a backstop; the two agree where both fire.)
      let
        val tyl = gotype_of_ins_local(full, iins, bnds)
      in
        if (tyl = "any") then gotype_of_tnm_from_tytab(stmp) else tyl
      end
    else gotype_of_tnm_in_lets2(stmp, full, ilts1, bnds))
  |I1LETnew0(_) => gotype_of_tnm_in_lets2(stmp, full, ilts1, bnds))
)
//
and
gotype_of_tnm_in_lets
(stmp: stamp, ilts: i1letlst, bnds: i1bndlst): strn =
  gotype_of_tnm_in_lets2(stmp, ilts, ilts, bnds)
//
(*
[gotype_of_cmp2]: the Go type of a cmp's RESULT value (the type the binding
temp should have when this cmp is a value-position branch / lambda body).  A
literal result types directly via [gotype_of_ival]; a COMPUTED result
(I1Vtnm) is typed by finding its producing instruction in the cmp's lets
([gotype_of_tnm_in_lets]) -- and when it is NOT in the lets, by the in-scope
param binds [bnds] (free parameter / capture, the M2.5 fix); else "any".
*)
and
gotype_of_cmp2
(icmp: i1cmp, bnds: i1bndlst): strn =
(
case+ icmp of
|I1CMPcons(ilts, ival) =>
  let
    val t0 = gotype_of_ival(ival)
    val res =
    (
    if (t0 = "any")
    then
      (
      case+ ival.node() of
      |I1Vtnm(rtnm) =>
         gotype_of_tnm_in_lets(i1tnm_stmp$get(rtnm), ilts, bnds)
      | _(*else*) => "any")
    else t0)
  in
    res
  end
)
//
and
gotype_of_cmpopt2
(ocmp: i1cmpopt, bnds: i1bndlst): strn =
(
case+ ocmp of
|optn_nil() => "any"
|optn_cons(icmp) => gotype_of_cmp2(icmp, bnds)
)
//
(*
[gotype_of_clss2]: the Go type of a case's result, taken from the first
clause body whose result types concretely.
*)
and
gotype_of_clss2
(icls: i1clslst, bnds: i1bndlst): strn =
(
case+ icls of
|list_nil() => "any"
|list_cons(ic1, ics1) =>
  (
  case+ ic1.node() of
  |I1CLSgpt(_) => gotype_of_clss2(ics1, bnds)
  |I1CLScls(_, icmp) =>
    goty_join(gotype_of_cmp2(icmp, bnds), gotype_of_clss2(ics1, bnds)))
)
//
and
gotype_of_ift0type2
(iins: i1ins, bnds: i1bndlst): strn =
(
case+ iins of
|I1INSift0(_, othn, oels) =>
  goty_join(gotype_of_cmpopt2(othn, bnds), gotype_of_cmpopt2(oels, bnds))
|I1INScas0(_, _, icls) => gotype_of_clss2(icls, bnds)
|I1INSlet0(_, icmp) => gotype_of_cmp2(icmp, bnds)
| _(*else*) => "any"
)
//
(*
[gotype_of_lam_ret2]: the Go RESULT type of a lambda/fix body cmp, given the
in-scope param binds [bnds] (own params + enclosing captures).  The body is
the canonical [I1CMPcons([I1LETnew0(I1INSrturn(_, innerCmp))], I1Vnil())]; we
unwrap to [innerCmp] and type its result via [gotype_of_cmp2].  Falls back to
"any" for a non-canonical body or an unrecoverable result type.
*)
and
gotype_of_lam_ret2
(icmp: i1cmp, bnds: i1bndlst): strn =
(
case+ icmp of
|I1CMPcons
  (list_cons(I1LETnew0(I1INSrturn(_, innerCmp)), list_nil()), _) =>
    gotype_of_cmp2(innerCmp, bnds)
| _(*otherwise*) => gotype_of_cmp2(icmp, bnds)
)
//
(*
[gotype_of_cmp] / [gotype_of_ift0type] / [gotype_of_lam_ret]: the
no-in-scope-binds (top-level) entry points, used by value-position emission
where there are no captured params to resolve.  The [bnds]-threaded variants
([_2]) are the general form used by the lambda return-type recovery (M2.5).
*)
fun
gotype_of_cmp
(icmp: i1cmp): strn = gotype_of_cmp2(icmp, list_nil())
//
#implfun
gotype_of_ift0type
(iins) = gotype_of_ift0type2(iins, list_nil())
//
(* ****** ****** *)
//
(*
[i1ins_fully_returnsq]: does this if/case INSTRUCTION fully return -- i.e.
do ALL of its (present) branch bodies end in an [I1INSrturn] (i1cmp_retq)?
When true, the if/case is in RETURN position: each branch emits its own
`return <...>`, so no result temp is pre-declared and the enclosing cmp's
trailing result is suppressed (the branches already returned).  When false
it is in VALUE position: pre-declare a temp, branches assign to it.
//
A missing branch (optn_nil for if; an empty clause-list for case) counts
as NOT-fully-returning, conservatively keeping the value-position path
(safe: a pre-declared zero temp + assign in the present branches is always
correct, just less idiomatic).  For [I1INSlet0] this is true exactly when
its BODY cmp fully returns (i1cmp_tail_returns) -- a let whose body is a
returning if/case/nested-let, in FUNCTION-BODY (return) position; then the
let-block emits in return mode (no result temp, no trailing return).
*)
#implfun
i1ins_fully_returnsq
(iins) =
(
case+ iins of
//
|I1INSift0(_, othn, oels) =>
  (
  case+ othn of
  |optn_nil() => false
  |optn_cons(cthn) =>
    (
    case+ oels of
    |optn_nil() => false
    |optn_cons(cels) =>
      (
      if i1cmp_retq(cthn) then i1cmp_retq(cels) else false)))
//
|I1INScas0(_, _, icls) =>
  all_clauses_retq(icls)
//
// A let-in in RETURN position: its body cmp already returns on every path
// (its inner if/case branches end in I1INSrturn) -- so the let-block needs
// NO result temp + NO trailing return (the value-mode scaffold's trailing
// `return goxtnm<N>` would be UNREACHABLE -> `go vet`: "unreachable code").
// i1cmp_tail_returns(body) is the SAME fully-returns decision used for the
// trailing if/case recursion crux, now extended through I1INSlet0's body
// (so a let whose body is a returning if OR case OR nested let all qualify).
|I1INSlet0(_, body) =>
  i1cmp_tail_returns(body)
//
| _(*else*) => false
) where
{
//
// every clause body returns?  (an empty clause list -> vacuously true,
// but such a case never arises; [i1cmp_retq] over each I1CLScls body.)
fun
all_clauses_retq
(icls: i1clslst): bool =
(
case+ icls of
|list_nil() => true
|list_cons(ic1, ics1) =>
  (
  case+ ic1.node() of
  |I1CLSgpt(_) => all_clauses_retq(ics1)
  |I1CLScls(_, icmp) =>
    (
    if i1cmp_retq(icmp) then all_clauses_retq(ics1) else false))
)
//
}(*where*)//endof[i1ins_fully_returnsq(iins)]
//
(* ****** ****** *)
//
(*
[i1ins_is_blockform]: is this an instruction that emits as a MULTI-
STATEMENT Go block (if / switch / let-block) rather than a single
expression?  The [I1LETnew1]/[I1LETnew0] emitter special-cases these so it
can pre-declare a result temp + drive each branch, instead of the
`goxtnm := <expr>` single-line form.
*)
#implfun
i1ins_is_blockform
(iins) =
(
case+ iins of
|I1INSift0(_, _, _) => true
|I1INScas0(_, _, _) => true
|I1INSlet0(_, _) => true
// M2.5: a lambda / local recursive closure emits as a MULTI-LINE Go func
// literal (`goxtnm := func(...) ... { <body> }`), so it routes through the
// block emitter (which controls indentation of the captured body) rather
// than the single-expression let rule.
|I1INSlam0(_, _, _) => true
|I1INSfix0(_, _, _, _) => true
| _(*else*) => false
)
//
(* ****** ****** *)
//
(*
[i1cmp_tail_returns]: does this cmp ALREADY return on every path -- so the
result-mode emitter must NOT append a trailing `return <result>` / `goxtnm
= <result>` (which would read an unassigned var or be unreachable)?
//
True when EITHER:
  (a) i1cmp_retq holds (the stock predicate: the last let is itself an
      rturn, or a trailing if/case whose branches all return as I1LETnew0);
  (b) the last let is I1LETnew1(tnm, ift0/cas0) whose branches all return
      (i1ins_fully_returnsq) AND the cmp RESULT is exactly I1Vtnm(tnm) --
      i.e. the function/branch returns through that fully-returning if/case.
      [i1cmp_retq] misses (b) because it only inspects I1LETnew0; a VALUE-
      bound (I1LETnew1) fully-returning if/case is precisely how a recursive
      `fun ... = if ... then ... else ...` lowers (verified in test11), so
      handling (b) is the recursion/return crux.
*)
fun
last_let_returns
(icmp: i1cmp): bool =
let
  val-I1CMPcons(ilts, ival) = icmp
  //
  fun
  lastlet
  (ilts: i1letlst): optn(i1let) =
  (
  case+ ilts of
  |list_nil() => optn_nil()
  |list_cons(il1, list_nil()) => optn_cons(il1)
  |list_cons(_, ilts1) => lastlet(ilts1)
  )
in//let
  case+ lastlet(ilts) of
  |optn_nil() => false
  |optn_cons(I1LETnew1(itnm, iins)) =>
    (
    if i1ins_fully_returnsq(iins)
    then
      (
      case+ ival.node() of
      |I1Vtnm(rtnm) =>
        (stamp_cmp(i1tnm_stmp$get(itnm), i1tnm_stmp$get(rtnm)) = 0)
      | _(*else*) => false)
    else false)
  |optn_cons(I1LETnew0(_)) => false
end//let//endof[last_let_returns(icmp)]
//
#implfun
i1cmp_tail_returns
(icmp) =
(
  if i1cmp_retq(icmp) then true else last_let_returns(icmp))
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== (2b) TAIL-CALL OPTIMIZATION  (milestone M2.4)                      ==
=======================================================================
//
A TAIL self-call lowers (verified via the IR dump of
`fun fac(n,acc) = if n<=0 then acc else fac(n-1, acc*n)`) as an
I1INSrturn(I0CALfun(fac;[fac]), innerCmp) where innerCmp is
    I1CMPcons(
      [ ... arg pre-computation lets (t1 = n-1; t2 = acc*n) ...
      , I1LETnew1(tR, I1INSdapp(I1Vfenv(fac;[]), [t1, t2])) ]  // the self-call
    ; I1Vtnm(tR))                                              // result = tR
and i1cmp_tailq(innerCmp, ical) holds because the LAST let binds the cmp
result via a dapp whose callee is the self d2var (d2var_tailq).
//
CRITICAL SIMULTANEITY: each new argument (n-1, acc*n) is ALREADY
pre-computed into its OWN temp (t1, t2) by the lets that PRECEDE the
self-call dapp -- those temps reference the OLD parameter values.  So
emitting `goxtnm<p1> = t1; goxtnm<p2> = t2; continue` is safe: by the
time the params are reassigned, every new value is already in a temp
(no new value reads a partially-updated param).  [rturn_tail_args]
returns BOTH the preceding lets (to emit FIRST) and the call args (the
new param values), so the emitter never needs to spill.
*)
//
(*
[split_last_dapp_args]: from a let-list whose LAST let is
[I1LETnew1(_, I1INSdapp(_, args))], return (all-but-last lets, args).
(Only ever called when i1cmp_tailq already verified that shape.)
*)
fun
split_last_dapp_args
(ilts: i1letlst): @(i1letlst, i1valist) =
(
case+ ilts of
|list_nil() => @(list_nil(), list_nil())
|list_cons(il1, list_nil()) =>
  (
  case+ il1 of
  |I1LETnew1(_, I1INSdapp(_, args)) => @(list_nil(), args)
  | _(*else*) => @(list_nil(), list_nil()))
|list_cons(il1, ilts1) =>
  let
    val (pre1, args1) = split_last_dapp_args(ilts1)
  in
    @(list_cons(il1, pre1), args1)
  end
)
//
#implfun
rturn_tail_args
(ical, icmp) =
(
if i1cmp_tailq(icmp, ical)
then
  let
    val-I1CMPcons(ilts, _) = icmp
    val (pre, args) = split_last_dapp_args(ilts)
  in
    optn_cons(@(pre, args))
  end
else optn_nil()
)//endof[rturn_tail_args(ical,icmp)]
//
(*
[params_of_fjarglst]: collect the function's parameter temps in order --
the i1tnm of each I1BNDcons across every FJARGdarg.  These are the Go
parameter names (goxtnm<stamp>) reassigned at a tail self-call.
*)
fun
bnds_tnms
(i1bs: i1bndlst): i1tnmlst =
(
case+ i1bs of
|list_nil() => list_nil()
|list_cons(ibnd, i1bs1) =>
  let val-I1BNDcons(itnm, _, _) = ibnd
  in list_cons(itnm, bnds_tnms(i1bs1)) end
)
//
#implfun
params_of_fjarglst
(fjas) =
(
case+ fjas of
|list_nil() => list_nil()
|list_cons(fja1, fjas1) =>
  let
    val-FJARGdarg(i1bs) = fja1.node()
    val ps1 = bnds_tnms(i1bs)
    val ps2 = params_of_fjarglst(fjas1)
  in
    list_append(ps1, ps2)
  end
)//endof[params_of_fjarglst(fjas)]
//
(*
[i1cmp_body_has_tailcall]: does a FUNCTION-BODY cmp contain a reachable
TAIL self-call?  We walk the RETURN-position structure:
  - an I1INSrturn(ical, inner) is a tail self-call iff i1cmp_tailq(inner, ical);
  - it can sit directly in the body (a tail `fun f = g(...)`) or inside an
    if/case branch body (the common `fun f = if ... then ... else f(...)`),
    so we descend into I1INSift0/I1INScas0 branch cmps (themselves wrapping
    their own I1INSrturn);
  - a let-in (I1INSlet0) body is also return-position when the let-in is the
    function tail, so we descend there too.
Plain value-position lets (the arg pre-computation, op timps, etc.) are
NOT return-position, so they are not searched for tail calls (a tail call
only ever appears under an I1INSrturn).
*)
fun
has_tc_cmp
(icmp: i1cmp): bool =
let
  val-I1CMPcons(ilts, _) = icmp
in
  has_tc_lets(ilts)
end
//
and
has_tc_lets
(ilts: i1letlst): bool =
(
case+ ilts of
|list_nil() => false
|list_cons(il1, ilts1) =>
  lor(has_tc_let(il1), has_tc_lets(ilts1))
)
//
and
has_tc_let
(ilet: i1let): bool =
(
case+ ilet of
|I1LETnew0(iins) => has_tc_ins(iins)
|I1LETnew1(_, iins) => has_tc_ins(iins)
)
//
and
has_tc_ins
(iins: i1ins): bool =
(
case+ iins of
//
|I1INSrturn(ical, inner) =>
  (
  if i1cmp_tailq(inner, ical) then true else has_tc_cmp(inner))
//
|I1INSift0(_, othn, oels) =>
  lor(has_tc_cmpopt(othn), has_tc_cmpopt(oels))
//
|I1INScas0(_, _, icls) => has_tc_clss(icls)
//
|I1INSlet0(_, inner) => has_tc_cmp(inner)
//
| _(*else*) => false
)
//
and
has_tc_cmpopt
(ocmp: i1cmpopt): bool =
(
case+ ocmp of
|optn_nil() => false
|optn_cons(icmp) => has_tc_cmp(icmp)
)
//
and
has_tc_clss
(icls: i1clslst): bool =
(
case+ icls of
|list_nil() => false
|list_cons(ic1, ics1) =>
  (
  case+ ic1.node() of
  |I1CLSgpt(_) => has_tc_clss(ics1)
  |I1CLScls(_, icmp) => lor(has_tc_cmp(icmp), has_tc_clss(ics1)))
)
//
#implfun
i1cmp_body_has_tailcall
(icmp) = has_tc_cmp(icmp)
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== (3) FUNCTION-SIGNATURE TYPING  (milestone M2.2, Regime B)          ==
=======================================================================
//
A named function's d2cst carries the FULL function static type
[d2cst_get_styp] = T2Pfun1(f2clknd, npf, args, res) (possibly under
quantifiers/instantiation wrappers).  [gotypes_of_funstyp] chases through
those wrappers to the T2Pfun1, drops the leading [npf] PROOF args (erased),
and maps each remaining VALUE arg + the result through [gotype_of_styp] to
a concrete Go type (or "any" where not recoverable).  This is what makes a
user function's emitted Go signature concrete where the source type is a
scalar -- the Regime-B payoff for functions.
*)
//
(*
[chase_fun]: strip the wrappers the front-end leaves around a function
type (quantifiers, instantiation, init/linear/lvalue markers) down to the
underlying T2Pfun1, returning [optn] of (npf, args, res).
*)
fun
chase_fun
(t2p0: s2typ): optn(@(sint, s2typlst, s2typ)) =
(
case+ t2p0.node() of
|T2Pfun1(_, npf, args, res) => optn_cons(@(npf, args, res))
//
|T2Puni0(_, t2p1) => chase_fun(t2p1)
|T2Pexi0(_, t2p1) => chase_fun(t2p1)
|T2Papps(t2p1, _) => chase_fun(t2p1)
|T2Plam1(_, t2p1) => chase_fun(t2p1)
//
|T2Ptop0(t2p1) => chase_fun(t2p1)
|T2Ptop1(t2p1) => chase_fun(t2p1)
|T2Plft (t2p1) => chase_fun(t2p1)
|T2Pnone1(t2p1) => chase_fun(t2p1)
//
| _(*otherwise*) => optn_nil()
)
//
(*
[drop_pf]: drop the leading [npf] proof args from the arg list (erased at
runtime, so they have no Go parameter).
*)
fun
drop_pf
(npf: sint, args: s2typlst): s2typlst =
(
if
(npf <= 0)
then args
else
(
case+ args of
|list_nil() => args
|list_cons(_, args1) => drop_pf(npf-1, args1))
)
//
(*
[gotypes_of_args]: map each VALUE-arg static type to its Go type, chasing
the call-by-value/ref arg wrappers (T2Parg1/T2Patx2) down to the carried
type first.
*)
fun
gotype_of_arg
(t2p0: s2typ): strn =
(
case+ t2p0.node() of
|T2Parg1(_, t2p1) => gotype_of_arg(t2p1)
|T2Patx2(t2p1, _) => gotype_of_arg(t2p1)
| _(*otherwise*) => gotype_of_styp(t2p0)
)
//
fun
gotypes_of_args
(args: s2typlst): list(strn) =
(
case+ args of
|list_nil() => list_nil()
|list_cons(a1, args1) =>
  list_cons(gotype_of_arg(a1), gotypes_of_args(args1))
)
//
#implfun
gotypes_of_funstyp
(styp) =
(
case+ chase_fun(styp) of
|optn_nil() => @(list_nil(), "any")
|optn_cons(@(npf, args, res)) =>
  let
    val args1 = drop_pf(npf, args)
  in
    @(gotypes_of_args(args1), gotype_of_styp(res))
  end
)
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== (4) CLOSURE TYPING  (milestone M2.5)                              ==
=======================================================================
//
A lambda ([I1INSlam0]) / local recursive closure ([I1INSfix0]) has NO
d2cst carrying its function static type (it is anonymous), so we recover
the Go param types from each PARAMETER d2var's own static type
([d2var_get_styp] on the [I0Pvar] the [i1bnd] pattern carries), and the
RESULT type from the lambda body's result value ([gotype_of_lam_ret],
which unwraps the canonical [I1INSrturn] and types the inner cmp's result
via [gotype_of_cmp]).  Both fall back to "any" where unrecoverable
(documented), but for the scalar surface the parameter types ARE concrete
(so the body's native `(x OP y)` ops type-check) -- the Regime-B payoff.
*)
//
(*
[gotype_of_param_bnd]: the Go type of one lambda/fix parameter, from the
bind's pattern.  For [I0Pvar(d2var)] we read [d2var_get_styp] (the param's
inferred static type) and map it via [gotype_of_styp]; anything else -> "any".
*)
fun
gotype_of_param_bnd
(ibnd: i1bnd): strn =
let
  val-I1BNDcons(_, ipat, _) = ibnd
in
  case+ ipat.node() of
  |I0Pvar(d2v) => gotype_of_styp(d2var_get_styp(d2v))
  | _(*else*) => "any"
end
//
fun
gotypes_of_bnds
(i1bs: i1bndlst): list(strn) =
(
case+ i1bs of
|list_nil() => list_nil()
|list_cons(ibnd, i1bs1) =>
  list_cons(gotype_of_param_bnd(ibnd), gotypes_of_bnds(i1bs1))
)
//
(*
[gotypes_of_fjarglst]: the Go param-type list (in order) of a lambda/fix's
[fjarglst], one entry per [i1bnd] across every [FJARGdarg].  Parallel to
[params_of_fjarglst] (which gives the param i1tnms), so the emitter zips
the two to print `goxtnm<stamp> <T>`.
*)
#implfun
gotypes_of_fjarglst
(fjas) =
(
case+ fjas of
|list_nil() => list_nil()
|list_cons(fja1, fjas1) =>
  let
    val-FJARGdarg(i1bs) = fja1.node()
    val ts1 = gotypes_of_bnds(i1bs)
    val ts2 = gotypes_of_fjarglst(fjas1)
  in
    list_append(ts1, ts2)
  end
)//endof[gotypes_of_fjarglst(fjas)]
//
(*
[gotype_of_lam_ret]: the Go RESULT type of a lambda/fix body cmp, given the
in-scope param binds [bnds] (the lambda's OWN params + every enclosing
function/lambda's params, accumulated as the emitter descends).  Delegates to
the [bnds]-threaded [gotype_of_lam_ret2] (defined in the recovery [and]-chain
above) so a body that returns a captured/param var or a nested lambda is typed
to its concrete Go type instead of "any" (M2.5 BUG-1).
*)
#implfun
gotype_of_lam_ret
(icmp, bnds) = gotype_of_lam_ret2(icmp, bnds)
//
(*
[goretty_of_funvar]: the Go RESULT type of a NAMED function/closure value
(a fix-var), read from its function static type [d2var_get_styp] ->
T2Pfun1(...; res) -> [gotype_of_styp res].  For a local recursive closure
[I1INSfix0] this is more reliable than [gotype_of_lam_ret] (whose if/case-
bodied recursive form has both branches returning computed temps the i1val
level cannot type) -- the declared signature pins the result type.  Returns
"any" when the styp is not a recognizable function type.
*)
#implfun
goretty_of_funvar
(dvar) =
(
case+ chase_fun(d2var_get_styp(dvar)) of
|optn_nil() => "any"
|optn_cons(@(_, _, res)) => gotype_of_styp(res)
)//endof[goretty_of_funvar(dvar)]
//
(*
[goargtys_of_funvar]: the Go VALUE-arg type list of a named function/closure
value (a fix-var), from its function static type (proof args dropped).  Used
alongside [goretty_of_funvar] to build the fix0 `var f func(...)...`
self-reference type from the declared signature (robust when the param
patterns' own d2var styps are less precise).  Empty list if not a fun type.
*)
#implfun
goargtys_of_funvar
(dvar) =
(
case+ chase_fun(d2var_get_styp(dvar)) of
|optn_nil() => list_nil()
|optn_cons(@(npf, args, _)) => gotypes_of_args(drop_pf(npf, args))
)//endof[goargtys_of_funvar(dvar)]
//
(*
[gofunctype_of_fjarglst]: the Go FUNCTION-TYPE string `func(T0, T1) Tret`
for a lambda/fix with the given param types [argtys] and result type [retty].
Used to pre-declare a self-referential local recursive closure
(`var goxtnm<f> func(...)...`) so the func literal can name itself
([I1INSfix0], Go's `var f F; f = func(){... f() ...}` idiom).
*)
#implfun
gofunctype_of_fjarglst
(argtys, retty) =
let
  fun
  loop
  (i0: sint, ts: list(strn)): strn =
  (
  case+ ts of
  |list_nil() => ""
  |list_cons(t1, ts1) =>
    (
    if (i0 >= 1)
    then strn_append(strn_append(", ", t1), loop(i0+1, ts1))
    else strn_append(t1, loop(i0+1, ts1)))
  )
  val args = loop(0, argtys)
in
  strn_append(strn_append(strn_append("func(", args), ") "), retty)
end//endof[gofunctype_of_fjarglst(argtys,retty)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_go1emit_styp0.dats] *)
(***********************************************************************)
