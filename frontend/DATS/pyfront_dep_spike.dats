(* ****** ****** *)
(*
** STAGE-0 DEPENDENT/PROOF GATING SPIKE driver.
**
** Hand-builds at L2 (NO surface, NO lexer/parser) and runs each probe through the
** real stock pipeline trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a, then prints
** the post-tread3a nerror. EACH probe is an INDEPENDENT d2parsed in its OWN node
** process (PYB_probe selector) so a hard XATS000_cfail is ISOLATED.
**
** Probes (the static/dependent/proof parity area):
**   P1  index ARG on a type con            Foo(A, 0) : s2exp_apps(Foo, [typeArg, s2exp_int 0])
**   P2  universal over an INDEX var         {n:i0} ((Box(n)) -> Box(n))  used/applied
**   P3  guard {n:i0 | n >= 0}               uni0 with s2ps=[ gte_i0_i0(n, 0) ]
**   P4  dataprop  P(...) at sort prop       the enum recipe with s2cst sort = the_sort2_prop
**   P5  prfun / prval                       D2Cfundclst(FNKprfn1) ; D2Cvaldclst(VLKprval)
**   P6  sortdef / stacst / stadef           D2Csortdef ; D2Cstacst0 ; D2Csexpdef(int 2)
**
** PURELY ADDITIVE: only CALLS lib2xatsopt. Nothing under srcgen2/ or language-server/
** is modified. Typecheck-only (no codegen).
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
// resolve a (prelude or env) static NAME to its s2exp (head s2cst on hit).
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
// resolve a (prelude) static NAME to its head s2cst (for #stacst0 operators like gte_i0_i0).
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
// build a static arithmetic/comparison application  op(a, b)  from a prelude #stacst0
// (add_i0_i0 / gte_i0_i0 / ...). On unbound op, returns s2exp_none0 (degrades gracefully).
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
// ===== PROBE P1 : index ARG on a type constructor (structural) =================
//
//   A parametric con  Box : (type, i0) -> tbox   (ONE type param + ONE int index).
//   Annotate a value  v : Box(Int, 0)   built via s2exp_apps(Box, [Int, s2exp_int 0]).
//   We also build a producer con  Mk : {A:type}{n:i0} () -> Box(A, n)  and CALL it so
//   the index arg flows through trans23 (not just an annotation).
//
fun
probe_P1((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// (1) the con `Box` with sort (type, i0) -> tbox.
  val sym_box = symbl_make_name("Box")
  val s2t_box = S2Tfun1(list_cons(the_sort2_type, list_sing(the_sort2_int0)), the_sort2_tbox)
  val s2c_box = s2cst_make_idst(loc, sym_box, s2t_box)
  val () = tr12env_add1_s2cst(env, s2c_box)
//
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
// (2) the param A:type and index n:i0, pushed into a lam-scope to build Mk's con type.
  val () = tr12env_pshlam0(env)
  val s2v_A = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val s2v_n = s2var_make_idst(symbl_make_name("n"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_A)
  val () = tr12env_add0_s2var(env, s2v_n)
  val s2e_A = s2exp_var(s2v_A)
  val s2e_n = s2exp_var(s2v_n)
//
// Mk : () -> Box(A, n)  — result Box applied to TYPE arg A and INDEX arg n.
  val s2e_box_An =
    s2exp_apps(loc, s2exp_cst(s2c_box), list_cons(s2e_A, list_sing(s2e_n)))
  val sexp_mk = s2exp_fun1_nil0((-1)(*npf*), list_nil(), s2e_box_An)
  val tqas = list_sing(t2qag(loc, list_cons(s2v_A, list_sing(s2v_n)))) : t2qaglst
  val () = tr12env_poplam0(env)
//
// make Mk a value-constructor: a datatype Box with the single con Mk.
  val tok_mk = token_make_node(loc, T_IDALP("Mk"))
  val d2c_mk = d2con_make_idtp(tok_mk, tqas, sexp_mk)
  val () = d2con_set_ctag(d2c_mk, 0)
  val d2cs_box = list_sing(d2c_mk)
  val () = s2cst_set_d2cs(s2c_box, d2cs_box)
  val () = tr12env_add1_d2conlst(env, d2cs_box)
  val dtdecl =
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c_box)))
//
// def f() -> Box(Int, 0):  ( the annotation carries the INDEX arg 0 )
//     v : Box(Int, 0) = Mk()
//     v
  val s2e_int0 = s2exp_int(0)
  val s2e_box_int0 =
    s2exp_apps(loc, s2exp_cst(s2c_box), list_cons(s2e_int, list_sing(s2e_int0)))
//
  val sym_f = symbl_make_name("f")
  val d2v_f = d2var_new2_name(loc, sym_f)
  val () = tr12env_add0_d2var(env, d2v_f)
//
  val sres = S2RESsome(S2EFFnone(), s2e_box_int0)
//
  val () = tr12env_pshlam0(env)
//
// body: a `val v : Box(Int,0) = Mk()` then `v`.
  val d2v_v = d2var_new2_name(loc, symbl_make_name("v"))
  val pat_v = d2pat_var(loc, d2v_v)
  val pat_v_annot = d2pat_make_node(loc, D2Pannot(pat_v, s1exp_none0(loc), s2e_box_int0))
  val () = tr12env_add0_d2var(env, d2v_v)
//
  val d2e_mkref = d2exp_make_node(loc, D2Econ(d2c_mk))
  val d2e_mkapp = d2exp_make_node(loc, D2Edap0(d2e_mkref))
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val vdcl = d2valdcl_make_args(loc, pat_v_annot, TEQD2EXPsome(tok_val, d2e_mkapp), WTHS2EXPnone())
  val dcl_v = d2ecl_make_node(loc, D2Cvaldclst(tok_val, list_sing(vdcl)))
//
  val d2e_vref = resolve_var(env, loc, "v")
  val d2body = d2exp_make_node(loc, D2Elet0(list_sing(dcl_v), d2e_vref))
//
  val () = tr12env_poplam0(env)
//
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, list_nil()(*f2as*), sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil(), list_nil(), list_sing(d2f)))
//
  val decls = list_cons(dtdecl, list_sing(fundecl))
  val t2penv = tr12env_free_top(env)
