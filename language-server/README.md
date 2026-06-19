# ATS3 Language Server

An LSP server + VSCode client for **ATS3 (ATS-Xanadu)**. The server is written in ATS3 itself
(transpiled to JavaScript, run on Node, calling Node LSP libraries via FFI); the VSCode client is
a standard TypeScript extension.

**Feature goals (priority order):** (1) type-error diagnostics → (2) hover (type at cursor) →
(3) go-to definition / type / implementation.

## Start here (docs)
- **`docs/ATS3-COMPILER-PRIMER.md`** — how the ATS3 compiler works, focused on what the LSP needs
  (pipeline, front-end API, diagnostics model, location indexing, type/symbol model, JS FFI &
  build). Read before touching code.
- **`docs/LSP-ARCHITECTURE-AND-PLAN.md`** — architecture, the checker↔server JSON contract,
  decisions log, phased plan, subagent work breakdown.
- **`contract/`** — machine-checkable form of the JSON contract: `bundle.schema.json`, a
  dependency-free `validate-bundle.js`, canonical `fixtures/`, and `fake-checker.js` (a stand-in
  checker used to develop the server before the real one exists).

## Architecture in one paragraph
The compiler is strictly one-shot (no state reset), so type-checking runs in a **fresh `node`
subprocess per check** (the *checker*) that emits a JSON bundle `{diagnostics, hovers,
definitions}` to a temp file. A long-lived ATS3 *server* caches that bundle per `(uri, version)`
and answers hover/definition **from cache** — so one compile per document change feeds all three
features and interactive requests stay instant. The *client* is a thin TS extension that launches
the server over stdio and is swap-ready (set `ats3.server.module`).

## Layout
```
language-server/
  docs/             # primer + architecture/plan (source of truth)
  contract/         # JSON-bundle schema, validator, fixtures, fake-checker
  client/           # TS VSCode extension (vscode-languageclient)         [WS-0b ✅]
  server/
    stub/           # throwaway JS stub server (WS-0b round-trip proof)   [WS-0b ✅]
    lsp-server/     # the real ATS3 server → xats-lsp-server.js           [WS-1b 🚧]
    <checker>/      # the real ATS3 checker → xats-lsp-check.js           [WS-1a 🚧]
  scripts/smoke.js  # headless LSP round-trip test (no GUI)
  fixtures/Foo.dats # sample file for the dev host
  spikes/ffi/       # verified ATS3→JS→npm FFI/build spike                [WS-0a ✅]
```

## Status
| Phase | Workstream | State |
|---|---|---|
| P0 | WS-0a ATS3→JS FFI/build spike | ✅ verified (`spikes/ffi/`) |
| P0 | WS-0b client scaffold + stub round-trip | ✅ verified (smoke test passes) |
| P1 | WS-1a checker (structured diagnostics JSON) | ✅ verified (`server/BUILD/xats-lsp-check.js`) |
| P1 | WS-1b server (spawn/cache/publish diagnostics) | ✅ verified (real checker, true end-to-end) |
| P2 | WS-2 hover | ✅ verified (real checker, true end-to-end) |
| P3 | WS-3 navigation (definition + type-definition) | ✅ verified (incl. cross-file into prelude) |
| P4 | WS-4 hardening (UTF-16 cols, perf, async checks, packaging, tests) | ⏳ planned |

All three feature goals work against the **real** type-checker end-to-end (machine-verified via
smoke tests); the client now defaults to the real ATS3 server. Remaining is the editor GUI try
(F5, below) and P4 hardening.

## Build everything, then F5
```sh
export XATSHOME=/Users/qcfu/Projects/ATS-Xanadu
# 1) checker (one-time ~6-9 min builds the 171MB compiler-as-library, then the checker)
cd language-server/server && bash build-lib2xatsopt.sh && bash build.sh
# 2) server
cd lsp-server && npm install && bash build.sh && cd ..
# 3) client
cd ../client && npm install && npm run compile
```
**Verify headlessly (no GUI):**
```sh
# diagnostics + hover/def round-trips against the REAL checker:
cd language-server/server/lsp-server
ATS3_LSP_CHECKER=$PWD/../BUILD/xats-lsp-check.js SMOKE_TIMEOUT_MS=120000 node scripts/smoke.js
ATS3_LSP_CHECKER=$PWD/../BUILD/xats-lsp-check.js SMOKE_TIMEOUT_MS=120000 node scripts/smoke-nav.js
```
**See it in the editor (F5):** open the **`client/` folder** in VSCode, press **F5** ("Run ATS3
Extension") → in the Extension Development Host open any `.dats`/`.sats` → type errors appear as
squiggles (Problems panel), **hover** shows inferred types, and **Go to Definition / Go to Type
Definition** jump to the binding / type constant (incl. into the prelude). The client auto-resolves
`server/lsp-server/xats-lsp-server.js` and sets `XATSHOME` for the checker; override via
`ats3.server.module` / `ats3.xatshome`. If the server isn't built, it falls back to the WS-0b stub.
Set `"ats3.trace.server": "verbose"` to inspect JSON-RPC.

Pinned: `vscode-languageclient`/`vscode-languageserver` `9.0.1`, `vscode-languageserver-textdocument`
`1.0.12`, `typescript` `5.9.3` (9.x chosen over 10.x for VSCode `^1.82.0` compatibility).

## Toolchain
Node ≥ 20 (verified on v26) + npm. ATS3 builds use the prebuilt JS compilers in `../xassets/JS/`
with `XATSHOME=/Users/qcfu/Projects/ATS-Xanadu`; see primer §10.3 for the recipe. Compiler is GPLv3
(repo root); this subproject follows the repo's licensing.
