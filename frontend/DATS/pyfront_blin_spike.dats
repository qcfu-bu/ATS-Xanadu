(* ****** ****** *)
(*
** B-LIN (Area B — Linear / view / pointer surface) STAGE-0 SPIKE driver.
**
** Hand-builds at L2 (NO surface, NO lexer/parser) and runs each probe through the real stock
** pipeline trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a, then prints the post-tread3a
** nerror. EACH probe is an INDEPENDENT d2parsed in its OWN node process (PROBE selector) so a
** hard XATS000_cfail is ISOLATED.
**
** Probes (the Area-B L2 pieces):
**   BL-AT   `A at l`         — AT-VIEW s2exp.  A def
**             fun{a:t@ype} deref{l:addr}(pf: a @ l, p: ptr(l)): a
**           whose FIRST (proof) param is annotated with an at-view  `a @ l` = S2Eatx2(a,l) of
**           result-sort the_sort2_vwtp, and whose 2nd param is `ptr(l)`.  The body `!p` (D2Eeval)
**           reads the pointer.  Does the at-view s2exp ride to nerror=0?  How does it combine the
**           carried type + the address?  (S2Eatx2 : staexp2.sats:606 ; trans12 builds it with
**           result sort the_sort2_vwtp : trans12_staexp.dats:1388 ; addr sort the_sort2_addr :
**           staexp2.sats:304 ; ptr con the_s2cst_p2tr0 : staexp2.sats:448.)
**   BL-LIN  `case ~VCons(x,rest)` — LINEAR-CONSUME pattern.  A boxed datatype List(A) with
**           a `case xs of ~VCons(x,rest) => x | ~VNil() => d` whose con-arms are WRAPPED in
**           D2Pfree(...) (the `~` free/consume).  f0_free (trans2a_dynexp.dats:705) is a pure
**           pass-through (re-typechecks inner, re-wraps with the same type) so a well-formed
**           con pattern stays well-formed under ~.  nerror=0?  (D2Pfree : dynexp2.sats:733 ;
**           f0_free : trans2a_dynexp.dats:700 ; built via d2pat_make_node(loc, D2Pfree(inner)).)
**   BL-ADDR `&x`             — ADDRESS-OF D2Eaddr.  `&x` for a var-cell x : Int.  f0_addr
**           (trans2a_dynexp.dats:2918) types it as ptr(typ-of-x) via the_s2typ_p2tr1.  nerror=0?
**           (D2Eaddr : dynexp2.sats:1027 ; built via d2exp_make_node(loc, D2Eaddr(lval)).)
**   BL-DERF `!p`             — DEREFERENCE D2Eeval.  `!p` for p : ptr(a).  f0_eval
**           (trans2a_dynexp.dats:3019) peels the ptr element type.  nerror=0?
**           (D2Eeval : dynexp2.sats:1039 ; built via d2exp_make_node(loc, D2Eeval(p)).)
**   BL-MV   `x :=> y`        — MOVE D2Exazgn.  Two var-cells x,y : Int ; `x :=> y` moves y into
**           x.  f0_xazgn (trans2a_dynexp.dats:3210) typechecks rval against lval-type (like :=).
**           nerror=0?  (D2Exazgn : dynexp2.sats:1064 ; d2exp_make_node(loc, D2Exazgn(l,r)).)
**   BL-SW   `x :=: y`        — SWAP D2Exchng.  Two var-cells x,y : Int ; `x :=: y`.  f0_xchng
**           (trans2a_dynexp.dats:3238) cross-typechecks both sides.  nerror=0?
**           (D2Exchng : dynexp2.sats:1066 ; d2exp_make_node(loc, D2Exchng(l,r)).)
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
// resolve a (prelude) static type NAME to its s2exp.  The surface `Int` aliases to the
// prelude internal `the_s2exp_sint0` (M5a finding) — the SAME T2Pcst the int literal carries.
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
// the ptr type  ptr(l)  built from the_s2cst_p2tr0 applied to an addr-s2exp.
fun
build_ptr(loc: loctn, s2e_addr: s2exp): s2exp =
  s2exp_apps(loc, s2exp_cst(the_s2cst_p2tr0()), list_sing(s2e_addr))
//
// helper makers.
fun tok_val(loc: loctn): token = token_make_node(loc, T_VAL(VLKval))
fun tok_var(loc: loctn): token = token_make_node(loc, T_VAR(VRKvar))
fun tok_fun(loc: loctn): token = token_make_node(loc, T_FUN(FNKfn2))
//
fun d2e_int(loc: loctn, s: strn): d2exp =
  d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01(s))))
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
// build ONE `var name : Int = init` cell as a D2Cvardclst, register the dpid.
fun
build_var_cell
  (env: !tr12env, loc: loctn, name: strn, s2e_typ: s2exp, init: d2exp): d2ecl = let
  val d2v = d2var_new2_name(loc, symbl_make_name(name))
  val sres = optn_cons(s2e_typ)
  val dini = TEQD2EXPsome(tok_val(loc), init)
  val dvar = d2vardcl_make_args(loc, d2v, optn_nil()(*vpid*), sres, dini)
  val () = tr12env_add0_d2var(env, d2v)
