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
// the `case` kind-token for D2Ecas0: CSKcas0 = warning-only on non-exhaustiveness (suits the
// desugared-loop flow dispatch, which is not exhaustive over all flow ctors). The record kind
// token for D2Ercd2 is the `{` the stock parser emits for a record literal (T_LBRACE).
fun tok_case(loc: loctn): token = token_make_node(loc, T_CASE(CSKcas0))
fun tok_rec(loc: loctn): token = token_make_node(loc, T_LBRACE())
//
(* ****** ****** *)
//
// ---- literals -> token-based L2 leaves (LOWERING-MAP §2.1) ------------------
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
    // true/false are boolean-literal nodes (D2Ebtf sym), NOT data constructors.
    d2exp_make_node(loc, D2Ebtf(symbl_make_name(if b then "true" else "false")))
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
  | ~optn_vt_nil() => d2exp_none0(loc)
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
    | list_nil() => phd
    | list_cons(_, _) =>
        let val dps = pl_patlst(env, args) in d2pat_make_node(loc, D2Pdapp(phd, (-1), dps)) end
  end
| PCPtup(loc, ps) =>
    let val dps = pl_patlst(env, ps) in d2pat_make_node(loc, D2Ptup0((-1), dps)) end
| PCPrec(loc, fs) =>
    // { f = p, g = q } -> D2Prcd2(REC-tok, -1, [D2LAB(LABsym f, p), ...]). NAME labels.
    let val ldps = pl_pfieldlst(env, fs) in d2pat_make_node(loc, D2Prcd2(tok_rec(loc), (-1), ldps)) end
| PCPlit(loc, lit) =>
    (
      case+ lit of
      | PCLint(_, s) => d2pat_make_node(loc, D2Pint(token_make_node(loc, T_INT01(s))))
      | PCLflt(_, s) => d2pat_make_node(loc, D2Pflt(token_make_node(loc, T_FLT01(s))))
      | PCLstr(_, s) => d2pat_make_node(loc, D2Pstr(token_make_node(loc, T_STRN1_clsd(s, strn_length(s)))))
      | PCLchr(_, s) => d2pat_make_node(loc, D2Pchr(token_make_node(loc, T_CHAR2_char(s))))
      | PCLbool(_, b) => d2pat_make_node(loc, D2Pbtf(symbl_make_name(if b then "true" else "false")))
    )
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
// PCEcon : UIDENT -> a d2con reference (template A resolves it to D2ITMcon).
| PCEcon(loc, name) => pl_var(env, loc, symbl_make_name(name))
//
// template B : application f(a,b) -> D2Edapp(d2f, -1, args). Empty arg list -> D2Edap0.
// OPERATOR-HEADED applications are remapped to their concrete prelude `sint_*` function by
// ARITY (1-arg `-` -> sint_neg; 2-arg -> op_remap), so they resolve via the D2ITMcst arm and
// run (the overloaded D2ITMsym form would lower to a non-runnable D3Enone0; M3-REPORT).
| PCEapp(loc, hd, args) => pl_app(env, loc, hd, args)
//
// template D : lambda `lam(params) => body`. Push a lam scope, bind the params, lower the
// body, pop. No param/return type annotations on a bare lambda (inferred).
| PCElam(loc, params, body) => let
    val () = tr12env_pshlam0(env)
    val f2as = pl_params(loc, params)
    val () = tr12env_add0_f2arglst(env, f2as)
    val d2body = pl_exp(env, body)
    val () = tr12env_poplam0(env)
  in
    d2exp_make_node(loc, D2Elam0(tok_lam(loc), f2as, S2RESnone(), F1UNARRWdflt(loc), d2body))
  end
//
// template C/E : `let val p = rhs in body`. A single immutable binding (SSA rebind), local
// to `body`. Non-recursive => bind the pattern AFTER its RHS (template C binding order).
| PCElet(loc, p, rhs, body) => let
    val () = tr12env_pshlet0(env)
    val d2p = pl_pat(env, p)
    val d2rhs = pl_exp(env, rhs)
    val () = tr12env_add0_d2pat(env, d2p)        // non-rec: bind after RHS
    val dval = d2valdcl_make_args(loc, d2p, TEQD2EXPsome(tok_val(loc), d2rhs), WTHS2EXPnone())
    val decl = d2ecl_make_node(loc, D2Cvaldclst(tok_val(loc), list_sing(dval)))
    val d2body = pl_exp(env, body)
    val () = tr12env_poplet0(env)
  in
    d2exp_make_node(loc, D2Elet0(list_sing(decl), d2body))
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
// PCEerror : an elaboration poison node — surface it as a none-node (recovery).
| PCEerror(loc, _) => d2exp_none0(loc)
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
| list_nil() => pl_var(env, loc, symbl_make_name("list_nil"))
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
    | list_cons(PCFundcl(floc, nm, _, _, _), rest) =>
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
// lower one member: push a lam scope, build params (fresh d2vars), register them, lower the
// body, pop. Mirrors trans12_decl00.dats trans12_d1fundcl (4232-4279). `d2v` is the member's
// already-bound name. Return type inferred (PyCore drops the annotation; M3-REPORT).
//
and
pl_one_fundcl(env: !tr12env, d2v: d2var, fdcl: pcfundcl): d2fundcl = let
  val+ PCFundcl(loc, _, params, body, _) = fdcl
  val () = tr12env_pshlam0(env)
  val f2as = pl_params(loc, params)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2body = pl_exp(env, body)
  val () = tr12env_poplam0(env)
in
  d2fundcl_make_args
    (loc, d2v, f2as, S2RESnone(), TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
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
//
(* ****** ****** *)
(*
end of [frontend/DATS/pylower_dynexp.dats]
*)
