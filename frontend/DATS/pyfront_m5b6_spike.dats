(* ****** ****** *)
(*
** M5b.6 GATING SPIKE driver — characterizes the TYPECHECK behavior of the
** LINEAR and FLAT memory/representation MODES selected by the type-declaration
** decorators (@viewtype / @unboxed / @boxed) and type-param sort annotations.
**
** The boxed defaults already typecheck end-to-end (M5b / M5b.45 / M5b.3b). This
** spike determines whether the LINEAR (vtbx / TRCDbox1) and FLAT (TRCDflt0) modes
** are usable for typecheck — especially whether LINEARITY is tracked (a dropped
** linear value MUST error) — BEFORE the real lowering is wired.
**
** The confirmed mode mapping (SURFACE-GRAMMAR §5.7.1):
**   enum @viewtype  -> linear datatype, sort the_sort2_vtbx
**   enum bare/@boxed-> the_sort2_tbox (PROVEN, M5b)
**   struct @viewtype-> S2Etrcd(TRCDbox1, ...) (boxed linear)
**   struct @unboxed -> S2Etrcd(TRCDflt0, ...) (flat)
**   struct bare/box -> S2Etrcd(TRCDbox0, ...) (PROVEN, M5b.45)
**   type param sorts: Type->the_sort2_type ; VType->the_sort2_vwtp ; Prop->prop
**     param @unboxed on Type -> the_sort2_tflt ; on VType -> the_sort2_vtft
**
** PROBES (each is an INDEPENDENT d2parsed run, own fresh env + own node process
** via PYB_probe / PROBE env so a linearity error / hard cfail in one is ISOLATED;
** we report nerror after tread3a for EACH):
**
**   L1  LINEAR datatype, CONSUMED.   enum @viewtype Opt{Nothing,Just(Int)} (sort
**         vtbx) + def f(o:Opt)->Int: match o {Nothing:0 | Just(x):x}. The match
**         DESTRUCTS (consumes) o. Does a linear datatype + fully-consuming match
**         typecheck? nerror=0?
**   L2  LINEAR datatype, DROPPED.    Same linear Opt + def g(o:Opt)->Int: 0. `o`
**         is NEVER consumed. EXPECTED: linearity error (nerror>0). Characterize.
**   L3  FLAT record.   PointF = S2Etrcd(TRCDflt0,...) + def h(p:PointF)->Int: p.x.
**   L4  LINEAR record. PointL = S2Etrcd(TRCDbox1,...) + def k(p:PointL)->Int: p.x.
**         (a single projection — does it consume a linear record?)
**   L5  NON-DEFAULT param sort.  enum Box[A:VType]{Wrap(A)} (param sort vwtp) +
**         instantiate Box[Int] (Int non-linear; vtype superset of type). Does a
**         VType-sorted param build + instantiate at a non-linear arg? nerror=0?
**
** RECIPE MIRRORED FROM the proven boxed spikes:
**   pyfront_m5b_spike.dats   (monomorphic datatype + consuming match)
**   pyfront_m5b45_spike.dats (boxed record + field projection)
**   pyfront_m5b3b_spike.dats (parametric datatype w/ sort-annotated param)
** ONLY DELTA: the SORT constant (vtbx instead of tbox) / the TRCDknd (TRCDbox1 /
**   TRCDflt0 instead of TRCDbox0) / the param sort (vwtp instead of type).
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
// D2Pannot), exactly as the proven boxed spikes do.
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
// resolve a (prelude) static type NAME to its s2exp (the_s2exp_sint0 = the M5a
// direct T2Pcst Int that int literals/annotations carry). Same as the boxed spikes.
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
// resolve a bound dynamic VARIABLE by name to a D2Evar reference (scrutinee `o`,
// bound pattern var `x`, param `p`).
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
  // stock reporter on stderr (prints errck nodes when nerror>0) — this is how we
  // characterize the EXACT linearity error text for L2.
  val () = (if nerror > 0 then f3perr0_d3parsed(g_stderr(), dp3))
in
  nerror
end
//
(* ****** ****** *)
//
// build the LINEAR monomorphic datatype `Opt {Nothing, Just(Int)}` with sort
// the_sort2_vtbx (a viewtype datatype). DELTA vs the proven boxed M5b spike: the
// s2cst sort is vtbx, not tbox. Everything else is identical. Registers the cons
// into the env and returns (s2cst, the D2Cdatatype decl, [Nothing,Just]).
//
fun
build_linear_opt
  (env: !tr12env, loc: loctn): @(s2cst, d2ecl, d2con, d2con) = let
//
  val sym_opt = symbl_make_name("Opt")
  // ==== THE DELTA: linear datatype sort vtbx (vs boxed tbox) ====
  val s2c_opt = s2cst_make_idst(loc, sym_opt, the_sort2_vtbx)
  val () = tr12env_add1_s2cst(env, s2c_opt)
  val s2e_opt = s2exp_cst(s2c_opt)
//
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val tok_nothing = token_make_node(loc, T_IDALP("Nothing"))
  val tok_just    = token_make_node(loc, T_IDALP("Just"))
  val sexp_nothing = s2exp_fun1_nil0((-1)(*npf*), list_nil(), s2e_opt)
  val sexp_just    = s2exp_fun1_nil0((-1)(*npf*), list_sing(s2e_int), s2e_opt)
  val d2c_nothing = d2con_make_idtp(tok_nothing, list_nil()(*tqas*), sexp_nothing)
  val d2c_just    = d2con_make_idtp(tok_just,    list_nil()(*tqas*), sexp_just)
  val () = d2con_set_ctag(d2c_nothing, 0)
  val () = d2con_set_ctag(d2c_just, 1)
  val d2cs_opt = list_cons(d2c_nothing, list_sing(d2c_just))
  val () = s2cst_set_d2cs(s2c_opt, d2cs_opt)
  val () = tr12env_add1_d2conlst(env, d2cs_opt)
//
  val dtdecl =
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c_opt)))
in
  @(s2c_opt, dtdecl, d2c_nothing, d2c_just)
