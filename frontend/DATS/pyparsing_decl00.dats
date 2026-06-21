(* ****** ****** *)
(*
** M2 — Python-surface frontend: DECLARATION + MODULE parser + public entries (DATS).
**
** Recursive-descent over the §5.2 / §5.7 grammar:
**
**   decl      ::= binding | funcdef | typedecl | import | stmt
**   funcdef   ::= 'def' LIDENT [ typarams ] '(' [ params ] ')' [ '->' type ] ':' suite
**   typarams  ::= '[' typaram { ',' typaram } ']'                  (§5.7)
**   typaram   ::= UIDENT [ ':' SORT ] { '@' LIDENT }               (§5.7 — sort + inline decos)
**   typedecl  ::= { '@' LIDENT NEWLINE } ( enumdecl | structdecl | aliasdecl )  (§5.7)
**   enumdecl  ::= 'enum'   UIDENT [ typarams ] ':' NEWLINE INDENT { casedecl } DEDENT
**   casedecl  ::= 'case' UIDENT [ '(' type { ',' type } ')' ] NEWLINE
**   structdecl::= 'struct' UIDENT [ typarams ] ':' NEWLINE INDENT { fielddecl } DEDENT
**   fielddecl ::= LIDENT ':' type NEWLINE
**   aliasdecl ::= 'type' UIDENT [ typarams ] '=' type NEWLINE      (alias ONLY)
**   import    ::= 'import' modpath NEWLINE
**               | 'from' modpath 'import' ( '*' | LIDENT { ',' LIDENT } ) NEWLINE
**   modpath   ::= LIDENT { '.' LIDENT } | STRING
**
** Implements the SATS entry `parse_decl` and the two public entries `pyparse_tokens`
** (parse a pylex_layout token stream) and `pyparse_module` (lex + parse). CALLS the
** dynexp entries (parse_expr, parse_suite, p_simple_stmt via parse_decl dispatch) and
** the staexp entries (parse_type, parse_pattern).
**
** Adjacent `def`s form one mutually-recursive group (§5.2) — M2 does NOT mark this;
** it preserves source order in the decl list so M3 can group adjacency. (Flagged.)
**
** Error recovery: a malformed decl yields a PyCerror at the offending span; the module
** loop resyncs at NEWLINE and continues — a partial module + diagnostics. NEVER throws.
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
// expect a NEWLINE terminating a simple decl (recover if absent).
//
// consume a real NEWLINE if present; otherwise pass through (a DEDENT/EOF or a fresh
// statement-starter after a block-bodied construct legitimately has no NEWLINE — the
// layout guarantees boundaries, so we do NOT emit a spurious diagnostic).
fun
expect_newline_d(st: pstate): pstate =
( case+ ps_peek(st) of
  | PT_NEWLINE() => ps_advance(st)
  | _ => st )
//
(* ****** ****** *)
//
// DEP (guards): attach a parsed quantifier GUARD `g` (a bool-index-expr pytyp) to a typaram. The
// guard rides on the AST node (PyGuardSome); it is PARSE-ONLY for a def (the t2qag quantifier has
// no prop slot) but threads cleanly so the lowering can drop it without crashing. Local helper.
fun
typaram_set_guard(tp: pytyparam, gloc: loctn, g: pytyp): pytyparam =
( case+ tp of
  | PyTyParam(loc, nm, sopt, decos, _) =>
      PyTyParam(loc, nm, sopt, decos, PyGuardSome(gloc, g)) )
//
// DEP: parse one index-expr GUARD (delegates to the staexp index-binop grammar `parse_index_type`).
fun
p_index_type(st: pstate): @(pytyp, pstate) = parse_index_type(st)
//
// ---- typarams: '[' typaram { ',' typaram } ']' → a list(pytyparam). Empty if absent. ----
//   typaram ::= UIDENT [ ':' SORT(UIDENT) ] { '@' LIDENT }   (§5.7)
// The optional sort is `: UIDENT`; inline decorators are `@ LIDENT` with NO newline between
// (these are layout-suppressed inside the open '[' bracket, unlike the prefix decorators).
//
fun
p_typarams(st: pstate): @(list(pytyparam), pstate) =
( case+ ps_peek(st) of
  | PT_LBRACK() => p_tyvar_seq(ps_advance(st))
  | _ => @(list_nil(), st) )
//
and
p_tyvar_seq(st: pstate): @(list(pytyparam), pstate) =
( case+ ps_peek(st) of
  | PT_RBRACK() => @(list_nil(), ps_advance(st))
  // a TYPE param is an UIDENT (`A`); DEP: an INDEX param is a LOWERCASE LIDENT (`n`, `b` in
  // `[A, n: SInt]`) — both open a typaram. p_typaram accepts either name kind; the sort
  // annotation (`: SInt`/`: SBool`) is what makes it an index param at lowering (psort2_of).
  | PT_UIDENT(_) => p_tyvar_seq_one(st)
  | PT_LIDENT(_) => p_tyvar_seq_one(st)
  | _ =>
    let val st1 = ps_diag(st, ps_peek_loctn(st), "expected a type parameter") in
      @(list_nil(), st1) end )
//
// parse one typaram then the trailing ',' / ']' (shared by the UIDENT + LIDENT entry arms).
// DEP (guards): a `|` after a binder opens a quantifier GUARD `{... | <bool-index-expr>}` — we
// parse the guard as an index-expr type (p_index_type: the binop grammar, so `n >= 0` / `i < n`),
// attach it to THIS (the last) typaram via PyGuardSome, then expect ']'. The guard rides on the
// AST but is PARSE-ONLY for a def (the t2qag quantifier has no prop slot); it lowers w/o crashing.
and
p_tyvar_seq_one(st: pstate): @(list(pytyparam), pstate) =
  let val @(tp, st1) = p_typaram(st) in
    case+ ps_peek(st1) of
    | PT_COMMA() =>
      let val @(rest, st2) = p_tyvar_seq(ps_advance(st1)) in
        @(list_cons(tp, rest), st2) end
    | PT_RBRACK() => @(list_cons(tp, list_nil()), ps_advance(st1))
    | PT_BAR() =>
      let
        val locG = ps_peek_loctn(st1)
        val @(g, st2) = p_index_type(ps_advance(st1))   // the bool-index guard expression
        val tpG = typaram_set_guard(tp, locG, g)
      in
        case+ ps_peek(st2) of
        | PT_RBRACK() => @(list_cons(tpG, list_nil()), ps_advance(st2))
        | _ =>
          let val st3 = ps_diag(st2, ps_peek_loctn(st2), "expected ']' after a quantifier guard") in
            @(list_cons(tpG, list_nil()), st3) end
      end
    | _ =>
      let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected ',', '|' or ']' in type params") in
        @(list_cons(tp, list_nil()), st2) end
  end
//
// one type parameter: (UIDENT | DEP: LIDENT) [ ':' SORT ] { '@' LIDENT }. The name may be an
// UIDENT (a TYPE param `A`) or a LOWERCASE LIDENT (DEP: an INDEX param `n` — `[n: SInt]`).
and
p_typaram(st: pstate): @(pytyparam, pstate) = let
  val loc = ps_peek_loctn(st)
  val @(nm, st1) =
    ( case+ ps_peek(st) of
      | PT_UIDENT(s) => @(s, ps_advance(st))
      | PT_LIDENT(s) => @(s, ps_advance(st))   // DEP: a lowercase INDEX param name (`n`)
      | _ => @("?", ps_diag(st, loc, "expected a type parameter name")) )
  // optional sort annotation: ':' UIDENT
  val @(sopt, st2) =
    ( case+ ps_peek(st1) of
      | PT_COLON() =>
        let val locS = ps_peek_loctn(ps_advance(st1)) in
          case+ ps_peek(ps_advance(st1)) of
          | PT_UIDENT(srt) => @(PySortSome(locS, srt), ps_advance(ps_advance(st1)))
          | _ =>
            let val stE = ps_diag(ps_advance(st1), locS, "expected a sort (uppercase) after ':'") in
              @(PySortNone(), stE) end
        end
      | _ => @(PySortNone(), st1) )
  // zero or more inline decorators: '@' LIDENT
  val @(decos, st3) = p_inline_decorators(st2)
in
  @(PyTyParam(loc, nm, sopt, decos, PyGuardNone()), st3)
end
//
// inline decorators on a type param: { '@' LIDENT } with no NEWLINE between (open bracket).
and
p_inline_decorators(st: pstate): @(list(pydecorator), pstate) =
( case+ ps_peek(st) of
  | PT_AT() =>
    let
      val locA = ps_peek_loctn(st)
      val st1 = ps_advance(st)
    in
      case+ ps_peek(st1) of
      | PT_LIDENT(nm) =>
        // an inline type-param decorator (`[A @unboxed]`) never carries a bracket payload (the
        // enclosing `[` is the typaram bracket itself) — always PyDAnone.
        let val @(rest, st2) = p_inline_decorators(ps_advance(st1)) in
          @(list_cons(PyDecor(locA, nm, PyDAnone()), rest), st2) end
      | _ =>
        let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected a decorator name after '@'") in
          @(list_nil(), st2) end
    end
  | _ => @(list_nil(), st) )
//
// A-QUANT: the SATS-exported wrapper over the typaram-bracket parser, so staexp's `forall`/`exists`
// type-quantifier production can reuse the SAME `[ binders | guard ]` grammar a `def foo[A]` uses.
#implfun parse_typarams(st) = p_typarams(st)
//
(* ****** ****** *)
//
// A-TEMPLATE: parse a decorator's OPTIONAL `[…]` ARG PAYLOAD, dispatched by the decorator NAME:
//   * `@template`        -> type-param BINDERS (p_typarams, the SAME parser a `def foo[A]` uses):
//                           PyDAbinders. These BIND fresh (possibly sort-annotated) type vars.
//   * `@impl` / `@inst`  -> type-arg USES (parse_deco_typeargs): PyDAtypes. `Int`/`List[Int]`/...
//   * every other name   -> PyDAnone (no payload; byte-identical to before this slice).
// A name that CAN take a payload but is NOT followed by '[' gets PyDAnone (a bare `@impl def` /
// `@inst foo` is the no-bracket form). Only `@template`, `@impl`, `@inst` ever consume a '['.
fun
p_deco_args(nm: strn, st: pstate): @(pydecoargs, pstate) = let
  // does this decorator take a TYPE-arg payload (`@impl[...]` / `@inst[...]`)? (no `andalso` in this
  // dialect — compose with a nested if into a `val`, matching pl_app's `is_unary` style.)
  // C-PROOF: `@terminates[n]` also takes a type/INDEX-arg payload — the `[n]` is the termination
  // metric (an index EXPRESSION referencing the def's own typaram), parsed by the SAME type-arg
  // parser `@impl`/`@inst` use (PyDAtypes). The metric is lowered to F2ARGmets at the def path.
  val takes_types =
    (if strn_eq(nm, "impl") then true
     else (if strn_eq(nm, "inst") then true else strn_eq(nm, "terminates"))): bool
in
  case+ ps_peek(st) of
  | PT_LBRACK() =>
    // (the nested if is PARENTHESIZED — the ATS2 dialect rejects a bare `else if` after a
    // `let…end` then-branch; wrapping the continuation in `( if … )` is the codebase idiom.)
    if strn_eq(nm, "template") then
      // template BINDERS: reuse the def typaram parser (consumes the matching ']').
      let val @(bs, st1) = p_typarams(st) in @(PyDAbinders(bs), st1) end
    else (if takes_types then
      // type-arg USES: reuse the shared type-arg parser (consumes the matching ']').
      let val @(ts, st1) = parse_deco_typeargs(st) in @(PyDAtypes(ts), st1) end
    else @(PyDAnone(), st))        // a '[' after some OTHER decorator: not a payload — leave it.
  | _ => @(PyDAnone(), st)
end
//
// ---- prefix decorators: { '@' LIDENT [ '[' args ']' ] NEWLINE } → a list(pydecorator) in source
//      order. Each prefix decorator sits on its own line (§5.7), so a NEWLINE follows the (optional)
//      bracket payload. A-TEMPLATE: the OPTIONAL `[…]` payload is parsed by p_deco_args (per-name).
//
fun
p_decorators(st: pstate): @(list(pydecorator), pstate) =
( case+ ps_peek(st) of
  | PT_AT() =>
    let
      val locA = ps_peek_loctn(st)
      val st1 = ps_advance(st)
    in
      case+ ps_peek(st1) of
      | PT_LIDENT(nm) =>
        let
          val st2 = ps_advance(st1)
          // A-TEMPLATE: the optional `[…]` arg payload (template binders / impl-inst types).
          val @(dargs, st2b) = p_deco_args(nm, st2)
          // consume the trailing NEWLINE (prefix decorators are line-terminated).
          val st3 =
            ( case+ ps_peek(st2b) of
              | PT_NEWLINE() => ps_advance(st2b)
              | _ => st2b )
          val @(rest, st4) = p_decorators(st3)
        in
          @(list_cons(PyDecor(locA, nm, dargs), rest), st4)
        end
      | _ =>
        let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected a decorator name after '@'") in
          @(list_nil(), st2) end
    end
  | _ => @(list_nil(), st) )
//
(* ****** ****** *)
//
// ---- def: [@decorators] 'def' LIDENT [typarams] '(' [params] ')' ['->' type] [':' suite] ----
//
// The leading `decos` are the PREFIX decorators parsed by the caller (parse_decl) and threaded
// in (default `[]` = a plain def). DECORATOR REWORK: an `@extern def` / `@proof @extern def`
// (praxi-shaped) is BODYLESS — there is NO `:` body suite, the decl ends after the return type.
// p_def detects this from `is_bodyless` (the elaborator decides bodyless-ness by decorators, but
// the PARSER must also know whether to consume a `:` suite). To keep the surface uniform and
// recovery-robust, p_def parses a body iff a `:` actually follows; otherwise it leaves an empty
// suite. So `@extern def f(...) -> T` (no colon) parses with an empty body, and the elaborator's
// decorator dispatch (which never reads the body of an @extern/praxi def) is correct.
fun
p_def(st: pstate, decos: list(pydecorator)): @(pydecl, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)               // past 'def'
  // name (LIDENT)
  val @(nm, st2) =
    ( case+ ps_peek(st1) of
      | PT_LIDENT(s) => @(s, ps_advance(st1))
      | _ => @("?", ps_diag(st1, ps_peek_loctn(st1), "expected a function name")) )
  val @(tvs, st3) = p_typarams(st2)
  // '(' params ')'
  val st4 =
    ( case+ ps_peek(st3) of
      | PT_LPAREN() => ps_advance(st3)
      | _ => ps_diag(st3, ps_peek_loctn(st3), "expected '(' after function name") )
  val @(params, st5) = p_def_params(st4)
  val st6 =
    ( case+ ps_peek(st5) of
      | PT_RPAREN() => ps_advance(st5)
      | _ => ps_diag(st5, ps_peek_loctn(st5), "expected ')'") )
  // optional return type
  val @(ropt, st7) =
    ( case+ ps_peek(st6) of
      | PT_ARROW() =>
        let val @(t, st7) = parse_type(ps_advance(st6)) in @(PyTypSome(t), st7) end
      | _ => @(PyTypNone(), st6) )
  // OPTIONAL ':' body suite — a plain/@proof/@impl/@overload def HAS one; an @extern (or
  // @proof @extern = praxi) def is BODYLESS (no ':'). Parse a body iff a ':' follows; else empty.
  val @(body, st9) =
    ( case+ ps_peek(st7) of
      | PT_COLON() => parse_suite(ps_advance(st7))
      | _ => @(list_nil(), st7) )
in
  @(PyCfun(loc, decos, nm, tvs, params, ropt, body), st9)
end
//
// def params: param { ',' param } until ')'. param ::= LIDENT [ ':' type ].
and
p_def_params(st: pstate): @(list(pyparam), pstate) =
( case+ ps_peek(st) of
  | PT_RPAREN() => @(list_nil(), st)
  | PT_EOF() => @(list_nil(), st)
  | PT_LIDENT(nm) =>
    let
      val loc = ps_peek_loctn(st)
      val st1 = ps_advance(st)
      val @(topt, st2) =
        ( case+ ps_peek(st1) of
          | PT_COLON() =>
            let val @(t, st2) = parse_type(ps_advance(st1)) in @(PyTypSome(t), st2) end
          | _ => @(PyTypNone(), st1) )
      val prm = PyParam(loc, nm, topt)
    in
      case+ ps_peek(st2) of
      | PT_COMMA() =>
        let val @(ps0, st3) = p_def_params(ps_advance(st2)) in
          @(list_cons(prm, ps0), st3) end
      | _ => @(list_cons(prm, list_nil()), st2)
    end
  | _ =>
    let val st1 = ps_diag(st, ps_peek_loctn(st), "expected a parameter name") in
      @(list_nil(), st1) end )
//
(* ****** ****** *)
//
// DECORATOR REWORK (slice 2): is `@nm` among the prefix decorators? (LIDENT-named.)
fun
decos_has_p(decos: list(pydecorator), name: strn): bool =
( case+ decos of
  | list_nil() => false
  | list_cons(PyDecor(_, nm, _), rest) =>
      if strn_eq(nm, name) then true else decos_has_p(rest, name) )
//
// ---- type declarations (§5.7): the decorators are parsed by the caller (parse_decl)
//      and threaded in. The base keywords are:
//        enum   Name [typarams] ':' <case suite>     → a datatype/ADT  (PyCenum)
//        struct Name [typarams] ':' <field suite>    → a record        (PyCstruct)
//        type   Name [typarams] '=' type NEWLINE     → an alias         (PyCtype)
//
// DECORATOR REWORK (slice 2): an ATS-specific `type`/`let` VARIANT is now a @decorator on a plain
// `type`. p_typedecl dispatches on the prefix decorators to the SAME AST node the dedicated keyword
// produced (the L2 lowering is reused unchanged):
//   @abstract type Foo [tvs]      (NO `= rhs`)        -> PyCabstype  (was `abstype`; @unboxed→flat)
//   @impl     type Foo = T                            -> PyCassume   (was `assume`; hidden repr T)
//   @sort     type Nat = SInt     (RHS a sort UIDENT) -> PyCsortdef  (was `sortdef`; sort alias)
//   @static   type X   = <expr>   (RHS a static expr) -> PyCstadef   (was `stadef`; static def)
//   (no variant deco) type X = T                      -> PyCtype     (a plain alias, unchanged)
//
fun
p_typedecl(st: pstate, decos: list(pydecorator)): @(pydecl, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)               // past 'type'
  val @(nm, st2) =
    ( case+ ps_peek(st1) of
      | PT_UIDENT(s) => @(s, ps_advance(st1))
      | _ => @("?", ps_diag(st1, ps_peek_loctn(st1), "expected a type name (uppercase)")) )
in
  // @abstract type Foo [tvs] — an OPAQUE type; NO `= rhs` body (opacity is the point). The mode
  // decorators (@unboxed) ride in `decos`; the elaborator's mode_of_decos selects box/flat. Parse
  // the typarams and STOP (no `=`): PyCabstype, exactly the old `abstype` node.
  if decos_has_p(decos, "abstract") then
    let val @(tvs, st3) = p_typarams(st2) in
      @(PyCabstype(loc, decos, nm, tvs), st3) end
  // @sort type Nat = <rhs> — a SORT declaration. The RHS is EITHER:
  //   * a sort-reference UIDENT (`SInt`/`Type`/...)        -> PyCsortdef (the old `sortdef` alias), OR
  //   * A-QUANT: a SUBSET `{ a: SInt | a >= 0 }`           -> PyCsortsub (the refined sortdef).
  // No typarams (a sort decl is monomorphic). The leading `{` after `=` selects the subset form.
  else if decos_has_p(decos, "sort") then
    let
      val st3 =
        ( case+ ps_peek(st2) of
          | PT_EQ() => ps_advance(st2)
          | _ => ps_diag(st2, ps_peek_loctn(st2), "expected '=' in '@sort type' declaration") )
    in
      case+ ps_peek(st3) of
      // A-QUANT subset sort: `{ binder | guard {, guard} }`.
      | PT_LBRACE() => p_sort_subset(ps_advance(st3), loc, nm)
      // plain sort alias: a sort-reference UIDENT.
      | PT_UIDENT(s) => @(PyCsortdef(loc, nm, s), ps_advance(st3))
      | _ =>
        let val stE = ps_diag(st3, ps_peek_loctn(st3),
                              "expected a sort name or a '{binder | guard}' subset after '='") in
          @(PyCsortdef(loc, nm, "?"), stE) end
    end
  // @static type X = <expr> — a STATIC-LEVEL DEFINITION; the RHS is a static EXPRESSION (v1: an int
  // literal). No typarams; `= <expr>`. PyCstadef, the old `stadef`.
  else if decos_has_p(decos, "static") then
    let
      val st3 =
        ( case+ ps_peek(st2) of
          | PT_EQ() => ps_advance(st2)
          | _ => ps_diag(st2, ps_peek_loctn(st2), "expected '=' in '@static type' declaration") )
      val @(e, st4) = parse_expr(st3)
    in
      @(PyCstadef(loc, nm, e), st4)
    end
  // @impl type Foo = T — gives an abstract type its hidden REPRESENTATION T (monomorphic in v1).
  // `= T(type)`. PyCassume, the old `assume`.
  else if decos_has_p(decos, "impl") then
    let
      val st3 =
        ( case+ ps_peek(st2) of
          | PT_EQ() => ps_advance(st2)
          | _ => ps_diag(st2, ps_peek_loctn(st2), "expected '=' in '@impl type' declaration") )
      val @(t, st4) = parse_type(st3)
    in
      @(PyCassume(loc, nm, t), st4)
    end
  // a plain `type X [tvs] = T` alias — `= type`. PyCtype, unchanged.
  else
    let
      val @(tvs, st3) = p_typarams(st2)
      val st4 =
        ( case+ ps_peek(st3) of
          | PT_EQ() => ps_advance(st3)
          | _ => ps_diag(st3, ps_peek_loctn(st3), "expected '=' in type alias declaration") )
      val @(t, st5) = parse_type(st4)
    in
      @(PyCtype(loc, decos, nm, tvs, t), st5)
    end
end
//
// A-QUANT: parse a SUBSET-sort RHS body `{ binder | guard {, guard} }` (the opening `{` already
// consumed). The binder is ONE typaram (`a: SInt` — its sort is the subset's carrier sort), then a
// mandatory `|`, then one or more comma-separated bool-index GUARDS (parse_index_type — the same
// binop grammar a def-param guard uses), then `}`. Builds a PyCsortsub. A malformed body recovers
// to a PyCsortsub with whatever was parsed (errors already reported via ps_diag).
// (chained into p_typedecl's group via `and` so p_typedecl can forward-call it.)
and
p_sort_subset(st: pstate, loc: loctn, nm: strn): @(pydecl, pstate) = let
  val @(binder, st1) = p_typaram(st)                 // the carrier binder `a: SInt`
  val st2 =
    ( case+ ps_peek(st1) of
      | PT_BAR() => ps_advance(st1)
      | _ => ps_diag(st1, ps_peek_loctn(st1), "expected '|' after the binder in a subset sort") )
  val @(guards, st3) = p_sort_guards(st2)
  val st4 =
    ( case+ ps_peek(st3) of
      | PT_RBRACE() => ps_advance(st3)
      | _ => ps_diag(st3, ps_peek_loctn(st3), "expected '}' to close a subset sort") )
in
  @(PyCsortsub(loc, nm, binder, guards), st4)
end
//
// the comma-separated guard list inside a subset sort `{a | g1, g2}` — each guard is a bool-index
// expression (parse_index_type). Stops at `}` / EOF; recovers on anything else.
and
p_sort_guards(st: pstate): @(list(pytyp), pstate) =
(
case+ ps_peek(st) of
| PT_RBRACE() => @(list_nil(), st)
| PT_EOF() => @(list_nil(), st)
| _ =>
  let val @(g, st1) = parse_index_type(st) in
    case+ ps_peek(st1) of
    | PT_COMMA() =>
      let val @(gs, st2) = p_sort_guards(ps_advance(st1)) in
        @(list_cons(g, gs), st2) end
    | _ => @(list_cons(g, list_nil()), st1)
  end
)
//
(* ****** ****** *)
//
// DECORATOR REWORK (slice 1): the keyword parsers p_externdecl / p_implementdecl / p_overloaddecl
// were REMOVED. `extern def` / `implement` / `overload` are now @decorators on a plain `def`
// (`@extern def` / `@impl def` / `@overload def`), parsed by p_def with the prefix decorators
// threaded in by parse_decl. The elaborator (pyelab_decl) routes the decorated def to the SAME
// PyCore variant (PCCextern / PCCimplement / PCCoverload). See parse_decl's PT_KW_DEF arm.
//
// DECORATOR REWORK (slice 2): the keyword parsers p_abstypedecl / p_assumedecl / p_sortdefdecl /
// p_stacstdecl / p_stadefdecl were REMOVED. `abstype` / `assume` / `sortdef` / `stadef` are now
// @decorators on a plain `type` (`@abstract type` / `@impl type` / `@sort type` / `@static type`),
// routed by p_typedecl (above) to the SAME AST nodes (PyCabstype / PyCassume / PyCsortdef /
// PyCstadef). `stacst` is `@static let c: SInt` (a bodyless let), routed by p_let_stmt + the
// elaborator to PyCstacst. The L2 lowering is reused unchanged.
//
(* ****** ****** *)
//
// DECORATOR REWORK: the keyword parsers p_prfundecl / p_praxidecl / p_prvaldecl were REMOVED.
// `prfun` / `praxi` / `prval` are now @decorators on a plain `def`/`let`: `@proof def` (prfun),
// `@proof @extern def` (praxi — proof + bodyless), `@proof let` (prval). The elaborator routes
// the decorated def/let to the SAME PyCore variant (PCCprfun / PCCpraxi / PCCprval). See
// parse_decl's PT_KW_DEF / PT_KW_LET arms.
//
(* ****** ****** *)
//
// ---- EXN: exception decl: 'exception' UIDENT [ '(' type {',' type} ')' ] NEWLINE ----
//      a single exception CONSTRUCTOR (a con of the built-in `exn` type). Shape mirrors a
//      datacon: UIDENT + optional parenthesized arg types. Nullary `exception Empty` allowed.
//      The trailing NEWLINE is consumed by p_top_item (expect_newline_d), like `type`/`import`.
//
fun
p_exceptdecl(st: pstate): @(pydecl, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)               // past 'exception'
  val @(nm, st2) =
    ( case+ ps_peek(st1) of
      | PT_UIDENT(s) => @(s, ps_advance(st1))
      | _ => @("?", ps_diag(st1, ps_peek_loctn(st1), "expected an exception name (uppercase)")) )
in
  case+ ps_peek(st2) of
  | PT_LPAREN() =>
    let
      val @(ts, st3) = p_exc_types(ps_advance(st2))
      val locR = ps_peek_loctn(st3)
      val st4 =
        ( case+ ps_peek(st3) of
          | PT_RPAREN() => ps_advance(st3)
          | _ => ps_diag(st3, locR, "expected ')' in exception declaration") )
    in
      @(PyCexcept(loc_span(loc, locR), nm, ts), st4)
    end
  | _ => @(PyCexcept(loc, nm, list_nil()), st2)
end
//
// exc_types ::= [ type { ',' type } ]   (the parenthesized arg types of an exception con)
and
p_exc_types(st: pstate): @(pytyplst, pstate) =
( case+ ps_peek(st) of
  | PT_RPAREN() => @(list_nil(), st)
  | PT_EOF() => @(list_nil(), st)
  | _ =>
    let val @(t, st1) = parse_type(st) in
      case+ ps_peek(st1) of
      | PT_COMMA() =>
        let val @(ts, st2) = p_exc_types(ps_advance(st1)) in
          @(list_cons(t, ts), st2) end
      | _ => @(list_cons(t, list_nil()), st1)
    end )
//
(* ****** ****** *)
//
// ---- enum decl: 'enum' UIDENT [typarams] ':' NEWLINE INDENT { casedecl } DEDENT ----
//      casedecl ::= 'case' UIDENT [ '(' type {',' type} ')' ] NEWLINE
//
fun
p_enumdecl(st: pstate, decos: list(pydecorator)): @(pydecl, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)               // past 'enum'
  val @(nm, st2) =
    ( case+ ps_peek(st1) of
      | PT_UIDENT(s) => @(s, ps_advance(st1))
      | _ => @("?", ps_diag(st1, ps_peek_loctn(st1), "expected an enum name (uppercase)")) )
  val @(tvs, st3) = p_typarams(st2)
  val st4 =
    ( case+ ps_peek(st3) of
      | PT_COLON() => ps_advance(st3)
      | _ => ps_diag(st3, ps_peek_loctn(st3), "expected ':' before the enum body") )
  // open the suite: NEWLINE INDENT ... DEDENT
  val st5 = ( case+ ps_peek(st4) of PT_NEWLINE() => ps_advance(st4) | _ => st4 )
  val st6 =
    ( case+ ps_peek(st5) of
      | PT_INDENT() => ps_advance(st5)
      | _ => ps_diag(st5, ps_peek_loctn(st5), "expected an indented enum body") )
  val @(cases, st7) = p_casedecls(st6)
  val st8 = ( case+ ps_peek(st7) of PT_DEDENT() => ps_advance(st7) | _ => st7 )
in
  @(PyCenum(loc, decos, nm, tvs, cases), st8)
end
//
// { casedecl } until DEDENT/EOF.  casedecl ::= 'case' datacon NEWLINE
and
p_casedecls(st: pstate): @(list(pydatacon), pstate) =
( case+ ps_peek(st) of
  | PT_DEDENT() => @(list_nil(), st)
  | PT_EOF()    => @(list_nil(), st)
  | PT_KW_CASE() =>
    let
      val @(c, st1) = p_datacon(ps_advance(st))
      val st2 = ( case+ ps_peek(st1) of PT_NEWLINE() => ps_advance(st1) | _ => st1 )
      val @(cs, st3) = p_casedecls(st2)
    in
      @(list_cons(c, cs), st3)
    end
  | _ =>
    // recover: skip a token, diagnose, keep going to find the DEDENT.
    let val st1 = ps_resync(ps_diag(st, ps_peek_loctn(st), "expected a 'case' in enum body")) in
      p_casedecls(st1) end )
//
// datacon ::= UIDENT [ '(' type { ',' type } ')' ]
and
p_datacon(st: pstate): @(pydatacon, pstate) = let
  val loc = ps_peek_loctn(st)
in
  case+ ps_peek(st) of
  | PT_UIDENT(nm) =>
    let val st1 = ps_advance(st) in
      case+ ps_peek(st1) of
      | PT_LPAREN() =>
        let
          val @(ts, st2) = p_datacon_types(ps_advance(st1))
          val locR = ps_peek_loctn(st2)
          val st3 =
            ( case+ ps_peek(st2) of
              | PT_RPAREN() => ps_advance(st2)
              | _ => ps_diag(st2, locR, "expected ')' in data constructor") )
        in
          @(PyDataCon(loc_span(loc, locR), nm, ts), st3)
        end
      | _ => @(PyDataCon(loc, nm, list_nil()), st1)
    end
  | _ =>
    let val st1 = ps_diag(st, loc, "expected a data constructor (uppercase)") in
      @(PyDataCon(loc, "?", list_nil()), st1) end
end
//
and
p_datacon_types(st: pstate): @(pytyplst, pstate) =
( case+ ps_peek(st) of
  | PT_RPAREN() => @(list_nil(), st)
  | PT_EOF() => @(list_nil(), st)
  | _ =>
    let val @(t, st1) = parse_type(st) in
      case+ ps_peek(st1) of
      | PT_COMMA() =>
        let val @(ts, st2) = p_datacon_types(ps_advance(st1)) in
          @(list_cons(t, ts), st2) end
      | _ => @(list_cons(t, list_nil()), st1)
    end )
//
// DECORATOR REWORK (slice 2): the keyword parsers p_data_suite_after_kw / p_datapropdecl /
// p_dataviewdecl were REMOVED. `dataprop` / `dataview` are now @decorators on a plain `enum`
// (`@prop enum` / `@view enum`), parsed by p_enumdecl with the prefix decorators threaded in (the
// case-suite shape is IDENTICAL to a plain enum). The elaborator (pyelab_decl) routes the decorated
// enum to PCCdata carrying the PROP / VIEW mode (PCMprop / PCMview), so dt_sort_of picks the
// prop / view sort. The L2 lowering is reused unchanged. See parse_decl's PT_KW_ENUM arm.
//
(* ****** ****** *)
//
// ---- struct decl: 'struct' UIDENT [typarams] ':' NEWLINE INDENT { fielddecl } DEDENT ----
//      fielddecl ::= LIDENT ':' type NEWLINE
//
fun
p_structdecl(st: pstate, decos: list(pydecorator)): @(pydecl, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)               // past 'struct'
  val @(nm, st2) =
    ( case+ ps_peek(st1) of
      | PT_UIDENT(s) => @(s, ps_advance(st1))
      | _ => @("?", ps_diag(st1, ps_peek_loctn(st1), "expected a struct name (uppercase)")) )
  val @(tvs, st3) = p_typarams(st2)
  val st4 =
    ( case+ ps_peek(st3) of
      | PT_COLON() => ps_advance(st3)
      | _ => ps_diag(st3, ps_peek_loctn(st3), "expected ':' before the struct body") )
  val st5 = ( case+ ps_peek(st4) of PT_NEWLINE() => ps_advance(st4) | _ => st4 )
  val st6 =
    ( case+ ps_peek(st5) of
      | PT_INDENT() => ps_advance(st5)
      | _ => ps_diag(st5, ps_peek_loctn(st5), "expected an indented struct body") )
  val @(fields, st7) = p_fielddecls(st6)
  val st8 = ( case+ ps_peek(st7) of PT_DEDENT() => ps_advance(st7) | _ => st7 )
in
  @(PyCstruct(loc, decos, nm, tvs, fields), st8)
end
//
// { fielddecl } until DEDENT/EOF.  fielddecl ::= LIDENT ':' type NEWLINE
and
p_fielddecls(st: pstate): @(list(pyfield), pstate) =
( case+ ps_peek(st) of
  | PT_DEDENT() => @(list_nil(), st)
  | PT_EOF()    => @(list_nil(), st)
  | PT_LIDENT(nm) =>
    let
      val loc = ps_peek_loctn(st)
      val st1 = ps_advance(st)
      val st2 =
        ( case+ ps_peek(st1) of
          | PT_COLON() => ps_advance(st1)
          | _ => ps_diag(st1, ps_peek_loctn(st1), "expected ':' after a struct field name") )
      val @(t, st3) = parse_type(st2)
      val st4 = ( case+ ps_peek(st3) of PT_NEWLINE() => ps_advance(st3) | _ => st3 )
      val @(rest, st5) = p_fielddecls(st4)
    in
      @(list_cons(PyField(loc, nm, t), rest), st5)
    end
  | _ =>
    let val st1 = ps_resync(ps_diag(st, ps_peek_loctn(st), "expected a struct field (name ':' type)")) in
      p_fielddecls(st1) end )
//
(* ****** ****** *)
//
// ---- imports ----
//
// 'import' modpath  |  'from' modpath 'import' ( '*' | LIDENT { ',' LIDENT } )
//
fun
p_import(st: pstate): @(pydecl, pstate) = let
  val loc = ps_peek_loctn(st)
in
  case+ ps_peek(st) of
  | PT_KW_IMPORT() =>
    let
      val st1 = ps_advance(st)
      val @(segs, st2) = p_modpath(st1)
    in
      @(PyCimport(loc, PyImpModule(loc, segs)), st2)
    end
  | PT_KW_FROM() =>
    let
      val st1 = ps_advance(st)
      val @(segs, st2) = p_modpath(st1)
      val st3 =
        ( case+ ps_peek(st2) of
          | PT_KW_IMPORT() => ps_advance(st2)
          | _ => ps_diag(st2, ps_peek_loctn(st2), "expected 'import' in from-import") )
    in
      case+ ps_peek(st3) of
      | PT_STAR() =>
        @(PyCimport(loc, PyImpFrom(loc, segs, true, list_nil())), ps_advance(st3))
      | _ =>
        let val @(names, st4) = p_import_names(st3) in
          @(PyCimport(loc, PyImpFrom(loc, segs, false, names)), st4) end
    end
  | _ =>
    let val st1 = ps_diag(st, loc, "expected 'import' or 'from'") in
      @(PyCerror(loc, "expected an import"), st1) end
end
//
// modpath ::= IDENT { '.' IDENT } | STRING   where IDENT is LIDENT *or* UIDENT.
// A dotted module-path SEGMENT is a FILESYSTEM directory/file name (M7-import, task #34), which
// may be upper- or lower-case (e.g. `frontend.TEST.m7imp.lib`). So we accept BOTH PT_LIDENT and
// PT_UIDENT segments here (unlike a value/type identifier, the case carries no meaning for a path).
and
p_modpath(st: pstate): @(list(strn), pstate) =
( case+ ps_peek(st) of
  | PT_STRING(s) => @(list_cons(s, list_nil()), ps_advance(st))   // a path literal
  | PT_LIDENT(s) => p_modpath_seg(s, ps_advance(st))
  | PT_UIDENT(s) => p_modpath_seg(s, ps_advance(st))
  | _ =>
    let val st1 = ps_diag(st, ps_peek_loctn(st), "expected a module path") in
      @(list_nil(), st1) end )
//
// after consuming segment `s`, continue the dotted path iff a '.' follows.
and
p_modpath_seg(s: strn, st1: pstate): @(list(strn), pstate) =
( case+ ps_peek(st1) of
  | PT_DOT() =>
    let val @(rest, st2) = p_modpath(ps_advance(st1)) in
      @(list_cons(s, rest), st2) end
  | _ => @(list_cons(s, list_nil()), st1) )
//
and
p_import_names(st: pstate): @(list(strn), pstate) =
( case+ ps_peek(st) of
  | PT_LIDENT(nm) =>
    let val st1 = ps_advance(st) in
      case+ ps_peek(st1) of
      | PT_COMMA() =>
        let val @(rest, st2) = p_import_names(ps_advance(st1)) in
          @(list_cons(nm, rest), st2) end
      | _ => @(list_cons(nm, list_nil()), st1)
    end
  | _ =>
    let val st1 = ps_diag(st, ps_peek_loctn(st), "expected an imported name") in
      @(list_nil(), st1) end )
//
(* ****** ****** *)
//
// ---- the SATS `parse_decl` entry: a decl may be prefixed by decorators (§5.7), so FIRST parse
//      zero-or-more prefix decorators, THEN dispatch on the next keyword. The decorators are
//      threaded into the node:
//        * enum/struct/type/abstype : the MODE decorators (@boxed/@unboxed/@linear).
//        * def  : DECORATOR REWORK — `@proof`/`@extern`/`@impl`/`@overload` select the def VARIANT
//                 (the elaborator routes a decorated def to PCCprfun/PCCextern/PCCpraxi/...). An
//                 undecorated `def` is a plain def. We ALWAYS thread the decorators into PyCfun.
//        * let  : DECORATOR REWORK — `@proof let` (was `prval`); threaded into PyDlet, wrapped as
//                 a PyCstmt decl so the module loop and statement position both see it.
//
#implfun
parse_decl(st) = let
  val locD = ps_peek_loctn(st)
  val @(decos, st0) = p_decorators(st)
  val nod = ps_peek(st0)
in
  case+ nod of
  | PT_KW_DEF()    => p_def(st0, decos)   // decorators select the def variant (proof/extern/impl/overload)
  | PT_KW_LET()    =>
    // DECORATOR REWORK: a `@... let p = e` at module level (e.g. `@proof let`). parse_let_decos
    // (dynexp) parses the binding with the prefix decorators threaded in; we wrap it as PyCstmt
    // (a module-level let IS a statement, §5.2). Its trailing NEWLINE is consumed by p_top_item.
    let val @(s, st1) = parse_let_decos(st0, decos) in
      @(PyCstmt(pystmt_loctn(s), s), st1) end
  // DECORATOR REWORK (slice 2): `@prop enum` / `@view enum` are a plain enum with the prefix
  // decorators threaded into PyCenum; the elaborator routes them to PCCdata with the PROP/VIEW
  // mode. An undecorated enum is a plain boxed datatype.
  | PT_KW_ENUM()   => p_enumdecl(st0, decos)
  | PT_KW_STRUCT() => p_structdecl(st0, decos)
  // DECORATOR REWORK (slice 2): `type` carries the ATS-specific VARIANT decorators (@abstract /
  // @impl / @sort / @static) — p_typedecl dispatches on them to the right AST node (PyCabstype /
  // PyCassume / PyCsortdef / PyCstadef); an undecorated `type` is a plain alias (PyCtype). The
  // mode decorators (@boxed/@unboxed/@linear) also ride here for @abstract.
  | PT_KW_TYPE()   => p_typedecl(st0, decos)
  | PT_KW_EXCEPTION() =>
    // EXN: `exception E(T...)` takes NO decorators in v1 (it is a single exn constructor,
    // not a mode-bearing type decl). If any precede it, reject for recovery (mirrors def).
    ( case+ decos of
      | list_nil() => p_exceptdecl(st0)
      | _ =>
        let val @(_, st1) = p_exceptdecl(st0) in
          @(PyCerror(locD, "decorators are not allowed on an 'exception'"),
            ps_diag(st1, locD, "decorators are not allowed on an 'exception'")) end )
  | PT_KW_IMPORT() => p_import(st0)
  | PT_KW_FROM()   => p_import(st0)
  | _ =>
    // not a structural decl — should be reached only via the module loop's fallback;
    // produce an error decl (the loop already handles stmt-position decls separately).
    let
      val loc = ps_peek_loctn(st0)
      val st1 = ps_diag(st0, loc, "expected a declaration")
    in
      @(PyCerror(loc, "expected a declaration"), st1)
    end
end
//
(* ****** ****** *)
//
// =====================================================================
//  MODULE: a sequence of top-level decls. A structural keyword (def/type/import/from)
//  is a decl; everything else at top level is a STATEMENT (module init may contain
//  statements, §5.2) wrapped as PyCstmt. Layout NEWLINEs between decls are skipped;
//  stray INDENT/DEDENT at top level (shouldn't normally occur) are skipped defensively.
// =====================================================================
//
// parse one top-level item (decl or a statement-as-decl). The simple-statement path
// needs to consume its NEWLINE terminator; block statements consume their own.
//
fun
p_top_item(st: pstate): @(pydecl, pstate) = let
  val nod = ps_peek(st)
in
  case+ nod of
  | PT_KW_DEF()    => parse_decl(st)
  | PT_KW_ENUM()   => parse_decl(st)     // block-bodied: consumes its own DEDENT (no trailing NEWLINE)
  | PT_KW_STRUCT() => parse_decl(st)     // block-bodied: consumes its own DEDENT
  | PT_AT()        =>
    // DECORATOR REWORK: a decorator-prefixed decl. The construct after the decorators may be:
    //   * enum/struct/def-with-body (`@impl def`, `@proof def`, `@overload def`, `@prop enum`,
    //     `@view enum`) — BLOCK-bodied, consumes its own DEDENT; expect_newline_d is then a no-op.
    //   * type alias / `@abstract type` / `@impl type` / `@sort type` / `@static type` /
    //     `@extern def` / `@proof @extern def` (praxi) / `@proof let` / `@static let` — SINGLE-line;
    //     expect_newline_d consumes the trailing NEWLINE.
    // expect_newline_d handles BOTH (consume a NEWLINE iff present), so this one arm covers all
    // decorated forms uniformly.
    let val @(d, st1) = parse_decl(st) in @(d, expect_newline_d(st1)) end
  | PT_KW_TYPE()   =>
    let val @(d, st1) = parse_decl(st) in @(d, expect_newline_d(st1)) end
  | PT_KW_EXCEPTION() =>
    // EXN: a single-line `exception E(T...)` decl — consume its trailing NEWLINE, like `type`.
    let val @(d, st1) = parse_decl(st) in @(d, expect_newline_d(st1)) end
  | PT_KW_IMPORT() =>
    let val @(d, st1) = parse_decl(st) in @(d, expect_newline_d(st1)) end
  | PT_KW_FROM()   =>
    let val @(d, st1) = parse_decl(st) in @(d, expect_newline_d(st1)) end
  | _ =>
    // a top-level STATEMENT (let / expr / if / while / for / match / break / ...).
    // Reuse dynexp's `parse_stmt` (a block stmt consumes its own layout; a simple stmt
    // is terminated by NEWLINE) and wrap the result as PyCstmt (module init may contain
    // statements, §5.2). No duplication of the statement grammar.
    let
      val @(s, st1) = parse_stmt(st)
    in
      @(PyCstmt(pystmt_loctn(s), s), st1)
    end
end
//
(* ****** ****** *)
//
// the module loop: skip leading NEWLINEs; at EOF stop; else parse one top item, and
// if NOTHING was consumed (the lookahead is unchanged), force-advance + diagnose to
// guarantee progress (no infinite loop on a stuck token).
//
fun
p_module_loop(st: pstate, acc: pydeclst): @(pydeclst, pstate) = let
  val st0 = ps_skip_newlines(st)
in
  case+ ps_peek(st0) of
  | PT_EOF() => @(list_reverse(acc), st0)
  | PT_DEDENT() => p_module_loop(ps_advance(st0), acc)   // defensive
  | PT_INDENT() => p_module_loop(ps_advance(st0), acc)   // defensive
  | _ =>
    let
      val @(d, st1) = p_top_item(st0)
      // progress guard: if the stream did not advance, drop a token to avoid a loop.
      val st2 =
        ( if same_head(st0, st1)
          then ps_resync(ps_diag(st1, ps_peek_loctn(st1), "skipping unparseable token"))
          else st1 )
    in
      p_module_loop(st2, list_cons(d, acc))
    end
end
//
// crude structural "did the head token advance?" check by comparing remaining lengths.
and
same_head(a: pstate, b: pstate): bool = let
  val+ PState(ta, _) = a
  val+ PState(tb, _) = b
in
  (list_length(ta) = list_length(tb))
end
//
(* ****** ****** *)
//
// ---- the public entries ----------------------------------------------------
//
#implfun
pyparse_tokens(toks) = let
  // ROBUSTNESS (Bug #41): re-arm the module-local bracket-recursion DEPTH guard at the start of
  // every file parse (the parser is one-shot per file; this keeps the counter re-entrant-safe).
  val () = ps_depth_reset()
  val st0 = PState(toks, list_nil())
  val @(decls, st1) = p_module_loop(st0, list_nil())
  val+ PState(_, rdiag) = st1
in
  PyModule(decls, list_reverse(rdiag))
end
//
#implfun
pyparse_module(src, text) = let
  val toks = pylex_layout(src, text)
in
  pyparse_tokens(toks)
end
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyparsing_decl00.dats]
*)
