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
// A-QUANT: HOIST the quantifier GUARD out of the binder list into a standalone pyguardopt. The
// shared `p_typarams` grammar parks a `[binders | g]` guard on the LAST binder (PyGuardSome); for
// a `forall`/`exists` type-quantifier we want it as the quantifier's OWN guard slot, with the
// binders themselves guard-free. We scan for the first (and only) PyGuardSome, strip it to
// PyGuardNone on that binder, and return it. No guard => PyGuardNone + the binders unchanged.
fun
hoist_quant_guard
(binders: list(pytyparam)): @(list(pytyparam), pyguardopt) =
(
case+ binders of
| list_nil() => @(list_nil(), PyGuardNone())
| list_cons(tp, rest) =>
  (
    case+ tp of
    | PyTyParam(loc, nm, sopt, decos, PyGuardSome(gloc, g)) =>
        // found the guard: strip it here, keep the rest as-is (p_typarams only guards the last).
        @(list_cons(PyTyParam(loc, nm, sopt, decos, PyGuardNone()), rest), PyGuardSome(gloc, g))
    | PyTyParam(_, _, _, _, PyGuardNone()) =>
        let val @(rest1, gopt) = hoist_quant_guard(rest) in
          @(list_cons(tp, rest1), gopt) end
  )
)
//
(* ****** ****** *)
//
// ==================================================================
//  TYPE PARSER (internal recursion group: p_type / p_type_*)
// ==================================================================
//
// p_type: type_app { '->' type_app } — function type, right-assoc.
// A-QUANT: a leading `forall`/`exists` opens an EXPLICIT quantified type — `forall[binders|g] T`
// / `exists[binders|g] T`. It binds the WHOLE following type (so the body may itself be an arrow
// `forall[n] (Vec[A,n]) -> SInt`), hence dispatched at the TOP of p_type (loosest level), before
// the application/arrow grammar. The binder list + optional guard reuse the def-param `p_typarams`
// grammar (`[n: SInt | g]`); the guard `p_typarams` attaches to the last binder is HOISTED into the
// PyTquant's own guard slot (binders stay guard-free).
//
fun
p_type(st: pstate): @(pytyp, pstate) =
(
case+ ps_peek(st) of
| PT_KW_FORALL() => p_type_quant(st, 0(*forall*))
| PT_KW_EXISTS() => p_type_quant(st, 1(*exists*))
| _ =>
  let
    val @(t0a, st1a) = p_type_app(st)
    // B-LINEAR: a postfix `at` relation — `A at l` (the AT-VIEW). It binds TIGHTER than `->`
    // (so `A at l -> B` is `(A at l) -> B`) but looser than application. The address `l` is a
    // type_app atom (a quantifier var of sort `addr`, an applied con, etc.).
    val @(t0a2, st1b2) =
      (case+ ps_peek(st1a) of
       | PT_KW_AT() =>
         let
           val @(addr, st1b) = p_type_app(ps_advance(st1a))
           val span = loc_span(pytyp_loctn(t0a), pytyp_loctn(addr))
         in
           @(PyTat(span, t0a, addr), st1b)
         end
       | _ => @(t0a, st1a)) : @(pytyp, pstate)
    // BOOTSTRAP-PARITY: consume an erased view-change tail after any carried type,
    // covering both `&T >> _` and `!T >> _`.
    val t0 = t0a2
    val st1 = p_type_viewchange_tail(st1b2)
  in
    case+ ps_peek(st1) of
    | PT_ARROW() =>
      let
        // ARROW-EFFECTS: after `->`, an OPTIONAL `[Tag]` arrow tag (CamelCase UIDENT —
        // `CloRef1`, `Fun0`, `CloPtr1`, ...). UNAMBIGUOUS: no type production starts with a bare
        // `[` (p_type_atom accepts only UIDENT/LIDENT/INT/`(`/`{`; existentials open with the
        // `exists` keyword; list types are `List[..]` = UIDENT-prefixed). So a `[` right after
        // `->` is always the tag. The bare `->` carries `""`.
        val st1b = ps_advance(st1)                   // consume `->`
        val @(tag, st1c) = p_arrow_tag(st1b)
        val @(rhs, st2) = p_type(st1c)               // right-assoc
        val span = loc_span(pytyp_loctn(t0), pytyp_loctn(rhs))
        val args = p_type_fun_lhs_args(t0)
      in
        @(PyTfun(span, args, rhs, tag), st2)
      end
    | _ => @(t0, st1)
  end
)
//
and
p_type_fun_lhs_args(t0: pytyp): pytyplst =
(
case+ t0 of
| PyTtup(_, ts) => ts
| PyTparen(_, t1) => list_sing(p_type_unparen(t1))
| _ => list_sing(t0)
)
//
and
p_type_unparen(t0: pytyp): pytyp =
(
case+ t0 of
| PyTparen(_, t1) => p_type_unparen(t1)
| _ => t0
)
//
and
p_type_viewchange_tail(st: pstate): pstate =
(
case+ ps_peek(st) of
| PT_GT() =>
  let val st1 = ps_advance(st) in
    case+ ps_peek(st1) of
    | PT_GT() => p_type_byref_target(ps_advance(st1))
    | _ => st
  end
| _ => st
)
//
// ARROW-EFFECTS: parse the OPTIONAL `[Tag]` after a `->`. `[` UIDENT `]` -> the UIDENT string;
// no `[` -> `""` (the bare arrow). A malformed bracket (no UIDENT / no `]`) diagnoses and yields
// `""` so the surrounding type still parses.
and
p_arrow_tag(st: pstate): @(strn, pstate) =
(
case+ ps_peek(st) of
| PT_LBRACK() =>
  let
    val locL = ps_peek_loctn(st)
    val st1 = ps_advance(st)                         // consume `[`
  in
    case+ ps_peek(st1) of
    | PT_UIDENT(s) =>
      let
        val st2 = ps_advance(st1)                    // consume the tag UIDENT
      in
        case+ ps_peek(st2) of
        | PT_RBRACK() => @(s, ps_advance(st2))       // consume `]`
        | _ =>
          let val st3 = ps_diag(st2, ps_peek_loctn(st2), "expected `]` after arrow tag") in
            @(s, st3) end
      end
    | _ =>
      let val st2 = ps_diag(st1, locL, "expected a CamelCase arrow tag after `->[`") in
        @("", st2) end
  end
| _ => @("", st)
)
//
// A-QUANT: `forall`/`exists` already consumed-as-keyword by the caller's peek; parse the binder
// bracket via the SHARED p_typarams (`[n: SInt | g]`) then the body type. HOIST the guard the
// binder grammar parked on the last binder into the quantifier's own `pyguardopt` slot.
and
p_type_quant(st: pstate, kind: int): @(pytyp, pstate) = let
  val locK = ps_peek_loctn(st)
  val st1 = ps_advance(st)                       // consume `forall`/`exists`
  val @(binders0, st2) = parse_typarams(st1)     // the SHARED `[ binders | guard ]` parser (decl00)
  val @(binders, gopt) = hoist_quant_guard(binders0)
  val @(body, st3) = p_type(st2)                 // the quantified body type (recursive)
  val span = loc_span(locK, pytyp_loctn(body))
