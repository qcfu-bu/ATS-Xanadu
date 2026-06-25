(* ****** ****** *)
(*
** C-PROOF (Area C — proof surface) STAGE-0 SPIKE driver.
**
** Hand-builds at L2 (NO surface, NO lexer/parser) and runs each probe through the real
** stock pipeline trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a, then prints the
** post-tread3a nerror. EACH probe is an INDEPENDENT d2parsed in its OWN node process
** (PYB_probe selector) so a hard XATS000_cfail is ISOLATED.
**
** Probes (the three Area-C L2 pieces):
**   CP-MET  @terminates[n]  — a recursive indexed `def fact[n:i0](k:Idx(n)):SInt` carrying a
**           TERMINATION METRIC `.<n>.` attached as F2ARGmets([s2exp_var n]) inside the fn's
**           f2arglst (mets f2arg BEFORE the dapp f2arg). Does the metric f2arg ride the
**           D2Cfundclst to nerror=0?  (F2ARGmets : dynexp2.sats:1323; trans23 F3ARGmets :
**           trans23_dynexp.dats:3166; the type is metric-agnostic — trans2a_utils0:367 SKIPS it.)
**   CP-UNP  VCons{m}(x,rest)  — an EXISTENTIAL-UNPACK pattern. A `Vec[A,n]` datatype (VNil :
**           {A}     ()       -> Vec(A,0)  ;  VCons : {A}{n} (A, Vec(A,n)) -> Vec(A,n+1)) and a
**           `case v of VCons{m}(x,rest) => x`. The con pattern is wrapped d2pat_con -> dap0,
**           then d2pat_sapp(loc, conpat, [s2v m]) introduces the hidden index binder `m`, then
**           d2pat_dapp(loc, sappPat, -1, [x,rest]) applies the value args. nerror=0?
**           (d2pat_sapp : dynexp2.sats:885 ; my_d2pat_sapp/my_d2pat_dapp recipe :
**           trans12_dynexp.dats:245/266 ; D2Psapp : dynexp2.sats:744.)
**   CP-WTH  @with[pf: LE(m,n)]  — a proof-augmented clause/case. The d2fundcl_make_args / d2val
**           withtype slot is WTHS2EXPsome(token, s2exp) (dynexp2.sats:1434). Probe whether a
**           proof binding can be attached to a CASE-CLAUSE at L2 with a clean structural target.
**           FINDING: WTHS2EXPsome rides a d2fundcl/d2valdcl to nerror=0 (a DEF-level withtype is
**           GO). BUT the surface `@with` decorates a CASE — a per-arm clause withtype. There is NO
**           per-clause WTHS2EXP slot on D2CLScls (dynexp2.sats:1358 = (d2gpt, d2exp), no withtype
**           field) — only the def/val-level slot exists. So @with on a *case arm* has no clean
**           structural L2 target; it would have to re-shape to a def/val withtype. DEFERRED (the
**           decorator/payload infra is wired so a future def-level @with lands trivially).
**
** PURELY ADDITIVE: only CALLS lib2xatsopt. Nothing under srcgen2/ or language-server/ is
** modified. Typecheck-only (no codegen).
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
fun
resolve_s2cst(env: !tr12env, name: strn): s2cstopt_vt = let
  val key = symbl_make_name(name)
  val sopt = tr12env_find_s2itm(env, key)
in
  case+ sopt of
  | ~optn_vt_cons(s2i) =>
    (
      case+ s2i of
      | S2ITMcst(s2cs) =>
          if list_nilq(s2cs) then optn_vt_nil() else optn_vt_cons(s2cs.head())
      | _ => optn_vt_nil()
    )
  | ~optn_vt_nil() => optn_vt_nil()
end
//
fun
build_binop
(env: !tr12env, loc: loctn, opname: strn, a: s2exp, b: s2exp): s2exp = let
  val copt = resolve_s2cst(env, opname)
in
  case+ copt of
  | ~optn_vt_cons(c) =>
      s2exp_apps(loc, s2exp_cst(c), list_cons(a, list_sing(b)))
  | ~optn_vt_nil()    => s2exp_none0()
end
//
(* ****** ****** *)
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
  val () = (if nerror > 0 then f3perr0_d3parsed(g_stderr(), dp3))
in
  nerror
end
//
(* ****** ****** *)
//
// ===== PROBE CP-MET : @terminates[n] termination metric  =========================
//
//   fact : {n:i0} (Idx(n)) -> SInt     with metric  .<n>.
//   Idx : (i0) -> tbox is a small indexed type con (a self-contained stand-in for SInt[n]).
//   The body is the recursive `fact(k)` (an int-result placeholder via Mk0 : () -> SInt-ish),
//   here we keep the body trivial-recursive: `fact(k)` self-call so the recursive name resolves;
//   the metric f2arg `.<n>.` is the F2ARGmets([s2exp_var n]) that rides the f2arglst.
//
fun
probe_CP_MET((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// (1) the indexed type con  Idx : (i0) -> tbox  (a stand-in for SInt[n]).
  val sym_idx = symbl_make_name("Idx")
  val s2t_idx = S2Tfun1(list_sing(the_sort2_int0), the_sort2_tbox)
  val s2c_idx = s2cst_make_idst(loc, sym_idx, s2t_idx)
  val () = tr12env_add1_s2cst(env, s2c_idx)
//
// (2) a nullary result con  R : () -> Idx(0)  so the body has a typed value to return that
//     unifies with the result type.  We make the result type just `Idx(n)` to keep it simple:
//     fact returns an Idx(n) and the body is a recursive self-call fact(k).
//
// (3) the fn  fact : {n:i0} (Idx(n)) -> Idx(n)  with the metric  .<n>.
  val () = tr12env_pshlam0(env)
  val s2v_n = s2var_make_idst(symbl_make_name("n"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_n)
  val s2e_n = s2exp_var(s2v_n)
  val s2e_idx_n =
    s2exp_apps(loc, s2exp_cst(s2c_idx), list_sing(s2e_n))
//
//   the parameter pattern  k : Idx(n)  (annotated).
  val sym_k = symbl_make_name("k")
  val d2v_k = d2var_new2_name(loc, sym_k)
  val pat_k = d2pat_var(loc, d2v_k)
  val pat_k_annot =
    d2pat_make_node(loc, D2Pannot(pat_k, s1exp_none0(loc), s2e_idx_n))
//
//   THE METRIC f2arg  .<n>.  ==> F2ARGmets([ s2exp_var n ]).
  val f2a_met = f2arg_make_node(loc, F2ARGmets(list_sing(s2e_n)))
//   the value-arg f2arg.
  val f2a_dap = f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_k_annot)))
//   ORDER: the metric f2arg precedes the value-arg f2arg (stock f0_f2as skips mets, descends).
  val f2as = list_cons(f2a_met, list_sing(f2a_dap)) : f2arglst
//
  val sres = S2RESsome(S2EFFnone(), s2e_idx_n)
//
//   the recursive name fact (bound BEFORE the body so the self-call resolves).
  val sym_fact = symbl_make_name("fact")
  val d2v_fact = d2var_new2_name(loc, sym_fact)
  val () = tr12env_add0_d2var(env, d2v_fact)
//
//   body scope: register the param, build the body `fact(k)` (recursive self-call).
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2e_fact = d2exp_make_node(loc, D2Evar(d2v_fact))
  val d2e_k    = d2exp_make_node(loc, D2Evar(d2v_k))
  val d2body   = d2exp_make_node(loc, D2Edapp(d2e_fact, (-1), list_sing(d2e_k)))
  val () = tr12env_poplam0(env)
//
  val () = tr12env_poplam0(env)
  val tqas = list_sing(t2qag(loc, list_sing(s2v_n))) : t2qaglst
//
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2f =
    d2fundcl_make_args
      (loc, d2v_fact, f2as, sres, TEQD2EXPsome(token_make_node(loc, T_VAL(VLKval)), d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, tqas, list_nil()(*d2cs*), list_sing(d2f)))
//
  val decls = list_sing(fundecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[CP-MET] fact[n](k:Idx(n)):Idx(n) WITH metric .<n>.  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE CP-UNP : VCons{m}(x,rest) existential-unpack pattern  ===============
//
//   datatype Vec(type, i0) :
//     VNil  : {A:type}      ()                 -> Vec(A, 0)
//     VCons : {A:type}{n:i0} (A, Vec(A, n))    -> Vec(A, n+1)
//   def headOr[A](d:A, v:Vec(A, ?)) -> A :
//     case v of
//     | VNil               => d
//     | VCons{m}(x, rest)  => x
//   The VCons arm pattern is built  d2pat_dapp( d2pat_sapp( dap0(con) , [m] ) , -1, [x,rest] ).
//
fun
probe_CP_UNP((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// (1) the con  Vec : (type, i0) -> tbox.
  val sym_vec = symbl_make_name("Vec")
  val s2t_vec = S2Tfun1(list_cons(the_sort2_type, list_sing(the_sort2_int0)), the_sort2_tbox)
  val s2c_vec = s2cst_make_idst(loc, sym_vec, s2t_vec)
  val () = tr12env_add1_s2cst(env, s2c_vec)
//
// (2) VNil : {A}() -> Vec(A, 0).
  val () = tr12env_pshlam0(env)
  val s2v_A0 = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val () = tr12env_add0_s2var(env, s2v_A0)
  val s2e_A0 = s2exp_var(s2v_A0)
  val s2e_vec_A0 =
    s2exp_apps(loc, s2exp_cst(s2c_vec), list_cons(s2e_A0, list_sing(s2exp_int(0))))
  val sexp_vnil = s2exp_fun1_nil0((-1)(*npf*), list_nil(), s2e_vec_A0)
  val tqas_vnil = list_sing(t2qag(loc, list_sing(s2v_A0))) : t2qaglst
  val () = tr12env_poplam0(env)
  val tok_vnil = token_make_node(loc, T_IDALP("VNil"))
  val d2c_vnil = d2con_make_idtp(tok_vnil, tqas_vnil, sexp_vnil)
  val () = d2con_set_ctag(d2c_vnil, 0)
//
// (3) VCons : {A}{n:i0} (A, Vec(A, n)) -> Vec(A, n+1).
  val () = tr12env_pshlam0(env)
  val s2v_A1 = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val s2v_n1 = s2var_make_idst(symbl_make_name("n"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_A1)
  val () = tr12env_add0_s2var(env, s2v_n1)
  val s2e_A1 = s2exp_var(s2v_A1)
  val s2e_n1 = s2exp_var(s2v_n1)
  val s2e_vec_A1n1 =
    s2exp_apps(loc, s2exp_cst(s2c_vec), list_cons(s2e_A1, list_sing(s2e_n1)))
  val s2e_np1 = build_binop(env, loc, "add_i0_i0", s2e_n1, s2exp_int(1))
  val s2e_vec_A1np1 =
    s2exp_apps(loc, s2exp_cst(s2c_vec), list_cons(s2e_A1, list_sing(s2e_np1)))
  val sexp_vcons =
    s2exp_fun1_nil0((-1)(*npf*), list_cons(s2e_A1, list_sing(s2e_vec_A1n1)), s2e_vec_A1np1)
  val tqas_vcons = list_sing(t2qag(loc, list_cons(s2v_A1, list_sing(s2v_n1)))) : t2qaglst
  val () = tr12env_poplam0(env)
  val tok_vcons = token_make_node(loc, T_IDALP("VCons"))
  val d2c_vcons = d2con_make_idtp(tok_vcons, tqas_vcons, sexp_vcons)
  val () = d2con_set_ctag(d2c_vcons, 1)
//
  val d2cs_vec = list_cons(d2c_vnil, list_sing(d2c_vcons))
  val () = s2cst_set_d2cs(s2c_vec, d2cs_vec)
  val () = tr12env_add1_d2conlst(env, d2cs_vec)
  val dtdecl =
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c_vec)))
//
// (4) def headOr : {A:type} (A, Vec(A, n0)) -> A  for SOME n0.  We quantify the def over
//     {A} and an existential-ish index n0 (a universal here is fine; the arm unpacks it).
  val () = tr12env_pshlam0(env)
  val s2v_A2 = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val s2v_n0 = s2var_make_idst(symbl_make_name("n0"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_A2)
  val () = tr12env_add0_s2var(env, s2v_n0)
  val s2e_A2 = s2exp_var(s2v_A2)
  val s2e_n0 = s2exp_var(s2v_n0)
  val s2e_vec_A2n0 =
    s2exp_apps(loc, s2exp_cst(s2c_vec), list_cons(s2e_A2, list_sing(s2e_n0)))
//
//   params:  d : A ,  v : Vec(A, n0).
  val d2v_d = d2var_new2_name(loc, symbl_make_name("d"))
  val pat_d = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_d), s1exp_none0(loc), s2e_A2))
  val d2v_v = d2var_new2_name(loc, symbl_make_name("v"))
  val pat_v = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_v), s1exp_none0(loc), s2e_vec_A2n0))
  val f2as =
    list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_cons(pat_d, list_sing(pat_v))))) : f2arglst
  val sres = S2RESsome(S2EFFnone(), s2e_A2)
