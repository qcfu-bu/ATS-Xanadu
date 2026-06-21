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
  | PT_UIDENT(_) =>
    let val @(tp, st1) = p_typaram(st) in
      case+ ps_peek(st1) of
      | PT_COMMA() =>
        let val @(rest, st2) = p_tyvar_seq(ps_advance(st1)) in
          @(list_cons(tp, rest), st2) end
      | PT_RBRACK() => @(list_cons(tp, list_nil()), ps_advance(st1))
      | _ =>
        let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected ',' or ']' in type params") in
          @(list_cons(tp, list_nil()), st2) end
    end
  | _ =>
    let val st1 = ps_diag(st, ps_peek_loctn(st), "expected a type parameter (uppercase)") in
      @(list_nil(), st1) end )
//
// one type parameter: UIDENT [ ':' SORT ] { '@' LIDENT }.
and
p_typaram(st: pstate): @(pytyparam, pstate) = let
  val loc = ps_peek_loctn(st)
  val @(nm, st1) =
    ( case+ ps_peek(st) of
      | PT_UIDENT(s) => @(s, ps_advance(st))
      | _ => @("?", ps_diag(st, loc, "expected a type parameter (uppercase)")) )
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
  @(PyTyParam(loc, nm, sopt, decos), st3)
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
        let val @(rest, st2) = p_inline_decorators(ps_advance(st1)) in
          @(list_cons(PyDecor(locA, nm), rest), st2) end
      | _ =>
        let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected a decorator name after '@'") in
          @(list_nil(), st2) end
    end
  | _ => @(list_nil(), st) )
//
(* ****** ****** *)
//
// ---- prefix decorators: { '@' LIDENT NEWLINE } → a list(pydecorator) in source order. ----
//   Each prefix decorator sits on its own line (§5.7), so a NEWLINE follows.
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
          // consume the trailing NEWLINE (prefix decorators are line-terminated).
          val st3 =
            ( case+ ps_peek(st2) of
              | PT_NEWLINE() => ps_advance(st2)
              | _ => st2 )
          val @(rest, st4) = p_decorators(st3)
        in
          @(list_cons(PyDecor(locA, nm), rest), st4)
        end
      | _ =>
        let val st2 = ps_diag(st1, ps_peek_loctn(st1), "expected a decorator name after '@'") in
          @(list_nil(), st2) end
    end
  | _ => @(list_nil(), st) )
//
(* ****** ****** *)
//
// ---- def: 'def' LIDENT [typarams] '(' [params] ')' ['->' type] ':' suite ----
//
fun
p_def(st: pstate): @(pydecl, pstate) = let
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
  // ':' then the body suite
  val st8 =
    ( case+ ps_peek(st7) of
      | PT_COLON() => ps_advance(st7)
      | _ => ps_diag(st7, ps_peek_loctn(st7), "expected ':' before the def body") )
  val @(body, st9) = parse_suite(st8)
in
  @(PyCfun(loc, nm, tvs, params, ropt, body), st9)
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
// ---- type declarations (§5.7): the decorators are parsed by the caller (parse_decl)
//      and threaded in. Three distinct keywords (no alias-vs-datatype heuristic):
//        enum   Name [typarams] ':' <case suite>     → a datatype/ADT  (PyCenum)
//        struct Name [typarams] ':' <field suite>    → a record        (PyCstruct)
//        type   Name [typarams] '=' type NEWLINE     → an alias ONLY   (PyCtype)
//
// alias-only `type` decl: 'type' UIDENT [typarams] '=' type NEWLINE.
//
fun
p_typedecl(st: pstate, decos: list(pydecorator)): @(pydecl, pstate) = let
  val loc = ps_peek_loctn(st)
  val st1 = ps_advance(st)               // past 'type'
  val @(nm, st2) =
    ( case+ ps_peek(st1) of
      | PT_UIDENT(s) => @(s, ps_advance(st1))
      | _ => @("?", ps_diag(st1, ps_peek_loctn(st1), "expected a type name (uppercase)")) )
  val @(tvs, st3) = p_typarams(st2)
  val st4 =
    ( case+ ps_peek(st3) of
      | PT_EQ() => ps_advance(st3)
      | _ => ps_diag(st3, ps_peek_loctn(st3), "expected '=' in type alias declaration") )
  val @(t, st5) = parse_type(st4)
in
  @(PyCtype(loc, decos, nm, tvs, t), st5)
end
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
// ---- the SATS `parse_decl` entry: a type decl may be prefixed by decorators (§5.7), so
//      FIRST parse zero-or-more prefix decorators, THEN dispatch on the next keyword. The
//      decorators are threaded into the enum/struct/type node. A `def` takes NO decorators
//      in v1 — if any precede a `def` we REJECT with a clear PyCerror (the def body is still
//      consumed for recovery so the module loop makes progress).
//
#implfun
parse_decl(st) = let
  val locD = ps_peek_loctn(st)
  val @(decos, st0) = p_decorators(st)
  val nod = ps_peek(st0)
in
  case+ nod of
  | PT_KW_DEF()    =>
    ( case+ decos of
      | list_nil() => p_def(st0)
      | _ =>
        // decorators on a `def` are not supported in v1: reject, but still parse the def
        // for recovery and discard it, returning a PyCerror at the decorator span.
        let val @(_, st1) = p_def(st0) in
          @(PyCerror(locD, "decorators are not allowed on a 'def' (§5.7)"),
            ps_diag(st1, locD, "decorators are not allowed on a 'def'")) end )
  | PT_KW_ENUM()   => p_enumdecl(st0, decos)
  | PT_KW_STRUCT() => p_structdecl(st0, decos)
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
    // a decorator-prefixed type decl (enum/struct = block; type = alias). expect_newline_d
    // is a no-op after a block (DEDENT consumed), and consumes the NEWLINE after an alias.
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
