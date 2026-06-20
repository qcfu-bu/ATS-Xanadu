# WS-6 — Autocomplete (`textDocument/completion`)

**Status:** architecture de-risked (Stage-3 type→members API confirmed); Stage 1
(lexical core) implemented. Stages 2–4 planned below.

This is the marquee Tier-2 feature. It is fundamentally different from WS-5
(hover/def/symbols/inlays): those run on a *successfully type-checked* AST, but
completion fires on **incomplete, often unparseable** code (`lis|`, `foo.ba|`),
many times per second, and must stay well under ~100 ms.

---

## 1. The two grounding constraints (why the design is shaped this way)

1. **The compiler environment is lookup-only.** `tr12env` exposes
   `find`/`qfind`/`ofind` (resolve a *named* identifier) but **no `foreach` /
   enumeration**, and there is no global topmap/symmap enumeration API either
   (`srcgen2/SATS/*`). So we **cannot** ask the compiler "what names are in scope
   here?" the way a from-scratch semantic engine would. Candidate **enumeration**
   must come from sources *we* can walk: the harvest AST + textual indices.

2. **In-memory buffer parsing already exists.** The resident's live path runs
   `d0parsed_from_atext_named(stadyn, text, path)` → `d3parsed_of_trans03(…)` on
   the unsaved buffer string in **~1–8 ms warm** (no temp file). So we can
   munge + re-parse an in-progress buffer in-process when a context genuinely
   needs types.

Conclusion: **index-based completion driven by textual context detection, with
best-effort semantic refinement** where a re-parse (or the cached type index)
provides types. This is a legitimate, common LSP architecture — many production
servers are index-based — and it composes existing pieces rather than building a
new engine.

---

## 2. Layered architecture

### Layer 0 — Candidate indices ("what exists"), all enumerable by us
| Source | Reuse | Lifecycle |
|---|---|---|
| **Prelude/global names** (`print`, `list0`, `+`, …; ~3300) | **the loaded pervasive name envs** — `the_dexpenv_pvstmap() : topmap(d2itm)` + `the_sexpenv_pvstmap() : topmap(s2itm)`, enumerated with `topmap_strmize`. The names the startup parse already extracted; **no second parse, no regex, no compiler change** (see §5). | built at startup + on `reload_prelude` |
| **Project names** (every top-level decl in the workspace) | **already exists** — WS-5 `LSP_ws_symbols_by_file` | kept fresh on edit/watch |
| **Current-file top-level names** | **already exists** — WS-5 per-uri `idx.symbols` | refreshed per validation |
| **In-scope locals** (params, lambda/let/val binders, pattern vars) + visibility range | **new** harvest sink `scope_push` (Stage 2) | per-uri, from the last good parse |
| **Keywords** | static ATS3 keyword list | constant |

Ranking falls out of the source: **locals-in-scope > current-file > project >
prelude > keyword**.

### Layer 1 — Context detection (textual, robust to unparseable buffers)
On a request at `(line, character)`, inspect the buffer text left of the cursor
(no parse needed); extract the **partial identifier** (the word being typed) and
its **replace-range**, and classify:

