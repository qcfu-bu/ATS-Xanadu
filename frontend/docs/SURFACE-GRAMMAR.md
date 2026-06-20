# Surface grammar — the Python/Scala fusion (decisions log)

> Companion to **PYTHON-FRONTEND-PLAN.md**. This is the canonical home for surface-
> syntax decisions. **Bindings, functions/lambdas, and the layout rule are settled**
> here; operators/precedence and the dependent-type surface are still evolving and
> are marked *open*. Semantics are always ATS3 (functional, expression-oriented);
> see LOWERING-MAP.md for how each form reaches L2, and LOOP-DESUGARING.md for the
> imperative-control-flow elaboration.

## Design stance

A **Python skeleton** (significant indentation, `def`, `match`, `f(a, b)` calls)
with **Scala fixes** for Python's rough edges: explicit binding keywords, an
expression-oriented core, and full-statement lambda bodies. Where Python and Scala
disagree, pick the form that keeps the grammar unambiguous and the core small.

---

## 1. Bindings — `let` / `let mut` (no declare/assign conflation)

Python conflates *declare* and *assign* (`x = e` does both, scoped by function).
We separate them:

| Form | Meaning |
|---|---|
| `let x = e` | **immutable** binding (the default; prefer this) |
| `let mut x = e` | **mutable** binding (reassignable) |
| `x = e` | **reassignment** — legal **only** if `x` was bound `let mut`, else an error |
| `let x = e2` (again) | **shadowing** — a *new* immutable binding (Rust-style), distinct from reassignment |

Rules:
- A bare `x = e` on an undeclared name, or on a `let` (immutable) name, is an
  **elaboration error** on the surface span ("cannot reassign immutable binding `x`"
  / "`x` is not declared"). No implicit declaration anywhere.
- `let mut` is a **binding-class** fact, not a memory model: it stays in the
  functional core. Reassignments and loop mutation are handled by the elaborator via
  SSA rebinding / accumulator threading (LOOP-DESUGARING §5) — `let mut` does **not**
  lower to an ATS `var`/cell. (ATS `var`/`:=` remains the escape hatch for genuinely
  aliasable memory; rarely needed.)
- `let`/`let mut` are **statements**: they bind for the remainder of the enclosing
  suite. They appear at module level and in any block.

```
let n = 10                  # immutable
let mut total = 0           # mutable
total = total + n           # ok: total is `let mut`
# n = 0                     # ERROR: n is immutable
let n = n + 1               # ok: shadows with a new immutable binding
```

---

## 2. Functions & lambdas — one notion of body

**There is a single notion of "function body": a suite** (an indented statement
block that yields its tail value or an explicit `return`). `def` and lambda share
it — a block lambda is simply an anonymous `def`, so it reuses the suite elaboration
+ function epilogue from LOOP-DESUGARING §5.4. This removes Python's def/lambda
asymmetry (Python lambdas are a single expression only).

- **Named:** `def name(params) -> Ret:` followed by an indented suite.
- **Anonymous:** `params => body`, where `params` is `(x: T, y)` or a single bare
  `x`, and `body` is **either** an inline expression **or** an indented suite opened
  by the arrow at end-of-line. The `lambda` keyword is **dropped**.

```
let inc = (x: Int) => x + 1              # inline-body lambda

let scaled =
  xs.map (x) =>                          # trailing block-bodied lambda
      let y = x * k
      y + 1                              # tail = the lambda's value

def clamp(x: Int, lo: Int, hi: Int) -> Int:
    if x < lo: lo
    elif x > hi: hi
    else: x
```

Both forms lower to `D2Elam0` (anonymous) / `D2Cfundclst` (named); the body is the
elaborated suite as a single `d2exp` (LOWERING-MAP §1/§4).

---

## 3. Blocks & layout — the uniform block-opener rule

Indentation is significant. A **block (suite)** is opened by a line ending in a
**block-opener token** and consists of the maximal run of following lines indented
**past the opener's reference column** (the "column offset" resolution):

- block-openers are **`:`** (statement headers: `def`, `if`/`elif`/`else`, `while`,
  `for`, `match`, `case`) and **`=>`** (a lambda whose body is on the next line).
- the layout pass maintains an indent stack of contexts; a line at ≤ the reference
  column closes contexts (emit `DEDENT`s) until it matches an enclosing one; EOF
  closes all open contexts.

**Brackets vs layout (the subtle case — block lambdas inside expressions).** Open
`(`/`[`/`{` suppress *statement* `NEWLINE`s (implicit line-join, as in Python), **but
a block-opener still opens a layout context** even inside brackets; when that block
closes, the surrounding bracket context resumes. This is what makes a **trailing
block lambda** as a call argument work:

```
result = data.fold(0) (acc, x) =>
    let v = step(acc, x)
    acc + v
```

