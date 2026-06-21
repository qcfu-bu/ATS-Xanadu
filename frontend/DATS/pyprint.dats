(* ****** ****** *)
(*
** pyprint.dats — the BOOTSTRAP PRETTY-PRINTER (P2): stock L0 AST -> pythonic.
**
** The INVERSE of the frontend's lowering. Walks the stock parser's d0parsed
** declaration tree (obtained via d0parsed_from_fpath) and emits the pythonic
** spelling of each node. TRACER scope = the constructs in xstamp0.sats.
**
** THE MAPPING (frontend/docs/BOOTSTRAP-PLAN.md):
**   #typedef A = B / abstbox-alias        -> type A = B
**   #abstype T <= REP / #abstbox T        -> @abstract type T <= REP   (rep optional)
**     parametric #abstbox T(x:t0)         -> @abstract type T[X]
**   bodyless fun f{a:s}(args): R          -> @extern def f[A](args) -> R
**   bodyless val x: T                     -> @static let x: T
**   #symload NAME with FN [of N]          -> @overload NAME = FN
**   #define NAME val                      -> let NAME = val
**   #include "x"                          -> # include "x"  (TODO: import)
**
** REWRITE RULES:
**   (1) CAPITALIZE type & data-constructor names (positionally: type exprs,
**       typedef/abstype LHS, result/arg types). FUNCTION/value names stay as-is.
**   (2) `$`-in-ident foo$bar -> Koka-style foo/bar  ($->/).
**   (3) qualified $M.x -> bare x.
**   Anything unmapped -> `# TODO(pp): <construct>` (gaps stay VISIBLE).
**
** PURELY ADDITIVE: only CALLS the compiler-as-a-library (lib2xatsopt).
*)
(* ****** ****** *)
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
#staload "./../../srcgen2/SATS/lexing0.sats"
#staload "./../../srcgen2/SATS/staexp0.sats"
#staload "./../../srcgen2/SATS/dynexp0.sats"
#staload "./../../srcgen2/SATS/parsing.sats"
//
#staload "./../SATS/pyprint.sats"
//
(* ****** ****** *)
//
// string transforms done in the JS glue (frontend/CATS/pyprint.cats) — trivial in
// JS, and avoids the dependently-typed strn_get$at surgery in ATS.
//   PYPP_capitalize : uppercase the first character.
//   PYPP_dollar_fix : rewrite the `$`-in-ident.  The DESIGN decision (BOOTSTRAP-
//     PLAN) is Koka-style `$`->`/`; HOWEVER our frontend lexer does NOT yet accept
//     `/` inside an identifier (it lexes as the division op), so for the TRACER we
//     emit `$`->`_` (what the reference _ucase translation uses, reaching nerror=0).
//     Switching to `/` is parser-breadth work (lexer ident-char set), not a P2
//     pretty-printer concern — see the TODO note at the call site.
//   PYPP_xname/PYPP_pname : synthesized positional typaram/param names.
#extern fun PYPP_capitalize(s: strn): strn = $extnam()
#extern fun PYPP_dollar_fix(s: strn): strn = $extnam()
// synthesized positional names (string-building done in JS to avoid the ATS
// string-append template): "X"+i (a typaram), "a"/"b".../"x"+i (a parameter).
#extern fun PYPP_xname(i: sint): strn = $extnam()
#extern fun PYPP_pname(i: sint): strn = $extnam()
// whether a name contains a `$` (so we can emit the visible $->/ divergence note).
#extern fun PYPP_has_dollar(s: strn): bool = $extnam()
//
// CAPITALIZE-SCOPING (dynamic side): the file-local name registry. PYPP_local_add
// records a name DEFINED IN THIS FILE (a datatype type-name or data-constructor,
// in its lowercase ATS spelling); PYPP_local_has tests membership. Only file-local
// names capitalize at emission; prelude/external names stay verbatim.
#extern fun PYPP_local_reset((*0*)): void = $extnam()
#extern fun PYPP_local_add(s: strn): void = $extnam()
#extern fun PYPP_local_has(s: strn): bool = $extnam()
// capitalize-ALL mode (the STATIC tracer default) vs file-local-only (DYNAMIC).
#extern fun PYPP_capall_set(b: bool): void = $extnam()
#extern fun PYPP_capall_get((*0*)): bool = $extnam()
//
(* ****** ****** *)
//
// ====================== string + name helpers ===============================
//
// raw lexeme out of a token (identifier/literal payload).
fun
tok_lexeme(tok: token): strn =
(
  case+ tok.node() of
  | T_IDALP(s) => s
  | T_IDSYM(s) => s
  | T_IDDLR(s) => s     // $name
  | T_IDSRP(s) => s     // #name
  | T_IDQUA(s) => s     // $name.
  | T_IDENT(s) => s
  | T_INT01(s) => s
  | T_INT02(_, s) => s
  | T_STRN1_clsd(s, _) => s
  | _ => "?"
)
//
fun
i0dnt_lexeme(id: i0dnt): strn =
(
  case+ id.node() of
  | I0DNTsome(tok) => tok_lexeme(tok)
  | I0DNTnone(tok) => tok_lexeme(tok)
)
//
// d0qid (qualified dyn-id): DROP the qualifier (rule 3), keep the bare name.
fun
d0qid_lexeme(q: d0qid): strn =
(
  case+ q of
  | D0QIDnone(id) => i0dnt_lexeme(id)
  | D0QIDsome(_, id) => i0dnt_lexeme(id)
)
//
// s0ymb (the symload alias name): an i0dnt or a [] bracket symbol.
fun
s0ymb_lexeme(sym: s0ymb): strn =
(
  case+ sym.node() of
  | S0YMBi0dnt(id) => i0dnt_lexeme(id)
  | S0YMBbrckt(_, _) => "[]"
)
//
(* ****** ****** *)
//
// rule 2: `$`-in-ident.  Design target = `/` (Koka-style); emitted as `_` until
// the lexer accepts `/` in idents (see PYPP_dollar_fix note). rule 3 (qualified
// `$M.x` -> bare `x`) is handled at the qualifier level (we take bare names).
fun rewrite_dollar(s: strn): strn = PYPP_dollar_fix(s)
//
// a FUNCTION / VALUE name: keep case, but $->/.
fun fname(s: strn): strn = rewrite_dollar(s)
//
// a TYPE name (LHS of typedef/abstype, or a value-name in a value position):
// capitalize + $->/.   (rule 1)
fun tyname(s: strn): strn = PYPP_capitalize(rewrite_dollar(s))
//
// CAPITALIZE-SCOPING: a name in TYPE position that capitalizes ONLY if it is
// file-local (a datatype defined in THIS file). Prelude/external type names
// (strn, list, optn, ...) stay verbatim so they resolve against the lowercase
// pyrt — exactly what the nerror=0 hand-translation did.
fun tyname_scoped(s: strn): strn =
  if PYPP_capall_get()
  then PYPP_capitalize(rewrite_dollar(s))
  else (if PYPP_local_has(s)
        then PYPP_capitalize(rewrite_dollar(s)) else rewrite_dollar(s))
