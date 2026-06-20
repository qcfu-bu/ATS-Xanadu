(* ****** ****** *)
(*
** M5b.3b GATING SPIKE driver — proves (or characterizes the blocker for)
** DIRECT-L2 construction of PARAMETRIC (generic) types:
**   P1  parametric DATATYPE  `Opt[A] = { None | Some(A) }`  + instantiation at
**         int + a `match` that binds `x:int` in the `Some(x)` arm.
**   P2  parametric ALIAS/RECORD `Pair[A,B] = {fst:A, snd:B}` + instantiation at
**         [int,int] + a field projection `p.fst`.
**
** The PARAMETRIC delta vs the MONOMORPHIC M5b spike (3 things):
**   (1) the type's s2cst SORT is a FUNCTION sort  (type)->type  (one `type` per
**       param), built by  S2Tfun1(list_of(the_sort2_type), the_sort2_tbox)
**       — exactly what f0_tmas does (trans12_decl00.dats:3580-3600).
**   (2) the type PARAMS are s2vars created by s2var_make_idst(sym, the_sort2_type)
**       and pushed into scope with tr12env_add0_s2var inside a pshlam0/poplam0
**       lam-scope — exactly f1_s2vs (trans12_decl00.dats:3603-3664). The con arg
**       type `A` resolves to s2exp_var(s2v_A); the result `Opt(A)` is built by
**       s2exp_apps(loc, s2exp_cst(Opt), [s2exp_var(s2v_A)])  (f1_sres+f0_idxs,
**       trans12_decl00.dats:3933-4010, 4111-4118).
**   (3) the con is UNIVERSALLY QUANTIFIED over the params — but NOT inside the
**       sexp: the quantifier lives in the d2con's `tqas` field. trans12 builds
**       tqas = f1_tqas(s2c0, svss) = [ t2qag(loc, [s2v_A]) ] and passes it to
**       d2con_make_idtp(tok, tqas, sexp)  (trans12_decl00.dats:4666-4694, 4068-
**       4079). The con sexp itself stays  (A)->Opt(A)  via s2exp_fun1_nil0.
**   For the ALIAS, f0_sexpdef wraps the body in s2exp_lam1(s2vs, body) per param
**       group (auxslam, trans12_decl00.dats:1399-1424); s2t2 = sdef.sort() then
**       becomes the function sort automatically (staexp2.dats:1005).
**
** Each probe is an INDEPENDENT d2parsed run (own fresh env, own node process via
** PYB_probe / PROBE env) so a hard XATS000_cfail in one is ISOLATED.
**
** PURELY ADDITIVE: only CALLS lib2xatsopt. Nothing under srcgen2/ or
** language-server/ is modified. Typecheck-only (no codegen).
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
// libxatsopt.hats; staload them (vestigial d1ecl for D2Cdatatype, given-slot of
// D2Pannot), exactly as the M5b enum spike does.
#staload "./../../srcgen2/SATS/staexp1.sats"
#staload "./../../srcgen2/SATS/dynexp1.sats"
//
(* ****** ****** *)
//
#extern fun PYB_log(s: strn): void = $extnam()
#extern fun PYB_log_int(s: strn, n: sint): void = $extnam()
#extern fun PYB_probe((*void*)): sint = $extnam()
//
(* ****** ****** *)
//
// resolve a (prelude) static type NAME to its s2exp, exactly as the M5b spikes.
// Used to obtain `Int` (the prelude internal the_s2exp_sint0 = the M5a direct
// T2Pcst that int literals/annotations carry).
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
// resolve a bound dynamic VARIABLE by name to a D2Evar reference (the scrutinee
// `o`, the bound pattern var `x`, the param `p`).
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
// run ONE d2parsed (one decl list) through the full L2->L3 pipeline and return
// the post-tread3a nerror. EACH probe builds its own fresh env + d2parsed.
//
fun
run_one(label: strn, decls: d2eclist, t2penv: d2topenv): sint = let
  val source = LCSRCnone0()
  val dpar =
    d2parsed_make_args
    ( 1(*stadyn:dynamic*), 0(*nerror*), source
    , tr01env_free_top(tr01env_make_nil()), t2penv, optn_cons(decls) )