//
  val sym_hd = symbl_make_name("headOr")
  val d2v_hd = d2var_new2_name(loc, sym_hd)
  val () = tr12env_add0_d2var(env, d2v_hd)
//
//   body scope: register params, build the case.
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
//
  val d2e_v = d2exp_make_node(loc, D2Evar(d2v_v))
  val d2e_d = d2exp_make_node(loc, D2Evar(d2v_d))
//
//   --- arm 1:  VNil => d  ---  (nullary con pattern: dap0(con)).
  val pat_vnil = d2pat_make_node(loc, D2Pdap0(d2pat_con(loc, d2c_vnil)))
  val dgpt_nil = d2gpt_make_node(loc, D2GPTpat(pat_vnil))
  val () = tr12env_add0_d2gpt(env, dgpt_nil)
  val cls_nil = d2cls_make_node(loc, D2CLScls(dgpt_nil, d2e_d))
//
//   --- arm 2:  VCons{m}(x, rest) => x  ---  the EXISTENTIAL-UNPACK.
//   the hidden index binder m (a FRESH s2var introduced by the pattern's static-arg list).
  val s2v_m = s2var_make_idst(symbl_make_name("m"), the_sort2_int0)
//   the value binders x, rest.
  val d2v_x = d2var_new2_name(loc, symbl_make_name("x"))
  val d2v_rest = d2var_new2_name(loc, symbl_make_name("rest"))
  val pat_x = d2pat_var(loc, d2v_x)
  val pat_rest = d2pat_var(loc, d2v_rest)