//
// a data-CONSTRUCTOR name in expr/pattern position: capitalize ONLY if file-local
// (e.g. DRPTH — already upper, but a lowercase file-local con would also lift).
// Prelude cons (list_cons, list_nil, ...) stay verbatim.
fun conname_scoped(s: strn): strn =
  if PYPP_local_has(s) then PYPP_capitalize(rewrite_dollar(s)) else rewrite_dollar(s)
//
(* ****** ****** *)
//
// ====================== output primitives ===================================
//
fun ps(out: FILR, s: strn): void = strn_fprint(s, out)
fun nl(out: FILR): void = strn_fprint("\n", out)
//
fun
todo(out: FILR, what: strn): void =
  (ps(out, "# TODO(pp): "); ps(out, what); nl(out))
//
(* ****** ****** *)
//
// ====================== TYPE (s0exp) emission ===============================
//
// emit a type expression in pythonic form. Names in type position capitalize.
//
// (one mutually-recursive block: pp_s0exp + its sequence/apps helpers.)
fun
pp_s0exp(out: FILR, se: s0exp): void =
(
  case+ se.node() of
  //
  // a bare type name (stamp, uint, bool, ...). Capitalize per scoping (rule 1):
  // capall=true (static) -> always; dynamic -> only file-local datatype names.
  | S0Eid0(id) => ps(out, tyname_scoped(i0dnt_lexeme(id)))
  //
  // an integer literal as a type/index (e.g. a tuple arity) — verbatim.
  | S0Eint(t0) => (
      case+ t0 of
      | T0INTsome(tok) => ps(out, tok_lexeme(tok))
      | T0INTnone(tok) => ps(out, tok_lexeme(tok))
    )
  //
  // a type application: head followed by paren arg-groups.
  //   tmpmap(itm)            -> Tmpmap[Itm]
  //   strm_vt(@(sint,itm))   -> Strm_vt[(SInt, Itm)]
  | S0Eapps(ses) => pp_apps(out, ses)
  //
  // a flat / boxed tuple `@(a,b)` / `$(a,b)`  -> (A, B).
  | S0Etup1(_, _, ses, _) => pp_tuple(out, ses)
  //
  // a parenthesized single type (grouping) — render its contents.
  | S0Elpar(_, ses, _) => (
      case+ ses of
      | list_cons(se1, list_nil()) => pp_s0exp(out, se1)
      | _ => pp_tuple(out, ses)
    )
  //
  // a qualified static type $M.t -> drop the $M. (rule 3), capitalize the bare.
  | S0Equal0(_, se1) => pp_s0exp(out, se1)
  //
  | S0Eannot(se1, _) => pp_s0exp(out, se1)
  //
  | _ => ps(out, "# TODO(pp): s0exp")
)
//
// an apps list: first elem is the head (a type name); subsequent S0Elpar groups
// are arg lists -> `Head[arg, ...]`. A standalone head (no args) is just `Head`.
and
pp_apps(out: FILR, ses: s0explst): void =
(
  case+ ses of
  | list_nil() => ()
  | list_cons(hd, rest) => (
      pp_s0exp(out, hd);
      pp_apps_args(out, rest)
    )
)
and
pp_apps_args(out: FILR, ses: s0explst): void =
(
  case+ ses of
  | list_nil() => ()
  | list_cons(se, rest) => (
      (case+ se.node() of
       | S0Elpar(_, args, _) => pp_typargs(out, args)
       | _ => (ps(out, "["); pp_s0exp(out, se); ps(out, "]")));
      pp_apps_args(out, rest)
    )
)
// a comma-separated list of s0exp (arg lists / tuple elems / type args).
and
pp_s0exp_seq(out: FILR, ses: s0explst): void =
(
  case+ ses of
  | list_nil() => ()
  | list_cons(se, rest) => (
      pp_s0exp(out, se);
      (case+ rest of list_nil() => () | _ => ps(out, ", "));
      pp_s0exp_seq(out, rest)
    )
)
// a paren-app argument group -> the bracketed type-arg list `[arg, ...]`.
and
pp_typargs(out: FILR, ses: s0explst): void =
  (ps(out, "["); pp_s0exp_seq(out, ses); ps(out, "]"))
// the elements inside a flat tuple `@(a, b)` -> `(A, B)`.
and
pp_tuple(out: FILR, ses: s0explst): void =
  (ps(out, "("); pp_s0exp_seq(out, ses); ps(out, ")"))
//
(* ****** ****** *)
//
// ====================== sort-quantifier {a:s} -> [A] typaram ================
//
// emit the type-params bracket from a list of static-quantifier args. Each
// S0QUAvars binds names; we render them capitalized inside `[...]`. Returns
// whether anything was emitted (so the caller can decide on the bracket).
//
fun
collect_squa_names(sqs: s0qualst): list(strn) =
(
  case+ sqs of
  | list_nil() => list_nil()
  | list_cons(sq, rest) => (
      case+ sq.node() of
      | S0QUAvars(ids, _) => list_append(squa_idnames(ids), collect_squa_names(rest))
      | S0QUAprop(_) => collect_squa_names(rest)
    )
)
and
squa_idnames(ids: i0dntlst): list(strn) =
(
  case+ ids of
  | list_nil() => list_nil()
  | list_cons(id, rest) => list_cons(tyname(i0dnt_lexeme(id)), squa_idnames(rest))
)
//
fun
pp_names_brkt(out: FILR, ns: list(strn)): void = let
  fun loop(out: FILR, ns: list(strn)): void =
    case+ ns of
    | list_nil() => ()
    | list_cons(n, rest) => (
        ps(out, n);
        (case+ rest of list_nil() => () | _ => ps(out, ", "));
        loop(out, rest)
      )
in
  case+ ns of
  | list_nil() => ()
  | _ => (ps(out, "["); loop(out, ns); ps(out, "]"))
end
//
(* ****** ****** *)
//
// ====================== d0arg (fun arg lists + sort-quants) ================
//
// the dynamic-arg list of a bodyless fun signature is a d0arglst mixing:
//   D0ARGsta0(tk, sqs, tk)  -- the {itm:tbox} sort-quantifier  -> [Itm] typaram
//   D0ARGdyn2(tk, atyps, _, tk) -- the (arg-types) dyn parens   -> (args) ...
// We split: collect ALL sort-quant names (-> the [..] typaram), and render the
// dyn arg-types as `(a: T, b: T)` with positional pythonic names a,b,c,...
//
fun
darg_squa_names(dargs: d0arglst): list(strn) =
(
  case+ dargs of
  | list_nil() => list_nil()
  | list_cons(da, rest) => (
      case+ da.node() of
      | D0ARGsta0(_, sqs, _) => list_append(collect_squa_names(sqs), darg_squa_names(rest))
      | _ => darg_squa_names(rest)
    )
)
//
// the a0typ's type (each carries an s0exp + optional comment).
fun
pp_a0typ(out: FILR, at: a0typ): void =
(
  case+ at.node() of
  | A0TYPsome(se, _) => pp_s0exp(out, se)
)
//
// positional pythonic parameter names: a, b, c, ... (the ATS arg-type list is
// unnamed/positional, so we synthesize Python parameter names).
fun pname_at(i: sint): strn = PYPP_pname(i)
//
fun
pp_atyps(out: FILR, i: sint, ats: a0typlst): void =
(
  case+ ats of
  | list_nil() => ()
  | list_cons(at, rest) => (
      ps(out, pname_at(i)); ps(out, ": "); pp_a0typ(out, at);
      (case+ rest of list_nil() => () | _ => ps(out, ", "));
      pp_atyps(out, i+1, rest)
    )
)
//
// render the (arg-types) parens of a fun signature.
fun
pp_darg_dyn(out: FILR, dargs: d0arglst): void =
(
  case+ dargs of
  | list_nil() => ps(out, "()")
  | list_cons(da, rest) => (
      case+ da.node() of
      | D0ARGdyn2(_, atyps, _, _) => (ps(out, "("); pp_atyps(out, 0, atyps); ps(out, ")"))
      | _ => pp_darg_dyn(out, rest)
    )
)
//
(* ****** ****** *)
//
// ====================== bodyless val / fun (D0Cdynconst) ===================
//
// distinguish val vs fun by the leading token kind: T_VAL -> @static let,
// T_FUN -> @extern def.
//
fun
tok_is_val(tok: token): bool =
  (case+ tok.node() of T_VAL _ => true | _ => false)