//
  val dpar = d2parsed_of_trans2a(dpar)
  val ( ) = d2parsed_by_trsym2b(dpar)
  val dpar = d2parsed_of_t2read0(dpar)
  val dp3 = d3parsed_of_trans23(dpar)
  val dp3 = d3parsed_of_tread3a(dp3)
  val nerror = d3parsed_get_nerror(dp3)
  val () = PYB_log_int(label, nerror)
//
  // stock reporter on stderr (prints errck nodes when nerror>0).
  val () = (if nerror > 0 then f3perr0_d3parsed(g_stderr(), dp3))
in
  nerror
end
//
(* ****** ****** *)
//
// ===== PROBE P1 : parametric datatype Opt[A] + Opt[Int] match ==================
//
//   enum Opt[A]:
//       case None
//       case Some(A)
//   def f(o: Opt[Int]) -> Int:
//       match o:
//           case None:    0
//           case Some(x): x
//
fun
probe_P1((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// (1) the type constructor `Opt` with a FUNCTION SORT  (type)->type.
//     DELTA vs monomorphic: NOT the_sort2_tbox, but S2Tfun1([type], tbox).
  val sym_opt = symbl_make_name("Opt")
  val s2t_opt = S2Tfun1(list_sing(the_sort2_type), the_sort2_tbox)
  val s2c_opt = s2cst_make_idst(loc, sym_opt, s2t_opt)
  val () = tr12env_add1_s2cst(env, s2c_opt)
//
// (2) the param `A` : an s2var of sort `type`, pushed into a lam-scope while we
//     elaborate the con types (mirrors trans12_d1tsc's pshlam0 + f1_s2vs).
  val () = tr12env_pshlam0(env)
  val s2v_A = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val () = tr12env_add0_s2var(env, s2v_A)
//
// (3) the result type `Opt(A)` = s2exp_apps(Opt, [A]).  DELTA vs monomorphic:
//     the result is an APPLICATION, not the bare s2exp_cst(Opt).
  val s2e_A   = s2exp_var(s2v_A)
  val s2e_opt_A = s2exp_apps(loc, s2exp_cst(s2c_opt), list_sing(s2e_A))
//
// (4) the two cons.  Each con SEXP stays a plain con-function type  (args)->Opt(A)
//     via s2exp_fun1_nil0 — the quantifier is NOT in the sexp.  DELTA vs
//     monomorphic: the QUANTIFICATION lives in the `tqas` arg of d2con_make_idtp.
//       None : tqas=[{A}]  sexp = ()  -> Opt(A)
//       Some : tqas=[{A}]  sexp = (A) -> Opt(A)
  val tok_none = token_make_node(loc, T_IDALP("None"))
  val tok_some = token_make_node(loc, T_IDALP("Some"))
//
  val sexp_none = s2exp_fun1_nil0((-1)(*npf*), list_nil(), s2e_opt_A)
  val sexp_some = s2exp_fun1_nil0((-1)(*npf*), list_sing(s2e_A), s2e_opt_A)
//
// the universal quantifier {A:type} over BOTH cons, as a t2qaglst = [ t2qag(loc,[A]) ]
// (mirrors f1_tqas: trans12_decl00.dats:4672-4694).
  val tqas = list_sing(t2qag(loc, list_sing(s2v_A))) : t2qaglst
//
  val d2c_none = d2con_make_idtp(tok_none, tqas, sexp_none)
  val d2c_some = d2con_make_idtp(tok_some, tqas, sexp_some)
//
  val () = d2con_set_ctag(d2c_none, 0)
  val () = d2con_set_ctag(d2c_some, 1)
//
  val d2cs_opt = list_cons(d2c_none, list_sing(d2c_some))
  val () = s2cst_set_d2cs(s2c_opt, d2cs_opt)
  val () = tr12env_add1_d2conlst(env, d2cs_opt)
//
// pop the param lam-scope now that the cons are fully elaborated.
  val () = tr12env_poplam0(env)
//
  val dtdecl =
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c_opt)))
//
// ===== the function `def f(o: Opt[Int]) -> Int: match o: ...` ===================
//
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
// the param type `Opt(Int)` = INSTANTIATE Opt at int via s2exp_apps.
  val s2e_opt_int = s2exp_apps(loc, s2exp_cst(s2c_opt), list_sing(s2e_int))
