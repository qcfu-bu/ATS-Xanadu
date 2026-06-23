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
    else (if strn_eq(nm, "overload") then
      // GAP1: `@overload[N]` — a single INT PRECEDENCE literal (the `#symload … of N`). Parse
      // `[`, the INT lexeme, `]`; a malformed/missing int degrades to PyDAnone (no precedence ->
      // the default at lowering), a graceful recovery rather than a crash.
      p_deco_prec(st)
    else @(PyDAnone(), st)))       // a '[' after some OTHER decorator: not a payload — leave it.
  | _ => @(PyDAnone(), st)
end
//
// GAP1: parse a `@overload[N]` PRECEDENCE bracket — `[` INT `]` -> PyDAprec(loc, N). A
// non-int or missing `]` degrades to PyDAnone (graceful: the overload alias just uses the
// default precedence). Assumes the leading `[` has NOT been consumed (ps_peek = PT_LBRACK).
and
p_deco_prec(st: pstate): @(pydecoargs, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)   // consume `[`
in
  case+ ps_peek(st1) of
  | PT_INT(raw) =>
    let
      val st2 = ps_advance(st1)
      val st3 =
        ( case+ ps_peek(st2) of
          | PT_RBRACK() => ps_advance(st2)
          | _ => ps_diag(st2, ps_peek_loctn(st2), "expected ']' after overload precedence") )
    in
      @(PyDAprec(loc, gint_parse_sint(raw)), st3)
    end
  | _ =>
    let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected an integer precedence in @overload[…]") in
      @(PyDAnone(), st2) end
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
  fun
  has_deco(ds: list(pydecorator), name: strn): bool =
  ( case+ ds of
    | list_nil() => false
    | list_cons(PyDecor(_, nm, _), rest) =>
        if strn_eq(nm, name) then true else has_deco(rest, name) )
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)               // past 'def'
  // name: a LIDENT (ordinary def) OR a UIDENT. FFI (bootstrap P1, feature 3): the corpus's
  // foreign-binding functions are ALL uppercase-initial (`XATS000_foo`, `XATS2PY_g_stdin`,
  // `XATSOPT_a0ref_set`), so `@extern def XATS000_foo(...)` / `@impl def XATS000_bar(...)` must
  // accept an UPPERCASE function name. A UIDENT name is otherwise byte-identical to a LIDENT one:
  // the elaborator routes it the same (PCCextern/PCCimplement/PCCfun), and the lowering resolves
  // a UIDENT-headed call to the registered d2cst via pl_var's D2ITMcst arm (pl_app's con-head arm
  // already lowers a PCEcon head through pl_exp -> pl_con_value -> pl_var). Lowercase still lexes
  // as the usual function/variable name; only the parser's name slot is widened.
  val @(nm, st2) =
    ( case+ ps_peek(st1) of
      | PT_LIDENT(s) => @(s, ps_advance(st1))
      | PT_UIDENT(s) => @(s, ps_advance(st1))   // FFI: an uppercase-initial foreign function name
      | _ => @("?", ps_diag(st1, ps_peek_loctn(st1), "expected a function name")) )
  val @(tvs, st3) = p_typarams(st2)
  // '(' params ')' when present. A pretty-printed `#impltmp f<T> = body` has no
  // dynamic farg at all, distinct from the nullary farg `f<T>()`; preserve that
  // distinction as `has_darg=false` for `@impl def f: body`.
  val @(has_darg, params, st6) =
    ( case+ ps_peek(st3) of
      | PT_LPAREN() =>
        let
          val @(params, st5) = p_def_params(ps_advance(st3))
          val st6 =
            ( case+ ps_peek(st5) of
              | PT_RPAREN() => ps_advance(st5)
              | _ => ps_diag(st5, ps_peek_loctn(st5), "expected ')'") )
        in
          @(true, params, st6)
        end
      | _ =>
        if has_deco(decos, "impl") then @(false, list_nil(), st3)
        else @(true, list_nil(), ps_diag(st3, ps_peek_loctn(st3), "expected '(' after function name")) )
  // optional return type
  val @(ropt, st7) =
    ( case+ ps_peek(st6) of
      | PT_ARROW() =>
        let val @(t, st7) = parse_type(ps_advance(st6)) in @(PyTypSome(t), st7) end
      | _ => @(PyTypNone(), st6) )
  // FFI: an OPTIONAL `= extnam(["cname"])` foreign-name binding on an `@extern def` (the round-trip
  // of stock `#extern fun foo(...) : T = $extnam(["cname"])` — the dominant 665× prelude construct).
  // It sits BETWEEN the return type and any (normally absent) body. We parse it whenever it follows
  // and ATTACH it to the `@extern` decorator's payload (PyDAextnam), so elab_decl threads it onto
  // PCCextern with NO change to the PyCfun shape. A bodyless `@extern def` (no `= extnam`) is
  // byte-identical to before. `extnam()` -> PyExpNone (empty form); `extnam("c")` -> PyExpSome(str).
  val @(decos, st8) = p_extnam_rhs(decos, st7)
  // OPTIONAL ':' body suite — a plain/@proof/@impl/@overload def HAS one; an @extern (or
  // @proof @extern = praxi) def is BODYLESS (no ':'). Parse a body iff a ':' follows; else empty.
  val @(body, st9) =
    ( case+ ps_peek(st8) of
      | PT_COLON() => parse_suite(ps_advance(st8))
      | _ => @(list_nil(), st8) )
  // SCOPING (bootstrap P1): an OPTIONAL trailing `where:` block at the DEF's indent level. After
  // the body suite consumes its own DEDENT, a `where` keyword sits at the def's level. Its block
  // is a SUITE OF DECLS (`def go(...)`) indented under `where:`. The decls are BACKWARDS-scoped
  // around the body (ATS `e where {decls}`); we attach them and M3 wraps the body in D2Ewhere.
  val @(wheres, st10) =
    ( case+ ps_peek(st9) of
      | PT_KW_WHERE() =>
        let
          val stw = ps_advance(st9)              // past 'where'
          val stw2 =
            ( case+ ps_peek(stw) of
              | PT_COLON() => ps_advance(stw)
              | _ => ps_diag(stw, ps_peek_loctn(stw), "expected ':' after 'where'") )
        in
          p_decl_block(stw2)
        end
      | _ => @(list_nil(), st9) )