//   con-pattern -> sapp([m]) -> dapp(-1,[x,rest]).  The BARE con (NOT dap0-wrapped) is the
//   head of the sapp, exactly as stock my_d2pat_sapp wraps a non-D2Pdap0 con (trans12:258-260),
//   then my_d2pat_dapp applies the value args to the sapp (trans12:306-323).
  val pat_con0 = d2pat_con(loc, d2c_vcons)
  val pat_sapp = d2pat_sapp(loc, pat_con0, list_sing(s2v_m))
  val pat_vcons =
    d2pat_make_node(loc, D2Pdapp(pat_sapp, (-1), list_cons(pat_x, list_sing(pat_rest))))
  val dgpt_cons = d2gpt_make_node(loc, D2GPTpat(pat_vcons))
  val () = tr12env_add0_d2gpt(env, dgpt_cons)
  val d2e_x = d2exp_make_node(loc, D2Evar(d2v_x))
  val cls_cons = d2cls_make_node(loc, D2CLScls(dgpt_cons, d2e_x))
//
  val clss = list_cons(cls_nil, list_sing(cls_cons)) : d2clslst
  val tok_case = token_make_node(loc, T_CASE(CSKcas0))
  val d2body = d2exp_make_node(loc, D2Ecas0(tok_case, d2e_v, clss))
