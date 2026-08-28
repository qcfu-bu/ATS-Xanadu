# ATS3 LSP server on the Go backend — the plan

Mission (see `../README.md`): an LSP server for ATS3, WRITTEN IN ATS3,
compiled by the **xats2go** Go backend into ONE native binary.  Maximum
ATS3, minimum externs; efficient and responsive per edit; fresh compiler
process per typecheck (the frontend is one-shot).

Update this file per milestone.  Architect = qcfu; implementation =
Claude; the architect reviews commits and decides open questions.

---

## Status

| Milestone | State |
|---|---|
| M1 — resident echo (framing + JSON + lifecycle) | **DONE** (2026-08-28) |
| M2 — diagnostics via check-only driver | next |
| M3 — hover + go-to-definition | — |
| M4 — wire the VSCode client | — |

**M1 measured:** cold spawn → `initialize` response round-trip **3.3 ms**
(best of 5); binary 3.4 MB; golden suite 6/6 incl. multibyte, \u-escape
(surrogate pair), parse-error, and 7-byte-chunked-delivery cases, each
output independently re-validated by `tests/check-stream.py` (Python
recomputes Content-Length byte math and re-parses every JSON body).

---

## Architecture (as built for M1)

### One Go package from separately-emitted modules
Each server DATS is emitted to Go **separately** (one compiler run per
module) and assembled into one `package main` by `tools/build.sh`, which
mirrors `srcgen2/xats2go/selfhost-build/assemble.sh`:
strip per-module headers; rename per-module ANF temps
(`goxtnm`→`go<N>tnm`, `goxtmpl`→`go<N>tmpl`); rename each module's
`func main()` (its top-level `val` effects) to `Zzmodinit_<N>`; dedup
the per-layout constructor structs (`Zzs_*`/`ZzpZzs_*`); generate
`func main()` = the modinits in assembly order (the driver's serve loop
is the last one).  **No print-store flush in main** — stdout is the
protocol channel.

Cross-module calls link because SATS-declared symbols emit as
stamp-mangled names (`Z_json_parse_<stamp>`) and stamps are
deterministic in the loaded-SATS order.  Hence the **stamp discipline**:
every DATS includes the ONE manifest `HATS/lspserver_sats.hats` (same
SATS set, same order, for every module); any SATS/HATS edit invalidates
every emission (build.sh enforces via mtime).

### Emitter support (compiler changes, landed with M1)
Two edits in `srcgen2/xats2go/srcgen2/DATS/go1emit_utils0.dats`, both
gated by `build.sh quick` (psuite 75/75) + `gate`:
1. `go1emit_package_pathq` also treats `language-server/go-server/` as
   package source — SATS-declared server symbols emit/reference as
   stamped package names instead of bridging to nonexistent
   `xatsgo.Xats_*` runtime hooks.
2. `d2cstgo1`'s `goleafq` also accepts `XATS2GO_*` externs declared
   under `language-server/go-server/` — the server's spliced `.cats`
   floor behaves exactly like the prelude's CATS/GO floor (bare
   `$`→`_`-mangled names).

**Consequence:** until a selfcycle rebuilds the selfhost binary with
these edits, server emission must use the **bundle**
(`srcgen2/BUILD/xats2go-bundle.patched.js`, refreshed by every
`build.sh quick`).  `tools/build.sh` defaults to the bundle;
`XLSP_EMIT=selfhost` switches over later.

### Prelude completion (landed with M1)
`prelude/DATS/CATS/GO/strn000.{dats,cats}`: the deferred
**string-construction** primitive `strn_make_fwork` got its GO-arm
floor leaf (`XATS2GO_strn_make_fwork`, a `strings.Builder`).  This makes
`strn_append` + all prelude string builders work in GO-arm programs
(they previously bridged to a nonexistent runtime leaf and failed the Go
build).  Appended at EOF (stamp-safe); no existing test exercises the
old path, and quick/gate stay green.

### The byte-string model
GO-arm strings are native Go strings = **byte strings**: `strn_length`
counts bytes, `strn_get$at`/`byte_at` yield bytes.  All parsing/framing
is byte-indexed; **Content-Length arithmetic is therefore exact for
UTF-8 by construction**.  The emit-char contract of
`XATS2GO_strn_make_fwork`: a code ≤ 0xFF appends that **byte** (so
per-byte copies round-trip UTF-8); codepoint encode/decode (JSON \u,
later UTF-16 column math in `lsp_u16`) is done explicitly in ATS.

### The extern floor (M1: 4 leaves)
`CATS/GO/lsp_floor.cats` — kept a one-pager; belief-consistent types:
- `XATS2GO_LSP_read_chunk() string` — blocking stdin read, "" = EOF
- `XATS2GO_LSP_write_out(s string) any` — stdout (protocol)
- `XATS2GO_LSP_write_log(s string) any` — stderr (log)
- `XATS2GO_LSP_now_ms() int` — monotonic ms (for M2 debounce)
Pre-authorized floor additions (per the project brief): process
spawn/reap for the M2 checker.  ANYTHING else: ask the architect first.