in
  @(PyCfun(loc, decos, nm, tvs, has_darg, params, ropt, body, wheres), st10)
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
// FFI: parse an OPTIONAL `= extnam(["cname"])` foreign-name binding (the round-trip of stock
// `= $extnam(["cname"])`) and ATTACH it onto the `@extern` decorator's payload (PyDAextnam). The
// grammar is `'=' 'extnam' '(' [ STRING ] ')'`. The optional STRING (quotes included in the lexeme)
// is the explicit foreign C name; absent = the empty `extnam()` form (the foreign name defaults to
// the fun's own name — the dominant prelude form). When the RHS is NOT present (no `=`, or `=`
// not followed by `extnam`), the decorators are returned UNCHANGED (a plain/bodyless def). We only
// rewrite the `@extern` decorator (the elaborator reads it from there); if there is no `@extern`
// decorator the RHS is parsed but harmlessly dropped (recovery — an `= extnam` on a non-extern def
// is malformed, but we do not crash the parse).
and
p_extnam_rhs(decos: list(pydecorator), st: pstate): @(list(pydecorator), pstate) =
( case+ ps_peek(st) of
  | PT_EQ() =>
    ( case+ ps_peek(ps_advance(st)) of   // the token AFTER the '='
      | PT_LIDENT(kw) =>
        if strn_eq(kw, "extnam") then p_extnam_after_eq(decos, st)
        // `= <something-else>`: NOT an extnam binding. Leave the '=' for the (absent) body path;
        // do not consume anything. Return the ORIGINAL state so nothing is lost.
        else @(decos, st)
      | _ => @(decos, st) )
  | _ => @(decos, st) )