end
//
(* ****** ****** *)
//
// ===== PROBE L1 : LINEAR datatype, CONSUMED via a full match ===================
//
//   enum @viewtype Opt { Nothing, Just(Int) }     (sort vtbx)
//   def f(o: Opt) -> Int: match o { Nothing:0 | Just(x):x }
//
fun
probe_L1((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val @(s2c_opt, dtdecl, d2c_nothing, d2c_just) = build_linear_opt(env, loc)
  val s2e_opt = s2exp_cst(s2c_opt)
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val sym_f = symbl_make_name("f")
  val d2v_f = d2var_new2_name(loc, sym_f)
  val () = tr12env_add0_d2var(env, d2v_f)
//
  val d2v_o = d2var_new2_name(loc, symbl_make_name("o"))
  val pat_o = d2pat_var(loc, d2v_o)
  val pat_o_annot = d2pat_make_node(loc, D2Pannot(pat_o, s1exp_none0(loc), s2e_opt))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_o_annot))))
  val sres = S2RESsome(S2EFFnone(), s2e_int)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
//
  val d2scrut = resolve_var(env, loc, "o")
//
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
  val arm2 = let
    val phd = d2pat_con(loc, d2c_just)
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
  val () = tr12env_poplam0(env)
//
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil()(*tqas*), list_nil()(*d2cs*), list_sing(d2f)))
//
  val decls = list_cons(dtdecl, list_sing(fundecl))
  val t2penv = tr12env_free_top(env)
