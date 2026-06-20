# M1 fix — spaces-only indentation (leading TAB is a hard error)

> **Status: DONE.** A TAB (0x09) in a logical line's **leading (indentation)
> whitespace** now emits a `PT_ERROR` token over the offending byte instead of being
> silently consumed. The lexer does **not** throw (non-fail-fast, like the rest of
> M1). A tab *after* the first non-whitespace token of a line stays ordinary inline
> whitespace (unchanged). All 7 existing M1 goldens still pass; one new golden
> (`t08_tab_indent`) fires the error.

---

## 1. The rule (SURFACE-GRAMMAR §3, lead-architect ruling)

"Indentation must be spaces — tabs are NOT allowed. A tab character in a line's
**leading (indentation) whitespace is a hard error**: the lexer emits a diagnostic
(error token) rather than guessing a tab width — no tab-stop, no spaces/tabs mixing,
no silent acceptance. Tabs *after* the first non-whitespace token (e.g. between
operands) are ordinary whitespace."

This supersedes the v1 M1-REPORT.md §3 edge-case #2 / §5 hardening-item #3 ("a tab is
one lenient whitespace byte").

---

## 2. What changed — and exactly where the check lives

**One source file changed:** `frontend/DATS/pylexing_token.dats` — the **raw
scanner** (`scan_loop`). Nothing else (`pylayout.dats`, the SATS contract, the
printer, the harness, the CATS glue) needed to change.

### Why the raw scanner, not `pylayout.dats`

The layout pass only ever sees **real tokens + `PT_NL_RAW` markers**; the raw scanner
**discards all inline whitespace** (spaces *and* tabs, via `is_inws`) before layout
runs (`pylexing_token.dats` old line 386–387: `else if is_inws(b) then
scan_loop(src, cur_adv(c), acc)`). So by the time `pylayout.dats` runs, the
leading-whitespace **composition** (was it spaces? a tab?) is already gone — only the
first real token's byte *column* survives. The tab is therefore only observable in
the raw scanner. This matches the task's contingency note: the leading-indentation
scan discards whitespace composition in the raw scanner, so the minimal fix is there
(no layout refactor required).

### The change (minimal + additive)

`scan_loop` gained a single threaded-by-value boolean `bol` ("beginning of line" = we
are still in the **leading** whitespace of the current logical line — no real token
seen yet). No global state; the lexer stays pure/re-entrant by construction.

- `bol` is **true** at input start (`pylex_text` seeds `scan_loop(..., true, ...)`)
  and **true** again immediately after emitting a `PT_NL_RAW`.
