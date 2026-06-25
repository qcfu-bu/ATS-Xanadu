# M1 — lexer + layout: implementation report

> **Status: DONE.** A fresh Python-surface lexer (`pylex_text`) + CPython off-side
> layout pass (`pylex_layout`) scan `.py`-surface source into a `pytoken` stream
> carrying **real `loctn` spans** (0-based; columns in UTF-8 **bytes**). All four
> M1 DATS transpile with **0 errck**, the build is one-command reproducible
> (`bash frontend/build-m1.sh`), and **all 7 golden snippets pass** verification
> (including the two required layout edge cases: bracket-suppressed newlines and
> dedent-to-EOF). Purely additive: `git status` shows zero changes under `srcgen2/`
> or `language-server/`, and no M0 file was touched.

---

## 1. What was built (the new files)

| File | Role |
|---|---|
| `frontend/SATS/pylexing.sats` | **THE M2 CONTRACT.** The `ptnode`/`pytoken` datatype + lexer/layout/printer entries. Documented field-by-field. |
| `frontend/DATS/pylexing_token.dats` | The **raw scanner**: bytes → raw `pytoken` list (real spans, `#` comments, escapes, numeric literals, UIDENT/LIDENT case split, line continuations). |
| `frontend/DATS/pylayout.dats` | The **layout pass**: CPython off-side rule (INDENT/DEDENT/NEWLINE; bracket suppression; blank/comment lines; trailing DEDENTs at EOF). |
| `frontend/DATS/pylexing_print.dats` | Token **pretty-printer** (`KIND[lexeme]@(r0:c0-r1:c1)`) for goldens + M2 debugging. |
| `frontend/DATS/pylexing_harness.dats` | Golden **harness**: lex `argv[2]`, dump the layout token stream to stdout. |
| `frontend/CATS/pylexing.cats` | FFI byte source (UTF-8 buffer + `byte_at`/`slice`) + file read + argv + stdout. |
| `frontend/build-m1.sh` | One-command transpile (jsemit00) + cat-link + golden run/diff. `--accept` rewrites goldens. |
| `frontend/TEST/t0[1-7]_*.py` + `.golden` | 7 representative snippets + checked-in golden dumps. |

**Reused** (never rebuilt): `srcgen2/lib/lib2xatsopt.js` (~171 MB) and the M0a
runtime/link recipe verbatim (same runtime list, same `sed` namespacing, same
`jsemit00`, same `--stack-size=8801`).

---

## 2. The token datatype — the contract M2 will consume

`pytoken = PYTOKEN of (ptnode, loctn)` — a kind paired with a half-open span. The
kind `ptnode` (full definition + rationale in `pylexing.sats`):

```
ptnode =
  // keywords (reserved; SURFACE-GRAMMAR §5.1) — one ctor each:
  | PT_KW_LET | PT_KW_MUT | PT_KW_DEF | PT_KW_IF | PT_KW_ELIF | PT_KW_ELSE
  | PT_KW_WHILE | PT_KW_FOR | PT_KW_IN | PT_KW_MATCH | PT_KW_CASE
  | PT_KW_BREAK | PT_KW_CONTINUE | PT_KW_RETURN | PT_KW_IMPORT | PT_KW_FROM
  | PT_KW_TYPE | PT_KW_AS | PT_KW_AND | PT_KW_OR | PT_KW_NOT
  // identifiers (case-split per §5 preamble) + wildcard:
  | PT_UIDENT of strn   // Uppercase-initial: type-/data-constructor
  | PT_LIDENT of strn   // lowercase-initial: var/fun/type-var/field
  | PT_USCORE           // _
  // literals (lexeme kept VERBATIM, quotes/prefix included):
  | PT_INT of strn | PT_FLOAT of strn | PT_STRING of strn | PT_CHAR of strn
  | PT_TRUE | PT_FALSE  // boolean literal keywords (NOT data constructors)
  // operators & punctuation (one ctor each):
  | PT_PLUS PT_MINUS PT_STAR PT_SLASH PT_SLASH2 PT_PERCENT PT_STAR2
  | PT_EQEQ PT_NEQ PT_LT PT_LTE PT_GT PT_GTE
  | PT_EQ PT_FATARROW PT_ARROW PT_COLON PT_BAR PT_COMMA PT_DOT
  | PT_LPAREN PT_RPAREN PT_LBRACK PT_RBRACK PT_LBRACE PT_RBRACE
  // layout & control:
  | PT_NL_RAW   // physical newline (RAW SCANNER ONLY; consumed by layout)
  | PT_NEWLINE PT_INDENT PT_DEDENT   // layout-pass output
  | PT_EOF
  // error recovery (never throws):
  | PT_ERROR of strn
```