in
  @(PyTquant(span, kind, binders, gopt, body), st3)
end
//
// type_app: atom { '[' type {, type} ']' } — left-assoc application of [..] args. A lowercase
// head stays a PyTvar when bare (`a`/`n`), but becomes a PyTcon when applied (`mydict[K,V]`) so
// lowering can resolve source-level lowercase `#sexpdef` aliases instead of losing the head.
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
  // ROBUSTNESS (Bug #41): each nested `[ … ]` type-arg payload is one native-stack DESCENT
  // (p_type_args -> p_index -> p_type -> p_type_app -> here, recursively). Bound that descent
  // so a pathologically nested input (`List[List[List[…`) emits a clean diagnostic + a
  // survivable PyTerror + resyncs to NEWLINE, instead of overflowing the JS native stack
  // (SEGFAULT EXIT 139). Mirrors every other parse error: ps_diag + an error node, no crash.
  if ps_depth_enter() then
    let
      val loc = ps_peek_loctn(st)
      val st1 = ps_diag(st, loc, "type nesting too deep (malformed '[...]'); recovering")
      val st2 = ps_resync(st1)
      val () = ps_depth_leave()
    in
      @(PyTerror(loc, "type nesting too deep"), st2)
    end
  else
  let
    val locL = pytyp_loctn(t0)
    val @(args, st1) = p_type_args(ps_advance(st))
    val locR = ps_peek_loctn(st1)
    val st2 = expect_rbrack(st1, locR)
    val () = ps_depth_leave()
    val t1 =
      ( case+ t0 of
        | PyTcon(_, nm, prev) => PyTcon(loc_span(locL, locR), nm, list_append(prev, args))
        | PyTvar(_, nm) => PyTcon(loc_span(locL, locR), nm, args)
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
  // DEP (static arithmetic): a type-arg may be an INDEX EXPRESSION (`n+1`, `i<n`, `n*2`) — parse
  // via p_index (the binop grammar over the type atom), not the bare p_type. A plain type/index
  // arg (`A`, `Int`, `0`, `n`, `Vec[A,n]`) is the no-operator base case of p_index, so this is a
  // strict SUPERSET of the old behavior (byte-identical when no index operator follows the atom).
  let val @(t, st1) = p_index(st) in
    case+ ps_peek(st1) of
    | PT_COMMA() =>
      let val @(ts, st2) = p_type_args(ps_advance(st1)) in
        @(list_cons(t, ts), st2) end
    | _ => @(list_cons(t, list_nil()), st1)
  end
)
//
// ==================================================================
//  INDEX-EXPRESSION grammar (DEP static arithmetic) — a small precedence-climbing parser over
//  the STATIC arithmetic/comparison operators, with `p_type` (the FULL type, incl. application
//  `Vec[A,n]` and arrows) as the ATOM. Precedence (loosest first), mirroring §5.6:
//    p_index      ::= p_index_add [ CMP p_index_add ]            CMP = < <= > >= == !=  (non-assoc)
//    p_index_add  ::= p_index_mul { ('+'|'-') p_index_mul }      (left-assoc)
//    p_index_mul  ::= p_type      { '*' p_type }                 (left-assoc)
//  A bare atom with NO trailing operator falls straight through (so a plain type arg is unchanged).
//  Each binop builds a `PyTbin(span, <pybop>, a, b)`; lowering maps the tag to a prelude static
//  `*_i0_i0` const (DEP-spike P1/P3/P4 recipe: add_i0_i0/lt_i0_i0/...). Reused by the guard parser.
// ==================================================================
//
and
p_index(st: pstate): @(pytyp, pstate) = let
  val @(a, st1) = p_index_add(st)