in
  d2ecl_make_node(loc, D2Cvardclst(tok_var(loc), list_sing(dvar)))
end
//
(* ****** ****** *)
//
// ===== PROBE BL-AT : `A at l` at-view proof param + ptr  ==========================
//
//   fun{a:t@ype} deref{l:addr}(pf: a @ l, p: ptr(l)): a = !p
//   pf's type is the AT-VIEW  a @ l = S2Eatx2(a, l), result sort the_sort2_vwtp.  The fn type
//   marks ONE proof param (npf=1).  The body `!p` (D2Eeval) reads p:ptr(l), yielding `a`.
//
fun
probe_BL_AT((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val () = tr12env_pshlam0(env)
//   the carried type a : t@ype  and the address l : addr.
  val s2v_a = s2var_make_idst(symbl_make_name("a"), the_sort2_tflt)
  val s2v_l = s2var_make_idst(symbl_make_name("l"), the_sort2_addr)
  val () = tr12env_add0_s2var(env, s2v_a)
  val () = tr12env_add0_s2var(env, s2v_l)
  val s2e_a = s2exp_var(s2v_a)
  val s2e_l = s2exp_var(s2v_l)
//   the AT-VIEW  a @ l  (S2Eatx2 with result sort the_sort2_vwtp).
  val s2e_at =
    s2exp_make_node(the_sort2_vwtp, S2Eatx2(s2e_a, s2e_l))
//   the pointer type  ptr(l).
  val s2e_ptr_l = build_ptr(loc, s2e_l)
//
//   params:  pf : a @ l  (proof) ,  p : ptr(l)  (value).  npf = 1.
  val d2v_pf = d2var_new2_name(loc, symbl_make_name("pf"))
  val pat_pf = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_pf), s1exp_none0(loc), s2e_at))
  val d2v_p = d2var_new2_name(loc, symbl_make_name("p"))
  val pat_p = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_p), s1exp_none0(loc), s2e_ptr_l))
  val f2as =
    list_sing(f2arg_make_node(loc, F2ARGdapp(1(*npf*), list_cons(pat_pf, list_sing(pat_p))))) : f2arglst
  val sres = S2RESsome(S2EFFnone(), s2e_a)
//
  val sym_deref = symbl_make_name("deref")
  val d2v_deref = d2var_new2_name(loc, sym_deref)
  val () = tr12env_add0_d2var(env, d2v_deref)
//
//   body scope:  !p  (D2Eeval of the pointer read).
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2e_p = d2exp_make_node(loc, D2Evar(d2v_p))
  val d2body = d2exp_make_node(loc, D2Eeval(d2e_p))
  val () = tr12env_poplam0(env)
//
  val () = tr12env_poplam0(env)
//   quantify the def over {l:addr}; the template arg {a} rides tqas too (one group).
  val tqas = list_sing(t2qag(loc, list_cons(s2v_a, list_sing(s2v_l)))) : t2qaglst
