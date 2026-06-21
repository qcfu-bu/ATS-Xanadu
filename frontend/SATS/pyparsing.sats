(* ****** ****** *)
(*
** M2 — Python-surface frontend: the surface AST (PyAST) + parser entries (SATS).
**
** THIS FILE IS THE CONTRACT M2.5 (the loop/mut elaborator → PyCore) AND M3 (the L2
** lowering) WILL CONSUME. The parser (frontend/DATS/pyparsing_*.dats) reads the
** `pytoken` stream produced by `pylex_layout` (frontend/SATS/pylexing.sats) and
** produces a *faithful surface* AST — NO desugaring, NO lowering. Every node carries
** a real `loctn` (borrowed from the compiler's location model, srcgen2/SATS/
** locinfo.sats) so diagnostics land on the .py source and the lowering can thread the
** span into the L2 node (PYTHON-FRONTEND-PLAN.md §6.3).
**
** Authority for the surface grammar: frontend/docs/SURFACE-GRAMMAR.md (§5.2 module &
** decls, §5.3 statements & suites, §5.4 expressions, §5.5 patterns & types, §5.6
** operator precedence). Authority for the imperative-control representation that M2.5
** desugars: frontend/docs/LOOP-DESUGARING.md §1–§2.
**
** ===================== design rationale (read before changing) =====================
**
** WHY A FAITHFUL SURFACE AST (not already-desugared):
**   M2 stops at the surface. The `mut` flag on a binding, the distinct
**   `while`/`for`/`break`/`continue`/`return` statement nodes, the loop-`else`
**   clause, and the reassignment node are ALL kept EXPLICIT so M2.5 can run its
**   accumulator-set analysis (LOOP-DESUGARING §4) and emit PyCore. If M2 desugared,
**   M2.5 would have nothing to analyze. So:
**     * `PyDlet`     carries a `bool` mut flag (let vs let-mut).
**     * `PySreassign` is a DISTINCT node (NOT a `let`) — "x = e" reassignment.
**     * `PySwhile`/`PySfor` each carry an OPTIONAL else-suite (loop-`else`).
**     * `PySbreak`/`PyScontinue`/`PySreturn` are distinct nullary/­value control nodes.
**
** WHY THE UIDENT/LIDENT DISTINCTION IS PRESERVED IN THE AST (not collapsed to one
** "ident" node):
**   The load-bearing §5 case convention lets M3 tell a CONSTRUCTOR from a VAR / a
**   TYPE-CONSTRUCTOR from a TYPE-VAR *without re-resolving names*. The lexer already
**   split them (PT_UIDENT/PT_LIDENT); we KEEP that split in the AST:
**     * `PyEvar`  (LIDENT)  = a variable / function reference            → d2var lookup
**     * `PyEcon`  (UIDENT)  = a data constructor (e.g. nullary `Leaf`)   → d2con lookup
**     * `PyPvar`  (LIDENT)  = a fresh pattern binder
**     * `PyPcon`  (UIDENT)  = a constructor pattern (must resolve to a d2con)
**     * `PyTcon`  (UIDENT)  = a type constructor (Int, List, Tree)
**     * `PyTvar`  (LIDENT)  = a type variable (a, b)
**   So lowering keys off the AST node KIND, exactly as the grammar's case convention
**   intends — no name resolution in M3 just to recover constructor-vs-var.
**
** WHY OPERATORS ARE ALREADY GROUPED (Pratt output, not a flat token list):
**   The parser OWNS precedence (§5.6) via precedence-climbing (Pratt). By the time a
**   `pyexp` exists, the source `a plus b times c` is already grouped as
**   PyEbin(add, a, PyEbin(mul, b, c)) — fully
**   associated/grouped. M3 never re-parses precedence. Binary/unary operators are
**   represented by a small `pybop`/`pyuop` tag enum (one ctor per §5.6 operator) so
**   M3 maps each to its prelude `d2cst` (LOWERING-MAP §3.4) by matching the tag, and
**   `and`/`or`/`not` are kept as their own tags so M3 lowers them to short-circuit
**   `if` (LOOP-DESUGARING / §5.6).
**
** ERROR RECOVERY (non-fail-fast; matches the compiler's …errck spirit):
**   The parser NEVER throws. On a parse error it inserts an ERROR node
**   (`PyEerror`/`PyPerror`/`PyTerror`/`PySerror`/`PyDerror`) carrying a message + the
**   span it failed at, then resynchronizes at the next NEWLINE / DEDENT. A malformed
**   file still yields a partial PyAST plus a list of recovery diagnostics
**   (`pydiag`). The harness dumps both.
**
** RE-ENTRANCY (plan §6.2; the LSP is resident): the parser is PURE per call. It takes
** a token list, returns a fresh `pymodule` + diagnostics; there is no module-global
** mutable parser state across calls.
**
** PURELY ADDITIVE: nothing under srcgen2/ or language-server/ is modified; we only
** CALL the location model. M0/M1 files are untouched; we CONSUME pylexing.sats
** read-only.
*)
(* ****** ****** *)
//
// Bring in the location model (loctn / postn / lcsrc + makers/printers/`+`) and the
// pure prelude+libcats SATS bundle (FILR = FILEref, strn, list, ...). Same 3-header
// discipline the M1 SATS used (libxatsopt.hats is SATS-only; xatsopt_sats.hats names
// FILR/strn/list). The DATS additionally include xatsopt_dpre.hats for the prelude
// DATS (template implementations), per ENGINEERING.md §2.
//
#include "./../../srcgen2/HATS/libxatsopt.hats"
#include "./../../srcgen2/HATS/xatsopt_sats.hats"
//
#staload "./../../srcgen2/SATS/locinfo.sats"
//
#staload "./../SATS/pylexing.sats"
//
(* ****** ****** *)
//
// ==================================================================
//  Operator tags (the §5.6 table, already-resolved by the Pratt parser)
// ==================================================================
//
// Binary operators (levels 1,2,4,5,6,8 of §5.6). `and`/`or` are kept distinct so M3
// lowers them to short-circuiting `if`; the rest map to a prelude `d2cst`.
//
datatype
pybop =
| PyBor   of ()  // or   (lvl 1, left, short-circuit)
| PyBand  of ()  // and  (lvl 2, left, short-circuit)
| PyBeq   of ()  // ==   (lvl 4, non-assoc)
| PyBne   of ()  // !=
| PyBlt   of ()  // <
| PyBle   of ()  // <=
| PyBgt   of ()  // >
| PyBge   of ()  // >=
| PyBadd  of ()  // +    (lvl 5, left)
| PyBsub  of ()  // -
| PyBmul  of ()  // *    (lvl 6, left)
| PyBdiv  of ()  // /
| PyBmod  of ()  // %
| PyBfdiv of ()  // //   (integer division)
| PyBpow  of ()  // **   (lvl 8, right-assoc)
//
// Unary (prefix) operators (levels 3,7 of §5.6).
//
datatype
pyuop =
| PyUnot  of ()  // not  (lvl 3, prefix, short-circuit → if)
| PyUneg  of ()  // -    (lvl 7, prefix)
| PyUpos  of ()  // +    (lvl 7, prefix)
//
(* ****** ****** *)
//
// NOTE on list aliases: the `*lst = list(*)` typedefs are declared AFTER the datatype
// block (below), NOT here. A forward `#typedef pyexplst = list(pyexp)` placed before
// the datatype resolves the element type to an impredicative `type` and breaks L3 list
// packing (verified: a fresh `list_cons(x, list_nil())` then fails to unify with the
// alias). Inside the datatype the list fields use the INLINE `list(pyexp)` form.
//
(* ****** ****** *)
//
// ==================================================================
//  pytyp — the surface TYPE language (§5.5)
// ==================================================================
//
//   PyTcon  : UIDENT applied to 0+ type args — `Int`, `List[Int]`, `Tree[a]`.
//             (a bare `Int` is `PyTcon("Int", [])`; `List[Int]` carries one arg.)
//   PyTvar  : LIDENT — a type variable (`a`, `b`).
//   PyTidx  : an INT index literal in a dependent type (e.g. array sizes).
//   PyTfun  : function type `(A, B) -> C` — args ++ result, right-assoc at parse.
//   PyTtup  : tuple type `(A, B)`.
//   PyTrec  : record type `{ x: Int, y: Int }` — fields use ':'.
//   PyTerror: a type we could not parse (recovery).
//
datatype
pytyp =
| PyTcon   of (loctn, strn, list(pytyp))
| PyTvar   of (loctn, strn)
| PyTidx   of (loctn, strn)
| PyTfun   of (loctn, list(pytyp), pytyp)
| PyTtup   of (loctn, list(pytyp))
| PyTrec   of (loctn, list(pytfield))
| PyTerror of (loctn, strn)
//
// a record-type field `name: type`
and
pytfield =
| PyTField of (loctn, strn, pytyp)
//
(* ****** ****** *)
//
// ==================================================================
//  pypat — the surface PATTERN language (§5.5)
// ==================================================================
//
//   PyPvar   : LIDENT — a fresh binder.
//   PyPwild  : `_` wildcard.
//   PyPcon   : UIDENT [ '(' args ')' ] — constructor pattern; nullary `Leaf` has [].
//   PyPtup   : `( p, p )` tuple pattern.
//   PyPrec   : `{ f = p, ... }` record pattern.
//   PyPlit   : a literal pattern (incl. true/false). Carries the literal node.
//   PyPas    : `p as x` — an as-pattern binding the whole match to LIDENT.
//   PyPann   : `p : T` — an annotated pattern (kept for completeness; param sites).
//   PyPerror : a pattern we could not parse (recovery).
//
and
pypat =
| PyPvar   of (loctn, strn)
| PyPwild  of (loctn)
| PyPcon   of (loctn, strn, list(pypat))
| PyPtup   of (loctn, list(pypat))
| PyPrec   of (loctn, list(pypfield))
| PyPlit   of (loctn, pylit)
| PyPas    of (loctn, pypat, strn)
| PyPann   of (loctn, pypat, pytyp)
| PyPerror of (loctn, strn)
//
// a record-pattern field `name = pat`
and
pypfield =
| PyPField of (loctn, strn, pypat)
//
// ==================================================================
//  pylit — literals (lexeme kept verbatim, exactly as the lexer delivered them)
// ==================================================================
//
//   M2 keeps the SOURCE LEXEME (quotes/prefix included). Numeric value parsing and
//   escape decoding stay in M3/lowering (which synthesizes the L2 leaf token from the
//   lexeme; ENGINEERING.md §3 uses token_make_node over the lexeme). true/false are
//   their own literal nodes (NOT data constructors; §5 preamble).
//
and
pylit =
| PyLint  of (loctn, strn)
| PyLflt  of (loctn, strn)
| PyLstr  of (loctn, strn)
| PyLchr  of (loctn, strn)
| PyLbool of (loctn, bool)
//
(* ****** ****** *)
//
// ==================================================================
//  pyexp — the surface EXPRESSION language (§5.4)
// ==================================================================
//
//   PyEvar   : LIDENT — a variable / function reference (→ d2var).
//   PyEcon   : UIDENT — a data constructor reference (e.g. nullary `Leaf`) (→ d2con).
//   PyElit   : a literal.
//   PyEwild  : `_` used as an expression (rare; kept for symmetry).
//   PyEapp   : a CALL `f(a, b)` — head ++ arglist. (Constructor application `Node(l,x,r)`
//              is `PyEapp(PyEcon "Node", [l;x;r])`; the head's kind tells M3 con-vs-fun.)
//   PyEbin   : a binary operator application (Pratt-grouped). Carries the `pybop` tag.
//   PyEuna   : a unary/prefix operator application. Carries the `pyuop` tag.
//   PyEif    : `if c: t elif c2: t2 ... else: e` EXPRESSION. A list of (cond, branch)
//              guarded arms + a mandatory else branch (§5.4 if_expr requires `else`).
//   PyEmatch : `match e: case p [if g]: body ...` EXPRESSION. scrutinee + arm list.
//   PyEtup   : `( e, e )` tuple (also a bare `a, b` in return/RHS positions, §5.4 exprs).
//              A 0-tuple `()` is unit; a 1-element parenthesized expr is NOT a tuple
//              (the parser returns the inner expr directly).
//   PyElist  : `[ e, e ]` list literal.
//   PyErec   : `{ f = e, ... }` record literal — value fields use '='.
//   PyEfield : `e.name` field access / projection.
//   PyEindex : `e[i]` indexing.
//   PyElam   : a lambda `params => body` — inline OR block body (§2). The body is a
//              SUITE (a pystmt list) carrying its own tail value; an inline body is a
//              single expr-stmt suite. Params are `pyparam`s.
//              M7-closures: the `bool` is the `@func` FLAG (true = the surface lambda was
//              prefixed with `@func`). The surface default (`false`) is a CAPTURING first-
//              class closure (uniform cloref). `@func` (true) opts the lambda into being
//              NON-capturing, ENFORCED by the elaborator's free-variable/capture check (a
//              `@func` lambda that references an enclosing FUNCTION-LOCAL is an error). The
//              flag is a CHECK gate + a recorded codegen hint — it is NOT a type distinction.
//   PyEann   : `e : T` — an annotated expression.
//   PyEerror : an expression we could not parse (recovery).
//
and
pyexp =
| PyEvar   of (loctn, strn)
| PyEcon   of (loctn, strn)
| PyElit   of (loctn, pylit)
| PyEwild  of (loctn)
| PyEapp   of (loctn, pyexp, list(pyexp))
| PyEbin   of (loctn, pybop, pyexp, pyexp)
| PyEuna   of (loctn, pyuop, pyexp)
| PyEif    of (loctn, list(pyguard), pyexp)
| PyEmatch of (loctn, pyexp, list(pyarm))
| PyEtup   of (loctn, list(pyexp))
| PyElist  of (loctn, list(pyexp))
| PyErec   of (loctn, list(pyefield))
| PyEfield of (loctn, pyexp, strn)
| PyEindex of (loctn, pyexp, pyexp)
| PyElam   of (loctn, bool(*@func*), list(pyparam), list(pystmt))
| PyEann   of (loctn, pyexp, pytyp)
//   PyEraise : `raise e` — raise an exception (EXN). `e` is an exn-typed expression
//              (a constructor application `E(args)` or a nullary `E`). The whole
//              `raise` does not return (it has any type — lowers to D2Eraise).
//   PyEtry   : `try: <body suite>  except <pat>: <handler suite> ...` (EXN). A VALUE:
//              the body's value if no raise, else the matching handler's value (all
//              branches unify). The except clauses reuse `pyarm` (pattern + body suite,
//              like a match `case`). Lowers to D2Etry0(body, clauses-over-exn).
| PyEraise of (loctn, pyexp)
| PyEtry   of (loctn, list(pystmt)(*body*), list(pyarm)(*except handlers over exn*))
| PyEerror of (loctn, strn)
//
// a record-literal field `name = expr`
and
pyefield =
| PyEField of (loctn, strn, pyexp)
//
// a guarded arm of an `if`-expression / `if`-statement: `cond : branch`. The branch
// is a SUITE so a block body is representable (§5.4 branch ::= expr | INDENT stmts).
and
pyguard =
| PyGuard of (loctn, pyexp, list(pystmt))
//
// a `case` arm: `case pat [if guard]: body`. The optional guard is an expr option.
and
pyarm =
| PyArm of (loctn, pypat, pyexpopt, list(pystmt))
//
// a function/lambda parameter: `x` or `x : T`.
and
pyparam =
| PyParam of (loctn, strn, pytypopt)
//
// a decorator: @name  (§5.7) — e.g. @linear, @unboxed, @boxed
and pydecorator = PyDecor of (loctn, strn)
// the optional sort annotation on a type param (Type/Linear/Prop/… — OPEN vocab, kept as strn)
and pysortopt   = PySortNone of () | PySortSome of (loctn, strn)
// a type parameter:  UIDENT [ ':' SORT ] { DECORATOR }   (§5.7)
and pytyparam    = PyTyParam of (loctn, strn, pysortopt, list(pydecorator))
// a struct field:  LIDENT ':' type   (§5.7)
and pyfield      = PyField of (loctn, strn, pytyp)
//
(* ****** ****** *)
//
// ==================================================================
//  pystmt — the surface STATEMENT language (§5.3). KEPT FAITHFUL for M2.5.
// ==================================================================
//
//   PyDlet      : `let [mut] pat [: T] = e` — the `bool` is the MUT FLAG (true = mut).
//                 This is the linchpin M2.5 keys on (LOOP-DESUGARING §1).
//   PySreassign : `lvalue = e` reassignment — a DISTINCT node (NOT a let). M2.5 turns
//                 a valid one into an SSA shadowing rebind; an invalid one (immutable
//                 / undeclared target) is an elaboration error THERE (not M2's job).
//                 The lvalue is a `pyexp` restricted by the parser to LIDENT / field /
//                 index forms (§5.3 lvalue); we keep it as a pyexp so M2.5 inspects it.
//   PySexpr     : a bare expression statement.
//   PySif       : `if c: ... elif ...: ... else: ...` STATEMENT — guarded arms + an
//                 OPTIONAL else suite (statement `if` may omit `else`, unlike if-expr).
//   PySwhile    : `while c: <suite> [else: <suite>]` — body + OPTIONAL else suite.
//   PySfor      : `for pat in e: <suite> [else: <suite>]` — pattern, iterable, body,
//                 OPTIONAL else suite.
//   PySbreak    : `break`.
//   PyScontinue : `continue`.
//   PySreturn   : `return [exprs]` — optional value (a bare-tuple `a, b` parses to one
//                 PyEtup expr; absence is None = `return` with no value).
//   PySblock    : a bare local block (an INDENT-opened suite used as a statement). Kept
//                 for completeness; the grammar mostly opens suites via headers.
//   PySdecl     : a declaration appearing in statement position (def / type — §5.3
//                 allows `funcdef`/`typedecl` as statements; we wrap a pydecl).
//   PySerror    : a statement we could not parse (recovery).
//
and
pystmt =
| PyDlet      of (loctn, bool, pypat, pytypopt, pyexp)
| PySreassign of (loctn, pyexp, pyexp)
| PySexpr     of (loctn, pyexp)
| PySif       of (loctn, list(pyguard), pystmtlstopt)
| PySwhile    of (loctn, pyexp, list(pystmt), pystmtlstopt)
| PySfor      of (loctn, pypat, pyexp, list(pystmt), pystmtlstopt)
| PySbreak    of (loctn)
| PyScontinue of (loctn)
| PySreturn   of (loctn, pyexpopt)
| PySblock    of (loctn, list(pystmt))
| PySdecl     of (loctn, pydecl)
| PySerror    of (loctn, strn)
//
(* ****** ****** *)
//
// ==================================================================
//  pydecl — top-level / structural DECLARATIONS (§5.2)
// ==================================================================
//
//   PyCfun  : `def name [typarams] (params) [-> Ret]: <suite>`. Carries the name
//             (LIDENT), optional type params (rich pytyparam list — §5.7), value params,
//             optional return type, and the body suite. Recursion grouping (adjacent defs
//             = one mutually-recursive group, §5.2) is M3's concern; M2 emits one PyCfun
//             per def and preserves adjacency via order in the module decl list.
//   PyCenum : `[decorators] enum Name [typarams]: <case suite>` — a datatype/ADT (§5.7).
//             Each `case` line is a pydatacon. Decorators select the memory/repr mode.
//   PyCstruct : `[decorators] struct Name [typarams]: <field suite>` — a record (§5.7).
//   PyCtype : `[decorators] type Name [typarams] = <type>` — a type ALIAS only (§5.7);
//             the `enum`/`struct` keywords carry the datatype/record roles.
//   PyCimport : `import modpath` or `from modpath import (*|names)`.
//   PyCstmt : a statement appearing at module top level (module init may contain
//             statements — §5.2 decl includes stmt). Wraps a pystmt.
//   PyCerror : a declaration we could not parse (recovery).
//
and
pydecl =
| PyCfun    of (loctn, strn, list(pytyparam), list(pyparam), pytypopt, list(pystmt))
| PyCenum   of (loctn, list(pydecorator), strn, list(pytyparam), list(pydatacon))   // enum: case suite
| PyCstruct of (loctn, list(pydecorator), strn, list(pytyparam), list(pyfield))     // struct: field suite
| PyCtype   of (loctn, list(pydecorator), strn, list(pytyparam), pytyp)             // type: ALIAS ONLY
| PyCexcept of (loctn, strn, list(pytyp))   // exception E(T1,T2): an exception constructor (EXN)
| PyCimport of (loctn, pyimport)
| PyCstmt   of (loctn, pystmt)
| PyCerror  of (loctn, strn)
//
// a data constructor in a datatype sum (an `enum` `case`): UIDENT [ '(' arg-types ')' ] (§5.7).
and
pydatacon =
| PyDataCon of (loctn, strn, list(pytyp))
//
// an import: `import modpath` or `from modpath import (* | names)` (§5.2).
//   modpath is a dotted LIDENT path OR a STRING path literal — we keep the raw
//   segments / string lexeme. `star = true` ⇒ `import *`; else the named LIDENTs.
and
pyimport =
| PyImpModule of (loctn, list(strn))
| PyImpFrom   of ( loctn
                 , list(strn)
                 , bool
                 , list(strn) )
//
(* ****** ****** *)
//
// ==================================================================
//  Optionals. The prelude's `optn` is DEPENDENTLY-TYPED (indexed by a present/absent
//  boolean), which is awkward to pattern-match in a transpiled standalone DATS (same
//  dependent-type friction M1 hit with strn_get$at). We instead define three small
//  NON-dependent, monomorphic option datatypes — trivially matchable, fully additive,
//  and guaranteed to transpile cleanly. (A parametric pyopt(a) would also work but the
//  compiler's own ASTs favor concrete nodes; we mirror that.)
// ==================================================================
//
and pyexpopt = PyExpNone of () | PyExpSome of pyexp
and pytypopt = PyTypNone of () | PyTypSome of pytyp
and pystmtlstopt = PyElseNone of () | PyElseSome of list(pystmt)
//
// list aliases — declared AFTER the datatype block so each element type is the fully
// boxed datatype (a forward #typedef before the block resolves the element to an
// impredicative `type` and breaks L3 list packing — verified). Used by the parser
// signatures + printer below.
//
#typedef pyexplst = list(pyexp)
#typedef pypatlst = list(pypat)
#typedef pytyplst = list(pytyp)
#typedef pystmtlst = list(pystmt)
#typedef pydeclst = list(pydecl)
//
//
(* ****** ****** *)
//
// ==================================================================
//  pymodule — the whole parsed file: a decl list + recovery diagnostics.
// ==================================================================
//
// A parse diagnostic: a message + the span it was reported at. Severity is implicit
// (all are recoverable parse errors in M2). The harness dumps these after the AST so
// a malformed file shows BOTH the partial AST and what went wrong.
//
datatype
pydiag =
| PyDiag of (loctn, strn)
//
#typedef pydiaglst = list(pydiag)
//
datatype
pymodule =
| PyModule of (list(pydecl), list(pydiag))
//
(* ****** ****** *)
//
// ==================================================================
//  Location accessors — every node carries a loctn; expose a uniform getter so the
//  printer / downstream passes can fetch a node's span without re-matching.
// ==================================================================
//
fun pyexp_loctn(e: pyexp): loctn
fun pypat_loctn(p: pypat): loctn
fun pytyp_loctn(t: pytyp): loctn
fun pystmt_loctn(s: pystmt): loctn
fun pydecl_loctn(d: pydecl): loctn
//
(* ****** ****** *)
//
// ==================================================================
//  Parser state + INTERNAL cross-file entries.
// ==================================================================
//
// The parser threads a `pstate` BY VALUE (functional, re-entrant): the remaining
// token stream + the reversed accumulated diagnostics. Each parse function takes a
// pstate and returns @(node, pstate'). No global mutable state (plan §6.2).
//
//   toks  : the remaining pytokens (head = the lookahead token).
//   rdiag : recovery diagnostics accumulated so far, in REVERSE (newest first).
//
datatype
pstate =
| PState of (pytokenlst, pydiaglst)
//
// The parser is split across three DATS to mirror the lowering split:
//   pyparsing_staexp.dats — TYPES + PATTERNS (the "static"-ish surface).
//   pyparsing_dynexp.dats — EXPRESSIONS + STATEMENTS/SUITES (mutually recursive).
//   pyparsing_decl00.dats — DECLARATIONS + module + the public entries.
// The cross-file boundaries are these SATS-declared entries so the DATS can call each
// other without one giant `and`-group:
//
//   parse_type  : parse one surface type        (staexp; used by dynexp + decl00).
//   parse_pattern : parse one surface pattern    (staexp; used by dynexp + decl00).
//   parse_expr  : parse one surface expression   (dynexp; used by staexp guards? no —
//                 used by decl00 for let/import; types/patterns do NOT call it).
//   parse_suite : parse a suite (inline simple-stmt OR INDENT block) given we are
//                 positioned right AFTER the ':'/'=>' opener (dynexp; used by decl00
//                 for def bodies).
//   parse_decl  : parse one top-level/stmt-position declaration (decl00; def/type/
//                 import — used by dynexp when a stmt is actually a decl).
//
fun parse_type(st: pstate): @(pytyp, pstate)
fun parse_pattern(st: pstate): @(pypat, pstate)
fun parse_expr(st: pstate): @(pyexp, pstate)
fun parse_suite(st: pstate): @(pystmtlst, pstate)
fun parse_decl(st: pstate): @(pydecl, pstate)
//
// parse_stmt: one full statement (block stmt consumes its own suite+layout; a simple
// stmt is terminated by NEWLINE). Used at module top level (decl00) and inside suites
// (dynexp's own loop). Implemented in dynexp.
fun parse_stmt(st: pstate): @(pystmt, pstate)
//
// ---- shared token-stream + recovery utilities (pyparsing_util.dats) ----------
//
// peek the lookahead node (PT_EOF if the stream is exhausted — defensive).
fun ps_peek(st: pstate): ptnode
// peek the lookahead token's loctn (a dummy at EOF).
fun ps_peek_loctn(st: pstate): loctn
// the token one ahead (for 2-token lookahead, e.g. `let mut`).
fun ps_peek2(st: pstate): ptnode
// advance past the lookahead token (no-op at EOF).
fun ps_advance(st: pstate): pstate
// is the lookahead PT_EOF?
fun ps_at_eof(st: pstate): bool
// record a recovery diagnostic at `loc` with message `msg`; returns the new state.
fun ps_diag(st: pstate, loc: loctn, msg: strn): pstate
// skip layout NEWLINE/INDENT/DEDENT tokens at the head (used between decls etc.).
fun ps_skip_newlines(st: pstate): pstate
// resynchronize after an error: drop tokens up to and including the next NEWLINE, OR
// stop at a DEDENT/EOF (do NOT consume those — they close the enclosing suite).
fun ps_resync(st: pstate): pstate
//
// combine two spans into one covering both (min pbeg .. max pend) — the span-merge
// the task calls `loc1 + loc2`. Wraps the verified `add_loctn_loctn` (locinfo.sats)
// by name (avoids any `+`-overload-resolution risk in a standalone DATS).
fun loc_span(l1: loctn, l2: loctn): loctn
//
(* ****** ****** *)
//
// ==================================================================
//  The parser entries (frontend/DATS/pyparsing_*.dats). PURE per call.
// ==================================================================
//
// `pyparse_module(src, text)` is the one-shot entry: lex (pylex_layout) + parse, into
// a `pymodule` (decls + recovery diagnostics). NEVER throws; a malformed file yields a
// partial AST + diagnostics. `src` is stamped into the lexer spans.
//
fun
pyparse_module
(src: lcsrc, text: strn): pymodule
//
// Lower-level entry: parse an already-lexed token stream (so callers that already have
// tokens — e.g. the LSP — don't re-lex). The `pytokenlst` MUST be a pylex_layout
// stream (INDENT/DEDENT/NEWLINE present, ending in PT_EOF).
//
fun
pyparse_tokens
(toks: pytokenlst): pymodule
//
(* ****** ****** *)
//
// ==================================================================
//  The PyAST pretty-printer (frontend/DATS/pyparsing_print.dats) — golden tests +
//  downstream debugging. S-expression-ish, one construct per parenthesized form, with
//  `@span` on every node so the goldens PROVE real spans flow everywhere.
// ==================================================================
//
fun pybop_fprint(out: FILR, op: pybop): void
fun pyuop_fprint(out: FILR, op: pyuop): void
fun pylit_fprint(out: FILR, lit: pylit): void
fun pytyp_fprint(out: FILR, t: pytyp): void
fun pypat_fprint(out: FILR, p: pypat): void
fun pyexp_fprint(out: FILR, e: pyexp): void
fun pystmt_fprint(out: FILR, s: pystmt): void
fun pydecl_fprint(out: FILR, d: pydecl): void
fun pydiag_fprint(out: FILR, g: pydiag): void
//
// dump a whole module (decls, then a `==== diagnostics ====` section) to `out`.
fun pymodule_fprint(out: FILR, m: pymodule): void
//
(* ****** ****** *)
(*
end of [frontend/SATS/pyparsing.sats]
*)
