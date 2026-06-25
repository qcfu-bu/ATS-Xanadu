# ATS3 Language Support (VSCode LSP client)

A VSCode extension that provides ATS3 language support — diagnostics, hover, and
go-to-definition — by launching the in-process **resident** ATS3 language server
and speaking LSP/JSON-RPC over stdio.

This extension can be run two ways:

- **From source (dev):** open this folder in VSCode and press `F5` (Run
  Extension). It resolves the server and `XATSHOME` from the in-repo layout.
- **Installed (`.vsix`):** build a self-contained package and install it. The
  packaged extension ships the server and its runtime deps inside itself.

## Install from a `.vsix`

```sh
code --install-extension ats3-lsp-client.vsix
# or: VSCode → Extensions view → "..." menu → Install from VSIX...
```

### Required configuration: `ats3.xatshome`

An **installed** extension has no copy of the ATS3/Xanadu repo next to it, so it
**cannot** guess where the prelude lives. You must point it at your repo root:

```jsonc
// settings.json
{
  "ats3.xatshome": "/absolute/path/to/ATS-Xanadu"
}
```

Equivalently, export `XATSHOME` in the environment VSCode is launched from. If
neither is set (or the path does not exist), the extension shows an actionable
error and the server does not start — it never silently crashes.

The server binary itself is bundled inside the extension
(`<extension>/server-dist/xats-lsp-resident.opt1.js`) along with its runtime
`node_modules`, so you do **not** need to set `ats3.server.module`.

## Settings

| Setting                | Purpose                                                                                                  |
| ---------------------- | -------------------------------------------------------------------------------------------------------- |
| `ats3.xatshome`        | Path to the ATS3/Xanadu repo root (`XATSHOME`). **Required for installed `.vsix`.**                       |
| `ats3.server.module`   | Override the server entrypoint (absolute path). Empty = auto-resolve (packaged `server-dist`, then repo). |
| `ats3.server.nodePath` | Path to the `node` executable used to launch the server.                                                  |
| `ats3.trace.server`    | LSP trace level (`off` / `messages` / `verbose`).                                                         |

## How packaging works

Building the `.vsix` is fully scripted:

```sh
npm install
npm run package        # -> ats3-lsp-client.vsix
```

`npm run package` does three things:

1. **`npm run bundle`** — esbuild bundles `src/extension.ts` (and inlines
   `vscode-languageclient`) into a single `dist/extension.js`
   (`--external:vscode`, CJS, minified). `package.json` `main` points here.
2. **`npm run copy-server`** (`scripts/copy-server.js`) — copies the **current**
   resident server artifact
   (`../server/resident/BUILD/xats-lsp-resident.opt1.js`) and its runtime
   `node_modules` (`vscode-languageserver`, `vscode-languageserver-textdocument`,
   and their deps) into `server-dist/`. Because the server requires those modules
   from a **sibling** `node_modules`, they must sit next to the copied `.js` —
   which is exactly the `server-dist/` layout.
3. **`vsce package`** — zips it into the `.vsix`, honoring `.vscodeignore`
   (excludes `src/`, dev `node_modules`, `out/`, tsconfig; **includes** `dist/`
   and `server-dist/`).

At runtime, `resolveServerModule` (in `src/extension.ts`) looks for the packaged
server at `<extensionPath>/server-dist/xats-lsp-resident.opt1.js` **first**, so
an installed extension always uses its bundled copy; the repo-relative dev paths
are only fallbacks for the F5 case.

> The server bytes are copied at **package time**, so re-running `npm run
> package` always snapshots the latest server build.

## Develop

```sh
npm install
npm run compile        # tsc -> out/ (type-check; F5 uses dist via bundle)
npm run bundle         # esbuild -> dist/extension.js
```
