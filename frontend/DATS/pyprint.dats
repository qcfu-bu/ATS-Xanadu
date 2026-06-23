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
**   #include "x"                          -> include "x"   (TEXTUAL inline expansion, NOT a staload)
**
** REWRITE RULES:
**   (1) CAPITALIZE type & data-constructor names (positionally: type exprs,
**       typedef/abstype LHS, result/arg types). FUNCTION/value names stay as-is.
**   (2) `$`-in-ident foo$bar -> Koka-style foo/bar  ($->/).
**   (3) qualified $M.x -> M.x (drop the leading '$', keep the module qualifier).
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
//   PYPP_dollar_fix : rewrite `$`-in-ident to Koka-style `/`.
//   PYPP_xname/PYPP_pname : synthesized positional typaram/param names.
//   PYPP_source_set/PYPP_import_stem : normalize source-relative #staload paths.
#extern fun PYPP_capitalize(s: strn): strn = $extnam()
#extern fun PYPP_dollar_fix(s: strn): strn = $extnam()
#extern fun PYPP_qual_name(s: strn): strn = $extnam()
#extern fun PYPP_value_name(s: strn): strn = $extnam()
#extern fun PYPP_identish(s: strn): bool = $extnam()
#extern fun PYPP_string_literal(s: strn): strn = $extnam()
// synthesized positional names (string-building done in JS to avoid the ATS
// string-append template): "X"+i (a typaram), "a"/"b".../"x"+i (a parameter).
#extern fun PYPP_xname(i: sint): strn = $extnam()
#extern fun PYPP_pname(i: sint): strn = $extnam()
#extern fun PYPP_source_set(s: strn): void = $extnam()
#extern fun PYPP_import_path(raw: strn): strn = $extnam()
// MISC (Cluster E): unquote a `"..."` string lexeme (verbatim content for `initialize "PATH"`).
#extern fun PYPP_unquote(raw: strn): strn = $extnam()
#extern fun PYPP_import_stem(raw: strn): strn = $extnam()
// CAPITALIZE-SCOPING (dynamic side): file-local type/constructor registries. Type aliases must
// capitalize in type position (`key` -> `Key`) without rewriting value variables named `key`.
#extern fun PYPP_local_reset((*0*)): void = $extnam()
#extern fun PYPP_local_add(s: strn): void = $extnam()
#extern fun PYPP_local_has(s: strn): bool = $extnam()
#extern fun PYPP_type_add(s: strn): void = $extnam()
#extern fun PYPP_type_has(s: strn): bool = $extnam()
#extern fun PYPP_type_scope_push((*0*)): void = $extnam()
#extern fun PYPP_type_scope_pop((*0*)): void = $extnam()
#extern fun PYPP_type_rename_push(s: strn): void = $extnam()
#extern fun PYPP_type_rename_pop(s: strn): void = $extnam()
#extern fun PYPP_type_rename_get(s: strn): strn = $extnam()
#extern fun PYPP_con_add(s: strn): void = $extnam()
#extern fun PYPP_con_has(s: strn): bool = $extnam()
#extern fun PYPP_con_maparg_add(con: strn, idx: sint, kind: strn, elem: strn): void = $extnam()
#extern fun PYPP_con_maparg_elem(con: strn, idx: sint, kind: strn): strn = $extnam()
#extern fun PYPP_value_add(s: strn): void = $extnam()
#extern fun PYPP_value_has(s: strn): bool = $extnam()
#extern fun PYPP_binder_push(s: strn): void = $extnam()
#extern fun PYPP_binder_pop(s: strn): void = $extnam()
#extern fun PYPP_binder_has(s: strn): bool = $extnam()
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
  // A SYMBOLIC identifier — rendered VERBATIM from its lexeme. This is the faithful
  // (NOT accidental-fallback) path for the `?` STATIC operator: stock lexes `?` as
  // T_IDSYM("?") (#sexpdef ? = top0_vt_t0), so a static-app head `{?a}` reaches here
  // and emits `?` deliberately, giving the round-trippable `@sapp[?[A]]` the Pythonic
  // parser re-accepts (PT_QMARK -> PyTcon("?",[A]); QMARK-TYPE).
  | T_IDSYM(s) => s
  | T_IDDLR(s) => s     // $name
  | T_IDSRP(s) => s     // #name
  | T_IDQUA(s) => s     // $name.
  | T_IDENT(s) => s
  | T_INT01(s) => s
  | T_INT02(_, s) => s
  | T_INT03(_, s, _) => s
  | T_FLT01(s) => s
  | T_FLT02(_, s) => s
  | T_FLT03(_, s, _) => s
  | T_CHAR1_nil0(s) => s
  | T_CHAR2_char(s) => s
  | T_CHAR3_blsh(s) => s
  | T_STRN1_clsd(s, _) => PYPP_string_literal(s)
  | T_AT0() => "@"
  | T_BAR() => "|"
  | T_CLN() => ":"
  | T_DOT() => "."
  | T_EQ0() => "="
  | T_LT0() => "<"
  | T_GT0() => ">"
  | T_DLR() => "$"
  | T_SRP() => "#"
  | T_EQLT() => "=<"
  | T_EQGT() => "=>"
  | T_LTGT() => "<>"
  | T_GTLT() => "><"
  | T_MSLT() => "-<"
  | T_MSGT() => "->"
  | T_COMMA() => ","
  | T_SMCLN() => ";"
  | T_BSLSH() => "\\"
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
// d0qid (qualified dyn-id): keep the bare name in value position.
fun
d0qid_lexeme(q: d0qid): strn =
(
  case+ q of
  | D0QIDnone(id) => i0dnt_lexeme(id)
  | D0QIDsome(_, id) => i0dnt_lexeme(id)
)
//
// s0qid (qualified static-id): declaration heads still use their bare local name.
fun
s0qid_lexeme(q: s0qid): strn =
(
  case+ q of
  | S0QIDnone(id) => i0dnt_lexeme(id)
  | S0QIDsome(_, id) => i0dnt_lexeme(id)
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
// rule 2: `$`-in-ident -> `/` (Koka-style). Qualified static names preserve the module qualifier
// as `M.x`; only the leading `$` on the qualifier token is removed.
fun rewrite_dollar(s: strn): strn = PYPP_dollar_fix(s)
fun qualname(tok: token): strn =
(
  case+ tok.node() of
  | T_IDQUA(s) => PYPP_qual_name(s)
  | _ => ""
)
//
// a FUNCTION / VALUE name: keep case, but $->/.
fun fname(s: strn): strn = rewrite_dollar(s)
//
// a dynamic VALUE binder/reference name. The Pythonic lexer treats leading
// uppercase as constructor/type-shaped, so uppercase ATS values need a stable
// lower-case escape. Leading `$free`-style names also lose the leading `$`.
fun vname(s: strn): strn = PYPP_value_name(s)
fun vname_bind(s: strn): strn =
  if strn_eq(s, "_") then "_" else let val () = PYPP_value_add(s) in vname(s) end
//
// primitive ATS type names whose Pythonic spellings are not just first-letter capitalization.
fun tyname_primitive(s: strn): strn = let
  val r = rewrite_dollar(s)
in
  if strn_eq(r, "int") then "Int"
  else if strn_eq(r, "sint") then "SInt"
  else if strn_eq(r, "uint") then "UInt"
  else if strn_eq(r, "bool") then "Bool"
  else if strn_eq(r, "strn") then "String"
  else if strn_eq(r, "char") then "Char"
  else if strn_eq(r, "dflt") then "Float"
  else if strn_eq(r, "void") then "Void"
  else r
end
//
// a TYPE name (LHS of typedef/abstype, or a value-name in a value position):
// capitalize + $->/.   (rule 1)
fun tyname(s: strn): strn = PYPP_capitalize(rewrite_dollar(s))
fun tyname_decl(s: strn): strn = let
  val rn = PYPP_type_rename_get(s)
in
  if strn_eq(rn, "") then tyname(s) else rn
end
//
// CAPITALIZE-SCOPING: a name in TYPE position that capitalizes ONLY if it is
// file-local (a datatype defined in THIS file). Primitive ATS names get stable
// Pythonic spellings via tyname_primitive; other prelude/external type names
// (list, optn, ...) stay verbatim so they resolve against the lowercase pyrt.
fun tyname_scoped(s: strn): strn = let
  val rn = PYPP_type_rename_get(s)
  val r = rewrite_dollar(s)
  val p = tyname_primitive(s)
in
  if ~(strn_eq(rn, ""))
  then rn
  else if ~(strn_eq(p, r))
  then p
  else if PYPP_binder_has(s)
  then PYPP_capitalize(r)
  else if PYPP_capall_get()
  then PYPP_capitalize(r)
  else (if PYPP_type_has(s)
        then PYPP_capitalize(r) else r)
end
//
// a data-CONSTRUCTOR name in expr/pattern position: capitalize ONLY if file-local
// (e.g. DRPTH — already upper, but a lowercase file-local con would also lift).
// Prelude cons (list_cons, list_nil, ...) stay verbatim.
fun conname_scoped(s: strn): strn =
  if PYPP_con_has(s) then PYPP_capitalize(rewrite_dollar(s)) else rewrite_dollar(s)
//
fun val_or_con_name(s: strn): strn =
  if PYPP_con_has(s) then PYPP_capitalize(rewrite_dollar(s))
  else if PYPP_value_has(s) then vname(s)
  else rewrite_dollar(s)
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
// a record/projection field label (l0abl): an integer index, a symbolic name, or an
// invalid placeholder token. STANDALONE (not in the pp_* and-chains) so BOTH the static
// (S0Ercd2) and dynamic (D0Ercd2/D0Prcd2) record-field emitters can call it. Placed after
// `ps`/`fname`/`tok_lexeme` so its forward references resolve.
fun
pp_lab0(out: FILR, lab: l0abl): void =
(
  case+ lab.node() of
  | L0ABLsome(l0) => (
      case+ l0 of
      | LABint(i) => gint_fprint$sint(i, out)
      | LABsym(sym) => ps(out, fname(symbl_get_name(sym)))
    )
  | L0ABLnone(tok) => ps(out, tok_lexeme(tok))
)
//
// RECORD-VARIANT prefix decode (Cluster D). The box/flat/linear kind of a record
// `@{..}`/`$rec..{..}`/`#{..}` is packed into the T_TRCD20(n) token int (lexing0.sats:172);
// stock decodes it to a trcdknd (staexp2.dats:1525 s2exp_r1cd / trans23 f0_rcd2):
//   0 = @{}     -> TRCDflt0          (flat / unboxed)     -- our bare `{..}`
//   1 = #{}     -> TRCDbox1          (boxed linear)
//   2 = $rec{}  -> TRCDbox0|1        (boxed, linear-by-field)
//   3 = $rectx{}-> TRCDbox0          (boxed)
//   4 = $recvx{}-> TRCDbox1          (boxed linear / viewtype)
//   5 = $recrf{}-> TRCDbox2          (ref)
// We round-trip the kind via a prefix DECORATOR on the brace literal, reusing the
// existing @boxed/@linear/@unboxed surface vocabulary (SURFACE-GRAMMAR §5.7), extended with
// @vbox (`#{}`, int 1) and @ref (`$recrf`, int 5). The mapping is a BIJECTION on the TRCD20
// int so the RAW token int (which the L2 dump preserves verbatim) round-trips structurally —
// `#{}` (int 1) and `$recvx{}` (int 4) both decode to TRCDbox1 but stay DISTINCT tokens, so
// they need distinct surfaces (@vbox vs @linear). The bare `{..}` stays flat (int 0), keeping
// the existing single record form byte-stable. Placed before pp_s0exp so all three record
// emitters (static / dynamic / pattern) resolve it.
fun
pp_rcd_prefix(out: FILR, tknd: token): void =
(
  case+ tknd.node() of
  | T_TRCD20(0) => ()                       // flat   -> bare `{..}` (default)
  | T_TRCD20(1) => ps(out, "@vbox ")        // #{}    -> TRCDbox1 (the `#`-sigil boxed-linear)
  | T_TRCD20(2) => ps(out, "@rec ")         // $rec   -> boxed-or-linear by field (int 2)
  | T_TRCD20(3) => ps(out, "@boxed ")       // $rectx -> TRCDbox0
  | T_TRCD20(4) => ps(out, "@linear ")      // $recvx -> TRCDbox1 (viewtype)
  | T_TRCD20(5) => ps(out, "@ref ")         // $recrf -> TRCDbox2
  | _ => ()
)
//
fun
g0exp_lexeme(ge: g0exp): strn =
(
  case+ ge.node() of
  | G0Eid0(id) => i0dnt_lexeme(id)
  | G0Eint(t0) => (case+ t0 of T0INTsome(tok) => tok_lexeme(tok) | T0INTnone(tok) => tok_lexeme(tok))
  | G0Estr(t0) => (case+ t0 of T0STRsome(tok) => tok_lexeme(tok) | T0STRnone(tok) => tok_lexeme(tok))
  | _ => "?"
)
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
  // a STRING literal in static position — the argument of `$extype("name")` / `$extbox("name")`,
  // emitted as a quoted Pythonic string (PYPP_string_literal re-quotes/escapes). The lowering of
  // `Extype["name"]`/`Extbox["name"]` recovers the raw name and builds S2Etext.
  | S0Estr(t0) => (
      case+ t0 of
      | T0STRsome(tok) => ps(out, PYPP_string_literal(tok_lexeme(tok)))
      | T0STRnone(tok) => ps(out, PYPP_string_literal(tok_lexeme(tok)))
    )
  // a CHARACTER / FLOAT literal in static position — verbatim lexeme (rare; index literals).
  | S0Echr(t0) => (
      case+ t0 of
      | T0CHRsome(tok) => ps(out, tok_lexeme(tok))
      | T0CHRnone(tok) => ps(out, tok_lexeme(tok))
    )
  | S0Eflt(t0) => (
      case+ t0 of
      | T0FLTsome(tok) => ps(out, tok_lexeme(tok))
      | T0FLTnone(tok) => ps(out, tok_lexeme(tok))
    )
  // a bare quantifier with NO body in the apps spine (e.g. `[a:t0p]` alone) — emit just the prefix.
  // (The common case `[..] T` is an S0Eapps and is handled by pp_apps; this covers the degenerate
  // standalone quantifier so it never falls through to the TODO marker.)
  | S0Eexi0(_, sqs, _) => pp_quant_prefix(out, "exists", sqs)
  | S0Euni0(_, sqs, _) => pp_quant_prefix(out, "forall", sqs)
  //
  // a type application: head followed by paren arg-groups.
  //   tmpmap(itm)            -> Tmpmap[Itm]
  //   strm_vt(@(sint,itm))   -> Strm_vt[(SInt, Itm)]
  //   (postn, FILR) -> void  -> (Postn, FILR) -> Void
  | S0Eapps(ses) => pp_apps(out, ses)
  //
  // a flat / boxed tuple `@(a,b)` / `$(a,b)`  -> (A, B).
  | S0Etup1(_, _, ses, _) => pp_tuple(out, ses)
  //
  // RECORD-VARIANT type `@{x= int, y= int}` / `$rectx{..}` / `$recvx{..}` (Cluster D, S0Ercd2).
  // -> `[@boxed|@linear ]{ x: Int, y: Int }`. The box/flat/linear kind rides the TRCD20 token
  // (pp_rcd_prefix); type fields use `:` (matching the existing `struct`/PyTrec surface).
  | S0Ercd2(tknd, _, lses, _) => (
      pp_rcd_prefix(out, tknd);
      ps(out, "{ "); pp_s0rcd_fields(out, lses); ps(out, " }"))
  //
  // a parenthesized single type (grouping) — render its contents.
  | S0Elpar(_, ses, _) => (
      case+ ses of
      | list_cons(se1, list_nil()) => pp_s0exp(out, se1)
      | _ => pp_tuple(out, ses)
    )
  //
  // a qualified static type $M.t -> M.t.
  | S0Equal0(tok, se1) => pp_s0exp_qual(out, tok, se1)
  //
  | S0Eannot(se1, _) => pp_s0exp(out, se1)
  //
  | _ => ps(out, "# TODO(pp): s0exp")
)
and
pp_s0exp_qual(out: FILR, tok: token, se1: s0exp): void = let
  val q = qualname(tok)
in
  if strn_eq(q, "")
  then pp_s0exp(out, se1)
  else (ps(out, q); ps(out, "."); pp_s0exp_qual_tail(out, se1))
end
and
pp_s0exp_qual_tail(out: FILR, se: s0exp): void =
(
  case+ se.node() of
  | S0Eid0(id) => ps(out, rewrite_dollar(i0dnt_lexeme(id)))
  | S0Eannot(se1, _) => pp_s0exp_qual_tail(out, se1)
  | _ => pp_s0exp(out, se)
)
//
// an apps list: first elem is the head (a type name); subsequent S0Elpar groups
// are arg lists -> `Head[arg, ...]`. A standalone head (no args) is just `Head`.
// Plain ATS function types parse as the source-order application spine
// `(args), ->, result`; render those as the Pythonic arrow grammar instead of a
// bogus type application like `(Args)[->][Result]`.
and
pp_apps(out: FILR, ses: s0explst): void =
(
  case+ ses of
  | list_cons(prefix, rest) =>
      // a QUANTIFIER head: an existential `[..] T` (S0Eexi0) / universal `{..} T` (S0Euni0)
      // parses as an apps spine whose FIRST element is the quantifier and whose REST is the
      // quantified body. Emit `exists[binders | guards] ` / `forall[binders | guards] ` then the
      // body as a fresh apps (so `[i:i0|i>=0] sint(i)` -> `exists[I: SInt | I >= 0] SInt[I]`).
      (case+ prefix.node() of
       | S0Eexi0(_, sqs, _) => (pp_quant_prefix(out, "exists", sqs); pp_apps(out, rest))
       | S0Euni0(_, sqs, _) => (pp_quant_prefix(out, "forall", sqs); pp_apps(out, rest))
       | _ =>
         if s0exp_is_amp(prefix)
         then pp_prefix_update_or_generic(out, "&", rest)
         else (
           if s0exp_is_bang(prefix)
           then pp_prefix_update_or_generic(out, "!", rest)
           else pp_apps_arrow_or_prefix(out, ses)
         ))
  | _ => pp_apps_arrow_or_prefix(out, ses)
)
and
// emit a quantifier prefix `KW[binders | guard, ...]` (KW = "exists"/"forall") from the s0qualst.
// Binders (S0QUAvars) render capitalized with an optional `: SORT` (`I: SInt`, `A`); props
// (S0QUAprop) render after a `|` as comma-separated guard exprs. A guardless quantifier emits
// `KW[binders]`; an empty quantifier still emits `KW[]` (collapses to the body at lowering, matching
// stock's empty-binder uni0/exi0). Always followed by a single space before the body. SELF-CONTAINED
// (only tyname / PYPP_binder_* — all visible here) so it lives in the pp_s0exp recursion group, where
// it can recurse into pp_s0exp for the guard exprs. Pushes each binder name so a binder USE in the
// body/guard lifts (capitalize-scoping), mirroring the def-quantifier path's push_binders.
pp_quant_prefix(out: FILR, kw: strn, sqs: s0qualst): void = (
  quant_push_binders(sqs);
  ps(out, kw);
  ps(out, "[");
  pp_quant_binders(out, sqs, true);
  pp_quant_guards(out, sqs);
  ps(out, "] ")
)
and
// push every binder name (raw lexeme) of the quantifier so its capitalize-scoping is active for the
// body + guards (the def-quantifier path's push_binders companion; we never pop — a quantifier binder
// scopes to the end of the enclosing decl, same as the existing typaram binders).
quant_push_binders(sqs: s0qualst): void =
(
  case+ sqs of
  | list_nil() => ()
  | list_cons(sq, rest) => (
      (case+ sq.node() of
       | S0QUAvars(ids, _) => quant_push_ids(ids)
       | _ => ());
      quant_push_binders(rest))
)
and
quant_push_ids(ids: i0dntlst): void =
(
  case+ ids of
  | list_nil() => ()
  | list_cons(id, rest) => (PYPP_binder_push(i0dnt_lexeme(id)); quant_push_ids(rest))
)
and
// emit the comma-separated binder list (S0QUAvars only; props are the guard tail). `first` tracks
// whether a leading comma is needed across the S0QUAvars groups.
pp_quant_binders(out: FILR, sqs: s0qualst, first: bool): void =
(
  case+ sqs of
  | list_nil() => ()
  | list_cons(sq, rest) =>
      (case+ sq.node() of
       | S0QUAvars(ids, sopt) => let
           val sn = quant_sort_py(sopt)
           val first1 = pp_quant_ids(out, ids, sn, first)
         in
           pp_quant_binders(out, rest, first1)
         end
       | _ => pp_quant_binders(out, rest, first))
)
and
// emit one S0QUAvars group `n1: SORT, n2: SORT` (the shared sort applies to every id in the group).
// Returns the updated `first` flag. Names capitalize via tyname; a sort "" emits a bare `N`.
pp_quant_ids(out: FILR, ids: i0dntlst, sn: strn, first: bool): bool =
(
  case+ ids of
  | list_nil() => first
  | list_cons(id, rest) => (
      (if first then () else ps(out, ", "));
      ps(out, tyname(i0dnt_lexeme(id)));
      (if strn_eq(sn, "") then () else (ps(out, ": "); ps(out, sn)));
      pp_quant_ids(out, rest, sn, false))
)
and
// the guard tail of a quantifier: ` | g1, g2, ...` from the S0QUAprop entries (`[i:i0 | i>=0]`).
// No props -> nothing. The leading ` | ` is emitted once before the first prop.
pp_quant_guards(out: FILR, sqs: s0qualst): void =
  if s0qualst_has_prop(sqs)
  then (ps(out, " | "); pp_quant_guards_seq(out, sqs, true))
  else ()
