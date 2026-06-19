# ATS3 LSP — Architecture & Implementation Plan

> Companion to `ATS3-COMPILER-PRIMER.md` (read that first for compiler internals).
> This doc is the **source of truth for architecture, the checker↔server contract,
> the phased plan, and the work breakdown**. Implementors and reviewers should treat
> §2 (architecture), §4 (JSON contract), and their assigned workstream in §6 as binding.

Goals, in priority order (from the project brief):
1. **Type-error diagnostics**
2. **Hover** (type at cursor)
3. **Go-to definition / type / implementation**

---

## ⚡ ARCHITECTURE REVISION R1 — resident in-process checking (supersedes D1/D2)

> Decided 2026-06-18 after benchmarking against the author's own LSP
> (`github.com/qcfu-bu/ats-lsp`). The original process-per-check design (§2–§4 below)
> works and isolates state, but pays ~0.33 s per check (fresh node + reparse the bundle +
> reload the prelude). The resident model below is **~10–30× faster per keystroke** and is
> what we are moving to. Sections §2–§4 are kept for history; R1 is now binding.

**Model (mirrors qcfu-bu/ats-lsp — credit to that design):** ONE resident artifact that
bundles the compiler in-process with the LSP server. Prelude loaded **once** at startup; each
check reuses the warm compiler. No subprocess, no temp-file JSON contract.

**How the one-shot-state problem (primer §4) is solved — surgical cache eviction, not reset.**
The compiler caches each translated file in `the_d{1,2,3}parenv` (xglobal.sats:256/284/298),
which are **plain JS objects keyed by canonical filename (`fpath.fnm2()`)**. To re-check an
edited file you don't reset the whole compiler — you just **evict that file's key**:
`env_reset(topmap, key) ≈ delete env[key]`. The prelude and unchanged deps stay cached (fast);
only the edited file (and its dependents) re-translate. A **dependency graph** records "B
staloads A" so editing A evicts A **and** B.

**Request flow (matching the reference):**
- startup: `the_fxtyenv_pvsload()`, `the_tr12env_pvsl00d()`, set `--_XATSOPT_` /
  `--_SRCGEN2_XATSOPT_` flags; `connection.listen()`.
- `onDidChangeContent` → **prune only** (evict the file + dependents from the caches). Cheap.
- `onDidOpen` / `onDidSave` → **validate**: `d3parsed_of_fil{dats,sats}(realPath)` in-process →
  harvest diagnostics + build the hover/def index from the same `d3parsed` → `sendDiagnostics`
  + cache the index per uri. (v1 reads the saved file on disk, like the reference — clean cache
  keying and correct relative-staload resolution. **Live-on-change is a follow-up**, now cheap
  because checks are warm.)
- hover / definition: answered from the cached index (unchanged from our current design — and a
  feature the reference may not fully ship, so we keep our lead there).

**Build:** ONE artifact (no separate checker). Link: runtime + `lib2xatsopt` + our harvest DATS
+ server FFI `.cats` (vscode-languageserver bindings) → Closure SIMPLE. Reuse `srcgen2/lib/
lib2xatsopt.js` (or the prebuilt minified `lib2xatsopt2js_ats3_opt1.js` if present in XATSHOME).

**What we reuse from our existing code:** the harvest traversals + `s2typ` pretty-printer
(`server/DATS/xats_lsp_check.dats`, `CATS/xats_lsp_check.cats`) and the vscode-languageserver
FFI (`server/lsp-server/xats-lsp-server.{dats,cats}`). The checker subprocess + the JSON
contract become internal/optional (still useful for the CLI `ats-check.sh`).

**New mechanisms to port from the reference:** `env_reset` (JS `delete env[key]` over
`the_d?parenv_pvstmap()`), the `depset`/`depgraph` (JS `Set`/`Map`), and the dependency-extract
pass that populates the graph from a checked `d3parsed`.

---

## R2 — robust invalidation: content-validated cache + project index (queued after R1)

> Closes a real gap in the event-driven model (R1 / the reference): **out-of-band edits** (other
> editors, `git pull`/`checkout`/`rebase`, codegen, formatters run outside the editor) fire no
> `onDidChange`/`onDidSave`, so `the_d?parenv` keeps a stale entry → wrong diagnostics for that
> file and its dependents. This is where ours improves on the reference. Builds on R1's resident
> model + `env_reset`; do R1 first.