//
  val d2f =
    d2fundcl_make_args
      (loc, d2v_deref, f2as, sres,
       TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), tqas, list_nil()(*d2cs*), list_sing(d2f)))
//
  val decls = list_sing(fundecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[BL-AT] deref{l:addr}(pf: a @ l, p: ptr(l)): a = !p  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE BL-LIN : `~VCons(x,rest)` linear-consume pattern  ===================
//
//   datatype List(type) :  VNil : {A} () -> List(A) ;  VCons : {A} (A, List(A)) -> List(A)
//   def headOr[A](d:A, xs: List(A)) -> A :
//     case xs of
//     | ~VNil()         => d
//     | ~VCons(x, rest) => x
//   Each con-arm pattern is WRAPPED in D2Pfree(...) — the `~` linear-consume.  f0_free is a
//   pass-through, so a well-formed con-pattern stays well-formed under ~.
//
fun
probe_BL_LIN((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// (1) List : (type) -> tbox.
  val sym_lst = symbl_make_name("List")
  val s2t_lst = S2Tfun1(list_sing(the_sort2_type), the_sort2_tbox)
  val s2c_lst = s2cst_make_idst(loc, sym_lst, s2t_lst)
  val () = tr12env_add1_s2cst(env, s2c_lst)
//
// (2) VNil : {A} () -> List(A).
  val () = tr12env_pshlam0(env)
  val s2v_A0 = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val () = tr12env_add0_s2var(env, s2v_A0)
  val s2e_A0 = s2exp_var(s2v_A0)
  val s2e_lst_A0 = s2exp_apps(loc, s2exp_cst(s2c_lst), list_sing(s2e_A0))
  val sexp_vnil = s2exp_fun1_nil0((-1)(*npf*), list_nil(), s2e_lst_A0)
  val tqas_vnil = list_sing(t2qag(loc, list_sing(s2v_A0))) : t2qaglst
  val () = tr12env_poplam0(env)
  val tok_vnil = token_make_node(loc, T_IDALP("VNil"))
  val d2c_vnil = d2con_make_idtp(tok_vnil, tqas_vnil, sexp_vnil)
  val () = d2con_set_ctag(d2c_vnil, 0)
//
// (3) VCons : {A} (A, List(A)) -> List(A).
  val () = tr12env_pshlam0(env)
  val s2v_A1 = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val () = tr12env_add0_s2var(env, s2v_A1)
  val s2e_A1 = s2exp_var(s2v_A1)
  val s2e_lst_A1 = s2exp_apps(loc, s2exp_cst(s2c_lst), list_sing(s2e_A1))
  val sexp_vcons =
    s2exp_fun1_nil0((-1)(*npf*), list_cons(s2e_A1, list_sing(s2e_lst_A1)), s2e_lst_A1)
  val tqas_vcons = list_sing(t2qag(loc, list_sing(s2v_A1))) : t2qaglst
  val () = tr12env_poplam0(env)
  val tok_vcons = token_make_node(loc, T_IDALP("VCons"))
  val d2c_vcons = d2con_make_idtp(tok_vcons, tqas_vcons, sexp_vcons)
  val () = d2con_set_ctag(d2c_vcons, 1)
//
  val d2cs_lst = list_cons(d2c_vnil, list_sing(d2c_vcons))
  val () = s2cst_set_d2cs(s2c_lst, d2cs_lst)
  val () = tr12env_add1_d2conlst(env, d2cs_lst)
  val dtdecl =
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c_lst)))
//
// (4) def headOr : {A:type} (A, List(A)) -> A.
  val () = tr12env_pshlam0(env)
  val s2v_A2 = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val () = tr12env_add0_s2var(env, s2v_A2)
  val s2e_A2 = s2exp_var(s2v_A2)
  val s2e_lst_A2 = s2exp_apps(loc, s2exp_cst(s2c_lst), list_sing(s2e_A2))
