# ATS3 Language Support (VSCode LSP client)

A VSCode extension that provides ATS3 (ATS-Xanadu) language support by
launching the **native ATS3 language server** and speaking LSP/JSON-RPC
over stdio.

The server (`language-server/go-server/`) is written in ATS3 and compiled
by the **xats2go** Go backend into one self-contained binary
(`ats3-lsp-server`) — no runtime dependencies.  Per typecheck it spawns
the CHECK-ONLY compiler driver (`xats2go-tcheck`), so diagnostics need
that second binary plus `XATSHOME` (the repo root, for the prelude).

Current feature surface: **live type-error / syntax diagnostics**
(as-you-type, unsaved buffers included), **hover** (inferred type in
ATS3 surface syntax), and **go-to-definition** (within-file and into
the prelude).  See `../go-server/PLAN.md`.

## Run from source (F5, in-repo)

1. Build the server: `../go-server/tools/build.sh`
2. Build the checker: `../../srcgen2/xats2go/selfhost-build/wire-tcheck.sh`
3. `npm install && npm run bundle`, then F5 (Extension Development Host).

In the in-repo layout everything auto-resolves: the server from
`../go-server/BUILD/`, `XATSHOME` as the repo root, the checker from
`$XATSHOME/srcgen2/xats2go/selfhost-build/src/`.

## Install from a `.vsix`

```sh
npm run package          # bundles + stages both binaries into server-dist/
code --install-extension ats3-lsp-client.vsix
```

An installed extension cannot guess where your ATS3 repo lives, so set:

```jsonc
// settings.json
{ "ats3.xatshome": "/absolute/path/to/ATS-Xanadu" }
```

(or export `XATSHOME` in the environment VSCode is launched from).

## Settings

| Setting                   | Purpose                                                                                    |
| ------------------------- | ------------------------------------------------------------------------------------------ |
| `ats3.server.path`        | Override the server binary (empty = auto-resolve from `server-dist/`, then `go-server/BUILD/`). |
| `ats3.server.checkerPath` | Override the check-only driver (empty = `server-dist/`, then `$XATSHOME/srcgen2/xats2go/selfhost-build/src/`). |
| `ats3.xatshome`           | The ATS3/Xanadu repo root (`XATSHOME`). **Required for an installed `.vsix`.**             |
| `ats3.trace.server`       | LSP trace level (`off` / `messages` / `verbose`).                                          |

The whole server configuration travels in `initialize`'s
`initializationOptions` (`{checker, xatshome}`) — the server reads no
environment variables and takes no CLI flags.
