(* ****** ****** *)
(*
** M2 — Python-surface frontend: TYPE + PATTERN parser (DATS).
**
** Recursive-descent over the §5.5 grammar:
**
**   type      ::= type_arrow
**   type_arrow::= type_app { '->' type_app }              (function type, right-assoc)
**   type_app  ::= type_atom { '[' type { ',' type } ']' } (application List[Int])
**   type_atom ::= UIDENT | LIDENT | INT
**               | '(' type { ',' type } ')'               (tuple / paren)
**               | '{' LIDENT ':' type { ',' ... } '}'     (record type — fields use ':')
**
**   pattern   ::= pat_app [ 'as' LIDENT ]
**   pat_app   ::= UIDENT [ '(' pat { ',' pat } ')' ]      (constructor app / nullary)
**               | LIDENT | '_' | literal
**               | '(' pat { ',' pat } ')'                 (tuple)
**               | '{' LIDENT '=' pat { ',' ... } '}'      (record pattern — fields use '=')
**
** Mirrors the lowering split (types/patterns ≈ the "static"-ish surface). These two
** parsers do NOT call the expression parser, so they live together here, separate from
** dynexp. Cross-file public entries: `parse_type`, `parse_pattern` (declared in SATS),
** implemented as thin wrappers over the internal recursion groups `p_type`/`p_pat`.
**
** STRUCTURE NOTE (ATS3 dialect): the internal mutually-recursive workers are plain
** `fun ... and ...` groups (named p_type/p_pat etc); the SATS-declared
** `parse_type`/`parse_pattern` are
** separate `#implfun` wrappers that delegate to them. (M1 used the same shape: plain
** `fun` recursion + a thin `#implfun` entry — mixing `#implfun` INTO an `and`-group is
** avoided.)
**
** Error recovery: a malformed type/pattern yields a `PyTerror`/`PyPerror` node at the
** offending span; the caller resynchronizes. NEVER throws.
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
// ---- literal recognition: build a pylit from a literal token node + loctn.
// returns @(is_literal, pylit). When is_literal is false the pylit is a dummy.
//
fun
lit_of_node(loc: loctn, nod: ptnode): @(bool, pylit) =
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
(* ****** ****** *)
//
// ---- small expect-helpers (emit a diagnostic + DON'T advance if absent; advance if
// present). Plain standalone funs so both the type and pattern groups can call them.
//
fun
expect_colon(st: pstate): pstate =
(
case+ ps_peek(st) of
| PT_COLON() => ps_advance(st)
| _ => ps_diag(st, ps_peek_loctn(st), "expected ':'")
)
//
fun
expect_eq(st: pstate): pstate =
(
case+ ps_peek(st) of
| PT_EQ() => ps_advance(st)
| _ => ps_diag(st, ps_peek_loctn(st), "expected '='")
)
//
fun
expect_rparen(st: pstate, loc: loctn): pstate =
(
case+ ps_peek(st) of
| PT_RPAREN() => ps_advance(st)
| _ => ps_diag(st, loc, "expected ')'")
)
//
fun
expect_rbrack(st: pstate, loc: loctn): pstate =
(
case+ ps_peek(st) of
| PT_RBRACK() => ps_advance(st)
| _ => ps_diag(st, loc, "expected ']'")
)
//
fun
expect_rbrace(st: pstate, loc: loctn): pstate =
(
case+ ps_peek(st) of
| PT_RBRACE() => ps_advance(st)
| _ => ps_diag(st, loc, "expected '}'")
)
//
(* ****** ****** *)
//
// ==================================================================
//  TYPE PARSER (internal recursion group: p_type / p_type_*)
// ==================================================================
//
// p_type: type_app { '->' type_app } — function type, right-assoc.
//
fun
p_type(st: pstate): @(pytyp, pstate) = let
  val @(t0, st1) = p_type_app(st)
in
  case+ ps_peek(st1) of
  | PT_ARROW() =>
    let
      val @(rhs, st2) = p_type(ps_advance(st1))    // right-assoc
      val span = loc_span(pytyp_loctn(t0), pytyp_loctn(rhs))
    in
      @(PyTfun(span, list_cons(t0, list_nil()), rhs), st2)
    end
  | _ => @(t0, st1)
end
//
// type_app: atom { '[' type {, type} ']' } — left-assoc application of [..] args.
and
p_type_app(st: pstate): @(pytyp, pstate) = let
  val @(t0, st1) = p_type_atom(st)
in
  p_type_app_loop(t0, st1)
end
//
and
p_type_app_loop(t0: pytyp, st: pstate): @(pytyp, pstate) =
(
case+ ps_peek(st) of
| PT_LBRACK() =>
  let
    val locL = pytyp_loctn(t0)
    val @(args, st1) = p_type_args(ps_advance(st))
    val locR = ps_peek_loctn(st1)
    val st2 = expect_rbrack(st1, locR)
    val t1 =
      ( case+ t0 of
        | PyTcon(_, nm, prev) => PyTcon(loc_span(locL, locR), nm, list_append(prev, args))
        | _ => PyTcon(loc_span(locL, locR), "?app", args) )
  in
    p_type_app_loop(t1, st2)
  end
| _ => @(t0, st)
)
//
and
p_type_args(st: pstate): @(pytyplst, pstate) =
(
case+ ps_peek(st) of
| PT_RBRACK() => @(list_nil(), st)
| PT_EOF() => @(list_nil(), st)
| _ =>
  let val @(t, st1) = p_type(st) in
    case+ ps_peek(st1) of
    | PT_COMMA() =>
      let val @(ts, st2) = p_type_args(ps_advance(st1)) in
        @(list_cons(t, ts), st2) end
    | _ => @(list_cons(t, list_nil()), st1)
  end
)
//
// type_atom: UIDENT | LIDENT | INT | '(' ... ')' | '{' ... '}'
and
p_type_atom(st: pstate): @(pytyp, pstate) = let
  val loc = ps_peek_loctn(st)
  val nod = ps_peek(st)
in
  case+ nod of
  | PT_UIDENT(s) => @(PyTcon(loc, s, list_nil()), ps_advance(st))
  | PT_LIDENT(s) => @(PyTvar(loc, s), ps_advance(st))
  | PT_INT(s)    => @(PyTidx(loc, s), ps_advance(st))
  | PT_LPAREN()  => p_type_paren(ps_advance(st), loc)
  | PT_LBRACE()  => p_type_record(ps_advance(st), loc)
  | _ =>
    let val st1 = ps_diag(st, loc, "expected a type") in
      @(PyTerror(loc, "expected a type"), st1) end
end
//
// after '(' : a tuple type or a parenthesized type.
and
p_type_paren(st: pstate, locL: loctn): @(pytyp, pstate) = let
  val @(ts, st1) = p_type_seq(st)
  val locR = ps_peek_loctn(st1)
  val st2 = expect_rparen(st1, locR)
  val span = loc_span(locL, locR)
in
  case+ ts of
  | list_cons(t, list_nil()) => @(t, st2)   // single ⇒ unwrap (paren group)
  | _ => @(PyTtup(span, ts), st2)
end
//
// parse types separated by ',' until ')' (does not consume the ')').
and
p_type_seq(st: pstate): @(pytyplst, pstate) =
(
case+ ps_peek(st) of
| PT_RPAREN() => @(list_nil(), st)
| PT_EOF() => @(list_nil(), st)
| _ =>
  let val @(t, st1) = p_type(st) in
    case+ ps_peek(st1) of
    | PT_COMMA() =>
      let val @(ts, st2) = p_type_seq(ps_advance(st1)) in
        @(list_cons(t, ts), st2) end
    | _ => @(list_cons(t, list_nil()), st1)
  end
)
//
// after '{' : a record type `{ x: Int, y: Int }`.
and
p_type_record(st: pstate, locL: loctn): @(pytyp, pstate) = let
  val @(fs, st1) = p_tfields(st)
  val locR = ps_peek_loctn(st1)
  val st2 = expect_rbrace(st1, locR)
in
  @(PyTrec(loc_span(locL, locR), fs), st2)
end
//
and
p_tfields(st: pstate): @(list(pytfield), pstate) =
(
case+ ps_peek(st) of
| PT_RBRACE() => @(list_nil(), st)
| PT_EOF() => @(list_nil(), st)
| PT_LIDENT(nm) =>
  let
    val locf = ps_peek_loctn(st)
    val st1 = ps_advance(st)
    val st2 = expect_colon(st1)
    val @(t, st3) = p_type(st2)
    val fld = PyTField(locf, nm, t)
  in
    case+ ps_peek(st3) of
    | PT_COMMA() =>
      let val @(fs, st4) = p_tfields(ps_advance(st3)) in
        @(list_cons(fld, fs), st4) end
    | _ => @(list_cons(fld, list_nil()), st3)
  end
| _ =>
  let val loc = ps_peek_loctn(st)
      val st1 = ps_diag(st, loc, "expected a record-type field name") in
    @(list_nil(), st1) end
)
//
(* ****** ****** *)
//
// ==================================================================
//  PATTERN PARSER (internal recursion group: p_pat / p_pat_*)
// ==================================================================
//
// p_pat: pat_atom [ 'as' LIDENT ]. A trailing `:` is DELIBERATELY NOT consumed here
// (it is the block-header in `case pat:` / `for pat in e:` and the annotation in
// `let pat : T = e`, which the binding parser handles). See M2-REPORT for the choice.
//
fun
p_pat(st: pstate): @(pypat, pstate) = let
  val @(p0, st1) = p_pat_atom(st)
in
  case+ ps_peek(st1) of
  | PT_KW_AS() =>
    let val st2 = ps_advance(st1) in
      case+ ps_peek(st2) of
      | PT_LIDENT(nm) =>
        let val locn = ps_peek_loctn(st2) in
          @(PyPas(loc_span(pypat_loctn(p0), locn), p0, nm), ps_advance(st2)) end
      | _ =>
        let val st3 = ps_diag(st2, ps_peek_loctn(st2), "expected a name after 'as'") in
          @(p0, st3) end
    end
  | _ => @(p0, st1)
end
//
and
p_pat_atom(st: pstate): @(pypat, pstate) = let
  val loc = ps_peek_loctn(st)
  val nod = ps_peek(st)
in
  case+ nod of
  | PT_USCORE() => @(PyPwild(loc), ps_advance(st))
  | PT_LIDENT(s) => @(PyPvar(loc, s), ps_advance(st))
  | PT_UIDENT(s) =>
    let val st1 = ps_advance(st) in
      case+ ps_peek(st1) of
      | PT_LPAREN() =>
        let
          val @(args, st2) = p_pat_seq(ps_advance(st1))
          val locR = ps_peek_loctn(st2)
          val st3 = expect_rparen(st2, locR)
        in
          @(PyPcon(loc_span(loc, locR), s, args), st3)
        end
      | _ => @(PyPcon(loc, s, list_nil()), st1)
    end
  | PT_LPAREN() =>
    let
      val @(ps0, st1) = p_pat_seq(ps_advance(st))
      val locR = ps_peek_loctn(st1)
      val st2 = expect_rparen(st1, locR)
    in
      case+ ps0 of
      | list_cons(p, list_nil()) => @(p, st2)            // single ⇒ unwrap
      | _ => @(PyPtup(loc_span(loc, locR), ps0), st2)
    end
  | PT_LBRACE() =>
    let
      val @(fs, st1) = p_pfields(ps_advance(st))
      val locR = ps_peek_loctn(st1)
      val st2 = expect_rbrace(st1, locR)
    in
      @(PyPrec(loc_span(loc, locR), fs), st2)
    end
  | _ =>
    let val @(islit, lit) = lit_of_node(loc, nod) in
      if islit then @(PyPlit(loc, lit), ps_advance(st))
      else
        let val st1 = ps_diag(st, loc, "expected a pattern") in
          @(PyPerror(loc, "expected a pattern"), st1) end
    end
end
//
and
p_pat_seq(st: pstate): @(pypatlst, pstate) =
(
case+ ps_peek(st) of
| PT_RPAREN() => @(list_nil(), st)
| PT_EOF() => @(list_nil(), st)
| _ =>
  let val @(p, st1) = p_pat(st) in
    case+ ps_peek(st1) of
    | PT_COMMA() =>
      let val @(ps0, st2) = p_pat_seq(ps_advance(st1)) in
        @(list_cons(p, ps0), st2) end
    | _ => @(list_cons(p, list_nil()), st1)
  end
)
//
and
p_pfields(st: pstate): @(list(pypfield), pstate) =
(
case+ ps_peek(st) of
| PT_RBRACE() => @(list_nil(), st)
| PT_EOF() => @(list_nil(), st)
| PT_LIDENT(nm) =>
  let
    val locf = ps_peek_loctn(st)
    val st1 = ps_advance(st)
    val st2 = expect_eq(st1)
    val @(p, st3) = p_pat(st2)
    val fld = PyPField(locf, nm, p)
  in
    case+ ps_peek(st3) of
    | PT_COMMA() =>
      let val @(fs, st4) = p_pfields(ps_advance(st3)) in
        @(list_cons(fld, fs), st4) end
    | _ => @(list_cons(fld, list_nil()), st3)
  end
| _ =>
  let val loc = ps_peek_loctn(st)
      val st1 = ps_diag(st, loc, "expected a record-pattern field name") in
    @(list_nil(), st1) end
)
//
(* ****** ****** *)
//
// ---- the public wrappers (SATS entries) ------------------------------------
//
#implfun parse_type(st) = p_type(st)
#implfun parse_pattern(st) = p_pat(st)
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyparsing_staexp.dats]
*)