//
  val sym_f = symbl_make_name("f")
  val d2v_f = d2var_new2_name(loc, sym_f)
  val () = tr12env_add0_d2var(env, d2v_f)
//
  val d2v_o = d2var_new2_name(loc, symbl_make_name("o"))
  val pat_o = d2pat_var(loc, d2v_o)
  val pat_o_annot = d2pat_make_node(loc, D2Pannot(pat_o, s1exp_none0(loc), s2e_opt_int))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_o_annot))))
//
  val sres = S2RESsome(S2EFFnone(), s2e_int)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
//
// ---- the body: `match o: case None: 0 case Some(x): x` -------------------------
//
  val d2scrut = resolve_var(env, loc, "o")
//
// arm 1 : `case None: 0` — NULLARY con pattern WRAPPED in D2Pdap0 (M5b finding).
  val arm1 = let
    val pcon = d2pat_con(loc, d2c_none)
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
// arm 2 : `case Some(x): x` — UNARY con-app pattern; x must bind at int (Opt
// instantiated at int, so the quantified con's A := int and x : int).
  val arm2 = let
    val phd = d2pat_con(loc, d2c_some)
    val d2v_x = d2var_new2_name(loc, symbl_make_name("x"))
    val pat_x = d2pat_var(loc, d2v_x)
    val d2p = d2pat_make_node(loc, D2Pdapp(phd, (-1), list_sing(pat_x)))
    val dgpt = d2gpt_make_node(loc, D2GPTpat(d2p))
    val () = tr12env_pshlam0(env)
    val () = tr12env_add0_d2gpt(env, dgpt)
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
  val decls = list_cons(dtdecl, list_sing(fundecl))
  val t2penv = tr12env_free_top(env)