in
  run_one("[L1] linear Opt(vtbx) ; f(o:Opt)->Int:match(CONSUMES)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE L2 : LINEAR datatype, DROPPED (linearity must bite) ===============
//
//   enum @viewtype Opt { Nothing, Just(Int) }     (sort vtbx)
//   def g(o: Opt) -> Int: 0     -- `o` is NEVER consumed -> EXPECTED linearity err
//
fun
probe_L2((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val @(s2c_opt, dtdecl, d2c_nothing, d2c_just) = build_linear_opt(env, loc)
  val s2e_opt = s2exp_cst(s2c_opt)
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val sym_g = symbl_make_name("g")
  val d2v_g = d2var_new2_name(loc, sym_g)
  val () = tr12env_add0_d2var(env, d2v_g)
//
  val d2v_o = d2var_new2_name(loc, symbl_make_name("o"))
  val pat_o = d2pat_var(loc, d2v_o)
  val pat_o_annot = d2pat_make_node(loc, D2Pannot(pat_o, s1exp_none0(loc), s2e_opt))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_o_annot))))
  val sres = S2RESsome(S2EFFnone(), s2e_int)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  // the body is JUST `0` — the linear param `o` is dropped (never consumed).
  val d2body = d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01("0"))))
  val () = tr12env_poplam0(env)
//
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2g =
    d2fundcl_make_args
      (loc, d2v_g, f2as, sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil()(*tqas*), list_nil()(*d2cs*), list_sing(d2g)))
//
  val decls = list_cons(dtdecl, list_sing(fundecl))
  val t2penv = tr12env_free_top(env)
in
  run_one("[L2] linear Opt(vtbx) ; g(o:Opt)->Int:0 (DROPS o)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// build a record s2exp `{x:int, y:int}` with the GIVEN trcdknd + the GIVEN sort.
// flat -> (TRCDflt0, the_sort2_tflt) ; linear-boxed -> (TRCDbox1, the_sort2_vtbx).
// Fields use the_s2exp_sint0 (the M5a direct T2Pcst Int) — the proven mitigation.
//
fun
build_point_rcd(knd: trcdknd, srt: sort2, s2e_int: s2exp): s2exp = let
  val lab_x = LABsym(symbl_make_name("x"))
  val lab_y = LABsym(symbl_make_name("y"))
  val fld_x = S2LAB(lab_x, s2e_int)
  val fld_y = S2LAB(lab_y, s2e_int)
  val flds  = list_cons(fld_x, list_sing(fld_y))
in
  s2exp_make_node(srt, S2Etrcd(knd, (-1)(*npf*), flds))
end
//
// build the sexpdef alias `name = <rcd>`, register, return (s2cst, decl).
//
fun
build_sexpdef
  (env: !tr12env, loc: loctn, name: strn, sdef: s2exp): @(s2cst, d2ecl) = let
  val s2t2 = sdef.sort()
  val sid1 = symbl_make_name(name)
  val tdef = s2exp_stpize(sdef)
  val s2c1 = s2cst_make_idst(loc, sid1, s2t2)
  val () = s2cst_set_sexp(s2c1, sdef)
  val () = s2cst_set_styp(s2c1, tdef)
  val () = tr12env_add1_s2cst(env, s2c1)
  val dcl = d2ecl_make_node(loc, D2Csexpdef(s2c1, sdef))
in
  @(s2c1, dcl)
end
//
// build `def NAME(p: PTYP) -> RTYP: p.x` (projection of field x through PTYP).
//
fun
build_proj_fun
  (env: !tr12env, loc: loctn, fname: strn, ptyp: s2exp, rtyp: s2exp): d2ecl = let
  val sym_f = symbl_make_name(fname)
  val d2v_f = d2var_new2_name(loc, sym_f)
  val () = tr12env_add0_d2var(env, d2v_f)
//
  val d2v_p = d2var_new2_name(loc, symbl_make_name("p"))
  val pat_p = d2pat_var(loc, d2v_p)
  val pat_p_annot = d2pat_make_node(loc, D2Pannot(pat_p, s1exp_none0(loc), ptyp))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_p_annot))))
  val sres = S2RESsome(S2EFFnone(), rtyp)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2body = let
    val d2p = resolve_var(env, loc, "p")
    val drxp = d2rxp_new1(loc)
    val lab  = LABsym(symbl_make_name("x"))
  in
    d2exp_make_node(loc, D2Eproj(token_make_node(loc, T_VAL(VLKval)), drxp, lab, d2p))
  end
  val () = tr12env_poplam0(env)