in
  case+ ps_peek(st1) of
  | PT_LT()   => p_index_cmp(a, PyBlt(), ps_advance(st1))
  | PT_LTE()  => p_index_cmp(a, PyBle(), ps_advance(st1))
  | PT_GT()   => p_index_cmp(a, PyBgt(), ps_advance(st1))
  | PT_GTE()  => p_index_cmp(a, PyBge(), ps_advance(st1))
  | PT_EQEQ() => p_index_cmp(a, PyBeq(), ps_advance(st1))
  | PT_NEQ()  => p_index_cmp(a, PyBne(), ps_advance(st1))
  | _ => @(a, st1)
end
//
// one (non-assoc) comparison: a CMP b — build the PyTbin over the already-parsed lhs.
and
p_index_cmp(a: pytyp, bop: pybop, st: pstate): @(pytyp, pstate) = let
  val @(b, st1) = p_index_add(st)
  val span = loc_span(pytyp_loctn(a), pytyp_loctn(b))
in
  @(PyTbin(span, bop, a, b), st1)
end
//
and
p_index_add(st: pstate): @(pytyp, pstate) = let
  val @(a, st1) = p_index_mul(st)
in
  p_index_add_loop(a, st1)
end
//
and
p_index_add_loop(a: pytyp, st: pstate): @(pytyp, pstate) =
(
case+ ps_peek(st) of
| PT_PLUS()  =>
  let val @(b, st1) = p_index_mul(ps_advance(st))
      val span = loc_span(pytyp_loctn(a), pytyp_loctn(b)) in
    p_index_add_loop(PyTbin(span, PyBadd(), a, b), st1) end
| PT_MINUS() =>
  let val @(b, st1) = p_index_mul(ps_advance(st))
      val span = loc_span(pytyp_loctn(a), pytyp_loctn(b)) in
    p_index_add_loop(PyTbin(span, PyBsub(), a, b), st1) end
| _ => @(a, st)
)
//
and
p_index_mul(st: pstate): @(pytyp, pstate) = let
  val @(a, st1) = p_type(st)   // the ATOM = a full type-app (Vec[A,n]) / index literal / var
