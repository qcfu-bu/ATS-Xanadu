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
//             (a bare `Int` is `PyTcon("Int", [])`; `List[Int]` carries one arg.) DEP: a type-app
//             arg list `Vec[A, n]` / `Vec[Int, 0]` may MIX type args (`A`, `Int` — PyTcon) and
//             INDEX args (a literal `0` -> PyTidx; a variable `n` -> PyTvar). The index-vs-type
//             distinction is resolved at LOWERING (a digit -> s2exp_int; a bound index s2var ->
//             s2exp_var via resolve_typ's S2ITMvar arm), not in the AST shape.
//   PyTvar  : LIDENT — a type variable (`a`, `b`) OR an INDEX variable (`n`, bound by an enclosing
//             `[n: SInt]` quantifier). Both are lowercase names; resolve_typ's S2ITMvar arm yields
//             s2exp_var of WHATEVER s2var the name is bound to (type-sorted or int/bool-sorted).
//   PyTidx  : an INT index LITERAL in a dependent type (e.g. `Vec[A, 0]` size). DEP: the parser
//             emits this for a bare digit in a type-arg list (PT_INT); lowering -> s2exp_int(k).
//   PyTbin  : a STATIC-ARITHMETIC index binop in a dependent type (DEP follow-up): `n+1`, `i-1`,
//             `n*2`, and the comparisons `i<n`, `n>=0`, `n==m` (carries a `pybop` tag + the two
//             index operands). Reachable ONLY inside a type-arg bracket `Vec[A, n+1]` or a
//             quantifier guard `{n | n>=0}`. Lowering maps the tag to a prelude STATIC `*_i0_i0`
//             const (add_i0_i0/lt_i0_i0/...) and emits `s2exp_apps(<const>, [a, b])`.
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
| PyTbin   of (loctn, pybop, pytyp, pytyp)
// ARROW-EFFECTS (bootstrap P1): a function type `(A) -> B` (bare) or `(A) ->[Tag] B`. The
// trailing `strn` carries the VERBATIM CamelCase arrow tag (`CloRef1`, `Fun0`, `CloPtr1`, ...) for
// round-trip; the EMPTY string `""` = the bare `->` (unchanged). The tag's CLASS part drives the
// lowered f2clknd (CloRef/Fun -> F2CLfun cloref ; CloPtr -> F2CLclo linear) — the effect digit is
// cosmetic (erased at the s2exp level). See pylower_staexp PyTfun arm + the arrow-spike (AR-DIST
// proved the class IS structurally enforced: an F2CLclo(1) value is rejected at an F2CLfun param).
| PyTfun   of (loctn, list(pytyp), pytyp, strn(*arrow tag; ""=bare*))
| PyTtup   of (loctn, list(pytyp))
| PyTrec   of (loctn, list(pytfield))
// A-QUANT: an EXPLICIT quantified type — `forall[n: SInt | g] <type>` (universal) or
// `exists[m: SInt | m <= n] <type>` (existential). The `int` tag is 0=forall / 1=exists.
// The binder list `list(pytyparam)` + the OPTIONAL guard `pyguardopt` reuse the EXISTING
// def-param quantifier grammar (`[n: SInt | g]`); the body is a recursive `pytyp`. Lowers to
// s2exp_uni0 (forall) / s2exp_exi0 (exists) — both proven structurally (dep-spike P2/P3 for
// uni0/guards; a-quant SX-EXI for exi0).
| PyTquant of (loctn, int(*0=forall,1=exists*), list(pytyparam), pyguardopt, pytyp)
// B-LINEAR: the AT-VIEW relation `A at l` — the carried type `A` is held AT the address `l`.
// A postfix `at`-relation in a type (keyword `at`; SPIKE BL-AT2 proved S2Eatx2 rides clean).
// The first `pytyp` is the carried type, the second is the address expression (a `pytyp` —
// usually a `PyTvar` naming an `addr`-sorted quantifier). Lowers to the at-view s2exp
// `S2Eatx2(carried, addr)` of result sort `the_sort2_vwtp`. (`view` sort reserved.)
| PyTat    of (loctn, pytyp(*carried*), pytyp(*addr*))
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
//   PyPcon   : UIDENT [ '{' sargs '}' ] [ '(' args ')' ] — constructor pattern; nullary `Leaf`
//              has no value args. C-PROOF: the OPTIONAL `{ sargs }` between the con name and the
//              value-arg parens is the EXISTENTIAL-UNPACK static-arg list (`VCons{n}(x, rest)` —
//              the `{n}` BINDS the con's hidden index var into the arm scope). `list(strn)` = the
//              static binder NAMES (`[]` = a plain con pattern, no unpack).
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
| PyPcon   of (loctn, strn, list(strn)(*sargs*), list(pypat))
| PyPtup   of (loctn, list(pypat))
| PyPrec   of (loctn, list(pypfield))
| PyPlit   of (loctn, pylit)
| PyPas    of (loctn, pypat, strn)
| PyPann   of (loctn, pypat, pytyp)
// B-LINEAR: the LINEAR-CONSUME pattern `~p` — frees/consumes the matched linear value.
// The inner `pypat` is the con-pattern being consumed (`~VCons(x, rest)`). Lowers to the
// D2Pfree node wrapping the inner pattern (SPIKE BL-LIN proved f0_free is a pass-through).
| PyPfree  of (loctn, pypat)
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
//   PyEop    : `(+)` / `(<)` — an OPERATOR used as a first-class VALUE (Scala/Haskell parenthesized-
//              operator form; was the removed `op+` keyword syntax). The strn is the operator's symbol
//              ("+", "<", ...), the SAME name `bop_sym`/`uop_sym` give the call-head path; the
//              elaborator maps it to `PCEvar(loc, name)` so M3's `pl_var` resolves it (the operator's
//              prelude overload symbol -> a d2exp_sym0 value). So `reduce(xs, (+))` passes `+` as a
//              `(Int,Int)->Int` value; `let f = (+)` then `f(1,2)` works. The parser disambiguates
//              `(+)` (an OPERATOR token between the parens) from a parenthesized expression `(e)`.
| PyEop    of (loctn, strn)
//   PyEaddr  : `&x` — ADDRESS-OF (B-LINEAR). Takes the address of an l-value (a var cell).
//              Lowers to D2Eaddr; the result is a `ptr(typ-of-x)` (SPIKE BL-ADDR, nerror=0).
//   PyEderef : `!p` — DEREFERENCE in EXPRESSION position (B-LINEAR). Reads the pointee of `p`.
//              Lowers to D2Eeval; on an element-typed pointer (e.g. from `&x`) it peels the
//              element type (SPIKE BL-DERF2, nerror=0). `!p` in a PATTERN position is unfold —
//              a DISTINCT, deferred feature; this is the expr-position deref only.
| PyEaddr  of (loctn, pyexp)
| PyEderef of (loctn, pyexp)
//   PyEderefcell : `r[]` — read THROUGH a first-class ref CELL (GAP B, DYNAMIC P1 feature 5).
//              The EMPTY-bracket subscript `r[]` (no index) — DISTINCT from `PyEindex` (`r[i]`,
//              array indexing). ATS's pervasive `a0ref` deref: the elaborator maps it to the
//              prelude `a0ref_get(r)` call (re-exported in pyrt.sats). In an LVALUE position
//              `r[] := e`, the PySassign elaborator instead maps `r[]` to `a0ref_set(r, e)`.
| PyEderefcell of (loctn, pyexp)
//   PyEinst  : `@inst[T1, T2, ..] e` — an EXPRESSION-position TEMPLATE INSTANTIATION decorator
//              (A-template). `@inst` is our FIRST non-declaration decorator: it carries a list of
//              type-ARG USES (the `[T1,T2,..]` brackets, a `list(pytyp)`) and the following
//              EXPRESSION `e` it instantiates. The surface `@inst[Int] foo(x)` ATS-lowers to
//              `foo<Int>(x)` = `D2Edapp(d2exp_tapp(foo, [Int]), -1, [x])` (the tapp wraps the
//              CALLEE, nested inside the value-app). If `e` is a bare head (not a call), it lowers
//              to a plain `d2exp_tapp(e, [Int])` (no value-app). `@` stays decorators-only on the
//              surface, so there is no collision with any operator.
| PyEinst  of (loctn, list(pytyp), pyexp)
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
// a decorator: @name  (§5.7) — e.g. @linear, @unboxed, @boxed. A-TEMPLATE: a decorator may now
// carry an OPTIONAL `[…]` ARG PAYLOAD, dispatched by the decorator NAME at parse time:
//   * `@template[A, B]`   — type-param BINDERS (`pydecoargs = PyDAbinders`): these BIND fresh type
//                           vars (possibly sort-annotated `[A: Type]`), parsed with the def typaram
//                           parser. They become the template d2cst's `tqas` (the `fun{A,B}` args).
//   * `@impl[Int, Bool]`  — type-arg USES (`pydecoargs = PyDAtypes`): type EXPRESSIONS like `Int` /
//   * `@inst[Int, ..]`      `List[Int]`, parsed with the type-arg parser. `@impl[…]` -> the impl's
//                           `tias` (instantiation list); `@inst[…]` -> the call-site `<…>` brackets.
//   * every OTHER decorator (@proof/@extern/@impl-without-brackets/@linear/…) carries `PyDAnone`
//     (no payload — byte-identical to before this slice).
// The payload rides on PyDecor as a THIRD field so the existing per-name routing (decos_has, the
// mode/variant dispatch) is unchanged; only the new template paths read the payload.
// PyDAprec — a `@overload[N]` PRECEDENCE payload (a single INT literal, the `#symload … of N`
// resolution precedence). UNLIKE PyDAbinders/PyDAtypes (which carry type-level lists), this is a
// plain int; only the overload-ALIAS path reads it (decos_overload_prec). A bare `@overload`
// (no bracket) carries PyDAnone -> the default precedence at lowering.
and pydecoargs   = PyDAnone of () | PyDAbinders of list(pytyparam) | PyDAtypes of list(pytyp)
                 | PyDAprec of (loctn, sint)
