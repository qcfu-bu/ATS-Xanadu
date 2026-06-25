# M2 — parser → PyAST: implementation report

> **Status: DONE.** A pure, re-entrant recursive-descent + Pratt parser turns the
> `pylex_layout` token stream into a faithful **PyAST** (surface AST) carrying a real
> `loctn` on every node. All 8 M2 DATS transpile with **0 errck** (`jsemit00`,
> `node --stack-size=8801`), the build is one-command reproducible
> (`bash frontend/build-m2.sh`), and **all 7 golden snippets pass** — including the
> required malformed-input recovery case. No desugaring, no lowering (those are
> M2.5 / M3). Purely additive: `git status` shows zero changes under `srcgen2/` or
> `language-server/`, and **no M0/M1 file was touched** (M2 snippets live in
> `frontend/TEST/m2/` so M1's `TEST/*.py` glob never reaches them).

---

## 1. What was built (new files only)

| File | Role | LoC |
|---|---|---|
| `frontend/SATS/pyparsing.sats` | **THE M2.5/M3 CONTRACT.** PyAST datatype family + parser-state + parser/printer entries. | 552 |
| `frontend/DATS/pyparsing_util.dats` | `pstate` cursor (peek/advance/diag/resync), node-`loctn` accessors, `loc_span`. | 182 |
| `frontend/DATS/pyparsing_staexp.dats` | **TYPE + PATTERN** parser (the "static"-ish surface). | 389 |
| `frontend/DATS/pyparsing_dynexp.dats` | **EXPRESSION (Pratt) + STATEMENT/SUITE** parser. | 886 |
| `frontend/DATS/pyparsing_decl00.dats` | **DECLARATION + MODULE** parser + public entries. | 433 |
| `frontend/DATS/pyparsing_print.dats` | PyAST **pretty-printer** (S-expr + `@span`) for goldens. | 502 |
| `frontend/DATS/pyparsing_harness.dats` | Golden harness: parse `argv[2]`, dump PyAST + diagnostics. | 68 |
| `frontend/build-m2.sh` | One-command transpile + link + golden run/diff (mirrors `build-m1.sh`). | 158 |
| `frontend/TEST/m2/m2_*.{py,golden}` | 7 representative snippets + checked-in goldens. | — |

**Reused** verbatim (never rebuilt): `srcgen2/lib/lib2xatsopt.js` (~171 MB), the M1
runtime/link recipe (same runtime list, same `sed` namespacing, same `jsemit00`,
same `--stack-size=8801`), the M1 FFI glue `frontend/CATS/pylexing.cats` (the parser
calls `pylex_layout`, which needs `PYL_load`/`PYL_byte_at`/`PYL_slice` + the file/argv
helpers), and the M1 lexer DATS (`pylexing_token.dats`, `pylayout.dats`).

---

## 2. The PyAST design — the contract for M2.5 and M3

`pyparsing.sats` defines a small surface AST family (86 constructors). The design
choices are load-bearing for the downstream passes; each is documented in-file.

### 2.1 Faithful surface, NOT pre-desugared (so M2.5 has something to analyze)

M2 stops at the surface. The imperative-control vocabulary is kept **explicit** so the
M2.5 elaborator (LOOP-DESUGARING §4 accumulator analysis, §5 rules) can lower it:

- **`PyDlet(loc, mut: bool, pat, ann, rhs)`** — `let` / `let mut` is ONE node with a
  **mut flag** (`true` = `let mut`). This is the linchpin M2.5 keys on (LOOP-DESUGARING
  §1): the mut flag makes the mutated set syntactically evident.
- **`PySreassign(loc, lvalue, rhs)`** — `x = e` reassignment is a **DISTINCT node**, not
  a `let`. M2.5 turns a valid one into an SSA shadowing rebind; an invalid one
  (immutable / undeclared target) is an *elaboration* error THERE, not M2's job. The
  lvalue is kept as a `pyexp` (parser restricts it to LIDENT / field / index forms) so
  M2.5 can inspect it.
- **`PySwhile(loc, cond, body, else)`** / **`PySfor(loc, pat, iter, body, else)`** — each
  carries an **OPTIONAL else-suite** (`pystmtlstopt`) for loop-`else` (LOOP-DESUGARING
  §5.2/§5.3, §7.3).
- **`PySbreak` / `PyScontinue` / `PySreturn(loc, expr?)`** — distinct control nodes
  (`return`'s value is optional; a bare-tuple `a, b` parses to one `PyEtup`).
- **`PySif(loc, guards, else?)`** — the *statement* `if` has an OPTIONAL else (unlike
  the *expression* `if`, whose else is mandatory — §5.4 vs §5.3). Both use a `pyguard`
  list (`if` arm + `elif` arms), each guard a `(cond, branch-suite)`.

### 2.2 UIDENT/LIDENT distinction preserved (M3 keys con-vs-var off the node kind)

The load-bearing §5 case convention is kept in the AST so M3 never re-resolves names to
tell a constructor from a variable:

| AST node | source | M3 resolves to |
|---|---|---|
| `PyEvar(loc, name)` | LIDENT expr | a `d2var` |
| `PyEcon(loc, name)` | UIDENT expr (e.g. nullary `Leaf`) | a `d2con` |
| `PyPvar(loc, name)` | LIDENT pattern | a fresh binder |
| `PyPcon(loc, name, args)` | UIDENT pattern | a `d2con` (else "unknown constructor") |
| `PyTcon(loc, name, args)` | UIDENT type | a type constructor |
| `PyTvar(loc, name)` | LIDENT type | a type variable |

A constructor **application** `Node(l, x, r)` is `PyEapp(PyEcon "Node", [l;x;r])` — the
head's kind tells M3 it is a constructor application, not a function call. Literals keep
their **exact source lexeme** (quotes/prefix included) in `pylit` so M3 synthesizes the
L2 leaf token from the lexeme (ENGINEERING.md §3 `token_make_node`); `true`/`false` are
`PyLbool`, not constructors (§5 preamble).

### 2.3 Operators already grouped (Pratt output, not a flat token list)

By the time a `pyexp` exists, precedence (§5.6) is fully resolved: `a + b * c` is
`PyEbin(add, a, PyEbin(mul, b, c))`. Binary/unary operators are small tag enums
(`pybop` / `pyuop`, one ctor per §5.6 operator) so M3 maps each to its prelude `d2cst`
(LOWERING-MAP §3.4) by matching the tag, and `and`/`or`/`not` keep their own tags so M3
lowers them to short-circuiting `if`.

### 2.4 Lambdas (§2): one notion of body

`PyElam(loc, params, body)` — the body is a **suite** (`list(pystmt)`); an inline-body
lambda `(x) => x*2` is a one-element suite `[PySexpr ...]`, a block-bodied lambda is the
full indented suite. So `def` and lambda share the suite representation, matching §2.

### 2.5 Every node carries a real `loctn`

Spans are combined with `loc_span(l1, l2)` = the verified `add_loctn_loctn` (min pbeg ..
max pend) — the task's `loc1 + loc2`. Wrapped **by name** rather than via the `+`
overload to avoid any fixity-resolution risk in a standalone DATS. The goldens print
`@(r0:c0-r1:c1)` on every node, proving real spans flow everywhere (see §6).

### 2.6 Options + lists (an ATS3-dialect trap, solved)

- The prelude's `optn` is **dependently typed** (indexed present/absent), awkward to
  match in a transpiled DATS. We use three small **non-dependent monomorphic** option
  datatypes (`pyexpopt`, `pytypopt`, `pystmtlstopt`) — trivially matchable, additive.
- **List-alias ordering matters (verified).** A forward `#typedef pyexplst = list(pyexp)`
  *before* the datatype resolves the element to an impredicative `type`, which breaks L3
  packing — a fresh `list_cons(x, list_nil())` then fails to unify with the alias
  (`D3Et2pck`). Fix: the datatype fields use the **inline** `list(pyexp)` form, and the
  `*lst` typedefs are declared **after** the datatype block (where the element is the
  fully-boxed datatype). Bisected to a minimal repro; documented in the SATS.

---

## 3. The parser

### 3.1 Architecture (pure, re-entrant, split to mirror the lowering)

The parser threads a **`pstate = PState(remaining-tokens, reversed-diagnostics)`** by
value — functional, no module-global state (plan §6.2). Every parse function is
`(st) -> @(node, st')`. Re-entrancy is proven: parsing file A, then B, then A again
yields byte-identical output for A.

The recursive descent is split across three DATS to mirror the M3 lowering split, with
cross-file boundaries declared in the SATS (`parse_type`, `parse_pattern`, `parse_expr`,
`parse_suite`, `parse_stmt`, `parse_decl`):

- **`pyparsing_staexp.dats`** — types + patterns (do not call the expression parser).
- **`pyparsing_dynexp.dats`** — expressions (Pratt) + statements/suites (mutually
  recursive; one `fun … and …` group). Calls staexp + `parse_decl`.
- **`pyparsing_decl00.dats`** — declarations + module + the public entries
  `pyparse_tokens` / `pyparse_module`. Reuses dynexp's `parse_stmt` for module-level
  statements (no duplicated statement grammar).

> **ATS3-dialect structure rule (cost a debugging cycle, like M1's traps):** an
> `#implfun X` must **not head a `fun … and …` group** that contains non-`#impl`
> helpers — the helper is left unresolved (`D1Eid0(helper)`). Pattern used throughout:
> plain `fun p_*` / `pp_*` recursion groups + thin standalone `#implfun` wrappers for
> the SATS entries. (Two more dialect traps hit & fixed: `op` and `cons` are **reserved
> lexemes** — renamed to `theop`/`dcons`. And accidental `(*` / `*)` inside prose
> comments **nest** and silently swallow declarations — all doc comments were scrubbed;
> this was the single biggest early blocker, since the whole SATS's datatypes went
> invisible until the stray `PyEbin(*` and `p_*)` were removed.)

### 3.2 Pratt expression parser vs §5.6

`p_pratt(st, minbp)` is precedence-climbing: parse a unary/postfix primary, then fold
binary operators with binding power `>= minbp`. `binop_of_node` returns
`@(is_binop, tag, lbp, rbp)`:

| Lvl (§5.6) | Operators | lbp | rbp | Assoc |
|---|---|---|---|---|
| 1 | `or` | 1 | 2 | left |
| 2 | `and` | 2 | 3 | left |
| 4 | `== != < <= > >=` | 4 | 5 | **non-assoc** (capped at call site) |
| 5 | `+ -` | 5 | 6 | left |
| 6 | `* / % //` | 6 | 7 | left |
| 8 | `**` | 8 | 8 | **right** (`rbp == lbp`) |

Left-assoc uses `rbp = lbp+1` (equal-level ops group left); right-assoc uses
`rbp = lbp` (`**` groups right). Comparisons (lvl 4) are **non-associative**: after one
comparison the loop refuses a second at the same level and emits "comparison operators
do not chain (v1)" (§5.6 / §5.4 "non-chaining in v1"). Prefix unary `- + not` (lvls 3,7)
are `p_unary`; postfix call `()` / index `[]` / field `.` (lvl 9) are `p_postfix`,
left-assoc. **The parser owns precedence — no ATS fixity is used.**

Verified on `m2_exprs.py` (golden, §6): `1 + 2*3 - 4`, `2 ** 3 ** 2` (right-assoc),
`not a == b and a < b or b > a` (full chain), `-a + +b`, `xs[0].field`,
`obj.method(a,b)[1]`.

### 3.3 Suites & layout

`parse_suite` is entered **after** the `:` / `=>` opener: a leading `NEWLINE` ⇒ a block
(`NEWLINE INDENT stmt { stmt } DEDENT`, consuming all three layout marks); otherwise an
inline `simple_stmt` terminated by `NEWLINE`. `match` consumes `: NEWLINE INDENT
case_arm{…} DEDENT`. Brackets had layout suppressed by the lexer (M1), so the expression
parser sees no stray NEWLINEs inside `()`/`[]`/`{}`.

### 3.4 Lambda disambiguation

A lambda is detected by lookahead: `LIDENT '=>'` (peek-2) or `'(' … ')' '=>'` (a pure
balanced-paren skip `paren_then_fatarrow` checks the token after the matching `)` is
`=>`, committing only then). This keeps `(e)` groups and `(a,b)` tuples distinct from
`(x) => …` lambdas. The inline vs block body is chosen by whether a `NEWLINE` follows
the `=>` (§2). Verified on `m2_lambda.py` (inline `(x) => x*2` and block `(acc, x) =>
<suite>`).

### 3.5 Error recovery (non-fail-fast; the …errck spirit)

The parser **never throws**. On a parse error it (a) records a `PyDiag(loc, msg)` via
`ps_diag`, (b) inserts an **error node** (`PyEerror` / `PyPerror` / `PyTerror` /
`PySerror` / `PyCerror`) at the offending span, and (c) where needed `ps_resync`s:
consume tokens up to **and including** the next `NEWLINE`, but **stop at `DEDENT`/`EOF`
without consuming** (those close the enclosing suite, so the suite/module loop handles
them). The module loop additionally has a **progress guard**: if a top item consumed no
tokens it force-drops one (preventing any infinite loop on a stuck token). A malformed
file thus yields a **partial PyAST + a diagnostics list**, both dumped by the harness.
Proven by `m2_malformed.py` (§6): `def good` parses, the broken `let x = (1 +`
recovers with an `Eerror`, the parser resyncs and continues through `def after` /
`let z = 99`.

---

## 4. Verified compiler-API table (re-grepped against live SATS, 2026-06-20)

| API | Verified signature / fact | Location |
|---|---|---|
| `add_loctn_loctn` | `(loctn, loctn): loctn` = `(lsrc, g_min(pbegs), g_max(pends))` — the span-merge `loc1 + loc2`; `#symload + … of 1000`. Wrapped by name as `loc_span`. ✓ | `locinfo.sats:144-148`, `locinfo.dats:196-208` |
| `loctn_make_arg3` | `(lcsrc, postn, postn): loctn`; `#symload loctn` ✓ | `locinfo.sats:135-140` |
| `loctn_get_pbeg/pend/lsrc` | `(loctn): postn/lcsrc`; `#symload pbeg/pend/lsrc` ✓ | `locinfo.sats:119-125` |
| `loctn_dummy` | `(): loctn` (synthetic spans only) ✓ | `locinfo.sats:128-129` |
| `postn_get_nrow/ncol` | `(postn): sint`; `#symload nrow/ncol` (printer reads these) ✓ | `locinfo.sats:98-104` |
| `pylex_layout` | `(lcsrc, strn): pytokenlst` — the layout token stream the parser consumes ✓ | `pylexing.sats:222-224` |
| `pytoken.node()/loctn()` | `#symload node/loctn` on `pytoken` ✓ | `pylexing.sats:191-195` |
| `list_cons/list_nil/list_reverse/list_length/list_append` | prelude list ops; `list(a:t0) = [n] list(a,n)` (existential over length) ✓ | `list000.sats`, `basics0.sats:929` |
| `strn_fprint` / `gint_fprint$sint` | `(value, out)` arg order (NOT `(out, value)`) ✓ | `libcats.sats:155-159` |
| `g_stdout` / `FILR` | `g_stdout(): FILR`; `FILR = FILEref` ✓ | `libcats.sats:69 / 58` |

### Discrepancies / Xanadu-specific facts found (all real)

- **Δ1 — forward list-alias typedef breaks L3 packing.** `#typedef pyexplst = list(pyexp)`
  placed *before* `datatype pyexp` makes the element an impredicative `type`; a fresh
  `list_cons(x, list_nil())` then fails L3 (`D3Et2pck`). Fix: inline `list(pyexp)` in the
  datatype, declare the `*lst` typedefs *after* the block. Bisected to a 6-line repro.
- **Δ2 — `op` and `cons` are reserved lexemes.** Using them as binders yields
  `D2Esym0`/`T_OP1` parse/resolve errors. Renamed to `theop` / `dcons`.
- **Δ3 — `#implfun` cannot head a `fun … and …` group** containing non-`#impl` helpers
  (helper unresolved). Pattern: plain `fun` recursion groups + thin `#implfun` wrappers.
- **Δ4 — comments nest.** Accidental `(*` / `*)` in prose (`PyEbin(*…`, `p_*)`,
  `bool(*import *?*)`) open/close nested comments and silently swallow declarations —
  the entire SATS datatype set went invisible until scrubbed. (Same class as M1's
  dialect traps; the inline `(*field*)` annotation style is hazardous and was removed.)
- **Δ5 — `optn` is dependently typed.** Replaced with monomorphic option datatypes (§2.6).

(The M1 facts Δ1–Δ5 — `FILR` via `xatsopt_sats.hats`, no `&&`/`||`, `(-1)` not `~1`,
`@(…)` not `'{…}`, `XATSHOME` in env — all still hold and are honored.)

---

## 5. SURFACE-GRAMMAR.md gaps / ambiguities found (FLAGGED, not silently invented)

None *blocked* the PyAST design (no STOP required). The following minor decisions were
adopted (most Python/Scala-conventional) and are flagged for ratification:

1. **Pattern annotation `p : T` vs the block-header `:`.** §5.5 lists `pattern ::=
   pat_app [as LIDENT]` AND a `p : T` form, but `:` is *also* the block-opener in
   `case pat:` / `for pat in e:` and the binding annotation in `let pat : T = e`. To
   avoid an ambiguity, `parse_pattern` **does not** consume a trailing `:` — the
   *binding* / *param* parsers consume `: T` explicitly (producing the annotation), and
   `case`/`for` treat `:` as their own terminator. `PyPann` exists in the AST but is
   produced only by those sites. *Please confirm pattern annotations are param/binding-
   only.*

2. **`type T = Foo` — alias or single-constructor datatype?** §5.2 `typedef ::= type |
   datacon { '|' datacon }` is ambiguous for a bare UIDENT RHS. Decision: a RHS that
   **begins with a UIDENT** is parsed as a (possibly single-constructor) **datatype sum**
   (`PyTDdata`); any other RHS (tvar, `(`, `{`, INT) is an **alias** (`PyTDalias`). So
   `type T = Foo` is a one-constructor datatype — the conventional datatype reading. A
   true single-constructor *type alias* to `Foo` would need an explicit form. *Please
   confirm, or specify a disambiguator (e.g. `type T = Foo` alias vs `type T = | Foo`
   sum).*

3. **`if`-expression else (§5.4) read as a single inline expr.** `if_expr` requires
   `else`; M2 reads its branches via `parse_suite` (so an inline `if c: e` branch works)
   but reads the **else branch of an if-EXPRESSION** as a single inline `pyexp` (the
   common `else: e`). A *block*-bodied else of an if-*expression* (block-as-expression)
   is the OPEN §7 item "whether an indented block is allowed as a general expression";
   v1 keeps it inline. Statement-`if` else is a full suite. *No design impact; flagged.*

4. **Trailing block-lambda inside a call (§3, explicitly OPEN).** v1 accepts the inline
   `(x) => e` and the statement/`let`-RHS block lambda; the *trailing* block lambda as a
   call's last argument across the bracket/layout boundary (M1 flag #2) is **not yet**
   special-cased — it parses as far as the layout allows and recovers otherwise. This
   matches M1's "brackets fully suppress layout" choice and §3's "finalized during
   M1–M2 / Scala pragmatic stance". *Flagged for the finalized acceptance rule.*

5. **`|` as a match-arm separator (M1's open question).** M2 uses `case` per arm (§5.3)
   and does **not** require/consume `|` between arms; `|` (`PT_BAR`) is consumed only as
   the datatype-alternative separator (§5.2). *Confirms M1's `PT_BAR` = datacon
   separator; no or-patterns in v1.*

---

## 6. Captured golden output (EVIDENCE)

`bash frontend/build-m2.sh` → transpile (0 errck ×8) → link (192 MB) → run/diff:

```
>> [1/4] transpile M2 DATS (jsemit00)  (8 files)
   - pylexing_token  - pylayout  - pyparsing_util  - pyparsing_staexp
   - pyparsing_dynexp  - pyparsing_decl00  - pyparsing_print  - pyparsing_harness
>> [3/4] run the parser harness over frontend/TEST/m2/*.py
   [ok]   m2_def    [ok]   m2_exprs   [ok]   m2_lambda   [ok]   m2_loops
   [ok]   m2_malformed   [ok]   m2_match   [ok]   m2_records
>> M2 GOLDEN: PASS (all snippets match)
```

The 7 snippets cover the full v1 surface: a `def` with typed params + return + inline
`if/elif/else`; a `type T[a] = A | B(…)` datatype + `match`/`case` with constructor &
tuple patterns; `let`/`let mut` + reassignment + `while` + `for…else` with
`break`/`continue`/`return`; inline & block-body lambdas; record type / literal / field
access; `from … import *`; and the malformed-recovery case. Notation:
`(NodeKind … @(r0:c0-r1:c1) …)`, half-open byte spans.

### Evidence A — `m2_def.py` (def + types + inline if/elif/else; Pratt grouping)

Source:
```
def fact(n: Int) -> Int:
    if n <= 0: 1
    elif n == 1: 1
    else: n * fact(n - 1)
```
PyAST dump (`@(row:bytecol-row:bytecol)` on every node; note `n * fact(n-1)` grouped as
`(Ebin * (Evar n) (Eapp fact …))`, and the inline `if`/`elif`/`else` as one statement-`if`
with guard arms + an else suite):
```
(module
(def fact@(0:0-0:3) (params (n: (Tcon Int@(0:12-0:15)))) (ret (Tcon Int@(0:20-0:23)))
  (if@(1:4-1:6)
    (guard@(1:4-1:6) (cond (Ebin <=@(1:7-1:13) (Evar n@(1:7-1:8)) (Elit@(1:12-1:13) (int 0@(1:12-1:13)))))
      (expr@(1:15-1:16) (Elit@(1:15-1:16) (int 1@(1:15-1:16)))))
    (guard@(2:4-2:8) (cond (Ebin ==@(2:9-2:15) (Evar n@(2:9-2:10)) (Elit@(2:14-2:15) (int 1@(2:14-2:15)))))
      (expr@(2:17-2:18) (Elit@(2:17-2:18) (int 1@(2:17-2:18)))))
    (else
      (expr@(3:10-3:25) (Ebin *@(3:10-3:25) (Evar n@(3:10-3:11)) (Eapp@(3:14-3:25) (Evar fact@(3:14-3:18)) (args (Ebin -@(3:19-3:24) (Evar n@(3:19-3:20)) (Elit@(3:23-3:24) (int 1@(3:23-3:24)))))))))))
)
==== diagnostics ====
(none)
```

### Evidence B — `m2_loops.py` (let mut + reassign + while + for…else + break/continue/return)

Source (excerpt) + dump showing the **mut flag**, the **distinct reassign node**, the
**loop-`else`**, and the control nodes — exactly the vocabulary M2.5 desugars:
```
(def sum_upto@(0:0-0:3) (params (n: (Tcon Int@(0:16-0:19)))) (ret (Tcon Int@(0:24-0:27)))
  (let mut@(1:4-1:21) (Pvar total@(1:12-1:17)) = (Elit@(1:20-1:21) (int 0@(1:20-1:21))))
  (let mut@(2:4-2:17) (Pvar i@(2:12-2:13)) = (Elit@(2:16-2:17) (int 1@(2:16-2:17))))
  (while@(3:4-3:9) (cond (Ebin <=@(3:10-3:16) (Evar i@(3:10-3:11)) (Evar n@(3:15-3:16))))
    (reassign@(4:8-4:25) (Evar total@(4:8-4:13)) = (Ebin +@(4:16-4:25) (Evar total@(4:16-4:21)) (Evar i@(4:24-4:25))))
    (reassign@(5:8-5:17) (Evar i@(5:8-5:9)) = (Ebin +@(5:12-5:17) (Evar i@(5:12-5:13)) (Elit@(5:16-5:17) (int 1@(5:16-5:17))))))
  (expr@(6:4-6:9) (Evar total@(6:4-6:9))))
(def first_even@(8:0-8:3) (params (xs: (Tcon List@(8:19-8:28) (Tcon Int@(8:24-8:27))))) (ret (Tcon Int@(8:33-8:36)))
  (for@(9:4-9:7) (Pvar x@(9:8-9:9)) in (Evar xs@(9:13-9:15))
    (if@(10:8-10:10)
      (guard@(10:8-10:10) (cond (Ebin ==@(10:11-10:21) (Ebin %@(10:11-10:16) (Evar x@(10:11-10:12)) (Elit@(10:15-10:16) (int 2@(10:15-10:16)))) (Elit@(10:20-10:21) (int 0@(10:20-10:21)))))
        (return@(10:23-10:31) (Evar x@(10:30-10:31)))))
    (continue@(11:8-11:16))
    (else
      (return@(13:8-13:17) (Euna -@(13:15-13:17) (Elit@(13:16-13:17) (int 1@(13:16-13:17))))))))
```

### Evidence C — `m2_malformed.py` (REQUIRED: partial AST + recovery)

Source (`let x = (1 +` is unterminated; `let y = 1 2 3` has stray tokens):
```
def good(n: Int) -> Int:
    n + 1

let x = (1 +

def after(m: Int) -> Int:
    m * 2

let y = 1 2 3
let z = 99
```
PyAST dump — `def good` parses cleanly; the broken `let x` recovers with an
**`Eerror "expected an expression"`** node, the parser **resynchronizes and continues**
through `def after`, `let y` (recovered as separate expr-stmts) and `let z = 99`; the
**diagnostics list** records the two meaningful errors. This is the non-fail-fast
partial-AST guarantee:
```
(module
(def good@(0:0-0:3) (params (n: (Tcon Int@(0:12-0:15)))) (ret (Tcon Int@(0:20-0:23)))
  (expr@(1:4-1:9) (Ebin +@(1:4-1:9) (Evar n@(1:4-1:5)) (Elit@(1:8-1:9) (int 1@(1:8-1:9))))))
(cstmt@(3:0-5:3)
  (let imm@(3:0-5:3) (Pvar x@(3:4-3:5)) = (Ebin +@(3:9-5:3) (Elit@(3:9-3:10) (int 1@(3:9-3:10))) (Eerror "expected an expression"@(5:0-5:3)))))
(def after@(5:0-5:3) (params (m: (Tcon Int@(5:13-5:16)))) (ret (Tcon Int@(5:21-5:24)))
  (expr@(6:4-6:9) (Ebin *@(6:4-6:9) (Evar m@(6:4-6:5)) (Elit@(6:8-6:9) (int 2@(6:8-6:9))))))
(cstmt@(8:0-8:9)  (let imm@(8:0-8:9) (Pvar y@(8:4-8:5)) = (Elit@(8:8-8:9) (int 1@(8:8-8:9)))))
(cstmt@(8:10-8:11) (expr@(8:10-8:11) (Elit@(8:10-8:11) (int 2@(8:10-8:11)))))
(cstmt@(8:12-8:13) (expr@(8:12-8:13) (Elit@(8:12-8:13) (int 3@(8:12-8:13)))))
(cstmt@(9:0-9:10)  (let imm@(9:0-9:10) (Pvar z@(9:4-9:5)) = (Elit@(9:8-9:10) (int 99@(9:8-9:10)))))
)
==== diagnostics ====
  expected an expression @(5:0-5:3)
  expected ')' @(5:0-5:3)
```

---

## 7. Re-entrancy & purity (plan §6.2)

`pyparse_module(src, text)` / `pyparse_tokens(toks)` take their input as arguments and
return a fresh `pymodule`; the only mutable state is the FFI byte buffer (fully reset by
`pylex_layout` per call). **No module-global parser state.** Verified: parse `m2_def`,
then `m2_match`, then `m2_def` again ⇒ byte-identical output for `m2_def`. Safe to call
repeatedly in the resident LSP.

---

## 8. Scope boundary

M2 is **parser only**: it produces a faithful surface PyAST + recovery diagnostics. NO
desugaring of `let mut`/loops/`break`/`continue`/`return` (M2.5), NO lowering to L2 (M3).
The `pyparsing.sats` PyAST is the seam M2.5 and M3 consume; spans are real today, so when
M2.5/M3 thread them into PyCore/L2 nodes, diagnostics land on the `.py` source for free.

---

## 9. Purely-additive check

```
$ git status --short | grep -E "srcgen2/|language-server/"   →  (no output)
```
Only new files under `frontend/SATS/`, `frontend/DATS/`, `frontend/TEST/m2/`,
`frontend/build-m2.sh`, `frontend/docs/M2-REPORT.md` were added. **No M0/M1 file was
modified** (M2 snippets live in `frontend/TEST/m2/` so M1's `TEST/*.py` glob never
reaches them — `build-m1.sh` still PASSES). The three pre-modified docs
(LOWERING-MAP / PYTHON-FRONTEND-PLAN / SURFACE-GRAMMAR) were not touched by M2.
```
$ bash frontend/build-m1.sh   →  M1 GOLDEN: PASS (all snippets match)
$ bash frontend/build-m2.sh   →  M2 GOLDEN: PASS (all snippets match)
```