//
  val d2v_d = d2var_new2_name(loc, symbl_make_name("d"))
  val pat_d = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_d), s1exp_none0(loc), s2e_A2))
  val d2v_xs = d2var_new2_name(loc, symbl_make_name("xs"))
  val pat_xs = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_xs), s1exp_none0(loc), s2e_lst_A2))
  val f2as =
    list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_cons(pat_d, list_sing(pat_xs))))) : f2arglst
  val sres = S2RESsome(S2EFFnone(), s2e_A2)
//
  val sym_hd = symbl_make_name("headOr")
  val d2v_hd = d2var_new2_name(loc, sym_hd)
  val () = tr12env_add0_d2var(env, d2v_hd)
//
//   body scope.
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
//
  val d2e_xs = d2exp_make_node(loc, D2Evar(d2v_xs))
  val d2e_d = d2exp_make_node(loc, D2Evar(d2v_d))
//
//   --- arm 1:  ~VNil() => d  ---  nullary con pattern dap0(con), wrapped in D2Pfree.
  val pat_vnil0 = d2pat_make_node(loc, D2Pdap0(d2pat_con(loc, d2c_vnil)))
  val pat_vnil  = d2pat_make_node(loc, D2Pfree(pat_vnil0))
  val dgpt_nil = d2gpt_make_node(loc, D2GPTpat(pat_vnil))
  val () = tr12env_add0_d2gpt(env, dgpt_nil)
  val cls_nil = d2cls_make_node(loc, D2CLScls(dgpt_nil, d2e_d))
//
//   --- arm 2:  ~VCons(x, rest) => x  ---  con-pattern applied, wrapped in D2Pfree.
  val d2v_x = d2var_new2_name(loc, symbl_make_name("x"))
  val d2v_rest = d2var_new2_name(loc, symbl_make_name("rest"))
  val pat_x = d2pat_var(loc, d2v_x)
  val pat_rest = d2pat_var(loc, d2v_rest)
  val pat_con0 = d2pat_con(loc, d2c_vcons)
  val pat_vcons0 =
    d2pat_make_node(loc, D2Pdapp(pat_con0, (-1), list_cons(pat_x, list_sing(pat_rest))))
  val pat_vcons = d2pat_make_node(loc, D2Pfree(pat_vcons0))
  val dgpt_cons = d2gpt_make_node(loc, D2GPTpat(pat_vcons))
  val () = tr12env_add0_d2gpt(env, dgpt_cons)
  val d2e_x = d2exp_make_node(loc, D2Evar(d2v_x))
  val cls_cons = d2cls_make_node(loc, D2CLScls(dgpt_cons, d2e_x))
//
  val clss = list_cons(cls_nil, list_sing(cls_cons)) : d2clslst
  val tok_case = token_make_node(loc, T_CASE(CSKcas0))
  val d2body = d2exp_make_node(loc, D2Ecas0(tok_case, d2e_xs, clss))
//
  val () = tr12env_poplam0(env)
  val () = tr12env_poplam0(env)
  val tqas_hd = list_sing(t2qag(loc, list_sing(s2v_A2))) : t2qaglst
//
  val d2f =
    d2fundcl_make_args
      (loc, d2v_hd, f2as, sres, TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), tqas_hd, list_nil()(*d2cs*), list_sing(d2f)))
//
  val decls = list_cons(dtdecl, list_sing(fundecl))
  val t2penv = tr12env_free_top(env)
in
  run_one("[BL-LIN] headOr ; case xs of ~VNil()=>d | ~VCons(x,rest)=>x  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE BL-ADDR : `&x` address-of  ==========================================
//
//   def f() -> ptr :
//       var x: Int = 0
//       &x            // D2Eaddr -> ptr(typ-of-x)
//   The body is the address-of; its result type is the ptr type f0_addr synthesizes.  We let
//   the def result be inferred (S2RESnone) so we don't have to name the ptr type at the surface.
//
fun
probe_BL_ADDR((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val d2v_f = d2var_new2_name(loc, symbl_make_name("f"))
  val () = tr12env_add0_d2var(env, d2v_f)
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil()))) : f2arglst
  val sres = S2RESnone()
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val () = tr12env_pshlet0(env)
//
//   var x : Int = 0.
  val decl_x = build_var_cell(env, loc, "x", s2e_int, d2e_int(loc, "0"))