in
  p_index_mul_loop(a, st1)
end
//
and
p_index_mul_loop(a: pytyp, st: pstate): @(pytyp, pstate) =
(
case+ ps_peek(st) of
| PT_STAR() =>
  let val @(b, st1) = p_type(ps_advance(st))
      val span = loc_span(pytyp_loctn(a), pytyp_loctn(b)) in
    p_index_mul_loop(PyTbin(span, PyBmul(), a, b), st1) end
| _ => @(a, st)
)
//
// type_atom: UIDENT[.ident]* | LIDENT | INT | '!' type_atom | '(' ... ')' | '{' ... '}'
and
p_type_atom(st: pstate): @(pytyp, pstate) = let
  val loc = ps_peek_loctn(st)
  val nod = ps_peek(st)
in
  case+ nod of
  | PT_UIDENT(s) => p_type_con_name(loc, s, ps_advance(st))
  | PT_LIDENT(s) => @(PyTvar(loc, s), ps_advance(st))
  | PT_INT(s)    => @(PyTidx(loc, s), ps_advance(st))
  // EXTYPE: a STRING LITERAL as a type atom — only meaningful as the arg of `Extype["name"]` /
  // `Extbox["name"]` (lowering's Extype/Extbox head detects it). Carries the raw quoted lexeme.
  | PT_STRING(s) => @(PyTstr(loc, s), ps_advance(st))
  // BOOTSTRAP-PARITY: ATS `!T` / `~T` linear/viewtype prefixes are accepted
  // in type position and erased for now. The parser keeps corpus interfaces round-trippable while
  // the deeper view-modality AST is still deferred.
  | PT_BANG()    => p_type_atom(ps_advance(st))
  | PT_TILDE()   => p_type_atom(ps_advance(st))
  // QMARK-TYPE: the `?` STATIC operator as a type-application HEAD — `?[A]` is the
  // "maybe-uninitialized" / top-view of `A` (ATS `#sexpdef ? = top0_vt_t0`). We parse
  // the bare `?` as the applied-type CON named "?" with NO args yet; the trailing
  // `[A]` is attached by p_type_app_loop's PyTcon arm (giving `PyTcon("?", [A])`).
  // Lowering resolves the head "?" against the prelude sexpdef, reproducing the stock
  // `S2Eapps([?, A])` -> S2Etop0(A). (A bare `?` with no `[...]` stays `PyTcon("?", [])`.)
  // The lexer splits `?!` into `?` + `!`; in TYPE position a `?` immediately followed by `!`
  // is the DISTINCT view operator `?!` (ATS `#sexpdef ?! = top1_vt_t0`, the discard-on-write
  // top view). Combine them into a single `PyTcon("?!", ...)` head (the trailing `[A]` is then
  // attached by the app-loop), so the emitted `?![A]` round-trips like `?[A]`.
  | PT_QMARK()   =>
    (case+ ps_peek(ps_advance(st)) of
     | PT_BANG() => @(PyTcon(loc, "?!", list_nil()), ps_advance(ps_advance(st)))
     | _ => @(PyTcon(loc, "?", list_nil()), ps_advance(st)))
  | PT_AMP()     => p_type_byref(ps_advance(st), loc)
  | PT_LPAREN()  => p_type_paren(ps_advance(st), loc)
  | PT_LBRACE()  => p_type_record(ps_advance(st), loc)
  // RECORD-VARIANT (Cluster D): `@boxed {..}` / `@linear {..}` / `@unboxed {..}` / `@ref {..}` — a
  // record-kind decorator before a `{` selects the box/flat/linear/ref kind in TYPE position.
  | PT_AT()      =>
    let val st1 = ps_advance(st) in     // past '@'
      case+ ps_peek(st1) of
      | PT_LIDENT(nm) =>
          let val @(knd, isr) = rcd_kind_of_deco(nm) in
            if isr then
              let val st2 = ps_advance(st1) in     // past the kind name
                case+ ps_peek(st2) of
                | PT_LBRACE() => p_type_record_kinded(ps_advance(st2), loc, knd)
                | _ =>
                    let val st3 = ps_diag(st2, ps_peek_loctn(st2),
                          strn_append("@", strn_append(nm, " here expects a '{ ... }' record type"))) in
                      @(PyTerror(loc, "record-kind decorator not followed by '{'"), st3) end
              end
            else
              let val st2 = ps_diag(st1, loc,
                    strn_append("unexpected type decorator @", nm)) in
                @(PyTerror(loc, "unexpected type decorator"), st2) end
          end
      | _ =>
          let val st2 = ps_diag(st1, loc, "expected a record-kind name after '@'") in
            @(PyTerror(loc, "expected a record-kind name after '@'"), st2) end
    end
  | _ =>
    let val st1 = ps_diag(st, loc, "expected a type") in
      @(PyTerror(loc, "expected a type"), st1) end