//
// emit ONE d0cstdcl (the name + signature) as an @extern def / @static let body.
//
fun
pp_dynconst_fun(out: FILR, dcd: d0cstdcl): void = let
  val nm    = i0dnt_lexeme(d0cstdcl_get_dpid(dcd))
  val dargs = d0cstdcl_get_darg(dcd)
  val sres  = d0cstdcl_get_sres(dcd)
  val tps   = darg_squa_names(dargs)
in
  // VISIBLE divergence note: the `$`-in-ident name is rendered with `_` (design
  // target is Koka `/`, but the lexer doesn't accept `/` in idents yet).
  (if PYPP_has_dollar(nm)
   then todo(out, "$-in-ident rendered '_' (design target '/'; lexer ident-char gap)")
   else ());
  ps(out, "@extern"); nl(out);
  ps(out, "def "); ps(out, fname(nm));
  pp_names_brkt(out, tps);
  pp_darg_dyn(out, dargs);
  ps(out, " -> ");
  (case+ sres of
   | S0RESsome(_, se) => pp_s0exp(out, se)
   | S0RESnone() => ps(out, "Void"));
  nl(out)
end
//
fun
pp_dynconst_val(out: FILR, dcd: d0cstdcl): void = let
  val nm   = i0dnt_lexeme(d0cstdcl_get_dpid(dcd))
  val sres = d0cstdcl_get_sres(dcd)
in
  ps(out, "@static"); nl(out);
  ps(out, "let "); ps(out, fname(nm)); ps(out, ": ");
  (case+ sres of
   | S0RESsome(_, se) => pp_s0exp(out, se)
   | S0RESnone() => ps(out, "Void"));
  nl(out)
end
//
fun
pp_dynconst(out: FILR, tok: token, dcds: d0cstdclist): void = let
  val isval = tok_is_val(tok)
  fun loop(out: FILR, first: bool, dcds: d0cstdclist): void =
    case+ dcds of
    | list_nil() => ()
    | list_cons(dcd, rest) => (
        (if first then () else nl(out));
        (if isval then pp_dynconst_val(out, dcd) else pp_dynconst_fun(out, dcd));
        loop(out, false, rest)
      )
in
  loop(out, true, dcds)
end
//
(* ****** ****** *)
//
// ====================== t0maglst (parametric abstype/typedef args) =========
//
// the parametric arg group `(x0:t0)` of `#abstbox T(x0:t0)` / `#typedef T(x0:t0)`.
// Each T0MAGlist holds t0args; we render the binder names as `[X0]` typarams.
//
// synthesize positional typaram names X0, X1, ... (the ATS parametric binder is
// `(x0:t0)`; we don't reuse its lowercase name, we emit a capitalized typaram).
fun xname(i: sint): strn = PYPP_xname(i)
//
fun
tag_count(tags: t0arglst): sint =
  (case+ tags of list_nil() => 0 | list_cons(_, r) => 1 + tag_count(r))
fun
sarg_count(sargs: s0arglst): sint =
  (case+ sargs of list_nil() => 0 | list_cons(_, r) => 1 + sarg_count(r))
//
fun
gen_xnames(i: sint, n: sint): list(strn) =
  if i >= n then list_nil() else list_cons(xname(i), gen_xnames(i+1, n))
//
fun
pp_tmag_names(tmas: t0maglst): list(strn) =
(
  case+ tmas of
  | list_nil() => list_nil()
  | list_cons(tm, rest) => (
      case+ tm.node() of
      | T0MAGlist(_, tags, _) => list_append(gen_xnames(0, tag_count(tags)), pp_tmag_names(rest))
      | T0MAGnone(_) => pp_tmag_names(rest)
    )
)
//
// the s0maglst form (used by #typedef's parametric args, e.g. tmpmap(x0:t0)).
fun
pp_smag_names(smas: s0maglst): list(strn) =
(
  case+ smas of
  | list_nil() => list_nil()
  | list_cons(sm, rest) => (
      case+ sm.node() of
      | S0MAGlist(_, sargs, _) => list_append(gen_xnames(0, sarg_count(sargs)), pp_smag_names(rest))
      | S0MAGsing(_) => list_cons(xname(0), pp_smag_names(rest))
      | S0MAGnone(_) => pp_smag_names(rest)
    )
)
//
(* ****** ****** *)
//
// ====================== DYNAMIC side: indentation =========================
//
// a Python suite is an INDENT block. We thread an indent level (number of 4-space
// units); `ind` emits the leading whitespace.  This is the only state the dynamic
// walkers carry (the AST is otherwise positional).
//
fun
ind(out: FILR, n: sint): void =
  if n <= 0 then () else (ps(out, "    "); ind(out, n-1))
