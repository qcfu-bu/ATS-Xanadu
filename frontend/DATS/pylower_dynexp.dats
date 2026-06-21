(* ****** ****** *)
(*
** M3 — Python-surface frontend: expression/pattern/literal lowering (pcexp/pcpat/pclit
** -> d2exp/d2pat). The functional core (LOOP-DESUGARING §2): a straight structural map,
** mirroring the trans12_dynexp.dats templates (LOWERING-MAP §4) against a live tr12env.
**
** Templates mirrored:
**   A identifier-ref  (trans12_dynexp.dats f0_id0_d2itm, 1920-2105)
**   B application     (trans12_dynexp.dats, d2exp_dapp npf=-1)
**   D lambda          (trans12_dynexp.dats f0_lam0, 3242-3282)
**   E let/block       (trans12_dynexp.dats, push/pop a let scope)
**   F fun group       (trans12_decl00.dats f0_fundclst, 2902-3032)
**
** LITERALS are TOKEN-based (D2Eint/D2Eflt/D2Estr/D2Echr/D2Ebtf via token_make_node) — the
** only form proven through codegen (LOWERING-MAP §2.1, M0b §5.5). NEVER the unboxed D2E*00.
** REAL Python loctn threaded into every node (the type error lands on the .py span).
**
** ATS3-dialect structure rule (M2.5 Δ3, pyelab_core.dats preamble): an `#implfun` must NOT
** head a `fun ... and ...` group with non-#impl helpers. So the mutually-recursive workers
** are plain `fun pl_* / and ...`, and the SATS entries are thin `#implfun` wrappers at the
** end. Helpers used by the group are defined BEFORE it (token makers, literal lowering).
**
** PURELY ADDITIVE; consumes pycore.sats/pyparsing.sats read-only.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
#staload "./../../srcgen2/SATS/lexing0.sats"
//
// libxatsopt.hats staloads dynexp2 but NOT dynexp1; we need d1exp_make_node / D1Eid0 for the
// operator-overload (D2ITMsym) arm of template A (d2exp_sym0's d1exp proxy).
#staload "./../../srcgen2/SATS/dynexp1.sats"
// M5a: type-annotation carrying. D2Pannot/D2Eannot carry a `s1exp` "given" part; libxatsopt
// staloads neither staexp1 (s1exp) — we need s1exp_none0 as the benign given-part placeholder
// (trans2a/trans23 type FROM the s2exp, never the s1exp; verified trans2a_dynexp f0_annot).
#staload "./../../srcgen2/SATS/staexp1.sats"
//
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pylower.sats"
//
(* ****** ****** *)
//
// the `val`/`=` token reused for synthesized binding tokens (its lexeme is irrelevant to
// trans23; only its presence/kind matters). A LAM token for lambdas; a FUN token for groups.
//
fun tok_val(loc: loctn): token = token_make_node(loc, T_VAL(VLKval))
fun tok_lam(loc: loctn): token = token_make_node(loc, T_LAM(0(*lam0*)))
fun tok_fun(loc: loctn): token = token_make_node(loc, T_FUN(FNKfn2(*tailrec*)))
// the `var` kind-token for D2Cvardclst (ATS-parity var/mutation). VRKvar is the only var
// kind (xbasics.sats:184). trans23 only destructures the token's kind, not its lexeme.
fun tok_var(loc: loctn): token = token_make_node(loc, T_VAR(VRKvar))
// the `case` kind-token for D2Ecas0: CSKcas0 = warning-only on non-exhaustiveness (suits the
// desugared-loop flow dispatch, which is not exhaustive over all flow ctors).
fun tok_case(loc: loctn): token = token_make_node(loc, T_CASE(CSKcas0))
// the record kind-token for D2Ercd2/D2Prcd2: trans23 f0_rcd2 does a PARTIAL `case-` over
// T_TRCD20(n) ONLY (trans23_dynexp.dats:2230-2242 / 240) — a T_LBRACE token CRASHES it
// (inexhaustive match). T_TRCD20(0) selects TRCDflt0, the FLAT (unboxed) record `@{...}` the
// Pythonic `{l=e,...}` lowers to. (Verified: T_LBRACE -> hard crash in trans23_d2valdcl.)
fun tok_rec(loc: loctn): token = token_make_node(loc, T_TRCD20(0))
// EXN: the `$raise`/`try` kind-tokens for D2Eraise/D2Etry0 (the tknd is only destructured by
// trans23 — its presence/kind is what matters, not the lexeme). The stock parser builds
// D2Eraise with a T_DLR_RAISE token and D2Etry0 with a T_TRY token (SPIKE-PROVEN).
fun tok_raise(loc: loctn): token = token_make_node(loc, T_DLR_RAISE())
fun tok_try(loc: loctn): token = token_make_node(loc, T_TRY())
//
(* ****** ****** *)
//
// ---- literals -> token-based L2 leaves (LOWERING-MAP §2.1) ------------------
//
// STYP-STAMPING (M4): the directly-constructed L2 leaf carries its own `styp` field; trans23's
// `_tpck` (e.g. a `case`-guard checked against `bool`, or a literal in any checked position)
// unifies that field with the expected type. The from-FILE pipeline fills this field in the
// trans2a literal-type pass (trans2a_dynexp.dats f0_int/f0_btf/...), but `d3parsed_of_trans23`
// does NOT run trans2a (those passes live in trans03_from_fpath, NOT in d3parsed_of_trans23 —
// verified trans23.dats:89-90 vs :104-137; M3-REPORT §5.3's "internally runs trans2a" is wrong).
// So we MUST stamp it here — mirroring f0_*'s exact types — WITHOUT running the full trans2a
// pass (which would mutate the d2exp_none0 recovery nodes and silently kill the 4b unbound-name
// errck; the M4-recovery HARD LESSON). This is the minimal, targeted stamp: literals only.
//
fun
d2e_styp(d2e: d2exp, t2p: s2typ): d2exp = let val () = d2exp_set_styp(d2e, t2p) in d2e end
//
// VAL-BINDER STYP (M4): trans23_d2valdcl (trans23_decl00.dats:883) checks the val RHS against
// `dpat.styp()` (= the binder d2var's styp). The from-FILE pipeline gives every binder a fresh
// existential tyvar in trans2a (f0_var, 546-574) so the RHS type flows in; but
// `d3parsed_of_trans23` does NOT run trans2a, so our binder keeps styp T2Pnone0. With `none`, a
// CONCRETE-typed RHS (a tuple synthesizing `trcd`, an annotated value, ...) fails to unify
// `trcd-vs-none` -> a spurious errck (observed: `let p = (1,2,3)`).
//
// BUT a blanket fresh-tyvar binder REGRESSES the 4b unbound-name test: an unbound name lowers to
// `d2exp_none0` whose styp is `void`; with a `none` binder, `unify(void, none)` FAILS -> the
// errck that 4b counts; with a fresh tyvar, `void` unifies (xtv solves to void) -> the errck
// VANISHES (M4-recovery HARD LESSON: unbound-name detection is coupled to the `none` binder).
//
// So the fix is SELECTIVE: give the binder a fresh tyvar EXCEPT when the lowered RHS is the bare
// recovery node `D2Enone0` (an unbound name) — there we keep `none` so the errck survives. This
// preserves 4b verbatim while letting concrete-typed values bind to an untyped `let`/`val`.
//
fun
is_d2enone0(d2e: d2exp): bool =
  (case+ d2e.node() of D2Enone0() => true | _ => false)
//
#implfun
bind_let_styp(d2p, d2rhs) =
(
case+ d2p.node() of
| D2Pvar(d2v) =>
    if is_d2enone0(d2rhs) then ()  // unbound-name recovery: keep `none` so trans23 errcks (4b)
    else d2var_set_styp(d2v, s2typ_xtv(x2t2p_make_lctn(d2p.lctn())))
| _ => ()  // non-var patterns (tup/rec/con) carry their own structural styp already
)
//
// STYP NOTE (M4): only the BOOLEAN literal is styp-stamped. trans23 checks a `case`-guard
// expression against `bool` (trans23_dynexp.dats:3189 the_s2typ_bool) via `_tpck`, which
// unifies the node's OWN styp with `bool`; an unstamped D2Ebtf carries T2Pnone0 and fails to
// unify. Int/float/string/char literals are left UNSTAMPED on purpose: they flow in synthesis
// position (an untyped `let a = 7`, or a literal pattern unified against the scrutinee's
// inferred type), where a precise stamped type (e.g. the singleton `sint(7)` from
// intrep_s2typ_xint) would OVER-CONSTRAIN and spuriously fail unify23 against the inferred
// `none` slot — regressing m3_run's `let a = 7` (observed: sint0 vs none errck). Bool is the
// only literal trans23 checks against a fixed concrete type with no inference the other way.
//
fun
pl_lit(loc: loctn, lit: pclit): d2exp =
(
case+ lit of
| PCLint(_, s) =>
    d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01(s))))