**Bounding the complexity (recommendation):** block-bodied lambdas are idiomatic
(a) as a statement RHS and (b) as a call's **trailing/last** argument; a lambda used
mid-expression should use the **inline** `=>` form (parenthesize if needed). This is
Scala's pragmatic stance and keeps the layout/bracket interleaving tractable. *Open:
the exact trailing-lambda acceptance rule is finalized during M1–M2.*

---

## 4. Token roles (kept distinct on purpose)

| Token | Role(s) |
|---|---|
| `:` | type annotation (`x: T`, param/return positions) **or** statement block-header |
| `=>` | **lambda** (term-level) arrow — the only use |
| `->` | **type-level** arrow: function *types* (`(Int) -> Bool`) and `def` return type (`-> T`) |
| `=` | binding (`let …`) / reassignment |

Term arrow (`=>`) vs type arrow (`->`) are never the same token, so lambda values and
function types never collide. `:` is unambiguous by position (annotation sites vs the
end of a statement header).

---

## 5. Grammar (EBNF)

Notation: `|` alternation, `{ x }` zero-or-more, `[ x ]` optional, `( )` grouping,
`'…'` literal terminals, UPPERCASE = lexer tokens. `NEWLINE`, `INDENT`, `DEDENT` are
emitted by the layout pass (§3); inside `(`/`[`/`{`, `NEWLINE`s are suppressed but a
block-opener (`:` / `=>`) still opens a layout block. This grammar is **provisional
for v1** — the operator set (§5.6) and trailing-lambda rule (§3) finalize in M1–M2.

**Identifier case convention (load-bearing).** Initial case classifies identifiers,
Rust/Haskell-style, so the parser distinguishes a constructor from a binder *without*
consulting name resolution:

- **`UIDENT`** (uppercase initial) — a **type constructor** (`Int`, `List`, `Tree`)
  **or** a **data constructor** (`Leaf`, `Node`, `Some`).
- **`LIDENT`** (lowercase initial) — a **variable, function, type variable, or field**
  (`x`, `sum_tree`, `a`, `name`).
- `true` / `false` are **lowercase literal keywords** (like `42` / `"s"`), **not** data
  constructors — which is why they are lowercase even though `Leaf` / `Node` are not.

Consequences: in a **pattern**, a `UIDENT` is a constructor (must resolve to a `d2con`,
else "unknown constructor") and a `LIDENT` is a fresh binder — disambiguated by case
alone. In a **type**, a `UIDENT` is a type constructor and a `LIDENT` is a type variable.

> **Bridge to the ATS prelude.** The ATS prelude names its types/constructors in
> *lowercase* (`int`, `bool`, `list`, `list_cons`). The capitalized surface vocabulary
> (`Int`, `Bool`, `List`, `Cons`, …) is supplied by the **`pyrt`** prelude as aliases/
> re-exports over the ATS prelude (type aliases via `sexpdef`; thin datatype wrappers
> or re-exports for constructors). So a Python program resolves `Int`/`List`/`Some`
> against `pyrt` like any other name (plan §4 fall-through), while lowering-internal
> resolution against the *ATS* prelude correctly uses the lowercase names. Defining
> the exact `pyrt` vocabulary is an M2.5/M5 task.

### 5.1 Lexical

```
LIDENT   = lowerletter { letter | digit | '_' }     (* var / fun / type-var / field *)
UIDENT   = upperletter { letter | digit | '_' }     (* type- or data-constructor *)
INT      = digit {digit} | '0x' hex+ | '0o' oct+ | '0b' bin+
FLOAT    = digit+ '.' digit+ [ ('e'|'E') ['+'|'-'] digit+ ]
STRING   = '"' { strchar | escape } '"'
CHAR     = "'" ( char | escape ) "'"
COMMENT  = '#' { ¬newline }                         (* discarded *)
keywords = let mut def if elif else while for in match case
           break continue return import from type and or not true false '_'
```

### 5.2 Module & declarations

```
module    ::= { decl }
decl      ::= binding | funcdef | typedecl | import | stmt   (* module init may contain stmts *)

binding   ::= 'let' [ 'mut' ] pattern [ ':' type ] '=' expr NEWLINE

funcdef   ::= 'def' LIDENT [ typarams ] '(' [ params ] ')' [ '->' type ] ':' suite
params    ::= param { ',' param }
param     ::= LIDENT [ ':' type ]
typarams  ::= '[' LIDENT { ',' LIDENT } ']'          (* generics: def f[a](…) — type vars lowercase *)

typedecl  ::= 'type' UIDENT [ typarams ] '=' typedef NEWLINE     (* type name uppercase *)
typedef   ::= type                                   (* alias:  type Id = List[Int] *)
            | datacon { '|' datacon }                (* sum:    type Tree[a] = Leaf | Node(…) *)
datacon   ::= UIDENT [ '(' type { ',' type } ')' ]   (* data constructor uppercase *)

import    ::= 'import' modpath NEWLINE
            | 'from' modpath 'import' ( '*' | LIDENT { ',' LIDENT } ) NEWLINE
modpath   ::= LIDENT { '.' LIDENT } | STRING          (* dotted name or a path literal *)
```