//
(* ****** ****** *)
//
// ====================== DYNAMIC side: d0pat ===============================
//
// a pattern. Constructor names capitalize ONLY if file-local (conname_scoped);
// prelude cons (list_cons/list_nil) stay verbatim. Variables/wildcards verbatim.
//
fun
pp_d0pat(out: FILR, dp: d0pat): void =
(
  case+ dp.node() of
  //
  // a bare id: a variable pattern, or a nullary con. We treat lexeme via
  // conname_scoped (file-local cons capitalize; `_` wildcard + vars pass through).
  | D0Pid0(id) => ps(out, conname_scoped(i0dnt_lexeme(id)))
  //
  | D0Pint(t0) => (case+ t0 of T0INTsome(t) => ps(out, tok_lexeme(t)) | T0INTnone(t) => ps(out, tok_lexeme(t)))
  | D0Pstr(t0) => (case+ t0 of T0STRsome(t) => ps(out, tok_lexeme(t)) | T0STRnone(t) => ps(out, tok_lexeme(t)))
  | D0Pchr(t0) => (case+ t0 of T0CHRsome(t) => ps(out, tok_lexeme(t)) | T0CHRnone(t) => ps(out, tok_lexeme(t)))
  | D0Pflt(t0) => (case+ t0 of T0FLTsome(t) => ps(out, tok_lexeme(t)) | T0FLTnone(t) => ps(out, tok_lexeme(t)))
  //
  // a constructor application `CON(p, ...)` — the apps list is [head; (args)].
  | D0Papps(dps) => pp_dpat_apps(out, dps)
  //
  // a parenthesized group / tuple of patterns.
  | D0Plpar(_, dps, _) => (
      case+ dps of
      | list_cons(dp1, list_nil()) => pp_d0pat(out, dp1)
      | _ => pp_dpat_tuple(out, dps))
  | D0Ptup1(_, _, dps, _) => pp_dpat_tuple(out, dps)
  //
  // `p as x` — render as `p as x` (our surface accepts as-patterns).
  | D0Paspt(_, dp1) => (ps(out, "_ as "); pp_d0pat(out, dp1))
  //
  // annotation `p: T` — drop the annot (the body context supplies the type).
  | D0Pannot(dp1, _) => pp_d0pat(out, dp1)
  | D0Pqual0(_, dp1) => pp_d0pat(out, dp1)
  //
  | _ => ps(out, "# TODO(pp): d0pat")
)
// a constructor-pattern apps list: head con + paren arg-groups.
and
pp_dpat_apps(out: FILR, dps: d0patlst): void =
(
  case+ dps of
  | list_nil() => ()
  | list_cons(hd, rest) => (
      pp_d0pat(out, hd);
      pp_dpat_apps_args(out, rest))
)
and
pp_dpat_apps_args(out: FILR, dps: d0patlst): void =
(
  case+ dps of
  | list_nil() => ()
  | list_cons(dp, rest) => (
      (case+ dp.node() of
       | D0Plpar(_, args, _) => (ps(out, "("); pp_dpat_seq(out, args); ps(out, ")"))
       | _ => (ps(out, "("); pp_d0pat(out, dp); ps(out, ")")));
      pp_dpat_apps_args(out, rest))
)
and
pp_dpat_seq(out: FILR, dps: d0patlst): void =
(
  case+ dps of
  | list_nil() => ()
  | list_cons(dp, rest) => (
      pp_d0pat(out, dp);
      (case+ rest of list_nil() => () | _ => ps(out, ", "));
      pp_dpat_seq(out, rest))
)
and
pp_dpat_tuple(out: FILR, dps: d0patlst): void =
  (ps(out, "("); pp_dpat_seq(out, dps); ps(out, ")"))