//   &x  -> D2Eaddr(D2Evar x).
  val read_x = resolve_var(env, loc, "x")
  val d2e_addr = d2exp_make_node(loc, D2Eaddr(read_x))
//
  val d2body = d2exp_make_node(loc, D2Elet0(list_sing(decl_x), d2e_addr))
//
  val () = tr12env_poplet0(env)
  val () = tr12env_poplam0(env)
//
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f)))
//
  val decls = list_sing(fundecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[BL-ADDR] f() = (var x:Int=0; &x)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE BL-DERF : `!p` dereference  =========================================
//
//   fun{a:t@ype} rd{l:addr}(p: ptr(l)): a = !p
//   The body `!p` (D2Eeval) reads p:ptr(l).  f0_eval peels the ptr element type.  (Note: a ptr
//   alone carries no element-type at the surface; f0_eval synthesizes a fresh tyvar that unifies
//   with the result `a`.  This is the EXPR-position deref probe.)
//
fun
probe_BL_DERF((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val () = tr12env_pshlam0(env)
  val s2v_a = s2var_make_idst(symbl_make_name("a"), the_sort2_tflt)
  val s2v_l = s2var_make_idst(symbl_make_name("l"), the_sort2_addr)
  val () = tr12env_add0_s2var(env, s2v_a)
  val () = tr12env_add0_s2var(env, s2v_l)
  val s2e_a = s2exp_var(s2v_a)
  val s2e_l = s2exp_var(s2v_l)
  val s2e_ptr_l = build_ptr(loc, s2e_l)
//
  val d2v_p = d2var_new2_name(loc, symbl_make_name("p"))
  val pat_p = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_p), s1exp_none0(loc), s2e_ptr_l))
  val f2as =
    list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_p)))) : f2arglst
  val sres = S2RESsome(S2EFFnone(), s2e_a)
//
  val sym_rd = symbl_make_name("rd")
  val d2v_rd = d2var_new2_name(loc, sym_rd)
  val () = tr12env_add0_d2var(env, d2v_rd)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2e_p = d2exp_make_node(loc, D2Evar(d2v_p))
  val d2body = d2exp_make_node(loc, D2Eeval(d2e_p))
  val () = tr12env_poplam0(env)
//
  val () = tr12env_poplam0(env)
  val tqas = list_sing(t2qag(loc, list_cons(s2v_a, list_sing(s2v_l)))) : t2qaglst
//
  val d2f =
    d2fundcl_make_args
      (loc, d2v_rd, f2as, sres, TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), tqas, list_nil(), list_sing(d2f)))
//
  val decls = list_sing(fundecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[BL-DERF] rd{l:addr}(p: ptr(l)): a = !p  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE BL-DERF2 : `!p` dereference of an ELEMENT-typed pointer  =============
//
//   def f() -> Int :
//       var x: Int = 0
//       !(&x)             // D2Eeval(D2Eaddr(x)) : &x is ptr(typ-of-x) which DOES carry the
//                         // element type Int, so f0_eval peels Int.  This is the REALISTIC
//                         // surface deref — `&x` makes an element-typed pointer, `!p` reads it.
//
fun
probe_BL_DERF2((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val d2v_f = d2var_new2_name(loc, symbl_make_name("f"))
  val () = tr12env_add0_d2var(env, d2v_f)
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil()))) : f2arglst
  val sres = S2RESsome(S2EFFnone(), s2e_int)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val () = tr12env_pshlet0(env)
//
  val decl_x = build_var_cell(env, loc, "x", s2e_int, d2e_int(loc, "0"))
  val read_x = resolve_var(env, loc, "x")
  val d2e_addr = d2exp_make_node(loc, D2Eaddr(read_x))          // &x : ptr(typ-of-x)
  val d2e_eval = d2exp_make_node(loc, D2Eeval(d2e_addr))        // !(&x) : Int
//
  val d2body = d2exp_make_node(loc, D2Elet0(list_sing(decl_x), d2e_eval))
//
  val () = tr12env_poplet0(env)
  val () = tr12env_poplam0(env)