| PCLflt(_, s) =>
    d2exp_make_node(loc, D2Eflt(token_make_node(loc, T_FLT01(s))))
| PCLstr(_, s) =>
    // the lexeme keeps the surrounding quotes verbatim; len counts them (lexing0 §note).
    d2exp_make_node(loc, D2Estr(token_make_node(loc, T_STRN1_clsd(s, strn_length(s)))))
| PCLchr(_, s) =>
    d2exp_make_node(loc, D2Echr(token_make_node(loc, T_CHAR2_char(s))))
| PCLbool(_, b) =>
    // true/false are boolean-literal nodes (D2Ebtf sym), NOT data constructors. STAMPED bool.
    d2e_styp(d2exp_make_node(loc, D2Ebtf(symbl_make_name(if b then "true" else "false"))), the_s2typ_bool())
)
//
(* ****** ****** *)
//
// ---- template A : identifier reference (no recursion) ----------------------
//
// resolve `sym` via tr12env_find_d2itm, branching on the d2itm exactly like
// trans12_dynexp.dats f0_id0_d2itm. The D2ITMsym (operator-overload) arm needs a synthetic
// d1exp = D1Eid0(sym) proxy + a fresh d2rxp for d2exp_sym0 (PROBE-VERIFIED: every arithmetic
// /comparison operator resolves to D2ITMsym). An unbound name yields d2exp_none0 (recovery).
//
fun
pl_var(env: !tr12env, loc: loctn, sym: sym_t): d2exp = let
  val dopt = tr12env_find_d2itm(env, sym)
in
  case+ dopt of
  // UNBOUND-NAME RECOVERY (#13a): emit the SAME node the stock trans12 emits — d2exp_none1(d1e0),
  // where d1e0 = D1Eid0(sym) carries the unresolved id (trans12_dynexp.dats:2003 f0_id0_d1sym's
  // else-branch). This is NOT a bare d2exp_none0: trans2a/trans23 have no D2Enone1 arm, so the node
  // falls through to their `_(*otherwise*)` recovery (-> D2Enone2 -> D3Enone1), and tread3a's
  // `_(*otherwise*)` COUNTS it (err+1) on the id's .py span (deliverable 4b). The old d2exp_none0
  // got `void`-stamped by trans2a + the binder's fresh tyvar then unified the errck AWAY (the
  // M4-recovery HARD LESSON); d2exp_none1 is immune to that because trans2a never rewrites it.
  | ~optn_vt_nil() => d2exp_none1(d1exp_make_node(loc, D1Eid0(sym)))
  | ~optn_vt_cons(d2i) =>
    (
      case+ d2i of
      | D2ITMvar(d2v)  => d2exp_var(loc, d2v)
      | D2ITMcon(d2cs) =>
          if list_singq(d2cs) then d2exp_con(loc, d2cs.head()) else d2exp_cons(loc, d2cs)
      | D2ITMcst(d2cs) =>
          if list_singq(d2cs) then d2exp_cst(loc, d2cs.head()) else d2exp_csts(loc, d2cs)
      | D2ITMsym(_, dpis) =>
          let
            val d1e0 = d1exp_make_node(loc, D1Eid0(sym))
            val drxp = d2rxp_new1(loc)
          in
            d2exp_sym0(loc, drxp, d1e0, dpis)
          end
    )
end
//
// resolve a bare CONSTRUCTOR NAME used as a VALUE. Identical to pl_var EXCEPT a single resolved
// con whose arity is 0 (a nullary con: `Nothing`, `Empty`, a nullary exn con) is APPLIED to zero
// args — wrapped in D2Edap0 — so it has its RESULT type, not its `() -> T` con-function type
// (the same fix the list-literal `list_nil()` path and the nullary-con PATTERN path apply). A
// con of arity > 0 referenced bare (a partial/HOF con) is left as the raw d2exp_con (unchanged).
fun
pl_con_value(env: !tr12env, loc: loctn, sym: sym_t): d2exp = let
  val dopt = tr12env_find_d2itm(env, sym)
  // is the resolution a SINGLE nullary con? (compute the verdict; consume `dopt` cleanly).
  val nullary_con =
    (
    case+ dopt of
    | ~optn_vt_cons(d2i) =>
      (
        case+ d2i of
        | D2ITMcon(d2cs) =>
            if list_singq(d2cs) then (d2con_get_narg(d2cs.head()) = 0) else false
        | _ => false
      )
    | ~optn_vt_nil() => false
    ) : bool
