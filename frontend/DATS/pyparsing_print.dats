(* ****** ****** *)
(*
** M2 — Python-surface frontend: the PyAST PRETTY-PRINTER (DATS).
**
** Dumps a `pymodule` (and every sub-node) in an S-expression-ish form with `@span`
** on every node, so the golden tests PROVE that a real `loctn` flows into every PyAST
** node. The span is printed as @(r0:c0-r1:c1) (0-based row, byte col; half-open),
** identical to the M1 token dump format, so spans are directly comparable.
**
** STRUCTURE NOTE (ATS3 dialect): the mutually-recursive printers are plain `fun ...
** and ...` workers named pp_*; the SATS-declared entries (pytyp_fprint etc.) are thin
** `#implfun` wrappers at the end. (Mixing `#implfun` INTO an `and`-group with non-impl
** helpers leaves the helper unresolved — verified — so we avoid it.)
**
** Output primitives: the prelude's `strn_fprint(strn,FILR)` / `gint_fprint$sint`
** (argument order is (value, out); verified in M1). No global state.
**
** PURELY ADDITIVE; consumes pyparsing.sats / pylexing.sats / locinfo.sats read-only.
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
//
(* ****** ****** *)
//
fun ps(out: FILR, s: strn): void = strn_fprint(s, out)
fun pi(out: FILR, n: sint): void = gint_fprint$sint(n, out)
//
// C-PROOF: a comma-separated NAME list printer (the `{n, m}` unpack static binders on PyPcon).
fun
pp_strnlst(out: FILR, ns: list(strn)): void =
(
case+ ns of
| list_nil() => ()
| list_cons(n, list_nil()) => ps(out, n)
| list_cons(n, rest) => (ps(out, n); ps(out, ", "); pp_strnlst(out, rest))
)
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
// ---- operator tags + literals (no recursion) -------------------------------
//
fun
pp_bop(out: FILR, b: pybop): void =
(
case+ b of
| PyBor()   => ps(out, "or")
| PyBand()  => ps(out, "and")
| PyBeq()   => ps(out, "==")
| PyBne()   => ps(out, "!=")
| PyBlt()   => ps(out, "<")
| PyBle()   => ps(out, "<=")
| PyBgt()   => ps(out, ">")
| PyBge()   => ps(out, ">=")
| PyBadd()  => ps(out, "+")
| PyBsub()  => ps(out, "-")
| PyBmul()  => ps(out, "*")
| PyBdiv()  => ps(out, "/")
| PyBmod()  => ps(out, "%")
| PyBfdiv() => ps(out, "//")
| PyBpow()  => ps(out, "**")
)
//
fun
pp_uop(out: FILR, u: pyuop): void =
(
case+ u of
| PyUnot() => ps(out, "not")
| PyUneg() => ps(out, "-")
| PyUpos() => ps(out, "+")
)
//
fun
pp_lit(out: FILR, lit: pylit): void =
(
case+ lit of
| PyLint(loc, s)  => (ps(out, "(int "); ps(out, s); print_span(out, loc); ps(out, ")"))
| PyLflt(loc, s)  => (ps(out, "(flt "); ps(out, s); print_span(out, loc); ps(out, ")"))
| PyLstr(loc, s)  => (ps(out, "(str "); ps(out, s); print_span(out, loc); ps(out, ")"))
| PyLchr(loc, s)  => (ps(out, "(chr "); ps(out, s); print_span(out, loc); ps(out, ")"))
| PyLbool(loc, b) =>
  ( ps(out, "(bool ");
    ps(out, (if b then "true" else "false"));
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
(* ****** ****** *)
//
// ---- TYPE printers (mutually recursive group) ------------------------------
//
fun
pp_typ(out: FILR, t: pytyp): void =
(
case+ t of
| PyTcon(loc, nm, args) =>
  ( ps(out, "(Tcon "); ps(out, nm); print_span(out, loc);
    pp_typlst(out, args); ps(out, ")") )
| PyTvar(loc, nm) =>
  (ps(out, "(Tvar "); ps(out, nm); print_span(out, loc); ps(out, ")"))
| PyTidx(loc, s) =>
  (ps(out, "(Tidx "); ps(out, s); print_span(out, loc); ps(out, ")"))
| PyTbin(loc, bop, a, b) =>
  ( ps(out, "(Tbin "); pybop_fprint(out, bop); print_span(out, loc);
    ps(out, " "); pp_typ(out, a); ps(out, " "); pp_typ(out, b); ps(out, ")") )
| PyTfun(loc, ps0, res, tag) =>
  ( ps(out, "(Tfun"); print_span(out, loc);
    ps(out, " (params"); pp_typlst(out, ps0); ps(out, ")");
    // ARROW-EFFECTS: round-trip the verbatim arrow tag (empty = bare `->`).
    ps(out, " (tag "); ps(out, tag); ps(out, ")");
    ps(out, " (res "); pp_typ(out, res); ps(out, "))") )
| PyTtup(loc, ts) =>
  (ps(out, "(Ttup"); print_span(out, loc); pp_typlst(out, ts); ps(out, ")"))
| PyTrec(loc, fs) =>
  (ps(out, "(Trec"); print_span(out, loc); pp_tfields(out, fs); ps(out, ")"))
// A-QUANT: a quantified type `forall[..]/exists[..] T` — print the kind, binders, optional guard, body.
| PyTquant(loc, kind, binders, gopt, body) =>
  ( ps(out, "(Tquant ");
    ps(out, (if kind = 0 then "forall" else "exists")); print_span(out, loc);
    ps(out, " "); pp_quant_binders(out, binders);
    ( case+ gopt of
      | PyGuardSome(_, g) => (ps(out, " (guard "); pp_typ(out, g); ps(out, ")"))
      | PyGuardNone() => () );
    ps(out, " (body "); pp_typ(out, body); ps(out, "))") )
// B-LINEAR: the AT-VIEW `A at l`.
| PyTat(loc, carr, addr) =>
  ( ps(out, "(Tat"); print_span(out, loc); ps(out, " ");
    pp_typ(out, carr); ps(out, " at "); pp_typ(out, addr); ps(out, ")") )
| PyTerror(loc, msg) =>
  (ps(out, "(Terror \""); ps(out, msg); ps(out, "\""); print_span(out, loc); ps(out, ")"))
)
//
and
pp_typlst(out: FILR, ts: list(pytyp)): void =
(
case+ ts of
| list_nil() => ()
| list_cons(t, rest) => (ps(out, " "); pp_typ(out, t); pp_typlst(out, rest))
)
//
and
pp_tfields(out: FILR, fs: list(pytfield)): void =
(
case+ fs of
| list_nil() => ()
| list_cons(PyTField(loc, nm, t), rest) =>
  ( ps(out, " ("); ps(out, nm); ps(out, ": "); pp_typ(out, t); ps(out, ")");
    pp_tfields(out, rest) )
)
//
// A-QUANT: a minimal binder printer LOCAL to the type-printer group (the full pp_typaramlst lives
// in a separate, later `and`-group, so we print the binders + their optional sort here to stay
// within this group). " (b a : SInt)".
and
pp_quant_binders(out: FILR, tps: list(pytyparam)): void =
(
case+ tps of
| list_nil() => ()
| list_cons(PyTyParam(loc, nm, sopt, _decos, _gopt), rest) =>
  ( ps(out, " (b "); ps(out, nm); print_span(out, loc);
    ( case+ sopt of
      | PySortNone() => ()
      | PySortSome(_, srt) => (ps(out, " : "); ps(out, srt)) );
    ps(out, ")");
    pp_quant_binders(out, rest) )
)
//
(* ****** ****** *)
//
// ---- PATTERN printers (mutually recursive group) ---------------------------
//
fun
pp_pat(out: FILR, p: pypat): void =
(
case+ p of
| PyPvar(loc, nm) =>
  (ps(out, "(Pvar "); ps(out, nm); print_span(out, loc); ps(out, ")"))
| PyPwild(loc) =>
  (ps(out, "(Pwild"); print_span(out, loc); ps(out, ")"))
| PyPcon(loc, nm, sargs, args) =>
  ( ps(out, "(Pcon "); ps(out, nm); print_span(out, loc);
    ( case+ sargs of list_nil() => () | _ => (ps(out, " {"); pp_strnlst(out, sargs); ps(out, "}")) );
    pp_patlst(out, args); ps(out, ")") )
| PyPtup(loc, ps0) =>
  (ps(out, "(Ptup"); print_span(out, loc); pp_patlst(out, ps0); ps(out, ")"))
| PyPrec(loc, fs) =>
  (ps(out, "(Prec"); print_span(out, loc); pp_pfields(out, fs); ps(out, ")"))
| PyPlit(loc, lit) =>
  (ps(out, "(Plit"); print_span(out, loc); ps(out, " "); pp_lit(out, lit); ps(out, ")"))
| PyPas(loc, p1, nm) =>
  ( ps(out, "(Pas "); ps(out, nm); print_span(out, loc); ps(out, " ");
    pp_pat(out, p1); ps(out, ")") )
| PyPann(loc, p1, t) =>
  ( ps(out, "(Pann"); print_span(out, loc); ps(out, " ");
    pp_pat(out, p1); ps(out, " : "); pp_typ(out, t); ps(out, ")") )
// B-LINEAR: the LINEAR-CONSUME pattern `~p`.
| PyPfree(loc, p1) =>
  ( ps(out, "(Pfree"); print_span(out, loc); ps(out, " ~"); pp_pat(out, p1); ps(out, ")") )
| PyPerror(loc, msg) =>
  (ps(out, "(Perror \""); ps(out, msg); ps(out, "\""); print_span(out, loc); ps(out, ")"))
)
//
and
pp_patlst(out: FILR, ps0: list(pypat)): void =
(
case+ ps0 of
| list_nil() => ()
| list_cons(p, rest) => (ps(out, " "); pp_pat(out, p); pp_patlst(out, rest))
)
//
and
pp_pfields(out: FILR, fs: list(pypfield)): void =
(
case+ fs of
| list_nil() => ()
| list_cons(PyPField(loc, nm, p), rest) =>
  ( ps(out, " ("); ps(out, nm); ps(out, " = "); pp_pat(out, p); ps(out, ")");
    pp_pfields(out, rest) )
)
//
(* ****** ****** *)
//
// ---- EXPRESSION + STATEMENT + DECL printers (one big mutually-recursive group;
// statements contain expressions, expressions contain suites = statement lists) ----
//
fun
pp_exp(out: FILR, e: pyexp): void =
(
case+ e of
| PyEvar(loc, nm) =>
  (ps(out, "(Evar "); ps(out, nm); print_span(out, loc); ps(out, ")"))
| PyEcon(loc, nm) =>
  (ps(out, "(Econ "); ps(out, nm); print_span(out, loc); ps(out, ")"))
| PyElit(loc, lit) =>
  (ps(out, "(Elit"); print_span(out, loc); ps(out, " "); pp_lit(out, lit); ps(out, ")"))
| PyEwild(loc) =>
  (ps(out, "(Ewild"); print_span(out, loc); ps(out, ")"))
| PyEapp(loc, hd, args) =>
  ( ps(out, "(Eapp"); print_span(out, loc); ps(out, " ");
    pp_exp(out, hd); ps(out, " (args"); pp_explst(out, args); ps(out, "))") )
| PyEbin(loc, b, l, r) =>
  ( ps(out, "(Ebin "); pp_bop(out, b); print_span(out, loc); ps(out, " ");
    pp_exp(out, l); ps(out, " "); pp_exp(out, r); ps(out, ")") )
| PyEuna(loc, u, e1) =>
  ( ps(out, "(Euna "); pp_uop(out, u); print_span(out, loc); ps(out, " ");
    pp_exp(out, e1); ps(out, ")") )
| PyEif(loc, gs, els) =>
  ( ps(out, "(Eif"); print_span(out, loc);
    pp_guardlst(out, gs, 1);
    nl(out); print_indent(out, 1); ps(out, "(else ");
    pp_exp(out, els); ps(out, "))") )
| PyEmatch(loc, scrut, arms) =>
  ( ps(out, "(Ematch"); print_span(out, loc); ps(out, " ");
    pp_exp(out, scrut); pp_armlst(out, arms, 1); ps(out, ")") )
| PyEtup(loc, es) =>
  (ps(out, "(Etup"); print_span(out, loc); pp_explst(out, es); ps(out, ")"))
| PyElist(loc, es) =>
  (ps(out, "(Elist"); print_span(out, loc); pp_explst(out, es); ps(out, ")"))
| PyErec(loc, fs) =>
  (ps(out, "(Erec"); print_span(out, loc); pp_efields(out, fs); ps(out, ")"))
| PyEfield(loc, e1, nm) =>
  ( ps(out, "(Efield "); ps(out, nm); print_span(out, loc); ps(out, " ");
    pp_exp(out, e1); ps(out, ")") )
| PyEindex(loc, e1, ix) =>
  ( ps(out, "(Eindex"); print_span(out, loc); ps(out, " ");
    pp_exp(out, e1); ps(out, " "); pp_exp(out, ix); ps(out, ")") )
| PyElam(loc, is_func, params, body) =>
  ( ps(out, "(Elam"); (if is_func then ps(out, "@func") else ()); print_span(out, loc);
    ps(out, " (params"); pp_paramlst(out, params); ps(out, ")");
    pp_stmtlst(out, body, 1); ps(out, ")") )
| PyEann(loc, e1, t) =>
  ( ps(out, "(Eann"); print_span(out, loc); ps(out, " ");
    pp_exp(out, e1); ps(out, " : "); pp_typ(out, t); ps(out, ")") )
| PyEraise(loc, e1) =>
  ( ps(out, "(Eraise"); print_span(out, loc); ps(out, " "); pp_exp(out, e1); ps(out, ")") )
| PyEtry(loc, body, hs) =>
  ( ps(out, "(Etry"); print_span(out, loc);
    pp_stmtlst(out, body, 1); pp_armlst(out, hs, 1); ps(out, ")") )
| PyEop(loc, nm) =>
  (ps(out, "(Eop "); ps(out, nm); print_span(out, loc); ps(out, ")"))
// A-TEMPLATE: `@inst[T..] e` — print the type-arg list then the instantiated expr.
| PyEinst(loc, ts, e1) =>
  ( ps(out, "(Einst"); print_span(out, loc); ps(out, " [types");
    pp_typlst(out, ts); ps(out, "] "); pp_exp(out, e1); ps(out, ")") )
// B-LINEAR: `&x` address-of and `!p` deref.
| PyEaddr(loc, e1) =>
  ( ps(out, "(Eaddr"); print_span(out, loc); ps(out, " &"); pp_exp(out, e1); ps(out, ")") )
| PyEderef(loc, e1) =>
  ( ps(out, "(Ederef"); print_span(out, loc); ps(out, " !"); pp_exp(out, e1); ps(out, ")") )
// GAP B: `r[]` ref-cell deref.
| PyEderefcell(loc, e1) =>
  ( ps(out, "(Ederefcell"); print_span(out, loc); ps(out, " "); pp_exp(out, e1); ps(out, "[])") )
| PyEerror(loc, msg) =>
  (ps(out, "(Eerror \""); ps(out, msg); ps(out, "\""); print_span(out, loc); ps(out, ")"))
)
//
and
pp_explst(out: FILR, es: list(pyexp)): void =
(
case+ es of
| list_nil() => ()
| list_cons(e, rest) => (ps(out, " "); pp_exp(out, e); pp_explst(out, rest))
)
//
and
pp_efields(out: FILR, fs: list(pyefield)): void =
(
case+ fs of
| list_nil() => ()
| list_cons(PyEField(loc, nm, e), rest) =>
  ( ps(out, " ("); ps(out, nm); ps(out, " = "); pp_exp(out, e); ps(out, ")");
    pp_efields(out, rest) )
)
//
and
pp_paramlst(out: FILR, ps0: list(pyparam)): void =
(
case+ ps0 of
| list_nil() => ()
| list_cons(PyParam(loc, nm, topt), rest) =>
  ( ps(out, " ("); ps(out, nm);
    ( case+ topt of
      | PyTypNone() => ()
      | PyTypSome(t) => (ps(out, ": "); pp_typ(out, t)) );
    ps(out, ")"); pp_paramlst(out, rest) )
)
//
and
pp_guardlst(out: FILR, gs: list(pyguard), ind: sint): void =
(
case+ gs of
| list_nil() => ()
| list_cons(PyGuard(loc, c, body), rest) =>
  ( nl(out); print_indent(out, ind); ps(out, "(guard");
    print_span(out, loc); ps(out, " (cond "); pp_exp(out, c); ps(out, ")");
    pp_stmtlst(out, body, ind + 1); ps(out, ")");
    pp_guardlst(out, rest, ind) )
)
//
and
pp_armlst(out: FILR, arms: list(pyarm), ind: sint): void =
(
case+ arms of
| list_nil() => ()
| list_cons(PyArm(loc, p, gopt, body), rest) =>
  ( nl(out); print_indent(out, ind); ps(out, "(arm");
    print_span(out, loc); ps(out, " "); pp_pat(out, p);
    ( case+ gopt of
      | PyExpNone() => ()
      | PyExpSome(g) => (ps(out, " (if "); pp_exp(out, g); ps(out, ")")) );
    pp_stmtlst(out, body, ind + 1); ps(out, ")");
    pp_armlst(out, rest, ind) )
)
//
and
pp_stmt(out: FILR, s: pystmt, ind: sint): void =
(
nl(out); print_indent(out, ind);
case+ s of
| PyDlet(loc, decos, mut, p, topt, rhs) =>
  ( ps(out, "(let "); ps(out, (if mut then "mut" else "imm")); print_span(out, loc);
    pp_decolst(out, decos);   // DECORATOR REWORK: prints " (deco ...)" only when non-empty (no golden drift for a plain let)
    ps(out, " "); pp_pat(out, p);
    ( case+ topt of
      | PyTypNone() => ()
      | PyTypSome(t) => (ps(out, " : "); pp_typ(out, t)) );
    ps(out, " = "); pp_exp(out, rhs); ps(out, ")") )
| PySvar(loc, nm, topt, rhs) =>
  ( ps(out, "(var"); print_span(out, loc); ps(out, " "); ps(out, nm);
    ( case+ topt of
      | PyTypNone() => ()
      | PyTypSome(t) => (ps(out, " : "); pp_typ(out, t)) );
    ps(out, " = "); pp_exp(out, rhs); ps(out, ")") )
| PySassign(loc, lv, rhs) =>
  ( ps(out, "(assign"); print_span(out, loc); ps(out, " ");
    pp_exp(out, lv); ps(out, " := "); pp_exp(out, rhs); ps(out, ")") )
| PySmove(loc, lv, rhs) =>
  ( ps(out, "(move"); print_span(out, loc); ps(out, " ");
    pp_exp(out, lv); ps(out, " :=> "); pp_exp(out, rhs); ps(out, ")") )
| PySswap(loc, lv, rhs) =>
  ( ps(out, "(swap"); print_span(out, loc); ps(out, " ");
    pp_exp(out, lv); ps(out, " :=: "); pp_exp(out, rhs); ps(out, ")") )
| PySreassign(loc, lv, rhs) =>
  ( ps(out, "(reassign"); print_span(out, loc); ps(out, " ");
    pp_exp(out, lv); ps(out, " = "); pp_exp(out, rhs); ps(out, ")") )
| PySexpr(loc, e) =>
  (ps(out, "(expr"); print_span(out, loc); ps(out, " "); pp_exp(out, e); ps(out, ")"))
| PySif(loc, gs, els) =>
  ( ps(out, "(if"); print_span(out, loc);
    pp_guardlst(out, gs, ind + 1);
    pp_else(out, els, ind + 1); ps(out, ")") )
| PySwhile(loc, c, body, els) =>
  ( ps(out, "(while"); print_span(out, loc); ps(out, " (cond ");
    pp_exp(out, c); ps(out, ")");
    pp_stmtlst(out, body, ind + 1);
    pp_else(out, els, ind + 1); ps(out, ")") )
| PySfor(loc, p, it, body, els) =>
  ( ps(out, "(for"); print_span(out, loc); ps(out, " ");
    pp_pat(out, p); ps(out, " in "); pp_exp(out, it);
    pp_stmtlst(out, body, ind + 1);
    pp_else(out, els, ind + 1); ps(out, ")") )
| PySbreak(loc) =>
  (ps(out, "(break"); print_span(out, loc); ps(out, ")"))
| PyScontinue(loc) =>
  (ps(out, "(continue"); print_span(out, loc); ps(out, ")"))
| PySreturn(loc, eopt) =>
  ( ps(out, "(return"); print_span(out, loc);
    ( case+ eopt of
      | PyExpNone() => ()
      | PyExpSome(e) => (ps(out, " "); pp_exp(out, e)) );
    ps(out, ")") )
| PySblock(loc, body) =>
  (ps(out, "(block"); print_span(out, loc); pp_stmtlst(out, body, ind + 1); ps(out, ")"))
| PySdecl(loc, d) =>
  (ps(out, "(sdecl"); print_span(out, loc); pp_decl(out, d, ind + 1); ps(out, ")"))
| PySerror(loc, msg) =>
  (ps(out, "(Serror \""); ps(out, msg); ps(out, "\""); print_span(out, loc); ps(out, ")"))
)
//
and
pp_else(out: FILR, els: pystmtlstopt, ind: sint): void =
(
case+ els of
| PyElseNone() => ()
| PyElseSome(body) =>
  ( nl(out); print_indent(out, ind); ps(out, "(else");
    pp_stmtlst(out, body, ind + 1); ps(out, ")") )
)
//
and
pp_stmtlst(out: FILR, ss: list(pystmt), ind: sint): void =
(
case+ ss of
| list_nil() => ()
| list_cons(s, rest) => (pp_stmt(out, s, ind); pp_stmtlst(out, rest, ind))
)
//
and
pp_decl(out: FILR, d: pydecl, ind: sint): void =
(
nl(out); print_indent(out, ind);
case+ d of
| PyCfun(loc, decos, nm, tvs, params, ropt, body, wheres) =>
  ( ps(out, "(def "); ps(out, nm); print_span(out, loc);
    pp_decolst(out, decos);   // DECORATOR REWORK: prints " (deco ...)" only when non-empty (no golden drift for a plain def)
    ( case+ tvs of list_nil() => () | _ => (ps(out, " (tvs"); pp_typaramlst(out, tvs); ps(out, ")")) );
    ps(out, " (params"); pp_paramlst(out, params); ps(out, ")");
    ( case+ ropt of
      | PyTypNone() => ()
      | PyTypSome(t) => (ps(out, " (ret "); pp_typ(out, t); ps(out, ")")) );
    pp_stmtlst(out, body, ind + 1);
    // SCOPING: print the `where:` block only when present (no golden drift for a plain def).
    ( case+ wheres of
      | list_nil() => ()
      | _ => (nl(out); print_indent(out, ind + 1); ps(out, "(where");
              pp_decllst_ind(out, wheres, ind + 2); ps(out, ")")) );
    ps(out, ")") )
| PyCprivate(loc, ds) =>
  ( ps(out, "(private"); print_span(out, loc);
    pp_decllst_ind(out, ds, ind + 1); ps(out, ")") )
| PyCenum(loc, decos, nm, tvs, dcons) =>
  ( ps(out, "(enum "); ps(out, nm); print_span(out, loc);
    pp_decolst(out, decos);
    ( case+ tvs of list_nil() => () | _ => (ps(out, " (tvs"); pp_typaramlst(out, tvs); ps(out, ")")) );
    pp_dataconlst(out, dcons, ind + 1); ps(out, ")") )
| PyCstruct(loc, decos, nm, tvs, fields) =>
  ( ps(out, "(struct "); ps(out, nm); print_span(out, loc);
    pp_decolst(out, decos);
    ( case+ tvs of list_nil() => () | _ => (ps(out, " (tvs"); pp_typaramlst(out, tvs); ps(out, ")")) );
    pp_fieldlst(out, fields, ind + 1); ps(out, ")") )
| PyCtype(loc, decos, nm, tvs, t) =>
  ( ps(out, "(type "); ps(out, nm); print_span(out, loc);
    pp_decolst(out, decos);
    ( case+ tvs of list_nil() => () | _ => (ps(out, " (tvs"); pp_typaramlst(out, tvs); ps(out, ")")) );
    ps(out, " (alias "); pp_typ(out, t); ps(out, ")"); ps(out, ")") )
| PyCabstype(loc, decos, nm, tvs) =>
  ( ps(out, "(abstype "); ps(out, nm); print_span(out, loc);
    pp_decolst(out, decos);
    ( case+ tvs of list_nil() => () | _ => (ps(out, " (tvs"); pp_typaramlst(out, tvs); ps(out, ")")) );
    ps(out, ")") )
| PyCassume(loc, nm, t) =>
  ( ps(out, "(assume "); ps(out, nm); print_span(out, loc);
    ps(out, " (rep "); pp_typ(out, t); ps(out, ")"); ps(out, ")") )
| PyCexcept(loc, nm, ts) =>
  ( ps(out, "(exception "); ps(out, nm); print_span(out, loc); pp_typlst(out, ts); ps(out, ")") )
| PyCsortdef(loc, nm, srt) =>
  ( ps(out, "(sortdef "); ps(out, nm); print_span(out, loc);
    ps(out, " = "); ps(out, srt); ps(out, ")") )
| PyCsortsub(loc, nm, binder, guards) =>
  ( ps(out, "(sortsub "); ps(out, nm); print_span(out, loc);
    ps(out, " = {"); pp_typaramlst(out, list_cons(binder, list_nil()));
    ps(out, " |"); pp_typlst(out, guards); ps(out, " })") )
| PyCstacst(loc, nm, srt) =>
  ( ps(out, "(stacst "); ps(out, nm); print_span(out, loc);
    ps(out, " : "); ps(out, srt); ps(out, ")") )
| PyCstadef(loc, nm, e) =>
  ( ps(out, "(stadef "); ps(out, nm); print_span(out, loc);
    ps(out, " = "); pp_exp(out, e); ps(out, ")") )
| PyCimport(loc, imp) =>
  (ps(out, "(import"); print_span(out, loc); ps(out, " "); pp_import(out, imp); ps(out, ")"))
| PyCsymalias(loc, nm, tgt, prec) =>
  ( ps(out, "(symalias "); ps(out, nm); print_span(out, loc);
    ps(out, " = "); ps(out, tgt);
    ( if prec >= 0 then (ps(out, " of "); pi(out, prec)) else () );
    ps(out, ")") )
| PyCstmt(loc, s) =>
  (ps(out, "(cstmt"); print_span(out, loc); pp_stmt(out, s, ind + 1); ps(out, ")"))
| PyCerror(loc, msg) =>
  (ps(out, "(Cerror \""); ps(out, msg); ps(out, "\""); print_span(out, loc); ps(out, ")"))
)
//
// SCOPING: an INDENT-aware decl-list printer (for the `where:` / `private:` sub-blocks). In the
// `and`-group so it is mutually recursive with pp_decl (each sub-decl prints its own `nl`+indent).
and
pp_decllst_ind(out: FILR, ds: list(pydecl), ind: sint): void =
(
case+ ds of
| list_nil() => ()
| list_cons(d, rest) => (pp_decl(out, d, ind); pp_decllst_ind(out, rest, ind))
)
//
// a list of prefix/inline decorators: " (deco @linear@(..) @unboxed@(..))" (omit if none).
and
pp_decolst(out: FILR, decos: list(pydecorator)): void =
(
case+ decos of
| list_nil() => ()
| _ => (ps(out, " (deco"); pp_decolst_aux(out, decos); ps(out, ")"))
)
and
pp_decolst_aux(out: FILR, decos: list(pydecorator)): void =
(
case+ decos of
| list_nil() => ()
| list_cons(PyDecor(loc, nm, dargs), rest) =>
  ( ps(out, " @"); ps(out, nm); print_span(out, loc);
    // A-TEMPLATE: render the optional `[…]` arg payload so a goldens diff shows the new syntax.
    ( case+ dargs of
      | PyDAnone() => ()
      | PyDAbinders(bs) => (ps(out, "[binders"); pp_typaramlst(out, bs); ps(out, "]"))
      | PyDAtypes(ts)   => (ps(out, "[types"); pp_typlst(out, ts); ps(out, "]")) );
    pp_decolst_aux(out, rest) )
)
//
// a type-param list: " (tyvar A@(..)) (tyvar A@(..) : Linear (deco @unboxed@(..)))".
and
pp_typaramlst(out: FILR, tps: list(pytyparam)): void =
(
case+ tps of
| list_nil() => ()
| list_cons(PyTyParam(loc, nm, sopt, decos, gopt), rest) =>
  ( ps(out, " (tyvar "); ps(out, nm); print_span(out, loc);
    ( case+ sopt of
      | PySortNone() => ()
      | PySortSome(locS, srt) => (ps(out, " : "); ps(out, srt); print_span(out, locS)) );
    pp_decolst(out, decos);
    ( case+ gopt of
      | PyGuardNone() => ()
      | PyGuardSome(locG, g) => (ps(out, " (guard "); pp_typ(out, g); print_span(out, locG); ps(out, ")")) );
    ps(out, ")");
    pp_typaramlst(out, rest) )
)
//
// a struct-field list: each field on its own indented line "(field x@(..) <type>)".
and
pp_fieldlst(out: FILR, fields: list(pyfield), ind: sint): void =
(
case+ fields of
| list_nil() => ()
| list_cons(PyField(loc, nm, t), rest) =>
  ( nl(out); print_indent(out, ind); ps(out, "(field "); ps(out, nm); print_span(out, loc);
    ps(out, " "); pp_typ(out, t); ps(out, ")");
    pp_fieldlst(out, rest, ind) )
)
//
and
pp_dataconlst(out: FILR, dcons: list(pydatacon), ind: sint): void =
(
case+ dcons of
| list_nil() => ()
| list_cons(PyDataCon(loc, nm, ts), rest) =>
  ( nl(out); print_indent(out, ind); ps(out, "(case "); ps(out, nm); print_span(out, loc);
    pp_typlst(out, ts); ps(out, ")");
    pp_dataconlst(out, rest, ind) )
)
//
and
pp_import(out: FILR, imp: pyimport): void =
(
case+ imp of
| PyImpModule(loc, segs) =>
  (ps(out, "(module"); print_span(out, loc); pp_strlst(out, segs); ps(out, ")"))
| PyImpFrom(loc, segs, star, names) =>
  ( ps(out, "(from"); print_span(out, loc);
    ps(out, " (path"); pp_strlst(out, segs); ps(out, ")");
    ( if star then ps(out, " *")
      else (ps(out, " (names"); pp_strlst(out, names); ps(out, ")")) );
    ps(out, ")") )
)
//
(* ****** ****** *)
//
fun
pp_decllst(out: FILR, ds: list(pydecl)): void =
(
case+ ds of
| list_nil() => ()
| list_cons(d, rest) => (pp_decl(out, d, 0); pp_decllst(out, rest))
)
//
fun
pp_diaglst(out: FILR, gs: list(pydiag)): void =
(
case+ gs of
| list_nil() => ()
| list_cons(PyDiag(loc, msg), rest) =>
  (ps(out, "  "); ps(out, msg); ps(out, " "); print_span(out, loc); nl(out);
   pp_diaglst(out, rest))
)
//
(* ****** ****** *)
//
// ---- the public SATS entries (thin wrappers) -------------------------------
//
#implfun pybop_fprint(out, b) = pp_bop(out, b)
#implfun pyuop_fprint(out, u) = pp_uop(out, u)
#implfun pylit_fprint(out, lit) = pp_lit(out, lit)
#implfun pytyp_fprint(out, t) = pp_typ(out, t)
#implfun pypat_fprint(out, p) = pp_pat(out, p)
#implfun pyexp_fprint(out, e) = pp_exp(out, e)
#implfun pystmt_fprint(out, s) = pp_stmt(out, s, 0)
#implfun pydecl_fprint(out, d) = pp_decl(out, d, 0)
//
#implfun
pydiag_fprint(out, g) = let
  val+ PyDiag(loc, msg) = g
in
  ps(out, "  "); ps(out, msg); ps(out, " "); print_span(out, loc)
end
//
#implfun
pymodule_fprint(out, m) = let
  val+ PyModule(decls, diags) = m
in
  ps(out, "(module");
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
end of [frontend/DATS/pyparsing_print.dats]
*)