and
pp_quant_guards_seq(out: FILR, sqs: s0qualst, first: bool): void =
(
  case+ sqs of
  | list_nil() => ()
  | list_cons(sq, rest) =>
      (case+ sq.node() of
       | S0QUAprop(g) => (
           (if first then () else ps(out, ", "));
           pp_s0exp(out, g);
           pp_quant_guards_seq(out, rest, false))
       | _ => pp_quant_guards_seq(out, rest, first))
)
and
s0qualst_has_prop(sqs: s0qualst): bool =
(
  case+ sqs of
  | list_nil() => false
  | list_cons(sq, rest) =>
      (case+ sq.node() of
       | S0QUAprop(_) => true
       | _ => s0qualst_has_prop(rest))
)
and
// the Pythonic SORT name of a quantifier binder's optional sort annotation (`{n:nat}` -> `SInt`,
// `{b:bool}` -> `SBool`, `{a:t0p}` -> a capitalized user sort). Self-contained twin of sort0_pyname
// (which is defined later, outside this recursion group) covering the kernel index/type sorts.
quant_sort_py(opt: sort0opt): strn =
(
  case+ opt of
  | optn_nil() => ""
  | optn_cons(s0t) => (
      case+ s0t.node() of
      | S0Tid0(id) => quant_sort_name_py(i0dnt_lexeme(id))
      | _ => "")
)
and
quant_sort_name_py(s: strn): strn =
(
  if strn_eq(s, "") then ""
  else if strn_eq(s, "t0") then "Type"
  else if strn_eq(s, "type") then "Type"
  else if strn_eq(s, "t0p") then "T0p"
  else if strn_eq(s, "i0") then "SInt"
  else if strn_eq(s, "int") then "SInt"
  else if strn_eq(s, "nat") then "SInt"
  else if strn_eq(s, "b0") then "SBool"
  else if strn_eq(s, "bool") then "SBool"
  else if strn_eq(s, "addr") then "Addr"
  else if strn_eq(s, "a0") then "A0"
  else if strn_eq(s, "vt") then "Vt"
  else if strn_eq(s, "vt0p") then "Vt"
  else tyname(s)
)
and
pp_prefix_update_or_generic(out: FILR, mark: strn, rest: s0explst): void =
(
  if s0explst_has_gtgt(rest)
  then (
    ps(out, mark);
    pp_update_lhs(out, rest);
    ps(out, " >> ");
    pp_update_rhs(out, rest))
  else (ps(out, mark); pp_apps_generic(out, rest))
)
and
pp_apps_arrow_or_prefix(out: FILR, ses: s0explst): void =
(
  // a STATIC INFIX OPERATOR spine `lhs OP rhs` (S0Eop2 / operator-shaped S0Eid0 as the MIDDLE
  // element): the index-arithmetic + comparison ops `+ - * < <= > >= == !=` (`{n | n>=0}` guards,
  // `Vec[A, n+1]` sizes). Render `lhs OP rhs` (the Pythonic index grammar p_index parses) instead
  // of the bogus type-application `Lhs[OP][rhs]`. Falls through to the arrow/app handling otherwise.
  if s0explst_is_binop_spine(ses)
  then pp_binop_spine(out, ses)
  else
  (case+ ses of
   | list_cons(arg, list_cons(arr, res)) =>
       if s0exp_is_arrow(arr)
       then (pp_s0exp_arrow_lhs(out, arg); ps(out, " -> "); pp_apps_generic(out, res))
       else pp_apps_prefix_or_generic(out, ses)
   | _ => pp_apps_prefix_or_generic(out, ses))
)
and
// a 3-element spine `[lhs, op, rhs]` whose MIDDLE element is a static infix operator. (Destructured
// step by step — the standalone transpiler chokes on a 3-deep nested list_cons/list_nil pattern.)
s0explst_is_binop_spine(ses: s0explst): bool =
(
  case+ ses of
  | list_cons(_, rest1) =>
      (case+ rest1 of
       | list_cons(opr, rest2) =>
           (case+ rest2 of
            | list_cons(_, rest3) =>
                (case+ rest3 of
                 | list_nil() => s0exp_static_binop(opr)
                 | _ => false)
            | _ => false)
       | _ => false)
  | _ => false
)
and
pp_binop_spine(out: FILR, ses: s0explst): void =
(
  case+ ses of
  | list_cons(arg, rest1) =>
      (case+ rest1 of
       | list_cons(opr, rest2) =>
           (case+ rest2 of
            | list_cons(rhs, _) =>
                (pp_s0exp(out, arg); ps(out, " "); ps(out, s0exp_binop_sym(opr)); ps(out, " "); pp_s0exp(out, rhs))
            | _ => pp_apps_prefix_or_generic(out, ses))
       | _ => pp_apps_prefix_or_generic(out, ses))
  | _ => pp_apps_prefix_or_generic(out, ses)
)
and
// is this s0exp an INDEX-ARITHMETIC / COMPARISON operator usable infix (`+`,`-`,`*`,`<`,`<=`,`>`,
// `>=`,`==`,`!=`)? Matches an operator-shaped S0Eid0 (the lexeme IS the symbol) or an S0Eop2 token.
s0exp_static_binop(se: s0exp): bool =
  (not(strn_eq(s0exp_binop_sym(se), "")))
and
// the surface symbol of a static infix operator s0exp, or "" if it is not one. The ATS lexeme and
// the Pythonic surface coincide for these (`>=`/`+`/...); equality/inequality map ATS `==`/`!=`.
s0exp_binop_sym(se: s0exp): strn = let
  val lx =
    (case+ se.node() of
     | S0Eid0(id) => i0dnt_lexeme(id)
     | S0Eop2(tok) => tok_lexeme(tok)
     | S0Eop1(tok) => tok_lexeme(tok)
     | _ => "")
in
  if strn_eq(lx, "+") then "+"
  else if strn_eq(lx, "-") then "-"
  else if strn_eq(lx, "*") then "*"
  else if strn_eq(lx, "<") then "<"
  else if strn_eq(lx, "<=") then "<="
  else if strn_eq(lx, ">") then ">"
  else if strn_eq(lx, ">=") then ">="
  else if strn_eq(lx, "==") then "=="
  else if strn_eq(lx, "!=") then "!="
  else ""
end
and
pp_s0exp_arrow_lhs(out: FILR, se: s0exp): void =
(
  case+ se.node() of
  | S0Elpar(_, list_cons(se1, list_nil()), _) =>
      if s0exp_is_arrow_type(se1)
      then (ps(out, "("); pp_s0exp(out, se1); ps(out, ")"))
      else pp_s0exp(out, se)
  | _ => pp_s0exp(out, se)
)
and
pp_apps_prefix_or_generic(out: FILR, ses: s0explst): void =
(
  case+ ses of
  | list_cons(prefix, rest) =>
      if s0exp_is_bang(prefix)
      then (ps(out, "!"); pp_apps_generic(out, rest))
      else (
        if s0exp_is_tilde(prefix)
        then (ps(out, "~"); pp_apps_generic(out, rest))
        else pp_apps_generic(out, ses)
      )
  | _ => pp_apps_generic(out, ses)
)
and
// The view/update type spine is prefix + lhs + `>>` + target:
//   ! tmpstk >> _        -> !Tmpstk >> _
//   & stkmap(itm) >> _   -> &Stkmap[Itm] >> _
s0explst_has_gtgt(ses: s0explst): bool =
(
  case+ ses of
  | list_nil() => false
  | list_cons(se, rest) =>
      if s0exp_is_gtgt(se) then true else s0explst_has_gtgt(rest)
)
and
pp_update_lhs(out: FILR, ses: s0explst): void =
(
  case+ ses of
  | list_nil() => ()
  | list_cons(se, rest) =>
      if s0exp_is_gtgt(se)
      then ()
      else (pp_s0exp(out, se); pp_update_lhs_args(out, rest))
)
and
pp_update_lhs_args(out: FILR, ses: s0explst): void =
(
  case+ ses of
  | list_nil() => ()
  | list_cons(se, rest) =>
      if s0exp_is_gtgt(se)
      then ()
      else (
        (case+ se.node() of
         | S0Elpar(_, args, _) => pp_typargs(out, args)
         | _ => (ps(out, "["); pp_s0exp(out, se); ps(out, "]")));
        pp_update_lhs_args(out, rest))
)
and
pp_update_rhs(out: FILR, ses: s0explst): void =
(
  case+ ses of
  | list_nil() => ps(out, "_")
  | list_cons(se, rest) =>
      if s0exp_is_gtgt(se)
      then (
        case+ rest of
        | list_nil() => ps(out, "_")
        | _ => pp_apps_generic(out, rest))
      else pp_update_rhs(out, rest)
)
and
pp_apps_generic(out: FILR, ses: s0explst): void =
(
  case+ ses of
  | list_nil() => ()
  | list_cons(hd, rest) => (
      pp_s0exp(out, hd);
      pp_apps_args(out, rest)
    )
)
and
s0exp_is_arrow_type(se: s0exp): bool =
(
  case+ se.node() of
  | S0Eapps(ses) => s0explst_is_arrow_spine(ses)
  | S0Elpar(_, list_cons(se1, list_nil()), _) => s0exp_is_arrow_type(se1)
  | _ => false
)
and
s0explst_is_arrow_spine(ses: s0explst): bool =
(
  case+ ses of
  | list_cons(_, list_cons(arr, _)) => s0exp_is_arrow(arr)
  | _ => false
)
and
s0exp_is_arrow(se: s0exp): bool =
(
  case+ se.node() of
  | S0Eid0(id) => i0dnt_lexeme(id) = "->"
  | _ => false
)
and
s0exp_is_bang(se: s0exp): bool =
(
  case+ se.node() of
  | S0Eid0(id) => i0dnt_lexeme(id) = "!"
  | _ => false
)
and
s0exp_is_amp(se: s0exp): bool =
(
  case+ se.node() of
  | S0Eid0(id) => i0dnt_lexeme(id) = "&"
  | _ => false
)
and
s0exp_is_gtgt(se: s0exp): bool =
(
  case+ se.node() of
  | S0Eid0(id) => i0dnt_lexeme(id) = ">>"
  | _ => false
)
and
s0exp_is_tilde(se: s0exp): bool =
(
  case+ se.node() of
  | S0Eid0(id) => i0dnt_lexeme(id) = "~"
  | _ => false
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
// RECORD-VARIANT type fields: `x: Int, y: Int` from an l0s0elst (S0LAB(lab, =/:, type)).
// Field names print verbatim (lowercase field labels); the field TYPE goes through pp_s0exp
// (so it capitalizes per scoping). Type-record fields use `:` (matching the struct surface).
and
pp_s0rcd_fields(out: FILR, lses: l0s0elst): void =
(
  case+ lses of
  | list_nil() => ()
  | list_cons(S0LAB(lab, _, se), rest) => (
      pp_lab0(out, lab); ps(out, ": "); pp_s0exp(out, se);
      (case+ rest of list_nil() => () | _ => ps(out, ", "));
      pp_s0rcd_fields(out, rest)
    )
)
// the elements inside a flat tuple `@(a, b)` -> `(A, B)`.
and
pp_tuple(out: FILR, ses: s0explst): void =
  (ps(out, "("); pp_s0exp_seq(out, ses); ps(out, ")"))
//
(* ****** ****** *)
//
// extract the (optional) sort name of a static binder, and map ATS index sorts
// to their Pythonic surface spellings.  Defined here (before the quantifier
// emitters that use them) so the `{n:nat}` -> `[N: SInt]` annotation resolves.
fun
sort0_name(opt: sort0opt): strn =
(
  case+ opt of
  | optn_nil() => ""
  | optn_cons(s0t) => (
      case+ s0t.node() of
      | S0Tid0(id) => i0dnt_lexeme(id)
      | _ => ""
    )
)
fun
sort0_pyname(s: strn): strn =
(
  if strn_eq(s, "") then ""
  else if strn_eq(s, "t0") then "Type"
  else if strn_eq(s, "type") then "Type"
  else if strn_eq(s, "i0") then "SInt"
  else if strn_eq(s, "int") then "SInt"
  else if strn_eq(s, "nat") then "SInt"
  else if strn_eq(s, "b0") then "SBool"
  else if strn_eq(s, "bool") then "SBool"
  else tyname(s)
)
//
// the pythonic SORT name of a `sort0` (a sort REFERENCE, e.g. the RHS of `#sortdef num = int`
// or the `: int` of `#stacst0 c : int`). The kernel sort exprs in the SATS/prelude are bare
// id sorts (`int`/`bool`/`type`/`addr`/...); map them through sort0_pyname so `int -> SInt`,
// `bool -> SBool`, `type -> Type`, and a user sort name capitalizes (the round-trip the
// `@sort type`/`@static let : SORT` parser+lowering accept).
fun
sort0_py(s0t: sort0): strn =
(
  case+ s0t.node() of
  | S0Tid0(id) => sort0_pyname(i0dnt_lexeme(id))
  | S0Tqid(_, st1) => sort0_py(st1)
  | _ => "Type"
)
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
      | S0QUAvars(ids, sopt) =>
          list_append(squa_idnames(ids, sort0_pyname(sort0_name(sopt))), collect_squa_names(rest))
      | S0QUAprop(_) => collect_squa_names(rest)
    )
)
and
// render each quantifier binder as `N` or, when the surface carries a sort
// (e.g. `{n:nat}` / `{n:int}` / `{b:bool}`), as `N: SInt` / `B: SBool` so the
// index keeps its INT/BOOL sort (a bare `[N]` would default to `type`, which
// breaks `list_vt[..., N]` where N is the length index).
squa_idnames(ids: i0dntlst, sn: strn): list(strn) =
(
  case+ ids of
  | list_nil() => list_nil()
  | list_cons(id, rest) => let
      val nm = tyname(i0dnt_lexeme(id))
      val one =
        if strn_eq(sn, "") then nm
        else strn_append(strn_append(nm, ": "), sn)
    in
      list_cons(one, squa_idnames(rest, sn))
    end
)
and
collect_squa_raw_names(sqs: s0qualst): list(strn) =
(
  case+ sqs of
  | list_nil() => list_nil()
  | list_cons(sq, rest) => (
      case+ sq.node() of
      | S0QUAvars(ids, _) => list_append(squa_idraw_names(ids), collect_squa_raw_names(rest))
      | S0QUAprop(_) => collect_squa_raw_names(rest)
    )
)
and
squa_idraw_names(ids: i0dntlst): list(strn) =
(
  case+ ids of
  | list_nil() => list_nil()
  | list_cons(id, rest) => list_cons(i0dnt_lexeme(id), squa_idraw_names(rest))
)
//
fun
collect_q0arg_names(qas: q0arglst): list(strn) =
(
  case+ qas of
  | list_nil() => list_nil()
  | list_cons(qa, rest) => (
      case+ qa.node() of
      | Q0ARGsome(id, sopt) => let
          val nm = tyname(i0dnt_lexeme(id))
          val sn = sort0_pyname(sort0_name(sopt))
          val one =
            if strn_eq(sn, "") then nm
            else strn_append(strn_append(nm, ": "), sn)
        in
          list_cons(one, collect_q0arg_names(rest))
        end
      | _ => collect_q0arg_names(rest)
    )
)
and
collect_q0arg_raw_names(qas: q0arglst): list(strn) =
(
  case+ qas of
  | list_nil() => list_nil()
  | list_cons(qa, rest) => (
      case+ qa.node() of
      | Q0ARGsome(id, _) => list_cons(i0dnt_lexeme(id), collect_q0arg_raw_names(rest))
      | _ => collect_q0arg_raw_names(rest)
    )
)
and
tqag_names(tqas: t0qaglst): list(strn) =
(
  case+ tqas of
  | list_nil() => list_nil()
  | list_cons(tqa, rest) => (
      case+ tqa.node() of
      | T0QAGsome(_, qas, _) => list_append(collect_q0arg_names(qas), tqag_names(rest))
      | _ => tqag_names(rest)
    )
)
and
tqag_raw_names(tqas: t0qaglst): list(strn) =
(
  case+ tqas of
  | list_nil() => list_nil()
  | list_cons(tqa, rest) => (
      case+ tqa.node() of
      | T0QAGsome(_, qas, _) => list_append(collect_q0arg_raw_names(qas), tqag_raw_names(rest))
      | _ => tqag_raw_names(rest)
    )
)
and
// the UNIVERSAL `{...}` template-quantifier binder names of a `#impltmp` (the s0qaglst
// SECOND field of D0Cimplmnt0 — previously dropped). A `#impltmp {k0:t0}{x0:t0} NAME<...>`
// binds `k0`/`x0` there, NOT in the `<...>` t0qaglst, so without collecting these the
// instance-arg type vars (`@impl[mydict[k0,x0], k0, x0]`) stayed UNREGISTERED (lowercase),
// and M3 read them as type CONSTRUCTORS rather than the bound template type VARIABLES.
s0qag_names(sqas: s0qaglst): list(strn) =
(
  case+ sqas of
  | list_nil() => list_nil()
  | list_cons(sqa, rest) => (
      case+ sqa.node() of
      | S0QAGsome(_, qas, _) => list_append(collect_q0arg_names(qas), s0qag_names(rest))
      | _ => s0qag_names(rest)
    )
)
and
s0qag_raw_names(sqas: s0qaglst): list(strn) =
(
  case+ sqas of
  | list_nil() => list_nil()
  | list_cons(sqa, rest) => (
      case+ sqa.node() of
      | S0QAGsome(_, qas, _) => list_append(collect_q0arg_raw_names(qas), s0qag_raw_names(rest))
      | _ => s0qag_raw_names(rest)
    )
)
and
farg_sapp_names(farg: f0arglst): list(strn) =
(
  case+ farg of
  | list_nil() => list_nil()
  | list_cons(fa, rest) => (
      case+ fa.node() of
      | F0ARGsapp(_, sqs, _) => list_append(collect_squa_names(sqs), farg_sapp_names(rest))
      | _ => farg_sapp_names(rest)
    )
)
and
farg_sapp_raw_names(farg: f0arglst): list(strn) =
(
  case+ farg of
  | list_nil() => list_nil()
  | list_cons(fa, rest) => (
      case+ fa.node() of
      | F0ARGsapp(_, sqs, _) => list_append(collect_squa_raw_names(sqs), farg_sapp_raw_names(rest))
      | _ => farg_sapp_raw_names(rest)
    )
)
and
impl_farg_names(sqas: s0qaglst, tqas: t0qaglst, farg: f0arglst): list(strn) =
  list_append(s0qag_names(sqas), list_append(tqag_names(tqas), farg_sapp_names(farg)))
and
impl_farg_raw_names(sqas: s0qaglst, tqas: t0qaglst, farg: f0arglst): list(strn) =
  list_append(s0qag_raw_names(sqas), list_append(tqag_raw_names(tqas), farg_sapp_raw_names(farg)))
and
t0iag_s0es(tia: t0iag): s0explst =
(
  case+ tia.node() of
  | T0IAGsome(_, ses, _) => ses
  | T0IAGnone(_) => list_nil()
)
and
t0iaglst_s0es(tias: t0iaglst): s0explst =
(
  case+ tias of
  | list_nil() => list_nil()
  | list_cons(tia, rest) => list_append(t0iag_s0es(tia), t0iaglst_s0es(rest))
)
and
pp_impl_tias(out: FILR, tias: t0iaglst): void = let
  val ses = t0iaglst_s0es(tias)
in
  case+ ses of
  | list_nil() => ()
  | _ => (ps(out, "["); pp_s0exp_seq(out, ses); ps(out, "]"))
end
and
impltmp_tokenq(tknd: token): bool =
(
case+ tknd.node() of
| T_IMPLMNT(IMPLtmp()) => true
| T_IMPLMNT(IMPLtmpr()) => true
| _ => false
)
and
pp_impl_tias_for(out: FILR, tknd: token, tias: t0iaglst): void = let
  val ses = t0iaglst_s0es(tias)
in
  case+ ses of
  | list_nil() => if impltmp_tokenq(tknd) then ps(out, "[]") else ()
  | _ => (ps(out, "["); pp_s0exp_seq(out, ses); ps(out, "]"))