### The resident loop
`lsp_main.dats`: `serve(buf)` is a named tail-recursive loop (the Go
backend's real TCO → O(1) stack), owning ALL state as parameters — no
module-level cells in M1.  `lsp_frame.frame_next` is a pure function
over the buffer; `lsp_json` is a total recursive-descent parser
(`JVerr` on failure, no exceptions) and a one-pass serializer (a single
`strn_make_fwork` per document → O(n)).

### Module map (assembly order = staload order)
| module | role |
|---|---|
| `lsp_floor` | extern floor wrappers |
| `lsp_util`  | byte-level string helpers (slice, index-of, itoa…) |
| `lsp_json`  | jval datatype, parse, serialize, accessors |
| `lsp_frame` | Content-Length framing (pure) + frame_wrap |
| `lsp_main`  | dispatch loop, lifecycle handlers (driver) |

---

## Build & test

```sh
tools/build.sh              # emit (mtime-cached) + assemble + go build
tools/build.sh clean        # force full re-emit
tests/run-tests.sh          # golden transcripts (UPDATE=1 regenerates)
```
Prereqs: the bundle exists (run `selfhost-build/build.sh quick` after
any emitter edit); node on PATH for bundle emission; go 1.26.

Per-module frontend pre-flight (fast, node-free):
`XATSHOME=<repo> srcgen2/xats2go/selfhost-build/src/xats2go-selfhost DATS/<m>.dats 2>&1 >/dev/null | grep -c "F3PERR0-ERROR\|PREAD00-ERROR"` — want 0.

---

## M1 protocol surface (implemented)

- Framing: `Content-Length` (exact-case match) + CRLFCRLF; other headers
  ignored; incremental across arbitrary read boundaries (t06 proves 7-byte
  chunks); response frames are written as ONE string.
- `initialize` → capabilities `{textDocumentSync:{openClose,change:1}}` +
  serverInfo; `initialized` ignored; `shutdown` → null; `exit` → loop
  ends (process exits 0).
- Unknown REQUEST → `-32601` (echoes the method); unknown NOTIFICATION →
  ignored; unparseable body → `-32700` with `id:null`.
- JSON: ints (`JVint`), non-integral numbers preserved textually
  (`JVnum`, lossless re-serialization); strings are UTF-8 bytes; \u
  escapes (incl. surrogate pairs) decode to UTF-8; serializer escapes
  only what JSON requires.

## Known M1 limits / open questions for the architect

1. **exit code fidelity**: LSP says exit(1) if no `shutdown` was seen.
   The loop just returns (always exit 0).  Fix needs a process-exit
   extern (or the floor's write path tracking) — worth an extern?
2. **Framing desync policy**: `FRerr` (missing/malformed
   Content-Length) logs + terminates the loop.  Alternative: resync
   scan.  Terminating is the conservative M1 choice.
3. **Header-name case**: exact `Content-Length:` only (every real
   client sends canonical case).
4. A garbage stream with no header terminator grows the buffer without
   bound until EOF.  Bounded-buffer cutoff if it ever matters.
5. Buffer append is `strn_append` per chunk (O(buf) copy): a 1 MB
   message arriving in 16 chunks copies ~16 MB ≈ ms.  A chunk-list
   buffer is the upgrade if profiles ever show it.

---

## M2 plan (next): diagnostics

1. **Check-only driver** next to `srcgen2/xats2go/srcgen2/UTIL/`
   (`xats2go_tcheck01.dats`, name TBD): the goemit01 pipeline STOPPED
   after `f3perr0_d3parsed` (+ the PREAD00 report, commit 55d930eeb) —
   no trxd3i0/intrep/emission.  Build it into a binary over the existing
   selfhost-build assembly (swap the driver; keep zz_floor/zz_shims),
   per the typecheck-only note in the xats2go-dev-cycle memory.  Driver
   interface (argv/stderr format) needs the ARCHITECT'S REVIEW before
   M3 extends it to queries.
2. **Floor**: add spawn/reap leaves (pre-authorized): spawn(argv) →
   pid/handle, nonblocking reap poll or blocking wait — design so the
   serve loop stays single-threaded: poll the child between stdin
   reads?  NO — better: blocking read with a short-timeout variant, or
   a wait-either leaf.  Decide with a probe; keep the floor minimal.
3. **lsp_docs**: didOpen/didChange/didSave handlers, full-text sync,
   version tracking, module-level store (a0rf cell) or loop-state.
4. **Debounce + stale-drop**: `lsp_now_ms`; drop responses for
   superseded versions.
5. **Diagnostics shaping**: parse `PREAD00-ERROR`/`F3PERR0-ERROR`
   stderr lines → LSP ranges.  0-based internal vs 1-based printed
   locations (the compiler PRINTS 1-based) — the driver should emit a
   machine format with INTERNAL 0-based values instead of scraping the
   pretty report; that is part of the driver-interface review.
   Columns: UTF-8 bytes → UTF-16 code units via `lsp_u16` (pure ATS,
   golden-tested on multibyte fixtures).
6. **Latency bar**: measure didChange→publishDiagnostics on
   `language-server/fixtures/Foo.dats`; budget dominated by the checker
   process (~1.8 s full pipeline today; the check-only driver cuts the
   back half; report real numbers).

Deferred (per the brief): completion, workspace indexing, incremental
sync.