//
(* ****** ****** *)
//
// ====================== DYNAMIC side: d0exp ===============================
//
// a dynamic expression. The two FORMS:
//   * pp_d0exp_inline : render the expression INLINE (one line; no suite). For
//       atoms, applications, con-apps, tuples, ref get/set, qual/annot.
//   * pp_d0exp_suite  : render the expression as a `:`-SUITE BODY at indent `n`
//       (each statement on its own indented line). Handles let/case/if/seq, and
//       falls back to `ind(); inline; nl()` for an atom-bodied function.
//
// INLINE expression (no newline; used as an rvalue or call argument).
//
fun
pp_d0exp_inline(out: FILR, de: d0exp): void =
(
  case+ de.node() of
  //
  | D0Eid0(id) => ps(out, conname_scoped(i0dnt_lexeme(id)))
  | D0Eopid(oid) => pp_d0eid(out, oid)
  //
  | D0Eint(t0) => (case+ t0 of T0INTsome(t) => ps(out, tok_lexeme(t)) | T0INTnone(t) => ps(out, tok_lexeme(t)))
  | D0Estr(t0) => (case+ t0 of T0STRsome(t) => ps(out, tok_lexeme(t)) | T0STRnone(t) => ps(out, tok_lexeme(t)))
  | D0Echr(t0) => (case+ t0 of T0CHRsome(t) => ps(out, tok_lexeme(t)) | T0CHRnone(t) => ps(out, tok_lexeme(t)))
  | D0Eflt(t0) => (case+ t0 of T0FLTsome(t) => ps(out, tok_lexeme(t)) | T0FLTnone(t) => ps(out, tok_lexeme(t)))
  //
  // application / con-application: head then paren arg-groups.
  | D0Eapps(des) => pp_dexp_apps(out, des)
  //
  // a parenthesized / sequence group.  A single-elem paren -> that elem; a
  // SMCLN-sequence (cons2) at expression position -> a (a; b) we render inline
  // as a comma-paren only when used as an rvalue is wrong — but inside an INLINE
  // ref-set rhs the corpus never nests a sequence, so a single-elem is the norm.
  | D0Elpar(_, des, rp) => (
      case+ des of
      | list_cons(de1, list_nil()) => pp_d0exp_inline(out, de1)
      | _ => (ps(out, "("); pp_dexp_seq_inline(out, des); ps(out, ")")))
  //
  // a tuple `@(a, b)` / `(a, b)`.
  | D0Etup1(_, _, des, _) => (ps(out, "("); pp_dexp_seq_inline(out, des); ps(out, ")"))
  //
  // the ref-cell deref `r[]` (empty bracket).  D0Ebrckt(LB, [], RB) on an id head
  // is parsed as an APPS [id; brckt]; a STANDALONE brckt has an empty arg list.
  | D0Ebrckt(_, des, _) => (
      case+ des of
      | list_nil() => ps(out, "[]")
      | _ => (ps(out, "["); pp_dexp_seq_inline(out, des); ps(out, "]")))
  //
  | D0Eannot(de1, _) => pp_d0exp_inline(out, de1)
  | D0Equal0(_, de1) => pp_d0exp_inline(out, de1)
  //
  | _ => ps(out, "# TODO(pp): d0exp-inline")
)
// the d0eid (an operator-as-id) — a bare i0dnt (d0eid = i0dnt_tbox).
and
pp_d0eid(out: FILR, oid: d0eid): void = ps(out, fname(i0dnt_lexeme(oid)))
// an application apps-list: head then paren/bracket arg-groups. The HEAD is a con
// or a function id; trailing `[]` brackets are ref-derefs (`r[]`); trailing `(..)`
// are call/con args.
and
pp_dexp_apps(out: FILR, des: d0explst): void =
(
  case+ des of
  | list_nil() => ()
  | list_cons(hd, rest) => (
      pp_d0exp_inline(out, hd);
      pp_dexp_apps_args(out, rest))
)
and
pp_dexp_apps_args(out: FILR, des: d0explst): void =
(
  case+ des of
  | list_nil() => ()
  | list_cons(de, rest) => (
      (case+ de.node() of
       | D0Ebrckt(_, args, _) => (
           case+ args of
           | list_nil() => ps(out, "[]")
           | _ => (ps(out, "["); pp_dexp_seq_inline(out, args); ps(out, "]")))
       | D0Elpar(_, args, _) => (ps(out, "("); pp_dexp_seq_inline(out, args); ps(out, ")"))
       | D0Etup1(_, _, args, _) => (ps(out, "("); pp_dexp_seq_inline(out, args); ps(out, ")"))
       | _ => (ps(out, "("); pp_d0exp_inline(out, de); ps(out, ")")));
      pp_dexp_apps_args(out, rest))
)
and
pp_dexp_seq_inline(out: FILR, des: d0explst): void =
(
  case+ des of
  | list_nil() => ()
  | list_cons(de, rest) => (
      pp_d0exp_inline(out, de);
      (case+ rest of list_nil() => () | _ => ps(out, ", "));
      pp_dexp_seq_inline(out, rest))
)
//
(* ****** ****** *)
//
// the SUITE form: emit `de` as the indented body of a `def`/`case`/`let`. The
// `n` indent is for THIS body. The forms that become a multi-line suite:
//   let val+ P = e1 in e2 end -> `let P = e1` (newline) then e2-suite
//   case- X of | p => e       -> `match X:` then each `case p:` + e-suite
//   if c then t else e        -> `if c:` t-suite `else:` e-suite
//   (a; b)                    -> each elem as its own statement line
//   anything else (an atom)   -> `ind(); inline; nl()`
//
fun
pp_d0exp_suite(out: FILR, n: sint, de: d0exp): void =
(
  case+ de.node() of
  //
  // a let-binding suite. The L0 `let DECLS in BODY end` -> emit each decl, then
  // the body. The decls are d0eclist (here: val-bindings `val+ P = e`).
  | D0Elet0(_, decls, _, body, _) => (
      pp_dexp_letdecls(out, n, decls);
      pp_dexp_body_seq(out, n, body))
  //
  // a `case[+-] X of | p => e | ...` -> `match X:` then arms.
  | D0Ecas0(_, scrut, _, _, cls) => pp_dexp_match(out, n, scrut, cls)
  | D0Ecas1(_, scrut, _, _, cls, _) => pp_dexp_match(out, n, scrut, cls)
  //
  // `if c then t else e`.
  | D0Eift0(_, c, th, el) => pp_dexp_if(out, n, c, th, el)
  | D0Eift1(_, c, th, el, _) => pp_dexp_if(out, n, c, th, el)
  //
  // a `(a; b; ...)` SMCLN-sequence -> each on its own statement line.  The parse
  // SPLITS at the FIRST `;`: D0Elpar's d0explst holds the part BEFORE `;`, and the
  // RPAREN_cons2 holds the part AFTER (a comma-list).  We APPEND the two so every
  // statement appears (the last across both lists is the value -> a suite).
  | D0Elpar(_, des, rp) => (
      case+ rp of
      | d0exp_RPAREN_cons2(_, des2, _) => pp_dexp_stmts(out, n, list_append(des, des2))
      | _ => (
          case+ des of
          | list_cons(de1, list_nil()) => pp_d0exp_suite(out, n, de1)
          | _ => pp_dexp_stmts(out, n, des)))
  //
  | D0Eannot(de1, _) => pp_d0exp_suite(out, n, de1)
  | D0Equal0(_, de1) => pp_d0exp_suite(out, n, de1)
  //
  // a ref-set `r[] := e` is an APPS with `:=` — detected in pp_dexp_stmt. As a
  // whole-body it is a single statement.
  | _ => (ind(out, n); pp_dexp_stmt_inline(out, de); nl(out))
)
//
// a SUITE-as-list-of-statements (the (a; b; ...) sequence, or a let-body).
and
pp_dexp_stmts(out: FILR, n: sint, des: d0explst): void =
(
  case+ des of
  | list_nil() => ()
  | list_cons(de, rest) => (
      (case+ rest of
       // the LAST elem of a sequence is the value — render as a (possibly multi-
       // line) suite (it may itself be a match/let). Non-last elems are statements.
       | list_nil() => pp_d0exp_suite(out, n, de)
       | _ => (ind(out, n); pp_dexp_stmt_inline(out, de); nl(out)));
      pp_dexp_stmts(out, n, rest))
)
//
// the body of a let after its decls: it can be a sequence or a single expr.
and
pp_dexp_body_seq(out: FILR, n: sint, des: d0explst): void =
(
  case+ des of
  | list_cons(de1, list_nil()) => pp_d0exp_suite(out, n, de1)
  | _ => pp_dexp_stmts(out, n, des)
)
//
// a single STATEMENT rendered inline: special-cases the ref-set `r[] := e`
// (an apps whose 2nd elem is the `:=` op), else a bare inline expr.
and
pp_dexp_stmt_inline(out: FILR, de: d0exp): void =
(
  case+ de.node() of
  | D0Eapps(des) => pp_dexp_stmt_apps(out, des)
  | _ => pp_d0exp_inline(out, de)
)
// detect `lhs[] := rhs` : the apps list is [lhs; D0Ebrckt([]); :=; rhs ...]. The
// `:=` shows up as a D0Eid0/D0Eopid `:=`. We render lhs + `[] := ` + rhs.
and
pp_dexp_stmt_apps(out: FILR, des: d0explst): void =
(
  if dexp_apps_has_assign(des)
  then pp_dexp_assign(out, des)
  else pp_dexp_apps(out, des)
)
// does this apps-list contain a `:=` infix op? (a ref-set).
and
dexp_apps_has_assign(des: d0explst): bool =
(
  case+ des of
  | list_nil() => false
  | list_cons(de, rest) => (
      if dexp_is_assign_op(de) then true else dexp_apps_has_assign(rest))
)
and
dexp_is_assign_op(de: d0exp): bool =
(
  case+ de.node() of
  | D0Eid0(id) => strn_eq(i0dnt_lexeme(id), ":=")
  | D0Eopid(oid) => strn_eq(i0dnt_lexeme(oid), ":=")
  | _ => false
)
// render `LHS... := RHS...` : everything before `:=` is the lhs apps, everything
// after is the rhs apps. (lhs is e.g. `the_drpth_ref[]`.)
and
pp_dexp_assign(out: FILR, des: d0explst): void = let
  fun
  loop_lhs(out: FILR, des: d0explst): d0explst =
    case+ des of
    | list_nil() => list_nil()
    | list_cons(de, rest) => (
        if dexp_is_assign_op(de)
        then rest
        else loop_lhs(out, rest))  // rhs continuation
  // emit lhs apps up to (not including) `:=`
  fun
  emit_lhs(out: FILR, des: d0explst): void =
    case+ des of
    | list_nil() => ()
    | list_cons(de, rest) => (
        if dexp_is_assign_op(de) then ()
        else (
          (case+ de.node() of
           | D0Ebrckt(_, args, _) => (
               case+ args of
               | list_nil() => ps(out, "[]")
               | _ => (ps(out, "["); pp_dexp_seq_inline(out, args); ps(out, "]")))
           | _ => pp_d0exp_inline(out, de));
          emit_lhs(out, rest)))
in let
  val rhs = loop_lhs(out, des)
in
  emit_lhs(out, des);
  ps(out, " := ");
  pp_dexp_rhs(out, rhs)
