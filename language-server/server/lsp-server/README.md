# WS-1b — LSP server core (`xats-lsp-server.js`)

The ATS3-built Language Server for ATS3 (compiled to JS, run on node). It owns the
JSON-RPC connection over stdio, TextDocument sync, the per-uri debounce, a
per-`(uri,version)` cache of the checker's JSON bundle, and the
spawn → read-`--json-out` → cache → `publishDiagnostics` pipeline. It replaces the
WS-0b stub server.

This is a **standalone ATS3 → JS node program** (like the WS-0a spike), **not** a
compiler-linking build: the ATS3 source is transpiled with the prebuilt jsemit
compiler and `cat`-linked with the runtime + the `.cats` FFI glue.

## Files

| File | Purpose |
|---|---|
| `xats-lsp-server.dats` | The ATS3 program. Owns ALL control flow: `main` (create connection, register handlers, listen), the open/change handlers (the debounce decision), the check pipeline (`run_check`: write-temp → spawn → read-json → cache → publish), and close (clear). FFI is declared via `#extern fun NAME(...) = $extnam()`. |
| `xats-lsp-server.cats` | FFI/marshalling glue (raw JS). `require()`s `vscode-languageserver/node`, `vscode-languageserver-textdocument`, `node:child_process` (`spawnSync`), `node:fs`/`os`/`path`. Implements each `#extern` body; holds the connection, the TextDocuments manager, the debounce-timer table, and the `(uri,version)` bundle cache; shapes LSP `Diagnostic[]` from the parsed bundle. |
| `build.sh` | Primer §10.3 recipe: transpile `.dats` → `.js`, then `cat` the **5** runtime files + the `.cats` (before the compiled output) → `xats-lsp-server.js`. |
| `scripts/smoke.js` | Headless LSP/JSON-RPC round-trip test (adapts WS-0b): initialize → didOpen `sample-bad.dats` → asserts both diagnostics at contract coords; then a clean doc → empty diagnostics. |
| `scripts/smoke-debounce.js` | Asserts a burst of `didChange` for one uri coalesces into exactly one checker spawn. |
| `package.json` | Pins `vscode-languageserver` + `vscode-languageserver-textdocument` so `require` resolves next to `xats-lsp-server.js`. |
| *(generated)* `xats-lsp-server_dats.js`, `xats-lsp-server.js` | Transpiler output and the linked runnable. Git-ignored. |

## Build & run

```sh
cd language-server/server/lsp-server
npm install                                   # vscode-languageserver(-textdocument)
export XATSHOME=/Users/qcfu/Projects/ATS-Xanadu
bash build.sh                                 # -> xats-lsp-server.js
node xats-lsp-server.js --stdio               # run over stdio (logs go to stderr)
```

`build.sh` runs the prebuilt jsemit compiler with `--stack-size=8801` (needed only
when compiling) and detects a bad transpile by grepping the transpiler's **stderr**
for `PERR0-ERROR` (exit code is unreliable). No deviations from the WS-0a-corrected
primer §10.3 recipe.

## Verify

```sh
node scripts/smoke.js            # full round-trip (uses contract/fake-checker.js)
node scripts/smoke-debounce.js   # burst coalescing
```

## Configuration

| Env var | Default | Meaning |
|---|---|---|
| `ATS3_LSP_CHECKER` | sibling `xats-lsp-check.js`, else `../BUILD/xats-lsp-check.js` (WS-1a) | The checker command (`node <it> <src> --uri <uri> --json-out <json>`). Point at `contract/fake-checker.js` for testing. |
| `ATS3_LSP_DEBOUNCE_MS` | `300` | Debounce window for coalescing change bursts. |

## Pointing the WS-0b client at this server

Set the client config key (declared in `client/package.json`):

```jsonc
// .vscode/settings.json
{
  "ats3.server.module": "/Users/qcfu/Projects/ATS-Xanadu/language-server/server/lsp-server/xats-lsp-server.js"
}
```

The client launches it over stdio (it passes `--stdio`), so no client change is
needed beyond this path. Logs appear on stderr (and in the client's trace if
`ats3.trace.server` is set).