end
and
p_type_con_name(loc0: loctn, name0: strn, st: pstate): @(pytyp, pstate) =
(
case+ ps_peek(st) of
| PT_DOT() =>
    let
      val st1 = ps_advance(st)
    in
      case+ ps_peek(st1) of
      | PT_LIDENT(s1) =>
          let
            val loc1 = ps_peek_loctn(st1)
            val name1 = strn_append(strn_append(name0, "."), s1)
          in
            p_type_con_name(loc_span(loc0, loc1), name1, ps_advance(st1))
          end
      | PT_UIDENT(s1) =>
          let
            val loc1 = ps_peek_loctn(st1)
            val name1 = strn_append(strn_append(name0, "."), s1)
          in
            p_type_con_name(loc_span(loc0, loc1), name1, ps_advance(st1))
          end
      | _ =>
          let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected a type name after '.'") in
            @(PyTcon(loc0, name0, list_nil()), st2)
          end
    end
| _ => @(PyTcon(loc0, name0, list_nil()), st)
)
//
// BOOTSTRAP-PARITY: ATS by-reference/view-change argument types such as
// `&sint >> _` are accepted in Pythonic output as `&SInt >> _` and erased to the
// carried type for now. This is deliberately a parser shim; a first-class byref
// type node can replace it when M3 owns the deeper linear view-change semantics.
and
p_type_byref(st: pstate, locA: loctn): @(pytyp, pstate) = let
  val @(t0, st1) = p_type_app(st)
in
  case+ ps_peek(st1) of
  | PT_GT() =>
    let
      val st2 = ps_advance(st1)
    in
      case+ ps_peek(st2) of
      | PT_GT() =>
        let
          val st3 = ps_advance(st2)
          val st4 = p_type_byref_target(st3)
        in
          @(t0, st4)
        end
      | _ => @(t0, st1)
    end
  | _ => @(t0, st1)
end
and
p_type_byref_target(st: pstate): pstate =
(
  case+ ps_peek(st) of
  | PT_USCORE() => ps_advance(st)
  | _ =>
    let
      val @(_, st1) = p_type_app(st)
    in
      st1
    end
)
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
  | list_cons(t, list_nil()) => @(PyTparen(span, t), st2)
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
// after '{' : a record type `{ x: Int, y: Int }`. RECORD-VARIANT: `knd` is the TRCD20 kind
// (0=bare flat default; @boxed/@linear/.. prefix passes 3/4/.. via p_type_record_kinded).
and
p_type_record(st: pstate, locL: loctn): @(pytyp, pstate) =
  p_type_record_kinded(st, locL, 0(*flat*))
and
p_type_record_kinded(st: pstate, locL: loctn, knd: int): @(pytyp, pstate) = let
  val @(fs, st1) = p_tfields(st)
  val locR = ps_peek_loctn(st1)
  val st2 = expect_rbrace(st1, locR)