in
  run_one("[P1] enum Opt[A]{None,Some(A)} ; f(o:Opt[Int])->Int:match  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// build the boxed record s2exp `{fst:A, snd:B}` with the PARAM s2vars in the
// field types =  s2exp_make_node(tbox, S2Etrcd(TRCDbox0, -1, [fst:A, snd:B])).
//
fun
build_pair_rcd(s2e_A: s2exp, s2e_B: s2exp): s2exp = let
  val lab_fst = LABsym(symbl_make_name("fst"))
  val lab_snd = LABsym(symbl_make_name("snd"))
  val fld_fst = S2LAB(lab_fst, s2e_A)
  val fld_snd = S2LAB(lab_snd, s2e_B)
  val flds  = list_cons(fld_fst, list_sing(fld_snd))
in
  s2exp_make_node(the_sort2_tbox, S2Etrcd(TRCDbox0, (-1)(*npf*), flds))
end
//
// ===== PROBE P2 : parametric alias Pair[A,B] = {fst:A,snd:B} + projection ======
//
//   type Pair[A,B] = { fst: A, snd: B }
//   def g(p: Pair[Int, Int]) -> Int: p.fst
//
fun
probe_P2((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// the params A,B : s2vars of sort `type`, pushed into a lam-scope while we build
// the record body (mirrors f0_sexpdef's pshlam0 + trans12_s1maglst, 1353-1356).
  val () = tr12env_pshlam0(env)
  val s2v_A = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val s2v_B = s2var_make_idst(symbl_make_name("B"), the_sort2_type)
  val () = tr12env_add0_s2var(env, s2v_A)
  val () = tr12env_add0_s2var(env, s2v_B)
  val s2e_A = s2exp_var(s2v_A)
  val s2e_B = s2exp_var(s2v_B)
//
// the record body with PARAM fields, then WRAP in s2exp_lam1([A,B], body) — the
// parametric-alias DELTA (auxslam: trans12_decl00.dats:1399-1424).
  val s2e_rcd = build_pair_rcd(s2e_A, s2e_B)
  val s2e_lam = s2exp_lam1(list_cons(s2v_A, list_sing(s2v_B)), s2e_rcd)
//
  val () = tr12env_poplam0(env)
//
// the D2Csexpdef for `Pair`.  s2t2 = sdef.sort() is now a FUNCTION sort
// (type)->(type)->tbox automatically (staexp2.dats:1005). Mirrors f0_sexpdef's
// final block (1434-1464).
  val sym_pair = symbl_make_name("Pair")
  val s2t2 = s2e_lam.sort()
  val tdef = s2exp_stpize(s2e_lam)
  val s2c_pair = s2cst_make_idst(loc, sym_pair, s2t2)
  val () = s2cst_set_sexp(s2c_pair, s2e_lam)
  val () = s2cst_set_styp(s2c_pair, tdef)
  val () = tr12env_add1_s2cst(env, s2c_pair)
  val dcl_alias = d2ecl_make_node(loc, D2Csexpdef(s2c_pair, s2e_lam))
//
// def g(p: Pair[Int,Int]) -> Int: p.fst
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
// INSTANTIATE Pair at [int,int] via s2exp_apps.
  val s2e_pair_ii = s2exp_apps(loc, s2exp_cst(s2c_pair), list_cons(s2e_int, list_sing(s2e_int)))
//
  val sym_g = symbl_make_name("g")
  val d2v_g = d2var_new2_name(loc, sym_g)
  val () = tr12env_add0_d2var(env, d2v_g)
//
  val d2v_p = d2var_new2_name(loc, symbl_make_name("p"))
  val pat_p = d2pat_var(loc, d2v_p)
  val pat_p_annot = d2pat_make_node(loc, D2Pannot(pat_p, s1exp_none0(loc), s2e_pair_ii))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_p_annot))))
//
  val sres = S2RESsome(S2EFFnone(), s2e_int)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
//
  val d2body = let
    val d2p = resolve_var(env, loc, "p")
    val drxp = d2rxp_new1(loc)
    val lab  = LABsym(symbl_make_name("fst"))
  in
    d2exp_make_node(loc, D2Eproj(token_make_node(loc, T_VAL(VLKval)), drxp, lab, d2p))
  end
//
  val () = tr12env_poplam0(env)
//
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
//
  val d2g =
    d2fundcl_make_args
      (loc, d2v_g, f2as, sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
  val dcl_g =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil()(*tqas*), list_nil()(*d2cs*), list_sing(d2g)))
//
  val decls = list_cons(dcl_alias, list_sing(dcl_g))
  val t2penv = tr12env_free_top(env)
in
  run_one("[P2] type Pair[A,B]={fst:A,snd:B} ; g(p:Pair[Int,Int])->Int:p.fst  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
fun
mymain_m5b3b((*void*)): void = let
//
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
//
  val () = PYB_log("######## M5b.3b PARAMETRIC generics GATING SPIKE ########")
//
  val sel = PYB_probe()
  val _ =
    (
      case+ sel of
      | 1 => let val () = PYB_log("---- PROBE P1 (parametric datatype Opt[A] + match) ----")
                 val _ = probe_P1() in 0 end
      | 2 => let val () = PYB_log("---- PROBE P2 (parametric alias Pair[A,B] + proj) ----")
                 val _ = probe_P2() in 0 end
      | _ => let val () = PYB_log("---- PROBE P1 ----") val _ = probe_P1()
                 val () = PYB_log("---- PROBE P2 ----") val _ = probe_P2()
              in 0 end
    ) : sint
in
  PYB_log("######## END M5b.3b SPIKE ########")
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_m5b3b()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_m5b3b_spike.dats]
*)