in
  run_one("[P1] index ARG Box(Int,0)=Mk() ; f()->Box(Int,0)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE P2 : universal over an INDEX var (collapse vs crash) ===============
//
//   A con  Box : (type, i0) -> tbox   (reuse).
//   A function genuinely quantified over n :   id : {A:type}{n:i0} (Box(A,n)) -> Box(A,n)
//   built as a d2cst whose sexp is s2exp_uni0([A,n], [], (Box(A,n))->Box(A,n)), then CALLED.
//
fun
probe_P2((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val sym_box = symbl_make_name("Box")
  val s2t_box = S2Tfun1(list_cons(the_sort2_type, list_sing(the_sort2_int0)), the_sort2_tbox)
  val s2c_box = s2cst_make_idst(loc, sym_box, s2t_box)
  val () = tr12env_add1_s2cst(env, s2c_box)
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
// (1) build the universally-quantified fun type {A:type}{n:i0} (Box(A,n))->Box(A,n).
  val () = tr12env_pshlam0(env)
  val s2v_A = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val s2v_n = s2var_make_idst(symbl_make_name("n"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_A)
  val () = tr12env_add0_s2var(env, s2v_n)
  val s2e_A = s2exp_var(s2v_A)
  val s2e_n = s2exp_var(s2v_n)
  val s2e_box_An =
    s2exp_apps(loc, s2exp_cst(s2c_box), list_cons(s2e_A, list_sing(s2e_n)))
  val s2e_fun = s2exp_fun1_nil0((-1)(*npf*), list_sing(s2e_box_An), s2e_box_An)
  val () = tr12env_poplam0(env)
//
  val s2e_uni =
    s2exp_uni0(list_cons(s2v_A, list_sing(s2v_n)), list_nil()(*s2ps*), s2e_fun)
//
// (2) declare it as a dynamic constant `id` with that type (D2Cdynconst).
  val tok_funk = token_make_node(loc, T_FUN(FNKfn1))
  val tok_id   = token_make_node(loc, T_IDALP("id"))
  val d2c_id = d2cst_make_idtp(tok_funk, tok_id, list_nil()(*tqas*), s2e_uni)
  val () = tr12env_add1_d2cst(env, d2c_id)
  val dargs = list_nil() : d2arglst
  val cstdcl_id = d2cstdcl_make_args(loc, d2c_id, dargs, S2RESnone(), TEQD2EXPnone())
  val dcl_id = d2ecl_make_node(loc, D2Cdynconst(tok_funk, list_nil(), list_sing(cstdcl_id)))
//
// (3) USE it:  def g(b: Box(Int, 3)) -> Box(Int, 3): id(b)
  val s2e_int3 = s2exp_int(3)
  val s2e_box_int3 =
    s2exp_apps(loc, s2exp_cst(s2c_box), list_cons(s2e_int, list_sing(s2e_int3)))
//
  val sym_g = symbl_make_name("g")
  val d2v_g = d2var_new2_name(loc, sym_g)
  val () = tr12env_add0_d2var(env, d2v_g)
//
  val d2v_b = d2var_new2_name(loc, symbl_make_name("b"))
  val pat_b = d2pat_var(loc, d2v_b)
  val pat_b_annot = d2pat_make_node(loc, D2Pannot(pat_b, s1exp_none0(loc), s2e_box_int3))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_b_annot))))
  val sres = S2RESsome(S2EFFnone(), s2e_box_int3)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2e_idref = d2exp_make_node(loc, D2Ecst(d2c_id))
  val d2e_bref = resolve_var(env, loc, "b")
  val d2body = d2exp_dapp(loc, d2e_idref, (-1), list_sing(d2e_bref))
  val () = tr12env_poplam0(env)