**Layer A — content-validated cache (the robust core; not event-dependent).** Stamp each cached
**workspace** file with a signature `{mtimeMs, size}` (or a content hash) when it is validated.
**Before every check, pre-walk the target file's staload closure and `stat` each entry; evict
(env_reset) any whose on-disk signature changed, then cascade to dependents via the graph.** This
makes correctness independent of *how* a file changed — editor event or not. `stat` is ~µs, the
closure is bounded, so the cost is negligible against a warm check.
- **Scope to the workspace; never stat/evict the prelude or XATSHOME libs** — they're assumed
  stable for the session (that's the whole point of loading the prelude once). Offer an explicit
  `ats3.reloadPrelude` command for the compiler-dev case instead.

**Layer B — eager file monitoring (promptness, so stale state doesn't linger until next check).**
- Register LSP **`workspace/didChangeWatchedFiles`** for `**/*.{sats,dats,hats}` (client-side
  native watcher; catches in-workspace external edits, creates, deletes). On an event → update the
  index + `env_reset` the file + cascade. This is the idiomatic, efficient trigger.
- Layer A remains the backstop for anything the watcher misses (network FS, races, edits outside
  the workspace root). Belt **and** suspenders.

**Layer C — project index (complete cascade + future features).** On `initialize` (workspace
folders) and incrementally on watch events, scan `*.{sats,dats,hats}` and parse only their
`#staload`/`#include` directives (cheap regex/lex — NOT a type-check) to build the **whole-project
dependency graph** (forward + reverse). The reference's graph is built only from *checked* files,
so a dependent that hasn't been opened yet is invisible; a project index gives complete reverse
edges, so editing `A` correctly invalidates *every* dependent of `A`, opened or not. Also the
foundation for later workspace-wide features (find-references, workspace symbols, rename).

**Eviction stays the same primitive** (R1's `env_reset` over `the_d{1,2,3}parenv` keyed by
`fnm2`); R2 only improves *what triggers it and how completely it cascades*.

### Edge case: the workspace IS the prelude / compiler tree (`$XATSHOME`)
This breaks the resident model's load-the-prelude-once assumption, and **`env_reset` is not
enough to fix it**. Two distinct stores hold prelude state:
1. **Per-file caches** `the_d{1,2,3}parenv` — keyed by `fnm2`, *evictable* via `env_reset`.
2. **Global, load-once envs** — `the_fxtyenv`, `the_sexpenv`/`the_dexpenv`, `the_d2cstmap`, etc.,
   populated by `the_fxtyenv_pvsload`/`the_tr12env_pvsl00d` and **gated by `the_ntime`** (load
   once, never re-run). The prelude's *definitions* live here, **not keyed by file**, so there is
   no surgical way to evict them — and the compiler ships **no reset API** (primer §4).

Consequences if a prelude file is edited in-session:
- Evicting its `the_d?parenv` entry re-translates that one file, but the **stale definitions
  remain in the global envs** → the edit is not truly reflected.
- Because **every** file staloads the prelude, a stale prelude **poisons all checks**, not just
  the edited file. Correctness for the whole workspace depends on the prelude being current.

**Behavior we implement (graceful, correct):**
- **Detect** when a changed/saved file resolves under `$XATSHOME` (prelude/compiler tree).
- On such an edit, the only correct refresh is to **reload the prelude**, which — absent an
  in-process reset — means **restarting the resident server** (debounced; the client re-launches
  it and the new process loads the edited prelude fresh). Also exposed as the
  **`ats3.reloadPrelude`** command. Cost: one prelude reload (~0.3 s) per prelude edit-batch —
  fine for compiler-dev.
- **Surface it in the UI/log** ("prelude-tree edit → reloading prelude") so the slower,
  reload-based mode is not mysterious.
- We do **not** silently `env_reset` prelude files and pretend it worked — that would give wrong
  diagnostics (the trap above).

**The real fix (available to you as the compiler author):** add a `reset`/`reload` API to
`xglobal` that clears the global envs (`the_fxtyenv`/`the_sexpenv`/`the_d2cstmap`/`the_d?parenv`)
and resets the `the_ntime` gates. Then in-process prelude reload becomes possible and R2 can treat
prelude files like any other invalidatable file — no restart. This is the principled long-term
answer to the compiler's one-shot-state limitation (primer §4, §12).

**Sequencing:** R1 (resident + event eviction) → **R2a** content-validated cache (biggest
robustness win, smallest surface) → **R2b** watched-files + project index. R2a alone already fixes
the user's external-edit scenario; R2b adds promptness and completeness.

---

Constraint from the brief: **the LSP server is written in ATS3** (compiled to JS, run on
node) and uses existing node JSON-RPC / LSP libraries via FFI. The **VSCode client** is a
standard TypeScript extension (the VSCode extension API is JS/TS — unavoidable).

---

## 1. Why the design is shaped the way it is (the two hard constraints)

From the primer, two compiler facts dictate the whole architecture:

- **C1 — The compiler is strictly one-shot** (no state reset; global stamp/symbol/env tables
  leak between runs). ⇒ **Type-checking must happen in a fresh `node` process that exits after
  one file.** We cannot keep a resident in-process type-checker.
- **C2 — Errors live in the AST as `…errck` nodes; types live on `d3exp.styp()`; def-locations
  ride on entity objects.** ⇒ A single front-end run can, in one pass, harvest **diagnostics +
  a hover index + a definition index**. We compute all three together and serialize them.

These combine into the core idea:

> **Compile-once-per-version, serve-from-cache.** On each (debounced) document change, spawn a
> one-shot **checker** process that runs the front-end and emits a JSON bundle
> `{ diagnostics, hovers, definitions }`. The long-lived **server** caches that bundle per
> `(uri, version)` and answers hover / definition / diagnostics from the cache **without
> re-invoking the compiler**. Only a content change triggers a new compile.

This sidesteps C1 (each compile is a fresh process) and exploits C2 (one compile feeds all three
features), and keeps interactive requests (hover/def) instant despite cold-start compile cost.

---

## 2. Architecture

```
┌────────────────────┐   LSP/JSON-RPC over stdio   ┌───────────────────────────────┐
│  VSCode CLIENT      │ ◀─────────────────────────▶ │  LSP SERVER  (ATS3 → JS, node) │
│  (TypeScript ext)   │                              │  language-server/server        │
│  language-server/   │                              │                                │
│   client            │                              │  • JSON-RPC via                │
│  • activates on ATS │                              │    vscode-languageserver/node  │
│  • launches server  │                              │    (bound via FFI)             │
│  • vscode-          │                              │  • TextDocument sync + debounce│
│    languageclient   │                              │  • per-(uri,version) cache of  │
└────────────────────┘                              │    {diagnostics,hovers,defs}   │
                                                     │  • on change → spawn checker   │
                                                     │  • hover/def answered from cache│
                                                     └───────────────┬───────────────┘
                                                                     │ spawn (one-shot)
                                                                     │ argv: file + --json-out
                                                                     ▼
                                                     ┌───────────────────────────────┐
                                                     │  CHECKER  (ATS3 → JS, node)    │
                                                     │  language-server/server (2nd   │
                                                     │  entrypoint / 2nd built JS)    │
                                                     │  • links the ATS3 front-end    │
                                                     │  • d3parsed_of_fil{sats,dats}  │
                                                     │  • harvest traversal →         │
                                                     │    diagnostics + hover index + │
                                                     │    def index                   │
                                                     │  • writes JSON bundle, exits   │
                                                     └───────────────────────────────┘
```

**Three deployable artifacts:**
- **client** — `language-server/client/`, a TypeScript VSCode extension. Thin: declares the
  `ats`/`ats3` languages, starts the server over stdio with `vscode-languageclient`.
- **server** — `language-server/server/`, ATS3 source compiled to a long-lived node script
  (`xats-lsp-server.js`). Owns the JSON-RPC connection, document store, debounce, cache, and
  spawns the checker.
- **checker** — ATS3 source compiled to a one-shot node script (`xats-lsp-check.js`) that links
  the compiler front-end and emits the JSON bundle. May share an ATS3 source tree with the
  server (two `main`s) or be a separate program; **separate program is simpler** because the
  checker must bundle the whole compiler and the server must not.

**Process model details:**
- Server is launched once by the client, lives for the session.
- Per change (after ~300–500 ms debounce), server writes the current buffer to a temp file
  (handles unsaved edits), spawns `node --stack-size=8801 xats-lsp-check.js <tmpfile>
  --json-out <tmp.json> --uri <original-uri>`, waits, reads `<tmp.json>`, updates cache,
  publishes diagnostics.
- Concurrency: at most one in-flight checker per document; supersede stale runs. A small pool/
  queue caps total concurrent `node` processes.
- **Why temp file + `--json-out` (not stdout):** the linked compiler prints heavy debug tracing
  to stdout (primer §10.4). Writing the JSON bundle to a dedicated file avoids all stream-mixing.
  (Stretch: silence the tracing and use a stdout sentinel.)

---

## 3. Decisions log (binding unless revisited with the architect)

| # | Decision | Rationale |
|---|---|---|
| D1 | One-shot **checker subprocess** per compile; **no** resident in-process compiler. | Compiler global state can't be reset (primer §4). |
| D2 | **Compile-once-per-version; cache** diagnostics+hover+def; serve interactive requests from cache. | One front-end run yields all three (primer §6–8); avoids per-keystroke cold start. |
| D3 | Checker emits a **JSON bundle to a temp file** (`--json-out`); server reads it. | Stdout has debug noise (primer §10.4). |
| D4 | **Server in ATS3**, **client in TS**, **checker in ATS3** (separate program from server). | Brief requires ATS3 server; VSCode client must be TS; checker must bundle the compiler, server must not. |
| D5 | Coordinates: internal **0-based** values via accessors; never parse printed (1-based) text. line=`nrow`; char=`ncol` (ASCII v1; UTF-16 conversion later). | Primer §5 display trap. |
| D6 | Diagnostics dedup: keep innermost (smallest-range) `…errck`, collapse by begin-position; drop `lvl ≥ 3`. | Cross-level/nested redundancy (primer §6). |
| D7 | v1 severity = always `Error`; messages authored per-constructor. | No severity/messages in compiler (primer §6). |
| D8 | Phase 0 **de-risking spikes** (toolchain/FFI, client↔stub round-trip) land before feature work. | FFI+build is the highest-uncertainty area; everything depends on it. |
| D9 | Cross-file incremental (edit A → recheck dependents) is **out of scope for v1**. | No cache invalidation in compiler (primer §3). Re-check on open/change of the focused file only. |

Open questions to resolve as we go (not blockers): cold-start latency budget (measure in Phase
0); whether to silence compiler tracing; whether to bundle a pinned prebuilt compiler vs build
from `srcgen2` in CI.

---

## 4. The checker ↔ server JSON contract (v1 — frozen interface)

The checker writes UTF-8 JSON to the `--json-out` path. **All positions are 0-based; `line`=`nrow`,
`character`=`ncol` (byte column; ASCII-correct in v1).** This decouples the two workstreams: the
checker team and the server team build against this contract in parallel.

```jsonc
{
  "schema": 1,
  "uri": "file:///abs/path/Foo.dats",   // echoed from --uri
  "ok": true,                            // false only if the checker itself crashed
  "nerror": 2,
  "diagnostics": [
    {
      "range": { "start": {"line": 0, "character": 13}, "end": {"line": 0, "character": 20} },
      "severity": 1,                     // 1=Error (LSP DiagnosticSeverity); v1 always 1
      "code": "type-mismatch",           // stable kebab id per error kind (see §4.1)
      "message": "expected `int`, got `string`",
      "source": "ats3"
    }
  ],
  "hovers": [                            // hover index: one entry per typed node with a type
    {
      "range": { "start": {"line": 0, "character": 4}, "end": {"line": 0, "character": 5} },
      "type": "int",                     // source-syntax type string (new pretty-printer)
      "kind": "expr"                     // expr | pat
    }
  ],
  "definitions": [                       // def index: one entry per resolved use site
    {
      "useRange":  { "start": {"line": 5, "character": 8}, "end": {"line": 5, "character": 11} },
      "defUri":    "file:///abs/path/Foo.dats",
      "defRange":  { "start": {"line": 0, "character": 4}, "end": {"line": 0, "character": 5} },
      "entity":    "var",                // var | cst | con
      "typeDefUri":   "file:///.../prelude/...",   // optional: head type-constant location
      "typeDefRange": { "start": {...}, "end": {...} }   // optional
    }
  ]
}
```

**Phasing of the contract:** Phase 1 ships only `diagnostics` (others may be `[]`). Phase 2 adds
`hovers`. Phase 3 adds `definitions`. The schema is stable; later phases only populate more arrays.

### 4.1 Error `code` vocabulary (extend as encountered)
Start with a small stable set the server maps to messages/telemetry:
`type-mismatch` (`D3Et2pck` under `…errck`), `unbound-identifier` (`D2Enone1(D1Eid0 …)`),
`unresolved-template` (`D3Etimp`/`D3Etimq`), `pattern-error` (`D?Perrck`), `decl-error`
(`D?Cerrck` not otherwise classified), `unknown` (fallback). The checker assigns `code`; the
message is authored alongside.

---

## 5. Phased delivery (aligned to the goal priority)

| Phase | Outcome | Gates on |
|---|---|---|
| **P0 — De-risk** | (a) ATS3 "hello-FFI" program builds to JS, `require`s an npm module, runs on node. (b) VSCode client launches a *stub* server and renders one hard-coded diagnostic. | nothing (start now) |
| **P1 — Diagnostics** | Real type errors from the focused file appear as squiggles in VSCode, live, debounced. Checker emits `diagnostics`; server spawns checker, caches, publishes. | P0 |
| **P2 — Hover** | Hovering an expression shows its type. Checker adds `hovers` (needs the `s2typ` pretty-printer + position index); server answers `textDocument/hover` from cache. | P1 |
| **P3 — Navigation** | Go-to-definition (and type-definition; implementation where feasible). Checker adds `definitions`; server answers `textDocument/definition` etc. | P1 (parallel to P2) |
| **P4 — Hardening** | UTF-16 columns, perf (cold-start budget, cancellation of superseded checks), config (toolchain path), packaging (`.vsix`), tests. | P1–P3 |

---

## 6. Work breakdown (subagent assignments)

Each workstream (WS) has an **implementor** (writes code) and is checked by a **reviewer** who
reports a summary back to the architect (me). Reviewers verify against this doc's contract and
the primer's facts; the architect decides fit. Keep WS deliverables small and contract-bounded.

> Process note (how the architect runs this): implementors deliver code + a self-test; a reviewer
> independently builds/runs and reports (what was implemented, does it meet the contract, risks).
> The architect integrates only the reviewer's summary into the global plan. Implementors must
> cite primer anchors they relied on so reviewers can verify.

### WS-0a — Toolchain & FFI spike  *(P0, implementor; critical path)*
- **Deliver:** `language-server/spikes/ffi/` containing a minimal `.dats` that (1) binds
  `console.log`, (2) `require()`s a node builtin (`fs`) and an npm module, (3) reads `argv` and a
  file, (4) registers an ATS callback invoked from JS. Plus a `build.sh` implementing the
  primer §10.3 recipe and a `README` with exact commands + measured run output.
- **Acceptance:** `bash build.sh && node app.js` prints expected output, incl. data flowing
  through the npm module. Document any deviation from the primer recipe.
- **Why first:** validates the entire ATS3→JS→npm path that every later WS depends on.

### WS-0b — Client scaffold + stub round-trip  *(P0, implementor; parallel to 0a)*
- **Deliver:** `language-server/client/` TS VSCode extension (package.json, tsconfig, extension.ts)
  that registers languages `ats`(.sats)/`ats3`(.dats) and starts a server over stdio via
  `vscode-languageclient`. A **stub server** (may be plain JS/TS initially) that returns a single
  hard-coded diagnostic on open, to prove the editor round-trip. `.vscode/launch.json` for F5
  debugging.
- **Acceptance:** Opening a `.dats` in the Extension Development Host shows the hard-coded
  squiggle. Independent of the ATS3 build.

### WS-1a — Checker: structured diagnostics  *(P1, implementor; gates on WS-0a)*
- **Deliver:** `language-server/server/` ATS3 checker program: copy `UTIL/xatsopt_tcheck00.dats`
  skeleton → run `d3parsed_of_fil{sats,dats}` → **new harvest traversal** (model on
  `f3perr0_dynexp.dats`) collecting `(loctn, code, message)` with dedup (D6) → write the §4 JSON
  bundle (`diagnostics` only) to `--json-out`. Build script producing `xats-lsp-check.js`.
- **Acceptance:** On the primer's sample (`val x: int = "hello"` + unbound name) emits exactly the
  expected deduped diagnostics with correct **0-based** ranges and `type-mismatch` /
  `unbound-identifier` codes. Reviewer diffs against the contract.
- **Relies on primer:** §3 (API), §5 (coords), §6 (errck/codes/dedup), §9 (traversal template).

### WS-1b — Server: spawn, cache, publish  *(P1, implementor; gates on WS-0a/0b, contract §4)*
- **Deliver:** ATS3 LSP server (replacing the WS-0b stub): bind enough of
  `vscode-languageserver/node` via FFI (createConnection, TextDocuments, onDidChangeContent,
  sendDiagnostics, onInitialize) + `child_process` + temp files. Debounce; one-shot checker spawn;
  parse JSON bundle; cache per `(uri,version)`; publish diagnostics. FFI glue in a `.cats`.
- **Acceptance:** Editing a `.dats` live updates squiggles end-to-end through the real ATS3
  checker. Cache holds the bundle for P2/P3 to consume.
- **Note:** this is the largest FFI surface; lean on WS-0a's proven idioms.

### WS-2 — Hover  *(P2, implementor; gates on P1)*
- **Deliver (checker side):** position-indexed `hovers` array — a traversal collecting
  `(range, typeString, kind)` for `d3exp`/`d3pat` nodes via `.styp()`; **a new source-syntax
  `s2typ` pretty-printer** (primer §7). **Deliver (server side):** `textDocument/hover` answered
  by innermost-range lookup in the cached `hovers`.
- **Acceptance:** Hover over a `val`-bound variable and a literal shows readable types.

### WS-3 — Navigation  *(P3, implementor; gates on P1, parallel to WS-2)*
- **Deliver (checker side):** `definitions` array — traversal collecting
  `(useRange, defLoc)` from `D3Evar/D3Ecst/D3Econ` entities (`entity.lctn()`), plus optional
  `typeDef` from `styp()` head `T2Pcst` → `s2cst_get_lctn`. **Deliver (server side):**
  `textDocument/definition` + `typeDefinition` (+ `implementation` where feasible) from cache.
- **Acceptance:** Go-to-def jumps to the binding site within-file and into prelude files;
  type-definition jumps to the type constant's declaration.

### WS-4 — Hardening  *(P4, implementor; after P1–P3)*
- UTF-16 column conversion; supersede/cancel stale checks; configurable toolchain path
  (`XATSHOME`, compiler JS location); `.vsix` packaging; a small fixture test-suite (sample
  `.dats` → expected JSON bundle) runnable in CI.

### Reviewers
- **R-build/FFI** verifies WS-0a, WS-1a, WS-1b actually build & run on this machine and match the
  contract; reports anchors checked.
- **R-correctness** verifies diagnostics/hover/def outputs against hand-computed expected results
  on fixtures; hunts for coord off-by-ones, dedup gaps, and unhandled AST constructors.

---

## 7. Directory layout (target)

```
language-server/
  docs/
    ATS3-COMPILER-PRIMER.md          # compiler internals (onboarding)
    LSP-ARCHITECTURE-AND-PLAN.md     # this file
  client/                            # TS VSCode extension
    package.json  tsconfig.json  src/extension.ts  .vscode/launch.json
  server/                            # ATS3 LSP server + checker
    DATS/ SATS/ CATS/                # ATS3 sources + FFI glue
    build.sh                         # produces xats-lsp-server.js, xats-lsp-check.js
    BUILD/                           # generated JS (gitignored)
  spikes/                            # P0 de-risking throwaways
    ffi/                             # WS-0a
  fixtures/                          # sample .dats + expected JSON bundles (WS-4 tests)
```

---

## 8. What I (architect) own vs delegate
- **Own:** this architecture, the §4 contract, the §3 decisions, phase gating, reviewer
  acceptance, and keeping the global view. I update these docs as facts change.
- **Delegate:** all implementation (WS-*) and independent verification (R-*). Implementors work
  to the contract + primer; reviewers report summaries; I integrate decisions, not file dumps.