end end
// the rhs of `:=` is an apps tail (head + args): re-use the apps renderer but the
// head is the first elem, args follow.
and
pp_dexp_rhs(out: FILR, des: d0explst): void = pp_dexp_apps(out, des)
//
(* ****** ****** *)
//
// the let-decls (val+ P = e bindings) of a `let ... in` -> `let P = e` lines.
//
and
pp_dexp_letdecls(out: FILR, n: sint, decls: d0eclist): void =
(
  case+ decls of
  | list_nil() => ()
  | list_cons(dc, rest) => (
      pp_dexp_letdecl(out, n, dc);
      pp_dexp_letdecls(out, n, rest))
)
and
pp_dexp_letdecl(out: FILR, n: sint, dc: d0ecl): void =
(
  case+ dc.node() of
  // a `val+ P = e` / `val P = e` value binding -> `let P = e` (or just the stmt
  // if P is the void pattern `()` — a side-effecting binding).
  | D0Cvaldclst(_, vds) => pp_dexp_valdcls(out, n, vds)
  | _ => (ind(out, n); todo(out, "let-decl"))
)
and
pp_dexp_valdcls(out: FILR, n: sint, vds: d0valdclist): void =
(
  case+ vds of
  | list_nil() => ()
  | list_cons(vd, rest) => (
      pp_dexp_valdcl(out, n, vd);
      pp_dexp_valdcls(out, n, rest))
)
and
pp_dexp_valdcl(out: FILR, n: sint, vd: d0valdcl): void = let
  val dpat = d0valdcl_get_dpat(vd)
  val tdxp = d0valdcl_get_tdxp(vd)
in
  case+ tdxp of
  | TEQD0EXPsome(_, rhs) => (
      // a void-pattern binding `val () = e` (a side-effecting statement) -> emit e
      // as a bare statement (no `let () =`).
      if dpat_is_void(dpat)
      then (ind(out, n); pp_dexp_stmt_inline(out, rhs); nl(out))
      else (
        ind(out, n); ps(out, "let "); pp_d0pat(out, dpat); ps(out, " = ");
        pp_d0exp_inline(out, rhs); nl(out)))
  | TEQD0EXPnone() => (ind(out, n); todo(out, "valdcl-no-rhs"))
end
// is the pattern the void/unit pattern `()` (an empty paren group)?
and
dpat_is_void(dp: d0pat): bool =
(
  case+ dp.node() of
  | D0Plpar(_, list_nil(), _) => true
  | _ => false
)
//
(* ****** ****** *)
//
// a `match X:` from `case- X of | p => e | ...`.
//
and
pp_dexp_match(out: FILR, n: sint, scrut: d0exp, cls: d0clslst): void = (
  ind(out, n); ps(out, "match "); pp_d0exp_inline(out, scrut); ps(out, ":"); nl(out);
  pp_dexp_clauses(out, n+1, cls)
)
and
pp_dexp_clauses(out: FILR, n: sint, cls: d0clslst): void =
(
  case+ cls of
  | list_nil() => ()
  | list_cons(cl, rest) => (
      pp_dexp_clause(out, n, cl);
      pp_dexp_clauses(out, n, rest))
)
and
pp_dexp_clause(out: FILR, n: sint, cl: d0cls): void =
(
  case+ cl.node() of
  | D0CLScls(gpt, _, body) => (
      ind(out, n); ps(out, "case ");
      pp_dexp_gpt(out, gpt); ps(out, ":"); nl(out);
      pp_d0exp_suite(out, n+1, body))
  | D0CLSgpt(gpt) => (
      ind(out, n); ps(out, "case ");
      pp_dexp_gpt(out, gpt); ps(out, ":"); nl(out);
      ind(out, n+1); todo(out, "empty match-arm body"))
)
// the guarded-pattern of a match arm: a plain pattern, or `p when guards`.
and
pp_dexp_gpt(out: FILR, gpt: d0gpt): void =
(
  case+ gpt.node() of
  | D0GPTpat(dp) => pp_d0pat(out, dp)
  | D0GPTgua(dp, _, _) => (pp_d0pat(out, dp); ps(out, " # TODO(pp): when-guard"))
)
//
(* ****** ****** *)
//
// an `if c: t else: e`.
//
and
pp_dexp_if(out: FILR, n: sint, c: d0exp, th: d0exp_THEN, el: d0exp_ELSE): void = (
  ind(out, n); ps(out, "if "); pp_d0exp_inline(out, c); ps(out, ":"); nl(out);
  (case+ th of
   | d0exp_THEN_some(_, te) => pp_d0exp_suite(out, n+1, te)
   | d0exp_THEN_none(_) => (ind(out, n+1); todo(out, "if-then-empty")));
  (case+ el of
   | d0exp_ELSE_some(_, ee) => (
       ind(out, n); ps(out, "else:"); nl(out);
       pp_d0exp_suite(out, n+1, ee))
   | d0exp_ELSE_none(_) => ())
)
//
(* ****** ****** *)
//
// ====================== DYNAMIC side: datatype ============================
//
// `datatype drpth = DRPTH of (strn)`  ->  `enum Drpth:` / `case DRPTH(strn)`.
// We register `drpth` (type) + `DRPTH` (con) as file-local FIRST (so they
// capitalize), then emit. The cons' arg-types render via pp_s0exp (prelude field
// types like `strn` stay lowercase).
//
fun
register_d0typ_names(dts: d0typlst): void =
(
  case+ dts of
  | list_nil() => ()
  | list_cons(dt, rest) => (
      (case+ dt.node() of
       | D0TYPnode(nm, _, _, _, tcns) => (
           PYPP_local_add(i0dnt_lexeme(nm));
           register_d0tcn_names(tcns)));
      register_d0typ_names(rest))
)
and
register_d0tcn_names(tcns: d0tcnlst): void =
(
  case+ tcns of
  | list_nil() => ()
  | list_cons(tcn, rest) => (
      (case+ tcn.node() of
       | D0TCNnode(_, nm, _, _) => PYPP_local_add(i0dnt_lexeme(nm)));
      register_d0tcn_names(rest))
)
//
fun
pp_d0typ_enum(out: FILR, n: sint, dt: d0typ): void =
(
  case+ dt.node() of
  | D0TYPnode(nm, _tmas, _, _, tcns) => (
      ind(out, n); ps(out, "enum "); ps(out, tyname_scoped(i0dnt_lexeme(nm)));
      ps(out, ":"); nl(out);
      pp_d0tcns(out, n+1, tcns))
)
and
pp_d0tcns(out: FILR, n: sint, tcns: d0tcnlst): void =
(
  case+ tcns of
  | list_nil() => ()
  | list_cons(tcn, rest) => (
      pp_d0tcn(out, n, tcn);
      pp_d0tcns(out, n, rest))
)
and
pp_d0tcn(out: FILR, n: sint, tcn: d0tcn): void =
(
  // D0TCNnode(s0us, dcon, s0is(*indices*), s0expopt(*of-type*)). The constructor
  // FIELD TYPE is the 4th field — the `of (T)` argument (an s0exp, paren-wrapped
  // for a single field or a tuple).  s0is is the (here empty) index list.
  case+ tcn.node() of
  | D0TCNnode(_, nm, _s0is, ofty) => (
      ind(out, n); ps(out, "case "); ps(out, conname_scoped(i0dnt_lexeme(nm)));
      (case+ ofty of
       | optn_cons(se) => (ps(out, "("); pp_tcon_argty(out, se); ps(out, ")"))
       | optn_nil() => ());
      nl(out))
)
// the `of` argument type of a constructor.  A paren-group `(strn)` renders its
// inner element(s); a tuple `(a, b)` renders comma-separated.  pp_s0exp already
// unwraps S0Elpar/S0Etup1, but here we want the BARE element list (no extra
// parens, since we already emitted the enclosing `(...)`).
and
pp_tcon_argty(out: FILR, se: s0exp): void =
(
  case+ se.node() of
  | S0Elpar(_, ses, _) => pp_s0exp_seq(out, ses)
  | S0Etup1(_, _, ses, _) => pp_s0exp_seq(out, ses)
  | _ => pp_s0exp(out, se)
)
//
(* ****** ****** *)
//
// ====================== DYNAMIC side: #implfun (fundcl) ===================
//
// `#implfun f(args) = body`  parses to a D0Cfundclst(FUN, _, [d0fundcl]).  Each
// d0fundcl has dpid (name), farg (f0arglst), and tdxp (the `= body`).  We emit
//   `@impl def f(params): <body-suite>`
// with UNANNOTATED params (the .dats carries no param types — they are inferred,
// which the frontend's inline-implement path accepts at nerror=0).
//
fun
pp_fundcl_impl(out: FILR, n: sint, fd: d0fundcl): void = let
  val nm   = i0dnt_lexeme(d0fundcl_get_dpid(fd))
  val farg = d0fundcl_get_farg(fd)
  val tdxp = d0fundcl_get_tdxp(fd)