//
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2g =
    d2fundcl_make_args
      (loc, d2v_g, f2as, sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
  val dcl_g =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil(), list_nil(), list_sing(d2g)))
//
  val decls = list_cons(dcl_id, list_sing(dcl_g))
  val t2penv = tr12env_free_top(env)
in
  run_one("[P2] uni {A:type}{n:i0}(Box(A,n))->Box(A,n) ; g calls id(b)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE P3 : guard {n:i0 | n >= 0} (dropped at stpize; no crash?) ==========
//
//   Same as P2 but the uni0 carries a GUARD s2ps = [ gte_i0_i0(n, 0) ].
//
fun
probe_P3((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val sym_box = symbl_make_name("Box")
  val s2t_box = S2Tfun1(list_cons(the_sort2_type, list_sing(the_sort2_int0)), the_sort2_tbox)
  val s2c_box = s2cst_make_idst(loc, sym_box, s2t_box)
  val () = tr12env_add1_s2cst(env, s2c_box)
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val () = tr12env_pshlam0(env)
  val s2v_A = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val s2v_n = s2var_make_idst(symbl_make_name("n"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_A)
  val () = tr12env_add0_s2var(env, s2v_n)
  val s2e_A = s2exp_var(s2v_A)
  val s2e_n = s2exp_var(s2v_n)
//
// the GUARD:  n >= 0  via the prelude #stacst0 gte_i0_i0 (sort (i0,i0)->b0).
  val s2e_zero = s2exp_int(0)
  val s2e_guard = build_binop(env, loc, "gte_i0_i0", s2e_n, s2e_zero)
//
  val s2e_box_An =
    s2exp_apps(loc, s2exp_cst(s2c_box), list_cons(s2e_A, list_sing(s2e_n)))
  val s2e_fun = s2exp_fun1_nil0((-1)(*npf*), list_sing(s2e_box_An), s2e_box_An)
  val () = tr12env_poplam0(env)
//
  val s2e_uni =
    s2exp_uni0(list_cons(s2v_A, list_sing(s2v_n)), list_sing(s2e_guard)(*GUARD*), s2e_fun)
//
  val tok_funk = token_make_node(loc, T_FUN(FNKfn1))
  val tok_id   = token_make_node(loc, T_IDALP("idg"))
  val d2c_id = d2cst_make_idtp(tok_funk, tok_id, list_nil()(*tqas*), s2e_uni)
  val () = tr12env_add1_d2cst(env, d2c_id)
  val cstdcl_id = d2cstdcl_make_args(loc, d2c_id, list_nil(), S2RESnone(), TEQD2EXPnone())
  val dcl_id = d2ecl_make_node(loc, D2Cdynconst(tok_funk, list_nil(), list_sing(cstdcl_id)))
//
  val s2e_int5 = s2exp_int(5)
  val s2e_box_int5 =
    s2exp_apps(loc, s2exp_cst(s2c_box), list_cons(s2e_int, list_sing(s2e_int5)))
//
  val sym_g = symbl_make_name("h")
  val d2v_g = d2var_new2_name(loc, sym_g)
  val () = tr12env_add0_d2var(env, d2v_g)
  val d2v_b = d2var_new2_name(loc, symbl_make_name("b"))
  val pat_b = d2pat_var(loc, d2v_b)
  val pat_b_annot = d2pat_make_node(loc, D2Pannot(pat_b, s1exp_none0(loc), s2e_box_int5))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_b_annot))))
  val sres = S2RESsome(S2EFFnone(), s2e_box_int5)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2e_idref = d2exp_make_node(loc, D2Ecst(d2c_id))
  val d2e_bref = resolve_var(env, loc, "b")
  val d2body = d2exp_dapp(loc, d2e_idref, (-1), list_sing(d2e_bref))
  val () = tr12env_poplam0(env)