//
// parse the rest of `= extnam(["cname"])` (the `=` + `extnam` already peeked) and attach the payload.
and
p_extnam_after_eq(decos: list(pydecorator), st: pstate): @(list(pydecorator), pstate) = let
  val loc = ps_peek_loctn(st)
  val st2 = ps_advance(ps_advance(st))   // past '=' and 'extnam'
  // '(' [ STRING ] ')'
  val st3 =
    ( case+ ps_peek(st2) of
      | PT_LPAREN() => ps_advance(st2)
      | _ => ps_diag(st2, ps_peek_loctn(st2), "expected '(' after 'extnam'") )
  val @(copt, st4) =
    ( case+ ps_peek(st3) of
      | PT_STRING(s) => @(PyExpSome(PyElit(ps_peek_loctn(st3), PyLstr(ps_peek_loctn(st3), s))), ps_advance(st3))
      | _            => @(PyExpNone(), st3) )
  val st5 =
    ( case+ ps_peek(st4) of
      | PT_RPAREN() => ps_advance(st4)
      | _ => ps_diag(st4, ps_peek_loctn(st4), "expected ')' to close 'extnam(...)'") )
in
  @(decos_attach_extnam(decos, loc, copt), st5)
end
//
// rewrite the FIRST `@extern` decorator to carry the parsed extnam payload. A def with no `@extern`
// decorator is left unchanged (the payload is dropped — see p_extnam_rhs).
and
decos_attach_extnam(decos: list(pydecorator), loc: loctn, copt: pyexpopt): list(pydecorator) =
( case+ decos of
  | list_nil() => list_nil()
  | list_cons(PyDecor(dloc, nm, dargs), rest) =>
      if strn_eq(nm, "extern")
        then list_cons(PyDecor(dloc, nm, PyDAextnam(loc, copt)), rest)
        else list_cons(PyDecor(dloc, nm, dargs), decos_attach_extnam(rest, loc, copt)) )
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
//   @impl     type Foo [tvs] = T                      -> PyCassume   (was `assume`; hidden repr T)
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
  // @abstract type Foo [tvs] [<= REP] — an OPAQUE type; NO `= rhs` body (opacity is the point).
  // The mode decorators (@unboxed) ride in `decos`; the elaborator's mode_of_decos selects
  // box/flat. Parse the typarams, then OPTIONALLY a `<= REP` REPRESENTATION witness (TAIL ITEM 1,
  // the stock `abstype stamp_type <= uint`): if the next token is `<=` (PT_LTE), parse the REP
  // type and carry it as PyTypSome; otherwise PyTypNone. PyCabstype, the `abstype` node + rep slot.
  if decos_has_p(decos, "abstract") then
    let
      val @(tvs, st3) = p_typarams(st2)
      val @(repopt, st4) =
        ( case+ ps_peek(st3) of
          | PT_LTE() =>
            let val @(rt, stR) = parse_type(ps_advance(st3)) in @(PyTypSome(rt), stR) end
          | _ => @(PyTypNone(), st3) ): @(pytypopt, pstate)
    in
      @(PyCabstype(loc, decos, nm, tvs, repopt), st4) end
  // @sort type Nat [= <rhs>] — a SORT declaration. WITHOUT a `=` RHS it is an ABSTRACT SORT
  // (ATS-parity `#abssort Nat`) -> PyCabssort. WITH a `=` RHS it is a sort DEFINITION whose RHS is:
  //   * a sort-reference UIDENT (`SInt`/`Type`/...)        -> PyCsortdef (the old `sortdef` alias), OR
  //   * A-QUANT: a SUBSET `{ a: SInt | a >= 0 }`           -> PyCsortsub (the refined sortdef).
  // No typarams (a sort decl is monomorphic). The leading `{` after `=` selects the subset form.
  else if decos_has_p(decos, "sort") then
    (
      case+ ps_peek(st2) of
      // NO `=` RHS -> an ABSTRACT SORT. The MISSING RHS is exactly what distinguishes abssort
      // from a sort alias (`#abssort` vs `#sortdef`).
      | PT_EQ() =>
        let val st3 = ps_advance(st2) in
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
      | _ => @(PyCabssort(loc, nm), st2)
    )
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
  // @open type Foo — OPEN an abstract type's representation (ATS-parity `#absopen Foo`). No typarams,
  // no RHS — it just NAMES the already-declared abstract type to open. PyCabsopen.
  else if decos_has_p(decos, "open") then
    @(PyCabsopen(loc, nm), st2)
  // @impl type Foo [tvs] = T — gives an abstract type its hidden REPRESENTATION T.
  // Non-empty tvs mirror ATS `#absimpl Foo(a:type) = T`.
  else if decos_has_p(decos, "impl") then
    let
      val @(tvs, stT) = p_typarams(st2)
      val st3 =
        ( case+ ps_peek(stT) of
          | PT_EQ() => ps_advance(stT)
          | _ => ps_diag(stT, ps_peek_loctn(stT), "expected '=' in '@impl type' declaration") )
      val @(t, st4) = parse_type(st3)
    in
      @(PyCassume(loc, nm, tvs, t), st4)
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
      // optional `as NAME` -> the named-alias of `#staload NAME = "modpath"`.
      val @(aopt, st3) =
        ( case+ ps_peek(st2) of
          | PT_KW_AS() =>
            let val st2a = ps_advance(st2) in
              case+ ps_peek(st2a) of
              | PT_UIDENT(nm) => @(optn_cons(nm), ps_advance(st2a))
              | PT_LIDENT(nm) => @(optn_cons(nm), ps_advance(st2a))
              | _ =>
                let val st2b = ps_diag(st2a, ps_peek_loctn(st2a), "expected an alias name after 'as'") in
                  @(optn_nil(), st2b) end
            end
          | _ => @(optn_nil(), st2) ) : @(optn(strn), pstate)
    in
      @(PyCimport(loc, PyImpModule(loc, segs, aopt)), st3)
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
// ---- include (faithful #include) ----
//
// 'include' STRING   — the TEXTUAL inline-expansion form (stock ATS `#include "PATH"`). The path is
// a STRING literal ONLY (mirroring stock, which always quotes the include path); we keep the RAW
// lexeme (quotes included), unquoting at lowering. Distinct from import (a dotted modpath / sealed
// module): an include INLINES the referenced file's decls into THIS file's L2 tree.
fun
p_include(st: pstate): @(pydecl, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)   // consume the `include` keyword
in
  case+ ps_peek(st1) of
  | PT_STRING(s) => @(PyCinclude(loc, s), ps_advance(st1))
  | _ =>
    let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected a \"PATH\" string after 'include'") in
      @(PyCerror(loc, "expected a path string after 'include'"), st2) end
