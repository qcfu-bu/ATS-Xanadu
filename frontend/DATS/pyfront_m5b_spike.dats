(* ****** ****** *)
(*
** M5b GATING SPIKE driver — proves a DATATYPE declaration can be CONSTRUCTED
** DIRECTLY at level-2 (no L1, no lexer/parser) and that BOTH the datatype decl
** AND code that USES it (a pattern match) TYPECHECK to nerror=0.
**
** Hand-builds the L2 equivalent of:
**
**     enum Opt:
**         case Nothing
**         case Just(Int)
**
**     def f(o: Opt) -> Int:
**         match o:
**             case Nothing: 0
**             case Just(x): x
**
** i.e. a `D2Cdatatype(d1ecl, [Opt])` decl (Opt's two d2cons Nothing/Just stored
** via s2cst_set_d2cs) + a `D2Cfundclst` for `f` whose body is `D2Ecas0` over `o`.
** Both decls go into ONE d2parsed; the full L2->L3 pipeline runs (trans2a/trsym2b/
** t2read0/trans23/tread3a) and we assert nerror=0 after tread3a.
**
** RECIPE MIRRORED FROM (cited):
**   trans12_decl00.dats f0_datatype (3122) + trans12_d1typ (3776) + trans12_d1tsc
**     (3830) : s2cst_make_idst -> tr12env_add1_s2cst -> build cons -> set ctags ->
**     s2cst_set_d2cs -> tr12env_add1_d2cs ; con sexp via s2exp_fun1_nil0(npf, farg,
**     s2exp_cst(s2c)) (trans12_d1tcn 4067).
**   trans23_decl00.dats f0_datatype (802) : binds (d1cl,s2cs) but reads NEITHER —
**     just wraps the d2cl into D3Cd2ecl. So the d1ecl field is VESTIGIAL for the
**     typecheck path -> d1ecl_none0(loc) is safe.
**
** PURELY ADDITIVE: only CALLS the compiler-as-a-library (lib2xatsopt). Nothing
** under srcgen2/ or language-server/ is modified. Typecheck-only (no codegen).
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
// L1 AST makers d1ecl_none0 (dynexp1) + s1exp_none0 (staexp1) are NOT in
// libxatsopt.hats (it staloads only staexp2/dynexp2) — staload them here. We need
// d1ecl_none0 for the (vestigial) first field of D2Cdatatype, and s1exp_none0 for
// the `given` slot of a D2Pannot binder.
#staload "./../../srcgen2/SATS/staexp1.sats"
#staload "./../../srcgen2/SATS/dynexp1.sats"
//
(* ****** ****** *)
//
// FFI: progress markers / nerror line -> stderr (so stdout stays clean). Implemented
// in CATS/pyfront_m5b_spike.cats.
//
#extern fun PYB_log(s: strn): void = $extnam()
#extern fun PYB_log_int(s: strn, n: sint): void = $extnam()
//
(* ****** ****** *)
//
// resolve a (prelude) static type NAME to its s2exp, exactly as pylower_staexp.dats
// resolve_typ does. Used to obtain `Int`'s s2exp for the Just(Int) constructor: the
// surface `Int` aliases to the prelude internal `the_s2exp_sint0` (M5a finding), which
// is the SAME T2Pcst the int literal carries.
//
fun
resolve_typ_name(env: !tr12env, name: strn): s2exp = let
  val key = symbl_make_name(name)
  val sopt = tr12env_find_s2itm(env, key)
in
  case+ sopt of
  | ~optn_vt_cons(s2i) =>
    (
      case+ s2i of
      | S2ITMcst(s2cs) =>
          if list_nilq(s2cs) then s2exp_none0() else s2exp_cst(s2cs.head())
      | S2ITMvar(s2v)  => s2exp_var(s2v)
      | S2ITMenv(_)    => s2exp_none0()
    )
  | ~optn_vt_nil() => s2exp_none0()
end
//
(* ****** ****** *)
//
// resolve a bound dynamic VARIABLE by name to a D2Evar reference (template A,
// D2ITMvar arm). Used for the scrutinee `o` and the bound pattern var `x`. The
// name is guaranteed bound at the call sites, so the recovery yields a none-node.
//
fun
resolve_var(env: !tr12env, loc: loctn, name: strn): d2exp = let
  val dopt = tr12env_find_d2itm(env, symbl_make_name(name))
in
  case+ dopt of
  | ~optn_vt_cons(d2i) =>
    (
      case+ d2i of
      | D2ITMvar(d2v) => d2exp_make_node(loc, D2Evar(d2v))
      | _ => d2exp_none0(loc)
    )
  | ~optn_vt_nil() => d2exp_none0(loc)
end
//
(* ****** ****** *)
//
// BUILD the whole program directly at L2 and return a d2parsed.
//
fun
build_d2parsed((*void*)): d2parsed = let
//
val loc = loctn_dummy()
//
val env = tr12env_make_nil()
//
// ===== the datatype `Opt` (sort the_sort2_tbox = a boxed datatype) =============
//
// (1) create the type constructor s2cst (trans12_d1typ:3815).
val sym_opt = symbl_make_name("Opt")
val s2c_opt = s2cst_make_idst(loc, sym_opt, the_sort2_tbox)
//
// (2) register the s2cst FIRST, so the cons (and any recursive use) can reference it
//     (trans12_d1typ:3821 — registration BEFORE con elaboration).
val () = tr12env_add1_s2cst(env, s2c_opt)
//
// (3) the datatype's own s2exp (`Opt` as a type), via s2exp_cst (trans12_d1tcn:4116).
val s2e_opt = s2exp_cst(s2c_opt)
//
// (4) Int's s2exp for Just(Int) — the prelude internal sint type (M5a alias target).
val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
// (5) the two data constructors. Each con's sexp is a CONSTRUCTOR-FUNCTION TYPE
//     `(args) -> Opt` built by s2exp_fun1_nil0(npf, farg, fres) — EXACTLY what
//     trans12_d1tcn does (4121), with fres = s2exp_cst(Opt) and farg the arg list.
//     NULLARY `Nothing` : farg = []   -> () -> Opt
//     UNARY   `Just`    : farg = [Int]-> (Int) -> Opt
// d2con_make_idtp derives the con NAME via dconid_sym, which accepts only
// T_IDALP / T_IDSYM tokens (dynexp2.dats:522) — so use T_IDALP for the names.
val tok_nothing = token_make_node(loc, T_IDALP("Nothing"))
val tok_just    = token_make_node(loc, T_IDALP("Just"))
//
val sexp_nothing = s2exp_fun1_nil0((-1)(*npf*), list_nil(), s2e_opt)
val sexp_just    = s2exp_fun1_nil0((-1)(*npf*), list_sing(s2e_int), s2e_opt)
//
val d2c_nothing = d2con_make_idtp(tok_nothing, list_nil()(*tqas*), sexp_nothing)
val d2c_just    = d2con_make_idtp(tok_just,    list_nil()(*tqas*), sexp_just)
//
// (6) assign runtime ctags (trans12_d1tsc:3860-3867 assigns the list index; we do it
//     explicitly to avoid the list_iforitm template). 0 = Nothing, 1 = Just.
val () = d2con_set_ctag(d2c_nothing, 0)
val () = d2con_set_ctag(d2c_just, 1)
//
val d2cs_opt = list_cons(d2c_nothing, list_sing(d2c_just))
//
// (7) wire the cons onto the type constructor (so a pattern over Opt finds its cons)
//     and register the cons into the env (trans12_d1tsc:3871-3873).
val () = s2cst_set_d2cs(s2c_opt, d2cs_opt)
val () = tr12env_add1_d2conlst(env, d2cs_opt)
//
// (8) the D2Cdatatype decl. FIRST field is a level-1 d1ecl — VESTIGIAL for typecheck
//     (trans23 f0_datatype binds it but never reads it), so a dummy is safe.
val dtdecl =
  d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c_opt)))