//
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
in
  d2ecl_make_node
    (loc, D2Cfundclst(tok_fun, list_nil()(*tqas*), list_nil()(*d2cs*), list_sing(d2f)))
end
//
// ===== PROBE L3 : FLAT record (TRCDflt0, sort tflt) ============================
//
//   struct @unboxed PointF { x:int, y:int }     (flat)
//   def h(p: PointF) -> Int: p.x
//
fun
probe_L3((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_Int = resolve_typ_name(env, "the_s2exp_sint0")
//
  // ==== THE DELTA: flat record (TRCDflt0, the_sort2_tflt) ====
  val s2e_rcd = build_point_rcd(TRCDflt0, the_sort2_tflt, s2e_Int)
  val @(s2c_pt, dcl_alias) = build_sexpdef(env, loc, "PointF", s2e_rcd)
  val s2e_pt = s2exp_cst(s2c_pt)
//
  val dcl_h = build_proj_fun(env, loc, "h", s2e_pt, s2e_Int)
  val decls = list_cons(dcl_alias, list_sing(dcl_h))
  val t2penv = tr12env_free_top(env)
in
  run_one("[L3] flat PointF(TRCDflt0,tflt) ; h(p)->Int:p.x  nerror=", decls, t2penv)
end
//
// ===== PROBE L4 : LINEAR record (TRCDbox1, sort vtbx) ==========================
//
//   struct @viewtype PointL { x:int, y:int }     (boxed linear)
//   def k(p: PointL) -> Int: p.x
//
fun
probe_L4((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_Int = resolve_typ_name(env, "the_s2exp_sint0")
//
  // ==== THE DELTA: boxed-linear record (TRCDbox1, the_sort2_vtbx) ====
  val s2e_rcd = build_point_rcd(TRCDbox1, the_sort2_vtbx, s2e_Int)
  val @(s2c_pt, dcl_alias) = build_sexpdef(env, loc, "PointL", s2e_rcd)
  val s2e_pt = s2exp_cst(s2c_pt)
//
  val dcl_k = build_proj_fun(env, loc, "k", s2e_pt, s2e_Int)
  val decls = list_cons(dcl_alias, list_sing(dcl_k))
  val t2penv = tr12env_free_top(env)
in
  run_one("[L4] linear PointL(TRCDbox1,vtbx) ; k(p)->Int:p.x  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE L5 : NON-DEFAULT param sort (VType param) =========================
//
//   enum Box[A: VType] { Wrap(A) }     (param sort vwtp ; Box itself vtbx-ish)
//   def f(b: Box[Int]) -> Int: match b { Wrap(x): x }
//   (Int is non-linear; vtype superset of type, so a VType param accepts Int.)
//
fun
probe_L5((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// (1) tycon `Box` : FUNCTION sort (vtype)->vtbx. Box is a viewtype datatype (vtbx)
//     since it may hold a linear A; the PARAM sort is the_sort2_vwtp (VType).
  val sym_box = symbl_make_name("Box")
  val s2t_box = S2Tfun1(list_sing(the_sort2_vwtp), the_sort2_vtbx)
  val s2c_box = s2cst_make_idst(loc, sym_box, s2t_box)
  val () = tr12env_add1_s2cst(env, s2c_box)
//
// (2) the param `A` : an s2var of sort VType (the_sort2_vwtp), pushed into a
//     lam-scope while we elaborate the con.
  val () = tr12env_pshlam0(env)
  val s2v_A = s2var_make_idst(symbl_make_name("A"), the_sort2_vwtp)
  val () = tr12env_add0_s2var(env, s2v_A)
  val s2e_A = s2exp_var(s2v_A)
  val s2e_box_A = s2exp_apps(loc, s2exp_cst(s2c_box), list_sing(s2e_A))
//
// (3) the single con `Wrap : (A) -> Box(A)`, quantified over {A:vtype} via tqas.
  val tok_wrap = token_make_node(loc, T_IDALP("Wrap"))
  val sexp_wrap = s2exp_fun1_nil0((-1)(*npf*), list_sing(s2e_A), s2e_box_A)
  val tqas = list_sing(t2qag(loc, list_sing(s2v_A))) : t2qaglst
  val d2c_wrap = d2con_make_idtp(tok_wrap, tqas, sexp_wrap)
  val () = d2con_set_ctag(d2c_wrap, 0)
  val d2cs_box = list_sing(d2c_wrap)
  val () = s2cst_set_d2cs(s2c_box, d2cs_box)
  val () = tr12env_add1_d2conlst(env, d2cs_box)
  val () = tr12env_poplam0(env)
//
  val dtdecl =
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c_box)))
//
// ===== def f(b: Box[Int]) -> Int: match b { Wrap(x): x } =======================
//
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
  // INSTANTIATE Box at Int (a non-linear arg given to a VType param).
  val s2e_box_int = s2exp_apps(loc, s2exp_cst(s2c_box), list_sing(s2e_int))
//
  val sym_f = symbl_make_name("f")
  val d2v_f = d2var_new2_name(loc, sym_f)
  val () = tr12env_add0_d2var(env, d2v_f)
//
  val d2v_b = d2var_new2_name(loc, symbl_make_name("b"))
  val pat_b = d2pat_var(loc, d2v_b)
  val pat_b_annot = d2pat_make_node(loc, D2Pannot(pat_b, s1exp_none0(loc), s2e_box_int))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_b_annot))))
  val sres = S2RESsome(S2EFFnone(), s2e_int)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