end
//
(* ****** ****** *)
//
// GAP1 (overload-ALIAS): file-local helpers for the STANDALONE `@overload NAME = TARGET` decl, used
// by parse_decl below. Defined here (before parse_decl) so they are in scope; neither calls back into
// parse_decl, so they live in their own `fun … and …` group rather than parse_decl's #implfun.
//
// the overload-ALIAS parser, positioned ON the overloaded NAME, with `decos` already parsed.
// Grammar:  NAME '=' TARGET  where NAME is a LIDENT/UIDENT or an operator token (`+`, `[]`, ...)
// and TARGET is a LIDENT or UIDENT. The precedence rides on the `@overload[N]` decorator (read by
// decos_overload_prec_p; ~1 if none). A bare NAME with NO `@overload` decorator is NOT a decl ->
// the "expected a declaration" error (preserving the old behavior for non-overload junk). A missing
// `=` or TARGET degrades to a PyCerror + diagnostic (graceful recovery, never a crash).
fun
p_overload_name(st: pstate): @(strn, pstate, bool) =
(
  case+ ps_peek(st) of
  | PT_LIDENT(s) => @(s, ps_advance(st), true)
  | PT_UIDENT(s) => @(s, ps_advance(st), true)
  | PT_PLUS()    => @("+", ps_advance(st), true)
  | PT_MINUS()   => @("-", ps_advance(st), true)
  | PT_STAR()    => @("*", ps_advance(st), true)
  | PT_SLASH()   => @("/", ps_advance(st), true)
  | PT_SLASH2()  => @("//", ps_advance(st), true)
  | PT_PERCENT() => @("%", ps_advance(st), true)
  | PT_STAR2()   => @("**", ps_advance(st), true)
  | PT_EQEQ()    => @("==", ps_advance(st), true)
  | PT_NEQ()     => @("!=", ps_advance(st), true)
  | PT_LT()      =>
    let
      val st1 = ps_advance(st)
    in
      case+ ps_peek(st1) of
      | PT_LT() => @("<<", ps_advance(st1), true)
      | _ => @("<", st1, true)
    end
  | PT_LTE()     => @("<=", ps_advance(st), true)
  | PT_GT()      =>
    let
      val st1 = ps_advance(st)
    in
      case+ ps_peek(st1) of
      | PT_GT() =>
        let
          val st2 = ps_advance(st1)
        in
          case+ ps_peek(st2) of
          | PT_GT() => @(">>>", ps_advance(st2), true)
          | _ => @(">>", st2, true)
        end
      | _ => @(">", st1, true)
    end
  | PT_GTE()     => @(">=", ps_advance(st), true)
  | PT_AMP()     => @("&", ps_advance(st), true)
  | PT_LBRACK() =>
    let
      val st1 = ps_advance(st)
    in
      case+ ps_peek(st1) of
      | PT_RBRACK() => @("[]", ps_advance(st1), true)
      | _ => @("", st, false)
    end
  | _ => @("", st, false)
)
and
p_overload_alias(st: pstate, decos: list(pydecorator), loc: loctn): @(pydecl, pstate) =
  if ~decos_has_p(decos, "overload") then
    // a name token with no `@overload` (or any other) decorator at decl position: not a decl.
    let val st1 = ps_diag(st, ps_peek_loctn(st), "expected a declaration") in
      @(PyCerror(loc, "expected a declaration"), st1) end
  else let
    val @(nm, st1, ok) = p_overload_name(st)
  in
    if ~ok then
      let val st2 = ps_diag(st, ps_peek_loctn(st), "expected an overload-alias name") in
        @(PyCerror(loc, "expected an overload-alias name"), st2) end
    else
      case+ ps_peek(st1) of
      | PT_EQ() =>
        let
          val st2 = ps_advance(st1)   // consume '='
        in
          case+ ps_peek(st2) of
          // the TARGET may be a QUALIFIED name `M.x` (a named-staload member, e.g.
          // `@overload TRUE = SYM.TRUE_symbl` <-> ATS `#symload TRUE with $SYM.TRUE_symbl`).
          // p_overload_target_name joins a trailing `.name` into one dotted target string.
          | PT_LIDENT(tgt) =>
              let val @(tgt1, st3) = p_overload_target_name(tgt, ps_advance(st2)) in
                @(PyCsymalias(loc, nm, tgt1, decos_overload_prec_p(decos)), st3) end
          | PT_UIDENT(tgt) =>
              let val @(tgt1, st3) = p_overload_target_name(tgt, ps_advance(st2)) in
                @(PyCsymalias(loc, nm, tgt1, decos_overload_prec_p(decos)), st3) end
          | _ =>
            let val st3 = ps_diag(st2, ps_peek_loctn(st2), "expected a target function after '=' in an overload alias") in
              @(PyCerror(loc, "expected an overload-alias target"), st3) end
        end
      | _ =>
        let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected '=' in an overload alias (@overload NAME = TARGET)") in
          @(PyCerror(loc, "expected '=' in an overload alias"), st2) end
  end