in
  // a nullary con must be applied to zero args (D2Edap0) so it has its RESULT type. Everything
  // else (n-ary partial con, overloaded set, var, cst, sym, unbound) -> the shared pl_var path,
  // which re-does the (re-entrant) lookup and builds the appropriate node.
  if nullary_con
    then d2exp_make_node(loc, D2Edap0(pl_var(env, loc, sym)))
    else pl_var(env, loc, sym)
end
//
(* ****** ****** *)
//
// params (LIDENT names) -> a single f2arglst (one F2ARGdapp of fresh-d2var patterns). Param
// types are inferred (v1; PyCore drops the annotations, M3-REPORT). Shared by templates D/F.
//
fun
pl_params(loc: loctn, params: list(strn)): f2arglst = let
  fun
  loop(ps: list(strn)): d2patlst =
    case+ ps of
    | list_nil() => list_nil()
    | list_cons(nm, rest) =>
        let val d2v = d2var_new2_name(loc, symbl_make_name(nm))
        in list_cons(d2pat_var(loc, d2v), loop(rest)) end
  val dps = loop(params)
in
  list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), dps)))
end
//
// M5a: typed params -> a single f2arglst whose patterns are ANNOTATED for the params that
// carry a surface type. A `PyTypSome(T)` param becomes `D2Pannot(D2Pvar, s1exp_none0, <s2 T>)`
// (trans2a's f0_annot reads the s2exp -> the binder's styp, so `x + x` over a typed `x`
// resolves — LOWERING-MAP §1.3). A `PyTypNone()` param stays a bare binder (inferred). The
// two lists are parallel; a shorter/empty type list leaves the remaining params untyped.
//
fun
pl_one_param(env: !tr12env, loc: loctn, nm: strn, topt: pytypopt): d2pat = let
  val d2v = d2var_new2_name(loc, symbl_make_name(nm))
  val d2p = d2pat_var(loc, d2v)
in
  case+ topt of
  | PyTypNone() => d2p
  | PyTypSome(t) =>
      let val s2e = pylower_typ(env, t) in
        d2pat_make_node(loc, D2Pannot(d2p, s1exp_none0(loc), s2e))
      end
end
//
fun
pl_params_typed
(env: !tr12env, loc: loctn, params: list(strn), ptypes: list(pytypopt)): f2arglst = let
  fun
  loop(ps: list(strn), ts: list(pytypopt)): d2patlst =
    case+ ps of
    | list_nil() => list_nil()
    | list_cons(nm, prest) =>
      (
      case+ ts of
      | list_cons(topt, trest) => list_cons(pl_one_param(env, loc, nm, topt), loop(prest, trest))
      | list_nil() => list_cons(pl_one_param(env, loc, nm, PyTypNone()), loop(prest, list_nil()))
      )
  val dps = loop(params, ptypes)
in
  list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), dps)))
end
//
// M5a: a surface return annotation -> the d2fundcl/lambda's s2res (S2RESsome). PyTypNone -> none.
fun
pl_sres(env: !tr12env, ret: pytypopt): s2res =
( case+ ret of PyTypNone() => S2RESnone() | PyTypSome(t) => pylower_sres(env, t) )
//
// M5a: build a list of (possibly typed) param patterns, parallel to a name + type list.
fun
pl_param_pats
(env: !tr12env, loc: loctn, params: list(strn), ptypes: list(pytypopt)): d2patlst =
(
case+ params of
| list_nil() => list_nil()
| list_cons(nm, prest) =>
  (
  case+ ptypes of
  | list_cons(topt, trest) => list_cons(pl_one_param(env, loc, nm, topt), pl_param_pats(env, loc, prest, trest))
  | list_nil() => list_cons(pl_one_param(env, loc, nm, PyTypNone()), pl_param_pats(env, loc, prest, list_nil()))
  )
)
//
// M5a (the N-accumulator loop calling-convention fix): a generated `loop` is CALLED with a
// SINGLE argument that is the accumulator TUPLE (accs_tuple_exp: a bare var for one acc, an
// N-tuple for N>1), and its result is destructured by accs_tuple_pat. So a loop with 2+
// accumulators must take ONE tuple PARAMETER `(acc, i)`, not N flat params — otherwise the
// single tuple arg is checked against the first param only (a pre-existing arity mismatch that
// kept untyped 2-acc loops failing; M16 deferral). For ONE acc the param is the bare binder
// (1 arg = 1 param, already correct). The per-element annotations ride on the tuple's binders.
fun
pl_loop_params
(env: !tr12env, loc: loctn, params: list(strn), ptypes: list(pytypopt)): f2arglst =
(
case+ params of
// 0 accumulators (a `while`/`for` with NO `let mut` — e.g. a var-only loop): the call
// passes ONE unit argument `()` (accs_tuple_exp on the empty set is PCEunit), so the loop
// must take ONE unit PARAMETER to match — a `()` tuple pattern (D2Ptup0(-1,[])). A bare
// zero-param `F2ARGdapp(0,[])` here would receive the `()` arg against NO param (arity +
// void-type mismatch — the var-in-loop failure). (Pre-var, a 0-acc loop never typechecked
// meaningfully — there was nothing to thread — so this path was never exercised.)
| list_nil() =>
    let val unitp = d2pat_make_node(loc, D2Ptup0((-1), list_nil())) in
      list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(unitp))))
    end
| list_cons(_, list_nil()) =>
    list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), pl_param_pats(env, loc, params, ptypes))))