//
  val d2scrut = resolve_var(env, loc, "b")
  // single arm `Wrap(x): x` — consumes b, binds x:int.
  val arm1 = let
    val phd = d2pat_con(loc, d2c_wrap)
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
  val arms = list_sing(arm1)
  val tok_case = token_make_node(loc, T_CASE(CSKcas0))
  val d2body = d2exp_make_node(loc, D2Ecas0(tok_case, d2scrut, arms))
//
  val () = tr12env_poplam0(env)
//
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil()(*tqas*), list_nil()(*d2cs*), list_sing(d2f)))
//
  val decls = list_cons(dtdecl, list_sing(fundecl))
  val t2penv = tr12env_free_top(env)
in
  run_one("[L5] enum Box[A:VType]{Wrap(A)} ; f(b:Box[Int])->Int:match  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
fun
mymain_m5b6((*void*)): void = let
//
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
//
  val () = PYB_log("######## M5b.6 linear/flat MODE GATING SPIKE ########")
//
  val sel = PYB_probe()
  val _ =
    (
      case+ sel of
      | 1 => let val () = PYB_log("---- PROBE L1 (linear datatype, CONSUMED) ----")
                 val _ = probe_L1() in 0 end
      | 2 => let val () = PYB_log("---- PROBE L2 (linear datatype, DROPPED — must error) ----")
                 val _ = probe_L2() in 0 end
      | 3 => let val () = PYB_log("---- PROBE L3 (flat record TRCDflt0) ----")
                 val _ = probe_L3() in 0 end
      | 4 => let val () = PYB_log("---- PROBE L4 (linear record TRCDbox1) ----")
                 val _ = probe_L4() in 0 end
      | 5 => let val () = PYB_log("---- PROBE L5 (VType param sort) ----")
                 val _ = probe_L5() in 0 end
      | _ => let val () = PYB_log("---- PROBE L1 ----") val _ = probe_L1()
                 val () = PYB_log("---- PROBE L2 ----") val _ = probe_L2()
                 val () = PYB_log("---- PROBE L3 ----") val _ = probe_L3()
                 val () = PYB_log("---- PROBE L4 ----") val _ = probe_L4()
                 val () = PYB_log("---- PROBE L5 ----") val _ = probe_L5()
              in 0 end
    ) : sint
in
  PYB_log("######## END M5b.6 SPIKE ########")
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_m5b6()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_m5b6_spike.dats]
*)
