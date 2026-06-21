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
go1emit — the intrep1 -> Go text emitter (milestone M1).
//
M1 ("Hello World" walking skeleton): [i1parsed_go1emit] now genuinely
TRAVERSES the intrep1 IR (i1dclistopt -> i1dclist -> i1dcl ->
I1Dvaldclst -> i1valdcl -> i1cmp -> i1let -> i1ins -> i1val) for the
simplest meaningful program (a top-level [val () = strn_print("...")]
plus a [the_print_store_log()] flush) and emits real, runnable Go that
prints the SAME BYTES as the JS backend. Structure mirrors the js1emit
file split (utils0/dynexp/decl00). Nodes outside test01's needs emit
[// UNHANDLED: <ctor>] AND a stderr [prerrln] (never silently-wrong Go).
*)
//
(* ****** ****** *)
(* ****** ****** *)
//
#include
"./../../..\
/HATS/xatsopt_sats.hats"
//
(* ****** ****** *)
//
#staload "./intrep1.sats"
#staload "./xats2go.sats"
//
#staload
"./../../../SATS/statyp2.sats"
//
#staload
".\
/../../../xats2cc\
/srcgen1/SATS/intrep0.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
// --- liveness + s2typ->Go-type scaffold (go1emit_styp0.dats) -------------
//
// i1tnm_used_in_cmp: is the temp [itnm] referenced (as an I1Vtnm) anywhere
// in [icmp]?  Drives the clean I1LETnew1 emission (live -> bind; dead ->
// `_ = <ins>`).  See go1emit_styp0.dats.
//
fun
i1tnm_used_in_cmp
(itnm: i1tnm, icmp: i1cmp): bool
//
// gotype_of_styp / gotype_of_ival: the M2.0 scalar Go-type scaffold.  Both
// return a Go type name (int/bool/rune/float64/string) for the cases they
// can recognize, "any" otherwise.  M2.1 wires them to scalar emission.
//
fun
gotype_of_styp
(t2p0: s2typ): strn
fun
gotype_of_ival
(ival: i1val): strn
//
// gofield_of_label: the Go FIELD NAME for a tuple/record label (M2.6b).  A
// positional tuple label LABint(i) -> "F<i>"; a record label LABsym(s) ->
// "F<s>".  This is the SINGLE definition of the field-name scheme, shared by
// the type translation (gotype_of_i0typ/styp's struct arm) and the emitter's
// projection sites (v.F<lab>), so a construction site's struct type and every
// projection cannot disagree.
//
fun
gofield_of_label
(lab0: label): strn
//
// gotrcd_of_tnm: the construction-site side-table lookup (M2.6b).  Given a
// result temp's STAMP, if its recorded i0typ is a tuple/record, return
// optn_cons(@(isFlat, structBody)) where [structBody] is the Go `struct{...}`
// type WITHOUT the leading `*` (the construction emitter writes a flat value
// literal `struct{...}{...}` or a boxed pointer literal `&struct{...}{...}`),
// and [isFlat] = trcdknd_fltq.  optn_nil when not recorded / not a tuple.
//
fun
gotrcd_of_tnm
(stmp: stamp): optn(@(bool, strn))
//
// i1binop_of_dapp: given an I1INSdapp's callee + args + the enclosing cmp
// (op-resolution scope), return the native Go binary operator string
// ("+","-","<","==",...) iff the call should be emitted as native infix
// `(a OP b)`; "" otherwise (keep the runtime call).  This is the Regime-B
// primop payoff: scalar arithmetic/compare emits native Go operators.
//
fun
i1binop_of_dapp
(callee: i1val, args: i1valist, scp: i1cmp): strn
//
// i1ins_is_native_op: true iff this instruction is an I1INStimp resolving
// to a native-able scalar op (so its op-temp binding can drop to `_ = ...`).
//
fun
i1ins_is_native_op
(iins: i1ins): bool
//
// --- function-signature typing (M2.2, Regime B) --------------------------
//
// gotypes_of_funstyp: given a function d2cst's static type [styp]
// (T2Pfun1(_, npf, args, res) after chasing wrappers / quantifiers), return
// the Go arg-type list (one entry per VALUE arg, proof args dropped) and the
// Go result type.  Each entry is a Go type name (int/bool/rune/float64/
// string/any), so a recoverable scalar signature is concrete and the rest
// falls back to "any" (documented).  Returns (list_nil(), "any") when the
// type is not a recognizable function type.
//
fun
gotypes_of_funstyp
(styp: s2typ): @(list(strn), strn)
//
// --- control-flow helpers (M2.3) -----------------------------------------
//
// gotype_of_ift0type: the Go type to give a VALUE-position if/case/let
// result temp, recovered from the branch/clause RESULT i1vals
// (gotype_of_ival); "any" when no branch result types concretely.
//
fun
gotype_of_ift0type
(iins: i1ins): strn
//
// gotype_of_init_cmp (M2.6c): the Go type to DECLARE a mutable `var x = init`
// with -- the type of the init cmp's RESULT.  A tuple/record init yields its
// recorded struct type (flat VALUE `struct{...}` / boxed POINTER `*struct{...}`),
// so the var is value-typed for flat / pointer-typed for boxed -- which is what
// makes a field assignment realize flat=value vs boxed=shared semantics.  "any"
// when the init result's type is unrecoverable.
//
fun
gotype_of_init_cmp
(icmp: i1cmp): strn
//
// i1ins_fully_returnsq: true iff this if/case instruction is in RETURN
// position -- every present branch body ends in an I1INSrturn
// (i1cmp_retq).  Then branches emit their own `return` and no result temp
// is pre-declared (the recursion/return-mode crux).  false => value
// position (pre-declare a temp; branches assign to it).  Always false for
// I1INSlet0 (a let-in yields a value, not a return).
//
fun
i1ins_fully_returnsq
(iins: i1ins): bool
//
// i1ins_is_blockform: true iff this instruction emits as a multi-statement
// Go block (if / switch / let-block) rather than a single expression, so
// the I1LETnew0/1 emitter drives it specially (pre-declared temp + branch
// bodies) instead of the `goxtnm := <expr>` single-line form.
//
fun
i1ins_is_blockform
(iins: i1ins): bool
//
// i1ins_is_construct (M2.6b): true iff this instruction is a tuple/record
// CONSTRUCTION (I1INStup0 / I1INStup1 / I1INSrcd2).  Such an ins emits as a
// single-line Go struct literal `<structtype>{...}` (flat VALUE) or
// `&<structtype>{...}` (boxed POINTER), but the struct TYPE is recovered from
// the BINDING result temp's side-table entry -- so the I1LETnew1 emitter must
// route it to [i1trcd_construct_go1emit] (which has the temp), NOT to the
// generic [i1insgo1] (which has no temp and would emit `UNHANDLED nil`).
//
fun
i1ins_is_construct
(iins: i1ins): bool
//
// i1trcd_construct_go1emit (M2.6b): emit a tuple/record construction's RHS
// expression -- a flat VALUE struct literal `<structtype>{v0, v1, ...}` or a
// boxed POINTER literal `&<structtype>{v0, v1, ...}` -- where [otnm] is the
// BINDING result temp (its recorded i0typ supplies the struct type, via the
// M2.6a side-table, identical to what every projection root computes).  Emits
// ONLY the RHS (the caller emits the `goxtnm := ` / `_ = ` binding prefix).
//
fun
i1trcd_construct_go1emit
(filr: FILR, otnm: i1tnm, iins: i1ins): void
//
// i1cmp_tail_returns: does the cmp already return on every path, so a
// result-mode emitter must NOT append a trailing `return`/`= result`?
// Strictly stronger than the stock i1cmp_retq: ALSO true when the last let
// is I1LETnew1(tnm, fully-returning ift0/cas0) and the cmp result is
// I1Vtnm(tnm) -- exactly how a recursive `fun = if...` body lowers (the
// recursion crux; i1cmp_retq misses it because that form is I1LETnew1).
//
fun
i1cmp_tail_returns
(icmp: i1cmp): bool
//
(* ****** ****** *)
(* ****** ****** *)
//
// --- M2.4 tail-call optimization (TCO) helpers ---------------------------
//
// params_of_fjarglst: collect the function's parameter temps (the i1tnm of
// each I1BNDcons across every FJARGdarg) IN ORDER.  These are the Go param
// names (goxtnm<stamp>) reassigned at a tail self-call (positionally with
// the call's args).
//
fun
params_of_fjarglst
(fjas: fjarglst): i1tnmlst
//
// rturn_tail_args: when an I1INSrturn's body [icmp] is a TAIL self-call to
// the function identified by [ical] (i1cmp_tailq), return [optn_cons(args)]
// where [args] are the call's argument i1vals (the NEW parameter values, in
// positional order) AND [ilts] are the lets that PRECEDE the tail call (the
// ANF pre-computation of each new arg into its own temp -- emitting these
// FIRST is what makes the parameter reassignment simultaneity-safe).  When
// [icmp] is not a tail self-call, returns optn_nil() (the caller emits a
// plain `return`).
//
fun
rturn_tail_args
(ical: i0cal, icmp: i1cmp): optn(@(i1letlst, i1valist))
//
// i1cmp_body_has_tailcall: does this FUNCTION-BODY cmp contain a reachable
// TAIL self-call (an I1INSrturn whose body is i1cmp_tailq) anywhere down its
// return-position structure (the top rturn, or an if/case branch's rturn)?
// True => the function body must be wrapped in a Go `for { ... }` loop so the
// tail call becomes `param = newval; continue` instead of a recursive call.
//
fun
i1cmp_body_has_tailcall
(icmp: i1cmp): bool
//
(* ****** ****** *)
(* ****** ****** *)
//
// --- M2.5 closure typing helpers -----------------------------------------
//
// gotypes_of_fjarglst: the Go param-type list (in order) of a lambda/fix's
// fjarglst -- one entry per i1bnd, recovered from each parameter d2var's
// static type (d2var_get_styp via I0Pvar), "any" where unrecoverable.
// Parallel to params_of_fjarglst (the param i1tnms), so the emitter zips the
// two to print `goxtnm<stamp> <T>`.
//
fun
gotypes_of_fjarglst
(fjas: fjarglst): list(strn)
//
// binds_of_fjarglst: collect the parameter binds (the i1bnd of each I1BNDcons
// across every FJARGdarg) of a lambda/fix's fjarglst.  Accumulated into the
// in-scope bind environment threaded into gotype_of_lam_ret so a lambda body
// that returns a captured/param var resolves that var's declared static type
// (d2var_get_styp) instead of "any" (M2.5 BUG-1).
//
fun
binds_of_fjarglst
(fjas: fjarglst): i1bndlst
//
// gotype_of_lam_ret: the Go result type of a lambda/fix body cmp, given the
// in-scope param binds [bnds] (own params + enclosing captures) -- unwraps the
// canonical I1INSrturn and types the inner cmp's result; a result that is a
// free param/capture is typed from [bnds] (its d2var_get_styp), a result that
// is a NESTED lambda is typed to its concrete Go func(...)... type; "any" only
// where genuinely unrecoverable (M2.5).
//
fun
gotype_of_lam_ret
(icmp: i1cmp, bnds: i1bndlst): strn
//
// gofunctype_of_fjarglst: the Go function-TYPE string `func(T0, T1) Tret`
// from the recovered param types + result type.  Used to pre-declare a
// self-referential local recursive closure (I1INSfix0): `var goxtnm<f>
// func(...)...; goxtnm<f> = func(...){ ... goxtnm<f>(...) ... }`.
//
fun
gofunctype_of_fjarglst
(argtys: list(strn), retty: strn): strn
//
// goretty_of_funvar / goargtys_of_funvar: the Go RESULT type / VALUE-arg
// type-list of a NAMED function/closure value (a fix-var), read from its
// function static type (d2var_get_styp -> T2Pfun1).  For a local recursive
// closure (I1INSfix0) the DECLARED signature pins the result+arg types more
// reliably than inferring from the if/case-bodied body, so the emitted Go
// func type is concrete (not `any`).  "any" / nil when not a fun type.
//
fun
goretty_of_funvar
(dvar: d2var): strn
fun
goargtys_of_funvar
(dvar: d2var): list(strn)
//
(* ****** ****** *)
(* ****** ****** *)
//
// --- naming / leaf emission (go1emit_utils0.dats) ------------------------
//
fun
d2cstgo1
(filr:FILR, dcst: d2cst): void
fun
d2vargo1
(filr:FILR, dvar: d2var): void
//
fun
i1tnmgo1
(filr:FILR, itnm:i1tnm): void
//
fun
i0strgo1
(filr:FILR, tstr:token): void
fun
i0s00go1
(filr:FILR, str0:strn): void
//
// scalar literals -> concrete Go literal syntax (M2.1).  Each token form
// (I1Vint/chr/flt/btf) and each evaluated form (I1Vi00/c00/f00/b00) emits
// a native Go literal of the matching concrete type (int/rune/float64/bool).
//
fun
i0intgo1
(filr:FILR, tint:token): void
fun
i0i00go1
(filr:FILR, i00:sint): void
//
fun
i0btfgo1
(filr:FILR, btf0:sym_t): void
fun
i0b00go1
(filr:FILR, b00:bool): void
//
fun
i0chrgo1
(filr:FILR, tchr:token): void
fun
i0c00go1
(filr:FILR, c00:char): void
//
fun
i0fltgo1
(filr:FILR, tflt:token): void
fun
i0f00go1
(filr:FILR, f00:dflt): void
//
(* ****** ****** *)
//
fun
i1valgo1
(filr:FILR, ival:i1val): void
//
(* ****** ****** *)
(* ****** ****** *)
//
// --- the IR-walk (go1emit_dynexp.dats + go1emit_decl00.dats) -------------
//
fun
i1parsed_go1emit
(ipar: i1parsed, filr: FILR): void
//
(* ****** ****** *)
//
fun
i1dclistopt_go1emit
(dopt: i1dclistopt, env0: !envx2go): void
fun
i1dclist_go1emit
(dcls: i1dclist, env0: !envx2go): void
fun
i1dcl_go1emit
(dcl0: i1dcl, env0: !envx2go): void
//
// PASS-1 (package-level function) walkers -- emit ONLY I1Dfundclst nodes
// at package scope (Go requires top-level `func` declarations).  The
// in-main pass (i1dcl_go1emit) SKIPS I1Dfundclst.
//
fun
i1dclistopt_go1emit_funs
(dopt: i1dclistopt, env0: !envx2go): void
fun
i1dclist_go1emit_funs
(dcls: i1dclist, env0: !envx2go): void
fun
i1dcl_go1emit_fun
(dcl0: i1dcl, env0: !envx2go): void
//
(* ****** ****** *)
//
fun
i1valdclist_go1emit
(i1vs: i1valdclist, env0: !envx2go): void
fun
i1valdcl_go1emit
(ival: i1valdcl, env0: !envx2go): void
//
// i1vardclist_go1emit / i1vardcl_go1emit (M2.6c): emit a mutable-local group
// `var x = init` as Go `var goxtnm<x> <T> = <init>` (addressable -> its fields
// are assignable lvalues).  See go1emit_decl00.dats.
//
fun
i1vardclist_go1emit
(i1vs: i1vardclist, env0: !envx2go): void
fun
i1vardcl_go1emit
(ivar: i1vardcl, env0: !envx2go): void
//
(* ****** ****** *)
//
fun
i1cmp_go1emit
(icmp: i1cmp, env0: !envx2go): void
//
// i1cmp_go1emit_ret: emit an i1cmp in FUNCTION-BODY (return) mode -- the
// let-bindings as Go statements, then `return <result>`.  Distinct from
// i1cmp_go1emit (top-level effect cmp), which discards its result.  The
// body of a non-recursive [fun] surfaces as a single
// I1LETnew0(I1INSrturn(i0cal, innerCmp)); we unwrap that rturn so the inner
// cmp's lets emit and its result becomes the `return`.
//
// [params] (M2.4 TCO): the enclosing function's parameter temps, threaded
// down the whole return-position chain.  When NON-empty AND an unwrapped
// I1INSrturn is a TAIL self-call (rturn_tail_args), the call is emitted as
// `goxtnm<param_i> = <newarg_i>; continue` (the function body is wrapped in
// a Go `for { }` loop) instead of `return f(...)` -- O(1) stack.  An EMPTY
// [params] disables TCO (the M2.3 plain-return behavior); pass list_nil()
// for a non-tail-recursive function body or a value-position context.
//
// [bnds] (M2.5): the in-scope parameter binds (the enclosing function's + every
// enclosing lambda's params), threaded so a lambda emitted in this body can
// recover the Go type of a body that RETURNS a captured/param var (its
// d2var_get_styp) or a nested lambda -- otherwise that lambda's return type
// degrades to "any" and collides with the enclosing concrete signature.
//
fun
i1cmp_go1emit_ret
(icmp: i1cmp, params: i1tnmlst, bnds: i1bndlst, env0: !envx2go): void
//
// i1cmp_go1emit_tnm: emit an i1cmp in ASSIGN-TO-TEMP (value-position
// branch) mode -- the let-bindings as Go statements, then `goxtnm<itnm> =
// <result>` UNLESS the cmp already returns (i1cmp_retq: a branch whose body
// itself ends in a return needs no assignment).  This is the Go analog of
// js1emit's f0_i1tnmcmp; it is how an if/case BRANCH in value position binds
// its result into the pre-declared result var.
//
fun
i1cmp_go1emit_tnm
(itnm: i1tnm, icmp: i1cmp, env0: !envx2go): void
//
// i1fundclist_go1emit / i1fundcl_go1emit: emit user-defined functions
// (I1Dfundclst) as Go `func <name>(<params>) <ret> { <body> }`.  [d2cs] is
// the parallel d2cstlst (positional with the fundclist) carrying each
// function's static type, used to recover concrete arg/result Go types.
//
fun
i1fundclist_go1emit
(i1fs: i1fundclist, d2cs: d2cstlst, env0: !envx2go): void
fun
i1fundcl_go1emit
(ifun: i1fundcl, dcstopt: optn(d2cst), env0: !envx2go): void
//
// [scp] is the ENCLOSING i1cmp -- the liveness scope.  An I1LETnew1's
// tnm is bound cleanly iff it is used somewhere in [scp]; threading the
// scope (rather than recomputing) keeps the query O(lets x cmp-size).
//
fun
i1letlst_go1emit
(ilts: i1letlst, scp: i1cmp, env0: !envx2go): void
fun
i1let_go1emit
(ilet: i1let, scp: i1cmp, env0: !envx2go): void
//
// [_p] variants: as above but thread the TCO [params] (M2.4) so a
// return-position block-form (a trailing if/case in a FUNCTION BODY) routes
// its branch bodies in tail-loop mode.  The plain variants delegate with
// params = list_nil() (no TCO).  Declared here so the forward references in
// the plain variants' bodies resolve.
//
fun
i1letlst_go1emit_p
(ilts: i1letlst, scp: i1cmp, params: i1tnmlst, bnds: i1bndlst, env0: !envx2go): void
fun
i1let_go1emit_p
(ilet: i1let, scp: i1cmp, params: i1tnmlst, bnds: i1bndlst, env0: !envx2go): void
//
// emit_ret_plain / emit_param_reassign (M2.4): the plain-return path (unwrap
// the canonical I1INSrturn, emit lets + `return`, threading [params] to a
// trailing return-position if/case) and the tail-call parameter reassignment
// (`goxtnm<p_i> = <newarg_i>` per param).  Declared so i1cmp_go1emit_ret's
// forward references resolve.
//
fun
emit_ret_plain
(icmp: i1cmp, params: i1tnmlst, bnds: i1bndlst, env0: !envx2go): void
fun
emit_param_reassign
(params: i1tnmlst, args: i1valist, env0: !envx2go): void
//
fun
i1insgo1
(filr: FILR, scp: i1cmp, iins: i1ins): void
//
(* ****** ****** *)
//
// --- M2.3 control-flow block emission (if / case / let-in) ---------------
//
// i1ins_go1emit_block: emit a BLOCK-FORM instruction (I1INSift0 / I1INScas0
// / I1INSlet0) bound to result temp [itnm].  Picks return-position (each
// branch returns; no result temp) vs value-position (pre-declare a temp;
// branches assign) via i1ins_fully_returnsq.  [scp] is the liveness scope.
// [params] (M2.4 TCO) is threaded to the return-position branch bodies (so a
// tail self-call in a branch becomes a loop continue); empty disables TCO.
//
fun
i1ins_go1emit_block
(scp: i1cmp, itnm: i1tnm, iins: i1ins, params: i1tnmlst, bnds: i1bndlst, env0: !envx2go): void
//
// i1clslst_go1emit / i1cls_go1emit: emit case clauses onto Go's expression-
// less switch.  [retq] = return-position (branch returns) vs value-position
// (assign to [itnm]); [live] = whether the value-position result temp is
// read downstream; [casval] = the scrutinee i1val the patterns test against.
// [params] (M2.4 TCO) threads to return-position clause bodies; empty = off.
//
fun
i1clslst_go1emit
( retq: bool, live: bool, itnm: i1tnm
, casval: i1val, icls: i1clslst, params: i1tnmlst, bnds: i1bndlst, env0: !envx2go): void
fun
i1cls_go1emit
( retq: bool, live: bool, itnm: i1tnm
, casval: i1val, icl0: i1cls, params: i1tnmlst, bnds: i1bndlst, env0: !envx2go): void
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_SATS_go1emit.sats] *)
(***********************************************************************)