// 2+ accumulators: a SINGLE tuple parameter `(a, b, ...)` matching the tuple call argument.
| list_cons(_, list_cons(_, _)) =>
    let
      val elems = pl_param_pats(env, loc, params, ptypes)
      val tup = d2pat_make_node(loc, D2Ptup0((-1), elems))
    in
      list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(tup))))
    end
)
//
(* ****** ****** *)
//
// ---- the mutually-recursive lowering group ---------------------------------
//
// pl_pat / pl_patlst : patterns (fresh binders).
// pl_exp / pl_explst : expressions (templates A/B/C/D/E).
// pl_fungroup / pl_one_fundcl : the recursive fun group (template F).
//
fun
pl_pat(env: !tr12env, p: pcpat): d2pat =
(
case+ p of
| PCPvar(loc, name) =>
    let val d2v = d2var_new2_name(loc, symbl_make_name(name)) in d2pat_var(loc, d2v) end
| PCPwild(loc) => d2pat_make_node(loc, D2Pany())
| PCPcon(loc, name, args) => let
    val sym = symbl_make_name(name)
    val dopt = tr12env_find_d2itm(env, sym)
    val phd =
      (
        case+ dopt of
        | ~optn_vt_cons(d2i) =>
          (
            case+ d2i of
            | D2ITMcon(d2cs) =>
                if list_singq(d2cs) then d2pat_con(loc, d2cs.head())
                else d2pat_make_node(loc, D2Pnone0())
            | D2ITMvar(_) => d2pat_make_node(loc, D2Pnone0())
            | D2ITMcst(_) => d2pat_make_node(loc, D2Pnone0())
            | D2ITMsym(_, _) => d2pat_make_node(loc, D2Pnone0())
          )
        | ~optn_vt_nil() => d2pat_make_node(loc, D2Pnone0())
      )
  in
    case+ args of
    // NULLARY con pattern (e.g. `Nothing`, `Red`): MUST be wrapped in D2Pdap0 (#21, M5b-spike
    // proven). A bare d2pat_con is typed as the raw `() -> T` con-FUNCTION type and fails to
    // unify with the scrutinee `T`; trans2a's f0_dap0 rewrites D2Pdap0(con) -> dapp(con,-1,[]),
    // applying the con-function to ZERO args to yield the RESULT type `T`. (Dormant until now —
    // no nullary con pattern had ever been typechecked.) When `phd` is an unresolved D2Pnone0,
    // the dap0 wrapper is benign (the node is already a poison placeholder).
    | list_nil() => d2pat_make_node(loc, D2Pdap0(phd))
    | list_cons(_, _) =>
        let val dps = pl_patlst(env, args) in d2pat_make_node(loc, D2Pdapp(phd, (-1), dps)) end
  end
| PCPtup(loc, ps) =>
    let val dps = pl_patlst(env, ps) in d2pat_make_node(loc, D2Ptup0((-1), dps)) end
| PCPrec(loc, fs) =>
    // { f = p, g = q } -> D2Prcd2(REC-tok, -1, [D2LAB(LABsym f, p), ...]). NAME labels.
    let val ldps = pl_pfieldlst(env, fs) in d2pat_make_node(loc, D2Prcd2(tok_rec(loc), (-1), ldps)) end
| PCPlit(loc, lit) =>
    // Literal patterns are checked against the scrutinee type (trans23_d2pat_tpck pushes the
    // scrutinee's styp DOWN), so they need no own stamp — leaving them UNSTAMPED avoids the
    // same over-constraint the expression literals would hit. (Matches m4_probe1: `case 0:` on
    // an int scrutinee typechecks nerror=0 with no stamp.) Bool pattern kept symmetric with the
    // bool-expr stamp for robustness when a bool literal pattern is checked in synthesis.
    (
      case+ lit of
      | PCLint(_, s) => d2pat_make_node(loc, D2Pint(token_make_node(loc, T_INT01(s))))
      | PCLflt(_, s) => d2pat_make_node(loc, D2Pflt(token_make_node(loc, T_FLT01(s))))
      | PCLstr(_, s) => d2pat_make_node(loc, D2Pstr(token_make_node(loc, T_STRN1_clsd(s, strn_length(s)))))
      | PCLchr(_, s) => d2pat_make_node(loc, D2Pchr(token_make_node(loc, T_CHAR2_char(s))))
      | PCLbool(_, b) => d2pat_make_node(loc, D2Pbtf(symbl_make_name(if b then "true" else "false")))
    )
// M7: as-pattern `p as x` -> D2Prfpt(<lowered p>, AS-tok, D2Pvar <fresh d2v for x>). The L2
// node binds a fresh d2var for `x` AND keeps the inner pattern `p` (dynexp2.sats:757; trans12
// builds it as D2Prfpt(inner, tknd, binder) at trans12_dynexp.dats:1161). The binder is the
// SECOND d2pat (the comment at trans23_dynexp.dats:863 "[d2p1] is supposed to be a d2var" is
// about the INNER pat, which trans23 tpck's against the binder's type — so the binder `x` gets
// the matched value's type). tr12env_add0_d2pat has a D2Prfpt arm (trans12_myenv0.dats:2040)
// that REGISTERS BOTH the binder and the inner pattern's vars, so `x` is usable in the arm body
// (this is the dropped-binding bug fix). The AS token's kind/lexeme is irrelevant to typing
// (trans2a/trans23 f0_rfpt destructure but ignore tkas) — reuse tok_val like the other binders.
| PCPas(loc, name, inner) =>
    let
      val d2pinner = pl_pat(env, inner)
      val d2v = d2var_new2_name(loc, symbl_make_name(name))
      val d2pbind = d2pat_var(loc, d2v)
    in
      d2pat_make_node(loc, D2Prfpt(d2pinner, tok_val(loc), d2pbind))
    end
)
//
and
pl_patlst(env: !tr12env, ps: list(pcpat)): d2patlst =
(
case+ ps of
| list_nil() => list_nil()
| list_cons(p, rest) => list_cons(pl_pat(env, p), pl_patlst(env, rest))
)
//
// record-pattern fields -> l2d2p = D2LAB(label, d2pat). NAME labels (LABsym).
and
pl_pfieldlst(env: !tr12env, fs: list(pcpfield)): l2d2plst =
(
case+ fs of
| list_nil() => list_nil()
| list_cons(PCPField(_, name, fp), rest) =>
    let
      val lab = LABsym(symbl_make_name(name))
      val d2p = pl_pat(env, fp)
    in
      list_cons(D2LAB(lab, d2p), pl_pfieldlst(env, rest))
    end
)
//
and
pl_exp(env: !tr12env, e: pcexp): d2exp =
(
case+ e of
//
| PCElit(loc, lit) => pl_lit(loc, lit)
//
// PCEvar : an ordinary var/fun reference (template A). A BARE operator name (not applied) is
// not a runnable value in v1, but resolve it as-is for recovery (deferred).
| PCEvar(loc, name) => pl_var(env, loc, symbl_make_name(name))
// PCEcon : UIDENT -> a d2con reference (template A resolves it to D2ITMcon). CRITICAL: a
// NULLARY con used as a VALUE (`Nothing`, `Empty`, a nullary exn con) must be APPLIED to zero
// args — wrapped in D2Edap0 — exactly as the list-literal path wraps `list_nil()` (M16) and the
// nullary-con PATTERN path wraps in D2Pdap0 (#21). A bare D2Econ keeps the con's `() -> T`
// FUNCTION type, which then fails to unify with the result type `T` (D3Et2pck errck). An n-ary
// con reaches here only as the head of a PCEapp (handled by pl_app -> D2Edapp); a BARE n-ary con
// reference (a HOF-style partial con) stays unwrapped. So: wrap iff the resolved con is nullary.
| PCEcon(loc, name) => pl_con_value(env, loc, symbl_make_name(name))
//
// template B : application f(a,b) -> D2Edapp(d2f, -1, args). Empty arg list -> D2Edap0.
// OPERATOR-HEADED applications are remapped to their concrete prelude `sint_*` function by
// ARITY (1-arg `-` -> sint_neg; 2-arg -> op_remap), so they resolve via the D2ITMcst arm and
// run (the overloaded D2ITMsym form would lower to a non-runnable D3Enone0; M3-REPORT).
| PCEapp(loc, hd, args) => pl_app(env, loc, hd, args)
//
// template D : lambda `lam(params) => body`. Push a lam scope, bind the params, lower the
// body, pop. M5a: a param carrying a surface type annotation lowers to an ANNOTATED binder
// (D2Pannot) so its type is respected (e.g. the for-fold's typed accumulator param). The
// type list is built BEFORE the param scope is pushed (it resolves type names in the env).
// M7-closures: the `_is_func` flag is a RECORDED HINT only — it does NOT change the L2
// closure-kind here (the spike showed F2CLfun is inferred from context, and an escaping
// capturing cloref already typechecks). The frontend capture CHECK runs in the elaborator
// (el_exp's PyElam case); by the time we lower, a @func lambda has already passed it.
| PCElam(loc, _is_func, params, ptypes, body) => let
    val f2as = pl_params_typed(env, loc, params, ptypes)
    val () = tr12env_pshlam0(env)
    val () = tr12env_add0_f2arglst(env, f2as)
    val d2body = pl_exp(env, body)
    val () = tr12env_poplam0(env)
  in
    d2exp_make_node(loc, D2Elam0(tok_lam(loc), f2as, S2RESnone(), F1UNARRWdflt(loc), d2body))
  end
//
// template C/E : `let val p = rhs in body`. A single immutable binding (SSA rebind), local
// to `body`. Non-recursive => bind the pattern AFTER its RHS (template C binding order).
// M5a: an annotated `let p : T = e` wraps the RHS in `D2Eannot` so the binding is typed
// (trans2a's f0_annot reads the s2exp -> the RHS is checked against T, and the binder's styp
// flows from it). An unannotated `let` keeps the M4 fresh-tyvar binder path (types inferred).
| PCElet(loc, p, ann, rhs, body) => let
    val () = tr12env_pshlet0(env)
    val d2p = pl_pat(env, p)
    val d2rhs0 = pl_exp(env, rhs)
    val d2rhs =
      (
      case+ ann of
      | PyTypNone() => d2rhs0
      | PyTypSome(t) =>
          let val s2e = pylower_typ(env, t) in
            d2exp_make_node(loc, D2Eannot(d2rhs0, s1exp_none0(loc), s2e))
          end
      ): d2exp
    val () = bind_let_styp(d2p, d2rhs)           // M4: fresh tyvar binder (unless RHS is none0)
    val () = tr12env_add0_d2pat(env, d2p)        // non-rec: bind after RHS
    val dval = d2valdcl_make_args(loc, d2p, TEQD2EXPsome(tok_val(loc), d2rhs), WTHS2EXPnone())
    val decl = d2ecl_make_node(loc, D2Cvaldclst(tok_val(loc), list_sing(dval)))
    val d2body = pl_exp(env, body)
    val () = tr12env_poplet0(env)
  in
    d2exp_make_node(loc, D2Elet0(list_sing(decl), d2body))
  end
//
// PCEvarcell : `var nm [: T] = init in body` — a MUTABLE CELL (ATS-parity var/mutation).
// Lowers to a `D2Cvardclst` (one d2vardcl, vpid=None) wrapped in `D2Elet0` over `body`,
// mirroring the SPIKE-PROVEN recipe (pyfront_var_spike.dats build_var_cell / case1):
//   * d2var_new2_name(loc, nm)         — the cell's dpid (a plain d2var; trans2a's
//     f0_vardclst types it as a LEFT-VALUE of T via dpid.styp(s2typ_lft(tres))).
//   * d2vardcl_make_args(loc, d2v, optn_nil()(*vpid*), sres, TEQD2EXPsome(=, init)) —
//     vpid OPTIONAL (the view-proof id; views are threaded but NOT enforced at typecheck,
//     so a plain cell needs no view plumbing). sres = the annotation (Some T) or None.
//   * tr12env_add0_d2var(env, d2v)     — REGISTER the cell so a later `PCEvar nm` (read OR
//     the LHS of an assignment) resolves to it (mirrors trans12 f1_add0_d2vs).
//   * The init RHS is lowered in the SAME let-scope BEFORE the binder is registered
//     (a `var x = ...x...` self-reference is not valid; init sees the OUTER scope).
// A `var` is NEVER a loop accumulator (the elaborator never put nm in `muts`/`accs`).
| PCEvarcell(loc, nm, ann, init, body) => let
    val () = tr12env_pshlet0(env)
    val d2init = pl_exp(env, init)
    val sres =
      (
      case+ ann of
      | PyTypNone() => optn_nil()
      | PyTypSome(t) => optn_cons(pylower_typ(env, t))
      ): s2expopt
    val d2v = d2var_new2_name(loc, symbl_make_name(nm))
    val dvar = d2vardcl_make_args(loc, d2v, optn_nil()(*vpid*), sres, TEQD2EXPsome(tok_val(loc), d2init))
    val () = tr12env_add0_d2var(env, d2v)          // register AFTER the init is lowered
    val decl = d2ecl_make_node(loc, D2Cvardclst(tok_var(loc), list_sing(dvar)))
    val d2body = pl_exp(env, body)
    val () = tr12env_poplet0(env)
  in
    d2exp_make_node(loc, D2Elet0(list_sing(decl), d2body))
  end
//
// PCEassign : `lval := rval` -> D2Eassgn(lval, rval). trans23 f0_assgn typechecks rval
// against lval's type and returns void (no view consumption). `lval` is a `PCEvar nm`
// (resolves to the registered cell d2var); field/index lvalues are a later slice.
| PCEassign(loc, lv, rv) => let
    val d2lv = pl_exp(env, lv)
    val d2rv = pl_exp(env, rv)
  in
    d2exp_make_node(loc, D2Eassgn(d2lv, d2rv))
  end
//
// template F (local form) : `let fun f(..)=.. and g(..)=.. in body`.
| PCEletfun(loc, fdcls, body) => let
    val () = tr12env_pshlet0(env)
    val decl = pl_fungroup(env, loc, fdcls)
    val d2body = pl_exp(env, body)
    val () = tr12env_poplet0(env)
  in
    d2exp_make_node(loc, D2Elet0(list_sing(decl), d2body))
  end
//
// PCEif : 3-branch value-if -> D2Eift0(cond, Some then, Some else).
| PCEif(loc, c, t, f) => let
    val d2c = pl_exp(env, c)
    val d2t = pl_exp(env, t)
    val d2f = pl_exp(env, f)
  in
    d2exp_make_node(loc, D2Eift0(d2c, optn_cons(d2t), optn_cons(d2f)))
  end
//
// PCEcase : `match scrut: case p [if g] => body ...` -> D2Ecas0(match-tok, scrut, clauses).
// The scrutinee is lowered FIRST (its names resolve in the OUTER scope). Each arm becomes a
// d2cls; a guarded arm uses ATS's native guarded clause (D2GPTgua) so a failed guard FALLS
// THROUGH to the next arm (the architect's ruling iv: NOT an inner-if). Per-arm pattern binding
// (own scope) mirrors trans12_d1cls/d1gpt exactly. This is also what makes the desugared loops
// (PCEletfun + PCEcase over flow ctors) lower & typecheck.
| PCEcase(loc, scrut, arms) => let
    val d2scrut = pl_exp(env, scrut)
    val d2cs = pl_armlst(env, arms)
  in
    d2exp_make_node(loc, D2Ecas0(tok_case(loc), d2scrut, d2cs))
  end
//
// PCEtup : (a, b) -> D2Etup0(-1, [..]).
| PCEtup(loc, es) =>
    let val d2es = pl_explst(env, es) in d2exp_make_node(loc, D2Etup0((-1), d2es)) end
//
// PCErec : { f = a, g = b } -> D2Ercd2(REC-tok, -1, [D2LAB(LABsym f, a), ...]). Labels are NAME
// labels (LABsym). npf=-1 (no proof fields). Mirrors trans12 f0_r1cd.
| PCErec(loc, fields) =>
    let val ldes = pl_efieldlst(env, fields) in
      d2exp_make_node(loc, D2Ercd2(tok_rec(loc), (-1), ldes))
    end
//
// PCElist : [a, b, c] -> a prelude list_cons/list_nil chain (there is NO D2Elist node; ATS
// source `[..]` desugars to cons/nil too). list_cons/list_nil resolve via the prelude
// fall-through (pyrt itself builds lists this way). Empty list -> list_nil().
| PCElist(loc, es) => pl_list(env, loc, es)
//
// PCEfield : e.name -> D2Eproj(tok, fresh d2rxp, LABsym name, e). Field/tuple-component
// projection (LOWERING-MAP §1.1). Per probe, D2Eproj is the projection node trans23 resolves
// for both records and tuples; the tknd's lexeme is irrelevant to typing.
| PCEfield(loc, e1, name) => let
    val d2e1 = pl_exp(env, e1)
    val drxp = d2rxp_new1(loc)
    val lab  = LABsym(symbl_make_name(name))
  in
    d2exp_make_node(loc, D2Eproj(tok_val(loc), drxp, lab, d2e1))
  end
//
// PCEseq : (e1; e2) -> D2Eseqn([e1], e2).
| PCEseq(loc, e1, e2) => let
    val d2e1 = pl_exp(env, e1)
    val d2e2 = pl_exp(env, e2)
  in
    d2exp_make_node(loc, D2Eseqn(list_sing(d2e1), d2e2))
  end
//
// PCEunit : () -> the empty tuple D2Etup0(-1, []).
| PCEunit(loc) => d2exp_make_node(loc, D2Etup0((-1), list_nil()))
//
// EXN: PCEraise -> D2Eraise($raise-tok, e). trans23 f0_raise typechecks `e` against the
// built-in exn type (the_s2typ_excptn) and gives the whole raise a FRESH type var — `raise`
// does not return, so it unifies with any context type. (SPIKE-PROVEN, nerror=0.)
| PCEraise(loc, e1) => let
    val d2e1 = pl_exp(env, e1)
  in
    d2exp_make_node(loc, D2Eraise(tok_raise(loc), d2e1))
  end
//
// EXN: PCEtry -> D2Etry0(try-tok, body, clauses). The body lowers first (its names resolve in
// the OUTER scope). The except clauses reuse pl_armlst — the SAME match-clause lowering as
// PCEcase — so each `except <pat>:` becomes a d2cls; trans23 f0_try0 typechecks them as
// case-arms over a synthetic exn-typed scrutinee, all branches unifying to the body's type.
// (SPIKE-PROVEN, nerror=0.)
| PCEtry(loc, body, hs) => let
    val d2body = pl_exp(env, body)
    val d2cs = pl_armlst(env, hs)
  in
    d2exp_make_node(loc, D2Etry0(tok_try(loc), d2body, d2cs))
  end
//
// PCEerror : an elaboration poison node — surface it as a none-node that SURVIVES to tread3a
// (so the elaboration error actually FAILS the typecheck, nerror>0). A bare d2exp_none0 gets
// `void`-stamped by trans2a and then unified AWAY (the M4-recovery HARD LESSON; #13a) — so a
// poison whose surrounding context happens to typecheck (e.g. a @func capture, where the
// captured var IS bound) would slip through with nerror=0. The d2exp_none1(D1Eid0(sym)) form is
// IMMUNE: trans2a never rewrites it, it falls through to D2Enone2 -> D3Enone1, and tread3a's
// `_(*otherwise*)` COUNTS it (err+1) on the poison's span — exactly the #13a unbound-name path.
| PCEerror(loc, _) =>
    d2exp_none1(d1exp_make_node(loc, D1Eid0(symbl_make_name("@elab-error"))))
//
)
//
and
pl_explst(env: !tr12env, es: list(pcexp)): d2explst =
(
case+ es of
| list_nil() => list_nil()
| list_cons(e, rest) => list_cons(pl_exp(env, e), pl_explst(env, rest))
)
//
// ---- case clauses (templates mirroring trans12_d1cls / d1gpt) ---------------
//
// one arm -> one d2cls. Mirrors trans12_d1cls(D1CLScls) + trans12_d1gpt EXACTLY:
//   * build the GUARDED-PATTERN (d2gpt): lower the pattern (fresh binders, NOT yet bound).
//     - UNGUARDED arm  -> D2GPTpat(d2p).
//     - GUARDED arm    -> D2GPTgua(d2p, [guard]); the guard is lowered in its OWN scope that
//                         binds the pattern (pshlam0 + add0_d2pat) so guard names resolve, then
//                         poplam0. A failed guard FALLS THROUGH to the next arm (ruling iv).
//   * build the matched clause D2CLScls(d2gpt, body): a SECOND scope (pshlam0 + add0_d2gpt) so
//     the body sees the pattern's binders, lower the body, poplam0.
// The double push/pop for a guarded arm is exactly trans12's order (guard-scope nested inside
// the gpt build; body-scope opened freshly by the clause build via add0_d2gpt).
and
pl_arm(env: !tr12env, arm: pcarm): d2cls = let
  val+ PCArm(loc, pat, gopt, body) = arm
  // the guarded-pattern.
  val d2p = pl_pat(env, pat)
  val dgpt =
    (
      case+ gopt of
      | PCEGNone() => d2gpt_make_node(loc, D2GPTpat(d2p))
      | PCEGSome(g) => let
          val () = tr12env_pshlam0(env)            // enter the guard scope
          val () = tr12env_add0_d2pat(env, d2p)    // pattern vars visible to the guard
          val d2g = pl_exp(env, g)
          val () = tr12env_poplam0(env)            // exit the guard scope
          val dgua = d2gua_make_node(loc, D2GUAexp(d2g))
        in
          d2gpt_make_node(loc, D2GPTgua(d2p, list_sing(dgua)))
        end
    ): d2gpt
  // the matched clause: a fresh scope binding the gpt's vars for the body.
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_d2gpt(env, dgpt)
  val d2body = pl_exp(env, body)
  val () = tr12env_poplam0(env)