in
  ind(out, n); ps(out, "@impl def "); ps(out, fname(nm));
  pp_farg_params(out, farg);
  ps(out, ":"); nl(out);
  (case+ tdxp of
   | TEQD0EXPsome(_, body) => pp_d0exp_suite(out, n+1, body)
   | TEQD0EXPnone() => (ind(out, n+1); todo(out, "impl-no-body")))
end
// the (params) of a fun arg-list. Each f0arg is F0ARGdapp(d0pat); the d0pat is a
// paren-group of the params (or a single).  F0ARGsapp `{a:t0}` would be a typaram
// bracket; the corpus impls have none.
and
pp_farg_params(out: FILR, farg: f0arglst): void = (
  ps(out, "(");
  pp_farg_dapps(out, 0, farg);
  ps(out, ")")
)
and
pp_farg_dapps(out: FILR, i: sint, farg: f0arglst): void =
(
  case+ farg of
  | list_nil() => ()
  | list_cons(fa, rest) => (
      case+ fa.node() of
      | F0ARGdapp(dp) => pp_farg_one(out, dp, rest)
      | _ => pp_farg_dapps(out, i, rest))   // skip sta-args/metrics (no corpus use)
)
// a single f0arg's d0pat: a paren-group `(a, b)` -> a,b ; `()` -> nothing ;
// a bare id -> that id.
and
pp_farg_one(out: FILR, dp: d0pat, rest: f0arglst): void =
(
  case+ dp.node() of
  | D0Plpar(_, dps, _) => pp_dpat_seq(out, dps)
  | D0Ptup1(_, _, dps, _) => pp_dpat_seq(out, dps)
  | _ => pp_d0pat(out, dp)
)
//
(* ****** ****** *)
//
// ====================== DYNAMIC side: `local` -> private: =================
//
// `local D1 in D2 end` -> `private:` block (D1) + capture-rest (D2). The walkers
// pp_local / pp_priv_head / pp_fundcl_impl_list / pp_topval are part of the single
// mutually-recursive group with pp_d0ecl + pp_walk (defined at the dispatch below),
// because pp_local recurses through pp_walk -> pp_d0ecl -> pp_local.
//
(* ****** ****** *)
//
// pre-scan a d0eclist for datatype names to register as file-local (recurses into
// `local` heads + bodies so cons defined anywhere capitalize at every use site).
//
fun
register_file_local_names(dcs: d0eclist): void =
(
  case+ dcs of
  | list_nil() => ()
  | list_cons(dc, rest) => (
      (case+ dc.node() of
       | D0Cdatatype(_, dts, _) => register_d0typ_names(dts)
       | D0Clocal0(_, head, _, body, _) => (
           register_file_local_names(head);
           register_file_local_names(body))
       | _ => ());
      register_file_local_names(rest))
)
//
(* ****** ****** *)
//
// ====================== top-level decl dispatch ============================
//
fun
pp_d0ecl(out: FILR, dc: d0ecl): bool = // returns: did we emit something?
(
  case+ dc.node() of
  //
  // `local D1 in D2 end`  ->  `private:` (D1) + capture-rest (D2).
  | D0Clocal0(_, head, _, body, _) => (pp_local(out, head, body); true)
  //
  // a top-level `datatype` -> an `enum` (capitalize the type + cons).
  | D0Cdatatype(_, dts, _) => (pp_d0typ_enum_list(out, 0, dts); true)
  //
  // `#implfun f(args) = body`  ->  `@impl def f(args): body`.  `#implfun` lexes to
  // T_IMPLMNT(IMPLfun) and parses to D0Cimplmnt0 (the implement decl): name (d0qid),
  // f0arglst (params), s0res, and the d0exp body.
  | D0Cimplmnt0(_, _, _, dqi, _, farg, _, _, body) => (pp_impl(out, dqi, farg, body); true)
  // a local fun-decl-with-body (`fun f(x) = e`) also reaches here as D0Cfundclst.
  | D0Cfundclst(_, _, fds) => (pp_fundcl_impl_list(out, fds); true)
  //
  // a top-level value binding (`val name = e`) -> `@static let name = e`.
  | D0Cvaldclst(_, vds) => (pp_topval(out, vds); true)
  //
  // `#staload "x"` (a .sats interface) -> a deferred-import comment (the abstract
  // type interface; for THIS standalone round-trip the rep is in-file).
  | D0Cstaload(_, _, ge) => (
      ps(out, "# staload "); pp_g0exp(out, ge); ps(out, "  (TODO: import)"); nl(out); true)
  //
  // #abstype T <= REP / #abstbox T(x0:t0)  ->  @abstract type T[X0] <= REP
  | D0Cabstype(_, sid, tmas, _, tdef) => let
      val nm = tyname(i0dnt_lexeme(sid))
      val tps = pp_tmag_names(tmas)
    in
      ps(out, "@abstract"); nl(out);
      ps(out, "type "); ps(out, nm);
      pp_names_brkt(out, tps);
      (case+ tdef of
       | A0TDFlteq(_, se) => (ps(out, " <= "); pp_s0exp(out, se))
       | A0TDFeqeq(_, se) => (ps(out, " <= "); pp_s0exp(out, se))
       | A0TDFsome() => ());
      nl(out);
      true
    end
  //
  // #typedef A = B   ->   type A = B   (with parametric [X0] if present)
  | D0Csexpdef(_, sid, smas, _, _, se) => let
      val nm = tyname(i0dnt_lexeme(sid))
      val tps = pp_smag_names(smas)
    in
      ps(out, "type "); ps(out, nm);
      pp_names_brkt(out, tps);
      ps(out, " = "); pp_s0exp(out, se); nl(out);
      true
    end
  //
  // bodyless val / fun (in a .sats interface)  ->  @static let / @extern def
  | D0Cdynconst(tok, _, dcds) => (pp_dynconst(out, tok, dcds); true)
  //
  // #symload NAME with FN [of prec]  ->  @overload NAME = FN
  | D0Csymload(_, sym, _, dqi, _) => let
      val nm  = fname(s0ymb_lexeme(sym))
      val tgt = fname(d0qid_lexeme(dqi))
    in
      ps(out, "@overload "); ps(out, nm); ps(out, " = "); ps(out, tgt); nl(out);
      true
    end
  //
  // #define NAME val  ->  @static let NAME = val   (a module-level binding; the
  // @static marker mirrors the hand-translation so it lowers as a static const,
  // not a bare top-level fun-decl).
  | D0Cdefine(_, gid, _, gedf) => let
      val nm = fname(i0dnt_lexeme(gid))
    in
      ps(out, "@static"); nl(out);
      ps(out, "let "); ps(out, nm); ps(out, " = ");
      (case+ gedf of
       | G0EDFsome(_, ge) => pp_g0exp(out, ge)
       | G0EDFnone() => ps(out, "()"));
      nl(out);
      true
    end
  //
  // #include "x"  ->  a deferred-construct comment marker.
  | D0Cinclude(_, _, ge) => (
      ps(out, "# include "); pp_g0exp(out, ge); ps(out, "  (TODO: import)"); nl(out);
      true
    )
  //
  // a trailing parser-skip token (e.g. EOF region / comment-only tail) — silent.
  | D0Ctkerr(_) => false
  | D0Ctkskp(_) => false
  //
  // anything else in scope-but-unmapped: a VISIBLE gap marker.
  | _ => (todo(out, "unmapped d0ecl"); true)
)
//
// a g0exp (the #define value / #include path). Literals + ids only (corpus).
and
pp_g0exp(out: FILR, ge: g0exp): void =
(
  case+ ge.node() of
  | G0Eid0(id) => ps(out, fname(i0dnt_lexeme(id)))
  | G0Eint(t0) => (case+ t0 of T0INTsome(tok) => ps(out, tok_lexeme(tok)) | T0INTnone(tok) => ps(out, tok_lexeme(tok)))
  | G0Estr(t0) => (case+ t0 of T0STRsome(tok) => ps(out, tok_lexeme(tok)) | T0STRnone(tok) => ps(out, tok_lexeme(tok)))
  | _ => ps(out, "# TODO(pp): g0exp")
)
//
(* ****** ****** *)
//
// walk the top-level decl list; a blank line AFTER each emitting decl (a Python-
// tolerant, peek-free separation — empty lines are insignificant at top level).
//
and
pp_walk(out: FILR, dcs: d0eclist): void =
(
  case+ dcs of
  | list_nil() => ()
  | list_cons(dc, rest) => let
      val emitted = pp_d0ecl(out, dc)
      val () = (if emitted then nl(out) else ())
    in
      pp_walk(out, rest)
    end
)
//
// `local D1 in D2 end` -> `private:` (D1) then D2 at the SAME (outer) level — the
// capture-rest lowering (D2Clocal0).  File-local names are pre-registered ONCE at
// the entry (register_file_local_names), so cons used in D2 bodies capitalize.
//
and
pp_local(out: FILR, head: d0eclist, body: d0eclist): void = (
  ps(out, "private:"); nl(out);
  pp_priv_head(out, 1, head);
  nl(out);
  pp_walk(out, body)
)
and
// the HEAD of a local: datatypes -> enum; val-bindings -> `let`; #absimpl -> TODO.
pp_priv_head(out: FILR, n: sint, head: d0eclist): void =
(
  case+ head of
  | list_nil() => ()
  | list_cons(dc, rest) => (
      pp_priv_head_one(out, n, dc);
      pp_priv_head(out, n, rest))
)
and
pp_priv_head_one(out: FILR, n: sint, dc: d0ecl): void =
(
  case+ dc.node() of
  | D0Cdatatype(_, dts, _) => pp_d0typ_enum_list(out, n, dts)
  | D0Cvaldclst(_, vds) => pp_priv_valdcls(out, n, vds)
  // #absimpl X = T (abstract-type impl) — implements a type DECLARED in the .sats;
  // standalone (no interface) it cannot typecheck, so we mark it a VISIBLE gap.
  | D0Cabsimpl(_, _, _, _, _, _) => (
      ind(out, n); todo(out, "#absimpl (abstract-type impl needs the .sats interface)"))
  | _ => (ind(out, n); todo(out, "private-head decl"))
)
and
pp_priv_valdcls(out: FILR, n: sint, vds: d0valdclist): void =
(
  case+ vds of
  | list_nil() => ()
  | list_cons(vd, rest) => (
      pp_dexp_valdcl(out, n, vd);
      pp_priv_valdcls(out, n, rest))
)
and
pp_d0typ_enum_list(out: FILR, n: sint, dts: d0typlst): void =
(
  case+ dts of
  | list_nil() => ()
  | list_cons(dt, rest) => (
      pp_d0typ_enum(out, n, dt);
      pp_d0typ_enum_list(out, n, rest))
)
and
// `#implfun NAME(params) = body` (a D0Cimplmnt0) -> `@impl def NAME(params): body`.
// Params are UNANNOTATED (the .dats carries no param types; the inline-implement
// path infers them — verified nerror=0). The body is a `:`-suite at indent 1.
pp_impl(out: FILR, dqi: d0qid, farg: f0arglst, body: d0exp): void = (
  ps(out, "@impl def "); ps(out, fname(d0qid_lexeme(dqi)));
  pp_farg_params(out, farg);
  ps(out, ":"); nl(out);
  pp_d0exp_suite(out, 1, body)
)
and
// the body of `#implfun` -> `@impl def` (one or more d0fundcl in a list).
pp_fundcl_impl_list(out: FILR, fds: d0fundclist): void =
(
  case+ fds of
  | list_nil() => ()
  | list_cons(fd, rest) => (
      pp_fundcl_impl(out, 0, fd);
      (case+ rest of list_nil() => () | _ => nl(out));
      pp_fundcl_impl_list(out, rest))
)
and
// a TOP-LEVEL `val name = e` binding (outside a local) -> `@static let name = e`.
pp_topval(out: FILR, vds: d0valdclist): void =
(
  case+ vds of
  | list_nil() => ()
  | list_cons(vd, rest) => (
      (ps(out, "@static"); nl(out); pp_dexp_valdcl(out, 0, vd));
      pp_topval(out, rest))
)
//
(* ****** ****** *)
//
#implfun
pyprint_of_fpath(stadyn, fpath, out) = let
  val dpar = d0parsed_from_fpath(stadyn, fpath)
  val dopt = d0parsed_get_parsed(dpar)
  // CAPITALIZE-SCOPING: the STATIC (.sats) path capitalizes ALL type names
  // (capall=true); the DYNAMIC (.dats) path capitalizes ONLY file-local datatype
  // names, so it first RESETS the registry + PRE-SCANS the decl tree to record
  // them (a datatype defined anywhere — incl. inside a `local` head — capitalizes
  // at every use site; prelude names stay lowercase to resolve against pyrt).
  val () = PYPP_local_reset()
  val () =
    if stadyn >= 1
    then PYPP_capall_set(false)
    else PYPP_capall_set(true)
in
  case+ dopt of
  | ~optn_cons(dcs) => (
      (if stadyn >= 1 then register_file_local_names(dcs) else ());
      pp_walk(out, dcs))
  | ~optn_nil() => todo(out, "parser returned no d0eclist")
end
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyprint.dats]
*)
