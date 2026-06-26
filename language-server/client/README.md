# ATS3 Language Support (VSCode LSP client)

A VSCode extension that provides ATS3 (ATS-Xanadu) language support — type-error
diagnostics, hover (inferred type), go-to definition / type-definition,
find-references, document & workspace symbols, inlay hints, semantic-token
highlighting, and completion — by launching the in-process **resident** ATS3
language server and speaking LSP/JSON-RPC over stdio.

The server is the same ATS3 source compiled two ways; this `.vsix` ships the
**Chez** build (`chez-lsp-resident.so`, from the `xats2cz` backend) and launches
it as `chez --script <so> --stdio`.

## Install from a `.vsix`

```sh
code --install-extension ats3-lsp-client.vsix
# or: VSCode → Extensions view → "..." menu → Install from VSIX...
```

### Requirements

- **Chez Scheme** on `PATH` (or set `ats3.server.chezBin` to its absolute path).
- **`ats3.xatshome`** — an installed extension has no copy of the ATS3/Xanadu
  repo next to it, so it cannot guess where the prelude lives. Point it at your
  repo root (the server reads the prelude from there at runtime):

```jsonc
// settings.json
{ "ats3.xatshome": "/absolute/path/to/ATS-Xanadu" }
```

Equivalently, export `XATSHOME` in the environment VSCode is launched from. If
neither is set (or the path does not exist), the extension shows an actionable
error and the server does not start — it never silently crashes.

## Settings

| Setting                 | Purpose                                                                                     |
| ----------------------- | ------------------------------------------------------------------------------------------- |
| `ats3.server.backend`   | `auto` (default; prefers the bundled Chez server), `chez`, or `deno`.                       |
| `ats3.server.chezPath`  | Override the path to `chez-lsp-resident.so` (empty = auto-resolve from `server-dist`/repo). |
| `ats3.server.chezBin`   | The Chez executable used to run the `.so` (default `chez`).                                  |
| `ats3.xatshome`         | Path to the ATS3/Xanadu repo root (`XATSHOME`). **Required for an installed `.vsix`.**       |
| `ats3.server.denoPath`  | Path to the alternative self-contained Deno server binary (when `backend` is `deno`).       |
| `ats3.trace.server`     | LSP trace level (`off` / `messages` / `verbose`).                                            |

## Develop / package

```sh
npm install
npm run bundle                         # esbuild -> dist/extension.js
cp ../server/BUILD/chez/chez-lsp-resident.so server-dist/chez-lsp-resident.so
vsce package --no-dependencies --allow-missing-repository --out ats3-lsp-client.vsix
```

`.vscodeignore` excludes `src/`, dev `node_modules`, scripts, and tsconfig, and
**includes** `dist/extension.js` + `server-dist/**`. At runtime the client
resolves the Chez `.so` from `<extension>/server-dist/` first (packaged), then
the repo `server/BUILD/chez/` (dev/F5).