- A **new branch** placed *before* the generic `is_inws` skip:
  ```
  else if band(bol, b = 9) then   // a TAB in LEADING indentation: HARD ERROR (§3)
    let
      val c1 = cur_adv(c)
      val tk = mk_tok(src, PT_ERROR(PYL_slice(c.0, c1.0)), c, c1)
    in scan_loop(src, c1, true, list_cons(tk, acc)) end
  ```
  → emits a **1-byte `PT_ERROR`** spanning exactly the tab `@(row:col - row:col+1)`,
  advances past it (so the first real token's byte column is unchanged), and stays
  `bol=true` (so a *run* of leading tabs yields one `PT_ERROR` per tab).
- The generic `is_inws` skip now runs only for **non-leading** whitespace, or for
  leading **spaces** (a leading space is `is_inws` but not byte 9, so it skips
  normally and keeps `bol=true`). A tab encountered when `bol=false` (after the first
  real token) falls through to `is_inws` → skipped as ordinary whitespace. **Tabs
  after the first token are unchanged.**
- Every branch that produces a **real token** (ident / number / string / char / op,
  and the lone-backslash `PT_ERROR`) now passes `bol=false`. The `#`-comment skip and
  leading spaces keep `bol` unchanged. A `\`-continuation keeps `bol` unchanged (it
  does **not** start a new logical line).

`pylex_text` seeds `bol=true`. No other entry/signature changed; `pylex_layout` and
the SATS contract are untouched (the `PT_ERROR of strn` ctor already existed).

---

## 3. Edge cases considered

| Case | Behavior |
|---|---|
| **Tab AFTER the first token** (`let x =\t1`) | Ordinary whitespace — `bol=false`, falls through to `is_inws`, skipped. **No error.** (Verified in t08 line 1: `=`→`1` join has no ERROR.) |
| **Leading tab** (`\tx + n`) | `PT_ERROR[<tab>]@(r:0-r:1)`; scanning continues. (t08 lines 1 & 2.) |
| **Mixed leading spaces + tab** (e.g. `␠␠\tfoo`) | Spaces skipped (kept `bol`), the tab fires one `PT_ERROR` at its byte column, then `foo`. One error per leading tab; spaces are not errors. |
| **Run of leading tabs** (`\t\tfoo`) | One 1-byte `PT_ERROR` **per tab** (stays `bol=true` between them), then `foo`. Precise spans, no merging. |
| **Tab-only line** (`\t\n`) | The tab(s) fire `PT_ERROR`(s); then the `\n` → `PT_NL_RAW`. The layout pass sees the `PT_ERROR`(s) as the line's "real" content; whether that counts as blank vs. flagged is M2's call — the lexer faithfully reports the tab error and does not crash. |
| **Comment-only line with a leading tab** (`\t# c`) | Leading tab → `PT_ERROR`; then the `#` comment is skipped to EOL. (The comment carries no real token, so `bol` stays true — the rule still applies to the tab.) |
| **CRLF / continuation** | Unchanged. `\r` is `is_inws` (skipped); a `\`-continuation joins lines and leaves `bol` unchanged, so the continued physical line's leading whitespace is **not** re-treated as indentation (correct — it's one logical line). |
| **Layout not mis-counted** | Because the `PT_ERROR` sits at byte col 0 (it *is* the line's first token from layout's view), no spurious INDENT is computed for a tab-"indented" body, and EOF emits no stray DEDENTs. The stream stays balanced — no crash, no mis-count. |

---

## 4. Captured evidence

### 4a. All goldens pass (`bash frontend/build-m1.sh`)

```
   [ok]   t01_def
   [ok]   t02_ifelif
   [ok]   t03_match
   [ok]   t04_nested
   [ok]   t05_brackets
   [ok]   t06_record
   [ok]   t07_dedent_eof
   [ok]   t08_tab_indent
>> M1 GOLDEN: PASS (all snippets match)
```

The 4 M1 DATS still transpile with **0 errck** (the build reached the run/diff phase;
no `errck`/`F2PERR0`/`F3PERR0` was reported). The 7 pre-existing goldens are
byte-identical (unchanged).

### 4b. The new tab-error golden fires — `t08_tab_indent.py`

Source (bytes; `\t` = TAB 0x09 — a leading tab on lines 1 & 2, plus a tab *between*
`=` and `1` on line 1):
```
def f(n: Int) -> Int:
\tlet x =\t1
\tx + n
```
Layout dump (`frontend/TEST/t08_tab_indent.golden`, verbatim):
```
KW_DEF@(0:0-0:3)
LIDENT[f]@(0:4-0:5)
LPAREN@(0:5-0:6)
LIDENT[n]@(0:6-0:7)
COLON@(0:7-0:8)
UIDENT[Int]@(0:9-0:12)
RPAREN@(0:12-0:13)
ARROW@(0:14-0:16)
UIDENT[Int]@(0:17-0:20)
COLON@(0:20-0:21)
NEWLINE@(0:21-0:21)
ERROR[	]@(1:0-1:1)        <- LEADING TAB on line 1 → PT_ERROR (span col 0–1)
KW_LET@(1:1-1:4)
LIDENT[x]@(1:5-1:6)
EQ@(1:7-1:8)
INT[1]@(1:9-1:10)          <- tab BETWEEN `=` and `1` (col 8) caused NO error
NEWLINE@(1:10-1:10)
ERROR[	]@(2:0-2:1)        <- LEADING TAB on line 2 → PT_ERROR (span col 0–1)
LIDENT[x]@(2:1-2:2)
PLUS@(2:3-2:4)
LIDENT[n]@(2:5-2:6)
NEWLINE@(2:6-2:6)
EOF@(3:0-3:0)
```
(The `ERROR[…]` lexeme is the literal tab byte; the span `@(1:0-1:1)` / `@(2:0-2:1)`
pins it to byte column 0.) Two leading tabs → exactly two `PT_ERROR`s with correct
spans; the inline tab after `=` is unaffected; the stream is balanced (one NEWLINE per
logical line, a clean EOF, **no crash, no mis-counted INDENT/DEDENT**).

---

## 5. Scope / purity

- **Files changed:** `frontend/DATS/pylexing_token.dats` (the scanner) +
  `frontend/TEST/t08_tab_indent.{py,golden}` (new golden) + this report. No existing
  golden was modified; `pylayout.dats`, `pylexing.sats`, `pylexing_print.dats`,
  `pylexing_harness.dats`, `pyparsing.*`, `pycore.*`, `pyelab.*`, `pyfront.*`, every
  M0 file, and everything under `srcgen2/` / `language-server/` are untouched.
- **Pure / re-entrant:** the only new state is the by-value `bol` flag threaded
  through `scan_loop`; no module-global lexer state was added. The lexer remains safe
  to call repeatedly in one warm process.