end
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
// the RAW (lowercase, un-capitalized) static-quantifier binder names of a fun's
// d0arglst — the push_binders companion of darg_squa_names. Needed so the binder
// USES inside an `@extern def f[Obj: Vt](buf: !obj)` PARAM type capitalize to `!Obj`
// (registering the template binder), matching the IMPL bodies and so the callee
// template's `<obj>` is inferable at the call site.
fun
darg_squa_raw_names(dargs: d0arglst): list(strn) =
(
  case+ dargs of
  | list_nil() => list_nil()
  | list_cons(da, rest) => (
      case+ da.node() of
      | D0ARGsta0(_, sqs, _) => list_append(collect_squa_raw_names(sqs), darg_squa_raw_names(rest))
      | _ => darg_squa_raw_names(rest)
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
fun
pp_s0exp_formal(out: FILR, i: sint, se: s0exp): void =
  (ps(out, pname_at(i)); ps(out, ": "); pp_s0exp(out, se))
//
fun
pp_s0exp_formals_seq(out: FILR, i: sint, ses: s0explst): void =
(
  case+ ses of
  | list_nil() => ()
  | list_cons(se, rest) => (
      pp_s0exp_formal(out, i, se);
      (case+ rest of list_nil() => () | _ => ps(out, ", "));
      pp_s0exp_formals_seq(out, i+1, rest))
)
//
fun
pp_s0exp_formals(out: FILR, arg: s0exp): void =
(
  ps(out, "(");
  (case+ arg.node() of
   | S0Elpar(_, ses, _) => pp_s0exp_formals_seq(out, 0, ses)
   | S0Etup1(_, _, ses, _) => pp_s0exp_formals_seq(out, 0, ses)
   | _ => pp_s0exp_formal(out, 0, arg));
  ps(out, ")")
)
//
fun
pp_fun_sig_from_result(out: FILR, se: s0exp): bool =
(
  case+ se.node() of
  | S0Eapps(ses) => pp_fun_sig_from_apps(out, ses)
  | _ => false
)
and
pp_fun_sig_from_apps(out: FILR, ses: s0explst): bool =
(
  case+ ses of
  | list_cons(arg, list_cons(arr, res)) =>
      if s0exp_is_arrow(arr)
      then (pp_s0exp_formals(out, arg); ps(out, " -> "); pp_apps(out, res); true)
      else false
  | _ => false
)
//
// register / unregister a list of (raw, lowercase) type-binder names so their USES
// capitalize while a scope's body is printed (defined here, before the first caller).
fun
push_binders(ns: list(strn)): void =
(
  case+ ns of
  | list_nil() => ()
  | list_cons(nm, rest) => (PYPP_binder_push(nm); push_binders(rest))
)
fun
pop_binders(ns: list(strn)): void =
(
  case+ ns of
  | list_nil() => ()
  | list_cons(nm, rest) => (PYPP_binder_pop(nm); pop_binders(rest))
)
//
fun
pp_dynconst_fun_tail(out: FILR, dargs: d0arglst, sres: s0res): void =
(
  case+ dargs of
  | list_nil() => (
      case+ sres of
      | S0RESsome(_, se) =>
          if pp_fun_sig_from_result(out, se)
          then ()
          else (ps(out, "() -> "); pp_s0exp(out, se))
      | S0RESnone() => ps(out, "() -> Void"))
  | _ => (
      pp_darg_dyn(out, dargs);
      ps(out, " -> ");
      (case+ sres of
       | S0RESsome(_, se) => pp_s0exp(out, se)
       | S0RESnone() => ps(out, "Void")))
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
pp_dynconst_fun(out: FILR, outer_tps: list(strn), outer_raws: list(strn), dcd: d0cstdcl): void = let
  val nm    = i0dnt_lexeme(d0cstdcl_get_dpid(dcd))
  val dargs = d0cstdcl_get_darg(dcd)
  val sres  = d0cstdcl_get_sres(dcd)
  val tps   = list_append(outer_tps, darg_squa_names(dargs))
  // the RAW binder names (outer `<obj:vt>` + per-decl static quals) — pushed so the
  // param/result types capitalize their binder USES (`!obj` -> `!Obj`).
  val raws  = list_append(outer_raws, darg_squa_raw_names(dargs))
in
  ps(out, "@extern"); nl(out);
  ps(out, "def "); ps(out, fname(nm));
  pp_names_brkt(out, tps);
  push_binders(raws);
  pp_dynconst_fun_tail(out, dargs, sres);
  pop_binders(raws);
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
// FFI: render the foreign-name g0nam of a `$extnam(...)` as the pythonic `extnam(["cname"])`. The
// L0 g0nam is `G0Nlist(LPAR, parts, RPAR)`: empty parts -> `extnam()`; a single `G0Nstr(t0str)`
// part -> `extnam("cname")` (the string lexeme, quotes included, emitted verbatim). Other shapes
// (multi-part / non-string names) are rare and conservatively rendered as the empty `extnam()`.
fun
pp_extnam_gnam(out: FILR, gnm: g0nam): void =
(
  case+ gnm.node() of
  | G0Nlist(_, parts, _) =>
    ( ps(out, "extnam(");
      ( case+ parts of
        | list_nil() => ()
        | list_cons(p0, _) =>
            (case+ p0.node() of
             | G0Nstr(t0) => (case+ t0 of T0STRsome(t) => ps(out, tok_lexeme(t)) | T0STRnone(t) => ps(out, tok_lexeme(t)))
             | _ => ()) );
      ps(out, ")") )
  | _ => ps(out, "extnam()")
)
//
// FFI: emit ` = extnam(...)` for an `#extern fun`'s `= $extnam(...)` body (its teqd0exp `tdxp`). Only
// a `TEQD0EXPsome(_, D0Eextnam(_, gnam))` produces output; a bodyless / non-extnam tdxp emits nothing.
fun
pp_extnam_rhs(out: FILR, tdxp: teqd0exp): void =
(
  case+ tdxp of
  | TEQD0EXPsome(_, body) =>
    ( case+ body.node() of
      | D0Eextnam(_, gnam) => (ps(out, " = "); pp_extnam_gnam(out, gnam))
      | _ => () )
  | TEQD0EXPnone() => ()
)
//
fun
pp_dynconst(out: FILR, tok: token, tqas: t0qaglst, dcds: d0cstdclist): void = let
  val isval = tok_is_val(tok)
  val outer_tps = tqag_names(tqas)
  val outer_raws = tqag_raw_names(tqas)
  fun loop(out: FILR, first: bool, dcds: d0cstdclist): void =
    case+ dcds of
    | list_nil() => ()
    | list_cons(dcd, rest) => (
        (if first then () else nl(out));
        (if isval then pp_dynconst_val(out, dcd) else pp_dynconst_fun(out, outer_tps, outer_raws, dcd));
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
sarg_name(sag: s0arg): strn =
(
  case+ sag.node() of
  | S0ARGsome(id, _) => i0dnt_lexeme(id)
  | S0ARGnone(_) => ""
)
fun
sarg_pyparam(sag: s0arg): strn =
(
  case+ sag.node() of
  | S0ARGsome(id, sopt) => let
      val nm = i0dnt_lexeme(id)
      val sn = sort0_pyname(sort0_name(sopt))
    in
      if strn_eq(sn, "") then tyname(nm)
      else strn_append(strn_append(tyname(nm), ": "), sn)
    end
  | S0ARGnone(_) => xname(0)
)
fun
sarg_raw_names(sargs: s0arglst): list(strn) =
(
  case+ sargs of
  | list_nil() => list_nil()
  | list_cons(sag, rest) =>
      let val nm = sarg_name(sag) in
        if strn_eq(nm, "")
        then list_cons(xname(0), sarg_raw_names(rest))
        else list_cons(nm, sarg_raw_names(rest))
      end
)
fun
sarg_pyparams(sargs: s0arglst): list(strn) =
(
  case+ sargs of
  | list_nil() => list_nil()
  | list_cons(sag, rest) => list_cons(sarg_pyparam(sag), sarg_pyparams(rest))
)
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
fun
t0arg_name(tag: t0arg): strn =
(
  case+ tag.node() of
  | T0ARGsome(_, optn_cons(tok)) => tok_lexeme(tok)
  | _ => ""
)
fun
t0arg_datatype_names(i: sint, tags: t0arglst): list(strn) =
(
  case+ tags of
  | list_nil() => list_nil()
  | list_cons(tag, rest) => let
      val nm = t0arg_name(tag)
      val py = (if strn_eq(nm, "") then xname(i) else tyname(nm)): strn
    in
      list_cons(py, t0arg_datatype_names(i+1, rest))
    end
)
fun
t0arg_raw_names(i: sint, tags: t0arglst): list(strn) =
(
  case+ tags of
  | list_nil() => list_nil()
  | list_cons(tag, rest) => let
      val nm = t0arg_name(tag)
      val raw = (if strn_eq(nm, "") then xname(i) else nm): strn
    in
      list_cons(raw, t0arg_raw_names(i+1, rest))
    end
)
fun
pp_tmag_datatype_names(tmas: t0maglst): list(strn) =
(
  case+ tmas of
  | list_nil() => list_nil()
  | list_cons(tm, rest) => (
      case+ tm.node() of
      | T0MAGlist(_, tags, _) => list_append(t0arg_datatype_names(0, tags), pp_tmag_datatype_names(rest))
      | T0MAGnone(_) => pp_tmag_datatype_names(rest)
    )
)
fun
pp_tmag_raw_names(tmas: t0maglst): list(strn) =
(
  case+ tmas of
  | list_nil() => list_nil()
  | list_cons(tm, rest) => (
      case+ tm.node() of
      | T0MAGlist(_, tags, _) => list_append(t0arg_raw_names(0, tags), pp_tmag_raw_names(rest))
      | T0MAGnone(_) => pp_tmag_raw_names(rest)
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
      | S0MAGlist(_, sargs, _) => list_append(sarg_pyparams(sargs), pp_smag_names(rest))
      | S0MAGsing(_) => list_cons(xname(0), pp_smag_names(rest))
      | S0MAGnone(_) => pp_smag_names(rest)
    )
)
fun
pp_smag_raw_names(smas: s0maglst): list(strn) =
(
  case+ smas of
  | list_nil() => list_nil()
  | list_cons(sm, rest) => (
      case+ sm.node() of
      | S0MAGlist(_, sargs, _) => list_append(sarg_raw_names(sargs), pp_smag_raw_names(rest))
      | S0MAGsing(sid) => list_cons(i0dnt_lexeme(sid), pp_smag_raw_names(rest))
      | S0MAGnone(_) => pp_smag_raw_names(rest)
    )
)
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
fun
pp_typedef(out: FILR, n: sint, sid: s0eid, smas: s0maglst, se: s0exp): void = let
  val raws = pp_smag_raw_names(smas)
  val tps = pp_smag_names(smas)
in
  ind(out, n); ps(out, "type "); ps(out, tyname_decl(i0dnt_lexeme(sid)));
  pp_names_brkt(out, tps);
  ps(out, " = ");
  push_binders(raws);
  pp_s0exp(out, se);
  pop_binders(raws);
  nl(out)
end
//
fun
pp_symload_alias(out: FILR, n: sint, sym: s0ymb, dqi: d0qid, prec: g0expopt): void = let
  val nm  = fname(s0ymb_lexeme(sym))
in
  ind(out, n);
  (case+ prec of
   | optn_cons(ge) => (ps(out, "@overload["); ps(out, g0exp_lexeme(ge)); ps(out, "] "))
   | optn_nil() => ps(out, "@overload "));
  ps(out, nm); ps(out, " = ");
  // the TARGET: keep the module qualifier of `$M.x` (-> `M.x`) — a named staload registers `x`
  // under `$M.`, so dropping the qualifier leaves it unresolved. A bare target prints verbatim.
  pp_d0qid_target(out, dqi); nl(out)
end
and
pp_d0qid_target(out: FILR, dqi: d0qid): void =
(
  case+ dqi of
  | D0QIDnone(id) => ps(out, fname(i0dnt_lexeme(id)))
  | D0QIDsome(tok, id) => let
      val q = qualname(tok)
    in
      if strn_eq(q, "")
      then ps(out, fname(i0dnt_lexeme(id)))
      else (ps(out, q); ps(out, "."); ps(out, rewrite_dollar(i0dnt_lexeme(id))))
    end
)
//
(* ****** ****** *)
//
// ====================== DYNAMIC side: d0pat ===============================
//
// a pattern. Constructor names capitalize ONLY if file-local (conname_scoped);
// prelude cons (list_cons/list_nil) stay verbatim. Variables/wildcards verbatim.
//
fun
dpat_is_tilde(dp: d0pat): bool =
(
  case+ dp.node() of
  | D0Pid0(id) => strn_eq(i0dnt_lexeme(id), "~")
  | _ => false
)
and
dpat_is_bang(dp: d0pat): bool =
(
  case+ dp.node() of
  | D0Pid0(id) => strn_eq(i0dnt_lexeme(id), "!")
  | _ => false
)
and
dpat_is_cons_op(dp: d0pat): bool =
(
  case+ dp.node() of
  | D0Pid0(id) => strn_eq(i0dnt_lexeme(id), "::")
  | _ => false
)
//
fun
pp_d0pat(out: FILR, dp: d0pat): void =
(
  case+ dp.node() of
  //
  // a bare id: either a variable pattern or a nullary constructor. Known
  // file-local constructors keep constructor spelling; value binders are tracked.
  | D0Pid0(id) =>
      let val s = i0dnt_lexeme(id) in
        if PYPP_con_has(s) then ps(out, conname_scoped(s)) else ps(out, vname_bind(s))
      end
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
  // RECORD-VARIANT pattern `@{x= a, y= b}` / `$rec..{..}` / `#{..}` (Cluster D, D0Prcd2).
  // -> `[@boxed|@linear ]{ x = a, y = b }`. The box/flat/linear kind rides the TRCD20 token
  // (pp_rcd_prefix). Record-pattern fields use `=` (the existing PyPrec surface).
  | D0Prcd2(tknd, _, ldps, _) => (
      pp_rcd_prefix(out, tknd);
      ps(out, "{ "); pp_dpat_rcd_fields(out, ldps); ps(out, " }"))
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
pp_d0pat_head(out: FILR, dp: d0pat): void =
(
  case+ dp.node() of
  | D0Pid0(id) => ps(out, conname_scoped(i0dnt_lexeme(id)))
  | _ => pp_d0pat(out, dp)
)
and
pp_dpat_prefix_apps(out: FILR, mark: strn, arg0: d0pat, rest: d0patlst): void =
(
  case+ arg0.node() of
  | D0Plpar(_, list_cons(inner, list_nil()), _) =>
      (ps(out, mark); pp_d0pat_head(out, inner); pp_dpat_apps_args(out, rest))
  | _ =>
      (ps(out, mark); pp_d0pat_head(out, arg0); pp_dpat_apps_args(out, rest))
)
and
pp_dpat_apps(out: FILR, dps: d0patlst): void =
(
  if dpat_list_followed_by_cons(dps)
  then pp_dpat_cons_chain(out, dps)
  else
    case+ dps of
    | list_nil() => ()
    // Stock ATS parses generated pattern prefixes (`! C(args)`, `~ C(args)`) as
    // applications headed by the prefix plus a parenthesized constructor head.
    // Pythonic spells these prefixes directly on the pattern.
    | list_cons(hd, list_cons(arg0, rest)) =>
        if dpat_is_tilde(hd) then
          pp_dpat_prefix_apps(out, "~", arg0, rest)
        else
          (
            if dpat_is_bang(hd) then
              pp_dpat_prefix_apps(out, "!", arg0, rest)
            else
              (pp_d0pat_head(out, hd); pp_dpat_apps_args(out, list_cons(arg0, rest)))
          )
    | list_cons(hd, rest) =>
        (
          case+ hd.node() of
          | D0Papps(list_cons(phd, list_cons(arg0, list_nil()))) =>
              if dpat_is_tilde(phd) then
                pp_dpat_prefix_apps(out, "~", arg0, rest)
              else
                (
                  if dpat_is_bang(phd) then
                    pp_dpat_prefix_apps(out, "!", arg0, rest)
                  else
                    (pp_d0pat_head(out, hd); pp_dpat_apps_args(out, rest))
                )
          | _ =>
              (pp_d0pat_head(out, hd); pp_dpat_apps_args(out, rest))
        )
)
and
dpat_list_followed_by_cons(dps: d0patlst): bool =
(
  case+ dps of
  | list_cons(_, rest) => dpat_args_until_cons_has_cons(rest)
  | list_nil() => false
)
and
dpat_args_until_cons_has_cons(dps: d0patlst): bool =
(
  case+ dps of
  | list_nil() => false
  | list_cons(dp, rest) =>
      if dpat_is_cons_op(dp) then true else dpat_args_until_cons_has_cons(rest)
)
and
pp_dpat_cons_chain(out: FILR, dps: d0patlst): void =
(
  case+ dps of
  | list_cons(hd, rest) => let
      val () = ps(out, "list_cons(")
      val tail = pp_dpat_operand_until_cons(out, hd, rest)
      val () = ps(out, ", ")
    in
      case+ tail of
      | list_cons(_, rhs) => pp_dpat_cons_rhs(out, rhs)
      | _ => ps(out, "# TODO(pp): d0pat-cons")
      ;
      ps(out, ")")
    end
  | list_nil() => ps(out, "# TODO(pp): d0pat-cons")
)
and
pp_dpat_cons_rhs(out: FILR, dps: d0patlst): void =
(
  if dpat_list_followed_by_cons(dps)
  then pp_dpat_cons_chain(out, dps)
  else pp_dpat_operand_list(out, dps)
)
and
pp_dpat_operand_list(out: FILR, dps: d0patlst): void =
(
  case+ dps of
  | list_cons(hd, rest) => let
      val _ = pp_dpat_operand_until_cons(out, hd, rest)
    in
      ()
    end
  | list_nil() => ps(out, "# TODO(pp): d0pat-cons")
)
and
pp_dpat_operand_until_cons(out: FILR, hd: d0pat, rest: d0patlst): d0patlst =
(
  pp_d0pat_head(out, hd);
  pp_dpat_apps_args_until_cons(out, rest)
)
and
pp_dpat_apps_args_until_cons(out: FILR, dps: d0patlst): d0patlst =
(
  case+ dps of
  | list_nil() => list_nil()
  | list_cons(dp, rest) =>
      if dpat_is_cons_op(dp)
      then dps
      else (
        pp_dpat_app_arg(out, dp);
        pp_dpat_apps_args_until_cons(out, rest))
)
and
pp_dpat_app_arg(out: FILR, dp: d0pat): void =
(
  case+ dp.node() of
  | D0Plpar(_, args, _) => (ps(out, "("); pp_dpat_seq(out, args); ps(out, ")"))
  | _ => (ps(out, "("); pp_d0pat(out, dp); ps(out, ")"))
)
and
pp_dpat_apps_args(out: FILR, dps: d0patlst): void =
(
  case+ dps of
  | list_nil() => ()
  | list_cons(dp, rest) => (
      pp_dpat_app_arg(out, dp);
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
// RECORD-VARIANT pattern fields: `x = a, y = b` from an l0d0plst (D0LAB(lab, =, pat)).
// Field names print verbatim; the sub-pattern goes through pp_d0pat.
and
pp_dpat_rcd_fields(out: FILR, ldps: l0d0plst): void =
(
  case+ ldps of
  | list_nil() => ()
  | list_cons(D0LAB(lab, _, dp), rest) => (
      pp_lab0(out, lab); ps(out, " = "); pp_d0pat(out, dp);
      (case+ rest of list_nil() => () | _ => ps(out, ", "));
      pp_dpat_rcd_fields(out, rest)
    )
)
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
  | D0Eid0(id) => ps(out, val_or_con_name(i0dnt_lexeme(id)))
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
	  // ATS `$raise e` -> Pythonic `raise e`.
	  | D0Eraise(_, de1) => (ps(out, "raise "); pp_d0exp_inline(out, de1))
	  //
	  // expression-level conditional.
	  | D0Eift0(_, c, th, el) => pp_dexp_if_inline(out, c, th, el)
	  | D0Eift1(_, c, th, el, _) => pp_dexp_if_inline(out, c, th, el)
	  //
	  // anonymous function (`lam i => e`) -> Pythonic inline lambda.
	| D0Elam0(_, farg, _, _, body, _) => (
	      pp_lam_farg_params(out, farg); ps(out, " => "); pp_d0exp_inline(out, body))
	  //
	  // MISC (Cluster E): a RECURSIVE lambda `fix f(params): R => e` (D0Efix0) -> the pythonic
	  // `fix f(params)[: R] => e`. The self-name is the d0pid; params reuse the lambda-arg emit; the
	  // optional s0res result-type is emitted `: T`. py->L2 (PyEfix -> PCEfix -> D2Efix0) round-trips.
	| D0Efix0(_, dpid, farg, sres, _, body, _) => (
	      ps(out, "fix "); ps(out, val_or_con_name(i0dnt_lexeme(dpid)));
	      pp_lam_farg_params(out, farg);
	      (case+ sres of S0RESsome(_, se) => (ps(out, ": "); pp_s0exp(out, se)) | S0RESnone() => ());
	      ps(out, " => "); pp_d0exp_inline(out, body))
	  //
	  // MISC (Cluster E): the EXPRESSION-position `$exists{W..}(S..)` (D0Eexists) -> the pythonic
	  // `exists {W..} (S..)`. The witness statics ride D0Esarg groups; the scope is the inner d0exp.
	  // Disambiguated from the type-level `exists[..]` by being an EXPR (this is a d0exp, not an s0exp).
	| D0Eexists(_, sargs, scope) => (
	      ps(out, "exists "); pp_exists_witness(out, sargs);
	      ps(out, " "); pp_exists_scope(out, scope))
	  //
	  // a parenthesized / sequence group.  Preserve single-elem source parens:
	  // `a + (b - c)` must not reparse as `(a + b) - c`.
  // SMCLN-sequence (cons2) at expression position -> a (a; b) we render inline
  // as a comma-paren only when used as an rvalue is wrong — but inside an INLINE
  // ref-set rhs the corpus never nests a sequence, so a single-elem is the norm.
  | D0Elpar(_, des, rp) => (
      case+ des of
      | list_cons(de1, list_nil()) => (ps(out, "("); pp_d0exp_inline(out, de1); ps(out, ")"))
      | _ => (ps(out, "("); pp_dexp_seq_inline(out, des); ps(out, ")")))
  //
  // a tuple `@(a, b)` / `(a, b)`.
  | D0Etup1(_, _, des, _) => (ps(out, "("); pp_dexp_seq_inline(out, des); ps(out, ")"))
  //
  // RECORD-VARIANT value `@{x= 1, y= 2}` / `$rec..{..}` / `#{..}` (Cluster D, D0Ercd2).
  // -> `[@boxed|@linear ]{ x = 1, y = 2 }`. The box/flat/linear kind rides the TRCD20 token
  // (pp_rcd_prefix). Record-literal fields use `=` (the existing PyErec surface).
  | D0Ercd2(tknd, _, ldes, _) => (
      pp_rcd_prefix(out, tknd);
      ps(out, "{ "); pp_d0rcd_fields(out, ldes); ps(out, " }"))
  //
  // the ref-cell deref `r[]` (empty bracket).  D0Ebrckt(LB, [], RB) on an id head
  // is parsed as an APPS [id; brckt]; a STANDALONE brckt has an empty arg list.
  | D0Ebrckt(_, des, _) => (
      case+ des of
      | list_nil() => ps(out, "[]")
      | _ => (ps(out, "["); pp_dexp_seq_inline(out, des); ps(out, "]")))
  | D0Edtsel(_, lab, opt) => pp_dexp_dtsel(out, lab, opt)
  //
	  | D0Eannot(de1, _) => pp_d0exp_inline(out, de1)
	  // a qualified dynamic name `$M.x` -> `M.x` (mirrors the static S0Equal0 -> M.t). The named
	  // staload registers the module under `$M.`, so the qualifier MUST be kept (dropping it leaves
	  // the bare name unresolved). A bare/empty qualifier falls through to the inner expression.
	  | D0Equal0(tok, de1) => pp_d0exp_qual_inline(out, tok, de1)
	  | D0Ewhere(de1, _) => pp_d0exp_inline(out, de1)
	  | D0Eerrck(_, de1) => pp_d0exp_inline(out, de1)
	  //
	  | _ => ps(out, "# TODO(pp): d0exp-inline")
	)
// MISC (Cluster E): the `$exists` witness `{W..}` — a d0explst of D0Esarg(_, s0explst, _) groups. Emit
// `{ s0exp, ... }` flattening the per-group statics (the corpus form is a single `{1}` group).
and
pp_exists_witness(out: FILR, sargs: d0explst): void = (
  ps(out, "{"); pp_exists_witness_sargs(out, sargs, true); ps(out, "}"))
and
pp_exists_witness_sargs(out: FILR, sargs: d0explst, first: bool): void =
(
  case+ sargs of
  | list_nil() => ()
  | list_cons(sa, rest) => (
      case+ sa.node() of
      | D0Esarg(_, ses, _) => (pp_exists_witness_statics(out, ses, first); pp_exists_witness_sargs(out, rest, false))
      | _ => pp_exists_witness_sargs(out, rest, first))
)
and
pp_exists_witness_statics(out: FILR, ses: s0explst, first: bool): void =
(
  case+ ses of
  | list_nil() => ()
  | list_cons(se, rest) => (
      (if first then () else ps(out, ", ")); pp_s0exp(out, se);
      pp_exists_witness_statics(out, rest, false))
)
// the `$exists` scope `(S..)` — the inner d0exp. A D0Elpar wraps the scope value-list; emit each as a
// comma-separated paren group. A bare scope d0exp is emitted in a single paren.
and
pp_exists_scope(out: FILR, scope: d0exp): void =
(
  case+ scope.node() of
  | D0Elpar(_, des, _) => (ps(out, "("); pp_dexp_seq_inline(out, des); ps(out, ")"))
  | _ => (ps(out, "("); pp_d0exp_inline(out, scope); ps(out, ")"))
)
// a qualified dynamic expression `$M.x` -> `M.x`: keep the module qualifier (the named staload
// alias), drop the leading `$`. An empty/bare qualifier renders just the inner expression.
and
pp_d0exp_qual_inline(out: FILR, tok: token, de1: d0exp): void = let
  val q = qualname(tok)
in
  if strn_eq(q, "")
  then pp_d0exp_inline(out, de1)
  else (ps(out, q); ps(out, "."); pp_d0exp_qual_tail_inline(out, de1))
end
and
pp_d0exp_qual_tail_inline(out: FILR, de: d0exp): void =
(
  case+ de.node() of
  // the tail after `M.` is the bare member name — emit it RAW (no value/con renaming): the
  // qualified resolver looks it up by its ATS name inside the module's env, exactly as stock does.
  | D0Eid0(id) => ps(out, rewrite_dollar(i0dnt_lexeme(id)))
  | D0Eopid(oid) => ps(out, fname(i0dnt_lexeme(oid)))
  | D0Eannot(de2, _) => pp_d0exp_qual_tail_inline(out, de2)
  | _ => pp_d0exp_inline(out, de)
)
// RECORD-VARIANT value fields: `x = 1, y = 2` from an l0d0elst (D0LAB(lab, =, expr)).
// Field names print verbatim; the value expr goes through pp_d0exp_inline.
and
pp_d0rcd_fields(out: FILR, ldes: l0d0elst): void =
(
  case+ ldes of
  | list_nil() => ()
  | list_cons(D0LAB(lab, _, de), rest) => (
      pp_lab0(out, lab); ps(out, " = "); pp_d0exp_inline(out, de);
      (case+ rest of list_nil() => () | _ => ps(out, ", "));
      pp_d0rcd_fields(out, rest)
    )
)
// the d0eid (an operator-as-id) — a bare i0dnt (d0eid = i0dnt_tbox).
and
pp_d0eid(out: FILR, oid: d0eid): void = ps(out, fname(i0dnt_lexeme(oid)))
and
pp_dexp_if_inline(out: FILR, c: d0exp, th: d0exp_THEN, el: d0exp_ELSE): void =
(
  ps(out, "if "); pp_d0exp_inline(out, c); ps(out, ": ");
  pp_dexp_then_inline(out, th);
  ps(out, " else: ");
  pp_dexp_else_inline(out, el)
)
and
pp_dexp_then_inline(out: FILR, th: d0exp_THEN): void =
(
  case+ th of
  | d0exp_THEN_some(_, te) => pp_d0exp_inline(out, te)
  | d0exp_THEN_none(_) => ps(out, "# TODO(pp): if-then-inline")
)
and
pp_dexp_else_inline(out: FILR, el: d0exp_ELSE): void =
(
  case+ el of
  | d0exp_ELSE_some(_, ee) => pp_d0exp_inline(out, ee)
  | d0exp_ELSE_none(_) => ps(out, "# TODO(pp): if-else-inline")
)
// an application apps-list: head then paren/bracket arg-groups. The HEAD is a con
// or a function id; trailing `[]` brackets are ref-derefs (`r[]`); trailing `(..)`
// are call/con args.
and
	pp_dexp_apps(out: FILR, des: d0explst): void =
	(
	  case+ des of
	  | list_nil() => ()
	  | list_cons(hd, rest) => pp_dexp_apps_from(out, hd, rest)
	)
	and
	pp_dexp_apps_from(out: FILR, hd: d0exp, rest: d0explst): void =
	(
	  case+ rest of
	  | list_cons(arg0, rest1) => (
	      case+ arg0.node() of
	      | D0Esarg(_, ses, _) => (
	          ps(out, "@sapp["); pp_s0exp_seq(out, ses); ps(out, "] ");
	          pp_dexp_apps_from(out, hd, rest1))
	      | D0Etarg(_, ses, _) => (
	          ps(out, "@inst["); pp_s0exp_seq(out, ses); ps(out, "] ");
	          pp_dexp_apps_from(out, hd, rest1))
	      | _ => pp_dexp_apps_from_plain(out, hd, rest))
	  | list_nil() => pp_dexp_apps_from_plain(out, hd, rest)
	)
	and
	pp_dexp_apps_from_plain(out: FILR, hd: d0exp, rest: d0explst): void =
	if dexp_is_unary_not_app(hd, rest)
	then pp_dexp_unary_not_app(out, rest)
	else if dexp_is_nullary_local_con_call(hd, rest)
	then pp_d0exp_inline(out, hd)
	else let
	  val tail0 = dexp_skip_postfix(rest)
	in
	  if dexp_tail_starts_cons(tail0)
	  then pp_dexp_cons_apps(out, hd, rest)
	  else if dexp_tail_starts_named_binop(tail0)
	  then pp_dexp_named_binop_apps(out, hd, rest, tail0)
	  else if dexp_tail_starts_cmp(tail0)
	  then pp_dexp_cmp_apps(out, hd, rest, tail0)
	  else if dexp_tail_starts_bslash_selector(tail0)
	  then pp_dexp_bslash_selector_apps(out, hd, rest, tail0)
	  else let
	    val tail1 = pp_dexp_operand_from(out, hd, rest)
	  in
	    pp_dexp_infix_tail(out, tail1)
	  end
	end
	and
	dexp_is_unary_not_app(hd: d0exp, rest: d0explst): bool =
	(
	  if dexp_is_name(hd, "~")
	  then (
	    case+ rest of
	    | list_cons(_, list_nil()) => true
	    | _ => false)
	  else false
	)
	and
	pp_dexp_unary_not_app(out: FILR, rest: d0explst): void =
	(
	  case+ rest of
	  | list_cons(arg, list_nil()) => (ps(out, "not "); pp_d0exp_inline(out, arg))
	  | _ => (ps(out, "~"); pp_dexp_apps_args_fallback(out, rest))
	)
	and
	pp_dexp_cons_apps(out: FILR, hd: d0exp, rest: d0explst): void =
	  pp_dexp_cons_chain(out, hd, rest)
	and
	pp_dexp_cons_chain(out: FILR, hd: d0exp, rest: d0explst): void =
	let
	  val () = ps(out, "list_cons(")
	  val tail = pp_dexp_operand_from(out, hd, rest)
	  val () = ps(out, ", ")
	in
	  case+ tail of
	  | list_cons(_, rhs) => pp_dexp_cons_rhs(out, rhs)
	  | _ => ps(out, "# TODO(pp): d0exp-cons")
	  ;
	  ps(out, ")")
	end
	and
	pp_dexp_cons_rhs(out: FILR, des: d0explst): void =
	(
	  case+ des of
	  | list_cons(hd, rest) =>
	      if dexp_list_followed_by_cons(des)
	      then pp_dexp_cons_chain(out, hd, rest)
	      else let
	        val tail = pp_dexp_operand_from(out, hd, rest)
	      in
	        pp_dexp_infix_tail(out, tail)
	      end
	  | list_nil() => ps(out, "# TODO(pp): d0exp-cons")
	)
	and
	pp_dexp_named_binop_apps(out: FILR, hd: d0exp, rest: d0explst, tail0: d0explst): void =
	(
	  case+ tail0 of
	  | list_cons(opr, list_cons(rhs, rhsrest)) => let
	      val () = ps(out, dexp_named_binop_call(opr))
	      val () = ps(out, "(")
	      val _ = pp_dexp_operand_from(out, hd, rest)
	      val () = ps(out, ", ")
	      val tail1 = pp_dexp_operand_from(out, rhs, rhsrest)
	      val () = ps(out, ")")
	    in
	      pp_dexp_infix_tail(out, tail1)
	    end
	  | _ => let
	      val tail1 = pp_dexp_operand_from(out, hd, rest)
	    in
	      pp_dexp_infix_tail(out, tail1)
	    end
	)
	and
	pp_dexp_cmp_apps(out: FILR, hd: d0exp, rest: d0explst, tail0: d0explst): void =
	(
	  case+ tail0 of
	  | list_cons(_, list_cons(_, list_cons(rhs, rhsrest))) => let
	      val () = ps(out, "g_cmp(")
	      val _ = pp_dexp_operand_from(out, hd, rest)
	      val () = ps(out, ", ")
	      val tail1 = pp_dexp_operand_from(out, rhs, rhsrest)
	      val () = ps(out, ")")
	    in
	      pp_dexp_infix_tail(out, tail1)
	    end
	  | _ => let
	      val tail1 = pp_dexp_operand_from(out, hd, rest)
	    in
	      pp_dexp_infix_tail(out, tail1)
	    end
	)
	and
	pp_dexp_bslash_selector_apps(out: FILR, hd: d0exp, rest: d0explst, tail0: d0explst): void =
	(
	  case+ tail0 of
	  | list_cons(_, list_cons(opr, list_cons(rhs, rhsrest))) => let
	      val _ = pp_dexp_operand_from(out, hd, rest)
	      val () = ps(out, ".")
	      val () = ps(out, fname(dexp_name(opr)))
	      val () = pp_dexp_bslash_selector_arg(out, rhs)
	    in
	      pp_dexp_infix_tail(out, rhsrest)
	    end
	  | _ => let
	      val tail1 = pp_dexp_operand_from(out, hd, rest)
	    in
	      pp_dexp_infix_tail(out, tail1)
	    end
	)
	and
	pp_dexp_bslash_selector_arg(out: FILR, arg: d0exp): void =
	(
	  case+ arg.node() of
	  | D0Elpar(_, args, _) => (ps(out, "("); pp_dexp_seq_inline(out, args); ps(out, ")"))
	  | D0Etup1(_, _, args, _) => (ps(out, "("); pp_dexp_seq_inline(out, args); ps(out, ")"))
	  | D0Ebrckt(_, args, _) => (ps(out, "["); pp_dexp_seq_inline(out, args); ps(out, "]"))
	  | _ => (ps(out, "("); pp_d0exp_inline(out, arg); ps(out, ")"))
	)
	and
	pp_dexp_operand_from(out: FILR, hd: d0exp, rest: d0explst): d0explst =
	(
	  pp_d0exp_inline(out, hd);
	  pp_dexp_postfix_tail(out, rest)
	)
	and
	pp_dexp_postfix_tail(out: FILR, des: d0explst): d0explst =
	(
	  case+ des of
	  | list_nil() => list_nil()
	  | list_cons(de, rest) => (
	      (case+ de.node() of
	       | D0Ebrckt(_, args, _) => (
	           case+ args of
	           | list_nil() => ps(out, "[]")
	           | _ => (ps(out, "["); pp_dexp_seq_inline(out, args); ps(out, "]")))
	       | D0Elpar(_, args, _) => (ps(out, "("); pp_dexp_seq_inline(out, args); ps(out, ")"))
	       | D0Etup1(_, _, args, _) => (ps(out, "("); pp_dexp_seq_inline(out, args); ps(out, ")"))
	       | D0Edtsel(_, lab, opt) => pp_dexp_dtsel(out, lab, opt)
	       | D0Esarg(_, _, _) => ()
	       | D0Etarg(_, _, _) => ()
	       | _ => ());
	      if dexp_is_postfix(de)
	      then pp_dexp_postfix_tail(out, rest) else des)
	)
	and
	pp_dexp_infix_tail(out: FILR, des: d0explst): void =
	(
	  case+ des of
	  | list_nil() => ()
	  | list_cons(opr, rest) => let
	      val bop = dexp_binop_py(opr)
	    in
	      if strn_eq(bop, "")
	      then pp_dexp_apps_args_fallback(out, des)
	      else (
	        case+ rest of
	        | list_nil() => (ps(out, "("); pp_d0exp_inline(out, opr); ps(out, ")"))
	        | list_cons(rhs, rhsrest) => let
	            val () = ps(out, " ")
	            val () = ps(out, bop)
	            val () = ps(out, " ")
	            val tail1 = pp_dexp_operand_from(out, rhs, rhsrest)
	          in
	            pp_dexp_infix_tail(out, tail1)
	          end)
	    end
	)
	and
	pp_dexp_apps_args_fallback(out: FILR, des: d0explst): void =
	(
	  case+ des of
	  | list_nil() => ()
	  | list_cons(de, rest) => (
	      ps(out, "("); pp_d0exp_inline(out, de); ps(out, ")");
	      pp_dexp_apps_args_fallback(out, rest))
	)
	and
	pp_dexp_dtsel(out: FILR, lab: l0abl, opt: d0expopt): void =
	(
	  ps(out, ".");
	  pp_l0abl(out, lab);
	  case+ opt of
	  | optn_nil() => ()
	  | optn_cons(arg) => pp_dexp_dtsel_arg(out, arg)
	)
	and
	pp_dexp_dtsel_arg(out: FILR, arg: d0exp): void =
	(
	  case+ arg.node() of
	  | D0Elpar(_, args, _) => (ps(out, "("); pp_dexp_seq_inline(out, args); ps(out, ")"))
	  | D0Etup1(_, _, args, _) => (ps(out, "("); pp_dexp_seq_inline(out, args); ps(out, ")"))
	  | D0Ebrckt(_, args, _) => (ps(out, "["); pp_dexp_seq_inline(out, args); ps(out, "]"))
	  | _ => (ps(out, "("); pp_d0exp_inline(out, arg); ps(out, ")"))
	)
	and
	pp_l0abl(out: FILR, lab: l0abl): void =
	(
	  case+ lab.node() of
	  | L0ABLsome(l0) => pp_label(out, l0)
	  | L0ABLnone(tok) => ps(out, tok_lexeme(tok))
	)
	and
	pp_label(out: FILR, lab: label): void =
	(
	  case+ lab of
	  | LABint(i) => gint_fprint$sint(i, out)
	  | LABsym(sym) => ps(out, fname(symbl_get_name(sym)))
	)
	and
	dexp_is_postfix(de: d0exp): bool =
	(
	  case+ de.node() of
	  | D0Ebrckt(_, _, _) => true
	  | D0Elpar(_, _, _) => true
	  | D0Etup1(_, _, _, _) => true
	  | D0Edtsel(_, _, _) => true
	  | D0Esarg(_, _, _) => true
	  | D0Etarg(_, _, _) => true
	  | _ => false
	)
	and
	dexp_is_local_con_head(de: d0exp): bool =
	(
	  case+ de.node() of
	  | D0Eid0(id) => PYPP_con_has(i0dnt_lexeme(id))
	  | _ => false
	)
	and
	dexp_is_nullary_local_con_call(hd: d0exp, rest: d0explst): bool =
	(
	  if dexp_is_local_con_head(hd)
	  then dexp_is_empty_call_tail(rest)
	  else false
	)
	and
	dexp_is_empty_call_tail(des: d0explst): bool =
	(
	  case+ des of
	  | list_nil() => false
	  | list_cons(de, rest) => (
	      case+ de.node() of
	      | D0Elpar(_, list_nil(), _) => dexp_tail_ignorable(rest)
	      | D0Esarg(_, _, _) => dexp_is_empty_call_tail(rest)
	      | D0Etarg(_, _, _) => dexp_is_empty_call_tail(rest)
	      | _ => false)
	)
	and
	dexp_tail_ignorable(des: d0explst): bool =
	(
	  case+ des of
	  | list_nil() => true
	  | list_cons(de, rest) => (
	      case+ de.node() of
	      | D0Esarg(_, _, _) => dexp_tail_ignorable(rest)
	      | D0Etarg(_, _, _) => dexp_tail_ignorable(rest)
	      | _ => false)
	)
	and
	dexp_skip_postfix(des: d0explst): d0explst =
	(
	  case+ des of
	  | list_nil() => list_nil()
	  | list_cons(de, rest) =>
	      if dexp_is_postfix(de) then dexp_skip_postfix(rest) else des
	)
	and
	dexp_tail_starts_cons(des: d0explst): bool =
	(
	  case+ des of
	  | list_cons(opr, list_cons(_, _)) => dexp_is_cons_op(opr)
	  | _ => false
	)
	and
	dexp_tail_starts_cmp(des: d0explst): bool =
	(
	  case+ des of
	  | list_cons(bs, list_cons(cmp, list_cons(_, _))) =>
	      if dexp_is_name(bs, "\\") then dexp_is_name(cmp, "cmp") else false
	  | _ => false
	)
	and
	dexp_tail_starts_named_binop(des: d0explst): bool =
	(
	  case+ des of
	  | list_cons(opr, list_cons(_, _)) => ~(strn_eq(dexp_named_binop_call(opr), ""))
	  | _ => false
	)
	and
	dexp_list_followed_by_cons(des: d0explst): bool =
	(
	  case+ des of
	  | list_cons(_, rest) => dexp_tail_starts_cons(dexp_skip_postfix(rest))
	  | list_nil() => false
	)
	and
	dexp_tail_starts_bslash_selector(des: d0explst): bool =
	(
	  case+ des of
	  | list_cons(bs, list_cons(opr, list_cons(_, _))) =>
	      if dexp_is_name(bs, "\\")
	      then ~(strn_eq(dexp_name(opr), ""))
	      else false
	  | _ => false
	)
	and
	dexp_is_cons_op(de: d0exp): bool = dexp_is_name(de, "::")
	and
	dexp_name(de: d0exp): strn =
	(
	  case+ de.node() of
	  | D0Eid0(id) => i0dnt_lexeme(id)
	  | D0Eopid(oid) => i0dnt_lexeme(oid)
	  | _ => ""
	)
	and
	dexp_is_name(de: d0exp, name: strn): bool = strn_eq(dexp_name(de), name)
	and
	dexp_is_llazy_head(de: d0exp): bool =
	  if dexp_is_name(de, "$llazy") then true else dexp_is_name(de, "llazy")
	and
	dexp_binop_py(de: d0exp): strn = let
	  val oper = dexp_name(de)
	in
	  if strn_eq(oper, "=") then "=="
	  else if strn_eq(oper, "<>") then "!="
	  else if strn_eq(oper, "+") then "+"
	  else if strn_eq(oper, "-") then "-"
	  else if strn_eq(oper, "*") then "*"
	  else if strn_eq(oper, "/") then "/"
	  else if strn_eq(oper, "%") then "%"
	  else if strn_eq(oper, "<") then "<"
	  else if strn_eq(oper, "<=") then "<="
	  else if strn_eq(oper, ">") then ">"
	  else if strn_eq(oper, ">=") then ">="
	  else if strn_eq(oper, "!=") then "!="
	  else ""
	end
	and
	dexp_named_binop_call(de: d0exp): strn = let
	  val oper = dexp_name(de)
	in
	  if strn_eq(oper, "&") then "land"
	  else if strn_eq(oper, "<<") then "lsln"
	  else if strn_eq(oper, ">>") then "asrn"
	  else if strn_eq(oper, ">>>") then "lsrn"
	  else ""
	end
	and
	farg_has_dapp(farg: f0arglst): bool =
	(
	  case+ farg of
	  | list_nil() => false
	  | list_cons(fa, rest) => (
	      case+ fa.node() of
	      | F0ARGdapp(_) => true
	      | _ => farg_has_dapp(rest))
	)
	and
	pp_lam_farg_params(out: FILR, farg: f0arglst): void = (
	  ps(out, "(");
	  pp_lam_farg_dapps(out, farg);
	  ps(out, ")")
	)
	and
	pp_lam_farg_dapps(out: FILR, farg: f0arglst): void =
	(
	  case+ farg of
	  | list_nil() => ()
	  | list_cons(fa, rest) => (
	      case+ fa.node() of
	      | F0ARGdapp(dp) => pp_lam_farg_one(out, dp, rest)
	      | _ => pp_lam_farg_dapps(out, rest))
	)
and
pp_lam_farg_one(out: FILR, dp: d0pat, rest: f0arglst): void =
(
  case+ dp.node() of
  | D0Plpar(_, dps, _) => pp_dpat_seq(out, dps)
  | D0Ptup1(_, _, dps, _) => pp_dpat_seq(out, dps)
  | _ => pp_d0pat(out, dp)
)
and
pp_sig_farg_params(out: FILR, farg: f0arglst): void = (
  ps(out, "(");
  pp_sig_farg_dapps(out, farg);
  ps(out, ")")
)
and
pp_sig_farg_dapps(out: FILR, farg: f0arglst): void =
(
  case+ farg of
  | list_nil() => ()
  | list_cons(fa, rest) => (
      case+ fa.node() of
      | F0ARGdapp(dp) => pp_sig_farg_one(out, dp, rest)
      | _ => pp_sig_farg_dapps(out, rest))
)
and
pp_sig_farg_one(out: FILR, dp: d0pat, rest: f0arglst): void =
(
  case+ dp.node() of
  | D0Plpar(_, dps, _) => pp_dpat_sig_seq(out, dps)
  | D0Ptup1(_, _, dps, _) => pp_dpat_sig_seq(out, dps)
  | _ => pp_d0pat_sig(out, dp)
)
and
pp_dpat_sig_seq(out: FILR, dps: d0patlst): void =
(
  case+ dps of
  | list_nil() => ()
  | list_cons(dp, rest) => (
      pp_d0pat_sig(out, dp);
      (case+ rest of list_nil() => () | _ => ps(out, ", "));
      pp_dpat_sig_seq(out, rest))
)
and
pp_d0pat_sig(out: FILR, dp: d0pat): void =
(
  case+ dp.node() of
  | D0Pannot(dp1, se) => (pp_d0pat(out, dp1); ps(out, ": "); pp_s0exp(out, se))
  | D0Pqual0(_, dp1) => pp_d0pat_sig(out, dp1)
  | _ => pp_d0pat(out, dp)
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
// #define NAME val -> let <value-name> = val. The compiler macro-expands these
// constants before dynamic typechecking; modeling them as dynamic value bindings
// matches the corpus use sites (`STA`, `DYN`, bit flags, etc.). Symbolic macro
// aliases such as `#define :: list_cons` do not have a Pythonic binder spelling
// yet, so preserve them as inert comments instead of emitting invalid syntax.
fun
pp_define(out: FILR, n: sint, gid: g0eid, gedf: g0edf): void = let
  val raw = i0dnt_lexeme(gid)
  val nm = vname_bind(raw)
in
  if PYPP_identish(raw)
  then (
    ind(out, n); ps(out, "let "); ps(out, nm); ps(out, " = ");
    (case+ gedf of
     | G0EDFsome(_, ge) => pp_define_g0exp(out, ge)
     | G0EDFnone() => ps(out, "()"));
    nl(out))
  else (
    ind(out, n); ps(out, "# define "); ps(out, nm); ps(out, " = ");
    (case+ gedf of
     | G0EDFsome(_, ge) => pp_define_g0exp(out, ge)
     | G0EDFnone() => ps(out, "()"));
    nl(out))
end
and
pp_define_g0exp(out: FILR, ge: g0exp): void =
(
  case+ ge.node() of
  | G0Eid0(id) => ps(out, val_or_con_name(i0dnt_lexeme(id)))
  | G0Eint(t0) => (case+ t0 of T0INTsome(tok) => ps(out, tok_lexeme(tok)) | T0INTnone(tok) => ps(out, tok_lexeme(tok)))
  | G0Estr(t0) => (case+ t0 of T0STRsome(tok) => ps(out, tok_lexeme(tok)) | T0STRnone(tok) => ps(out, tok_lexeme(tok)))
  | G0Eapps(ges) => pp_define_g0apps(out, ges)
  | _ => ps(out, "# TODO(pp): g0exp")
)
and
pp_define_g0apps(out: FILR, ges: g0explst): void =
(
  case+ ges of
  | list_cons(gop, list_cons(arg, list_nil())) =>
      if pp_define_g0exp_is_id(gop, "-")
      then (ps(out, "-"); pp_define_g0exp(out, arg))
      else pp_define_g0app_fallback(out, ges)
  | _ => pp_define_g0app_fallback(out, ges)
)
and
pp_define_g0app_fallback(out: FILR, ges: g0explst): void =
(
  case+ ges of
  | list_nil() => ps(out, "# TODO(pp): g0exp")
  | list_cons(ge, rest) => (
      pp_define_g0exp(out, ge);
      (case+ rest of
       | list_nil() => ()
       | _ => (ps(out, " "); pp_define_g0app_fallback(out, rest))))
)
and
pp_define_g0exp_is_id(ge: g0exp, s: strn): bool =
(
  case+ ge.node() of
  | G0Eid0(id) => i0dnt_lexeme(id) = s
  | _ => false
)
// Render constructor/exception payload types without adding a second set of
// parentheses around the source `of (...)` group.
and
pp_tcon_argty(out: FILR, se: s0exp): void =
(
  case+ se.node() of
  | S0Elpar(_, ses, _) => pp_s0exp_seq(out, ses)
  | S0Etup1(_, _, ses, _) => pp_s0exp_seq(out, ses)
  | _ => pp_s0exp(out, se)
)
and
pp_excptcon_list(out: FILR, n: sint, tcns: d0tcnlst): void =
(
  case+ tcns of
  | list_nil() => ()
  | list_cons(tcn, rest) => (
      pp_excptcon(out, n, tcn);
      pp_excptcon_list(out, n, rest))
)
and
pp_excptcon(out: FILR, n: sint, tcn: d0tcn): void =
(
  case+ tcn.node() of
  | D0TCNnode(_, nm, _s0is, ofty) => (
      ind(out, n); ps(out, "exception "); ps(out, conname_scoped(i0dnt_lexeme(nm)));
      (case+ ofty of
       | optn_cons(se) =>
           if s0exp_is_nullary_payload(se)
           then ()
           else (ps(out, "("); pp_tcon_argty(out, se); ps(out, ")"))
       | optn_nil() => ());
      nl(out))
)
and
s0exp_is_nullary_payload(se: s0exp): bool =
(
  case+ se.node() of
  | S0Elpar(_, list_nil(), _) => true
  | S0Etup1(_, _, list_nil(), _) => true
  | S0Eannot(se1, _) => s0exp_is_nullary_payload(se1)
  | S0Equal0(_, se1) => s0exp_is_nullary_payload(se1)
  | S0Eerrck(_, se1) => s0exp_is_nullary_payload(se1)
  | _ => false
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
	      PYPP_type_scope_push();
	      pp_dexp_letdecls_bodyctx(out, n, body, decls);
	      pp_dexp_body_seq(out, n, body);
	      PYPP_type_scope_pop())
  //
  // a `case[+-] X of | p => e | ...` -> `match X:` then arms.
  | D0Ecas0(_, scrut, _, _, cls) => pp_dexp_match(out, n, scrut, cls)
  | D0Ecas1(_, scrut, _, _, cls, _) => pp_dexp_match(out, n, scrut, cls)
  //
  // MISC (Cluster E): `try BODY with | p => e | ...` (D0Etry0) -> the Pythonic `try:` / `except p:`
  // form. The BODY is the SMCLN-sequence d0explst; each clause `| p => e` becomes an `except <pat>:`
  // handler-suite. py->L2 (PCEtry -> D2Etry0) already round-trips; this is the ATS->py emit half.
  | D0Etry0(_, body, _, _, cls, _) => pp_dexp_try(out, n, body, cls)
  //
  // `if c then t else e`.
	  | D0Eift0(_, c, th, el) => pp_dexp_if(out, n, c, th, el)
	  | D0Eift1(_, c, th, el, _) => pp_dexp_if(out, n, c, th, el)
	  //
	  // Suite-position `e where { decls }`: hoist the backwards-scoped decls before
	  // the expression so side-effecting `val () = ...` where decls are preserved.
	  // Top-level impl bodies still print a trailing `where:` block via pp_impl_body.
		  | D0Ewhere(body0, wdc) => (
		      PYPP_type_scope_push();
		      pp_dexp_where_decls_ctx(out, n, body0, wdc);
		      pp_d0exp_suite(out, n, body0);
	        PYPP_type_scope_pop())
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
          | list_nil() => (ind(out, n); ps(out, "()"); nl(out))
          | list_cons(de1, list_nil()) => pp_d0exp_suite(out, n, de1)
          | _ => (ind(out, n); ps(out, "("); pp_dexp_seq_inline(out, des); ps(out, ")"); nl(out))))
  //
  | D0Eannot(de1, _) => pp_d0exp_suite(out, n, de1)
  | D0Equal0(_, de1) => pp_d0exp_suite(out, n, de1)
  //
  // a ref-set `r[] := e` is an APPS with `:=` — detected in pp_dexp_stmt. As a
  // whole-body it is a single statement.
  | D0Eapps(des) => (
      if pp_dexp_llazy_case_suite(out, n, des)
      then ()
      else (ind(out, n); pp_dexp_stmt_inline(out, de); nl(out)))
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
       // Every sequence elem may still be a compound statement (`if`, `case`,
       // `let`, nested sequence). The last one is the value, but the same suite
       // renderer is also the statement-safe spelling for non-final elems.
       | list_nil() => pp_d0exp_suite(out, n, de)
       | _ => pp_d0exp_suite(out, n, de));
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
  | D0Elpar(_, list_cons(de1, list_nil()), _) => pp_dexp_stmt_inline(out, de1)
  | D0Eannot(de1, _) => pp_dexp_stmt_inline(out, de1)
  | D0Equal0(_, de1) => pp_dexp_stmt_inline(out, de1)
  | D0Eerrck(_, de1) => pp_dexp_stmt_inline(out, de1)
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
and
pp_dexp_llazy_case_suite(out: FILR, n: sint, des: d0explst): bool =
(
  case+ des of
  | list_cons(hd, list_cons(arg, list_nil())) =>
      if dexp_is_llazy_head(hd)
      then pp_dexp_llazy_case_arg_suite(out, n, arg)
      else false
  | _ => false
)
and
pp_dexp_llazy_case_arg_suite(out: FILR, n: sint, arg: d0exp): bool =
(
  case+ arg.node() of
  | D0Elpar(_, list_cons(de, list_nil()), _) => pp_dexp_llazy_case_exp_suite(out, n, de)
  | D0Eannot(de1, _) => pp_dexp_llazy_case_arg_suite(out, n, de1)
  | D0Equal0(_, de1) => pp_dexp_llazy_case_arg_suite(out, n, de1)
  | D0Eerrck(_, de1) => pp_dexp_llazy_case_arg_suite(out, n, de1)
  | _ => pp_dexp_llazy_case_exp_suite(out, n, arg)
)
and
pp_dexp_llazy_case_exp_suite(out: FILR, n: sint, de: d0exp): bool =
(
  case+ de.node() of
  | D0Ecas0(_, scrut, _, _, cls) => (
      ind(out, n); ps(out, "llazy:"); nl(out);
      pp_dexp_match(out, n+1, scrut, cls);
      true)
  | D0Ecas1(_, scrut, _, _, cls, _) => (
      ind(out, n); ps(out, "llazy:"); nl(out);
      pp_dexp_match(out, n+1, scrut, cls);
      true)
  | _ => false
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
           | D0Edtsel(_, lab, opt) => pp_dexp_dtsel(out, lab, opt)
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
	pp_dexp_letdecls_ctx(out: FILR, n: sint, ctx: d0exp, decls: d0eclist): void =
	(
	  case+ decls of
	  | list_nil() => ()
	  | list_cons(dc, rest) => (
	      pp_dexp_letdecl_ctx(out, n, ctx, dc);
	      pp_dexp_letdecls_ctx(out, n, ctx, rest))
	)
	and
	pp_dexp_letdecls_bodyctx(out: FILR, n: sint, body: d0explst, decls: d0eclist): void =
	(
	  case+ decls of
	  | list_nil() => ()
	  | list_cons(dc, rest) => (
	      pp_dexp_letdecl_bodyctx(out, n, body, dc);
	      pp_dexp_letdecls_bodyctx(out, n, body, rest))
	)
	and
	pp_dexp_letdecl(out: FILR, n: sint, dc: d0ecl): void =
	(
	  case+ dc.node() of
	  // a `val+ P = e` / `val P = e` value binding -> `let P = e` (or just the stmt
	  // if P is the void pattern `()` — a side-effecting binding).
	  | D0Cvaldclst(_, vds) => pp_dexp_valdcls(out, n, vds)
	  | D0Cvardclst(_, vds) => pp_dexp_vardcls(out, n, vds)
	  | D0Cfundclst(_, _, fds) => pp_dexp_fundcl_local_list(out, n, fds)
	  | D0Cimplmnt0(tknd, sqas, tqas, dqi, tias, farg, _, _, body) =>
	        pp_dexp_impl_local(out, n, tknd, sqas, tqas, dqi, tias, farg, body)
	  | D0Csexpdef(_, sid, smas, _, _, se) => (
	        PYPP_type_add(i0dnt_lexeme(sid));
	        pp_typedef(out, n, sid, smas, se))
	  | D0Cdefine(_, gid, _, gedf) => pp_define(out, n, gid, gedf)
	  | D0Cexcptcon(_, _, tcns) => pp_excptcon_list(out, n, tcns)
	  | D0Clocal0(_, head, _, body, _) => pp_dexp_local_decls(out, n, head, body)
	  | D0Cstatic(_, dc1) => pp_dexp_letdecl(out, n, dc1)
	  | D0Cextern(_, dc1) => pp_dexp_extern_decl(out, n, dc1)
	  | D0Ctkerr(_) => ()
	  | D0Ctkskp(_) => ()
		  | _ => (ind(out, n); todo(out, "let-decl"))
		)
	and
	pp_dexp_letdecl_ctx(out: FILR, n: sint, ctx: d0exp, dc: d0ecl): void =
	(
	  case+ dc.node() of
		  | D0Cvaldclst(_, vds) => pp_dexp_valdcls_ctx(out, n, ctx, vds)
		  | D0Cstatic(_, dc1) => pp_dexp_letdecl_ctx(out, n, ctx, dc1)
		  | _ => pp_dexp_letdecl(out, n, dc)
	)
	and
	pp_dexp_letdecl_bodyctx(out: FILR, n: sint, body: d0explst, dc: d0ecl): void =
	(
	  case+ dc.node() of
		  | D0Cvaldclst(_, vds) => pp_dexp_valdcls_bodyctx(out, n, body, vds)
		  | D0Cstatic(_, dc1) => pp_dexp_letdecl_bodyctx(out, n, body, dc1)
		  | _ => pp_dexp_letdecl(out, n, dc)
	)
and
pp_dexp_local_decls(out: FILR, n: sint, head: d0eclist, body: d0eclist): void =
(
  if list_nilq(head)
  then pp_dexp_letdecls(out, n, body)
  else (
    ind(out, n); ps(out, "private:"); nl(out);
    pp_dexp_letdecls(out, n+1, head);
    nl(out);
    pp_dexp_letdecls(out, n, body))
)
and
pp_dexp_extern_decl(out: FILR, n: sint, dc: d0ecl): void =
(
  case+ dc.node() of
  // an `#extern fun <obj:vt> NAME(buf: !obj, ...)`: the OUTER template quantifier
  // `<obj:vt>` (tqas) names must be pushed as binders so the `!obj` PARAM type
  // capitalizes to `!Obj` (registering the template binder) — matching the impl
  // bodies and so a call to another `<obj>` template can infer its instantiation.
  | D0Cfundclst(_, tqas, fds) =>
      pp_dexp_extern_fundcl_list(out, n, tqag_names(tqas), tqag_raw_names(tqas), fds)
  | D0Cstatic(_, dc1) => pp_dexp_extern_decl(out, n, dc1)
  | D0Cextern(_, dc1) => pp_dexp_extern_decl(out, n, dc1)
  | _ => pp_dexp_letdecl(out, n, dc)
)
and
pp_dexp_extern_fundcl_list(out: FILR, n: sint, tps: list(strn), tps_raw: list(strn), fds: d0fundclist): void =
(
  case+ fds of
  | list_nil() => ()
  | list_cons(fd, rest) => (
      pp_dexp_extern_fundcl(out, n, tps, tps_raw, fd);
      (case+ rest of list_nil() => () | _ => nl(out));
      pp_dexp_extern_fundcl_list(out, n, tps, tps_raw, rest))
)
and
pp_dexp_extern_fundcl(out: FILR, n: sint, tps: list(strn), tps_raw: list(strn), fd: d0fundcl): void = let
  val nm   = i0dnt_lexeme(d0fundcl_get_dpid(fd))
  val farg = d0fundcl_get_farg(fd)
  val sres = d0fundcl_get_sres(fd)
  val tdxp = d0fundcl_get_tdxp(fd)
  // push BOTH the outer template binders (tps_raw, e.g. `obj`) and the per-fun
  // static-quant binders (farg sapp raws) so every binder USE in the signature lifts.
  val raws = list_append(tps_raw, farg_sapp_raw_names(farg))
  val tps1 = list_append(tps, farg_sapp_names(farg))
in
  push_binders(raws);
  ind(out, n); ps(out, "@extern"); nl(out);
  ind(out, n); ps(out, "def "); ps(out, fname(nm));
  pp_names_brkt(out, tps1);
  pp_sig_farg_params(out, farg);
  ps(out, " -> ");
  (case+ sres of
   | S0RESsome(_, se) => pp_s0exp(out, se)
   | S0RESnone() => ps(out, "Void"));
  // FFI: emit the `= extnam(["cname"])` foreign-name binding when the fundcl carries one (the
  // round-trip of stock `= $extnam(["cname"])`). A non-extnam / absent body emits nothing.
  pp_extnam_rhs(out, tdxp);
  nl(out);
  pop_binders(raws)
end
and
	pp_dexp_where_decls(out: FILR, n: sint, wdc: d0eclseq_WHERE): void =
	(
	  case+ wdc of
	  | d0eclseq_WHERE(_, _, dcs, _) => pp_dexp_letdecls(out, n, dcs)
	)
	and
	pp_dexp_where_decls_ctx(out: FILR, n: sint, ctx: d0exp, wdc: d0eclseq_WHERE): void =
	(
	  case+ wdc of
	  | d0eclseq_WHERE(_, _, dcs, _) => pp_dexp_letdecls_ctx(out, n, ctx, dcs)
	)
and
pp_dexp_impl_local
( out: FILR, n: sint, tknd: token, sqas: s0qaglst, tqas: t0qaglst, dqi: d0qid, tias: t0iaglst
, farg: f0arglst, body: d0exp): void = let
  val raws = impl_farg_raw_names(sqas, tqas, farg)
  val tps = impl_farg_names(sqas, tqas, farg)
in
  ind(out, n); ps(out, "@impl"); push_binders(raws); pp_impl_tias_for(out, tknd, tias); nl(out);
  ind(out, n); ps(out, "def "); ps(out, fname(d0qid_lexeme(dqi)));
  pp_names_brkt(out, tps);
  (if farg_has_dapp(farg) then pp_lam_farg_params(out, farg) else ());
  ps(out, ":"); nl(out);
  pp_dexp_fun_body(out, n, body);
  pop_binders(raws)
end
and
pp_dexp_fundcl_local_list(out: FILR, n: sint, fds: d0fundclist): void =
(
  case+ fds of
  | list_nil() => ()
  | list_cons(fd, rest) => (
      pp_dexp_fundcl_local(out, n, fd);
      (case+ rest of list_nil() => () | _ => nl(out));
      pp_dexp_fundcl_local_list(out, n, rest))
)
and
pp_dexp_fundcl_local(out: FILR, n: sint, fd: d0fundcl): void = let
  val nm   = i0dnt_lexeme(d0fundcl_get_dpid(fd))
  val farg = d0fundcl_get_farg(fd)
  val sres = d0fundcl_get_sres(fd)
  val tdxp = d0fundcl_get_tdxp(fd)
  val raws = farg_sapp_raw_names(farg)
  val tps  = farg_sapp_names(farg)
in
  push_binders(raws);
  ind(out, n); ps(out, "def "); ps(out, fname(nm));
  pp_names_brkt(out, tps);
  pp_sig_farg_params(out, farg);
  (case+ sres of
   | S0RESsome(_, se) => (ps(out, " -> "); pp_s0exp(out, se))
   | S0RESnone() => ());
  ps(out, ":"); nl(out);
  (case+ tdxp of
   | TEQD0EXPsome(_, body) => pp_dexp_fun_body(out, n, body)
   | TEQD0EXPnone() => (ind(out, n+1); todo(out, "fun-no-body")));
  pop_binders(raws)
end
and
	pp_dexp_fun_body(out: FILR, n: sint, body: d0exp): void =
	(
	  case+ body.node() of
	  | D0Ewhere(body0, wdc) => (
	      pp_dexp_fun_body(out, n, body0);
	      pp_dexp_where_block_ctx(out, n, body0, wdc))
	  | _ => pp_d0exp_suite(out, n+1, body)
	)
	and
	pp_dexp_where_block(out: FILR, n: sint, wdc: d0eclseq_WHERE): void =
(
  case+ wdc of
  | d0eclseq_WHERE(_, _, dcs, _) => (
      case+ dcs of
      | list_nil() => ()
      | _ => (
          PYPP_type_scope_push();
          ind(out, n); ps(out, "where:"); nl(out);
	          pp_dexp_letdecls(out, n+1, dcs);
	          PYPP_type_scope_pop()))
	)
	and
	pp_dexp_where_block_ctx(out: FILR, n: sint, ctx: d0exp, wdc: d0eclseq_WHERE): void =
	(
	  case+ wdc of
	  | d0eclseq_WHERE(_, _, dcs, _) => (
	      case+ dcs of
	      | list_nil() => ()
	      | _ => (
	          PYPP_type_scope_push();
	          ind(out, n); ps(out, "where:"); nl(out);
	          pp_dexp_letdecls_ctx(out, n+1, ctx, dcs);
	          PYPP_type_scope_pop()))
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
	pp_dexp_valdcls_ctx(out: FILR, n: sint, ctx: d0exp, vds: d0valdclist): void =
	(
	  case+ vds of
	  | list_nil() => ()
	  | list_cons(vd, rest) => (
	      pp_dexp_valdcl_ctx(out, n, ctx, vd);
	      pp_dexp_valdcls_ctx(out, n, ctx, rest))
	)
	and
	pp_dexp_valdcls_bodyctx(out: FILR, n: sint, body: d0explst, vds: d0valdclist): void =
	(
	  case+ vds of
	  | list_nil() => ()
	  | list_cons(vd, rest) => (
	      pp_dexp_valdcl_bodyctx(out, n, body, vd);
	      pp_dexp_valdcls_bodyctx(out, n, body, rest))
	)
	and
	pp_dexp_valdcl(out: FILR, n: sint, vd: d0valdcl): void = let
	  val dpat = d0valdcl_get_dpat(vd)
	  val tdxp = d0valdcl_get_tdxp(vd)
in
  case+ tdxp of
  | TEQD0EXPsome(_, rhs) => (
      // A void-pattern binding `val () = e` is a side-effecting statement. Route it
      // through the suite printer so expression-level `where` decls are preserved.
      if dpat_is_void(dpat)
      then pp_d0exp_suite(out, n, rhs)
      else pp_dexp_val_rhs(out, n, dpat, rhs))
	  | TEQD0EXPnone() => (ind(out, n); todo(out, "valdcl-no-rhs"))
	end
	and
	pp_dexp_valdcl_ctx(out: FILR, n: sint, ctx: d0exp, vd: d0valdcl): void = let
	  val dpat = d0valdcl_get_dpat(vd)
	  val tdxp = d0valdcl_get_tdxp(vd)
	in
	  case+ tdxp of
	  | TEQD0EXPsome(_, rhs) =>
	      if pp_dexp_val_map_sapp_ctx(out, n, ctx, dpat, rhs)
	      then ()
	      else pp_dexp_valdcl(out, n, vd)
	  | TEQD0EXPnone() => pp_dexp_valdcl(out, n, vd)
	end
	and
	pp_dexp_valdcl_bodyctx(out: FILR, n: sint, body: d0explst, vd: d0valdcl): void = let
	  val dpat = d0valdcl_get_dpat(vd)
	  val tdxp = d0valdcl_get_tdxp(vd)
	in
	  case+ tdxp of
	  | TEQD0EXPsome(_, rhs) =>
	      if pp_dexp_val_map_sapp_bodyctx(out, n, body, dpat, rhs)
	      then ()
	      else pp_dexp_valdcl(out, n, vd)
	  | TEQD0EXPnone() => pp_dexp_valdcl(out, n, vd)
	end
	and
	pp_dexp_vardcls(out: FILR, n: sint, vds: d0vardclist): void =
	(
  case+ vds of
  | list_nil() => ()
  | list_cons(vd, rest) => (
      pp_dexp_vardcl(out, n, vd);
      pp_dexp_vardcls(out, n, rest))
)
and
pp_dexp_vardcl(out: FILR, n: sint, vd: d0vardcl): void = let
  val dpid = d0vardcl_get_dpid(vd)
  val sres = d0vardcl_get_sres(vd)
  val dini = d0vardcl_get_dini(vd)
in
  case+ dini of
  | TEQD0EXPsome(_, rhs) => (
      ind(out, n); ps(out, "var "); ps(out, fname(i0dnt_lexeme(dpid)));
      (case+ sres of
       | optn_cons(se) => (ps(out, ": "); pp_s0exp(out, se))
       | optn_nil() => ());
      ps(out, " = "); pp_d0exp_inline(out, rhs); nl(out))
  | TEQD0EXPnone() => (ind(out, n); todo(out, "vardcl-no-rhs"))
end
and
pp_dexp_val_rhs(out: FILR, n: sint, dpat: d0pat, rhs: d0exp): void =
(
  case+ rhs.node() of
  | D0Eannot(rhs1, _) => pp_dexp_val_rhs(out, n, dpat, rhs1)
  | D0Equal0(_, rhs1) => pp_dexp_val_rhs(out, n, dpat, rhs1)
  | D0Eerrck(_, rhs1) => pp_dexp_val_rhs(out, n, dpat, rhs1)
  | D0Elpar(_, list_cons(rhs1, list_nil()), _) => pp_dexp_val_rhs(out, n, dpat, rhs1)
  // `val x = e where { fun h(...) = ... }` has expression-level backwards scope in ATS. The
  // Pythonic surface only accepts `where:` after `def`, so emit the helper declarations just before
  // the `let` binding in the same local suite. This preserves RHS resolution for bootstrapping and
  // keeps the output parseable; the helper may remain visible to following suite statements.
  | D0Ewhere(rhs1, wdc) => (
      pp_dexp_where_decls(out, n, wdc);
      pp_dexp_val_rhs(out, n, dpat, rhs1))
  | D0Elet0(_, decls, _, body, _) => (
      PYPP_type_scope_push();
      pp_dexp_letdecls(out, n, decls);
      pp_dexp_val_body_seq(out, n, dpat, body);
      PYPP_type_scope_pop())
  | D0Eift0(_, c, th, el) => pp_dexp_val_if_rhs(out, n, dpat, c, th, el)
  | D0Eift1(_, c, th, el, _) => pp_dexp_val_if_rhs(out, n, dpat, c, th, el)
  // MISC (Cluster E): `val P = try BODY with | p => e ...` -> `let P = try:` then the body-suite and
  // `except p:` handler-suites. The try is a VALUE in ATS; the pyfront re-parses `let P = try:`
  // (PyEtry rhs) -> PCEtry -> D2Etry0.
  | D0Etry0(_, body, _, _, cls, _) => (
      ind(out, n); ps(out, "let "); pp_d0pat(out, dpat); ps(out, " = try:"); nl(out);
      pp_dexp_stmts(out, n+1, body);
      pp_dexp_except_clauses(out, n, cls))
  | D0Ecas0(_, scrut, _, _, cls) => (
      ind(out, n); ps(out, "let "); pp_d0pat(out, dpat); ps(out, " = match ");
      pp_d0exp_inline(out, scrut); ps(out, ":"); nl(out);
      pp_dexp_clauses(out, n+1, cls))
  | D0Ecas1(_, scrut, _, _, cls, _) => (
      ind(out, n); ps(out, "let "); pp_d0pat(out, dpat); ps(out, " = match ");
      pp_d0exp_inline(out, scrut); ps(out, ":"); nl(out);
      pp_dexp_clauses(out, n+1, cls))
  | D0Eapps(des) => (
      if pp_dexp_val_llazy_case_rhs(out, n, dpat, des)
      then ()
      else (
        ind(out, n); ps(out, "let "); pp_d0pat(out, dpat); ps(out, " = ");
        pp_d0exp_inline(out, rhs); nl(out)))
  | _ => (
      ind(out, n); ps(out, "let "); pp_d0pat(out, dpat); ps(out, " = ");
      pp_d0exp_inline(out, rhs); nl(out))
)
and
pp_dexp_val_llazy_case_rhs(out: FILR, n: sint, dpat: d0pat, des: d0explst): bool =
(
  case+ des of
  | list_cons(hd, list_cons(arg, list_nil())) =>
      if dexp_is_llazy_head(hd)
      then pp_dexp_val_llazy_case_arg(out, n, dpat, arg)
      else false
  | _ => false
)
and
pp_dexp_val_llazy_case_arg(out: FILR, n: sint, dpat: d0pat, arg: d0exp): bool =
(
  case+ arg.node() of
  | D0Elpar(_, list_cons(de, list_nil()), _) => pp_dexp_val_llazy_case_exp(out, n, dpat, de)
  | D0Eannot(de1, _) => pp_dexp_val_llazy_case_arg(out, n, dpat, de1)
  | D0Equal0(_, de1) => pp_dexp_val_llazy_case_arg(out, n, dpat, de1)
  | D0Eerrck(_, de1) => pp_dexp_val_llazy_case_arg(out, n, dpat, de1)
  | _ => pp_dexp_val_llazy_case_exp(out, n, dpat, arg)
)
and
pp_dexp_val_llazy_case_exp(out: FILR, n: sint, dpat: d0pat, de: d0exp): bool =
(
  case+ de.node() of
  | D0Ecas0(_, scrut, _, _, cls) => (
      ind(out, n); ps(out, "let "); pp_d0pat(out, dpat); ps(out, " = llazy:"); nl(out);
      pp_dexp_match(out, n+1, scrut, cls);
      true)
  | D0Ecas1(_, scrut, _, _, cls, _) => (
      ind(out, n); ps(out, "let "); pp_d0pat(out, dpat); ps(out, " = llazy:"); nl(out);
      pp_dexp_match(out, n+1, scrut, cls);
      true)
  | _ => false
)
and
pp_dexp_val_if_rhs
( out: FILR, n: sint, dpat: d0pat, c: d0exp
, th: d0exp_THEN, el: d0exp_ELSE): void =
(
  ind(out, n); ps(out, "let "); pp_d0pat(out, dpat); ps(out, " = if ");
  pp_d0exp_inline(out, c); ps(out, ":"); nl(out);
  (case+ th of
   | d0exp_THEN_some(_, te) => pp_d0exp_suite(out, n+1, te)
   | d0exp_THEN_none(_) => (ind(out, n+1); todo(out, "if-then-empty")));
  ind(out, n); ps(out, "else: ");
  pp_dexp_else_expr_line(out, n, el)
)
and
pp_dexp_else_expr_line(out: FILR, n: sint, el: d0exp_ELSE): void =
(
  case+ el of
  | d0exp_ELSE_some(_, ee) => pp_d0exp_expr_line(out, n, ee)
  | d0exp_ELSE_none(_) => (ps(out, "# TODO(pp): if-else-empty"); nl(out))
)
and
pp_d0exp_expr_line(out: FILR, n: sint, de: d0exp): void =
(
  case+ de.node() of
  | D0Eannot(de1, _) => pp_d0exp_expr_line(out, n, de1)
  | D0Equal0(_, de1) => pp_d0exp_expr_line(out, n, de1)
  | D0Eerrck(_, de1) => pp_d0exp_expr_line(out, n, de1)
  | D0Elpar(_, list_cons(de1, list_nil()), _) => pp_d0exp_expr_line(out, n, de1)
  | D0Ecas0(_, scrut, _, _, cls) => (
      ps(out, "match "); pp_d0exp_inline(out, scrut); ps(out, ":"); nl(out);
      pp_dexp_clauses(out, n+1, cls))
  | D0Ecas1(_, scrut, _, _, cls, _) => (
      ps(out, "match "); pp_d0exp_inline(out, scrut); ps(out, ":"); nl(out);
      pp_dexp_clauses(out, n+1, cls))
  | D0Elet0(_, _, _, _, _) => pp_d0exp_block_expr_line(out, n, de)
  | D0Ewhere(_, _) => pp_d0exp_block_expr_line(out, n, de)
  | D0Eift0(_, _, _, _) => pp_d0exp_block_expr_line(out, n, de)
  | D0Eift1(_, _, _, _, _) => pp_d0exp_block_expr_line(out, n, de)
  | _ => (pp_d0exp_inline(out, de); nl(out))
)
and
pp_d0exp_block_expr_line(out: FILR, n: sint, de: d0exp): void =
(
  ps(out, "match ():"); nl(out);
  ind(out, n+1); ps(out, "case ():"); nl(out);
  pp_d0exp_suite(out, n+2, de)
)
and
pp_dexp_val_body_seq(out: FILR, n: sint, dpat: d0pat, body: d0explst): void =
(
  case+ body of
  | list_nil() => (ind(out, n); todo(out, "let-body-empty"))
  | list_cons(rhs, list_nil()) => pp_dexp_val_rhs(out, n, dpat, rhs)
  | list_cons(stmt, rest) => (
      ind(out, n); pp_dexp_stmt_inline(out, stmt); nl(out);
      pp_dexp_val_body_seq(out, n, dpat, rest))
)
// is the pattern the void/unit pattern `()` (an empty paren group)?
and
	dpat_is_void(dp: d0pat): bool =
	(
	  case+ dp.node() of
	  | D0Plpar(_, list_nil(), _) => true
	  | _ => false
	)
	and
	pp_dexp_val_map_sapp_ctx
	( out: FILR, n: sint, ctx: d0exp
	, dpat: d0pat, rhs: d0exp): bool = let
	  val pat = dpat_var_raw(dpat)
	  val kind = dexp_nil_map_kind(rhs)
	  val elem =
	    (if strn_eq(pat, "") then ""
	     else if strn_eq(kind, "") then ""
	     else dexp_context_map_elem(ctx, pat, kind)): strn
	in
	  if strn_eq(elem, "")
	  then false
	  else (pp_dexp_val_map_sapp_emit(out, n, dpat, elem, rhs); true)
	end
	and
	pp_dexp_val_map_sapp_bodyctx
	( out: FILR, n: sint, body: d0explst
	, dpat: d0pat, rhs: d0exp): bool = let
	  val pat = dpat_var_raw(dpat)
	  val kind = dexp_nil_map_kind(rhs)
	  val elem =
	    (if strn_eq(pat, "") then ""
	     else if strn_eq(kind, "") then ""
	     else dexp_body_context_map_elem(body, pat, kind)): strn
	in
	  if strn_eq(elem, "")
	  then false
	  else (pp_dexp_val_map_sapp_emit(out, n, dpat, elem, rhs); true)
	end
	and
	pp_dexp_val_map_sapp_emit
	(out: FILR, n: sint, dpat: d0pat, elem: strn, rhs: d0exp): void =
	(
	  ind(out, n); ps(out, "let "); pp_d0pat(out, dpat);
	  ps(out, " = @sapp["); ps(out, elem); ps(out, "] ");
	  pp_d0exp_inline(out, rhs); nl(out)
	)
	and
	dpat_var_raw(dp: d0pat): strn =
	(
	  case+ dp.node() of
	  | D0Pid0(id) => i0dnt_lexeme(id)
	  | D0Pannot(dp1, _) => dpat_var_raw(dp1)
	  | D0Pqual0(_, dp1) => dpat_var_raw(dp1)
	  | D0Perrck(_, dp1) => dpat_var_raw(dp1)
	  | _ => ""
	)
	and
	dexp_id_raw(de: d0exp): strn =
	(
	  case+ de.node() of
	  | D0Eid0(id) => i0dnt_lexeme(id)
	  | D0Eannot(de1, _) => dexp_id_raw(de1)
	  | D0Equal0(_, de1) => dexp_id_raw(de1)
	  | D0Eerrck(_, de1) => dexp_id_raw(de1)
	  | D0Elpar(_, list_cons(de1, list_nil()), _) => dexp_id_raw(de1)
	  | _ => ""
	)
	and
	dexp_nil_map_kind(de: d0exp): strn =
	(
	  case+ de.node() of
	  | D0Eannot(de1, _) => dexp_nil_map_kind(de1)
	  | D0Equal0(_, de1) => dexp_nil_map_kind(de1)
	  | D0Eerrck(_, de1) => dexp_nil_map_kind(de1)
	  | D0Elpar(_, list_cons(de1, list_nil()), _) => dexp_nil_map_kind(de1)
	  | D0Eapps(des) => dexp_nil_map_kind_apps(des)
	  | _ => ""
	)
	and
	dexp_nil_map_kind_apps(des: d0explst): strn =
	(
	  case+ des of
	  | list_cons(hd, rest) => let
	      val nm = dexp_name(hd)
	    in
	      if strn_eq(nm, "topmap_make_nil")
	      then (if dexp_is_plain_empty_call_tail(rest) then "topmap" else "")
	      else (
	        if strn_eq(nm, "stkmap_make_nil")
	        then (if dexp_is_plain_empty_call_tail(rest) then "stkmap" else "")
	        else "")
	    end
	  | _ => ""
	)
	and
	dexp_is_plain_empty_call_tail(des: d0explst): bool =
	(
	  case+ des of
	  | list_cons(de, rest) => (
	      case+ de.node() of
	      | D0Elpar(_, list_nil(), _) => dexp_is_plain_tail_done(rest)
	      | _ => false)
	  | _ => false
	)
	and
	dexp_is_plain_tail_done(des: d0explst): bool =
	(
	  case+ des of
	  | list_nil() => true
	  | _ => false
	)
	and
	dexp_body_context_map_elem(body: d0explst, vraw: strn, kind: strn): strn =
	(
	  case+ body of
	  | list_nil() => ""
	  | list_cons(de, list_nil()) => dexp_context_map_elem(de, vraw, kind)
	  | list_cons(_, rest) => dexp_body_context_map_elem(rest, vraw, kind)
	)
	and
	dexp_context_map_elem(ctx: d0exp, vraw: strn, kind: strn): strn =
	(
	  case+ ctx.node() of
	  | D0Eannot(ctx1, _) => dexp_context_map_elem(ctx1, vraw, kind)
	  | D0Equal0(_, ctx1) => dexp_context_map_elem(ctx1, vraw, kind)
	  | D0Eerrck(_, ctx1) => dexp_context_map_elem(ctx1, vraw, kind)
	  | D0Ewhere(ctx1, _) => dexp_context_map_elem(ctx1, vraw, kind)
	  | D0Elpar(_, list_cons(ctx1, list_nil()), _) => dexp_context_map_elem(ctx1, vraw, kind)
	  | D0Eapps(des) => dexp_context_map_elem_apps(des, vraw, kind)
	  | _ => ""
	)
	and
	dexp_context_map_elem_apps(des: d0explst, vraw: strn, kind: strn): strn =
	(
	  case+ des of
	  | list_cons(hd, rest) => let
	      val con0 = dexp_id_raw(hd)
	    in
	      if strn_eq(con0, "")
	      then ""
	      else dexp_context_map_elem_tail(con0, rest, vraw, kind)
	    end
	  | _ => ""
	)
	and
	dexp_context_map_elem_tail
	(con0: strn, rest: d0explst, vraw: strn, kind: strn): strn =
	(
	  case+ rest of
	  | list_nil() => ""
	  | list_cons(arggrp, _) => (
	      case+ arggrp.node() of
	      | D0Elpar(_, args, _) => dexp_context_map_elem_args(con0, 0, args, vraw, kind)
	      | D0Etup1(_, _, args, _) => dexp_context_map_elem_args(con0, 0, args, vraw, kind)
	      | _ => dexp_context_map_elem_args(con0, 0, list_cons(arggrp, list_nil()), vraw, kind))
	)
	and
	dexp_context_map_elem_args
	( con0: strn, idx: sint, args: d0explst
	, vraw: strn, kind: strn): strn =
	(
	  case+ args of
	  | list_nil() => ""
	  | list_cons(arg, rest) => let
	      val raw = dexp_id_raw(arg)
	    in
	      if strn_eq(raw, vraw)
	      then let
	        val elem = PYPP_con_maparg_elem(con0, idx, kind)
	      in
	        if strn_eq(elem, "")
	        then dexp_context_map_elem_args(con0, idx+1, rest, vraw, kind)
	        else elem
	      end
	      else dexp_context_map_elem_args(con0, idx+1, rest, vraw, kind)
	    end
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
//
// MISC (Cluster E): `try:` / `except <pat>:` emit for D0Etry0. The body is the SMCLN-sequence
// d0explst (rendered as a suite — each stmt on its own line); each ATS clause `| p => e` becomes an
// `except <pat>:` handler-suite. The clause uses pp_dexp_clause_except (an `except`-spelled twin of
// pp_dexp_clause, which spells `case`). Mirrors the pyfront p_try_expr surface exactly so the emitted
// text re-parses (PCEtry) and lowers to the same D2Etry0.
and
pp_dexp_try(out: FILR, n: sint, body: d0explst, cls: d0clslst): void = (
  ind(out, n); ps(out, "try:"); nl(out);
  pp_dexp_stmts(out, n+1, body);
  pp_dexp_except_clauses(out, n, cls)
)
and
pp_dexp_except_clauses(out: FILR, n: sint, cls: d0clslst): void =
(
  case+ cls of
  | list_nil() => ()
  | list_cons(cl, rest) => (
      pp_dexp_except_clause(out, n, cl);
      pp_dexp_except_clauses(out, n, rest))
)
and
pp_dexp_except_clause(out: FILR, n: sint, cl: d0cls): void =
(
  case+ cl.node() of
  | D0CLScls(gpt, _, body) => (
      ind(out, n); ps(out, "except ");
      pp_dexp_gpt(out, gpt); ps(out, ":"); nl(out);
      pp_d0exp_suite(out, n+1, body))
  | D0CLSgpt(gpt) => (
      ind(out, n); ps(out, "except ");
      pp_dexp_gpt(out, gpt); ps(out, ":"); nl(out);
      ind(out, n+1); ps(out, "()"); nl(out))
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
      ind(out, n+1); ps(out, "()"); nl(out))
)
// the guarded-pattern of a match arm: a plain pattern, or `p when guards`.
and
pp_dexp_gpt(out: FILR, gpt: d0gpt): void =
(
  case+ gpt.node() of
  | D0GPTpat(dp) => pp_d0pat(out, dp)
  | D0GPTgua(dp, _, gs) => (
      pp_d0pat(out, dp);
      pp_d0gua_if(out, gs))
)
and
pp_d0gua_if(out: FILR, gs: d0gualst): void =
(
  case+ gs of
  | list_nil() => ()
  | _ => (ps(out, " if "); pp_d0gualst_inline(out, gs))
)
and
pp_d0gualst_inline(out: FILR, gs: d0gualst): void =
(
  case+ gs of
  | list_nil() => ()
  | list_cons(g, rest) => (
      pp_d0gua_inline(out, g);
      (case+ rest of list_nil() => () | _ => (ps(out, " and "); pp_d0gualst_inline(out, rest))))
)
and
pp_d0gua_inline(out: FILR, g: d0gua): void =
(
  case+ g.node() of
  | D0GUAexp(de) => pp_d0exp_inline(out, de)
  | D0GUAmat(_, _, _) => ps(out, "# TODO(pp): when-match-guard")
)
//
(* ****** ****** *)
//
// an `if c: t else: e`.
//
// A `where`-wrapped CONDITION (`if (t where { val t = ... }) then ...`) has its
// helper decls in expression-level backwards scope in ATS. The Pythonic surface
// has no `where:` after a condition, so when the condition reduces (under thin
// transparent wrappers) to a `D0Ewhere`, hoist its decls as in-scope `let`-lines
// just before the `if` and render the if on the unwrapped condition — exactly as
// pp_dexp_val_rhs does for a `where`-wrapped val rhs. This is GATED on
// dexp_cond_has_where(c): a condition with no `where` is unchanged (falls through
// to the original inline rendering, so non-where files are byte-identical).
//
and
pp_dexp_if(out: FILR, n: sint, c: d0exp, th: d0exp_THEN, el: d0exp_ELSE): void = (
  if dexp_cond_has_where(c)
  then pp_dexp_if_where(out, n, c, th, el)
  else (
    ind(out, n); ps(out, "if "); pp_d0exp_inline(out, c); ps(out, ":"); nl(out);
    (case+ th of
     | d0exp_THEN_some(_, te) => pp_d0exp_suite(out, n+1, te)
     | d0exp_THEN_none(_) => (ind(out, n+1); todo(out, "if-then-empty")));
    (case+ el of
     | d0exp_ELSE_some(_, ee) => (
         ind(out, n); ps(out, "else:"); nl(out);
         pp_d0exp_suite(out, n+1, ee))
     | d0exp_ELSE_none(_) => ()))
)
// total: peels only the thin transparent wrappers that pp_d0exp_inline itself sees
// through, reporting true exactly when the condition's core is a `D0Ewhere`. Every
// recursive arm strips one constructor, so it terminates on every d0exp.
and
dexp_cond_has_where(c: d0exp): bool =
(
  case+ c.node() of
  | D0Ewhere(_, _) => true
  | D0Elpar(_, list_cons(c0, list_nil()), _) => dexp_cond_has_where(c0)
  | D0Eannot(c0, _) => dexp_cond_has_where(c0)
  | D0Equal0(_, c0) => dexp_cond_has_where(c0)
  | D0Eerrck(_, c0) => dexp_cond_has_where(c0)
  | _ => false
)
// total: only entered after dexp_cond_has_where(c) is true, so a `D0Ewhere` is
// reachable through the wrapper arms; each arm strips one constructor toward it.
// The final `_` arm is a safe fallback (renders the if inline, never throws or
// loops) and is unreachable for a where-carrying condition.
and
pp_dexp_if_where(out: FILR, n: sint, c: d0exp, th: d0exp_THEN, el: d0exp_ELSE): void =
(
  case+ c.node() of
  | D0Ewhere(c0, wdc) => (
      PYPP_type_scope_push();
      pp_dexp_where_decls(out, n, wdc);
      pp_dexp_if_where(out, n, c0, th, el);
      PYPP_type_scope_pop())
  | D0Elpar(_, list_cons(c0, list_nil()), _) => pp_dexp_if_where(out, n, c0, th, el)
  | D0Eannot(c0, _) => pp_dexp_if_where(out, n, c0, th, el)
  | D0Equal0(_, c0) => pp_dexp_if_where(out, n, c0, th, el)
  | D0Eerrck(_, c0) => pp_dexp_if_where(out, n, c0, th, el)
  | _ => (
      ind(out, n); ps(out, "if "); pp_d0exp_inline(out, c); ps(out, ":"); nl(out);
      (case+ th of
       | d0exp_THEN_some(_, te) => pp_d0exp_suite(out, n+1, te)
       | d0exp_THEN_none(_) => (ind(out, n+1); todo(out, "if-then-empty")));
      (case+ el of
       | d0exp_ELSE_some(_, ee) => (
           ind(out, n); ps(out, "else:"); nl(out);
           pp_d0exp_suite(out, n+1, ee))
       | d0exp_ELSE_none(_) => ()))
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
           PYPP_type_add(i0dnt_lexeme(nm));
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
       | D0TCNnode(_, nm, _, _) => PYPP_con_add(i0dnt_lexeme(nm)));
      register_d0tcn_names(rest))
)
//
// the leading decorator for a non-default datatype HEAD, keyed by the `D0Cdatatype`
// token's `T_DATATYPE(knd)` sort: `datavwtp`/`datavtype` (VWTPSORT/VTBXSORT) -> `@linear`
// (a LINEAR datatype, M3 mode PCMlin -> vtbx; matching the linear cons), `dataprop`
// (PROPSORT) -> `@prop`, `dataview` (VIEWSORT) -> `@view`. A plain `datatype` (TYPESORT)
// carries no decorator. Dropping the decorator emitted a bare `enum`, which M3 lowered as
// BOXED (PCMbox -> tbox) — diverging from the linear/prop/view head sort and yielding the
// improper-base `S2Tbas(T2Bimpr(..))` reparse error.
// int equality wrapped as a boolean-returning application (the xats2js front-end accepts
// `else if f(..) then ..` only when the condition is an APPLICATION, not a bare paren-group
// `(knd = N)` — that shape derails its `else if` chain). knd_eq keeps the chain parseable.
fun
knd_eq(knd: int, srt: int): bool = (knd = srt)
//
fun
dt_kind_deco(tok: token): strn =
(
  case+ tok.node() of
  | T_DATATYPE(knd) => (
      if knd_eq(knd, VWTPSORT) then "@linear"
      else if knd_eq(knd, VTBXSORT) then "@linear"
      else if knd_eq(knd, PROPSORT) then "@prop"
      else if knd_eq(knd, VIEWSORT) then "@view"
      else "")
  | _ => ""
)
//
fun
pp_d0typ_enum(out: FILR, n: sint, deco: strn, dt: d0typ): void =
(
  case+ dt.node() of
  | D0TYPnode(nm, tmas, _, _, tcns) => let
      val raws = pp_tmag_raw_names(tmas)
      val tps = pp_tmag_datatype_names(tmas)
    in
      // a non-default head (`@linear`/`@prop`/`@view`) emits its decorator on its OWN line
      // first (§5.7: prefix decorators are line-terminated), then the `enum` declaration.
      (if ~(strn_eq(deco, "")) then (ind(out, n); ps(out, deco); nl(out)));
      ind(out, n); ps(out, "enum "); ps(out, tyname_scoped(i0dnt_lexeme(nm)));
      pp_names_brkt(out, tps);
      ps(out, ":"); nl(out);
      push_binders(raws);
      pp_d0tcns(out, n+1, tcns);
      pop_binders(raws)
    end
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
  | D0TCNnode(_, nm, _s0is, ofty) => let
      val con0 = i0dnt_lexeme(nm)
      val () = register_tcon_map_args(con0, ofty)
    in
      ind(out, n); ps(out, "case "); ps(out, conname_scoped(con0));
      (case+ ofty of
       | optn_cons(se) => (ps(out, "("); pp_tcon_argty(out, se); ps(out, ")"))
       | optn_nil() => ());
      nl(out)
    end
)
and
register_tcon_map_args(con0: strn, ofty: s0expopt): void =
(
  case+ ofty of
  | optn_nil() => ()
  | optn_cons(se) => register_tcon_map_args_s0exp(con0, 0, se)
)
and
register_tcon_map_args_s0exp(con0: strn, idx: sint, se: s0exp): void =
(
  case+ se.node() of
  | S0Elpar(_, ses, _) => register_tcon_map_args_seq(con0, idx, ses)
  | S0Etup1(_, _, ses, _) => register_tcon_map_args_seq(con0, idx, ses)
  | _ => register_tcon_map_arg_one(con0, idx, se)
)
and
register_tcon_map_args_seq(con0: strn, idx: sint, ses: s0explst): void =
(
  case+ ses of
  | list_nil() => ()
  | list_cons(se, rest) => (
      register_tcon_map_arg_one(con0, idx, se);
      register_tcon_map_args_seq(con0, idx+1, rest))
)
and
register_tcon_map_arg_one(con0: strn, idx: sint, se: s0exp): void = let
  val @(kind, elem) = s0exp_map_kind_elem(se)
in
  if strn_eq(elem, "")
  then ()
  else PYPP_con_maparg_add(con0, idx, kind, elem)
end
and
s0exp_map_kind_elem(se: s0exp): @(strn, strn) =
(
  case+ se.node() of
  | S0Eannot(se1, _) => s0exp_map_kind_elem(se1)
  | S0Equal0(_, se1) => s0exp_map_kind_elem(se1)
  | S0Eapps(ses) => s0exp_map_kind_elem_apps(ses)
  | _ => @("", "")
)
and
s0exp_map_kind_elem_apps(ses: s0explst): @(strn, strn) =
(
  case+ ses of
  | list_cons(hd, list_cons(arg, list_nil())) => (
      case+ hd.node() of
      | S0Eid0(id) => let
          val kind = i0dnt_lexeme(id)
          val elem = s0exp_single_static_arg_name(arg)
        in
          if strn_eq(kind, "topmap")
          then @("topmap", elem)
          else (
            if strn_eq(kind, "stkmap")
            then @("stkmap", elem)
            else @("", ""))
        end
      | _ => @("", ""))
  | _ => @("", "")
)
and
s0exp_single_static_arg_name(se: s0exp): strn =
(
  case+ se.node() of
  | S0Elpar(_, list_cons(se1, list_nil()), _) => s0exp_static_arg_name(se1)
  | S0Etup1(_, _, list_cons(se1, list_nil()), _) => s0exp_static_arg_name(se1)
  | _ => s0exp_static_arg_name(se)
)
and
s0exp_static_arg_name(se: s0exp): strn =
(
  case+ se.node() of
  | S0Eid0(id) => tyname_scoped(i0dnt_lexeme(id))
  | S0Eannot(se1, _) => s0exp_static_arg_name(se1)
  | S0Equal0(_, se1) => s0exp_static_arg_name(se1)
  | _ => ""
)
//
fun
pp_absimpl(out: FILR, n: sint, sqid: s0qid, smas: s0maglst, se: s0exp): void = let
  val raws = pp_smag_raw_names(smas)
  val tps = pp_smag_names(smas)
in
  ind(out, n); ps(out, "@impl"); nl(out);
  ind(out, n); ps(out, "type "); ps(out, tyname(s0qid_lexeme(sqid)));
  pp_names_brkt(out, tps);
  ps(out, " = ");
  push_binders(raws);
  pp_s0exp(out, se);
  pop_binders(raws);
  nl(out)
end
//
(* ****** ****** *)
//
// ====================== DYNAMIC side: #implfun (fundcl) ===================
//
// `#implfun f(args) = body`  parses to a D0Cfundclst(FUN, _, [d0fundcl]).  Each
// d0fundcl has dpid (name), farg (f0arglst), and tdxp (the `= body`).  We emit
//   `@impl`
//   `def f(params): <body-suite>`
// with UNANNOTATED params (the .dats carries no param types — they are inferred,
// which the frontend's inline-implement path accepts at nerror=0).
//
	fun
	pp_impl_n
	( out: FILR, n: sint, tknd: token, sqas: s0qaglst, tqas: t0qaglst, dqi: d0qid, tias: t0iaglst
	, farg: f0arglst, body: d0exp): void = let
	  val raws = impl_farg_raw_names(sqas, tqas, farg)
	  val tps = impl_farg_names(sqas, tqas, farg)
	in
	  ind(out, n); ps(out, "@impl"); push_binders(raws); pp_impl_tias_for(out, tknd, tias); nl(out);
	  ind(out, n); ps(out, "def "); ps(out, fname(d0qid_lexeme(dqi)));
	  pp_names_brkt(out, tps);
	  (if farg_has_dapp(farg) then pp_farg_params(out, farg) else ());
	  ps(out, ":"); nl(out);
	  pp_impl_body(out, n, body);
	  pop_binders(raws)
	end
	and
	pp_fundcl_impl(out: FILR, n: sint, fd: d0fundcl): void = let
	  val nm   = i0dnt_lexeme(d0fundcl_get_dpid(fd))
	  val farg = d0fundcl_get_farg(fd)
	  val tdxp = d0fundcl_get_tdxp(fd)
	  val raws = farg_sapp_raw_names(farg)
	  val tps = farg_sapp_names(farg)
in
  ind(out, n); ps(out, "@impl"); nl(out);
  ind(out, n); ps(out, "def "); ps(out, fname(nm)); push_binders(raws);
  pp_names_brkt(out, tps);
  pp_farg_params(out, farg);
  ps(out, ":"); nl(out);
	  (case+ tdxp of
	   | TEQD0EXPsome(_, body) => pp_impl_body(out, n, body)
	   | TEQD0EXPnone() => (ind(out, n+1); todo(out, "impl-no-body")));
  pop_binders(raws)
	end
	and
pp_fundcl_local(out: FILR, n: sint, fd: d0fundcl): void = let
  val nm   = i0dnt_lexeme(d0fundcl_get_dpid(fd))
  val farg = d0fundcl_get_farg(fd)
  val sres = d0fundcl_get_sres(fd)
  val tdxp = d0fundcl_get_tdxp(fd)
  val raws = farg_sapp_raw_names(farg)
  val tps  = farg_sapp_names(farg)
in
  push_binders(raws);
  ind(out, n); ps(out, "def "); ps(out, fname(nm));
  pp_names_brkt(out, tps);
  pp_sig_farg_params(out, farg);
  (case+ sres of
   | S0RESsome(_, se) => (ps(out, " -> "); pp_s0exp(out, se))
   | S0RESnone() => ());
  ps(out, ":"); nl(out);
  (case+ tdxp of
   | TEQD0EXPsome(_, body) => pp_impl_body(out, n, body)
	   | TEQD0EXPnone() => (ind(out, n+1); todo(out, "fun-no-body")));
  pop_binders(raws)
	end
	and
	pp_impl_body(out: FILR, n: sint, body: d0exp): void =
	  pp_impl_body_where(out, n, body, list_nil())
and
	pp_impl_body_where(out: FILR, n: sint, body: d0exp, wdcs: list(d0eclseq_WHERE)): void =
	(
	  case+ body.node() of
	  | D0Ewhere(body0, wdc) => pp_impl_body_where(out, n, body0, list_cons(wdc, wdcs))
	  | _ => (pp_d0exp_suite(out, n+1, body); pp_impl_flat_where_blocks_ctx(out, n, body, wdcs))
	)
and
impl_where_seq_has_decls(wdc: d0eclseq_WHERE): bool =
(
  case+ wdc of
  | d0eclseq_WHERE(_, _, dcs, _) => ~(list_nilq(dcs))
)
and
impl_where_blocks_has_decls(wdcs: list(d0eclseq_WHERE)): bool =
(
  case+ wdcs of
  | list_nil() => false
  | list_cons(wdc, rest) =>
      if impl_where_seq_has_decls(wdc) then true else impl_where_blocks_has_decls(rest)
)
and
	pp_impl_flat_where_blocks(out: FILR, n: sint, wdcs: list(d0eclseq_WHERE)): void =
	(
	  if impl_where_blocks_has_decls(wdcs)
  then (
    PYPP_type_scope_push();
    ind(out, n); ps(out, "where:"); nl(out);
    pp_impl_flat_where_decls(out, n+1, wdcs);
    PYPP_type_scope_pop())
	  else ()
	)
	and
	pp_impl_flat_where_blocks_ctx(out: FILR, n: sint, ctx: d0exp, wdcs: list(d0eclseq_WHERE)): void =
	(
	  if impl_where_blocks_has_decls(wdcs)
	  then (
	    PYPP_type_scope_push();
	    ind(out, n); ps(out, "where:"); nl(out);
	    pp_impl_flat_where_decls_ctx(out, n+1, ctx, wdcs);
	    PYPP_type_scope_pop())
	  else ()
	)
	and
	pp_impl_flat_where_decls(out: FILR, n: sint, wdcs: list(d0eclseq_WHERE)): void =
	(
	  case+ wdcs of
  | list_nil() => ()
  | list_cons(wdc, rest) => (
	      pp_impl_flat_where_decls(out, n, rest);
	      pp_impl_where_seq_decls(out, n, wdc))
	)
	and
	pp_impl_flat_where_decls_ctx(out: FILR, n: sint, ctx: d0exp, wdcs: list(d0eclseq_WHERE)): void =
	(
	  case+ wdcs of
	  | list_nil() => ()
	  | list_cons(wdc, rest) => (
	      pp_impl_flat_where_decls_ctx(out, n, ctx, rest);
	      pp_impl_where_seq_decls_ctx(out, n, ctx, wdc))
	)
	and
	pp_impl_where_seq_decls(out: FILR, n: sint, wdc: d0eclseq_WHERE): void =
	(
	  case+ wdc of
	  | d0eclseq_WHERE(_, _, dcs, _) => pp_where_decls(out, n, dcs)
	)
	and
	pp_impl_where_seq_decls_ctx(out: FILR, n: sint, ctx: d0exp, wdc: d0eclseq_WHERE): void =
	(
	  case+ wdc of
	  | d0eclseq_WHERE(_, _, dcs, _) => pp_where_decls_ctx(out, n, ctx, dcs)
	)
	and
pp_where_block(out: FILR, n: sint, wdc: d0eclseq_WHERE): void =
(
  case+ wdc of
  | d0eclseq_WHERE(_, _, dcs, _) => (
      case+ dcs of
      | list_nil() => ()
      | _ => (
          PYPP_type_scope_push();
          ind(out, n); ps(out, "where:"); nl(out);
          pp_where_decls(out, n+1, dcs);
          PYPP_type_scope_pop()))
)
and
	pp_where_decls(out: FILR, n: sint, dcs: d0eclist): void =
	(
	  case+ dcs of
  | list_nil() => ()
  | list_cons(dc, rest) => (
	      pp_where_decl(out, n, dc);
	      pp_where_decls(out, n, rest))
	)
	and
	pp_where_decls_ctx(out: FILR, n: sint, ctx: d0exp, dcs: d0eclist): void =
	(
	  case+ dcs of
	  | list_nil() => ()
	  | list_cons(dc, rest) => (
	      pp_where_decl_ctx(out, n, ctx, dc);
	      pp_where_decls_ctx(out, n, ctx, rest))
	)
	and
		pp_where_decl(out: FILR, n: sint, dc: d0ecl): void =
		(
		  case+ dc.node() of
	  | D0Cvaldclst(_, vds) => pp_dexp_valdcls(out, n, vds)
	  | D0Cfundclst(_, _, fds) => pp_fundcl_local_list_n(out, n, fds)
	  | D0Cimplmnt0(tknd, sqas, tqas, dqi, tias, farg, _, _, body) => pp_impl_n(out, n, tknd, sqas, tqas, dqi, tias, farg, body)
	  | D0Csexpdef(_, sid, smas, _, _, se) => (
	      PYPP_type_add(i0dnt_lexeme(sid));
	      pp_typedef(out, n, sid, smas, se))
	  | D0Cdefine(_, gid, _, gedf) => pp_define(out, n, gid, gedf)
	  | D0Cexcptcon(_, _, tcns) => pp_excptcon_list(out, n, tcns)
	  | D0Clocal0(_, head, _, body, _) => pp_where_local_decls(out, n, head, body)
	  | D0Cstatic(_, dc1) => pp_where_decl(out, n, dc1)
	  | D0Cextern(_, dc1) => pp_dexp_extern_decl(out, n, dc1)
	  | D0Csymload(_, sym, _, dqi, prec) => pp_symload_alias(out, n, sym, dqi, prec)
	  | D0Ctkerr(_) => ()
	  | D0Ctkskp(_) => ()
		  | _ => (ind(out, n); todo(out, "where-decl"))
		)
	and
	pp_where_decl_ctx(out: FILR, n: sint, ctx: d0exp, dc: d0ecl): void =
	(
	  case+ dc.node() of
	  | D0Cvaldclst(_, vds) => pp_dexp_valdcls_ctx(out, n, ctx, vds)
	  | D0Cstatic(_, dc1) => pp_where_decl_ctx(out, n, ctx, dc1)
	  | _ => pp_where_decl(out, n, dc)
	)
	and
	pp_where_local_decls(out: FILR, n: sint, head: d0eclist, body: d0eclist): void =
(
  if list_nilq(head)
  then pp_where_decls(out, n, body)
  else (
    ind(out, n); ps(out, "private:"); nl(out);
    pp_where_decls(out, n+1, head);
    nl(out);
    pp_where_decls(out, n, body))
)
and
pp_fundcl_impl_list_n(out: FILR, n: sint, fds: d0fundclist): void =
(
  case+ fds of
  | list_nil() => ()
  | list_cons(fd, rest) => (
      pp_fundcl_impl(out, n, fd);
	      (case+ rest of list_nil() => () | _ => nl(out));
	      pp_fundcl_impl_list_n(out, n, rest))
	)
	and
	pp_fundcl_local_list_n(out: FILR, n: sint, fds: d0fundclist): void =
	(
	  case+ fds of
	  | list_nil() => ()
	  | list_cons(fd, rest) => (
	      pp_fundcl_local(out, n, fd);
	      (case+ rest of list_nil() => () | _ => nl(out));
	      pp_fundcl_local_list_n(out, n, rest))
	)
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
       | D0Cdatatype(_, dts, wdc) => (
           register_d0typ_names(dts);
           // a datatype `where { ... }` may declare helper datatypes (e.g. an inner `datavwtp`);
           // register their names too so the inner cons capitalize at every use site.
           register_datatype_where_names(wdc))
       | D0Cexcptcon(_, _, tcns) => register_d0tcn_names(tcns)
       | D0Csexpdef(_, sid, _, _, _, _) => PYPP_type_add(i0dnt_lexeme(sid))
       | D0Clocal0(_, head, _, body, _) => (
           register_file_local_names(head);
           register_file_local_names(body))
       | _ => ());
      register_file_local_names(rest))
)
and
// register the datatype names declared inside a datatype's `where { ... }` clause (mutually
// recursive with register_file_local_names so nested `local`/`where` heads are covered too).
register_datatype_where_names(wdc: wd0eclseq): void =
(
  case+ wdc of
  | WD0CSnone() => ()
  | WD0CSsome(_, _, dcs, _) => register_file_local_names(dcs)
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
  // a top-level `datatype` -> an `enum` (capitalize the type + cons). A datatype may carry a
  // `where { ... }` clause whose nested declarations (typically a helper `datavwtp` the outer
  // cons reference, e.g. `datavwtp t3r0evn = T3R0EVN of trdstk where { datavwtp trdstk = ... }`)
  // belong in the SAME enclosing scope. Emit those where-decls FIRST (so forward references such
  // as `T3R0EVN of trdstk` resolve), then the enum itself. Dropping them left the inner cons
  // unresolved (D1Eid0). pp_datatype_where_decls recurses through pp_walk -> pp_d0ecl.
  | D0Cdatatype(dtok, dts, wdc) => (pp_datatype_where_decls(out, wdc); pp_d0typ_enum_list(out, 0, dt_kind_deco(dtok), dts); true)
  //
  // `excptcon E of (T)` -> `exception E(T)`.
  | D0Cexcptcon(_, _, tcns) => (pp_excptcon_list(out, 0, tcns); true)
  //
  // `#implfun f(args) = body`  ->  `@impl` + `def f(args): body`.  `#implfun` lexes to
  // T_IMPLMNT(IMPLfun) and parses to D0Cimplmnt0 (the implement decl): name (d0qid),
  // f0arglst (params), s0res, and the d0exp body.
  | D0Cimplmnt0(tknd, sqas, tqas, dqi, tias, farg, _, _, body) => (pp_impl(out, tknd, sqas, tqas, dqi, tias, farg, body); true)
  // an ordinary `fun f(x) = e` reaches here as D0Cfundclst. It creates a fresh
  // function binding, unlike an `@impl`-decorated def, which requires an existing signature.
  | D0Cfundclst(_, _, fds) => (pp_fundcl_local_list_n(out, 0, fds); true)
  //
  // a top-level dynamic value binding (`val name = e`) -> plain `let name = e`.
  | D0Cvaldclst(_, vds) => (pp_topval(out, vds); true)
  //
  // `#staload "x"` (a .sats interface) -> a scoped Pythonic import of the interface.
  | D0Cstaload(_, _, ge) => (pp_staload(out, ge); true)
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
  | D0Csexpdef(_, sid, smas, _, _, se) => (pp_typedef(out, 0, sid, smas, se); true)
  //
  // bodyless val / fun (in a .sats interface)  ->  @static let / @extern def
  | D0Cdynconst(tok, tqas, dcds) => (pp_dynconst(out, tok, tqas, dcds); true)
  //
  // #absimpl T = REP  ->  @impl type T = REP
  | D0Cabsimpl(_, sqid, smas, _, _, se) => (pp_absimpl(out, 0, sqid, smas, se); true)
  //
  // #extern fun f(...): R  ->  @extern def f(...) -> R
  | D0Cextern(_, dc1) => (pp_dexp_extern_decl(out, 0, dc1); true)
  //
  // #symload NAME with FN [of prec]  ->  @overload[prec] NAME = FN
  | D0Csymload(_, sym, _, dqi, prec) => (pp_symload_alias(out, 0, sym, dqi, prec); true)
  //
  // #define NAME val  ->  let name = val   (dynamic macro-constant model).
  | D0Cdefine(_, gid, _, gedf) => (pp_define(out, 0, gid, gedf); true)
  //
  // #include "x" -> the FAITHFUL pythonic `include "x"`. Stock `#include` is a TEXTUAL/inline
  // expansion (it splices the referenced file's decls into THIS file's tree), NOT a staload/env
  // merge — so it maps to the distinct `include` keyword (lowered via lower_include -> D2Cinclude),
  // not `from "x" import *` (which is a #staload -> D2Cstaload). This makes an include-bearing file's
  // round-tripped L2 structurally identical to stock's. The path is normalized XATSHOME-relative.
  | D0Cinclude(_, _, ge) => (
      ps(out, "include \""); ps(out, PYPP_import_path(g0exp_import_path(ge))); ps(out, "\""); nl(out);
      true
    )
  //
  // MISC (Cluster E): `#dyninit "PATH"` -> the FAITHFUL pythonic `initialize "PATH"` (D0Cdyninit ->
  // D2Cdyninit). The path is kept VERBATIM (no normalization — stock f0_dyninit keeps it verbatim);
  // we emit the raw string lexeme content (g0exp_dyninit_path unquotes the carrier).
  | D0Cdyninit(_, ge) => (
      ps(out, "initialize \""); ps(out, g0exp_dyninit_path(ge)); ps(out, "\""); nl(out);
      true
    )
  //
  // ============ Cluster B — fixity DSL (operator-precedence declarations) ======
  //
  // `#infixl + of 50` -> `infixl 50 +` : the ATS fixity keywords are KEPT VERBATIM in the pythonic
  // surface (project-owner LOCKED), only the SHAPE flips (keyword PREC NAME(s) — the precedence
  // precedes the names). The keyword is decoded from the T_SRP_FIXITY(knd) code (KINFIX0/KINFIXL/
  // KINFIXR/KPREFIX/KPSTFIX); the precedence is the precopt's int-token lexeme (omitted for a bare
  // `#infixl +`); the names are the i0dnt lexemes (symbolic `+`/`**` or alphanumeric `app`). The
  // round-tripped pythonic re-lexes the keyword, re-parses to PyCfixity, and re-lowers to the SAME
  // stock L2 (D2Cd1ecl(D1Cd0ecl(D0Cfixity(...)))) — a faithful pass-through (pylower build_fixity).
  | D0Cfixity(tknd, id0s, popt) => (
      ps(out, fixity_kw_of_token(tknd)); ps(out, " ");
      pp_fixity_prec(out, popt);            // emits "PREC " when present (else nothing)
      pp_fixity_names(out, id0s);
      nl(out);
      true
    )
  // `#nonfix foo` -> `nonfix foo` : strip an operator's fixity. No precedence; just the name(s).
  | D0Cnonfix(_, id0s) => (
      ps(out, "nonfix "); pp_fixity_names(out, id0s); nl(out);
      true
    )
  //
  // ============ Cluster A — static / sort KERNEL declarations =================
  //
  // `#sortdef num = int`  ->  `@sort type Num = SInt`   (a SORT ALIAS). The RHS s0tdf is the
  // sort being aliased; S0TDFsort carries the sort0 (the kernel forms are bare id-sorts, mapped
  // via sort0_py: int->SInt, bool->SBool, type->Type). The alias name is a SORT id, capitalized
  // to the pythonic UIDENT the `@sort type` parser expects (lowering uncapitalizes it back). The
  // refined `S0TDFtsub` subset form is rare in the kernel; we emit the bare alias for it (defensive).
  | D0Csortdef(_, sid, _, tdf) => (
      ps(out, "@sort"); nl(out);
      ps(out, "type "); ps(out, tyname(i0dnt_lexeme(sid))); ps(out, " = ");
      (case+ tdf.node() of
       | S0TDFsort(s0t) => ps(out, sort0_py(s0t))
       | _ => ps(out, "Type"));
      nl(out);
      true
    )
  //
  // `#stacst0 c : int`  ->  `@static let c: SInt`   (a STATIC CONSTANT decl). The `: sort0` is the
  // constant's sort, rendered pythonically (int->SInt, ...). Parses back via the bodyless `@static
  // let` path (pyelab_decl: bodyless + @static -> PCCstacst -> D2Cstacst0). The const name is a
  // VALUE-level id and is kept lowercase (an `@static let` binder is a LIDENT var-pattern PyPvar —
  // a UIDENT would parse as a constructor pattern and lose the name); lowering's ats_type_sym then
  // leaves the lowercase name as-is for the s2cst symbol, matching stock's `D2Cstacst0(c; ...)`.
  | D0Cstacst0(_, sid, _, _, srt) => (
      ps(out, "@static"); nl(out);
      ps(out, "let "); ps(out, fname(i0dnt_lexeme(sid))); ps(out, ": ");
      ps(out, sort0_py(srt));
      nl(out);
      true
    )
  //
  // `#abssort myord`  ->  `@sort type Myord`   (an ABSTRACT SORT — a `@sort type` with NO `= RHS`).
  // The absence of the RHS is what distinguishes abssort from sortdef at the parser; lowering builds
  // the t2abs (S2TEXsrt(S2Tbas(T2Btabs))) + emits D2Cabssort. Name capitalizes to a UIDENT.
  | D0Cabssort(_, sid) => (
      ps(out, "@sort"); nl(out);
      ps(out, "type "); ps(out, tyname(i0dnt_lexeme(sid)));
      nl(out);
      true
    )
  //
  // `#absopen mytype`  ->  `@open type Mytype`   (OPEN an abstract type's representation). The qual-id
  // names the abstract type to open; we emit just its tail name (the kernel uses an unqualified id).
  // Lowering resolves it against the env (f1_sqid) + emits D2Cabsopen. Name capitalizes to a UIDENT.
  | D0Cabsopen(_, sqid) => (
      ps(out, "@open"); nl(out);
      ps(out, "type ");
      (case+ sqid of
       | S0QIDnone(id) => ps(out, tyname(i0dnt_lexeme(id)))
       | S0QIDsome(_, id) => ps(out, tyname(i0dnt_lexeme(id))));
      nl(out);
      true
    )
  //
  // a trailing parser-skip token (e.g. EOF region / comment-only tail) — silent.
  | D0Ctkerr(_) => false
  | D0Ctkskp(_) => false
  // Conditional-compilation markers (`#if defq(...) ... #else ... #endif`) appear as FLAT
  // tokens interleaved with the guarded declarations in the L0 d0eclist (see trans01_decl00's
  // f1_then0/f1_else1/f1_endif). pp_walk intercepts `D0Cifexp` and emits ONLY the active backend
  // branch (see pp_walk + ifexp_guard_active below), so these markers should never reach this
  // dispatch via the normal top-level walk. They remain handled here (silently) as a safety net
  // for any stray marker reached out of band.
  | D0Cifdef(_, _) => false
  | D0Cifexp(_, _) => false
  | D0Celsif(_, _) => false
  | D0Cthen0(_) => false
  | D0Celse1(_) => false
  | D0Cendif(_) => false
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
  | G0Eapps(ges) => pp_g0apps(out, ges)
  | _ => ps(out, "# TODO(pp): g0exp")
)
and
pp_g0apps(out: FILR, ges: g0explst): void =
(
  case+ ges of
  | list_cons(gop, list_cons(arg, list_nil())) =>
      if g0exp_is_id(gop, "-")
      then (ps(out, "-"); pp_g0exp(out, arg))
      else pp_g0exp_app_fallback(out, ges)
  | _ => pp_g0exp_app_fallback(out, ges)
)
and
pp_g0exp_app_fallback(out: FILR, ges: g0explst): void =
(
  case+ ges of
  | list_nil() => ps(out, "# TODO(pp): g0exp")
  | list_cons(ge, rest) => (
      pp_g0exp(out, ge);
      (case+ rest of
       | list_nil() => ()
       | _ => (ps(out, " "); pp_g0exp_app_fallback(out, rest))))
)
and
g0exp_is_id(ge: g0exp, s: strn): bool =
(
  case+ ge.node() of
  | G0Eid0(id) => i0dnt_lexeme(id) = s
  | _ => false
)
and
g0exp_import_path(ge: g0exp): strn =
(
  case+ ge.node() of
  | G0Estr(t0) => (case+ t0 of T0STRsome(tok) => tok_lexeme(tok) | T0STRnone(tok) => tok_lexeme(tok))
  | G0Eapps(ges) => g0explst_import_path(ges)
  | G0Elpar(_, ges, _) => g0explst_import_path(ges)
  | G0Eerrck(_, ge1) => g0exp_import_path(ge1)
  | _ => "?"
)
and
// MISC (Cluster E): the VERBATIM dyninit path content (NO XATSHOME normalization — stock keeps the
// path-string verbatim). The G0Estr carrier's lexeme is the QUOTED source lexeme (`"foo/bar.dats"`);
// strip the surrounding quotes so the emit re-quotes exactly once (`initialize "foo/bar.dats"`).
g0exp_dyninit_path(ge: g0exp): strn =
( case+ ge.node() of
  | G0Estr(t0) =>
    let val raw = (case+ t0 of T0STRsome(tok) => tok_lexeme(tok) | T0STRnone(tok) => tok_lexeme(tok))
    in PYPP_unquote(raw) end
  | G0Eerrck(_, ge1) => g0exp_dyninit_path(ge1)
  | _ => g0exp_import_path(ge) )
and
g0explst_import_path(ges: g0explst): strn =
(
  case+ ges of
  | list_nil() => "?"
  | list_cons(ge, rest) => let
      val p0 = g0exp_import_path(ge)
    in
      if p0 = "?" then g0explst_import_path(rest) else p0
    end
)
and
// a NAMED staload `#staload SYM = "path"` parses (p1_g0exp) as the apps spine
// `[G0Eid0(SYM), G0Eid0(=), G0Estr("path")]`. Extract the alias name SYM; return ""
// for the bare `#staload "path"` form (a lone G0Estr, no leading id). This is the
// L0 mirror of the stock `g1exp_nmspace` (trans12_decl00.dats), which reads the same
// `= "path"` shape to discover the module qualifier.
g0exp_staload_alias(ge: g0exp): strn =
(
  case+ ge.node() of
  | G0Eapps(ges) => g0explst_staload_alias(ges)
  | G0Elpar(_, ges, _) => g0explst_staload_alias(ges)
  | G0Eerrck(_, ge1) => g0exp_staload_alias(ge1)
  | _ => ""
)
and
g0explst_staload_alias(ges: g0explst): strn =
(
  case+ ges of
  | list_cons(g0, list_cons(g1, _)) =>
      // require the shape `NAME = ...` — a leading id followed by the `=` operator.
      (case+ g0.node() of
       | G0Eid0(id) =>
           if g0exp_is_eq(g1) then i0dnt_lexeme(id) else ""
       | _ => "")
  | _ => ""
)
and
g0exp_is_eq(ge: g0exp): bool =
(
  case+ ge.node() of
  | G0Eid0(id) => i0dnt_lexeme(id) = "="
  | _ => false
)
and
pp_staload_n(out: FILR, n: sint, ge: g0exp): void = let
  val alias = g0exp_staload_alias(ge)
in
  ind(out, n);
  if strn_eq(alias, "")
  then (ps(out, "from \""); ps(out, PYPP_import_stem(g0exp_import_path(ge))); ps(out, "\" import *"); nl(out))
  // a NAMED staload -> `import "path" as ALIAS` (registers the `$ALIAS.` qualifier).
  else (ps(out, "import \""); ps(out, PYPP_import_stem(g0exp_import_path(ge))); ps(out, "\" as "); ps(out, alias); nl(out))
end
and
pp_staload(out: FILR, ge: g0exp): void =
  pp_staload_n(out, 0, ge)
//
// FIXITY (Cluster B) emitter helpers. `fixity_kw_of_token` decodes the T_SRP_FIXITY(knd) code to
// the pythonic keyword (KEPT VERBATIM from ATS): KINFIX0->infix0, KINFIXL->infixl, KINFIXR->infixr,
// KPREFIX->prefix, KPSTFIX->postfix. `pp_fixity_prec` emits the precopt's int lexeme + a trailing
// space when present (a bare `#infixl +` with no `of N` emits nothing). `pp_fixity_names` emits the
// operator lexemes space-separated (`#infix0 < <=` -> `< <=`).
and
fixity_kw_of_token(tknd: token): strn =
( case+ tknd.node() of
  | T_SRP_FIXITY(knd) =>
    ( if knd = 1 then "infixl"
      else if knd = 2 then "infixr"
      else if knd = 3 then "prefix"
      else if knd = 4 then "postfix"
      else "infix0" )                 // KINFIX0 = 0 (and the defensive default)
  | _ => "infixl" )                   // unreachable (D0Cfixity always carries T_SRP_FIXITY)
and
pp_fixity_prec(out: FILR, popt: precopt): void =
( case+ popt of
  | PRECnil0() => ()                  // bare fixity (no `of N`) -> no precedence token
  | PRECint1(tint) => (ps(out, tok_lexeme(tint)); ps(out, " "))
  // PRECopr2 (`of OP(+N)` — a precedence RELATIVE to another operator, e.g. `#infixl && of ||(+1)`).
  // Faithfully re-emit the operator name + the optional `(+N)` modifier so the round-trip preserves
  // the relative-precedence form. (The pythonic parser reads it back via p_fixity's INT path only —
  // a relative prec is rare in the corpus and not consulted by our fixed Pratt table — so we render
  // the resolved base operator's name; an explicit `(+N)` modifier is appended verbatim.)
  | PRECopr2(opr, pmod) => (
      ps(out, i0dnt_lexeme(opr));
      (case+ pmod of
       | PMODnone() => ()
       | PMODsome(_, pint, _) => (
           ps(out, "(");
           (case+ pint of
            | PINTint1(t0) => ps(out, tok_lexeme(t0))
            | PINTopr2(top, t0) => (ps(out, tok_lexeme(top)); ps(out, tok_lexeme(t0))));
           ps(out, ")")));
      ps(out, " ")) )
and
pp_fixity_names(out: FILR, id0s: i0dntlst): void =
( case+ id0s of
  | list_nil() => ()
  | list_cons(id, list_nil()) => ps(out, i0dnt_lexeme(id))
  | list_cons(id, rest) => (ps(out, i0dnt_lexeme(id)); ps(out, " "); pp_fixity_names(out, rest)) )
//
(* ****** ****** *)
//
// ===================== `#if defq(...)` backend selector ======================
//
// `#if`-guarded declarations select the active backend's prelude shim
// (`#if defq(_XATS2JS_) #typedef argv=jsa1sz(strn) #endif` vs the `_XATS2PY_`/`_XATS2CC_`
// variants — BOOTSTRAP-PLAN: 25 occurrences, backend-selection only, no `#elif`/arithmetic).
// The frontend + the stock codegen both target the JS backend, so the ACTIVE-branch SELECTION
// is `_XATS2JS_` (correct for codegen). Emitting BOTH branches re-declares the same type (e.g.
// `Argv`) against two different backend array types, which later uses (`argv[i]`,
// `length(argv)`) fail to resolve, so we emit only the one active branch.
//   CAVEAT (verification prelude): the M3 reparse driver's STATIC prelude is the stock C one
// (`the_tr12env_pvsl00d` loads `/prelude/basics0.sats` …, where `a1sz` lives), NOT the JS
// prelude `srcgen1/prelude/DATS/CATS/JS/basics3.dats` that declares `jsa1sz`. So a file whose
// active `_XATS2JS_` branch uses a JS-ONLY abstype (`jsa1sz`/`pya1sz`/`jsobj`/…) reparses with
// that head UNBOUND (`S2Enone0`) — see docs/CFAIL-INVESTIGATION.md "RE-DIAGNOSIS … tcheck00/01".
// That is a harness-prelude gap (the JS prelude is not f0_pvsload'd by the driver), not a
// pretty-print bug; selecting `_XATS2JS_` here is still correct.
//
// THE ACTIVE-BACKEND POLICY: `_XATS2JS_` is the one active flag; every other backend defq
// is inactive. To switch backends, change which name returns true here.
and
backend_defq_active(name: strn): bool =
(
  if name = "_XATS2JS_"  then true   // <-- the one active backend flag
  else if name = "_XATS2PY_"  then false
  else if name = "_XATS2CC_"  then false
  else if name = "_XATS2C_"   then false
  else if name = "_XATS2CPP_" then false
  else false                          // any other / unknown backend defq: inactive
)
//
// extract the bare identifier lexeme of a guard ARGUMENT. CRITICAL: the level-0 parse of
// `defq(_XATS2JS_)` is `G0Eapps([G0Eid0("defq"), G0Elpar(lp,[G0Eid0("_XATS2JS_")],rp)])` — the
// argument is a PARENTHESIZED group `G0Elpar`, NOT a bare `G0Eid0`. A plain `g0exp_lexeme` on
// it returns "?" (the `_` arm), so `backend_defq_active("?")` is false and the ACTIVE `_XATS2JS_`
// branch is wrongly dropped (its `#typedef argv=...` / `#extern` shim vanishes -> later uses of
// `argv`/`XATSOPT_*` resolve to an abstract `T2Pbas` head that stock `unify00_s2typ`/`tread3a_s2typ`
// has NO arm for -> a hard `XATS000_cfail`). So unwrap a single-element `G0Elpar`/`G0Eapps` (and a
// pread-error `G0Eerrck`) down to the inner id before reading its lexeme.
and
g0exp_guard_arg_lexeme(ge: g0exp): strn =
(
  case+ ge.node() of
  | G0Elpar(_, list_cons(ge1, list_nil()), _) => g0exp_guard_arg_lexeme(ge1)
  | G0Eapps(list_cons(ge1, list_nil())) => g0exp_guard_arg_lexeme(ge1)
  | G0Eerrck(_, ge1) => g0exp_guard_arg_lexeme(ge1)
  | _ => g0exp_lexeme(ge)
)
//
// evaluate an `#if` guard g0exp. Only the `defq(NAME)` form occurs in the corpus; anything
// else is treated as inactive (conservative — the inactive branch is dropped, never the
// declarations we know how to emit).
and
ifexp_guard_active(gexp: g0exp): bool =
(
  case+ gexp.node() of
  | G0Eapps(list_cons(gop, list_cons(arg, list_nil()))) =>
      if g0exp_is_id(gop, "defq")
      then backend_defq_active(g0exp_guard_arg_lexeme(arg))
      else false
  | _ => false
)
//
// split a FLAT d0eclist that follows a `#ifexp`/`#else1` marker into (this-branch-decls, rest),
// where `rest` begins at the next branch terminator (`#else1`/`#elsif`/`#endif`) or is empty.
// Mirrors trans01_decl00's f1_then0/f1_else1 branch collection.
and
ifexp_split_branch(dcs: d0eclist): @(d0eclist, d0eclist) =
(
  case+ dcs of
  | list_nil() => @(list_nil(), list_nil())
  | list_cons(dc, rest) =>
      (case+ dc.node() of
       | D0Celse1(_) => @(list_nil(), dcs)
       | D0Celsif(_, _) => @(list_nil(), dcs)
       | D0Cendif(_) => @(list_nil(), dcs)
       | _ => let
           val @(branch, after) = ifexp_split_branch(rest)
         in
           @(list_cons(dc, branch), after)
         end)
)
//
// drop a leading `#endif` marker (the tail after a fully-consumed `#if ... #endif`).
and
ifexp_skip_endif(dcs: d0eclist): d0eclist =
(
  case+ dcs of
  | list_nil() => list_nil()
  | list_cons(dc, rest) =>
      (case+ dc.node() of
       | D0Cendif(_) => rest
       | _ => dcs)
)
//
// walk the then/else branches of an `#if` block already split off the flat stream, emitting
// only the active branch (the marker-consuming logic lives in pp_walk).  `head` is the d0eclist
// starting right AFTER the `#ifexp` marker; returns the tail after the matching `#endif`.
and
pp_walk_ifexp(out: FILR, active: bool, head: d0eclist): d0eclist =
let
  val @(thenbr, afterthen) = ifexp_split_branch(head)
  // optional `#else1 ... ` branch.
  val @(elsebr, afterelse) =
    (case+ afterthen of
     | list_cons(dc, rest) =>
         (case+ dc.node() of
          | D0Celse1(_) => ifexp_split_branch(rest)
          // `#elsif` does not occur in the corpus (backend-selection only); treat its body as a
          // dropped (inactive) branch so we never emit it, and resume after its terminator.
          | D0Celsif(_, _) => let val @(_, aft) = ifexp_split_branch(rest) in @(list_nil(), aft) end
          | _ => @(list_nil(), afterthen))
     | list_nil() => @(list_nil(), list_nil()))
  val tail = ifexp_skip_endif(afterelse)
  val () = (if active then pp_walk(out, thenbr) else pp_walk(out, elsebr))
in
  tail
end
//
(* ****** ****** *)
//
// walk the top-level decl list; a blank line AFTER each emitting decl (a Python-
// tolerant, peek-free separation — empty lines are insignificant at top level).
// `#if defq(...)` blocks are intercepted here so ONLY the active backend branch emits.
//
and
pp_walk(out: FILR, dcs: d0eclist): void =
(
  case+ dcs of
  | list_nil() => ()
  | list_cons(dc, rest) =>
      (case+ dc.node() of
       | D0Cifexp(_, gexp) => let
           val active = ifexp_guard_active(gexp)
           val tail = pp_walk_ifexp(out, active, rest)
         in
           pp_walk(out, tail)
         end
       | _ => let
           val emitted = pp_d0ecl(out, dc)
           val () = (if emitted then nl(out) else ())
         in
           pp_walk(out, rest)
         end)
)
//
// `local D1 in D2 end` -> `private:` (D1) then D2 at the SAME (outer) level — the
// capture-rest lowering (D2Clocal0).  File-local names are pre-registered ONCE at
// the entry (register_file_local_names), so cons used in D2 bodies capitalize.
//
and
push_local_type_renames(head: d0eclist): void =
(
  case+ head of
  | list_nil() => ()
  | list_cons(dc, rest) => (
      (case+ dc.node() of
       | D0Csexpdef(_, sid, _, _, _, _) => PYPP_type_rename_push(i0dnt_lexeme(sid))
       | D0Cstatic(_, dc1) => push_local_type_renames(list_sing(dc1))
       | _ => ());
      push_local_type_renames(rest))
)
and
pop_local_type_renames(head: d0eclist): void =
(
  case+ head of
  | list_nil() => ()
  | list_cons(dc, rest) => (
      (case+ dc.node() of
       | D0Csexpdef(_, sid, _, _, _, _) => PYPP_type_rename_pop(i0dnt_lexeme(sid))
       | D0Cstatic(_, dc1) => pop_local_type_renames(list_sing(dc1))
       | _ => ());
      pop_local_type_renames(rest))
)
and
pp_local(out: FILR, head: d0eclist, body: d0eclist): void = (
  if list_nilq(head)
  then pp_walk(out, body)
  else (
    push_local_type_renames(head);
    ps(out, "private:"); nl(out);
    pp_priv_head(out, 1, head);
    nl(out);
    pp_walk(out, body);
    pop_local_type_renames(head))
)
and
// the HEAD of a local: datatypes -> enum; val-bindings -> `let`; #absimpl -> `@impl type`.
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
	  | D0Cdatatype(dtok, dts, _) => pp_d0typ_enum_list(out, n, dt_kind_deco(dtok), dts)
	  | D0Cexcptcon(_, _, tcns) => pp_excptcon_list(out, n, tcns)
	  | D0Cvaldclst(_, vds) => pp_priv_valdcls(out, n, vds)
	  | D0Cfundclst(_, _, fds) => pp_fundcl_local_list_n(out, n, fds)
	  | D0Cimplmnt0(tknd, sqas, tqas, dqi, tias, farg, _, _, body) => pp_impl_n(out, n, tknd, sqas, tqas, dqi, tias, farg, body)
	  | D0Cabsimpl(_, sqid, smas, _, _, se) => pp_absimpl(out, n, sqid, smas, se)
	  | D0Csexpdef(_, sid, smas, _, _, se) => pp_typedef(out, n, sid, smas, se)
	  | D0Cdefine(_, gid, _, gedf) => pp_define(out, n, gid, gedf)
	  | D0Cstaload(_, _, ge) => pp_staload_n(out, n, ge)
	  | D0Clocal0(_, head, _, body, _) => pp_priv_head_local(out, n, head, body)
	  | D0Cstatic(_, dc1) => pp_priv_head_one(out, n, dc1)
	  | D0Cextern(_, dc1) => pp_dexp_extern_decl(out, n, dc1)
	  | D0Csymload(_, sym, _, dqi, prec) => pp_symload_alias(out, n, sym, dqi, prec)
	  | D0Ctkerr(_) => ()
	  | D0Ctkskp(_) => ()
	  | _ => (ind(out, n); todo(out, "private-head decl"))
	)
