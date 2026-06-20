(* ****** ****** *)
(*
** M2 — Python-surface frontend: EXPRESSION (Pratt) + STATEMENT/SUITE parser (DATS).
**
** THE PARSER OWNS PRECEDENCE (§5.6) via precedence-climbing (Pratt) — there is NO ATS
** fixity involved. Expressions and statements/suites are mutually recursive (a lambda
** / if-branch / case body is a suite; a suite contains expressions), so they share one
** `fun … and …` recursion group here. Cross-file: this file implements the SATS
** entries `parse_expr` and `parse_suite`, and CALLS `parse_type`/`parse_pattern`
** (staexp) and `parse_decl` (decl00).
**
** ===================== the §5.6 precedence table (low → high) =====================
**   1  or                         left   (short-circuit; tag PyBor)
**   2  and                        left   (short-circuit; tag PyBand)
**   3  not e                      prefix (short-circuit; tag PyUnot)
**   4  == != < <= > >=            non-assoc (no chaining in v1)
**   5  + -                        left
**   6  * / % //                   left
**   7  unary - +                  prefix
**   8  **                         right
**   9  call () index [] field .   postfix
** Implemented with binding-power: each binary level has a left/right power; a level-4
** comparison is parsed non-associatively (at most one). `**` is right-assoc (rbp <
** lbp). Unary -/+ and `not` are prefix. Postfix call/index/field bind tightest.
**
** SUITES (§5.3): parse_suite is entered positioned right AFTER the ':'/'=>' opener.
**   inline:  simple_stmt NEWLINE                     → a one-element suite
**   block :  NEWLINE INDENT stmt { stmt } DEDENT      → the block's stmts
**
** Error recovery: malformed exprs/stmts yield PyEerror/PySerror at the offending span;
** the statement loop resyncs at NEWLINE/DEDENT. NEVER throws.
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
// ---- literal recognition (expression-local copy; keyed to PyElit) ----------
//
fun
elit_of_node(loc: loctn, nod: ptnode): @(bool, pylit) =
(
case+ nod of
| PT_INT(s)   => @(true, PyLint(loc, s))
| PT_FLOAT(s) => @(true, PyLflt(loc, s))
| PT_STRING(s)=> @(true, PyLstr(loc, s))
| PT_CHAR(s)  => @(true, PyLchr(loc, s))
| PT_TRUE()   => @(true, PyLbool(loc, true))
| PT_FALSE()  => @(true, PyLbool(loc, false))
| _ => @(false, PyLbool(loc, false))
)
//
// ---- binary-operator classification: node → @(is_binop, tag, left-bp, right-bp) ----
//
// left-bp = the level's binding power; right-bp encodes associativity:
//   left-assoc  : rbp = lbp + 1   (so equal-level ops group left)
//   right-assoc : rbp = lbp       (so equal-level ops group right — `**`)
//   non-assoc   : handled at the call site (parse at most one comparison)
//
fun
binop_of_node(nod: ptnode): @(bool, pybop, sint, sint) =
(
case+ nod of
| PT_KW_OR()  => @(true, PyBor(),  1, 2)    // lvl 1 left
| PT_KW_AND() => @(true, PyBand(), 2, 3)    // lvl 2 left
| PT_EQEQ()   => @(true, PyBeq(),  4, 5)    // lvl 4 non-assoc (call site caps it)
| PT_NEQ()    => @(true, PyBne(),  4, 5)
| PT_LT()     => @(true, PyBlt(),  4, 5)
| PT_LTE()    => @(true, PyBle(),  4, 5)
| PT_GT()     => @(true, PyBgt(),  4, 5)
| PT_GTE()    => @(true, PyBge(),  4, 5)
| PT_PLUS()   => @(true, PyBadd(), 5, 6)    // lvl 5 left
| PT_MINUS()  => @(true, PyBsub(), 5, 6)
| PT_STAR()   => @(true, PyBmul(), 6, 7)    // lvl 6 left
| PT_SLASH()  => @(true, PyBdiv(), 6, 7)
| PT_PERCENT()=> @(true, PyBmod(), 6, 7)
| PT_SLASH2() => @(true, PyBfdiv(),6, 7)
| PT_STAR2()  => @(true, PyBpow(), 8, 8)    // lvl 8 right-assoc (rbp == lbp)
| _ => @(false, PyBadd(), 0, 0)
)
//
// is a comparison operator (level 4, non-assoc)?
fun
is_cmp_node(nod: ptnode): bool =
(
case+ nod of
| PT_EQEQ() => true | PT_NEQ() => true
| PT_LT() => true | PT_LTE() => true | PT_GT() => true | PT_GTE() => true
| _ => false
)
//
(* ****** ****** *)
//
// =====================================================================
//  The mutually-recursive EXPRESSION + STATEMENT/SUITE group.
// =====================================================================
//
// p_expr: the full expression entry — lambda / if-expr / match-expr / Pratt(or_expr).
// A lambda is detected by lookahead (LIDENT '=>' or '(' params ')' '=>'); see
// p_try_lambda. The minimum binding power for the top Pratt call is 1 (any binary op).
//
fun
p_expr(st: pstate): @(pyexp, pstate) = let
  val nod = ps_peek(st)
in
  case+ nod of
  | PT_KW_IF()    => p_if_expr(st)
  | PT_KW_MATCH() => p_match_expr(st)
  | _ =>
    // try a lambda; if not a lambda, fall through to the Pratt parser.
    let val @(islam, e, st1) = p_try_lambda(st) in
      if islam then @(e, st1) else p_pratt(st, 1)
    end
end
//
// ---- lambda detection + parse ----------------------------------------------
//
// Detect `LIDENT '=>' …` or `'(' [params] ')' '=>' …`. Returns @(is_lambda, exp, st').
// When not a lambda, returns @(false, dummy, st) WITHOUT consuming anything.
//
and
p_try_lambda(st: pstate): @(bool, pyexp, pstate) = let
  val nod = ps_peek(st)
  val loc = ps_peek_loctn(st)
in
  case+ nod of
  | PT_LIDENT(nm) =>
    // single bare param iff '=>' immediately follows.
    ( case+ ps_peek2(st) of
      | PT_FATARROW() =>
        let
          val prm = PyParam(loc, nm, PyTypNone())
          val st1 = ps_advance(ps_advance(st))   // past LIDENT and '=>'
          val @(body, st2) = p_lam_body(st1)
        in
          @(true, PyElam(loc, list_cons(prm, list_nil()), body), st2)
        end
      | _ => @(false, PyEwild(loc), st) )
  | PT_LPAREN() =>
    // '(' params ')' '=>' …  — must scan-ahead to the matching ')' then check '=>'.
    // We optimistically parse the param list; if the token after ')' is '=>', it is a
    // lambda; otherwise we MUST NOT have consumed — but since we already parsed, we
    // re-derive: only commit when '=>' follows. To stay pure we peek via a structural
    // pre-check using a balanced-paren skip.
    ( if paren_then_fatarrow(st) then
        let
          val @(prms, st1) = p_params(ps_advance(st))   // after '('
          val locR = ps_peek_loctn(st1)
          val st2 = expect_rparen_e(st1, locR)
          // now expect '=>'
          val st3 =
            ( case+ ps_peek(st2) of
              | PT_FATARROW() => ps_advance(st2)
              | _ => ps_diag(st2, ps_peek_loctn(st2), "expected '=>'") )
          val @(body, st4) = p_lam_body(st3)
        in
          @(true, PyElam(loc_span(loc, locR), prms, body), st4)
        end
      else @(false, PyEwild(loc), st) )
  | _ => @(false, PyEwild(loc), st)
end
//
// structural lookahead: starting at '(', skip a balanced parenthesized group and
// report whether the token immediately after the matching ')' is '=>'. Pure (peeks a
// copy of the stream; does not mutate st). Used only to disambiguate lambda vs group.
and
paren_then_fatarrow(st: pstate): bool = let
  fun skip(st: pstate, depth: sint): pstate =
    ( case+ ps_peek(st) of
      | PT_EOF() => st
      | PT_LPAREN() => skip(ps_advance(st), depth + 1)
      | PT_RPAREN() =>
        if depth <= 1 then ps_advance(st) else skip(ps_advance(st), depth - 1)
      | _ => skip(ps_advance(st), depth) )
  val st1 = skip(st, 0)
in
  case+ ps_peek(st1) of PT_FATARROW() => true | _ => false
end
//
// a lambda body: inline expr (→ a one-stmt suite of PySexpr) OR a block suite.
and
p_lam_body(st: pstate): @(pystmtlst, pstate) =
(
case+ ps_peek(st) of
| PT_NEWLINE() => p_block_suite(st)   // block-bodied lambda
| _ =>
  let
    val @(e, st1) = p_expr(st)
    val loc = pyexp_loctn(e)
  in
    @(list_cons(PySexpr(loc, e), list_nil()), st1)
  end
)
//
// params: param { ',' param } until ')'. param ::= LIDENT [ ':' type ].
and
p_params(st: pstate): @(list(pyparam), pstate) =
(
case+ ps_peek(st) of
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
      let val @(ps0, st3) = p_params(ps_advance(st2)) in
        @(list_cons(prm, ps0), st3) end
    | _ => @(list_cons(prm, list_nil()), st2)
  end
| _ =>
  let val loc = ps_peek_loctn(st)
      val st1 = ps_diag(st, loc, "expected a parameter name") in
    @(list_nil(), st1) end
)
//
(* ****** ****** *)
//
// ---- Pratt core: p_pratt(st, minbp) -----------------------------------------
//
// parse a unary/postfix primary, then fold binary operators with binding power
// >= minbp. Comparisons (lvl 4) are non-associative: after consuming one comparison
// we DO NOT consume another at the same level.
//
and
p_pratt(st: pstate, minbp: sint): @(pyexp, pstate) = let
  val @(lhs, st1) = p_unary(st)
in
  p_pratt_loop(lhs, st1, minbp, false)
end
//
and
p_pratt_loop
(lhs: pyexp, st: pstate, minbp: sint, did_cmp: bool): @(pyexp, pstate) = let
  val nod = ps_peek(st)
  val oploc = ps_peek_loctn(st)
  val @(isbin, tag, lbp, rbp) = binop_of_node(nod)
in
  if ~isbin then @(lhs, st)
  else if lbp < minbp then @(lhs, st)
  else if (if is_cmp_node(nod) then did_cmp else false) then
    // a second comparison at the same level — non-assoc: stop + diagnose.
    let val st1 = ps_diag(st, oploc, "comparison operators do not chain (v1)") in
      @(lhs, st1) end
  else
    let
      val @(rhs, st1) = p_pratt(ps_advance(st), rbp)
      val span = loc_span(pyexp_loctn(lhs), pyexp_loctn(rhs))
      val node = PyEbin(span, tag, lhs, rhs)
      val now_cmp = is_cmp_node(nod)
    in
      p_pratt_loop(node, st1, minbp, now_cmp)
    end
end
//
// unary: ('-'|'+') unary | 'not' unary | pow. (pow handled in p_pratt via PyBpow.)
and
p_unary(st: pstate): @(pyexp, pstate) = let
  val nod = ps_peek(st)
  val loc = ps_peek_loctn(st)
in
  case+ nod of
  | PT_MINUS() =>
    let val @(e, st1) = p_unary(ps_advance(st)) in
      @(PyEuna(loc_span(loc, pyexp_loctn(e)), PyUneg(), e), st1) end
  | PT_PLUS() =>
    let val @(e, st1) = p_unary(ps_advance(st)) in
      @(PyEuna(loc_span(loc, pyexp_loctn(e)), PyUpos(), e), st1) end
  | PT_KW_NOT() =>
    let val @(e, st1) = p_unary(ps_advance(st)) in
      @(PyEuna(loc_span(loc, pyexp_loctn(e)), PyUnot(), e), st1) end
  | _ => p_postfix(st)
end
//
// postfix: atom { call | index | field }. call = '(' [args] ')'; index = '[' e ']';
// field = '.' LIDENT. Left-assoc chain.
and
p_postfix(st: pstate): @(pyexp, pstate) = let
  val @(a0, st1) = p_atom(st)
in
  p_postfix_loop(a0, st1)
end
//
and
p_postfix_loop(e0: pyexp, st: pstate): @(pyexp, pstate) = let
  val nod = ps_peek(st)
  val loc0 = pyexp_loctn(e0)
in
  case+ nod of
  | PT_LPAREN() =>
    let
      val @(args, st1) = p_arg_seq(ps_advance(st))
      val locR = ps_peek_loctn(st1)
      val st2 = expect_rparen_e(st1, locR)
      val e1 = PyEapp(loc_span(loc0, locR), e0, args)
    in
      p_postfix_loop(e1, st2)
    end
  | PT_LBRACK() =>
    let
      val @(ix, st1) = p_expr(ps_advance(st))
      val locR = ps_peek_loctn(st1)
      val st2 = expect_rbrack_e(st1, locR)
      val e1 = PyEindex(loc_span(loc0, locR), e0, ix)
    in
      p_postfix_loop(e1, st2)
    end
  | PT_DOT() =>
    let val st1 = ps_advance(st) in
      case+ ps_peek(st1) of
      | PT_LIDENT(nm) =>
        let
          val locn = ps_peek_loctn(st1)
          val e1 = PyEfield(loc_span(loc0, locn), e0, nm)
        in
          p_postfix_loop(e1, ps_advance(st1))
        end
      | _ =>
        let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected a field name after '.'") in
          @(e0, st2) end
    end
  | _ => @(e0, st)
end
//
// args: expr { ',' expr } until ')'.
and
p_arg_seq(st: pstate): @(pyexplst, pstate) =
(
case+ ps_peek(st) of
| PT_RPAREN() => @(list_nil(), st)
| PT_EOF() => @(list_nil(), st)
| _ =>
  let val @(e, st1) = p_expr(st) in
    case+ ps_peek(st1) of
    | PT_COMMA() =>
      let val @(es, st2) = p_arg_seq(ps_advance(st1)) in
        @(list_cons(e, es), st2) end
    | _ => @(list_cons(e, list_nil()), st1)
  end
)
//
// atom: literal | LIDENT | UIDENT | '_' | '(' ... ')' | '[' ... ']' | record.
and
p_atom(st: pstate): @(pyexp, pstate) = let
  val loc = ps_peek_loctn(st)
  val nod = ps_peek(st)
in
  case+ nod of
  | PT_LIDENT(s) => @(PyEvar(loc, s), ps_advance(st))
  | PT_UIDENT(s) => @(PyEcon(loc, s), ps_advance(st))
  | PT_USCORE()  => @(PyEwild(loc), ps_advance(st))
  | PT_LPAREN()  => p_paren_expr(ps_advance(st), loc)
  | PT_LBRACK()  => p_list_expr(ps_advance(st), loc)
  | PT_LBRACE()  => p_record_expr(ps_advance(st), loc)
  | _ =>
    let val @(islit, lit) = elit_of_node(loc, nod) in
      if islit then @(PyElit(loc, lit), ps_advance(st))
      else
        let val st1 = ps_diag(st, loc, "expected an expression") in
          @(PyEerror(loc, "expected an expression"), st1) end
    end
end
//
// after '(' : '()' unit | '(e)' group | '(e, e, ...)' tuple.
and
p_paren_expr(st: pstate, locL: loctn): @(pyexp, pstate) = let
  val @(es, st1) = p_arg_seq(st)
  val locR = ps_peek_loctn(st1)
  val st2 = expect_rparen_e(st1, locR)
in
  case+ es of
  | list_cons(e, list_nil()) => @(e, st2)            // single ⇒ group (unwrap)
  | _ => @(PyEtup(loc_span(locL, locR), es), st2)    // 0 or 2+ ⇒ tuple (0 = unit)
end
//
// after '[' : list literal.
and
p_list_expr(st: pstate, locL: loctn): @(pyexp, pstate) = let
  val @(es, st1) = p_list_seq(st)
  val locR = ps_peek_loctn(st1)
  val st2 = expect_rbrack_e(st1, locR)
in
  @(PyElist(loc_span(locL, locR), es), st2)
end
//
and
p_list_seq(st: pstate): @(pyexplst, pstate) =
(
case+ ps_peek(st) of
| PT_RBRACK() => @(list_nil(), st)
| PT_EOF() => @(list_nil(), st)
| _ =>
  let val @(e, st1) = p_expr(st) in
    case+ ps_peek(st1) of
    | PT_COMMA() =>
      let val @(es, st2) = p_list_seq(ps_advance(st1)) in
        @(list_cons(e, es), st2) end
    | _ => @(list_cons(e, list_nil()), st1)
  end
)
//
// after '{' : record literal `{ f = e, ... }` — value fields use '='.
and
p_record_expr(st: pstate, locL: loctn): @(pyexp, pstate) = let
  val @(fs, st1) = p_efields(st)
  val locR = ps_peek_loctn(st1)
  val st2 = expect_rbrace_e(st1, locR)
in
  @(PyErec(loc_span(locL, locR), fs), st2)
end
//
and
p_efields(st: pstate): @(list(pyefield), pstate) =
(
case+ ps_peek(st) of
| PT_RBRACE() => @(list_nil(), st)
| PT_EOF() => @(list_nil(), st)
| PT_LIDENT(nm) =>
  let
    val locf = ps_peek_loctn(st)
    val st1 = ps_advance(st)
    val st2 =
      ( case+ ps_peek(st1) of
        | PT_EQ() => ps_advance(st1)
        | _ => ps_diag(st1, ps_peek_loctn(st1), "expected '=' in record field") )
    val @(e, st3) = p_expr(st2)
    val fld = PyEField(locf, nm, e)
  in
    case+ ps_peek(st3) of
    | PT_COMMA() =>
      let val @(fs, st4) = p_efields(ps_advance(st3)) in
        @(list_cons(fld, fs), st4) end
    | _ => @(list_cons(fld, list_nil()), st3)
  end
| _ =>
  let val loc = ps_peek_loctn(st)
      val st1 = ps_diag(st, loc, "expected a record field name") in
    @(list_nil(), st1) end
)
//
(* ****** ****** *)
//
// ---- if-expression / match-expression --------------------------------------
//
// if_expr ::= 'if' expr ':' branch { 'elif' expr ':' branch } 'else' ':' branch
// The guarded arms (if + elifs) become a pyguard list; the mandatory else is a pyexp
// (we read the else branch as a suite, then take its tail expr — but to keep the
// EXPRESSION form faithful we represent the else branch as a single pyexp; an inline
// `else: e` is exactly one expr. A block else collapses to a block-as-expr is OUT OF
// SCOPE for v1, so we read the else as a single inline expr).
//
and
p_if_expr(st: pstate): @(pyexp, pstate) = let
  val loc = ps_peek_loctn(st)            // the 'if'
  val st1 = ps_advance(st)               // past 'if'
  val @(cond, st2) = p_expr(st1)
  val st3 = expect_colon_e(st2)
  val @(body, st4) = parse_suite(st3)
  val g0 = PyGuard(loc, cond, body)
  // collect elifs
  val @(gs, st5) = p_elifs(st4)
  val guards = list_cons(g0, gs)
  // mandatory else (if-EXPR requires it; if missing, diagnose + use an error expr).
in
  case+ ps_peek(st5) of
  | PT_KW_ELSE() =>
    let
      val st6 = ps_advance(st5)
      val st7 = expect_colon_e(st6)
      val @(els, st8) = p_expr(st7)      // else branch as a single expr (inline)
    in
      @(PyEif(loc_span(loc, pyexp_loctn(els)), guards, els), st8)
    end
  | _ =>
    let
      val loce = ps_peek_loctn(st5)
      val st6 = ps_diag(st5, loce, "if-expression requires an 'else' branch")
    in
      @(PyEif(loc, guards, PyEerror(loce, "missing else")), st6)
    end
end
//
// collect zero+ `elif expr ':' suite` arms.
and
p_elifs(st: pstate): @(list(pyguard), pstate) =
(
case+ ps_peek(st) of
| PT_KW_ELIF() =>
  let
    val loc = ps_peek_loctn(st)
    val st1 = ps_advance(st)
    val @(cond, st2) = p_expr(st1)
    val st3 = expect_colon_e(st2)
    val @(body, st4) = parse_suite(st3)
    val g = PyGuard(loc, cond, body)
    val @(gs, st5) = p_elifs(st4)
  in
    @(list_cons(g, gs), st5)
  end
| _ => @(list_nil(), st)
)
//
// match_expr ::= 'match' expr ':' NEWLINE INDENT case_arm { case_arm } DEDENT
and
p_match_expr(st: pstate): @(pyexp, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)               // past 'match'
  val @(scrut, st2) = p_expr(st1)
  val st3 = expect_colon_e(st2)
  // expect NEWLINE INDENT then case arms until DEDENT.
  val st4 = skip_one_newline(st3)
  val st5 = skip_one_indent(st4)
  val @(arms, st6) = p_case_arms(st5)
  val st7 = skip_one_dedent(st6)
in
  @(PyEmatch(loc, scrut, arms), st7)
end
//
and
p_case_arms(st: pstate): @(list(pyarm), pstate) =
(
case+ ps_peek(st) of
| PT_KW_CASE() =>
  let
    val loc = ps_peek_loctn(st)
    val st1 = ps_advance(st)             // past 'case'
    val @(p, st2) = parse_pattern(st1)
    // optional `if guard`
    val @(gopt, st3) =
      ( case+ ps_peek(st2) of
        | PT_KW_IF() =>
          let val @(g, st3) = p_expr(ps_advance(st2)) in @(PyExpSome(g), st3) end
        | _ => @(PyExpNone(), st2) )
    val st4 = expect_colon_e(st3)
    val @(body, st5) = parse_suite(st4)
    val arm = PyArm(loc, p, gopt, body)
    val @(arms, st6) = p_case_arms(st5)
  in
    @(list_cons(arm, arms), st6)
  end
| _ => @(list_nil(), st)
)
//
(* ****** ****** *)
//
// ---- expect helpers (expression file copies) -------------------------------
//
and
expect_colon_e(st: pstate): pstate =
( case+ ps_peek(st) of
  | PT_COLON() => ps_advance(st)
  | _ => ps_diag(st, ps_peek_loctn(st), "expected ':'") )
//
and
expect_rparen_e(st: pstate, loc: loctn): pstate =
( case+ ps_peek(st) of
  | PT_RPAREN() => ps_advance(st)
  | _ => ps_diag(st, loc, "expected ')'") )
//
and
expect_rbrack_e(st: pstate, loc: loctn): pstate =
( case+ ps_peek(st) of
  | PT_RBRACK() => ps_advance(st)
  | _ => ps_diag(st, loc, "expected ']'") )
//
and
expect_rbrace_e(st: pstate, loc: loctn): pstate =
( case+ ps_peek(st) of
  | PT_RBRACE() => ps_advance(st)
  | _ => ps_diag(st, loc, "expected '}'") )
//
// skip exactly one layout token of a given kind if present (else no-op).
and
skip_one_newline(st: pstate): pstate =
( case+ ps_peek(st) of PT_NEWLINE() => ps_advance(st) | _ => st )
and
skip_one_indent(st: pstate): pstate =
( case+ ps_peek(st) of PT_INDENT() => ps_advance(st) | _ => st )
and
skip_one_dedent(st: pstate): pstate =
( case+ ps_peek(st) of PT_DEDENT() => ps_advance(st) | _ => st )
//
(* ****** ****** *)
//
// =====================================================================
//  SUITES + STATEMENTS
// =====================================================================
//
// parse_suite (SATS entry): entered positioned right AFTER the ':'/'=>' opener.
//   if next is NEWLINE then a block: NEWLINE INDENT stmt { stmt } DEDENT.
//   otherwise an inline simple_stmt terminated by NEWLINE → a one-element suite.
//
and
p_suite(st: pstate): @(pystmtlst, pstate) =
( case+ ps_peek(st) of
  | PT_NEWLINE() => p_block_suite(st)
  | _ =>
    let
      val @(s, st1) = p_simple_stmt(st)
      val st2 = expect_newline(st1)
      val ss = list_cons(s, list_nil()): pystmtlst
    in @(ss, st2) end )
//
// a block suite: NEWLINE INDENT stmt { stmt } DEDENT (consume all three layout marks).
and
p_block_suite(st: pstate): @(pystmtlst, pstate) = let
  val st1 = skip_one_newline(st)
in
  case+ ps_peek(st1) of
  | PT_INDENT() =>
    let
      val st2 = ps_advance(st1)              // past INDENT
      val @(ss, st3) = p_stmt_list(st2)
      val st4 = skip_one_dedent(st3)         // past DEDENT
    in
      @(ss, st4)
    end
  | _ =>
    // a header with no indented body — recover with an empty suite + diagnostic.
    let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected an indented block") in
      @(list_nil(), st2) end
end
//
// stmt list until DEDENT/EOF. Resyncs on a statement-level error.
and
p_stmt_list(st: pstate): @(pystmtlst, pstate) =
( case+ ps_peek(st) of
  | PT_DEDENT() => @(list_nil(), st)
  | PT_EOF() => @(list_nil(), st)
  | PT_NEWLINE() => p_stmt_list(ps_advance(st))   // stray blank line inside a block
  | _ =>
    let val @(s, st1) = p_stmt(st) in
      let val @(ss, st2) = p_stmt_list(st1) in
        @(list_cons(s, ss), st2) end
    end )
//
// a full statement (block-introducing or simple). Block stmts (if/while/for/match/
// def/type) consume their own suite + trailing layout; simple stmts end at NEWLINE.
and
p_stmt(st: pstate): @(pystmt, pstate) = let
  val nod = ps_peek(st)
  val loc = ps_peek_loctn(st)
in
  case+ nod of
  | PT_KW_IF()    => p_if_stmt(st)
  | PT_KW_WHILE() => p_while_stmt(st)
  | PT_KW_FOR()   => p_for_stmt(st)
  | PT_KW_MATCH() =>
    // a match used as a statement: parse the match-EXPR, wrap as an expr-stmt.
    let val @(e, st1) = p_match_expr(st) in
      @(PySexpr(loc, e), st1) end
  | PT_KW_DEF() =>
    let val @(d, st1) = parse_decl(st) in @(PySdecl(loc, d), st1) end
  | PT_KW_TYPE() =>
    let val @(d, st1) = parse_decl(st) in @(PySdecl(loc, d), st1) end
  | PT_KW_IMPORT() =>
    let val @(d, st1) = parse_decl(st) in @(PySdecl(loc, d), st1) end
  | PT_KW_FROM() =>
    let val @(d, st1) = parse_decl(st) in @(PySdecl(loc, d), st1) end
  | _ =>
    // a simple statement terminated by NEWLINE.
    let
      val @(s, st1) = p_simple_stmt(st)
      val st2 = expect_newline(st1)
    in
      @(s, st2)
    end
end
//
// simple_stmt ::= binding | reassign | exprstmt | break | continue | return [exprs].
// (No trailing NEWLINE consumed here — the caller decides.)
and
p_simple_stmt(st: pstate): @(pystmt, pstate) = let
  val nod = ps_peek(st)
  val loc = ps_peek_loctn(st)
in
  case+ nod of
  | PT_KW_LET()      => p_let_stmt(st)
  | PT_KW_BREAK()    => @(PySbreak(loc), ps_advance(st))
  | PT_KW_CONTINUE() => @(PyScontinue(loc), ps_advance(st))
  | PT_KW_RETURN()   => p_return_stmt(st)
  | _ =>
    // an expression statement OR a reassignment (expr '=' expr). Parse an expr; if a
    // bare '=' follows, it is a reassignment with that expr as the lvalue.
    let
      val @(e, st1) = p_expr_or_tuple(st)
    in
      case+ ps_peek(st1) of
      | PT_EQ() =>
        let
          val st2 = ps_advance(st1)
          val @(rhs, st3) = p_expr_or_tuple(st2)
        in
          @(PySreassign(loc_span(pyexp_loctn(e), pyexp_loctn(rhs)), e, rhs), st3)
        end
      | _ => @(PySexpr(pyexp_loctn(e), e), st1)
    end
end
//
// p_expr_or_tuple: a bare comma list `a, b` parses to a PyEtup (§5.4 exprs); a single
// expr stays itself. Used in return-values and reassignment/expr-stmt RHS positions.
and
p_expr_or_tuple(st: pstate): @(pyexp, pstate) = let
  val @(e0, st1) = p_expr(st)
in
  case+ ps_peek(st1) of
  | PT_COMMA() =>
    let
      val @(es, st2) = p_comma_rest(ps_advance(st1))
      val all = list_cons(e0, es)
      val locend =
        ( case+ es of
          | list_nil() => pyexp_loctn(e0)
          | _ => last_loc(all, pyexp_loctn(e0)) )
    in
      @(PyEtup(loc_span(pyexp_loctn(e0), locend), all), st2)
    end
  | _ => @(e0, st1)
end
//
and
p_comma_rest(st: pstate): @(pyexplst, pstate) = let
  val @(e, st1) = p_expr(st)
in
  case+ ps_peek(st1) of
  | PT_COMMA() =>
    let val @(es, st2) = p_comma_rest(ps_advance(st1)) in
      @(list_cons(e, es), st2) end
  | _ => @(list_cons(e, list_nil()), st1)
end
//
// last loctn in an expr list (for span end of a bare tuple).
and
last_loc(es: pyexplst, acc: loctn): loctn =
( case+ es of
  | list_nil() => acc
  | list_cons(e, rest) => last_loc(rest, pyexp_loctn(e)) )
//
// let [mut] pattern [: type] = expr
and
p_let_stmt(st: pstate): @(pystmt, pstate) = let
  val loc = ps_peek_loctn(st)            // the 'let'
  val st1 = ps_advance(st)               // past 'let'
  val @(mut, st2) =
    ( case+ ps_peek(st1) of
      | PT_KW_MUT() => @(true, ps_advance(st1))
      | _ => @(false, st1) )
  val @(p, st3) = parse_pattern(st2)
  val @(topt, st4) =
    ( case+ ps_peek(st3) of
      | PT_COLON() =>
        let val @(t, st4) = parse_type(ps_advance(st3)) in @(PyTypSome(t), st4) end
      | _ => @(PyTypNone(), st3) )
  val st5 =
    ( case+ ps_peek(st4) of
      | PT_EQ() => ps_advance(st4)
      | _ => ps_diag(st4, ps_peek_loctn(st4), "expected '=' in let binding") )
  val @(rhs, st6) = p_expr_or_tuple(st5)
in
  @(PyDlet(loc_span(loc, pyexp_loctn(rhs)), mut, p, topt, rhs), st6)
end
//
// return [exprs]
and
p_return_stmt(st: pstate): @(pystmt, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)               // past 'return'
in
  case+ ps_peek(st1) of
  | PT_NEWLINE() => @(PySreturn(loc, PyExpNone()), st1)
  | PT_DEDENT() => @(PySreturn(loc, PyExpNone()), st1)
  | PT_EOF() => @(PySreturn(loc, PyExpNone()), st1)
  | _ =>
    let val @(e, st2) = p_expr_or_tuple(st1) in
      @(PySreturn(loc_span(loc, pyexp_loctn(e)), PyExpSome(e)), st2) end
end
//
// if-statement: like if-expr but else is OPTIONAL and branches are suites.
and
p_if_stmt(st: pstate): @(pystmt, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)
  val @(cond, st2) = p_expr(st1)
  val st3 = expect_colon_e(st2)
  val @(body, st4) = parse_suite(st3)
  val g0 = PyGuard(loc, cond, body)
  val @(gs, st5) = p_elifs(st4)
  val guards = list_cons(g0, gs)
  val @(els, st6) =
    ( case+ ps_peek(st5) of
      | PT_KW_ELSE() =>
        let
          val st6 = ps_advance(st5)
          val st7 = expect_colon_e(st6)
          val @(eb, st8) = parse_suite(st7)
        in @(PyElseSome(eb), st8) end
      | _ => @(PyElseNone(), st5) )
in
  @(PySif(loc, guards, els), st6)
end
//
// while cond: <suite> [else: <suite>]
and
p_while_stmt(st: pstate): @(pystmt, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)
  val @(cond, st2) = p_expr(st1)
  val st3 = expect_colon_e(st2)
  val @(body, st4) = parse_suite(st3)
  val @(els, st5) = p_loop_else(st4)
in
  @(PySwhile(loc, cond, body, els), st5)
end
//
// for pattern in expr: <suite> [else: <suite>]
and
p_for_stmt(st: pstate): @(pystmt, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)
  val @(p, st2) = parse_pattern(st1)
  val st3 =
    ( case+ ps_peek(st2) of
      | PT_KW_IN() => ps_advance(st2)
      | _ => ps_diag(st2, ps_peek_loctn(st2), "expected 'in' in for-loop") )
  val @(it, st4) = p_expr(st3)
  val st5 = expect_colon_e(st4)
  val @(body, st6) = parse_suite(st5)
  val @(els, st7) = p_loop_else(st6)
in
  @(PySfor(loc, p, it, body, els), st7)
end
//
// an optional loop `else:` suite.
and
p_loop_else(st: pstate): @(pystmtlstopt, pstate) =
( case+ ps_peek(st) of
  | PT_KW_ELSE() =>
    let
      val st1 = ps_advance(st)
      val st2 = expect_colon_e(st1)
      val @(eb, st3) = parse_suite(st2)
    in @(PyElseSome(eb), st3) end
  | _ => @(PyElseNone(), st) )
//
// expect a NEWLINE terminator for a simple statement. Consume a real NEWLINE; a
// DEDENT/EOF also ends the line (left for the loop). A block-bodied lambda as the RHS
// closes its own line via DEDENT, so the statement may already be terminated with NO
// NEWLINE and the next token is a fresh statement-starter — that is NOT an error (the
// layout guarantees boundaries). We therefore pass through silently on any other token
// rather than emit a spurious diagnostic.
and
expect_newline(st: pstate): pstate =
( case+ ps_peek(st) of
  | PT_NEWLINE() => ps_advance(st)
  | _ => st )
//
(* ****** ****** *)
//
// ---- the public SATS entries (thin wrappers over the recursion group) -------
//
#implfun parse_expr(st) = p_expr(st)
#implfun parse_suite(st) = p_suite(st)
#implfun parse_stmt(st) = p_stmt(st)
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyparsing_dynexp.dats]
*)