- `expr.<partial>` → **member** (record fields / datatype constructors of the
  receiver's type) → Layer 2
- `Module.<partial>` / `$EXTERN.` → qualified
- after `:` / a type position → **types** only (datatypes/typedefs/abstypes + type keywords)
- inside `case … of` / a `val` pattern → **constructors** + `_`
- statement start → **keywords + snippets**
- else → **general** identifier prefix

### Layer 2 — Semantic refinement (best-effort) — *only when a context needs types*
Most completions answer from the **cached index with zero re-parse**. Only member
access needs the receiver's type:

1. **Fast path:** the receiver's type is usually already in the **cached hover
   index** (range→type). Member completion = hover-lookup at the position just
   before the `.`, then enumerate members. **No re-parse.**
2. **Slow path (only when the receiver is freshly typed / not in the index):**
   munge the partial token to a placeholder so the buffer parses, run the
   existing `d0parsed_from_atext_named` + `d3parsed_of_trans03`, harvest the
   receiver's `styp()`. On any parse failure → fall back to Layer-1 textual
   candidates. The munge is **never load-bearing**.

**Type → members API (confirmed by spike — all read-only, no compiler change):**

- **Datatype constructors** (for `case x of …`):
  ```
  s2cst_get_d2cs : s2cst → optn_vt(d2conlst)        // dynexp2.sats:1753
  ```
  receiver type → peel to the head `s2cst` (reuse the harvest's existing
  `typedef_aux` wrapper-peeling) → `s2cst_get_d2cs` → each `d2con`:
  name = `symbl_get_name(d2con_get_name(c))`, signature = `d2con_get_styp(c)`.

- **Record fields** (for `record.field`):
  ```
  T2Ptrcd of (trcdknd, npf, l2t2plst)               // statyp2.sats:326
  l2t2p = s2lab(s2typ)                              // a (label, type) pair
  S2LAB of (label, x0)                             // staexp2.sats:93
  datatype label = LABint of sint | LABsym of sym_t // xlabel0.sats:56
  ```
  receiver type → peel to `T2Ptrcd(_,_, l2t2plst)` → each `S2LAB(lab, typ)`:
  field name = `symbl_get_name(sym)` (`LABsym`, named `.foo`) or the index
  (`LABint`, positional `.0`); field type = the `s2typ` for `detail`.

  All accessors are ones the harvest already calls (it pattern-matches the
  analogous `D3LAB`/`l3d3plst`).

### Layer 3 — Assemble / filter / rank / shape
Prefix-filter the chosen candidate set, dedup by name, rank by source + match
quality (encoded in `sortText`), cap (e.g. 200) with `isIncomplete: true` so the
client re-queries as typing continues. Build `CompletionItem[]`: `label`, `kind`
(our SymbolKind → LSP CompletionItemKind), `detail` (signature/type or a source
hint), `textEdit` (replace the partial-identifier range), `insertTextFormat:
Snippet` for keyword/decl templates. `completionItem/resolve` (Stage 4) lazily
fills `documentation` for the selected item.

---

## 3. Staging (shippable increments)

| Stage | Delivers | New code | Risk |
|---|---|---|---|
| **1 — Lexical core** *(implemented)* | identifier + keyword completion from prelude/project/current-file indices; context detection; `onCompletion` + capability | prelude scan, context detector, candidate assembler, handler (all `.cats`) | low — WS-5 reuse, **no re-parse** |
| **2 — Scope-aware locals** *(implemented)* | in-scope locals (params, let-binders) ranked above all globals; a local shadows a same-named global | `scope_push` harvest sink (binder + visibility range) emitted at fun/lambda/let scope-entry, at BOTH d3 and d2 (the d2 path keeps params available while the body is a half-typed/unbound partial — the real live-completion case) | done |
| **3 — Semantic member/dot** | `record.field`, constructors-in-`case` via real receiver types | member context + hover-index/`s2cst_get_d2cs`/`T2Ptrcd` enumeration; munge fallback | low-med — **API confirmed**, read-only |
| **4 — Polish** | `completionItem/resolve` lazy docs; snippets; signature `detail`; fuzzy ranking; trigger-char tuning; request cancellation | resolve handler, snippet templates | low |

---

## 4. Stage 1 — implementation (the lexical core)

All in `resident/CATS/xats_lsp_resident.cats` (+ capability/handler):

- **`LSP_prelude_symbols`** — array of `{name, kind}`, filled by an ATS pass
  (`harvest_prelude_globals` in the resident DATS) that enumerates the loaded
  pervasive **name** topmaps (`the_dexpenv_pvstmap`/`the_sexpenv_pvstmap`) via
  `topmap_strmize` right after `prelude_pvsload`, at startup and on every
  `reload_prelude`. Each `d2itm`/`s2itm` yields a `(name, SymbolKind)`. **No
  regex** (could misread surface syntax → wrong candidates) and **no second
  parse** (reuses the names the startup load already extracted). ~3300 names.
- **`LSP_KEYWORDS`** — static ATS3 keyword list (`val fun fn case of let in end
  if then else lam fix datatype typedef abstype …`).
- **`LSP_sk_to_cik(symKind)`** — SymbolKind → CompletionItemKind map.
- **`LSP_completion_partial(text, offset)`** — walk back over
  `[A-Za-z0-9_$']` to find the word being typed + its start offset; also report
  whether the char before the word is `.` (member context).
- **`LSP_build_completion(uri, position)`** — get the doc text + offset from
  `LSP_documents`, extract the partial, and (for the **general** context only in
  Stage 1) gather current-file + project + prelude + keyword candidates,
  case-insensitive **prefix** filter, dedup by name (best kind wins), rank via
  `sortText = <sourceRank><name>`, cap at 200, build `CompletionItem[]` with a
  `textEdit` replacing the partial range. Member context (`.`) returns an empty
  `isIncomplete` list — deferred to Stage 3.
- **Capability:** `completionProvider: { triggerCharacters: ['.'],
  resolveProvider: false }`. **Handler:** `onCompletion` → `LSP_build_completion`.

**Test:** `resident/scripts/smoke-completion.js` — capability advertised;
completing a prefix returns the expected prelude/project/current-file/keyword
candidates with correct `kind` + a `textEdit` over the partial range; member
context (after `.`) returns empty (Stage-3 placeholder).

---

## 5. Open items / spikes (all non-blocking for Stage 1)

1. **Munge robustness** (Stage 3 slow path) — `val x = foo.|` may still not parse
   after munging; mitigate with a few strategies (delete token / placeholder /
   truncate line) and always fall back to textual candidates.
2. **Request cancellation / debounce** (Stage 4) — supersede stale completion
   requests; we don't yet have `$/cancelRequest` plumbing.
3. **Prelude/global source — RESOLVED (canonical, never regex, no second parse).**
   Decision: a regex can mis-read ATS3 surface syntax (and is blind to a second
   frontend), so it must not back the index. The regex is removed.

   The investigation (each variant built + tested) ruled out the dead ends first:
   the `allist` enumeration is **commented out** upstream (`trans12_myenv0.dats`),
   and the per-file parse caches `the_d{2,3}parenv` are **empty** at startup (they
   cache *checked user files*, not the prelude). Reading `f0_pvsload` (`xglobal.dats`)
   gave the answer: it parses each prelude file **once**, merges the declared names
   into `the_dexpenv`/`the_sexpenv` (via `pvsmrgw` → their **topmaps**), then
   **discards the AST**. So the names are retained in
   `the_dexpenv_pvstmap() : topmap(d2itm)` and `the_sexpenv_pvstmap() : topmap(s2itm)`,
   which are **enumerable via `topmap_strmize`**.

   `harvest_prelude_globals` enumerates those two topmaps and pushes each
   `(name, SymbolKind)` — **reusing the single startup parse** (no re-parse), no
   regex, no compiler change. `the_dexpenv` holds only pervasive names (user decls
   go to per-file scopes), so it is prelude-only — no pollution. `topmap_strmize`
   over the live env is non-destructive (verified: file checks still resolve the
   prelude after enumeration). Yields ~3300 names — *more* complete than the regex's
   1934, since it is the actual loaded/resolved set.
4. **`workspace/symbol` migrated off regex (done).** It (and completion's project
   tier) now answer from the **AST-accurate** per-uri document symbols
   (`LSP_index[uri].symbols`) the harvest already produces — the textual
   `LSP_extract_ws_symbols` is removed. Trade-off: coverage = files the server has
   **checked** (opened/edited), not the whole project; correct-but-narrower beats
   broad-but-wrong. A **background project indexer** (check files off the event
   loop to widen `LSP_index`) is the follow-up for broad coverage. (The one
   remaining regex, `LSP_STALOAD_RE`, parses `#staload` directives for the cache
   invalidation graph — not user-facing symbols — and stays.)
4. **Project-scale candidate iteration** — Stage 1 prefix-filters during
   iteration and caps; if a very large workspace makes this slow, flatten into a
   single pre-sorted index (optimization, not correctness).