//
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2g =
    d2fundcl_make_args
      (loc, d2v_g, f2as, sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
  val dcl_g =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil(), list_nil(), list_sing(d2g)))
//
  val decls = list_cons(dcl_id, list_sing(dcl_g))
  val t2penv = tr12env_free_top(env)
in
  run_one("[P3] guard {n:i0 | n>=0} on uni ; h calls idg(b)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE P4 : dataprop (enum recipe with s2cst sort = the_sort2_prop) =======
//
//   prop  LE(i0, i0)  with two cons:
//     LEbas : {n:i0} () -> LE(n, n)
//     LEind : {m:i0}{n:i0} (LE(m,n)) -> LE(m, n+1)
//   Then a prval/prfun that USES it lives in P5; here we just declare the dataprop and
//   a prfun consuming/producing it.
//
fun
probe_P4((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// (1) the prop con `LE` : (i0, i0) -> prop.  DELTA vs enum: sort RESULT is the_sort2_prop.
  val sym_le = symbl_make_name("LE")
  val s2t_le = S2Tfun1(list_cons(the_sort2_int0, list_sing(the_sort2_int0)), the_sort2_prop)
  val s2c_le = s2cst_make_idst(loc, sym_le, s2t_le)
  val () = tr12env_add1_s2cst(env, s2c_le)
//
// (2) con LEbas : {n:i0} () -> LE(n, n)
  val () = tr12env_pshlam0(env)
  val s2v_n = s2var_make_idst(symbl_make_name("n"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_n)
  val s2e_n = s2exp_var(s2v_n)
  val s2e_le_nn =
    s2exp_apps(loc, s2exp_cst(s2c_le), list_cons(s2e_n, list_sing(s2e_n)))
  val sexp_bas = s2exp_fun1_nil0((-1)(*npf*), list_nil(), s2e_le_nn)
  val tqas_bas = list_sing(t2qag(loc, list_sing(s2v_n))) : t2qaglst
  val () = tr12env_poplam0(env)
  val tok_bas = token_make_node(loc, T_IDALP("LEbas"))
  val d2c_bas = d2con_make_idtp(tok_bas, tqas_bas, sexp_bas)
  val () = d2con_set_ctag(d2c_bas, 0)
//
// (3) con LEind : {m,n:i0} (LE(m,n)) -> LE(m, n+1)
  val () = tr12env_pshlam0(env)
  val s2v_m = s2var_make_idst(symbl_make_name("m"), the_sort2_int0)
  val s2v_n2 = s2var_make_idst(symbl_make_name("n"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_m)
  val () = tr12env_add0_s2var(env, s2v_n2)
  val s2e_m = s2exp_var(s2v_m)
  val s2e_n2 = s2exp_var(s2v_n2)
  val s2e_le_mn =
    s2exp_apps(loc, s2exp_cst(s2c_le), list_cons(s2e_m, list_sing(s2e_n2)))
  val s2e_np1 = build_binop(env, loc, "add_i0_i0", s2e_n2, s2exp_int(1))
  val s2e_le_mnp1 =
    s2exp_apps(loc, s2exp_cst(s2c_le), list_cons(s2e_m, list_sing(s2e_np1)))
  val sexp_ind = s2exp_fun1_nil0((-1)(*npf*), list_sing(s2e_le_mn), s2e_le_mnp1)
  val tqas_ind = list_sing(t2qag(loc, list_cons(s2v_m, list_sing(s2v_n2)))) : t2qaglst
  val () = tr12env_poplam0(env)
  val tok_ind = token_make_node(loc, T_IDALP("LEind"))
  val d2c_ind = d2con_make_idtp(tok_ind, tqas_ind, sexp_ind)
  val () = d2con_set_ctag(d2c_ind, 1)
//
  val d2cs_le = list_cons(d2c_bas, list_sing(d2c_ind))
  val () = s2cst_set_d2cs(s2c_le, d2cs_le)
  val () = tr12env_add1_d2conlst(env, d2cs_le)
  val dtdecl =
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c_le)))
//
  val decls = list_sing(dtdecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[P4] dataprop LE(i0,i0):{LEbas,LEind} (sort=prop)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE P5 : prfun / prval (proof funkind/valkind) =========================
//
//   prfun pf() : Int = 0        D2Cfundclst(FNKprfn1)
//   prval pv : Int = 0          D2Cvaldclst(VLKprval)
//
fun
probe_P5((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
// (A) prfun pf() -> Int: 0
  val sym_pf = symbl_make_name("pf")
  val d2v_pf = d2var_new2_name(loc, sym_pf)
  val () = tr12env_add0_d2var(env, d2v_pf)
  val sres_pf = S2RESsome(S2EFFnone(), s2e_int)
  val () = tr12env_pshlam0(env)
  val body_pf = d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01("0"))))
  val () = tr12env_poplam0(env)
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_prfun = token_make_node(loc, T_FUN(FNKprfn1))
  val d2pf =
    d2fundcl_make_args
      (loc, d2v_pf, list_nil()(*f2as*), sres_pf, TEQD2EXPsome(tok_val, body_pf), WTHS2EXPnone())
  val dcl_pf =
    d2ecl_make_node(loc, D2Cfundclst(tok_prfun, list_nil(), list_nil(), list_sing(d2pf)))
//
// (B) prval pv : Int = 0
  val d2v_pv = d2var_new2_name(loc, symbl_make_name("pv"))
  val pat_pv = d2pat_var(loc, d2v_pv)
  val pat_pv_annot = d2pat_make_node(loc, D2Pannot(pat_pv, s1exp_none0(loc), s2e_int))
  val () = tr12env_add0_d2var(env, d2v_pv)
  val body_pv = d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01("0"))))
  val tok_prval = token_make_node(loc, T_VAL(VLKprval))
  val vdcl_pv =
    d2valdcl_make_args(loc, pat_pv_annot, TEQD2EXPsome(tok_prval, body_pv), WTHS2EXPnone())
  val dcl_pv = d2ecl_make_node(loc, D2Cvaldclst(tok_prval, list_sing(vdcl_pv)))