//
// after the first target segment, join a trailing `.name` (qualified module member) into one
// dotted target string `M.x` (the lowering's symalias resolver routes a `.`-bearing target through
// the qualified-name path). A bare target has no trailing dot and returns unchanged.
and
p_overload_target_name(seg0: strn, st: pstate): @(strn, pstate) =
( case+ ps_peek(st) of
  | PT_DOT() =>
    let val st1 = ps_advance(st) in
      case+ ps_peek(st1) of
      | PT_LIDENT(s1) => @(strn_append(strn_append(seg0, "."), s1), ps_advance(st1))
      | PT_UIDENT(s1) => @(strn_append(strn_append(seg0, "."), s1), ps_advance(st1))
      | _ =>
        let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected a member name after '.' in an overload target") in
          @(seg0, st2) end
    end
  | _ => @(seg0, st) )
//
// read the `@overload[N]` PRECEDENCE off the decorator list (parser-side). Returns the parsed N,
// or `~1` when no `@overload[N]` bracket was given (the default-precedence sentinel the lowering
// maps to the stock default 0).
and
decos_overload_prec_p(decos: list(pydecorator)): sint =
( case+ decos of
  | list_nil() => (-1)
  | list_cons(PyDecor(_, nm, dargs), rest) =>
      if strn_eq(nm, "overload")
        then ( case+ dargs of
               | PyDAprec(_, n) => n
               | _ => decos_overload_prec_p(rest) )
        else decos_overload_prec_p(rest) )
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
  // INCLUDE (faithful #include): `include "PATH"` — a TEXTUAL inline expansion (distinct from
  // import/from, which merge a sealed module's env). Takes NO decorators (like import).
  | PT_KW_INCLUDE() => p_include(st0)
  // SCOPING (bootstrap P1): `private` — a decl-MODIFIER (`private def helper(...)` — one decl) or a
  // `private:` BLOCK (an indented suite of private decls). It is the OUTERMOST modifier (it takes no
  // PRECEDING decorators; an inner `private @impl def` re-enters parse_decl which parses those). The
  // capture-rest transform (privates = local-head D1, following siblings = local-body D2 -> D2Clocal0)
  // is a MODULE/SUITE-lowering concern; the parser just emits the PyCprivate marker carrying the run.
  | PT_KW_PRIVATE() =>
    ( case+ decos of
      | list_cons _ =>
        let val st1 = ps_diag(st0, locD, "decorators must follow 'private', not precede it") in
          @(PyCerror(locD, "decorators must follow 'private'"), st1) end
      | list_nil() => p_private(st0) )
  // GAP1: a STANDALONE overload-ALIAS `@overload NAME = TARGET` (+ `@overload[N]` precedence).
  // No keyword follows the decorator run — the next token is the overloaded NAME (a LIDENT/UIDENT
  // or operator symbol). REQUIRES `@overload` among the decorators;
  // a bare NAME with no overload decorator is NOT a decl -> the error arm. (This dialect has no
  // case `when`-guards, so we route both name tokens through p_overload_alias, which itself checks
  // the `@overload` decorator and falls back to the error path when it is absent.)
  | PT_LIDENT _ => p_overload_alias(st0, decos, locD)
  | PT_UIDENT _ => p_overload_alias(st0, decos, locD)
  | PT_PLUS() => p_overload_alias(st0, decos, locD)
  | PT_MINUS() => p_overload_alias(st0, decos, locD)
  | PT_STAR() => p_overload_alias(st0, decos, locD)
  | PT_SLASH() => p_overload_alias(st0, decos, locD)
  | PT_SLASH2() => p_overload_alias(st0, decos, locD)
  | PT_PERCENT() => p_overload_alias(st0, decos, locD)
  | PT_STAR2() => p_overload_alias(st0, decos, locD)
  | PT_EQEQ() => p_overload_alias(st0, decos, locD)
  | PT_NEQ() => p_overload_alias(st0, decos, locD)
  | PT_LT() => p_overload_alias(st0, decos, locD)
  | PT_LTE() => p_overload_alias(st0, decos, locD)
  | PT_GT() => p_overload_alias(st0, decos, locD)
  | PT_GTE() => p_overload_alias(st0, decos, locD)
  | PT_AMP() => p_overload_alias(st0, decos, locD)
  | PT_LBRACK() => p_overload_alias(st0, decos, locD)
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
//
// SCOPING (bootstrap P1): parse a `private` run. Positioned ON the `private` keyword.
//   `private:` <NEWLINE INDENT decl* DEDENT>   -> PyCprivate(loc, <block decls>)
//   `private <decl>`                           -> PyCprivate(loc, [<single decl>])
// A nested `private @impl def helper(...)` re-enters p_top_item, which dispatches the decorators.
#implfun
p_private(st) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)                       // past 'private'
in
  case+ ps_peek(st1) of
  | PT_COLON() =>
    let val @(ds, st2) = p_decl_block(ps_advance(st1)) in
      @(PyCprivate(loc, ds), st2) end
  | _ =>
    // a single private decl — reuse p_top_item so the following decl consumes its own layout.
    let val @(d, st2) = p_top_item(st1) in
      @(PyCprivate(loc, list_sing(d)), st2) end
