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
  // a bare type name (stamp, uint, bool, ...). Capitalize (rule 1).
  | S0Eid0(id) => ps(out, tyname(i0dnt_lexeme(id)))
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
// ====================== top-level decl dispatch ============================
//
fun
pp_d0ecl(out: FILR, dc: d0ecl): bool = // returns: did we emit something?
(
  case+ dc.node() of
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
fun
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
(* ****** ****** *)
//
#implfun
pyprint_of_fpath(stadyn, fpath, out) = let
  val dpar = d0parsed_from_fpath(stadyn, fpath)
  val dopt = d0parsed_get_parsed(dpar)
in
  case+ dopt of
  | ~optn_cons(dcs) => pp_walk(out, dcs)
  | ~optn_nil() => todo(out, "parser returned no d0eclist")
end
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyprint.dats]
*)