//
  val () = tr12env_poplam0(env)
  val () = tr12env_poplam0(env)
  val tqas_hd = list_sing(t2qag(loc, list_cons(s2v_A2, list_sing(s2v_n0)))) : t2qaglst
//
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2f =
    d2fundcl_make_args
      (loc, d2v_hd, f2as, sres, TEQD2EXPsome(token_make_node(loc, T_VAL(VLKval)), d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, tqas_hd, list_nil()(*d2cs*), list_sing(d2f)))
//
  val decls = list_cons(dtdecl, list_sing(fundecl))
  val t2penv = tr12env_free_top(env)
in
  run_one("[CP-UNP] headOr ; case v of VNil=>d | VCons{m}(x,rest)=>x  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE CP-WTH : @with[pf: LE(m,n)] withtype proof-augmented clause  ========
//
//   Probe the WTHS2EXPsome slot. A def whose d2fundcl carries a withtype:
//     fun f {n:i0} (k: Idx(n)) : Idx(n) =<withtype LE(0, n)> body
//   The withtype slot on d2fundcl_make_args is WTHS2EXPsome(token(*WTH*), s2exp). We attach a
//   PROP s2exp  LE(0, n)  (a relation con) as the withtype and see whether it rides to nerror=0
//   at the def level. This characterizes whether @with has a clean structural L2 target.
//
fun
probe_CP_WTH((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// (1) Idx : (i0) -> tbox  (the indexed value type, as in CP-MET).
  val sym_idx = symbl_make_name("Idx")
  val s2t_idx = S2Tfun1(list_sing(the_sort2_int0), the_sort2_tbox)
  val s2c_idx = s2cst_make_idst(loc, sym_idx, s2t_idx)
  val () = tr12env_add1_s2cst(env, s2c_idx)
//
// (2) LE : (i0, i0) -> prop  (a relation con — the proof's type).
  val sym_le = symbl_make_name("LE")
  val s2t_le = S2Tfun1(list_cons(the_sort2_int0, list_sing(the_sort2_int0)), the_sort2_prop)
  val s2c_le = s2cst_make_idst(loc, sym_le, s2t_le)
  val () = tr12env_add1_s2cst(env, s2c_le)
//
// (3) the fn  f : {n:i0} (Idx(n)) -> Idx(n)  withtype  LE(0, n).
  val () = tr12env_pshlam0(env)
  val s2v_n = s2var_make_idst(symbl_make_name("n"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_n)
  val s2e_n = s2exp_var(s2v_n)
  val s2e_idx_n =
    s2exp_apps(loc, s2exp_cst(s2c_idx), list_sing(s2e_n))
//   the withtype prop:  LE(0, n).
  val s2e_with =
    s2exp_apps(loc, s2exp_cst(s2c_le), list_cons(s2exp_int(0), list_sing(s2e_n)))
//
  val d2v_k = d2var_new2_name(loc, symbl_make_name("k"))
  val pat_k = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_k), s1exp_none0(loc), s2e_idx_n))
  val f2as =
    list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_k)))) : f2arglst
  val sres = S2RESsome(S2EFFnone(), s2e_idx_n)