//
  val decls = list_cons(dcl_pf, list_sing(dcl_pv))
  val t2penv = tr12env_free_top(env)
in
  run_one("[P5] prfun pf()->Int:0 ; prval pv:Int=0  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE P6 : sortdef / stacst / stadef ====================================
//
//   sortdef Nat = int     D2Csortdef(Nat, S2TEXsrt(the_sort2_int0))   (sort ALIAS)
//   stacst  c : int       D2Cstacst0(c, the_sort2_int0)
//   stadef  Two = 2       D2Csexpdef(Two, s2exp_int 2)  (static int def at sort i0)
//
fun
probe_P6((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// (A) sortdef Nat = int
  val sym_nat = symbl_make_name("Nat")
  val s2tx = S2TEXsrt(the_sort2_int0)
  val () = tr12env_add0_s2tex(env, sym_nat, s2tx)
  val dcl_sortdef = d2ecl_make_node(loc, D2Csortdef(sym_nat, s2tx))
//
// (B) stacst c : int
  val sym_c = symbl_make_name("c")
  val s2c_c = s2cst_make_idst(loc, sym_c, the_sort2_int0)
  val () = tr12env_add1_s2cst(env, s2c_c)
  val dcl_stacst = d2ecl_make_node(loc, D2Cstacst0(s2c_c, the_sort2_int0))
//
// (C) stadef Two = 2
  val sym_two = symbl_make_name("Two")
  val s2e_two = s2exp_int(2)
  val s2c_two = s2cst_make_idst(loc, sym_two, the_sort2_int0)
  val () = s2cst_set_sexp(s2c_two, s2e_two)
  val () = s2cst_set_styp(s2c_two, s2exp_stpize(s2e_two))
  val () = tr12env_add1_s2cst(env, s2c_two)
  val dcl_stadef = d2ecl_make_node(loc, D2Csexpdef(s2c_two, s2e_two))
//
  val decls = list_cons(dcl_sortdef, list_cons(dcl_stacst, list_sing(dcl_stadef)))
  val t2penv = tr12env_free_top(env)
in
  run_one("[P6] sortdef Nat=int ; stacst c:int ; stadef Two=2  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== STRESS P7 : MISMATCHED index (soundness vs erasure check) ================
//
//   def f() -> Box(Int, 0):  ( v : Box(Int, 1) = Mk[?,1]() ; v )
//   The annotation index (1) DISAGREES with the result-type index (0). If the index
//   were checked, this would be 1 error; if ERASED, nerror stays 0. Tells us whether
//   index soundness survives stpize (expected: ERASED -> nerror=0, NO crash).
//
fun
probe_P7((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val sym_box = symbl_make_name("Box")
  val s2t_box = S2Tfun1(list_cons(the_sort2_type, list_sing(the_sort2_int0)), the_sort2_tbox)
  val s2c_box = s2cst_make_idst(loc, sym_box, s2t_box)
  val () = tr12env_add1_s2cst(env, s2c_box)
  val s2e_int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val () = tr12env_pshlam0(env)
  val s2v_A = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val s2v_n = s2var_make_idst(symbl_make_name("n"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_A)
  val () = tr12env_add0_s2var(env, s2v_n)
  val s2e_A = s2exp_var(s2v_A)
  val s2e_n = s2exp_var(s2v_n)
  val s2e_box_An =
    s2exp_apps(loc, s2exp_cst(s2c_box), list_cons(s2e_A, list_sing(s2e_n)))
  val sexp_mk = s2exp_fun1_nil0((-1), list_nil(), s2e_box_An)
  val tqas = list_sing(t2qag(loc, list_cons(s2v_A, list_sing(s2v_n)))) : t2qaglst
  val () = tr12env_poplam0(env)
//
  val tok_mk = token_make_node(loc, T_IDALP("Mk"))
  val d2c_mk = d2con_make_idtp(tok_mk, tqas, sexp_mk)
  val () = d2con_set_ctag(d2c_mk, 0)
  val d2cs_box = list_sing(d2c_mk)
  val () = s2cst_set_d2cs(s2c_box, d2cs_box)
  val () = tr12env_add1_d2conlst(env, d2cs_box)
  val dtdecl =
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c_box)))
//
// f result type Box(Int, 0); local annotation Box(Int, 1) — DELIBERATE INDEX MISMATCH.
  val s2e_box_int0 =
    s2exp_apps(loc, s2exp_cst(s2c_box), list_cons(s2e_int, list_sing(s2exp_int(0))))
  val s2e_box_int1 =
    s2exp_apps(loc, s2exp_cst(s2c_box), list_cons(s2e_int, list_sing(s2exp_int(1))))
//
  val sym_f = symbl_make_name("f7")
  val d2v_f = d2var_new2_name(loc, sym_f)
  val () = tr12env_add0_d2var(env, d2v_f)
  val sres = S2RESsome(S2EFFnone(), s2e_box_int0)
//
  val () = tr12env_pshlam0(env)
  val d2v_v = d2var_new2_name(loc, symbl_make_name("v"))
  val pat_v = d2pat_var(loc, d2v_v)
  val pat_v_annot = d2pat_make_node(loc, D2Pannot(pat_v, s1exp_none0(loc), s2e_box_int1))
  val () = tr12env_add0_d2var(env, d2v_v)
  val d2e_mkref = d2exp_make_node(loc, D2Econ(d2c_mk))
  val d2e_mkapp = d2exp_make_node(loc, D2Edap0(d2e_mkref))
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val vdcl = d2valdcl_make_args(loc, pat_v_annot, TEQD2EXPsome(tok_val, d2e_mkapp), WTHS2EXPnone())
  val dcl_v = d2ecl_make_node(loc, D2Cvaldclst(tok_val, list_sing(vdcl)))
  val d2e_vref = resolve_var(env, loc, "v")
  val d2body = d2exp_make_node(loc, D2Elet0(list_sing(dcl_v), d2e_vref))
  val () = tr12env_poplam0(env)
//
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, list_nil(), sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil(), list_nil(), list_sing(d2f)))
//
  val decls = list_cons(dtdecl, list_sing(fundecl))
  val t2penv = tr12env_free_top(env)
in
  run_one("[P7] MISMATCH: f7()->Box(Int,0) body annot Box(Int,1)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== STRESS P8 : indexed PRIMITIVE int(n) — the M5a hazard ====================
//
//   Build the indexed primitive `the_s2exp_sint1(0)` = sint1(0) = gint1(sint_k,0) =
//   gint_type(sint_k,0)  (an #abstype -> T2Pbas) as an annotation on an int literal.
//   This is what surface `int(n)` would lower to. The M5a finding predicts unify00
//   crashes on T2Pbas (no T2Pbas arm). We resolve the parametric sexpdef and apply it.
//
fun
probe_P8((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// resolve the indexed-int parametric sexpdef name (if registered in a fresh env).
  val s2f_sint1 = resolve_typ_name(env, "the_s2exp_sint1")
// DIAGNOSTIC: is the indexed-primitive name actually resolvable? (none0 => VACUOUS test)
  val () =
    (case+ s2f_sint1.node() of
     | S2Enone0() => PYB_log("   [P8 diag] the_s2exp_sint1 -> S2Enone0 (UNRESOLVED => annotation VACUOUS)")
     | S2Ecst(_)  => PYB_log("   [P8 diag] the_s2exp_sint1 -> S2Ecst (resolved to a single s2cst)")
     | _          => PYB_log("   [P8 diag] the_s2exp_sint1 -> other node (resolved, non-cst head)")
    )
  val s2e_sint1_0 = s2exp_apps(loc, s2f_sint1, list_sing(s2exp_int(0)))
//
// def f() -> int(0):  ( v : int(0) = 0 ; v )  — int literal annotated with sint1(0).
  val sym_f = symbl_make_name("f8")
  val d2v_f = d2var_new2_name(loc, sym_f)
  val () = tr12env_add0_d2var(env, d2v_f)
  val sres = S2RESsome(S2EFFnone(), s2e_sint1_0)
//
  val () = tr12env_pshlam0(env)
  val d2v_v = d2var_new2_name(loc, symbl_make_name("v"))
  val pat_v = d2pat_var(loc, d2v_v)
  val pat_v_annot = d2pat_make_node(loc, D2Pannot(pat_v, s1exp_none0(loc), s2e_sint1_0))
  val () = tr12env_add0_d2var(env, d2v_v)
  val d2e_zero = d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01("0"))))
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val vdcl = d2valdcl_make_args(loc, pat_v_annot, TEQD2EXPsome(tok_val, d2e_zero), WTHS2EXPnone())
  val dcl_v = d2ecl_make_node(loc, D2Cvaldclst(tok_val, list_sing(vdcl)))
  val d2e_vref = resolve_var(env, loc, "v")
  val d2body = d2exp_make_node(loc, D2Elet0(list_sing(dcl_v), d2e_vref))
  val () = tr12env_poplam0(env)
//
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, list_nil(), sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, list_nil(), list_nil(), list_sing(d2f)))
//
  val decls = list_sing(fundecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[P8] indexed PRIM int(0)=the_s2exp_sint1(0) annot ; v:int(0)=0  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== STRESS P9 : dataview (P4 recipe with s2cst sort = the_sort2_view) ========
//
//   view  VW(addr)  with one con  VWmk : {l:addr} () -> VW(l).  (sort RESULT = view.)
//
fun
probe_P9((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val sym_vw = symbl_make_name("VW")
  val s2t_vw = S2Tfun1(list_sing(the_sort2_addr), the_sort2_view)
  val s2c_vw = s2cst_make_idst(loc, sym_vw, s2t_vw)
  val () = tr12env_add1_s2cst(env, s2c_vw)
//
  val () = tr12env_pshlam0(env)
  val s2v_l = s2var_make_idst(symbl_make_name("l"), the_sort2_addr)
  val () = tr12env_add0_s2var(env, s2v_l)
  val s2e_l = s2exp_var(s2v_l)
  val s2e_vw_l =
    s2exp_apps(loc, s2exp_cst(s2c_vw), list_sing(s2e_l))
  val sexp_mk = s2exp_fun1_nil0((-1), list_nil(), s2e_vw_l)
  val tqas = list_sing(t2qag(loc, list_sing(s2v_l))) : t2qaglst
  val () = tr12env_poplam0(env)
//
  val tok_mk = token_make_node(loc, T_IDALP("VWmk"))
  val d2c_mk = d2con_make_idtp(tok_mk, tqas, sexp_mk)
  val () = d2con_set_ctag(d2c_mk, 0)
  val d2cs_vw = list_sing(d2c_mk)
  val () = s2cst_set_d2cs(s2c_vw, d2cs_vw)
  val () = tr12env_add1_d2conlst(env, d2cs_vw)
  val dtdecl =
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c_vw)))
//
  val decls = list_sing(dtdecl)
  val t2penv = tr12env_free_top(env)