### Design rationale (why this shape)

- **Keywords are reserved, one ctor each.** An identifier lexeme equal to a keyword
  lexes as the keyword. `and`/`or`/`not` are kept as *keyword operators*
  (`PT_KW_AND/OR/NOT`) because the parser owns their precedence (§5.6); M2 treats
  them as operators. `true`/`false` lex as `PT_TRUE`/`PT_FALSE` **boolean literals**,
  not data constructors (§5 preamble).
- **Identifiers split by initial case in the lexer** (the load-bearing §5
  convention) → M2 never consults name resolution to tell a constructor from a
  binder. `_` is its own `PT_USCORE`.
- **Literals keep the exact source lexeme** (quotes/prefix included) as a `strn`.
  Numeric *value* parsing and escape *decoding* are deferred to M2/lowering; the
  lexer keeps the lexeme faithful and only validates enough to delimit. The span's
  byte length is recoverable as `pend.ntot - pbeg.ntot`.
- **Operators/punctuation are distinct nullary ctors** so M2 matches on kind, not a
  re-scanned lexeme. Roles per §4/§5.6 are documented on each ctor.
- **Layout tokens are synthesized by the layout pass**, not the raw scanner: the
  scanner emits `PT_NL_RAW` for a physical newline; the layout pass rewrites
  `PT_NL_RAW` runs into `PT_NEWLINE`/`PT_INDENT`/`PT_DEDENT`. `PT_EOF` terminates.
- **`PT_ERROR` carries the offending lexeme** — the lexer is non-fail-fast (matches
  the compiler's `…errck` spirit); recovery is M2's.

Accessors `pytoken.node()` / `pytoken.loctn()` are `#symload`ed (`node`/`loctn`).

---

## 3. The layout algorithm + the edge-case rules I chose

Implemented in `pylayout.dats` (the standard CPython tokenizer off-side rule). Rules
(documented in-file as R1–R6):

- **R1 Indent stack** of byte-columns, bottom = `0`. Top = current block indent.
- **R2 Logical-line indentation.** At each logical line's first real token (when not
  inside brackets), compare its byte-column `ind` to stack top `t`:
  `ind > t` → push, emit one `INDENT`; `ind == t` → nothing; `ind < t` → pop while
  top > ind, one `DEDENT` per pop.
- **R3 NEWLINE.** A `PT_NL_RAW` ending a *non-blank* logical line (bracket depth 0)
  emits one `NEWLINE`. Blank lines and comment-only lines emit nothing.
- **R4 Bracket suppression.** While bracket depth > 0 (inside `()`/`[]`/`{}`),
  `PT_NL_RAW` is dropped (implicit line join) and **no** INDENT/DEDENT is computed.
- **R5 EOF.** Optional final `NEWLINE` (if the last line was non-empty), then one
  `DEDENT` per open level — **`stklen - 1`**, since the base column-0 level is never
  closed — then `EOF`.
- **R6 Blank/indented-blank lines** are ignored (indentation read from the first
  *real* token of a line).

Synthetic tokens carry a **zero-width** span at the position where the change is
detected (e.g. `INDENT@(1:4-1:4)`), so they still report on the `.py` source.

### Edge-case decisions I made (and flagged)

