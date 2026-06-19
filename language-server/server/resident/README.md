# Resident in-process ATS3 LSP server (workstream R1)

ONE long-running artifact that bundles the ATS3 compiler front-end with the
vscode-languageserver loop and checks **in-process**. The prelude loads **once**
at startup; every subsequent check reuses the warm compiler. This replaces the
old process-per-check model (`../lsp-server/` + `../BUILD/xats-lsp-check.js`),
which is kept intact for the CLI.

Mirrors the project author's own LSP (`github.com/qcfu-bu/ats-lsp`).

## How it works

- **Startup (once):** `the_fxtyenv_pvsload()`, `the_tr12env_pvsl00d()`,
  `xatsopt_flag$pvsadd0("--_XATSOPT_")`, `--_SRCGEN2_XATSOPT_`, then
  `initialize(validator, pruner)` starts the connection loop.
- **didOpen / didSave → validate:** resolve the file path from the uri, run
  `d3parsed_of_fil{dats,sats}(path)` in-process (no subprocess, no temp JSON),
  harvest diagnostics + a hover/def index from that `d3parsed`,
  `sendDiagnostics`, and cache the index per-uri for hover/definition.
- **didChange → prune only (the make-or-break part):** evict the edited file AND
  its transitive dependents from `the_d{1,2,3}parenv` via
  `env_reset(topmap, key) ≈ delete env[key.stmp()]`. The topmaps are plain JS
  objects keyed by the file's canonical stamp (`fnm2().stmp()`; see
  `srcgen2/DATS/xsymmap_topmap.dats`), so `delete env[stamp]` evicts exactly that
  file. A `depset`/`depgraph` (JS Set/Map) records "B staloads A" so editing A
  evicts A and B. The prelude + unchanged files stay cached → warm rechecks.
- **hover / definition / type-definition / semantic-tokens:** answered from the
  cached per-uri harvest index.
- **WS-5 rich features** (all from the same cached index / project scan):
  - `documentSymbol` — outline from the harvest's top-level-decl pass.
  - `references` + `documentHighlight` — derived by inverting the cached
    `definitions` by `(defUri, defRange)` (no new harvest data).
  - `inlayHint` — inferred `: <type>` on un-annotated `val`-bindings.
  - `workspace/symbol` — fuzzy match over a textual top-level-decl index built
    during the project scan.
  - `completion` (WS-6 Stage 1) — index-backed identifier + keyword completion
    (current-file / project / prelude / keywords), prefix-filtered, **no
    re-parse**. Member completion (after `.`) is deferred to Stage 3. See
    `../../docs/COMPLETION-PLAN.md`.

## Files

- `SATS/xats_lsp_resident.sats` — FFI surface (url/severity/range/diagnostic,
  depset/depgraph, `env_reset`, harvest push primitives, `text_validator` /
  `cache_pruner`, `initialize`).
- `HATS/libxatsopt_resident.hats` — compiler-header include (libxatsopt +
  locinfo/lexing0/dynexp1/filpath).
- `DATS/xats_lsp_resident.dats` — FFI impls, the dependency-extraction pass
  (ported from the reference `dependency30_*`), the harvest traversal +
  s2typ pretty-printer (reused from `../DATS/xats_lsp_check.dats`), and the
  validator / pruner / startup.
- `CATS/xats_lsp_resident.cats` — the JS glue: vscode-languageserver connection
  loop, `JS_map_reset` (= `delete env[key]`), depset/depgraph JS, harvest
  accumulators → per-uri index, dedup (Decision D6) + friendly type names.
- `build.sh` — ONE-artifact build (runtime + `lib2xatsopt` + `.cats` + transpiled
  DATS → Closure SIMPLE). Reuses the prebuilt `srcgen2/lib/lib2xatsopt.js`.
- `scripts/smoke-resident.js` — verification: diagnostics, **cache-eviction
  correctness** (stale-vs-fresh), hover, definition, warm-latency.
- `scripts/smoke-depgraph.js` — cross-file invalidation (edit A → B re-checks).
- `scripts/smoke-ws5.js` — WS-5: documentSymbol, references, documentHighlight,
  inlayHint, workspace/symbol (all over the LSP protocol).
- `scripts/smoke-completion.js` — WS-6 Stage 1: completion candidates
  (current-file / prelude / keyword), textEdit range, member-context deferral.

## Build & run

```sh
export XATSHOME=/Users/qcfu/Projects/ATS-Xanadu
bash build.sh                       # -> BUILD/xats-lsp-resident.opt1.js (~4 MB)
node --stack-size=8801 BUILD/xats-lsp-resident.opt1.js --stdio
```

## Verify

```sh
node scripts/smoke-resident.js      # diagnostics + eviction + hover/def + latency
node scripts/smoke-depgraph.js      # cross-file depgraph invalidation
```

## Measured (this machine, node v26)

- one-time prelude load (spawn → listening): ~**380 ms** (paid once).
- per-check (in-process `d3parsed` + harvest of a small edited file): **1–8 ms**.
- old process-per-check baseline: ~**370 ms / keystroke** → ~**50–370× faster**.