> Adjacent `def`s at the same indentation form one **mutually-recursive group** (no
> special syntax) — so `is_even`/`is_odd` see each other. (Maps to a recursive
> `D2Cfundclst`; LOWERING-MAP §4.F.)

### 5.3 Statements & suites

```
suite     ::= simple_stmt NEWLINE                    (* inline:  if c: e *)
            | NEWLINE INDENT stmt { stmt } DEDENT     (* block *)

stmt      ::= binding | reassign | funcdef | typedecl
            | exprstmt | if_stmt | while_stmt | for_stmt | match_stmt
            | 'break' NEWLINE | 'continue' NEWLINE | 'return' [ exprs ] NEWLINE
simple_stmt ::= binding | reassign | exprstmt
            | 'break' | 'continue' | 'return' [ exprs ]

reassign  ::= lvalue '=' expr NEWLINE                (* lvalue must be a `let mut` name/place *)
lvalue    ::= LIDENT | postfix '.' LIDENT | postfix '[' expr ']'
exprstmt  ::= expr NEWLINE

if_stmt   ::= 'if' expr ':' suite { 'elif' expr ':' suite } [ 'else' ':' suite ]
while_stmt::= 'while' expr ':' suite [ 'else' ':' suite ]
for_stmt  ::= 'for' pattern 'in' expr ':' suite [ 'else' ':' suite ]
match_stmt::= 'match' expr ':' NEWLINE INDENT case_arm { case_arm } DEDENT
case_arm  ::= 'case' pattern [ 'if' expr ] ':' suite
```

### 5.4 Expressions

```
exprs     ::= expr { ',' expr }                      (* bare tuple in return/RHS: a, b ≡ (a, b) *)
expr      ::= lambda | if_expr | match_expr | or_expr
lambda    ::= lamparams '=>' lambody
lamparams ::= LIDENT | '(' [ param { ',' param } ] ')'
lambody   ::= expr | NEWLINE INDENT stmt { stmt } DEDENT     (* inline OR block — §2 *)
if_expr   ::= 'if' expr ':' branch { 'elif' expr ':' branch } 'else' ':' branch
match_expr::= 'match' expr ':' NEWLINE INDENT case_arm { case_arm } DEDENT
branch    ::= expr | NEWLINE INDENT stmt { stmt } DEDENT

(* precedence: lowest → highest; see §5.6 *)
or_expr   ::= and_expr   { 'or'  and_expr }          (* short-circuit *)
and_expr  ::= not_expr   { 'and' not_expr }          (* short-circuit *)
not_expr  ::= 'not' not_expr | cmp_expr
cmp_expr  ::= add_expr [ ('=='|'!='|'<'|'<='|'>'|'>=') add_expr ]   (* non-chaining in v1 *)
add_expr  ::= mul_expr   { ('+'|'-') mul_expr }
mul_expr  ::= unary_expr { ('*'|'/'|'%'|'//') unary_expr }
unary_expr::= ('-'|'+') unary_expr | pow_expr
pow_expr  ::= postfix [ '**' unary_expr ]            (* right-assoc *)

postfix   ::= atom { call | index | field }
call      ::= '(' [ exprs ] ')' [ trailing_lambda ]  (* trailing block lambda = last arg *)
index     ::= '[' expr ']'
field     ::= '.' LIDENT
trailing_lambda ::= lamparams '=>' ( NEWLINE INDENT stmt { stmt } DEDENT )

atom      ::= literal
            | LIDENT                                   (* variable / function *)
            | UIDENT                                   (* data constructor (e.g. nullary Leaf) *)
            | '_'
            | '(' [ exprs ] ')'                       (* '()' unit · '(e)' group · '(e,e)' tuple *)
            | '[' [ exprs ] ']'                       (* list literal *)
            | record
record    ::= '{' [ field_init { ',' field_init } ] '}'
field_init::= LIDENT '=' expr                          (* value fields use '='  (types use ':') *)
literal   ::= INT | FLOAT | STRING | CHAR | 'true' | 'false'
```

### 5.5 Patterns & types

