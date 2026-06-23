(* ****** ****** *)
(*
** M2.5 — Python-surface frontend: DIAGNOSTIC HARVEST + pyrt-usage scan (DATS).
**
** Two whole-PyCore walks used by the module driver:
**
**   harvest_decls : collect every PCEerror / PCCerror POISON node's (span, message) into
**                   a pcdiaglst. The elaborator emits poison nodes inline on misuse
**                   (reassign-immutable, break/continue outside a loop, return outside a
**                   function) rather than throwing; this walk surfaces them as the module's
**                   elaboration diagnostics, keeping the elaborator non-fail-fast + total.
**
**   uses_pyrt_decls : does the PyCore reference any pyrt name (a flow ctor, flow_bind,
**                   iter_open/iter_step/iter_done/iter_more, list_foldleft)? Drives the
**                   leading `staload pyrt` emission (LOOP-DESUGARING §9).
**
** Structure: each walk is one `fun ... and ...` worker group (the main recursor first,
** then helpers) + a thin `#implfun` SATS wrapper (M2 Δ3 — no `#implfun` heading a group).
**
** PURELY ADDITIVE; consumes pycore.sats / pyparsing.sats / pyelab.sats read-only.
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
//
#staload "./../SATS/pylexing.sats"
#staload "./../SATS/pyparsing.sats"
#staload "./../SATS/pycore.sats"
#staload "./../SATS/pyelab.sats"
//
(* ****** ****** *)
//
fun b_or(a: bool, b: bool): bool = if a then true else b
//
(* ****** ****** *)
//
// ---- HARVEST: collect poison-node messages (in order) ----------------------
//
fun
harv_exp(e: pcexp, acc: list(pcdiag)): list(pcdiag) =
(
case+ e of
| PCEerror(loc, msg) => list_append(acc, list_sing(PCDiag(loc, msg)))
| PCElit(_, _) => acc
| PCEvar(_, _) => acc
| PCEcon(_, _) => acc
| PCEunit(_) => acc
| PCEtop(_) => acc
| PCEapp(_, hd, args) => harv_explst(args, harv_exp(hd, acc))
| PCElam(_, _, _, _, body) => harv_exp(body, acc)
| PCElet(_, _, _, rhs, body) => harv_exp(body, harv_exp(rhs, acc))
| PCEvarcell(_, _, _, init, body) => harv_exp(body, harv_exp(init, acc))
| PCEassign(_, lv, rv) => harv_exp(rv, harv_exp(lv, acc))
| PCEletfun(_, fs, body) => harv_exp(body, harv_fundcls(fs, acc))
| PCEif(_, c, t, f) => harv_exp(f, harv_exp(t, harv_exp(c, acc)))
| PCEcase(_, scrut, arms) => harv_arms(arms, harv_exp(scrut, acc))
| PCEllazy(_, body) => harv_exp(body, acc)
| PCEtup(_, es) => harv_explst(es, acc)
| PCErec(_, fs) => harv_efields(fs, acc)
| PCElist(_, es) => harv_explst(es, acc)
| PCEfield(_, e1, _) => harv_exp(e1, acc)
| PCEseq(_, e1, e2) => harv_exp(e2, harv_exp(e1, acc))
// EXN: raise harvests its sub-expr; try harvests its body + the except arms.
| PCEraise(_, e1) => harv_exp(e1, acc)
| PCEtry(_, body, hs) => harv_arms(hs, harv_exp(body, acc))
// A-TEMPLATE: `@inst[types] e` harvests poison nodes of its instantiated inner expr.
| PCEinst(_, _, e1) => harv_exp(e1, acc)
| PCEsapp(_, _, e1) => harv_exp(e1, acc)
// SCOPING: a `where:` body harvests poison nodes of BOTH the body expr AND the where-decls.
| PCEwhere(_, body, ds) => harv_decls_go(ds, harv_exp(body, acc))
// B-LINEAR: &/!/move/swap harvest poison nodes of their operand sub-exprs.
| PCEaddr(_, lv) => harv_exp(lv, acc)
| PCEderef(_, p) => harv_exp(p, acc)
| PCEfold(_, p) => harv_exp(p, acc)
| PCEmove(_, lv, rv) => harv_exp(rv, harv_exp(lv, acc))
| PCEswap(_, lv, rv) => harv_exp(rv, harv_exp(lv, acc))
)
//
and
harv_explst(es: list(pcexp), acc: list(pcdiag)): list(pcdiag) =
(
case+ es of
| list_nil() => acc
| list_cons(e, rest) => harv_explst(rest, harv_exp(e, acc))
)
//
and
harv_efields(fs: list(pcefield), acc: list(pcdiag)): list(pcdiag) =
(
case+ fs of
| list_nil() => acc
| list_cons(PCEField(_, _, e), rest) => harv_efields(rest, harv_exp(e, acc))
)
//
and
harv_arms(arms: list(pcarm), acc: list(pcdiag)): list(pcdiag) =
(
case+ arms of
| list_nil() => acc
| list_cons(PCArm(_, _, gopt, body), rest) =>
    // harvest a poison node in the (preserved) guard too, then the body.
    let val acc1 = (case+ gopt of PCEGNone() => acc | PCEGSome(g) => harv_exp(g, acc))
    in harv_arms(rest, harv_exp(body, acc1)) end
)
//
and
harv_fundcls(fs: list(pcfundcl), acc: list(pcdiag)): list(pcdiag) =
(
case+ fs of
| list_nil() => acc
| list_cons(PCFundcl(_, _, _, _, _, body, _), rest) => harv_fundcls(rest, harv_exp(body, acc))
)
//
and
harv_decl(d: pcdecl, acc: list(pcdiag)): list(pcdiag) =
(
case+ d of
| PCCerror(loc, msg) => list_append(acc, list_sing(PCDiag(loc, msg)))
| PCCfun(_, _, _, fs) => harv_fundcls(fs, acc)
| PCCval(_, _, e) => harv_exp(e, acc)
| PCCdata(_, _, _, _, _) => acc
| PCCstaload(_, _) => acc
| PCCimport(_, _, _, _, _) => acc  // a USER import carries only a module path — no poison nodes.
| PCCinclude(_, _, _) => acc     // an include carries only a path — no poison nodes (the included file's are reported on ITS own check).
| PCCalias(_, _, _, _) => acc   // a type alias carries only a surface type — no poison nodes.
| PCCrecord(_, _, _, _, _) => acc // a struct record carries only field types — no poison nodes.
| PCCexcept(_, _, _) => acc      // EXN: an exception decl carries only arg types — no poison nodes.
| PCCabstype(_, _, _, _, _) => acc  // an abstract type carries only a name/params — no poison nodes.
| PCCassume(_, _, _, _) => acc   // an assume carries only a name/params + a surface type.
| PCCextern(_, _, _, _, _, _, _) => acc // an extern signature carries only types — no poison nodes.
| PCCimplement(_, _, _, _, _, _, _, body, _) => harv_exp(body, acc) // an implement BODY may carry poison nodes.
// A-TEMPLATE: a template decl's INLINE body (when present) may carry poison nodes; a bodyless one
// carries only its signature — no poison.
| PCCtempl(_, _, _, _, _, _, _, bodyopt) =>
    (case+ bodyopt of PCEGNone() => acc | PCEGSome(b) => harv_exp(b, acc))
| PCCoverload(_, _, _) => acc    // an overload carries only two bare names — no poison nodes.
| PCCsymalias(_, _, _, _) => acc // a symalias carries only two names + a precedence — no poison nodes.
| PCCsortdef(_, _, _) => acc     // a sortdef carries only two names — no poison nodes.
| PCCsortsub(_, _, _, _) => acc  // a subset sort carries a binder + raw guard types — no poison nodes.
| PCCstacst(_, _, _) => acc      // a stacst carries only a name + a sort ref — no poison nodes.
| PCCstadef(_, _, e) => harv_exp(e, acc) // a stadef BODY (an expr) may carry poison nodes.
| PCCprfun(_, _, PCFundcl(_, _, _, _, _, body, _)) => harv_exp(body, acc) // a prfun BODY may carry poison.
| PCCprval(_, _, _, e) => harv_exp(e, acc) // a prval RHS (an expr) may carry poison nodes.
| PCCpraxi(_, _, _, _, _) => acc // a praxi carries only a signature — no poison nodes.
// SCOPING: a `private` run harvests poison nodes of every private decl it carries.
| PCCprivate(_, ds) => harv_decls_go(ds, acc)
)
//
and
harv_decls_go(ds: list(pcdecl), acc: list(pcdiag)): list(pcdiag) =
(
case+ ds of
| list_nil() => acc
| list_cons(d, rest) => harv_decls_go(rest, harv_decl(d, acc))
)
//
(* ****** ****** *)
//
// ---- pyrt-usage scan -------------------------------------------------------
//
fun
is_pyrt_name(nm: strn): bool =
  b_or(strn_eq(nm, "flow_next"),
  b_or(strn_eq(nm, "flow_cont"),
  b_or(strn_eq(nm, "flow_break"),
  b_or(strn_eq(nm, "flow_return"),
  b_or(strn_eq(nm, "flow_bind"),
  b_or(strn_eq(nm, "iter_open"),
  b_or(strn_eq(nm, "iter_step"),
  b_or(strn_eq(nm, "iter_done"),
  b_or(strn_eq(nm, "iter_more"),
       strn_eq(nm, "list_foldleft"))))))))))
//
fun
uses_exp(e: pcexp): bool =
(
case+ e of
| PCEvar(_, nm) => is_pyrt_name(nm)
| PCEcon(_, nm) => is_pyrt_name(nm)
| PCElit(_, _) => false
| PCEunit(_) => false
| PCEtop(_) => false
| PCEerror(_, _) => false
| PCEapp(_, hd, args) => b_or(uses_exp(hd), uses_explst(args))
| PCElam(_, _, _, _, body) => uses_exp(body)
| PCElet(_, _, _, rhs, body) => b_or(uses_exp(rhs), uses_exp(body))
| PCEvarcell(_, _, _, init, body) => b_or(uses_exp(init), uses_exp(body))
| PCEassign(_, lv, rv) => b_or(uses_exp(lv), uses_exp(rv))
| PCEletfun(_, fs, body) => b_or(uses_fundcls(fs), uses_exp(body))
| PCEif(_, c, t, f) => b_or(uses_exp(c), b_or(uses_exp(t), uses_exp(f)))
| PCEcase(_, scrut, arms) => b_or(uses_exp(scrut), uses_arms(arms))
| PCEllazy(_, body) => uses_exp(body)
| PCEtup(_, es) => uses_explst(es)
| PCErec(_, fs) => uses_efields(fs)
| PCElist(_, es) => uses_explst(es)
| PCEfield(_, e1, _) => uses_exp(e1)
| PCEseq(_, e1, e2) => b_or(uses_exp(e1), uses_exp(e2))
// EXN: raise/try recurse into their sub-exprs / body + arms (no pyrt names of their own).
| PCEraise(_, e1) => uses_exp(e1)
| PCEtry(_, body, hs) => b_or(uses_exp(body), uses_arms(hs))
// A-TEMPLATE: `@inst[types] e` uses pyrt iff its inner expr does (the type-args name no pyrt fn).
| PCEinst(_, _, e1) => uses_exp(e1)
| PCEsapp(_, _, e1) => uses_exp(e1)
// SCOPING: a `where:` body uses pyrt iff the body OR any where-decl does.
| PCEwhere(_, body, ds) => b_or(uses_exp(body), uses_decls_go(ds))
// B-LINEAR: &/!/move/swap use pyrt iff an operand sub-expr does.
| PCEaddr(_, lv) => uses_exp(lv)
| PCEderef(_, p) => uses_exp(p)
| PCEfold(_, p) => uses_exp(p)
| PCEmove(_, lv, rv) => b_or(uses_exp(lv), uses_exp(rv))
| PCEswap(_, lv, rv) => b_or(uses_exp(lv), uses_exp(rv))
)
//
and
uses_explst(es: list(pcexp)): bool =
(
case+ es of
| list_nil() => false
| list_cons(e, rest) => b_or(uses_exp(e), uses_explst(rest))
)
//
and
uses_efields(fs: list(pcefield)): bool =
(
case+ fs of
| list_nil() => false
| list_cons(PCEField(_, _, e), rest) => b_or(uses_exp(e), uses_efields(rest))
)
//
and
uses_arms(arms: list(pcarm)): bool =
(
case+ arms of
| list_nil() => false
| list_cons(PCArm(_, p, gopt, body), rest) =>
    b_or(uses_pat(p),
    b_or((case+ gopt of PCEGNone() => false | PCEGSome(g) => uses_exp(g)),
    b_or(uses_exp(body), uses_arms(rest))))
)
//
and
uses_pat(p: pcpat): bool =
(
case+ p of
| PCPcon(_, nm, _, args) => b_or(is_pyrt_name(nm), uses_patlst(args))
| PCPtup(_, ps0) => uses_patlst(ps0)
| PCPas(_, _, inner) => uses_pat(inner)  // M7: recurse into the as-pattern's inner pattern
| PCPbang(_, inner) => uses_pat(inner)
| PCPflat(_, inner) => uses_pat(inner)
| _ => false
)
//
and
uses_patlst(ps0: list(pcpat)): bool =
(
case+ ps0 of
| list_nil() => false
| list_cons(p, rest) => b_or(uses_pat(p), uses_patlst(rest))
)
//
and
uses_fundcls(fs: list(pcfundcl)): bool =
(
case+ fs of
| list_nil() => false
| list_cons(PCFundcl(_, _, _, _, _, body, _), rest) => b_or(uses_exp(body), uses_fundcls(rest))
)
//
and
uses_decl(d: pcdecl): bool =
(
case+ d of
| PCCfun(_, _, _, fs) => uses_fundcls(fs)
| PCCval(_, _, e) => uses_exp(e)
// SCOPING: a `private` run uses pyrt iff any of its private decls does.
| PCCprivate(_, ds) => uses_decls_go(ds)
| _ => false
)
//
and
uses_decls_go(ds: list(pcdecl)): bool =
(
case+ ds of
| list_nil() => false
| list_cons(d, rest) => b_or(uses_decl(d), uses_decls_go(rest))
)
//
(* ****** ****** *)
//
#implfun harvest_decls(ds) = harv_decls_go(ds, list_nil())
#implfun uses_pyrt_decls(ds) = uses_decls_go(ds)
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyelab_diag.dats]
*)