in
  run_one("[P9] dataview VW(addr):{VWmk} (sort=view)  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
fun
mymain_dep((*void*)): void = let
//
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
//
  val () = PYB_log("######## STAGE-0 DEPENDENT/PROOF GATING SPIKE ########")
//
  val sel = PYB_probe()
  val _ =
    (
      case+ sel of
      | 1 => let val () = PYB_log("---- PROBE P1 (index arg on type con) ----")
                 val _ = probe_P1() in 0 end
      | 2 => let val () = PYB_log("---- PROBE P2 (universal over index var) ----")
                 val _ = probe_P2() in 0 end
      | 3 => let val () = PYB_log("---- PROBE P3 (guard {n|n>=0}) ----")
                 val _ = probe_P3() in 0 end
      | 4 => let val () = PYB_log("---- PROBE P4 (dataprop) ----")
                 val _ = probe_P4() in 0 end
      | 5 => let val () = PYB_log("---- PROBE P5 (prfun/prval) ----")
                 val _ = probe_P5() in 0 end
      | 6 => let val () = PYB_log("---- PROBE P6 (sortdef/stacst/stadef) ----")
                 val _ = probe_P6() in 0 end
      | 7 => let val () = PYB_log("---- STRESS P7 (mismatched index) ----")
                 val _ = probe_P7() in 0 end
      | 8 => let val () = PYB_log("---- STRESS P8 (indexed primitive int(n) M5a hazard) ----")
                 val _ = probe_P8() in 0 end
      | 9 => let val () = PYB_log("---- STRESS P9 (dataview) ----")
                 val _ = probe_P9() in 0 end
      | _ => let val () = PYB_log("---- P1 ----") val _ = probe_P1()
                 val () = PYB_log("---- P2 ----") val _ = probe_P2()
                 val () = PYB_log("---- P3 ----") val _ = probe_P3()
                 val () = PYB_log("---- P4 ----") val _ = probe_P4()
                 val () = PYB_log("---- P5 ----") val _ = probe_P5()
                 val () = PYB_log("---- P6 ----") val _ = probe_P6()
                 val () = PYB_log("---- P7 ----") val _ = probe_P7()
                 val () = PYB_log("---- P8 ----") val _ = probe_P8()
                 val () = PYB_log("---- P9 ----") val _ = probe_P9()
              in 0 end
    ) : sint
in
  PYB_log("######## END STAGE-0 DEP SPIKE ########")
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_dep()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_dep_spike.dats]
*)
