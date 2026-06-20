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
| PCEapp(_, hd, args) => harv_explst(args, harv_exp(hd, acc))
| PCElam(_, _, _, body) => harv_exp(body, acc)
| PCElet(_, _, _, rhs, body) => harv_exp(body, harv_exp(rhs, acc))
| PCEletfun(_, fs, body) => harv_exp(body, harv_fundcls(fs, acc))
| PCEif(_, c, t, f) => harv_exp(f, harv_exp(t, harv_exp(c, acc)))
| PCEcase(_, scrut, arms) => harv_arms(arms, harv_exp(scrut, acc))
| PCEtup(_, es) => harv_explst(es, acc)
| PCErec(_, fs) => harv_efields(fs, acc)
| PCElist(_, es) => harv_explst(es, acc)
| PCEfield(_, e1, _) => harv_exp(e1, acc)
| PCEseq(_, e1, e2) => harv_exp(e2, harv_exp(e1, acc))
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
fun
harv_decl(d: pcdecl, acc: list(pcdiag)): list(pcdiag) =
(
case+ d of
| PCCerror(loc, msg) => list_append(acc, list_sing(PCDiag(loc, msg)))
| PCCfun(_, fs) => harv_fundcls(fs, acc)
| PCCval(_, _, e) => harv_exp(e, acc)
| PCCdata(_, _, _, _) => acc
| PCCstaload(_, _) => acc
| PCCalias(_, _, _, _) => acc  // a type/struct alias carries only a surface type — no poison nodes.
)
//
fun
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
| PCEerror(_, _) => false
| PCEapp(_, hd, args) => b_or(uses_exp(hd), uses_explst(args))
| PCElam(_, _, _, body) => uses_exp(body)
| PCElet(_, _, _, rhs, body) => b_or(uses_exp(rhs), uses_exp(body))
| PCEletfun(_, fs, body) => b_or(uses_fundcls(fs), uses_exp(body))
| PCEif(_, c, t, f) => b_or(uses_exp(c), b_or(uses_exp(t), uses_exp(f)))
| PCEcase(_, scrut, arms) => b_or(uses_exp(scrut), uses_arms(arms))
| PCEtup(_, es) => uses_explst(es)
| PCErec(_, fs) => uses_efields(fs)
| PCElist(_, es) => uses_explst(es)
| PCEfield(_, e1, _) => uses_exp(e1)
| PCEseq(_, e1, e2) => b_or(uses_exp(e1), uses_exp(e2))
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
| PCPcon(_, nm, args) => b_or(is_pyrt_name(nm), uses_patlst(args))
| PCPtup(_, ps0) => uses_patlst(ps0)
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
fun
uses_decl(d: pcdecl): bool =
(
case+ d of
| PCCfun(_, fs) => uses_fundcls(fs)
| PCCval(_, _, e) => uses_exp(e)
| _ => false
)
//
fun
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