in
  @(PyTrec(loc_span(locL, locR), knd, fs), st2)
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
fun
lowercase_nullary_datacon(s: strn): bool =
(
  if strn_eq(s, "list_nil") then true
  else if strn_eq(s, "optn_nil") then true
  else if strn_eq(s, "list_vt_nil") then true
  else if strn_eq(s, "optn_vt_nil") then true
  else if strn_eq(s, "strmcon_vt_nil") then true
  else strn_eq(s, "strxcon_vt_nil")
)
//
fun
lowercase_datacon(s: strn): bool =
(
  if lowercase_nullary_datacon(s) then true
  else if strn_eq(s, "list_cons") then true
  else if strn_eq(s, "optn_cons") then true
  else if strn_eq(s, "list_vt_cons") then true
  else if strn_eq(s, "optn_vt_cons") then true
  else if strn_eq(s, "strmcon_vt_cons") then true
  else strn_eq(s, "strxcon_vt_cons")
)
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
  // BOOTSTRAP-PARITY: generated ATS view patterns mark carried fields as `!p`.
  // Preserve the prefix so lowering can emit the existing ATS `D2Pbang` node.
  | PT_BANG() =>
    let
      val @(p1, st1) = p_pat_atom(ps_advance(st))
    in
      @(PyPbang(loc_span(loc, pypat_loctn(p1)), p1), st1)
    end
  // B-LINEAR: `~p` — the LINEAR-CONSUME prefix. Consume `~`, parse the inner pattern atom,
  // wrap in PyPfree. (Typically `~VCons(x, rest)` — the inner is a con pattern.)
  | PT_TILDE() =>
    let
      val @(p1, st1) = p_pat_atom(ps_advance(st))
    in
      @(PyPfree(loc_span(loc, pypat_loctn(p1)), p1), st1)
    end
  // BOOTSTRAP-PARITY: ATS viewboxed constructor patterns print as `@(C)(args)`.
  // Preserve the wrapper so lowering can emit the existing ATS `D2Pflat` node.
  | PT_AT() => p_pat_at(st)
  | PT_USCORE() => @(PyPwild(loc), ps_advance(st))
  | PT_LIDENT(s) =>
    let val st1 = ps_advance(st) in
      if lowercase_datacon(s) then
        let
          val @(sargs, st1b) = p_pat_sargs(st1)
        in
          case+ ps_peek(st1b) of
          | PT_LPAREN() =>
            let
              val @(args, st2) = p_pat_seq(ps_advance(st1b))
              val locR = ps_peek_loctn(st2)
              val st3 = expect_rparen(st2, locR)
            in
              @(PyPcon(loc_span(loc, locR), s, sargs, args), st3)
            end
          | _ =>
              @(PyPcon(loc, s, sargs, list_nil()), st1b)
        end
      else
        // BOOTSTRAP-PARITY: a bare lowercase identifier is still a fresh variable
        // binder, but an APPLIED lowercase head is constructor-shaped in ATS output
        // (`strxcon_vt_cons(...)`, source-defined lowercase datacons, ...). Let
        // lowering resolve the constructor name instead of rejecting it syntactically.
        case+ ps_peek(st1) of
        | PT_LPAREN() =>
          let
            val @(args, st2) = p_pat_seq(ps_advance(st1))
            val locR = ps_peek_loctn(st2)
            val st3 = expect_rparen(st2, locR)
          in
            @(PyPcon(loc_span(loc, locR), s, list_nil(), args), st3)
          end
        | PT_LBRACE() =>
          let
            val @(sargs, st1b) = p_pat_sargs(st1)
          in
            case+ ps_peek(st1b) of
            | PT_LPAREN() =>
              let
                val @(args, st2) = p_pat_seq(ps_advance(st1b))
                val locR = ps_peek_loctn(st2)
                val st3 = expect_rparen(st2, locR)
              in
                @(PyPcon(loc_span(loc, locR), s, sargs, args), st3)
              end
            | _ => @(PyPcon(loc_span(loc, ps_peek_loctn(st1b)), s, sargs, list_nil()), st1b)
          end
        | _ => @(PyPvar(loc, s), st1)
    end
  | PT_UIDENT(s) =>
    let
      val st1 = ps_advance(st)
      // C-PROOF: an OPTIONAL `{ sarg, ... }` EXISTENTIAL-UNPACK static-arg list between the con
      // name and the value-arg parens (`VCons{n}(x, rest)`). `{n}` binds the con's hidden index
      // into the arm scope. p_pat_sargs returns [] when no `{` follows (a plain con pattern).
      val @(sargs, st1b) = p_pat_sargs(st1)
    in
      case+ ps_peek(st1b) of
      | PT_LPAREN() =>
        let
          val @(args, st2) = p_pat_seq(ps_advance(st1b))
          val locR = ps_peek_loctn(st2)
          val st3 = expect_rparen(st2, locR)
        in
          @(PyPcon(loc_span(loc, locR), s, sargs, args), st3)
        end
      | _ => @(PyPcon(loc, s, sargs, list_nil()), st1b)
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
  | PT_LBRACE() => p_pat_record_kinded(ps_advance(st), loc, 0(*flat*))
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
// RECORD-VARIANT (Cluster D): a record PATTERN `[@boxed|@linear ]{ f = p, ... }`. `knd` is the
// TRCD20 kind (0=bare flat default; @boxed/@linear/.. passes 3/4/..). Fields use '=' (PyPrec).
p_pat_record_kinded(st: pstate, locL: loctn, knd: int): @(pypat, pstate) = let
  val @(fs, st1) = p_pfields(st)
  val locR = ps_peek_loctn(st1)
  val st2 = expect_rbrace(st1, locR)