in
  d2cls_make_node(loc, D2CLScls(dgpt, d2body))
end
//
and
pl_armlst(env: !tr12env, arms: list(pcarm)): d2clslst =
(
case+ arms of
| list_nil() => list_nil()
| list_cons(a, rest) => list_cons(pl_arm(env, a), pl_armlst(env, rest))
)
//
// ---- record-literal fields (l2d2e = D2LAB(label, d2exp)) --------------------
//
and
pl_efieldlst(env: !tr12env, fs: list(pcefield)): l2d2elst =
(
case+ fs of
| list_nil() => list_nil()
| list_cons(PCEField(floc, name, fe), rest) =>
    let
      val lab = LABsym(symbl_make_name(name))
      val d2e = pl_exp(env, fe)
    in
      list_cons(D2LAB(lab, d2e), pl_efieldlst(env, rest))
    end
)
//
// ---- list literal -> a prelude list_cons / list_nil chain -------------------
//
// [a, b, c] -> list_cons(a, list_cons(b, list_cons(c, list_nil()))). There is NO D2Elist node;
// the stock parser desugars `[..]` to cons/nil too, and pyrt builds lists this way. list_cons /
// list_nil resolve via the env's prelude fall-through (template A on a UIDENT/LIDENT con name).
and
pl_list(env: !tr12env, loc: loctn, es: list(pcexp)): d2exp =
(
case+ es of
// the empty list `[]` is the nullary constructor APPLICATION `list_nil()` — it must be wrapped
// in D2Edap0 (a zero-arg application), NOT the bare `d2exp_con(list_nil)`. The bare constructor
// is a FUNCTION value `() -> list(a)`; trans23 then checks that function against the expected
// `list(a)` and errcks (T2Pfun1(...)->list vs list). This mirrors pl_app's `list_nil()` arm
// (D2Edap0 for an empty arg list) — M16 (the list-literal fix the #13a operator unblock exposed).
| list_nil() =>
    d2exp_make_node(loc, D2Edap0(pl_var(env, loc, symbl_make_name("list_nil"))))
| list_cons(e, rest) => let
    val d2hd = pl_exp(env, e)
    val d2tl = pl_list(env, loc, rest)
    val d2cons = pl_var(env, loc, symbl_make_name("list_cons"))
  in
    d2exp_dapp(loc, d2cons, (-1), list_cons(d2hd, list_sing(d2tl)))
  end
)
//
// template B with operator-head remapping. When the head is `PCEvar opname`, remap by ARITY
// (1 arg -> op_remap_unary; >=2 args -> op_remap) to the concrete prelude `sint_*` function,
// then resolve it (D2ITMcst arm). A remap result of "" means a NO-OP prefix (unary `+`) ->
// return the single operand. A non-operator head lowers normally (template B).
and
pl_app
(env: !tr12env, loc: loctn, hd: pcexp, args: list(pcexp)): d2exp =
(
case+ hd of
| PCEvar(hloc, name) => let
    val nargs = list_length(args)
    // a 1-arg `-`/`+` is UNARY (op_remap_unary); everything else (incl. 1-arg `print` and all
    // binary operators) goes through op_remap. Nested-if (no andalso/orelse in this dialect).
    val is_unary =
      (
        if nargs = 1
          then (if strn_eq(name, "-") then true else strn_eq(name, "+"))
          else false
      ): bool
    val key = (if is_unary then op_remap_unary(name) else op_remap(name)): strn
  in
    if strn_eq(key, "") then
      // a no-op prefix (unary +): the application IS its single operand.
      (case+ args of list_cons(a, _) => pl_exp(env, a) | list_nil() => d2exp_none0(loc))
    else let
      val d2f = pl_var(env, hloc, symbl_make_name(key))
    in
      case+ args of
      | list_nil() => d2exp_make_node(loc, D2Edap0(d2f))
      | list_cons(_, _) =>
          let val d2es = pl_explst(env, args) in d2exp_dapp(loc, d2f, (-1), d2es) end
    end
  end
| _ => let
    val d2f = pl_exp(env, hd)
  in
    case+ args of
    | list_nil() => d2exp_make_node(loc, D2Edap0(d2f))
    | list_cons(_, _) =>
        let val d2es = pl_explst(env, args) in d2exp_dapp(loc, d2f, (-1), d2es) end
  end
)
//
// template F : lower one (recursive/mutual) fun group to a D2Cfundclst d2ecl. Mirrors
// trans12_decl00.dats f0_fundclst: bind the group's NAMES first (a Python def group is
// recursive, so self/mutual calls resolve to the SAME d2var), then lower each body in its
// own lam scope, then emit. FNKfn2 (tailrec) lets the backend compile a tail self-call to a
// `while` loop (what the desugared loops rely on). No generic tqas in v1.
//
and
pl_fungroup(env: !tr12env, loc: loctn, fdcls: list(pcfundcl)): d2ecl = let
  //
  fun
  names_d2vs(fs: list(pcfundcl)): list(d2var) =
    case+ fs of
    | list_nil() => list_nil()
    | list_cons(PCFundcl(floc, nm, _, _, _, _, _), rest) =>
        list_cons(d2var_new2_name(floc, symbl_make_name(nm)), names_d2vs(rest))
  //
  val d2vs = names_d2vs(fdcls)
  // recursive: bind the names BEFORE lowering the bodies (so self/mutual calls resolve).
  val () = tr12env_add0_d2varlst(env, d2vs)
  //
  fun
  members(ds: list(d2var), fs: list(pcfundcl)): d2fundclist =
    case+ (ds, fs) of
    | (list_cons(d2v, drest), list_cons(fdcl, frest)) =>
        list_cons(pl_one_fundcl(env, d2v, fdcl), members(drest, frest))
    | (_, _) => list_nil()
  //
  val d2fs = members(d2vs, fdcls)