1. **Inconsistent dedent** (a line landing between two stack levels): CPython
   *raises*. I **recover** — emit DEDENTs to the nearest enclosing level and
   continue (non-fail-fast). M2 can flag it. *(Documented deviation.)*
2. **Tabs.** Treated as a single inline-whitespace byte (advances ncol by 1), like
   any other whitespace byte. v1 takes **spaces-only indentation** semantics; tabs
   are not expanded to a tab-stop. *(CPython-standard tab handling — tab-to-8 stops
   plus tab/space consistency errors — is a hardening item; flagged.)*
3. **CRLF.** `\r` is an ordinary inline-whitespace byte that does **not** reset the
   line; `\n` resets ncol and bumps nrow. A CRLF therefore advances ncol on the
   `\r` then resets on the `\n` — the standard behavior; columns stay byte-accurate.
4. **Line continuation `\<newline>`** (incl. `\` CRLF): both bytes consumed, **no**
   `PT_NL_RAW` emitted — the physical line join happens at the *raw scanner* level
   (proven by t08 edge probe). A lone `\` elsewhere → `PT_ERROR`.
5. **Block-opener inside brackets (trailing block lambdas, §3).** SURFACE-GRAMMAR §3
   says a block-opener (`:`/`=>`) *may* open a layout context even inside brackets.
   That nuance is an **OPEN** grammar item ("finalized during M1–M2") and is a
   **parser/lambda** concern, not byte-level layout. **v1 layout takes the standard
   CPython rule: brackets fully suppress layout.** *(Flagged — see §5.)*

---

## 4. The verified location-API table (re-grepped against the live SATS, 2026-06-20)

All from `srcgen2/SATS/locinfo.sats` (✓ = matched the task brief / design docs):

| API | Verified signature | Location |
|---|---|---|
| `postn_make_int3` | `(ntot:sint, nrow:sint, ncol:sint): postn`; `#symload postn` ✓ | `locinfo.sats:108-112` |
| `postn_get_ntot/nrow/ncol` | `(postn): sint`; `#symload ntot/nrow/ncol` ✓ | `locinfo.sats:98-104` |
| `loctn_make_arg3` | `(lcsrc, postn(pbeg), postn(pend)): loctn` (**half-open**); `#symload loctn` ✓ | `locinfo.sats:134-140` |
| `loctn_make_fpath` | `(fpath, postn, postn): loctn`; `#symload loctn` ✓ | `locinfo.sats:137-141` |
| `loctn_get_lsrc/pbeg/pend` | `(loctn): lcsrc/postn`; `#symload lsrc/pbeg/pend` ✓ | `locinfo.sats:119-125` |
| `loctn_dummy` | `(): loctn` (uses `LCSRCnone0` + `POSTN(-1,-1,-1)`) ✓ | `locinfo.sats:128-129` |
| `lcsrc` ctors | `LCSRCnone0 of () \| LCSRCsome1 of strn \| LCSRCfpath of fpath` ✓ | `locinfo.sats:69-73` |
| `POSTN`/`LOCTN` reprs | `POSTN of (sint,sint,sint)` (ntot,nrow,ncol); `LOCTN of (lcsrc,postn,postn)` — **confirms 0-based ntot/nrow/ncol & half-open** | `locinfo.dats:66-72, 125-131` |

**Output primitives** (`srcgen1/xatslib/libcats/SATS/libcats.sats`), used by the
printer/harness — **note argument order `(value, out)`**, NOT `(out, value)`:

| API | Signature | Location |
|---|---|---|
| `strn_fprint` | `(strn, FILR): void` ✓ | `libcats.sats:155-156` |
| `gint_fprint$sint` | `(sint, FILR): void` ✓ | `libcats.sats:158-159` |
| `g_stdout` / `FILR` | `g_stdout(): FILR`; `FILR = FILEref` ✓ | `libcats.sats:69 / 58` |

**Prelude lexical ops** (`srcgen1/prelude/SATS/strn000.sats`, `list000.sats`):
`strn_append`, `strn_eq` (`#symload =`), `strn_length`; `list_cons`/`list_nil`/
`list_reverse`/`list_sing`. All matched.

### Discrepancies / Xanadu-specific facts found (all real, not workarounds)

- **Δ1 — `FILR` is NOT visible via `libxatsopt.hats` alone.** Naming `FILR` in the
  SATS print signatures produced `D3Et2pck(out; T2Pnone0())` errcks (the param type
  resolved to *none*). Fix: the SATS additionally `#include`s
  `srcgen2/HATS/xatsopt_sats.hats` (the pure prelude+libcats SATS bundle, where
  `FILR = FILEref` lives). It is SATS-only and disjoint from `libxatsopt.hats`, so
  including both is safe. *(Same root cause M0a found for `xatsopt_dpre.hats`; here
  it bites in the SATS, not just the DATS.)*
- **Δ2 — short-circuit `&&`/`||` are NOT available** to a standalone DATS. They are
  fixity-aliases of `andalso`/`orelse`, declared in `srcgen2/DATS/xglobal_ext000.dats`
  (`#infixl orelse of ||` / `#infixl andalso of &&`) — i.e. in the *stock parser's*
  fixity env, not the prelude headers we include. Using them yielded
  `D2Enone1(D1Eid0(&&))` errcks. Fix: define eager prefix helpers `band`/`bor`
  (`pylexing_token.dats`) — sound because all operands are pure comparisons — and
  use nested `if` where a one-off boolean appears (`pylayout.dats`).
- **Δ3 — negative integer literals are written `(-1)`, not `~1`.** The unary `~`
  produced `D2Esym0(~)` errcks; the compiler tree uses parenthesized `(-1)`. Fixed
  in `brk_delta`.
- **Δ4 — anonymous record syntax `'{ f= v }` does NOT parse** in this surface (it
  was read as a `{` char literal). The Xanadu tree uses `@{ f= t }` for record
  *types* and record values are rare. The cursor was switched to a plain 3-tuple
  `cur = @(ntot, nrow, ncol)` (fields `.0/.1/.2`), which is well-supported.
- **Δ5 — the transpiler needs `XATSHOME` in its environment** (else it reads
  `/prelude/…` and ENOENTs). `build-m1.sh` exports it (as `build-m0a.sh` does).

---

## 5. SURFACE-GRAMMAR.md gaps found (flagged for the architect — NOT silently invented)

1. **`|` (vertical bar) is missing from §5.1 and §5.6 but IS used in the grammar.**
   §5.2 `typedef ::= datacon { '|' datacon }` (and the sum-type example `type Tree[a]
   = Leaf | Node(…)`) require a `|` token, yet `|` appears in **neither** the §5.1
   lexical list **nor** the §5.6 operator table. Without it the lexer would emit
   `PT_ERROR[|]` on every sum type (observed in t03 before the fix). **Decision:** I
   added a dedicated **`PT_BAR`** token (a separator, not an operator) — clearly
   required by the grammar. *Please confirm `PT_BAR` and add `|` to §5.1/§5.6.*
   *(Open question for M2: is `|` also a match-arm/or-pattern separator, or strictly
   the datacon separator? The token is the same either way.)*

2. **Trailing block-lambda layout inside brackets (§3) is explicitly OPEN.** §3 wants
   a block-opener to still open a layout context inside brackets. v1 layout takes the
   CPython rule (brackets fully suppress layout); the trailing-lambda acceptance is a
   **parser-level** concern to finalize in M2. *No token-design impact — flagged so
   the layout choice is a conscious one.*

3. **Tabs / indentation consistency unspecified.** §3/§5.1 don't state tab handling.
   v1 = spaces-only semantics (a tab is one whitespace byte, no tab-stop expansion,
   no tab/space-mixing error). CPython expands tabs to 8-column stops and errors on
   inconsistent tab/space use. *Flagged as a hardening item; pick a rule for v2.*

4. **`'_'` is listed among `keywords` in §5.1** but is semantically the wildcard
   (pattern/expr), not a reserved word. Lexed as its own `PT_USCORE` token (a
   lexeme of exactly `"_"`); identifiers like `_foo` / `x_1` are normal LIDENTs.
   *No action needed — noting the classification choice.*

None of these materially changed the token design beyond adding `PT_BAR`, so per the
brief I proceeded with the CPython-standard behavior and documented each choice. The
`PT_BAR` addition is the one item I'd like explicitly ratified.

---

## 6. Captured golden-test output (EVIDENCE)

`bash frontend/build-m1.sh` → transpile (0 errck ×4) → link (176 MB) → run/diff:

```
>> [1/4] transpile M1 DATS (jsemit00)
   - pylexing_token   - pylexing_print   - pylayout   - pylexing_harness
>> [2/4] link runtime + lib2xatsopt(SED-namespaced) + glue + DATS
   linked 1702147 lines (176M)
>> [3/4] run the golden harness over frontend/TEST/*.py
   [ok]   t01_def      [ok]   t02_ifelif   [ok]   t03_match   [ok]   t04_nested
   [ok]   t05_brackets [ok]   t06_record   [ok]   t07_dedent_eof
>> M1 GOLDEN: PASS (all snippets match)
```

### Evidence snippet A — `t01_def.py` (a `def` + inline `if`/`else`)

Source:
```
def fact(n: Int) -> Int:
    if n <= 0: 1
    else: n * fact(n - 1)
```
Dump (`KIND[lexeme]@(row:bytecol-row:bytecol)`, half-open spans):
```
KW_DEF@(0:0-0:3)      LIDENT[fact]@(0:4-0:8)   LPAREN@(0:8-0:9)
LIDENT[n]@(0:9-0:10)  COLON@(0:10-0:11)        UIDENT[Int]@(0:12-0:15)
RPAREN@(0:15-0:16)    ARROW@(0:17-0:19)        UIDENT[Int]@(0:20-0:23)
COLON@(0:23-0:24)     NEWLINE@(0:24-0:24)
INDENT@(1:4-1:4)      KW_IF@(1:4-1:6)          LIDENT[n]@(1:7-1:8)
LTE@(1:9-1:11)        INT[0]@(1:12-1:13)       COLON@(1:13-1:14)   INT[1]@(1:15-1:16)
NEWLINE@(1:16-1:16)   KW_ELSE@(2:4-2:8)        COLON@(2:8-2:9)
LIDENT[n]@(2:10-2:11) STAR@(2:12-2:13)         LIDENT[fact]@(2:14-2:18)
LPAREN@(2:18-2:19)    LIDENT[n]@(2:19-2:20)    MINUS@(2:21-2:22)   INT[1]@(2:23-2:24)
RPAREN@(2:24-2:25)    NEWLINE@(2:25-2:25)
DEDENT@(3:0-3:0)      DEDENT@(3:0-3:0)         EOF@(3:0-3:0)
```
*(Verbatim, one-per-line, in `frontend/TEST/t01_def.golden`.)* Note: `->` →
`ARROW@(0:17-0:19)` (2 bytes), `<=` → `LTE@(1:9-1:11)`, `Int` → `UIDENT` (case),
`fact`/`n` → `LIDENT`. The inline `if c: e` / `else: e` open **no** block (correct),
so only the `def` body produces one INDENT and the matching DEDENT at EOF (the second
DEDENT is the same `def` body level — there is exactly one open level, col 4).

### Evidence snippet B — `t05_brackets.py` (LAYOUT EDGE CASE: bracket suppression)

Source (newlines INSIDE `[ … ]` and `( … )` are implicit line joins):
```
let xs = [
    1,
    2,
    3
]
let r = f(a,
          b,
          c)
```
Dump (note: **no** NEWLINE/INDENT/DEDENT between rows 3–5 or 7–9 — layout suppressed
inside brackets; spans still advance across physical lines):
```
KW_LET@(2:0-2:3)  LIDENT[xs]@(2:4-2:6)  EQ@(2:7-2:8)  LBRACK@(2:9-2:10)
INT[1]@(3:4-3:5)  COMMA@(3:5-3:6)
INT[2]@(4:4-4:5)  COMMA@(4:5-4:6)
INT[3]@(5:4-5:5)
RBRACK@(6:0-6:1)  NEWLINE@(6:1-6:1)
KW_LET@(7:0-7:3)  LIDENT[r]@(7:4-7:5)  EQ@(7:6-7:7)  LIDENT[f]@(7:8-7:9)  LPAREN@(7:9-7:10)
LIDENT[a]@(7:10-7:11)  COMMA@(7:11-7:12)
LIDENT[b]@(8:10-8:11)  COMMA@(8:11-8:12)
LIDENT[c]@(9:10-9:11)  RPAREN@(9:11-9:12)  NEWLINE@(9:12-9:12)
EOF@(10:0-10:0)
```
**No spurious INDENT/DEDENT** — both bracketed multi-line expressions are joined; the
only NEWLINEs are at the *logical* ends (rows 6 and 9). EOF emits no DEDENT (nothing
was indented). This is the required bracket-suppressed-newline edge case.

### Evidence snippet C — `t07_dedent_eof.py` (LAYOUT EDGE CASE: dedent-to-EOF, no trailing `\n`)

Source (ends `a + b` deep in nested blocks, **no final newline**):
```
def outer(n: Int) -> Int:
    if n > 0:
        let a = 1
        let b = 2
        a + b
```
Dump tail — at EOF the final `NEWLINE` is synthesized, then both open blocks (col 8
`let`-body, col 4 `if`-body) close with `DEDENT`s back to base col 0:
```
LIDENT[a]@(6:8-6:9)  PLUS@(6:10-6:11)  LIDENT[b]@(6:12-6:13)
NEWLINE@(6:13-6:13)
DEDENT@(6:13-6:13)   DEDENT@(6:13-6:13)
EOF@(6:13-6:13)
```
Exactly **2** DEDENTs (the base level is never closed), proving R5.

---

## 7. Re-entrancy & purity (plan §6.2)

The lexer is **pure per call by construction**: `pylex_text(src, text)` /
`pylex_layout(src, text)` take the source as an argument, call `PYL_load(text)` —
which **wholesale replaces** the FFI byte buffer (`PYL__bytes`/`PYL__len`) — and scan
from `cur_init() = @(0,0,0)`. There is **no module-level mutable accumulator** that
persists between calls; the only mutable state is the FFI buffer, which is fully
re-set on every `PYL_load`. Verified: lexing file A, then B, then A again yields
byte-identical dumps for A (cross-run determinism check passed). This satisfies the
LSP resident-process requirement (safe to call repeatedly in one warm process).

---

## 8. Scope boundary

M1 is **lexer + layout only**. No parser (M2), no PyAST, no lowering. The `pytoken`
datatype in `pylexing.sats` is the seam M2 consumes. Spans are real and byte-accurate
today, so when M2/lowering thread them into L2 nodes (plan §6.3), diagnostics land on
the `.py` source for free.

---

## 9. Purely-additive check

```
$ git status --short        # (relevant excerpt)
?? frontend/SATS/pylexing.sats
?? frontend/DATS/pylexing_token.dats  pylexing_print.dats  pylayout.dats  pylexing_harness.dats
?? frontend/CATS/pylexing.cats
?? frontend/build-m1.sh
?? frontend/TEST/t0[1-7]_*.{py,golden}
?? frontend/docs/M1-REPORT.md
```
**Zero modifications under `srcgen2/` or `language-server/`.** No M0 file
(`pyfront.*`, `build-m0a.sh`, `build-m0b.sh`) was edited. Requirement met.
```
$ git status --short | grep -E "srcgen2/|language-server/"   →  (no output)
```