in
  @(PyPrec(loc_span(locL, locR), knd, fs), st2)
end
and
p_pat_at(st: pstate): @(pypat, pstate) = let
  val locA = ps_peek_loctn(st)
  val st1 = ps_advance(st)
in
  case+ ps_peek(st1) of
  // RECORD-VARIANT: `@boxed {..}` / `@linear {..}` / `@unboxed {..}` / `@ref {..}` — a record-kind
  // decorator (LIDENT) before a `{` selects the box/flat/linear/ref kind in PATTERN position. This
  // is checked BEFORE the `@(Con)` flat-pattern path (which needs a `(`, not a kind name). A LIDENT
  // that is NOT a record-kind name falls through to the error recovery below.
  | PT_LIDENT(nm) =>
    let val @(knd, isr) = rcd_kind_of_deco(nm) in
      if isr then
        let val st2 = ps_advance(st1) in    // past the kind name
          case+ ps_peek(st2) of
          | PT_LBRACE() => p_pat_record_kinded(ps_advance(st2), locA, knd)
          | _ =>
              let val st3 = ps_diag(st2, ps_peek_loctn(st2),
                    strn_append("@", strn_append(nm, " here expects a '{ ... }' record pattern"))) in
                @(PyPerror(locA, "record-kind decorator not followed by '{'"), st3) end
        end
      else
        let val st2 = ps_diag(st1, locA,
              strn_append("unexpected pattern decorator @", nm)) in
          @(PyPerror(locA, "unexpected pattern decorator"), ps_advance(st2)) end
    end
  | PT_LPAREN() =>
    let
      val st2 = ps_advance(st1)
    in
      case+ ps_peek(st2) of
      | PT_UIDENT(nm) =>
        let
          val st3 = ps_advance(st2)
          val @(sargs, st3b) = p_pat_sargs(st3)
          val locR0 = ps_peek_loctn(st3b)
          val st4 = expect_rparen(st3b, locR0)
        in
          p_pat_at_finish(locA, locR0, nm, sargs, st4)
        end
      | PT_LIDENT(nm) =>
        let
          val st3 = ps_advance(st2)
          val @(sargs, st3b) = p_pat_sargs(st3)
          val locR0 = ps_peek_loctn(st3b)
          val st4 = expect_rparen(st3b, locR0)
        in
          p_pat_at_finish(locA, locR0, nm, sargs, st4)
        end
      | _ =>
        let
          val loc = ps_peek_loctn(st2)
          val st3 = ps_diag(st2, loc, "expected a constructor name inside '@(...)' pattern")
        in
          @(PyPerror(loc_span(locA, loc), "expected '@(Constructor)' pattern"), st3)
        end
    end
  | _ =>
    let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected '(' after '@' in pattern") in
      @(PyPerror(locA, "expected '@(...)' pattern"), st2) end