in
  d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil()(*tqas*), list_nil()(*d2cs*), d2fs))
end
//
// lower one member: build the (possibly typed) params, push a lam scope, register them, lower
// the body, pop. Mirrors trans12_decl00.dats trans12_d1fundcl (4232-4279). `d2v` is the member's
// already-bound name. M5a: a typed param lowers to an annotated f2arg binder (D2Pannot) and a
// `-> T` return annotation to the d2fundcl's s2res (S2RESsome) — so a typed `def double(x:Int)`
// typechecks with its annotations (its `x + x` resolves because `x` is now typed). An
// unannotated def lowers exactly as before (params/return inferred).
//
and
pl_one_fundcl(env: !tr12env, d2v: d2var, fdcl: pcfundcl): d2fundcl = let
  val+ PCFundcl(loc, _, params, ptypes, ret, body, isloop) = fdcl
  // M5a: a generated `loop` (isloop) is called with a SINGLE accumulator-tuple argument, so
  // for 2+ accs it takes ONE tuple parameter (pl_loop_params). A surface `def` takes its
  // params flat (pl_params_typed). Both honor per-param type annotations (D2Pannot).
  val f2as =
    (if isloop then pl_loop_params(env, loc, params, ptypes)
     else pl_params_typed(env, loc, params, ptypes)): f2arglst
  val sres = pl_sres(env, ret)
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2body = pl_exp(env, body)
  val () = tr12env_poplam0(env)
