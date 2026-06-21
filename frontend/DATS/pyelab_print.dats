(* ****** ****** *)
(*
** M2.5 — Python-surface frontend: the PyCore PRETTY-PRINTER (DATS).
**
** Dumps a `pcmodule` (and every sub-node) in an S-expression-ish form with `@span`
** on every node — the same format as the PyAST printer (pyparsing_print.dats), so the
** §10 golden desugarings are diffable and spans are directly comparable. A real `loctn`
** flows into every PyCore node (LOOP-DESUGARING §9); synthesized binders (the `loop`
** name) print a dummy span so the goldens SHOW where the surface origin is/ isn't.
**
** STRUCTURE (ATS3 dialect): mutually-recursive workers `pp_*`; the SATS entries are thin
** `#implfun` wrappers at the end (mixing `#implfun` into an `and`-group with non-impl
** helpers leaves the helper unresolved — M2 trap Δ3).
**
** PURELY ADDITIVE; consumes pycore.sats / pyparsing.sats / locinfo.sats read-only.
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
//
(* ****** ****** *)
//
fun ps(out: FILR, s: strn): void = strn_fprint(s, out)
fun pi(out: FILR, n: sint): void = gint_fprint$sint(n, out)
//
fun
print_span(out: FILR, loc: loctn): void = let
  val pb = loc.pbeg()
  val pe = loc.pend()
in
  ps(out, "@(");
  pi(out, pb.nrow()); ps(out, ":"); pi(out, pb.ncol());
  ps(out, "-");
  pi(out, pe.nrow()); ps(out, ":"); pi(out, pe.ncol());
  ps(out, ")")
end
//
fun
print_indent(out: FILR, n: sint): void =
  if n <= 0 then () else (ps(out, "  "); print_indent(out, n - 1))
//
fun nl(out: FILR): void = ps(out, "\n")
//
(* ****** ****** *)
//
fun
pp_lit(out: FILR, lit: pclit): void =
(
case+ lit of
| PCLint(loc, s)  => (ps(out, "(int "); ps(out, s); print_span(out, loc); ps(out, ")"))
| PCLflt(loc, s)  => (ps(out, "(flt "); ps(out, s); print_span(out, loc); ps(out, ")"))
| PCLstr(loc, s)  => (ps(out, "(str "); ps(out, s); print_span(out, loc); ps(out, ")"))
| PCLchr(loc, s)  => (ps(out, "(chr "); ps(out, s); print_span(out, loc); ps(out, ")"))
| PCLbool(loc, b) =>
  ( ps(out, "(bool "); ps(out, (if b then "true" else "false"));
    print_span(out, loc); ps(out, ")") )
)
//
fun
pp_strlst(out: FILR, xs: list(strn)): void =
(
case+ xs of
| list_nil() => ()
| list_cons(x, rest) => (ps(out, " "); ps(out, x); pp_strlst(out, rest))
)
//
// M5b.6b: render a type-param list `A`, or `A:Linear` / `A@unboxed` when annotated, so a golden
// can SEE the sort the param carries (a plain `[A]` still prints as just `A` — unchanged).
fun
pp_pcparams(out: FILR, ps0: list(pcparam)): void =
(
case+ ps0 of
| list_nil() => ()
| list_cons(PCParam(_, nm, sname, unboxed), rest) =>
  ( ps(out, " "); ps(out, nm);
    ( if strn_eq(sname, "") then () else (ps(out, ":"); ps(out, sname)) );
    ( if unboxed then ps(out, "@unboxed") else () );
    pp_pcparams(out, rest) )
)
//
(* ****** ****** *)
//
// ---- type printer (reuse the PyAST surface-type printer; PyCore keeps surface types) --
//
fun
pp_typ(out: FILR, t: pytyp): void = pytyp_fprint(out, t)
//
fun
pp_typlst(out: FILR, ts: list(pytyp)): void =
(
case+ ts of
| list_nil() => ()
| list_cons(t, rest) => (ps(out, " "); pp_typ(out, t); pp_typlst(out, rest))
)
//
(* ****** ****** *)
//
// M5a: print a param list with each param's OPTIONAL type annotation (the two lists are
// parallel; the type list may be SHORTER/empty, in which case remaining params are untyped).
// An unannotated param prints as just its name (identical to pp_strlst, so untyped goldens
// are unchanged); a typed one as `name:T`, PROVING the carried annotation in the golden.
//
fun
pp_one_pann(out: FILR, x: strn, topt: pytypopt): void =
(
case+ topt of
| PyTypNone() => (ps(out, " "); ps(out, x))
| PyTypSome(t) => (ps(out, " "); ps(out, x); ps(out, ":"); pp_typ(out, t))
)
//
fun
pp_params_typed(out: FILR, xs: list(strn), ts: list(pytypopt)): void =
(
case+ xs of
| list_nil() => ()
| list_cons(x, xrest) =>
  (
  case+ ts of
  | list_cons(topt, trest) => (pp_one_pann(out, x, topt); pp_params_typed(out, xrest, trest))
  | list_nil() => (ps(out, " "); ps(out, x); pp_params_typed(out, xrest, list_nil()))
  )
)
//
// M5a: print an OPTIONAL return type as ` -> T` (nothing when absent).
fun
pp_retopt(out: FILR, ret: pytypopt): void =
(
case+ ret of
| PyTypNone() => ()
| PyTypSome(t) => (ps(out, " -> "); pp_typ(out, t))
)
//
// M5a: print an OPTIONAL binding annotation as `:T` (nothing when absent).
fun
pp_anncolon(out: FILR, ann: pytypopt): void =
(
case+ ann of
| PyTypNone() => ()
| PyTypSome(t) => (ps(out, ":"); pp_typ(out, t))
)
//
(* ****** ****** *)
//
// ---- PATTERN printers ------------------------------------------------------
//
fun
pp_pat(out: FILR, p: pcpat): void =
(
case+ p of
| PCPvar(loc, nm) =>
  (ps(out, "(Pvar "); ps(out, nm); print_span(out, loc); ps(out, ")"))
| PCPwild(loc) =>
  (ps(out, "(Pwild"); print_span(out, loc); ps(out, ")"))
| PCPcon(loc, nm, args) =>
  ( ps(out, "(Pcon "); ps(out, nm); print_span(out, loc);
    pp_patlst(out, args); ps(out, ")") )
| PCPtup(loc, ps0) =>
  (ps(out, "(Ptup"); print_span(out, loc); pp_patlst(out, ps0); ps(out, ")"))
| PCPrec(loc, fs) =>
  (ps(out, "(Prec"); print_span(out, loc); pp_pfields(out, fs); ps(out, ")"))
| PCPlit(loc, lit) =>
  (ps(out, "(Plit"); print_span(out, loc); ps(out, " "); pp_lit(out, lit); ps(out, ")"))
| PCPas(loc, nm, inner) =>
  ( ps(out, "(Pas "); ps(out, nm); print_span(out, loc);
    ps(out, " "); pp_pat(out, inner); ps(out, ")") )
)
//
and
pp_patlst(out: FILR, ps0: list(pcpat)): void =
(
case+ ps0 of
| list_nil() => ()
| list_cons(p, rest) => (ps(out, " "); pp_pat(out, p); pp_patlst(out, rest))
)
//
and
pp_pfields(out: FILR, fs: list(pcpfield)): void =
(
case+ fs of
| list_nil() => ()
| list_cons(PCPField(loc, nm, p), rest) =>
  ( ps(out, " ("); ps(out, nm); ps(out, " = "); pp_pat(out, p); ps(out, ")");
    pp_pfields(out, rest) )
)
//
(* ****** ****** *)
//
// ---- EXPRESSION printers (one big mutually-recursive group; exprs contain fun-groups
//      whose members contain exprs, arms contain exprs, etc.) ----
//
fun
pp_exp(out: FILR, e: pcexp, ind: sint): void =
(
case+ e of
| PCElit(loc, lit) =>
  (ps(out, "(Elit"); print_span(out, loc); ps(out, " "); pp_lit(out, lit); ps(out, ")"))
| PCEvar(loc, nm) =>
  (ps(out, "(Evar "); ps(out, nm); print_span(out, loc); ps(out, ")"))
| PCEcon(loc, nm) =>
  (ps(out, "(Econ "); ps(out, nm); print_span(out, loc); ps(out, ")"))
| PCEapp(loc, hd, args) =>
  ( ps(out, "(Eapp"); print_span(out, loc); ps(out, " ");
    pp_exp(out, hd, ind); ps(out, " (args"); pp_explst(out, args, ind); ps(out, "))") )
| PCElam(loc, is_func, ps0, ptypes, body) =>
  ( ps(out, "(Elam"); (if is_func then ps(out, "@func") else ()); print_span(out, loc);
    ps(out, " (params"); pp_params_typed(out, ps0, ptypes);
    ps(out, ") "); pp_exp(out, body, ind); ps(out, ")") )
| PCElet(loc, p, ann, rhs, body) =>
  ( ps(out, "(Elet"); print_span(out, loc); ps(out, " ");
    pp_pat(out, p); pp_anncolon(out, ann); ps(out, " = "); pp_exp(out, rhs, ind);
    nl(out); print_indent(out, ind + 1); ps(out, "in ");
    pp_exp(out, body, ind + 1); ps(out, ")") )
| PCEvarcell(loc, nm, ann, init, body) =>
  ( ps(out, "(Evarcell"); print_span(out, loc); ps(out, " "); ps(out, nm);
    pp_anncolon(out, ann); ps(out, " := "); pp_exp(out, init, ind);
    nl(out); print_indent(out, ind + 1); ps(out, "in ");
    pp_exp(out, body, ind + 1); ps(out, ")") )
| PCEassign(loc, lv, rv) =>
  ( ps(out, "(Eassign"); print_span(out, loc); ps(out, " ");
    pp_exp(out, lv, ind); ps(out, " := "); pp_exp(out, rv, ind); ps(out, ")") )
| PCEletfun(loc, fs, body) =>
  ( ps(out, "(Eletfun"); print_span(out, loc);
    pp_fundclst(out, fs, ind + 1);
    nl(out); print_indent(out, ind + 1); ps(out, "in ");
    pp_exp(out, body, ind + 1); ps(out, ")") )
| PCEif(loc, c, t, f) =>
  ( ps(out, "(Eif"); print_span(out, loc); ps(out, " ");
    pp_exp(out, c, ind);
    nl(out); print_indent(out, ind + 1); ps(out, "then "); pp_exp(out, t, ind + 1);
    nl(out); print_indent(out, ind + 1); ps(out, "else "); pp_exp(out, f, ind + 1);
    ps(out, ")") )
| PCEcase(loc, scrut, arms) =>
  ( ps(out, "(Ecase"); print_span(out, loc); ps(out, " ");
    pp_exp(out, scrut, ind); pp_armlst(out, arms, ind + 1); ps(out, ")") )
| PCEtup(loc, es) =>
  (ps(out, "(Etup"); print_span(out, loc); pp_explst(out, es, ind); ps(out, ")"))
| PCErec(loc, fs) =>
  (ps(out, "(Erec"); print_span(out, loc); pp_efields(out, fs, ind); ps(out, ")"))
| PCElist(loc, es) =>
  (ps(out, "(Elist"); print_span(out, loc); pp_explst(out, es, ind); ps(out, ")"))
| PCEfield(loc, e1, nm) =>
  ( ps(out, "(Efield "); ps(out, nm); print_span(out, loc); ps(out, " ");
    pp_exp(out, e1, ind); ps(out, ")") )
| PCEseq(loc, e1, e2) =>
  ( ps(out, "(Eseq"); print_span(out, loc); ps(out, " ");
    pp_exp(out, e1, ind);
    nl(out); print_indent(out, ind + 1); ps(out, "; ");
    pp_exp(out, e2, ind + 1); ps(out, ")") )
| PCEunit(loc) =>
  (ps(out, "(Eunit"); print_span(out, loc); ps(out, ")"))
| PCEraise(loc, e1) =>
  ( ps(out, "(Eraise"); print_span(out, loc); ps(out, " "); pp_exp(out, e1, ind); ps(out, ")") )
| PCEtry(loc, body, hs) =>
  ( ps(out, "(Etry"); print_span(out, loc); ps(out, " ");
    pp_exp(out, body, ind); pp_armlst(out, hs, ind + 1); ps(out, ")") )
// A-TEMPLATE: `@inst[types] e` -> the type-arg list + the instantiated inner expr.
| PCEinst(loc, ts, e1) =>
  ( ps(out, "(Einst"); print_span(out, loc); ps(out, " [types");
    pp_typlst(out, ts); ps(out, "] "); pp_exp(out, e1, ind); ps(out, ")") )
| PCEerror(loc, msg) =>
  (ps(out, "(Eerror \""); ps(out, msg); ps(out, "\""); print_span(out, loc); ps(out, ")"))
)
//
and
pp_explst(out: FILR, es: list(pcexp), ind: sint): void =
(
case+ es of
| list_nil() => ()
| list_cons(e, rest) => (ps(out, " "); pp_exp(out, e, ind); pp_explst(out, rest, ind))
)
//
and
pp_efields(out: FILR, fs: list(pcefield), ind: sint): void =
(
case+ fs of
| list_nil() => ()
| list_cons(PCEField(loc, nm, e), rest) =>
  ( ps(out, " ("); ps(out, nm); ps(out, " = "); pp_exp(out, e, ind); ps(out, ")");
    pp_efields(out, rest, ind) )
)
//
and
pp_armlst(out: FILR, arms: list(pcarm), ind: sint): void =
(
case+ arms of
| list_nil() => ()
| list_cons(PCArm(loc, p, gopt, body), rest) =>
  ( nl(out); print_indent(out, ind); ps(out, "(arm");
    print_span(out, loc); ps(out, " "); pp_pat(out, p);
    // PRESERVED surface guard (architect ruling iv): print it as `if <g>` so the golden
    // PROVES the guard survives in PyCore (it is NOT desugared to an inner `if`).
    ( case+ gopt of
      | PCEGNone() => ()
      | PCEGSome(g) => (ps(out, " if "); pp_exp(out, g, ind + 1)) );
    ps(out, " => ");
    pp_exp(out, body, ind + 1); ps(out, ")");
    pp_armlst(out, rest, ind) )
)
//
and
pp_fundclst(out: FILR, fs: list(pcfundcl), ind: sint): void =
(
case+ fs of
| list_nil() => ()
| list_cons(PCFundcl(loc, nm, params, ptypes, ret, body, isloop), rest) =>
  ( nl(out); print_indent(out, ind);
    ps(out, (if isloop then "(loop " else "(fun "));
    ps(out, nm); print_span(out, loc);
    ps(out, " (params"); pp_params_typed(out, params, ptypes); ps(out, ")");
    pp_retopt(out, ret); ps(out, " = ");
    pp_exp(out, body, ind + 1); ps(out, ")");
    pp_fundclst(out, rest, ind) )
)
//
(* ****** ****** *)
//
// ---- DECL printers ---------------------------------------------------------
//
fun
pp_datacon(out: FILR, dc: pcdatacon): void =
let val+ PCDataCon(loc, nm, ts) = dc in
  ps(out, "(con "); ps(out, nm); print_span(out, loc); pp_typlst(out, ts); ps(out, ")")
end
//
fun
pp_dataconlst(out: FILR, dcs: list(pcdatacon), ind: sint): void =
(
case+ dcs of
| list_nil() => ()
| list_cons(dc, rest) =>
  ( nl(out); print_indent(out, ind); pp_datacon(out, dc);
    pp_dataconlst(out, rest, ind) )
)
//
// M5b.6a: render the memory/representation MODE word so a golden/dump PROVES the decorator was
// honored (nerror=0 alone can't distinguish modes — linearity is erased downstream).
fun
pp_mode(out: FILR, m: pcmode): void =
(
case+ m of
| PCMbox()  => ps(out, "boxed")
| PCMlin()  => ps(out, "linear")
| PCMflat() => ps(out, "flat")
| PCMprop() => ps(out, "prop")
| PCMview() => ps(out, "view")
)
//
// M5b.6a: render a struct record-field list `(field name <typ>) ...`.
fun
pp_pcfields(out: FILR, fs: list(pcfield)): void =
(
case+ fs of
| list_nil() => ()
| list_cons(PCField(loc, nm, t), rest) =>
  ( ps(out, " (field "); ps(out, nm); print_span(out, loc); ps(out, " ");
    pp_typ(out, t); ps(out, ")"); pp_pcfields(out, rest) )
)
//
// print a list of bare names (extern param names).
fun
pp_strnlst(out: FILR, ns: list(strn)): void =
(
case+ ns of
| list_nil() => ()
| list_cons(n, rest) => (ps(out, " "); ps(out, n); pp_strnlst(out, rest))
)
//
fun
pp_decl(out: FILR, d: pcdecl, ind: sint): void =
(
nl(out); print_indent(out, ind);
case+ d of
| PCCdata(loc, nm, tvs, dcs, mode) =>
  ( ps(out, "(data "); ps(out, nm); print_span(out, loc);
    ( case+ tvs of list_nil() => () | _ => (ps(out, " (tvs"); pp_pcparams(out, tvs); ps(out, ")")) );
    ps(out, " mode="); pp_mode(out, mode);
    pp_dataconlst(out, dcs, ind + 1); ps(out, ")") )
| PCCrecord(loc, nm, tvs, fields, mode) =>
  ( ps(out, "(record "); ps(out, nm); print_span(out, loc);
    ( case+ tvs of list_nil() => () | _ => (ps(out, " (tvs"); pp_pcparams(out, tvs); ps(out, ")")) );
    ps(out, " mode="); pp_mode(out, mode);
    pp_pcfields(out, fields); ps(out, ")") )
| PCCfun(loc, _tps, fs) =>
  ( ps(out, "(fungroup"); print_span(out, loc);
    pp_fundclst(out, fs, ind + 1); ps(out, ")") )
| PCCval(loc, p, e) =>
  ( ps(out, "(val"); print_span(out, loc); ps(out, " ");
    pp_pat(out, p); ps(out, " = "); pp_exp(out, e, ind + 1); ps(out, ")") )
| PCCstaload(loc, nm) =>
  (ps(out, "(staload "); ps(out, nm); print_span(out, loc); ps(out, ")"))
| PCCimport(loc, path, _knd, _py) =>
  (ps(out, "(import "); ps(out, path); print_span(out, loc); ps(out, ")"))
| PCCalias(loc, nm, tvs, typ) =>
  ( ps(out, "(alias "); ps(out, nm); print_span(out, loc);
    ( case+ tvs of list_nil() => () | _ => (ps(out, " (tvs"); pp_pcparams(out, tvs); ps(out, ")")) );
    ps(out, " "); pp_typ(out, typ); ps(out, ")") )
| PCCexcept(loc, nm, ts) =>
  ( ps(out, "(exception "); ps(out, nm); print_span(out, loc); pp_typlst(out, ts); ps(out, ")") )
| PCCabstype(loc, nm, tvs, mode) =>
  ( ps(out, "(abstype "); ps(out, nm); print_span(out, loc);
    ( case+ tvs of list_nil() => () | _ => (ps(out, " (tvs"); pp_pcparams(out, tvs); ps(out, ")")) );
    ps(out, " mode="); pp_mode(out, mode); ps(out, ")") )
| PCCassume(loc, nm, typ) =>
  ( ps(out, "(assume "); ps(out, nm); print_span(out, loc);
    ps(out, " "); pp_typ(out, typ); ps(out, ")") )
| PCCextern(loc, nm, pnames, _ptypes, ret) =>
  ( ps(out, "(extern "); ps(out, nm); print_span(out, loc);
    ps(out, " (params"); pp_strnlst(out, pnames); ps(out, ")");
    ( case+ ret of
      | PyTypNone() => ()
      | PyTypSome(t) => (ps(out, " (ret "); pp_typ(out, t); ps(out, ")")) );
    ps(out, ")") )
| PCCimplement(loc, nm, pnames, _ptypes, ret, body, tias) =>
  ( ps(out, "(implement "); ps(out, nm); print_span(out, loc);
    // A-TEMPLATE: render the `@impl[Int, ..]` instantiation type-args (empty for a bare @impl).
    ( case+ tias of list_nil() => () | _ => (ps(out, " [tias"); pp_typlst(out, tias); ps(out, "]")) );
    ps(out, " (params"); pp_strnlst(out, pnames); ps(out, ")");
    ( case+ ret of
      | PyTypNone() => ()
      | PyTypSome(t) => (ps(out, " (ret "); pp_typ(out, t); ps(out, ")")) );
    ps(out, " = "); pp_exp(out, body, ind + 1); ps(out, ")") )
// A-TEMPLATE: a `@template[A] def foo[C](...) [: body]` declaration.
| PCCtempl(loc, targs, nm, pargs, pnames, _ptypes, ret, bodyopt) =>
  ( ps(out, "(template "); ps(out, nm); print_span(out, loc);
    ps(out, " (targs"); pp_pcparams(out, targs); ps(out, ")");
    ps(out, " (pargs"); pp_pcparams(out, pargs); ps(out, ")");
    ps(out, " (params"); pp_strnlst(out, pnames); ps(out, ")");
    ( case+ ret of
      | PyTypNone() => ()
      | PyTypSome(t) => (ps(out, " (ret "); pp_typ(out, t); ps(out, ")")) );
    ( case+ bodyopt of
      | PCEGNone() => ()
      | PCEGSome(b) => (ps(out, " = "); pp_exp(out, b, ind + 1)) );
    ps(out, ")") )
| PCCoverload(loc, nm, impl) =>
  ( ps(out, "(overload "); ps(out, nm); print_span(out, loc);
    ps(out, " with "); ps(out, impl); ps(out, ")") )
| PCCsortdef(loc, nm, srt) =>
  ( ps(out, "(sortdef "); ps(out, nm); print_span(out, loc);
    ps(out, " = "); ps(out, srt); ps(out, ")") )
| PCCstacst(loc, nm, srt) =>
  ( ps(out, "(stacst "); ps(out, nm); print_span(out, loc);
    ps(out, " : "); ps(out, srt); ps(out, ")") )
| PCCstadef(loc, nm, e) =>
  ( ps(out, "(stadef "); ps(out, nm); print_span(out, loc);
    ps(out, " = "); pp_exp(out, e, ind + 1); ps(out, ")") )
| PCCprfun(loc, _tps, f) =>
  ( ps(out, "(prfun"); print_span(out, loc);
    pp_fundclst(out, list_sing(f), ind + 1); ps(out, ")") )
| PCCprval(loc, p, ann, e) =>
  ( ps(out, "(prval"); print_span(out, loc); ps(out, " ");
    pp_pat(out, p);
    ( case+ ann of
      | PyTypNone() => ()
      | PyTypSome(t) => (ps(out, " : "); pp_typ(out, t)) );
    ps(out, " = "); pp_exp(out, e, ind + 1); ps(out, ")") )
| PCCpraxi(loc, nm, pnames, _ptypes, ret) =>
  ( ps(out, "(praxi "); ps(out, nm); print_span(out, loc);
    ps(out, " (params"); pp_strnlst(out, pnames); ps(out, ")");
    ( case+ ret of
      | PyTypNone() => ()
      | PyTypSome(t) => (ps(out, " (ret "); pp_typ(out, t); ps(out, ")")) );
    ps(out, ")") )
| PCCerror(loc, msg) =>
  (ps(out, "(Cerror \""); ps(out, msg); ps(out, "\""); print_span(out, loc); ps(out, ")"))
)
//
fun
pp_decllst(out: FILR, ds: list(pcdecl)): void =
(
case+ ds of
| list_nil() => ()
| list_cons(d, rest) => (pp_decl(out, d, 0); pp_decllst(out, rest))
)
//
fun
pp_diaglst(out: FILR, gs: list(pcdiag)): void =
(
case+ gs of
| list_nil() => ()
| list_cons(PCDiag(loc, msg), rest) =>
  (ps(out, "  "); ps(out, msg); ps(out, " "); print_span(out, loc); nl(out);
   pp_diaglst(out, rest))
)
//
(* ****** ****** *)
//
// ---- the public SATS entries (thin wrappers) -------------------------------
//
#implfun pclit_fprint(out, lit) = pp_lit(out, lit)
#implfun pcpat_fprint(out, p) = pp_pat(out, p)
#implfun pcexp_fprint(out, e) = pp_exp(out, e, 0)
#implfun pcdecl_fprint(out, d) = pp_decl(out, d, 0)
//
#implfun
pcdiag_fprint(out, g) = let
  val+ PCDiag(loc, msg) = g
in
  ps(out, "  "); ps(out, msg); ps(out, " "); print_span(out, loc)
end
//
#implfun
pcmodule_fprint(out, m) = let
  val+ PCModule(decls, diags) = m
in
  ps(out, "(pycore");
  pp_decllst(out, decls);
  nl(out); ps(out, ")"); nl(out);
  ps(out, "==== diagnostics ===="); nl(out);
  ( case+ diags of
    | list_nil() => (ps(out, "(none)"); nl(out))
    | _ => pp_diaglst(out, diags) )
end
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyelab_print.dats]
*)
