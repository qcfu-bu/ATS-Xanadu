(* ****** ****** *)
(*
** M5b.4/.5 GATING SPIKE driver — proves (or characterizes the blocker for)
** DIRECT-L2 construction of:
**   (.5) a TYPE ALIAS  `type X = <rhs>`  -> a `D2Csexpdef(s2cst, rhs)` node
**   (.4) a STRUCT/RECORD type             -> a `D2Csexpdef(Point, S2Etrcd(...))`
**
** Both lower to `D2Csexpdef`. `struct` additionally needs the record s2exp
** `S2Etrcd`. NEITHER is proven at direct-L2 construction, and there is a KNOWN
** hazard: aliasing a surface type to the prelude `int` SEXPDEF chain crashed
** `unify00_s2typ` (the M5a finding). A USER `D2Csexpdef` IS exactly a sexpdef,
** so the hazard probe (B) is make-or-break for `type X = <primitive>`.
**
** PROBES (each is an INDEPENDENT d2parsed run through trans2a/trsym2b/t2read0/
** trans23/tread3a; we report nerror after tread3a for EACH):
**
**   A  type Ints = list(int)        + def f(xs: Ints) -> Int: 0
**        (alias to a datatype application)
**   B  type MyInt = int             + def g(n: MyInt) -> Int: n      [HAZARD]
**        (alias to a PRIMITIVE; forces unify of MyInt against int)
**   C  Point = $rcd{ x:int, y:int } + def h(p: Point) -> Int: p.x
**        (named record type + field PROJECTION through the alias)
**   C2 (same Point)                 + def h2(p: Point) -> Point: p   [annot-only]
**        (isolates whether the RECORD TYPE itself is fine vs the projection)
**
** RECIPE MIRRORED FROM (cited):
**   trans12_decl00.dats f0_sexpdef (1329-1466):
**     s2t2 = sdef.sort() ; sid1 = sexpid_sym(tok1) ; tdef = s2exp_stpize(sdef)
**     s2c1 = s2cst_make_idst(loc0, sid1, s2t2)
**     s2cst_set_sexp(s2c1, sdef) ; s2cst_set_styp(s2c1, tdef)
**     D2Csexpdef(s2c1, sdef) ; tr12env_add1_s2cst(env0, s2c1)
**   staexp2.dats s2exp_r1cd (1515-1615): boxed non-linear record =
**     s2exp_make_node(the_sort2_tbox, S2Etrcd(TRCDbox0, -1(*npf*), lses))
**     where lses : l2s2elst = list( S2LAB(LABsym(sym), s2exp) ).
**   pylower_dynexp.dats PCEfield (479-488): e.name -> D2Eproj(tok, d2rxp_new1,
**     LABsym(sym name), e).
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
// L1 AST makers s1exp_none0 (staexp1) is NOT in libxatsopt.hats; staload it for the
// `given` slot of a D2Pannot binder, exactly as the M5b enum spike does.
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
// resolve a (prelude) static type NAME to its s2exp, exactly as pylower_staexp.dats
// resolve_typ does. We use it to obtain the prelude `list` type-constructor s2cst (for
// the `list(int)` application in probe A), the `int` sexpdef (for probe B's HAZARD
// alias-to-primitive), and `the_s2exp_sint0` (the M5a direct-T2Pcst Int for literals/
// return-annotations).
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
// resolve a bound dynamic VARIABLE by name to a D2Evar reference. Used for `n` (probe B)
// and `p` (probe C2) bodies. The name is guaranteed bound at the call site.
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
// THE CORE HELPER (mirrors f0_sexpdef @ trans12_decl00.dats:1434-1464): build a
// `D2Csexpdef` aliasing `name` to the s2exp `sdef`, register the s2cst in the env, and
// return (the new s2cst, the decl). The new s2cst's `sexp`/`styp` are wired so a later
// USE of the alias unfolds to `sdef`.
//
fun
build_sexpdef
  (env: !tr12env, loc: loctn, name: strn, sdef: s2exp): @(s2cst, d2ecl) = let
  val s2t2 = sdef.sort()                 // the alias inherits the RHS's sort
  val sid1 = symbl_make_name(name)
  val tdef = s2exp_stpize(sdef)          // the erased/styp form (f0_sexpdef tdef)
  val s2c1 = s2cst_make_idst(loc, sid1, s2t2)
  val () = s2cst_set_sexp(s2c1, sdef)
  val () = s2cst_set_styp(s2c1, tdef)
  val () = tr12env_add1_s2cst(env, s2c1)
  val dcl = d2ecl_make_node(loc, D2Csexpdef(s2c1, sdef))
in
  @(s2c1, dcl)
end
//
(* ****** ****** *)
//
// build a one-arg function decl `def NAME(param: PTYP) -> RTYP: BODY` where BODY is
// produced by the callback `mkbody` after the param has been bound into a fresh lam
// scope (so the body may resolve the param by name). Mirrors the enum spike's fun build.
//
fun
build_fun1
  ( env: !tr12env, loc: loctn
  , fname: strn, pname: strn, ptyp: s2exp, rtyp: s2exp
  , mkbody: (!tr12env, loctn) -<cloptr1> d2exp ): d2ecl = let
//
  val sym_f = symbl_make_name(fname)
  val d2v_f = d2var_new2_name(loc, sym_f)
  val () = tr12env_add0_d2var(env, d2v_f)
//
  val d2v_p = d2var_new2_name(loc, symbl_make_name(pname))
  val pat_p = d2pat_var(loc, d2v_p)
  val pat_p_annot = d2pat_make_node(loc, D2Pannot(pat_p, s1exp_none0(loc), ptyp))
  val f2as = list_sing(f2arg_make_node(loc, F2ARGdapp(0(*npf*), list_sing(pat_p_annot))))
//
  val sres = S2RESsome(S2EFFnone(), rtyp)
//
  val () = tr12env_pshlam0(env)
  val () = tr12env_add0_f2arglst(env, f2as)
  val d2body = mkbody(env, loc)
  val () = tr12env_poplam0(env)
//
  val tok_val = token_make_node(loc, T_VAL(VLKval))
  val tok_fun = token_make_node(loc, T_FUN(FNKfn2))
//
  val d2f =
    d2fundcl_make_args
      (loc, d2v_f, f2as, sres, TEQD2EXPsome(tok_val, d2body), WTHS2EXPnone())
in
  d2ecl_make_node
    (loc, D2Cfundclst(tok_fun, list_nil()(*tqas*), list_nil()(*d2cs*), list_sing(d2f)))
end
//
(* ****** ****** *)
//
// run ONE d2parsed (one decl list) through the full L2->L3 pipeline and return the
// post-tread3a nerror. EACH probe builds its own fresh env + d2parsed and calls this.
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
// ===== PROBE A : type Ints = list(int) ; def f(xs: Ints) -> Int: 0 ============
//
fun
probe_A((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  // resolve `list` (a datatype tycon) and `int` (the prelude sexpdef).
  val s2e_list = resolve_typ_name(env, "list")
  val s2e_int  = resolve_typ_name(env, "int")
  // Int (for the return annotation / literal) = the M5a direct T2Pcst.
  val s2e_Int  = resolve_typ_name(env, "the_s2exp_sint0")
//
  // build `list(int)` via s2exp_apps.
  val s2e_rhs = s2exp_apps(loc, s2e_list, list_sing(s2e_int))
//
  // the alias `type Ints = list(int)`.
  val @(s2c_ints, dcl_alias) = build_sexpdef(env, loc, "Ints", s2e_rhs)
  val s2e_ints = s2exp_cst(s2c_ints)
//
  // def f(xs: Ints) -> Int: 0
  val dcl_f =
    build_fun1
      ( env, loc, "f", "xs", s2e_ints, s2e_Int
      , lam (env, loc) =<cloptr1>
          d2exp_make_node(loc, D2Eint(token_make_node(loc, T_INT01("0")))) )
//
  val decls = list_cons(dcl_alias, list_sing(dcl_f))
  val t2penv = tr12env_free_top(env)
in
  run_one("[A] type Ints=list(int) ; f(xs:Ints)->Int:0  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE B : type MyInt = int ; def g(n: MyInt) -> Int: n  [HAZARD] ========
//
fun
probe_B((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  // the HAZARD RHS: the prelude `int` SEXPDEF (NOT the_s2exp_sint0). This is exactly
  // the sexpdef chain that crashed unify00_s2typ in the M5a finding.
  val s2e_int = resolve_typ_name(env, "int")
  val s2e_Int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val @(s2c_myint, dcl_alias) = build_sexpdef(env, loc, "MyInt", s2e_int)
  val s2e_myint = s2exp_cst(s2c_myint)
//
  // def g(n: MyInt) -> Int: n   — forces unify of MyInt (sexpdef->int) against Int.
  val dcl_g =
    build_fun1
      ( env, loc, "g", "n", s2e_myint, s2e_Int
      , lam (env, loc) =<cloptr1> resolve_var(env, loc, "n") )
//
  val decls = list_cons(dcl_alias, list_sing(dcl_g))
  val t2penv = tr12env_free_top(env)
in
  run_one("[B] type MyInt=int ; g(n:MyInt)->Int:n  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// ===== PROBE B' : the M5a MITIGATION variant — alias to the DIRECT T2Pcst =====
// (only meaningful if B fails: alias MyInt2 -> the_s2exp_sint0 instead of the int
//  sexpdef, then g2(n:MyInt2)->Int:n. Reported alongside B.)
//
fun
probe_Bp((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
  val s2e_Int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val @(s2c_myint, dcl_alias) = build_sexpdef(env, loc, "MyInt2", s2e_Int)
  val s2e_myint = s2exp_cst(s2c_myint)
//
  val dcl_g =
    build_fun1
      ( env, loc, "g2", "n", s2e_myint, s2e_Int
      , lam (env, loc) =<cloptr1> resolve_var(env, loc, "n") )
//
  val decls = list_cons(dcl_alias, list_sing(dcl_g))
  val t2penv = tr12env_free_top(env)
in
  run_one("[B'] type MyInt2=the_s2exp_sint0 ; g2(n)->Int:n  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
// build the boxed record s2exp `$rcd{ x:int, y:int }` =
//   s2exp_make_node(the_sort2_tbox, S2Etrcd(TRCDbox0, -1, [x:int, y:int]))
// label = S2LAB(LABsym(sym name), s2exp). Mirrors s2exp_r1cd's boxed-nonlinear arm.
//
fun
build_point_rcd(s2e_int: s2exp): s2exp = let
  val lab_x = LABsym(symbl_make_name("x"))
  val lab_y = LABsym(symbl_make_name("y"))
  val fld_x = S2LAB(lab_x, s2e_int)
  val fld_y = S2LAB(lab_y, s2e_int)
  val flds  = list_cons(fld_x, list_sing(fld_y))
in
  s2exp_make_node(the_sort2_tbox, S2Etrcd(TRCDbox0, (-1)(*npf*), flds))
end
//
// ===== PROBE C : Point=$rcd{x:int,y:int} ; def h(p: Point) -> Int: p.x =========
//
fun
probe_C((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val s2e_int = resolve_typ_name(env, "int")
  val s2e_Int = resolve_typ_name(env, "the_s2exp_sint0")
//
  val s2e_rcd = build_point_rcd(s2e_int)
  val @(s2c_point, dcl_alias) = build_sexpdef(env, loc, "Point", s2e_rcd)
  val s2e_point = s2exp_cst(s2c_point)
//
  // def h(p: Point) -> Int: p.x   — PROJECT field x through the alias.
  val dcl_h =
    build_fun1
      ( env, loc, "h", "p", s2e_point, s2e_Int
      , lam (env, loc) =<cloptr1> let
          val d2p = resolve_var(env, loc, "p")
          val drxp = d2rxp_new1(loc)
          val lab  = LABsym(symbl_make_name("x"))
        in
          d2exp_make_node(loc, D2Eproj(token_make_node(loc, T_VAL(VLKval)), drxp, lab, d2p))
        end )
//
  val decls = list_cons(dcl_alias, list_sing(dcl_h))
  val t2penv = tr12env_free_top(env)
in
  run_one("[C] Point=$rcd{x,y} ; h(p:Point)->Int:p.x  nerror=", decls, t2penv)
end
//
(* ====== PROBE C2 : annotation-only (no projection) — isolates the record type == *)
//
fun
probe_C2((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val s2e_int = resolve_typ_name(env, "int")
  val s2e_rcd = build_point_rcd(s2e_int)
  val @(s2c_point, dcl_alias) = build_sexpdef(env, loc, "Point", s2e_rcd)
  val s2e_point = s2exp_cst(s2c_point)
//
  // def h2(p: Point) -> Point: p   — annotation only; body is the param.
  val dcl_h2 =
    build_fun1
      ( env, loc, "h2", "p", s2e_point, s2e_point
      , lam (env, loc) =<cloptr1> resolve_var(env, loc, "p") )
//
  val decls = list_cons(dcl_alias, list_sing(dcl_h2))
  val t2penv = tr12env_free_top(env)
in
  run_one("[C2] Point=$rcd ; h2(p:Point)->Point:p (annot-only)  nerror=", decls, t2penv)
end
//
(* ====== PROBE C3 : MITIGATED record — fields = the_s2exp_sint0 (direct T2Pcst),
   annotation-only. If C2 crashes but C3 passes, the struct hazard is the SAME M5a
   sexpdef-field issue and the SAME mitigation (direct T2Pcst fields) fixes it. ==== *)
//
fun
probe_C3((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val s2e_Int = resolve_typ_name(env, "the_s2exp_sint0")
  val s2e_rcd = build_point_rcd(s2e_Int)   // fields are the DIRECT T2Pcst Int
  val @(s2c_point, dcl_alias) = build_sexpdef(env, loc, "PointI", s2e_rcd)
  val s2e_point = s2exp_cst(s2c_point)
//
  val dcl_h3 =
    build_fun1
      ( env, loc, "h3", "p", s2e_point, s2e_point
      , lam (env, loc) =<cloptr1> resolve_var(env, loc, "p") )
//
  val decls = list_cons(dcl_alias, list_sing(dcl_h3))
  val t2penv = tr12env_free_top(env)
in
  run_one("[C3] PointI=$rcd{the_s2exp_sint0} ; h3(p)->PointI:p (annot)  nerror=", decls, t2penv)
end
//
(* ====== PROBE C4 : MITIGATED record + field PROJECTION. h4(p:PointI)->Int: p.x === *)
//
fun
probe_C4((*void*)): sint = let
  val loc = loctn_dummy()
  val env = tr12env_make_nil()
//
  val s2e_Int = resolve_typ_name(env, "the_s2exp_sint0")
  val s2e_rcd = build_point_rcd(s2e_Int)
  val @(s2c_point, dcl_alias) = build_sexpdef(env, loc, "PointI", s2e_rcd)
  val s2e_point = s2exp_cst(s2c_point)
//
  val dcl_h4 =
    build_fun1
      ( env, loc, "h4", "p", s2e_point, s2e_Int
      , lam (env, loc) =<cloptr1> let
          val d2p = resolve_var(env, loc, "p")
          val drxp = d2rxp_new1(loc)
          val lab  = LABsym(symbl_make_name("x"))
        in
          d2exp_make_node(loc, D2Eproj(token_make_node(loc, T_VAL(VLKval)), drxp, lab, d2p))
        end )
//
  val decls = list_cons(dcl_alias, list_sing(dcl_h4))
  val t2penv = tr12env_free_top(env)
in
  run_one("[C4] PointI=$rcd{T2Pcst} ; h4(p:PointI)->Int:p.x  nerror=", decls, t2penv)
end
//
(* ****** ****** *)
//
fun
mymain_m5b45((*void*)): void = let
//
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
//
  val () = PYB_log("######## M5b.4/.5 sexpdef + S2Etrcd GATING SPIKE ########")
//
  // each probe runs in its OWN node process (selected by PYB_probe / PROBE env)
  // so a hard XATS000_cfail in one (the HAZARD) does NOT mask the others.
  val sel = PYB_probe()
  val _ =
    (
      case+ sel of
      | 1 => let val () = PYB_log("---- PROBE A (alias to datatype-app) ----")
                 val _ = probe_A() in 0 end
      | 2 => let val () = PYB_log("---- PROBE B (alias to PRIMITIVE — the HAZARD) ----")
                 val _ = probe_B() in 0 end
      | 3 => let val () = PYB_log("---- PROBE B' (M5a mitigation: alias to direct T2Pcst) ----")
                 val _ = probe_Bp() in 0 end
      | 4 => let val () = PYB_log("---- PROBE C2 (record annotation-only) ----")
                 val _ = probe_C2() in 0 end
      | 5 => let val () = PYB_log("---- PROBE C (record + field projection) ----")
                 val _ = probe_C() in 0 end
      | 6 => let val () = PYB_log("---- PROBE C3 (MITIGATED record, annot-only) ----")
                 val _ = probe_C3() in 0 end
      | 7 => let val () = PYB_log("---- PROBE C4 (MITIGATED record + projection) ----")
                 val _ = probe_C4() in 0 end
      | _ => let // ALL (best-effort; a crash here aborts the rest — use per-probe runs)
                 val () = PYB_log("---- PROBE A ----")  val _ = probe_A()
                 val () = PYB_log("---- PROBE B' ----") val _ = probe_Bp()
                 val () = PYB_log("---- PROBE C2 ----") val _ = probe_C2()
                 val () = PYB_log("---- PROBE C ----")  val _ = probe_C()
                 val () = PYB_log("---- PROBE B (HAZARD; may crash) ----") val _ = probe_B()
              in 0 end
    ) : sint
in
  PYB_log("######## END M5b.4/.5 SPIKE ########")
end
//
(* ****** ****** *)
//
val ((*entry*)) = mymain_m5b45()
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyfront_m5b45_spike.dats]
*)