end
//
// SCOPING (bootstrap P1): parse a block of DECLS — NEWLINE INDENT decl { decl } DEDENT — the body of
// a `where:` or `private:` header. Mirrors p_block_suite but loops `p_top_item` (the decl dispatcher),
// so each entry is a full pydecl (def/enum/type/nested private). Standalone #implfun so p_def (an
// earlier group) can forward-call it (the call crosses `fun`-group boundaries — see the SATS decl).
#implfun
p_decl_block(st) = let
  val st1 = ( case+ ps_peek(st) of PT_NEWLINE() => ps_advance(st) | _ => st )
in
  case+ ps_peek(st1) of
  | PT_INDENT() =>
    let
      val st2 = ps_advance(st1)                 // past INDENT
      val @(ds, st3) = p_decl_block_loop(st2)
      val st4 = ( case+ ps_peek(st3) of PT_DEDENT() => ps_advance(st3) | _ => st3 )
    in
      @(ds, st4)
    end
  | _ =>
    let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected an indented block") in
      @(list_nil(), st2) end
end
//
// decl-block loop until DEDENT/EOF. Each item is a full top-level decl (reusing p_top_item, which
// consumes per-decl trailing layout). Stray blank lines are skipped.
#implfun
p_decl_block_loop(st) =
( case+ ps_peek(st) of
  | PT_DEDENT() => @(list_nil(), st)
  | PT_EOF() => @(list_nil(), st)
  | PT_NEWLINE() => p_decl_block_loop(ps_advance(st))
  | _ =>
    let
      // ROBUSTNESS: the same non-advancement guard p_stmt_list uses (pyparsing_dynexp). Without
      // it, a decl that consumes NOTHING (e.g. an unparseable decorator type-arg like `@sapp[?]`,
      // where `?` is not yet an accepted type) makes this loop recurse forever -> stack overflow.
      // Detect the stuck position, resync past the offending line, and continue.
      val+ PState(t0, _) = st
      val @(d, st1) = p_top_item(st)
      val+ PState(t1, _) = st1
    in
      if list_length(t0) = list_length(t1) then
        let
          val st2 = ps_resync(ps_diag(st1, ps_peek_loctn(st1), "skipping unparseable declaration"))
          val @(ds, st3) = p_decl_block_loop(st2)
        in
          @(list_cons(d, ds), st3)
        end
      else
        let val @(ds, st2) = p_decl_block_loop(st1) in
          @(list_cons(d, ds), st2) end
    end )
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
#implfun
p_top_item(st) = let
  fun
  is_expr_decorator(nm: strn): bool =
    if strn_eq(nm, "func") then true else
    if strn_eq(nm, "inst") then true else
    if strn_eq(nm, "sapp") then true else false
  val nod = ps_peek(st)