and pydecorator  = PyDecor of (loctn, strn, pydecoargs)
// the optional sort annotation on a type param (Type/Linear/Prop/… — OPEN vocab, kept as strn)
and pysortopt   = PySortNone of () | PySortSome of (loctn, strn)
// a type parameter:  UIDENT [ ':' SORT ] { DECORATOR }   (§5.7)
//   DEP (guards): a quantifier `[A, n: SInt | n >= 0]` may carry an OPTIONAL bool-index GUARD
//   after the binder(s) (a `pytyp` built from PyTbin comparisons). The `pyguardopt` slot rides on
//   the typaram the `|` follows (we attach it to the binder immediately before the `|`). The guard
//   is PARSE-ONLY for a def (the def quantifier `t2qag` has NO prop slot; guards are dropped at
//   stpize — matching stock) but is CHECKED-or-dropped uniformly; it must lower without crashing.
and pyguardopt  = PyGuardNone of () | PyGuardSome of (loctn, pytyp)
and pytyparam    = PyTyParam of (loctn, strn, pysortopt, list(pydecorator), pyguardopt)
// a struct field:  LIDENT ':' type   (§5.7)
and pyfield      = PyField of (loctn, strn, pytyp)
//
(* ****** ****** *)
//
// ==================================================================
//  pystmt — the surface STATEMENT language (§5.3). KEPT FAITHFUL for M2.5.
// ==================================================================
//
//   PyDlet      : `[@decorators] let [mut] pat [: T] = e` — the `bool` is the MUT FLAG (true = mut).
//                 This is the linchpin M2.5 keys on (LOOP-DESUGARING §1). DECORATOR REWORK: a
//                 `list(pydecorator)` rides on the front (default `[]` = a plain `let`); `@proof let`
//                 carries `[@proof]` so the elaborator lowers it like the old `prval` (VLKprval).
//   PySvar      : `var NAME [: T] = e` — a MUTABLE CELL declaration (ATS-parity var/
//                 mutation). DISTINCT from `PyDlet(mut=true)`: `let mut` is an SSA-
//                 rebindable functional binding the loop elaborator THREADS as an
//                 accumulator; a `var` is an aliasable IN-PLACE cell that is NOT threaded.
//                 Binder is a bare NAME (LIDENT; field/index lvalues are a later slice),
//                 with an optional type annotation and a mandatory init expression.
//   PySassign   : `lvalue := e` — a CELL ASSIGNMENT (the `:=` operator). DISTINCT from
//                 `PySreassign` (the `=` SSA reassign). The lvalue is a `pyexp` (a var
//                 NAME for v1; field/index later) so the elaborator inspects it; it lowers
//                 to L2 `D2Eassgn` and returns void.
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
| PyDlet      of (loctn, list(pydecorator), bool, pypat, pytypopt, pyexp)
| PySvar      of (loctn, strn, pytypopt, pyexp)
| PySassign   of (loctn, pyexp(*lval*), pyexp(*rval*))
// B-LINEAR: MOVE `x :=> y` (consume y into x) and SWAP `x :=: y`. Statement-level siblings of
// PySassign — distinct operators (PT_MOVE / PT_SWAP). Lower (via PCEmove/PCEswap) to D2Exazgn /
// D2Exchng (SPIKE BL-MV / BL-SW, both nerror=0). They pair with `var` cells (already shipped).
| PySmove     of (loctn, pyexp(*lval*), pyexp(*rval*))
| PySswap     of (loctn, pyexp(*lval*), pyexp(*rval*))
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
//   PyCfun  : `[@decorators] def name [typarams] (params) [-> Ret]: <suite>`. Carries the
//             decorator list (default `[]` = a plain def), the name (LIDENT), optional type
//             params (rich pytyparam list — §5.7), value params, optional return type, and the
//             body suite. Recursion grouping (adjacent defs = one mutually-recursive group, §5.2)
//             is M3's concern; M2 emits one PyCfun per def and preserves adjacency via order in
//             the module decl list. DECORATOR REWORK: the ATS-specific def VARIANTS that used to
//             be dedicated keywords are now decorators on this base node — `@proof def` (was
//             `prfun`), `@extern def` (was `extern def`), `@proof @extern def` (was `praxi`),
//             `@impl def` (was `implement`), `@overload def` (was `overload`). The elaborator
//             (pyelab_decl) inspects the decorators and routes to the SAME PyCore variant the
//             keyword version produced (PCCprfun/PCCextern/PCCpraxi/PCCimplement/PCCoverload).
//             An undecorated `def` is a plain PCCfun.
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
//   SCOPING (bootstrap P1): PyCfun gains a TRAILING `list(pydecl)` WHERE-field — the decls of an
//   optional `where:` block at the def's indent level (default `[]` = no where-block). The
//   where-decls are BACKWARDS-scoped around the def BODY (ATS `e where {decls}`); the elaborator
//   WRAPS the def's body expr in a PCEwhere(body, <elaborated where-decls>) PyCore expr, and M3
//   lowers PCEwhere -> D2Ewhere(body, where_decls). (where IS an expression form, so it lives on the
//   body expr — no PCCfun/fungroup-lowering changes.) SPIKE-PROVEN (S1).
| PyCfun    of (loctn, list(pydecorator), strn, list(pytyparam), list(pyparam), pytypopt, list(pystmt), list(pydecl)(*where*))
//   SCOPING (bootstrap P1): PyCprivate carries a RUN of `private` decls — either a single
//   `private def …` modifier (one-element run) or a `private:` block (the indented suite). The
//   MODULE/SUITE lowering applies the capture-rest transform: the privates become the local-HEAD
//   (D1) and ALL following sibling decls become the local-BODY (D2) of a D2Clocal0(D1, D2) — so the
//   privates are visible to D2 but NOT exported past it. SPIKE-PROVEN (S2).
| PyCprivate of (loctn, list(pydecl)(*private decls*))
//   PyCenum : `[decorators] enum Name [typarams]: <case suite>` — a datatype/ADT (§5.7).
//   DECORATOR REWORK (slice 2): the @prop / @view decorators turn a plain `enum` into the old
//   `dataprop` / `dataview` (a PROOF / VIEW datatype) — the elaborator routes them to PCCdata
//   carrying the PCMprop / PCMview mode, so M3's dt_sort_of picks the_sort2_prop / the_sort2_view
//   (DEP-spike P4/P9). No dedicated AST node: a `@prop enum` IS a PyCenum (the case-suite shape is
//   identical to a plain enum); the prop/view kind is selected at elaboration from the decorators.
| PyCenum   of (loctn, list(pydecorator), strn, list(pytyparam), list(pydatacon))   // enum: case suite
| PyCstruct of (loctn, list(pydecorator), strn, list(pytyparam), list(pyfield))     // struct: field suite
| PyCtype   of (loctn, list(pydecorator), strn, list(pytyparam), pytyp)             // type: ALIAS ONLY
//   PyCabstype : `[decorators] abstype Name [typarams]` — an OPAQUE type declaration (ATS-parity).
//                No `= T` body (opacity); decorators select the box/flat sort (@boxed/none->tbox,
//                @unboxed->tflt; @linear deferred). M3 lowers it to D2Cabstype(s2cst, A2TDFsome()).
//   PyCassume  : `assume Name = T` — gives an abstract type its hidden representation T (ATS-parity).
//                M3 selects the abstract s2cst by name, lowers T via pylower_typ -> D2Cabsimpl.
//
//   DECORATOR REWORK: the former PyCextern / PyCimplement / PyCoverload (the keyword `extern def` /
//   `implement` / `overload` surface nodes) were REMOVED. Those variants are now @decorators on a
//   plain `def` (PyCfun): `@extern def` / `@impl def` / `@overload def`. The elaborator inspects the
//   def's decorators and routes to the SAME PyCore variant they used to (PCCextern / PCCimplement /
//   PCCoverload), so the PROVEN L2 lowering is reused unchanged.
| PyCabstype of (loctn, list(pydecorator), strn, list(pytyparam))
| PyCassume  of (loctn, strn, pytyp)
| PyCexcept of (loctn, strn, list(pytyp))   // exception E(T1,T2): an exception constructor (EXN)
//   PyCsortdef : `sortdef Name = SORT` — a SORT ALIAS (ATS-parity `sortdef`). Carries the
//                alias NAME (UIDENT) + the right-hand SORT-reference NAME (a sort vocab
//                string like `SInt`/`Type`/`Prop`, mapped by lowering via the sort vocab).
//                M3 lowers it to D2Csortdef(name, S2TEXsrt(<sort2>)) + tr12env_add0_s2tex.
//   PyCstacst  : `stacst Name : SORT` — a STATIC CONSTANT of a sort (ATS-parity `stacst`).
//                Carries the constant NAME + its SORT-reference NAME. M3 lowers it to
//                D2Cstacst0(s2cst_make_idst(...), <sort2>) + tr12env_add1_s2cst.
//   PyCstadef  : `stadef Name = <static-expr>` — a STATIC-LEVEL DEFINITION (ATS-parity
//                `stadef`). v1 supports a static INT literal body (`stadef Two = 2`). Carries
//                the NAME + the body expression. M3 lowers it via build_sexpdef restricted to
//                a static int (the index-lit lowering -> s2exp_int).
//   PyCsortsub : `@sort type Nat = {a: SInt | a >= 0}` — a SUBSET (refined) SORT (ATS-parity
//                `sortdef Nat = {a:int | a >= 0}`). Carries the alias NAME (UIDENT), the BINDER
//                (a `pytyparam`, e.g. `a: SInt` — its sort is the carrier) + the guard list (a
//                `list(pytyp)` of bool-index predicates). M3 lowers it to D2Csortdef(name,
//                S2TEXsub(<binder s2var>, [<lowered guards>])) + tr12env_add0_s2tex (a-quant
//                SX-SUB-proven). The plain sort-alias form stays PyCsortdef (byte-identical).
| PyCsortdef of (loctn, strn(*name*), strn(*sort-ref*))
| PyCsortsub of (loctn, strn(*name*), pytyparam(*binder*), list(pytyp)(*guards*))
| PyCstacst  of (loctn, strn(*name*), strn(*sort-ref*))
| PyCstadef  of (loctn, strn(*name*), pyexp(*static body*))
//   DECORATOR REWORK: the former PyCprfun / PyCprval / PyCpraxi (the keyword `prfun` / `prval` /
//   `praxi` surface nodes) were REMOVED. Those PROOF variants are now @decorators on a plain
//   `def`/`let`: `@proof def` (was prfun), `@proof let` (was prval), `@proof @extern def` (was
//   praxi — proof + bodyless). The elaborator inspects the decorators and routes to the SAME
//   PyCore variant they used to (PCCprfun / PCCprval / PCCpraxi), reusing the proven L2 lowering.
| PyCimport of (loctn, pyimport)
//   PyCsymalias : a STANDALONE overload-ALIAS decl `@overload NAME = TARGET` (+ optional
//                 `@overload[N]` precedence) — the ATS-parity `#symload NAME with TARGET [of N]`.
//                 There is NO `def` here: it RE-EXPORTS an already-existing function TARGET into
//                 the overload set of a DIFFERENT symbol NAME (the 2012× corpus form). Carries the
//                 overloaded NAME, the TARGET name, and the precedence (`~1` = none given). The
//                 elaborator passes it straight through to PCCsymalias; M3 lowers it via the SAME
//                 build_overload recipe PCCoverload uses (but with the parsed precedence as pval).
| PyCsymalias of (loctn, strn(*name*), strn(*target*), sint(*precopt; ~1 = none*))
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
// DEP (static arithmetic + guards): parse ONE index-expression (the binop grammar over index
// literals/vars + `+ - * < <= > >= == !=`, with the usual precedence) into a `pytyp` (PyTbin /
// PyTidx / PyTvar / PyTcon). Reachable inside type-arg brackets (`Vec[A, n+1]`) via the type
// parser and at a quantifier GUARD (`[n: SInt | n >= 0]`) via the decl parser. (staexp; used by
// decl00 for the guard.)
fun parse_index_type(st: pstate): @(pytyp, pstate)
// A-QUANT: parse a `[ binder {, binder} [ '|' guard ] ]` TYPE-PARAMETER bracket — the SAME grammar
// a `def foo[A, n: SInt | g]` quantifier uses (p_typarams). Lives in decl00 (where p_typaram is in
// scope); used by staexp's `forall`/`exists` type-quantifier production. Empty if the bracket is
// absent. The guard, if present, rides on the LAST binder (PyGuardSome) — the caller hoists it.
fun parse_typarams(st: pstate): @(list(pytyparam), pstate)
fun parse_pattern(st: pstate): @(pypat, pstate)
// A-TEMPLATE: parse a decorator's `[ type {, type} ]` TYPE-ARG payload (the `@impl[Int, Bool]` /
// `@inst[Int, ..]` brackets — type USES, NOT binders). The lookahead MUST be PT_LBRACK; we consume
// the matching PT_RBRACK. Each element is a full surface type (reuses the staexp type-arg grammar,
// so `Int` / `List[Int]` / a bare index all parse). Lives in staexp (where parse_type is in scope);
// used by BOTH decl00 (@impl decorator payload) and dynexp (@inst expr decorator payload).
fun parse_deco_typeargs(st: pstate): @(list(pytyp), pstate)
fun parse_expr(st: pstate): @(pyexp, pstate)
fun parse_suite(st: pstate): @(pystmtlst, pstate)
fun parse_decl(st: pstate): @(pydecl, pstate)
//
// SCOPING (bootstrap P1): the decl-block + private helpers (all in decl00). Declared here so they
// are GLOBALLY resolvable — p_def (an EARLY group) forward-calls p_decl_block, and p_decl_block_loop
// / p_private forward-call p_top_item, across separate `fun` groups in the same file.
//   p_top_item       : parse ONE top-level item (a decl, or a stmt-as-decl). Consumes per-decl layout.
//   p_decl_block     : a `where:`/`private:` SUITE-OF-DECLS — NEWLINE INDENT decl* DEDENT.
//   p_decl_block_loop: the decl-block body loop (until DEDENT/EOF), one p_top_item per entry.
//   p_private        : a `private` run — a `private:` block or a single `private <decl>` modifier.
fun p_top_item(st: pstate): @(pydecl, pstate)
fun p_decl_block(st: pstate): @(pydeclst, pstate)
fun p_decl_block_loop(st: pstate): @(pydeclst, pstate)
fun p_private(st: pstate): @(pydecl, pstate)
//
// parse_stmt: one full statement (block stmt consumes its own suite+layout; a simple
// stmt is terminated by NEWLINE). Used at module top level (decl00) and inside suites
// (dynexp's own loop). Implemented in dynexp.
fun parse_stmt(st: pstate): @(pystmt, pstate)
//
// DECORATOR REWORK: parse a `let [mut] pat [: T] = e` binding with the given PREFIX decorators
// already consumed by the caller (decl00's parse_decl, which parses the `@proof` etc.). The
// lookahead MUST be PT_KW_LET. Implemented in dynexp (it owns the let-binding grammar); used by
// decl00 to build a `@... let` decl (wrapped as PyCstmt). NO trailing NEWLINE is consumed.
fun parse_let_decos(st: pstate, decos: list(pydecorator)): @(pystmt, pstate)
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
// ROBUSTNESS (Bug #41): a module-local recursion-DEPTH guard for the nested-bracket grammar
// (the `[ … ]` type-application / decorator type-arg / @inst expression payloads). The
// recursive-descent type/expr parser has NO native-stack bound, so a deeply/badly nested
// payload (`@inst[@inst[@inst[…`, `List[List[List[…`, `foo(@inst[@inst[…`) overflows the JS
// native stack and SEGFAULTS (EXIT 139) instead of producing a clean diagnostic. These three
// primitives bound the descent:
//   ps_depth_reset() : zero the counter at the top-level parse entry (pyparse_tokens).
//   ps_depth_enter() : increment + return true IFF we have just CROSSED the limit (the caller
//                      must then emit a diagnostic + a survivable error node + NOT recurse).
//   ps_depth_leave() : decrement on the way back out of a bracketed descent.
// The guard is a template-free module-local sint ref (the proven `a0ref_make_1val(0)` pattern,
// xglobal.dats:170 `the_ntime`); the parser is one-shot per file so a module-local counter is
// re-entrant-safe across files via ps_depth_reset() at the entry.
fun ps_depth_reset((*void*)): void
fun ps_depth_enter((*void*)): bool
fun ps_depth_leave((*void*)): void
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
fun pybop_fprint(out: FILR, b: pybop): void
fun pyuop_fprint(out: FILR, u: pyuop): void
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