//
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f)))
//
  val decls = list_sing(fundecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[BL-DERF2] f():Int = (var x:Int=0; !(&x))  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE BL-AT2 : `A at l` at-view as a proof param, NO deref body  ===========
//
//   fun{a:t@ype} keep{l:addr}(pf: a @ l, p: ptr(l)): ptr(l) = p
//   IDENTICAL to BL-AT but the body is just `p` (NOT `!p`) and the result type is ptr(l).
//   This ISOLATES the at-view s2exp from the deref: if THIS is nerror=0, the at-view s2exp
//   ITSELF rides clean (S2Eatx2 well-formed) and the BL-AT nerror=1 is SOLELY the bare-ptr
//   `!p` (no view solver to link the proof), NOT the at-view node.
//
fun
probe_BL_AT2((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val () = tr12env_pshlam0(env)
  val s2v_a = s2var_make_idst(symbl_make_name("a"), the_sort2_tflt)
  val s2v_l = s2var_make_idst(symbl_make_name("l"), the_sort2_addr)
  val () = tr12env_add0_s2var(env, s2v_a)
  val () = tr12env_add0_s2var(env, s2v_l)
  val s2e_a = s2exp_var(s2v_a)
  val s2e_l = s2exp_var(s2v_l)
  val s2e_at = s2exp_make_node(the_sort2_vwtp, S2Eatx2(s2e_a, s2e_l))
  val s2e_ptr_l = build_ptr(loc, s2e_l)
//
  val d2v_pf = d2var_new2_name(loc, symbl_make_name("pf"))
  val pat_pf = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_pf), s1exp_none0(loc), s2e_at))
  val d2v_p = d2var_new2_name(loc, symbl_make_name("p"))
  val pat_p = d2pat_make_node(loc, D2Pannot(d2pat_var(loc, d2v_p), s1exp_none0(loc), s2e_ptr_l))
  val f2as =
    list_sing(f2arg_make_node(loc, F2ARGdapp(1(*npf*), list_cons(pat_pf, list_sing(pat_p))))) : f2arglst
  val sres = S2RESsome(S2EFFnone(), s2e_ptr_l)
//
  val sym_keep = symbl_make_name("keep")
  val d2v_keep = d2var_new2_name(loc, sym_keep)
  val () = tr12env_add0_d2var(env, d2v_keep)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2body = d2exp_make_node(loc, D2Evar(d2v_p))             // body is just `p` (NO deref)
  val () = tr12env_poplam0(env)
//
  val () = tr12env_poplam0(env)
  val tqas = list_sing(t2qag(loc, list_cons(s2v_a, list_sing(s2v_l)))) : t2qaglst
//
  val d2f =
    d2fundcl_make_args
      (loc, d2v_keep, f2as, sres, TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), tqas, list_nil(), list_sing(d2f)))
//
  val decls = list_sing(fundecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[BL-AT2] keep{l:addr}(pf: a @ l, p: ptr(l)): ptr(l) = p  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE BL-MV : `x :=> y` move  =============================================
//
//   def f() -> () :
//       var x: Int = 0
//       var y: Int = 1
//       x :=> y          // D2Exazgn(x, y)
//
fun
probe_BL_MV((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val d2v_f = d2var_new2_name(loc, symbl_make_name("f"))
  val () = tr12env_add0_d2var(env, d2v_f)
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil()))) : f2arglst
  val sres = S2RESnone()
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val () = tr12env_pshlet0(env)
//
  val decl_x = build_var_cell(env, loc, "x", s2e_int, d2e_int(loc, "0"))
  val decl_y = build_var_cell(env, loc, "y", s2e_int, d2e_int(loc, "1"))
  val lval_x = resolve_var(env, loc, "x")
  val rval_y = resolve_var(env, loc, "y")
  val d2e_mv = d2exp_make_node(loc, D2Exazgn(lval_x, rval_y))
//
  val d2body =
    d2exp_make_node
      (loc, D2Elet0(list_cons(decl_x, list_sing(decl_y)), d2e_mv))