//
  val sym_f = symbl_make_name("f")
  val d2v_f = d2var_new2_name(loc, sym_f)
  val () = tr12env_add0_d2var(env, d2v_f)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2e_f = d2exp_make_node(loc, D2Evar(d2v_f))
  val d2e_k = d2exp_make_node(loc, D2Evar(d2v_k))
  val d2body = d2exp_make_node(loc, D2Edapp(d2e_f, (-1), list_sing(d2e_k)))
  val () = tr12env_poplam0(env)
//
  val () = tr12env_poplam0(env)
  val tqas = list_sing(t2qag(loc, list_sing(s2v_n))) : t2qaglst
//
  val tok_wth = token_make_node(loc, T_IDALP("withtype"))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres,
       TEQD2EXPsome(token_make_node(loc, T_VAL(VLKval)), d2body),
       WTHS2EXPsome(tok_wth, s2e_with))
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, tqas, list_nil()(*d2cs*), list_sing(d2f)))
//
  val decls = list_sing(fundecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[CP-WTH] f[n](k:Idx(n)):Idx(n) WITHTYPE LE(0,n)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
fun
mymain_cproof((*void*)): void = let
//
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
//
  val () = PYB_log("######## C-PROOF STAGE-0 SPIKE (metric + unpack + withtype) ########")
//
  val sel = PYB_probe()
  val _ =
    (
      case+ sel of
      | 1 => let val () = PYB_log("---- PROBE CP-MET (metric F2ARGmets) ----")
                 val _ = probe_CP_MET() in 0 end
      | 2 => let val () = PYB_log("---- PROBE CP-UNP (unpack D2Psapp) ----")
                 val _ = probe_CP_UNP() in 0 end
      | 3 => let val () = PYB_log("---- PROBE CP-WTH (withtype WTHS2EXP) ----")
                 val _ = probe_CP_WTH() in 0 end
      | _ => let val () = PYB_log("---- CP-MET ----") val _ = probe_CP_MET()
                 val () = PYB_log("---- CP-UNP ----") val _ = probe_CP_UNP()
                 val () = PYB_log("---- CP-WTH ----") val _ = probe_CP_WTH()
              in 0 end
    ) : sint
in
  PYB_log("######## END C-PROOF SPIKE ########")
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_cproof()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_cproof_spike.dats]
*)
