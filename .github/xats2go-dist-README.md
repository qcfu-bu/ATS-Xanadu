# xats2go — prebuilt binaries

Two static, dependency-free Go binaries built from the ATS-Xanadu tree:

| binary           | what it does                                                        |
|------------------|---------------------------------------------------------------------|
| `xats2go`        | the compiler: typechecks a `.dats` file and emits Go on stdout       |
| `xats2go-tcheck` | check-only driver (no emission) — what the ATS3 LSP server runs      |

## XATSHOME is required

Both binaries read the prelude from `$XATSHOME` and **panic** if it is unset.
Point it at a checkout of the ATS-Xanadu repository, and give source paths
relative to it (path text is embedded in the emitted location comments, so
running from the repo root keeps emissions reproducible):

```sh
export XATSHOME=/path/to/ATS-Xanadu
cd "$XATSHOME"
xats2go srcgen2/DATS/xsymbol.dats > out.go
```

Progress chatter goes to stderr; the emitted Go goes to stdout between
`//==XATS2GO-BEGIN==` and `//==XATS2GO-END==` sentinels. The exit code is not
the error signal — check stdout/stderr for `F3PERR0-ERROR`, `TREAD12-ERROR`
and `TREAD23-ERROR`.

## Building these yourself

```sh
cd srcgen2/xats2go/selfhost-build
./build.sh full
```

On a fresh checkout this first bootstraps the frontend library and the emitter
bundle from the tracked seed compiler (~30–45 min), then emits all 193 modules
and builds. It needs **node** and **go 1.26+**.

Note on memory: the default build has the Go inliner on, which makes the
resulting compiler ~1.8× faster but makes the `zzfe2` package compile peak at
about **8 GB of RSS**. On a machine with less RAM than that the Go compiler is
OOM-killed and `go build` reports `compile: signal: killed`. Build with the
inliner off instead:

```sh
XGCFLAGS='all=-l' ./build.sh full   # ~1.2 GB peak, binaries ~1.8x slower
```