//
  val () = tr12env_poplet0(env)
  val () = tr12env_poplam0(env)
//
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f)))
//
  val decls = list_sing(fundecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[BL-MV] f() = (var x:Int=0; var y:Int=1; x :=> y)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE BL-SW : `x :=: y` swap  =============================================
//
//   def f() -> () :
//       var x: Int = 0
//       var y: Int = 1
//       x :=: y          // D2Exchng(x, y)
//
fun
probe_BL_SW((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val d2v_f = d2var_new2_name(loc, symbl_make_name("f"))
  val () = tr12env_add0_d2var(env, d2v_f)
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_nil()))) : f2arglst
  val sres = S2RESnone()
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val () = tr12env_pshlet0(env)
//
  val decl_x = build_var_cell(env, loc, "x", s2e_int, d2e_int(loc, "0"))
  val decl_y = build_var_cell(env, loc, "y", s2e_int, d2e_int(loc, "1"))
  val lval_x = resolve_var(env, loc, "x")
  val rval_y = resolve_var(env, loc, "y")
  val d2e_sw = d2exp_make_node(loc, D2Exchng(lval_x, rval_y))
//
  val d2body =
    d2exp_make_node
      (loc, D2Elet0(list_cons(decl_x, list_sing(decl_y)), d2e_sw))
//
  val () = tr12env_poplet0(env)
  val () = tr12env_poplam0(env)
//
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val(loc), d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun(loc), list_nil(), list_nil(), list_sing(d2f)))
//
  val decls = list_sing(fundecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[BL-SW] f() = (var x:Int=0; var y:Int=1; x :=: y)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
fun
mymain_blin((*void*)): void = let
//
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
//
  val () = PYB_log("######## B-LIN STAGE-0 SPIKE (at-view + ~p + &/! + move/swap) ########")
//
  val sel = PYB_probe()
  val _ =
    (
      case+ sel of
      | 1 => let val () = PYB_log("---- PROBE BL-AT (at-view S2Eatx2) ----")
                 val _ = probe_BL_AT() in 0 end
      | 2 => let val () = PYB_log("---- PROBE BL-LIN (D2Pfree ~p) ----")
                 val _ = probe_BL_LIN() in 0 end
      | 3 => let val () = PYB_log("---- PROBE BL-ADDR (D2Eaddr &x) ----")
                 val _ = probe_BL_ADDR() in 0 end
      | 4 => let val () = PYB_log("---- PROBE BL-DERF (D2Eeval !p) ----")
                 val _ = probe_BL_DERF() in 0 end
      | 5 => let val () = PYB_log("---- PROBE BL-MV (D2Exazgn :=>) ----")
                 val _ = probe_BL_MV() in 0 end
      | 6 => let val () = PYB_log("---- PROBE BL-SW (D2Exchng :=:) ----")
                 val _ = probe_BL_SW() in 0 end
      | 7 => let val () = PYB_log("---- PROBE BL-DERF2 (D2Eeval !(&x)) ----")
                 val _ = probe_BL_DERF2() in 0 end
      | 8 => let val () = PYB_log("---- PROBE BL-AT2 (at-view proof, no deref) ----")
                 val _ = probe_BL_AT2() in 0 end
      | _ => let val () = PYB_log("---- BL-AT ----")   val _ = probe_BL_AT()
                 val () = PYB_log("---- BL-LIN ----")  val _ = probe_BL_LIN()
                 val () = PYB_log("---- BL-ADDR ----") val _ = probe_BL_ADDR()
                 val () = PYB_log("---- BL-DERF ----") val _ = probe_BL_DERF()
                 val () = PYB_log("---- BL-DERF2 ----") val _ = probe_BL_DERF2()
                 val () = PYB_log("---- BL-AT2 ----")  val _ = probe_BL_AT2()
                 val () = PYB_log("---- BL-MV ----")   val _ = probe_BL_MV()
                 val () = PYB_log("---- BL-SW ----")   val _ = probe_BL_SW()
              in 0 end
    ) : sint
in
  PYB_log("######## END B-LIN SPIKE ########")
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_blin()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_blin_spike.dats]
*)