and
pp_priv_head_local(out: FILR, n: sint, head: d0eclist, body: d0eclist): void =
(
  if list_nilq(head)
  then pp_priv_head(out, n, body)
  else (
    ind(out, n); ps(out, "private:"); nl(out);
    pp_priv_head(out, n+1, head);
    nl(out);
    pp_priv_head(out, n, body))
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
pp_d0typ_enum_list(out: FILR, n: sint, deco: strn, dts: d0typlst): void =
(
  case+ dts of
  | list_nil() => ()
  | list_cons(dt, rest) => (
      pp_d0typ_enum(out, n, deco, dt);
      pp_d0typ_enum_list(out, n, deco, rest))
)
and
// emit a datatype's `where { ... }` nested declarations as ordinary top-level decls (an inner
// `datavwtp` -> its own `enum`). pp_walk separates each emitting decl with a blank line, the same
// top-level shape they would have had if written outside the where. WD0CSnone -> nothing.
pp_datatype_where_decls(out: FILR, wdc: wd0eclseq): void =
(
  case+ wdc of
  | WD0CSnone() => ()
  | WD0CSsome(_, _, dcs, _) => pp_walk(out, dcs)
)
and
	// `#implfun NAME(params) = body` (a D0Cimplmnt0) -> `@impl` + `def NAME(params): body`.
	// Params are UNANNOTATED (the .dats carries no param types; the inline-implement
	// path infers them — verified nerror=0). The body is a `:`-suite at indent 1.
	pp_impl(out: FILR, tknd: token, sqas: s0qaglst, tqas: t0qaglst, dqi: d0qid, tias: t0iaglst, farg: f0arglst, body: d0exp): void =
	  pp_impl_n(out, 0, tknd, sqas, tqas, dqi, tias, farg, body)
	and
	// the body of `#implfun` -> `@impl` + `def` (one or more d0fundcl in a list).
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
// a TOP-LEVEL `val name = e` binding (outside a local) is still dynamic in a .dats.
// `@static let` is reserved for real `stadef`/`stacst` declarations; token-valued
// aliases such as `val T0CAS0 = T_CASE(...)` must be ordinary dynamic values.
pp_topval(out: FILR, vds: d0valdclist): void =
(
  case+ vds of
  | list_nil() => ()
  | list_cons(vd, rest) => (
      pp_dexp_valdcl(out, 0, vd);
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
  val () = PYPP_source_set(fpath)
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