//
// ===== the function `def f(o: Opt) -> Int: match o: ...` =======================
//
// bind the fun NAME first (a def group is recursive; trans12 f0_fundclst order).
val sym_f = symbl_make_name("f")
val d2v_f = d2var_new2_name(loc, sym_f)
val () = tr12env_add0_d2var(env, d2v_f)
//
// the parameter `o : Opt` -> an ANNOTATED binder D2Pannot(D2Pvar o, _, Opt) so its
// styp is Opt (pylower pl_one_param / M5a). Wrapped in F2ARGdapp(0, [pat]).
val d2v_o = d2var_new2_name(loc, symbl_make_name("o"))
val pat_o = d2pat_var(loc, d2v_o)
val pat_o_annot = d2pat_make_node(loc, D2Pannot(pat_o, s1exp_none0(loc), s2e_opt))
val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_o_annot))))
//
// the return annotation `-> Int`.
val sres = S2RESsome(S2EFFnone(), s2e_int)
//
// enter the fun's param scope, bind the param, build the body, pop.
val () = tr12env_pshlam0(env)
val () = tr12env_add0_f2arglst(env, f2as)
//
// ---- the body: `match o: case Nothing: 0 case Just(x): x` -----------------------
//
// the scrutinee `o` (resolves to the bound param d2var).
val d2scrut = resolve_var(env, loc, "o")
//
// arm 1 : `case Nothing: 0`  — a NULLARY con pattern. CRITICAL: a nullary con
// pattern must be WRAPPED in D2Pdap0 (an argless application), NOT a bare D2Pcon.
// The stock trans12 does exactly this (my_d2pat_con @ trans12_dynexp.dats:232-240
// returns d2pat_dap0(d2pat_con(...))). trans2a's f0_dap0 then turns D2Pdap0(con)
// into d2pat_dapp(con, -1, []) and applies the con's `() -> Opt` function type to
// ZERO args, yielding the RESULT type Opt. A bare D2Pcon leaves the pattern typed
// as the raw `() -> Opt` con-function type, which then fails to unify with Opt.
val arm1 = let
  val pcon = d2pat_con(loc, d2c_nothing)
  val d2p = d2pat_make_node(loc, D2Pdap0(pcon))
  val dgpt = d2gpt_make_node(loc, D2GPTpat(d2p))
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_d2gpt(env, dgpt)
  val body = d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01("0"))))
  val () = tr12env_poplam0(env)
