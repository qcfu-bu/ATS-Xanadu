(* ****** ****** *)
(*
** A-QUANT (explicit-quantifier surface) STAGE-0 SPIKE driver.
**
** Hand-builds at L2 (NO surface, NO lexer/parser) and runs each probe through the real
** stock pipeline trans2a -> trsym2b -> t2read0 -> trans23 -> tread3a, then prints the
** post-tread3a nerror. EACH probe is an INDEPENDENT d2parsed in its OWN node process
** (PYB_probe selector) so a hard XATS000_cfail is ISOLATED.
**
** Probes (the two UNPROVEN A-quant L2 pieces; uni0/guard/index are PROVEN by dep-spike P2/P3):
**   SX-EXI  existential  s2exp_exi0([m],[],Box(A,m))   on a fn result `exists[m] Box(A,m)`,
**           body = Mk() where Mk : {A}{m} ()->Box(A,m). Does exi0 collapse gracefully
**           like uni0 (nerror=0, NO crash)?
**   SX-SUB  subset sort  D2Csortdef(Nat, S2TEXsub(a, [a>=0]))  (`@sort type Nat={a:SInt|a>=0}`),
**           registered via tr12env_add0_s2tex; then USED as a SORT for a stacst c:Nat to
**           verify Nat resolves as a sort downstream. nerror=0 / no crash?
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
// ===== PROBE SX-EXI : existential  s2exp_exi0 (collapse vs crash) ================
//
//   A con  Box : (type, i0) -> tbox.
//   A producer con  Mk : {A:type}{m:i0} () -> Box(A,m).
//   A polymorphic fn  some_box : {A:type} () -> exists[m:i0] Box(A,m)
//   whose RESULT type is s2exp_exi0([m],[],Box(A,m)) and whose body is `Mk()`.
//   This is exactly the surface `def some_box[A]() -> exists[m: SInt] Box[A, m]: Mk()`.
//
fun
probe_SX_EXI((*void*)): sint = let
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
// (2) the producer con  Mk : {A:type}{m:i0} () -> Box(A,m).
  val () = tr12env_pshlam0(env)
  val s2v_A = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val s2v_m = s2var_make_idst(symbl_make_name("m"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_A)
  val () = tr12env_add0_s2var(env, s2v_m)
  val s2e_A = s2exp_var(s2v_A)
  val s2e_m = s2exp_var(s2v_m)
  val s2e_box_Am =
    s2exp_apps(loc, s2exp_cst(s2c_box), list_cons(s2e_A, list_sing(s2e_m)))
  val sexp_mk = s2exp_fun1_nil0((-1)(*npf*), list_nil(), s2e_box_Am)
  val tqas_mk = list_sing(t2qag(loc, list_cons(s2v_A, list_sing(s2v_m)))) : t2qaglst
  val () = tr12env_poplam0(env)
//
  val tok_mk = token_make_node(loc, T_IDALP("Mk"))
  val d2c_mk = d2con_make_idtp(tok_mk, tqas_mk, sexp_mk)
  val () = d2con_set_ctag(d2c_mk, 0)
  val d2cs_box = list_sing(d2c_mk)
  val () = s2cst_set_d2cs(s2c_box, d2cs_box)
  val () = tr12env_add1_d2conlst(env, d2cs_box)
  val dtdecl =
    d2ecl_make_node(loc, D2Cdatatype(d1ecl_none0(loc), list_sing(s2c_box)))
//
// (3) the fn  some_box : {A:type} () -> (exists[m:i0] Box(A,m)).
//     Build the result type as an EXISTENTIAL over a FRESH index var m, the A bound by the
//     enclosing universal tqas (a polymorphic param). some_box[A]() returns "a Box of SOME m".
  val () = tr12env_pshlam0(env)
  val s2v_A2 = s2var_make_idst(symbl_make_name("A"), the_sort2_type)
  val () = tr12env_add0_s2var(env, s2v_A2)
  val s2e_A2 = s2exp_var(s2v_A2)
//
//   the existential index m (a SEPARATE binder scope nested under the universal A).
  val () = tr12env_pshlam0(env)
  val s2v_m2 = s2var_make_idst(symbl_make_name("m"), the_sort2_int0)
  val () = tr12env_add0_s2var(env, s2v_m2)
  val s2e_m2 = s2exp_var(s2v_m2)
  val s2e_box_A2m2 =
    s2exp_apps(loc, s2exp_cst(s2c_box), list_cons(s2e_A2, list_sing(s2e_m2)))
  val () = tr12env_poplam0(env)
//   THE EXISTENTIAL: exists[m:i0] Box(A, m).
  val s2e_exi =
    s2exp_exi0(list_sing(s2v_m2), list_nil()(*s2ps*), s2e_box_A2m2)
//
  val tqas_sb = list_sing(t2qag(loc, list_sing(s2v_A2))) : t2qaglst
  val () = tr12env_poplam0(env)
//
  val sym_sb = symbl_make_name("some_box")
  val d2v_sb = d2var_new2_name(loc, sym_sb)
  val () = tr12env_add0_d2var(env, d2v_sb)
  val sres_sb = S2RESsome(S2EFFnone(), s2e_exi)
//
//   body: Mk()  (Mk : {A}{m}()->Box(A,m) — the existential m gets witnessed by Mk's m).
  val () = tr12env_pshlam0(env)
  val d2e_mkref = d2exp_make_node(loc, D2Econ(d2c_mk))
  val d2body = d2exp_make_node(loc, D2Edap0(d2e_mkref))
  val () = tr12env_poplam0(env)
//
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
  val d2sb =
    d2fundcl_make_args
      (loc, d2v_sb, list_nil()(*f2as*), sres_sb, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
  val fundecl =
    d2ecl_make_node(loc, D2Cfundclst(tok_fun, tqas_sb, list_nil()(*d2cstlst*), list_sing(d2sb)))
//
  val decls = list_cons(dtdecl, list_sing(fundecl))
  val t2penv = tr12env_free_top(env)
in
  run_one("[SX-EXI] some_box[A]()->exists[m:i0]Box(A,m) body=Mk()  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE SX-SUB : subset sort  S2TEXsub (collapse vs crash) ==================
//
//   The exact `f0_sortdef`/`S1TDFtsub` recipe from trans12_decl00.dats:1291 :
//     @sort type Nat = {a: SInt | a >= 0}
//   ->  s2v1 = a:i0 ; push scope ; add0_s2var(a) ; lower guard [a>=0] at sort bool ; pop ;
//       s2tx = S2TEXsub(a, [a>=0]) ;
//       D2Csortdef(Nat, s2tx)  +  tr12env_add0_s2tex(env, Nat, s2tx)  (so Nat resolves as sort).
//   Then USE Nat as a SORT: stacst c : Nat — confirms the new sort name resolves downstream.
//
fun
probe_SX_SUB((*void*)): sint = let
//
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
// (A) @sort type Nat = {a: SInt | a >= 0}  ->  D2Csortdef(Nat, S2TEXsub(a, [a>=0]))
  val sym_nat = symbl_make_name("Nat")
  val s2v_a = s2var_make_idst(symbl_make_name("a"), the_sort2_int0)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_s2var(env, s2v_a)
  val s2e_a = s2exp_var(s2v_a)
  val s2e_zero = s2exp_int(0)
  val s2e_guard = build_binop(env, loc, "gte_i0_i0", s2e_a, s2e_zero)
  val s2ps = list_sing(s2e_guard)
  val () = tr12env_poplam0(env)
//
  val s2tx = S2TEXsub(s2v_a, s2ps)
  val () = tr12env_add0_s2tex(env, sym_nat, s2tx)
  val dcl_sortdef = d2ecl_make_node(loc, D2Csortdef(sym_nat, s2tx))
//
// (B) USE Nat as a SORT: stacst c : Nat.  Resolve the sort name `Nat` from the env (the s2tex
//     we just registered). On a subset sort the underlying sort is s2v_a.sort() = i0.
  val s2t_nat = the_sort2_int0  // the carrier sort of the subset (a : SInt)
  val sym_c = symbl_make_name("c")
  val s2c_c = s2cst_make_idst(loc, sym_c, s2t_nat)
  val () = tr12env_add1_s2cst(env, s2c_c)
  val dcl_stacst = d2ecl_make_node(loc, D2Cstacst0(s2c_c, s2t_nat))
//
  val decls = list_cons(dcl_sortdef, list_sing(dcl_stacst))
  val t2penv = tr12env_free_top(env)
in
  run_one("[SX-SUB] sortdef Nat={a:i0|a>=0} via S2TEXsub ; stacst c:Nat  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
fun
mymain_aquant((*void*)): void = let
//
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
//
  val () = PYB_log("######## A-QUANT STAGE-0 SPIKE (exi0 + S2TEXsub) ########")
//
  val sel = PYB_probe()
  val _ =
    (
      case+ sel of
      | 1 => let val () = PYB_log("---- PROBE SX-EXI (existential exi0) ----")
                 val _ = probe_SX_EXI() in 0 end
      | 2 => let val () = PYB_log("---- PROBE SX-SUB (subset sort S2TEXsub) ----")
                 val _ = probe_SX_SUB() in 0 end
      | _ => let val () = PYB_log("---- SX-EXI ----") val _ = probe_SX_EXI()
                 val () = PYB_log("---- SX-SUB ----") val _ = probe_SX_SUB()
              in 0 end
    ) : sint
in
  PYB_log("######## END A-QUANT SPIKE ########")
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_aquant()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_aquant_spike.dats]
*)