in
  case+ nod of
  | PT_KW_DEF()    => parse_decl(st)
  | PT_KW_ENUM()   => parse_decl(st)     // block-bodied: consumes its own DEDENT (no trailing NEWLINE)
  | PT_KW_STRUCT() => parse_decl(st)     // block-bodied: consumes its own DEDENT
  // SCOPING (bootstrap P1): `private` — a `private:` block consumes its own DEDENT; a `private def…`
  // modifier delegates to the inner p_top_item (which consumes the inner decl's own layout). Either
  // way no extra trailing NEWLINE is owed here.
  | PT_KW_PRIVATE() => parse_decl(st)
  | PT_AT()        =>
    // DECORATOR REWORK: expression decorators (`@func`, `@inst`, `@sapp`) are valid module-init
    // statements; declaration decorators continue through parse_decl.
    let
      val stA = ps_advance(st)
    in
      case+ ps_peek(stA) of
      | PT_LIDENT(nm) =>
          if is_expr_decorator(nm) then
            let val @(s, st1) = parse_stmt(st) in @(PyCstmt(pystmt_loctn(s), s), st1) end
          else
            let val @(d, st1) = parse_decl(st) in @(d, expect_newline_d(st1)) end
      | _ =>
          let val @(d, st1) = parse_decl(st) in @(d, expect_newline_d(st1)) end
    end
  | PT_KW_TYPE()   =>
    let val @(d, st1) = parse_decl(st) in @(d, expect_newline_d(st1)) end
  | PT_KW_EXCEPTION() =>
    // EXN: a single-line `exception E(T...)` decl — consume its trailing NEWLINE, like `type`.
    let val @(d, st1) = parse_decl(st) in @(d, expect_newline_d(st1)) end
  | PT_KW_IMPORT() =>
    let val @(d, st1) = parse_decl(st) in @(d, expect_newline_d(st1)) end
  | PT_KW_FROM()   =>
    let val @(d, st1) = parse_decl(st) in @(d, expect_newline_d(st1)) end
  | PT_KW_INCLUDE() =>
    // INCLUDE (faithful #include): a single-line `include "PATH"` — consume its trailing NEWLINE.
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