```
pattern   ::= pat_app [ 'as' LIDENT ]
pat_app   ::= UIDENT '(' pattern { ',' pattern } ')'  (* constructor app:  Node(l, x, r) *)
            | UIDENT                                   (* nullary constructor:  Leaf *)
            | LIDENT                                   (* variable binding *)
            | '_'                                      (* wildcard *)
            | literal                                  (* incl. true / false *)
            | '(' pattern { ',' pattern } ')'          (* tuple pattern *)
            | '{' field_pat { ',' field_pat } '}'      (* record pattern *)
field_pat ::= LIDENT '=' pattern

type      ::= type_arrow
type_arrow::= type_app { '->' type_app }              (* function type, right-assoc *)
type_app  ::= type_atom { '[' type { ',' type } ']' } (* application:  List[Int] *)
type_atom ::= UIDENT                                   (* type constructor:  Int, List, Tree *)
            | LIDENT                                   (* type variable:  a *)
            | INT                                      (* index literal in a dependent type *)
            | '(' type { ',' type } ')'                (* tuple type *)
            | '{' LIDENT ':' type { ',' LIDENT ':' type } '}'   (* record type — fields use ':' *)
```

### 5.6 Operator precedence (low → high)

| Lvl | Operators | Assoc | Notes |
|---|---|---|---|
| 1 | `or` | left | short-circuit → `if` |
| 2 | `and` | left | short-circuit → `if` |
| 3 | `not` _e_ | prefix | |
| 4 | `== != < <= > >=` | non-assoc | no chaining in v1 |
| 5 | `+ -` | left | |
| 6 | `* / % //` | left | `//` = integer div |
| 7 | unary `- +` | prefix | |
| 8 | `**` | right | power |
| 9 | call `()`, index `[]`, field `.` | postfix | |

Each operator lowers to a named prelude `d2cst` (LOWERING-MAP §3.4); `and`/`or`/`not`
lower to short-circuiting `if`. The parser owns precedence (Pratt) — no ATS fixity.

---

## 6. Example programs

Each example uses only the grammar above. The comments point at the relevant
lowering/elaboration doc; nothing here introduces new machinery.

**(a) Recursion + `if`-expression**
```
def fact(n: Int) -> Int:
    if n <= 0: 1
    else: n * fact(n - 1)
```

**(b) `let mut` + `while` (desugars to a tail-recursive loop → backend `while`)**
```
def sum_upto(n: Int) -> Int:
    let mut total = 0
    let mut i = 1
    while i <= n:
        total = total + i
        i = i + 1
    total                       # the block's tail value
```

**(c) Nested `for`, early `return` through both loops, loop-`else`**
```
def find(grid: List[List[Int]], target: Int) -> (Int, Int):
    let mut i = 0
    for row in grid:
        let mut j = 0
        for cell in row:
            if cell == target: return (i, j)   # flow_return threads out of both loops
            j = j + 1
        i = i + 1
    (-1, -1)

def first_even(xs: List[Int]) -> Int:
    for x in xs:
        if x % 2 == 0: return x
    else:
        return -1               # loop-else: ran because no `break`/`return` fired
```

**(d) Datatype + `match` (generic)**
```
type Tree[a] = Leaf | Node(Tree[a], a, Tree[a])

def sum_tree(t: Tree[Int]) -> Int:
    match t:
        case Leaf: 0
        case Node(l, x, r): sum_tree(l) + x + sum_tree(r)
```

**(e) Higher-order: inline lambda and a trailing block lambda**
```
def normalize(xs: List[Int], k: Int) -> List[Int]:
    let doubled = map(xs, (x) => x * 2)        # inline-body lambda as an argument
    fold(doubled, []) (acc, x) =>              # trailing block-bodied lambda (last arg)
        let y = x + k
        cons(y, acc)
```

**(f) Records (type uses `:`, literal uses `=`) + mutual recursion + a module entry**
```
from "prelude" import *

type Point = { x: Int, y: Int }

def manhattan(p: Point, q: Point) -> Int:
    abs(p.x - q.x) + abs(p.y - q.y)

def is_even(n: Int) -> Bool:                   # adjacent defs ⇒ one mutually-recursive group
    if n == 0: true
    else: is_odd(n - 1)
def is_odd(n: Int) -> Bool:
    if n == 0: false
    else: is_even(n - 1)

let origin = { x = 0, y = 0 }
let p = { x = 3, y = 4 }
print_int(manhattan(origin, p))                # top-level expr-stmt = module init
```

---

## 7. Cross-references & open items

- Imperative control flow (`while`/`for`/`break`/`continue`/`return`, loop-`else`)
  and how `let mut` is threaded: **LOOP-DESUGARING.md**.
- Per-construct lowering to L2 and the type-annotation surface: **LOWERING-MAP.md**.
- The EBNF (§5) is **provisional for v1**; it firms up while the lexer/parser are
  built (M1–M2).
- **Open:** the operator → prelude-`d2cst` mapping table (precedence itself is now
  drafted, §5.6); whether an indented block is allowed as a general expression
  (beyond function/lambda bodies); the finalized trailing-lambda acceptance rule
  (§3); comparison chaining (`a < b < c`); the native dependent-type surface (plan §8).