in
  d2cls_make_node(loc, D2CLScls(dgpt, body))
end
//
// arm 2 : `case Just(x): x` — a UNARY con-application pattern D2Pdapp(con, -1, [x]);
//         the binder `x` is visible to the body, which is just `x`.
val arm2 = let
  val phd = d2pat_con(loc, d2c_just)
  val d2v_x = d2var_new2_name(loc, symbl_make_name("x"))
  val pat_x = d2pat_var(loc, d2v_x)
  val d2p = d2pat_make_node(loc, D2Pdapp(phd, (-1), list_sing(pat_x)))
  val dgpt = d2gpt_make_node(loc, D2GPTpat(d2p))
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_d2gpt(env, dgpt)
  // the body `x` : resolve through the scope the gpt just bound.
  val body = resolve_var(env, loc, "x")
  val () = tr12env_poplam0(env)
in
  d2cls_make_node(loc, D2CLScls(dgpt, body))
end
//
val arms = list_cons(arm1, list_sing(arm2))
val tok_case = token_make_node(loc, T_CASE(CSKcas0))
val d2body = d2exp_make_node(loc, D2Ecas0(tok_case, d2scrut, arms))
//
val () = tr12env_poplam0(env)  // exit the fun's param scope
//
val tok_val = token_make_node(loc, T_VAL(VLKval))
val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
//
val d2f =
  d2fundcl_make_args
    (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
val fundecl =
  d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil()(*tqas*), list_nil()(*d2cs*), list_sing(d2f)))
//
// ===== assemble the d2parsed (datatype decl + fun decl in ONE decl list) =======
//
val decls = list_cons(dtdecl, list_sing(fundecl))
val t2penv = tr12env_free_top(env)
val source = LCSRCnone0()
//
val dpar =
  d2parsed_make_args
  ( 1(*stadyn:dynamic*), 0(*nerror*), source
  , tr01env_free_top(tr01env_make_nil()), t2penv, optn_cons(decls) )
//
in
  dpar
end // end of [build_d2parsed]
//
(* ****** ****** *)
//
// the full L2 -> L3 pipeline (mirrors pyfront_d3parsed_of_fpath in pyfront_m3.dats:
// trans2a overload-res -> trsym2b symbol-res -> t2read0 L2 check -> trans23 L2->L3).
//
fun
run_pipeline(dpar: d2parsed): d3parsed = let
  val dpar = d2parsed_of_trans2a(dpar)
  val () = PYB_log("[m5b] trans2a (overload res) done")
  val ( ) = d2parsed_by_trsym2b(dpar)
  val () = PYB_log("[m5b] trsym2b (symbol res) done")
  val dpar = d2parsed_of_t2read0(dpar)
  val () = PYB_log("[m5b] t2read0 (L2 read/check) done")
  val dp3 = d3parsed_of_trans23(dpar)
  val () = PYB_log("[m5b] trans23 (L2 -> L3) done")
in
  dp3
end
//
(* ****** ****** *)
//
fun
mymain_m5b((*void*)): void = let
//
// one-time global bootstrap (idempotent; required before name resolution).
val _ = the_fxtyenv_pvsl00d()
val _ = the_tr12env_pvsl00d()
//
val () = PYB_log("######## M5b datatype-construction GATING SPIKE ########")
val () = PYB_log("[m5b] building the enum Opt + f(match) program directly at L2 ...")
val dpar = build_d2parsed()
val () = PYB_log("[m5b] d2parsed built; running L2->L3 pipeline ...")
//
val dp3 = run_pipeline(dpar)
//
// CRITICAL: trans23 records type errors as errck NODES; tread3a SCANS them and
// updates nerror. Run tread3a FIRST, then read the REAL nerror (M3 finding).
val dp3 = d3parsed_of_tread3a(dp3)
val nerror = d3parsed_get_nerror(dp3)
val () = PYB_log_int("[m5b] nerror (after tread3a) =", nerror)
//
// the stock reporter on stderr (prints the errck nodes if nerror>0).
val out0 = g_stderr()
val () = PYB_log("[m5b] -- f3perr0_d3parsed (stock reporter) --")
val () = f3perr0_d3parsed(out0, dp3)
//
in
  if nerror = 0 then
    PYB_log("RESULT: PASS (datatype decl + match typecheck, nerror=0)")
  else
    PYB_log("RESULT: FAIL (nerror != 0 ; see f3perr0 above)")
end // end of [mymain_m5b]
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_m5b()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_m5b_spike.dats]
*)