in
  d2fundcl_make_args
    (loc, d2v, f2as, sres, TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
end
//
(* ****** ****** *)
//
// ---- implement (ATS-parity): PCCimplement -> D2Cimplmnt0 -------------------
//
// SPIKE-PROVEN recipe (frontend/DATS/pyfront_surf1_spike.dats case 3; mirrors stock
// f0_implmnt0_dimp @ srcgen2/DATS/trans12_decl00.dats:3373-3463):
//   * RESOLVE the pre-declared d2cst by NAME (the extern/template `def` already registered it via
//     tr12env_add1_d2cst) -> a `dimpl(loc, DIMPLone1(d2c))`. (No registration here — the d2cst is
//     pre-existing; building the impl does NOT re-register anything.)
//   * BIND the (typed) params in a pshlam0/add0_f2as scope, lower the body, poplam0 — EXACTLY the
//     fun-body scope dance (pl_one_fundcl). The f2arglst rides on the D2Cimplmnt0 node and the body
//     references the bound params.
//   * ASSEMBLE D2Cimplmnt0(tknd, [], [], dimp, [], f2as, sres, body) — all quantifier/template-arg
//     lists EMPTY (MONOMORPHIC v1; the resolved d2cst already carries the function type). tknd =
//     T_IMPLMNT(IMPLfun()). An UNRESOLVABLE name (no matching d2cst) -> a benign D2Cnone0 (recovery;
//     trans23 already reported any use-site mismatch).
fun
pl_implement
( env: !tr12env, loc: loctn, name: strn
, pnames: list(strn), ptypes: list(pytypopt), ret: pytypopt, body: pcexp): d2ecl = let
  // resolve the pre-declared d2cst by name (mirror f1_dqid: find_d2itm -> D2ITMcst head).
  val d2copt =
    (
    case+ tr12env_find_d2itm(env, symbl_make_name(name)) of
    | ~optn_vt_cons(d2i) =>
      (case+ d2i of
       | D2ITMcst(d2cs) => (if list_nilq(d2cs) then optn_nil() else optn_cons(d2cs.head()))
       | _ => optn_nil())
    | ~optn_vt_nil() => optn_nil()
    ): optn(d2cst)
in
  case+ d2copt of
  | ~optn_cons(d2c) => let
      val dimp = dimpl_make_node(loc, DIMPLone1(d2c))
      val tknd = token_make_node(loc, T_IMPLMNT(IMPLfun()))
      // build + bind the (typed) params, lower the body, pop — the fun-body scope dance.
      val f2as = pl_params_typed(env, loc, pnames, ptypes)
      val sres = pl_sres(env, ret)
      val () = tr12env_pshlam0(env)
      val () = tr12env_add0_f2arglst(env, f2as)
      val d2body = pl_exp(env, body)
      val () = tr12env_poplam0(env)
    in
      d2ecl_make_node
        (loc, D2Cimplmnt0(tknd, list_nil()(*sqas*), list_nil()(*tqas*),
                          dimp, list_nil()(*tias*), f2as, sres, d2body))
    end
  | ~optn_nil() => d2ecl_make_node(loc, D2Cnone0())   // unresolvable name: benign no-op (recovery)
end
//
(* ****** ****** *)
//
// ---- thin #implfun wrappers for the SATS entries ---------------------------
//
#implfun pylower_lit(loc, lit) = pl_lit(loc, lit)
#implfun pylower_var(env, loc, sym) = pl_var(env, loc, sym)
#implfun pylower_pat(env, p) = pl_pat(env, p)
#implfun pylower_patlst(env, ps) = pl_patlst(env, ps)
#implfun pylower_exp(env, e) = pl_exp(env, e)
#implfun pylower_explst(env, es) = pl_explst(env, es)
#implfun params_to_f2arglst(env, loc, params) = pl_params(loc, params)
#implfun lower_fungroup(env, loc, fdcls) = pl_fungroup(env, loc, fdcls)
#implfun lower_implement(env, loc, name, pnames, ptypes, ret, body) =
  pl_implement(env, loc, name, pnames, ptypes, ret, body)
//
(* ****** ****** *)
(*
end of [frontend/DATS/pylower_dynexp.dats]
*)