end
//
and
p_pat_at_finish
(locA: loctn, locH: loctn, nm: strn, sargs: list(strn), st: pstate): @(pypat, pstate) =
(
case+ ps_peek(st) of
| PT_LPAREN() =>
  let
    val @(args, st1) = p_pat_seq(ps_advance(st))
    val locR = ps_peek_loctn(st1)
    val st2 = expect_rparen(st1, locR)
  in
    let val p1 = PyPcon(loc_span(locA, locR), nm, sargs, args) in
      @(PyPflat(loc_span(locA, locR), p1), st2)
    end
  end
| _ =>
  let val p1 = PyPcon(loc_span(locA, locH), nm, sargs, list_nil()) in
    @(PyPflat(loc_span(locA, locH), p1), st)
  end
)
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
// C-PROOF: parse the OPTIONAL `{ name, name, ... }` EXISTENTIAL-UNPACK static-arg list that may
// follow a con name in a pattern (`VCons{n}(x, rest)`). Returns the binder NAMES (LIDENTs) — `[]`
// when no `{` follows (a plain con pattern). The `{n}` binds the con's hidden index var into the
// arm scope. A `{` here is unambiguous: a record PATTERN `{f=p}` is only ever an ATOM (never right
// after a UIDENT), so `UIDENT {` always opens a static-arg list.
and
p_pat_sargs(st: pstate): @(list(strn), pstate) =
(
case+ ps_peek(st) of
| PT_LBRACE() =>
  let
    val @(ns, st1) = p_sarg_names(ps_advance(st))
    val locR = ps_peek_loctn(st1)
    val st2 = expect_rbrace(st1, locR)
  in
    @(ns, st2)
  end
| _ => @(list_nil(), st)
)
//
// the comma-separated LIDENT name list inside a `{ ... }` static-arg list. A non-LIDENT (or `}`)
// terminates; a stray token is reported + skipped (recovery) so a malformed `{...}` can't wedge.
and
p_sarg_names(st: pstate): @(list(strn), pstate) =
(
case+ ps_peek(st) of
| PT_RBRACE() => @(list_nil(), st)
| PT_EOF() => @(list_nil(), st)
| PT_LIDENT(nm) =>
  let val st1 = ps_advance(st) in
    case+ ps_peek(st1) of
    | PT_COMMA() =>
      let val @(ns, st2) = p_sarg_names(ps_advance(st1)) in
        @(list_cons(nm, ns), st2) end
    | _ => @(list_cons(nm, list_nil()), st1)
  end
| _ =>
  let val st1 = ps_diag(st, ps_peek_loctn(st), "expected an index binder name in '{...}' unpack") in
    @(list_nil(), st1) end
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
#implfun parse_index_type(st) = p_index(st)
#implfun parse_pattern(st) = p_pat(st)
//
// A-TEMPLATE: a decorator's `[ type {, type} ]` type-arg payload (the `@impl[Int]` / `@inst[Int]`
// brackets). Consume the '[', reuse the EXISTING type-arg grammar (p_type_args — the SAME one a
// `List[Int]` application uses, so `Int` / `List[Int]` / a bare index all parse), then expect ']'.
// A missing '[' yields an empty list (the caller only calls this when a '[' is present, but be
// defensive). NO trailing token is consumed beyond the ']'.
#implfun
parse_deco_typeargs(st) =
( case+ ps_peek(st) of
  | PT_LBRACK() =>
    let
      val @(ts, st1) = p_type_args(ps_advance(st))
      val locR = ps_peek_loctn(st1)
      val st2 = expect_rbrack(st1, locR)
    in
      @(ts, st2)
    end
  | _ => @(list_nil(), st) )
//
(* ****** ****** *)
(*
end of [frontend/DATS/pyparsing_staexp.dats]
*)
