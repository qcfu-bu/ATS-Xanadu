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
| M2 — diagnostics via check-only driver | **DONE** (2026-08-28) |
| M2.5 — architect decisions: live checks (--stdin), kill-superseded, exit codes, cross-file | **DONE** (2026-08-29) |
| M3 — hover + go-to-definition (index-dump mode) | **DONE** (2026-08-29) |
| M3.5 — semantic tokens (same index mechanism) | **DONE** (2026-08-29) |
| M4 — wire the VSCode client | **code done** (2026-08-28); the human F5 demo remains |

**M1 measured:** cold spawn → `initialize` response round-trip **3.3 ms**
(best of 5); binary 3.4 MB; golden suite incl. multibyte, \u-escape
(surrogate pair), parse-error, and 7-byte-chunked-delivery cases, each
output independently re-validated by `tests/check-stream.py` (Python
recomputes Content-Length byte math and re-parses every JSON body).

**M3/M3.5 measured:** hover / definition / semanticTokens answer in
**~0.1 ms** from the per-uri index cache (refreshed by every check);
suite 12/12 (t11: hover on a fun and a var, def within-file and
cross-file into the prelude, a null miss; t12: the full delta-encoded
token array, verified by an independent Python decoder).

**Semantic tokens (M3.5):** the --index walk also emits
`T \t l0 \t c0 \t l1 \t c1 \t kind` for every identifier
(0 variable / 1 function / 2 enumMember; fun-vs-var by peeling the
entity's styp to T2Pfun1).  The server merge-sorts (O(n log n) — the
index-perf lesson), drops same-start duplicates, delta-encodes, and
declares the legend in semanticTokensProvider.  Tokens refresh per
check; VSCode blends the TextMate grammar between refreshes.
COMPLETION remains open — its JS-era plan needs re-grounding: the
prelude-name enumeration it relied on (topmap_strmize over
the_dexpenv) is the {itm:tbox} generic that errck-erases on this
backend; candidates need an AST-walk route or a concrete strmize in
the shared frontend (stamps move -> architect call).

**M2/M2.5 measured** on `language-server/fixtures/Foo.dats`:
didOpen → publishDiagnostics **283 ms**; **didChange →
publishDiagnostics 583 ms** (250 ms debounce + ~290 ms check of the
UNSAVED buffer via the driver's --stdin mode).  The checker process is
~290 ms on a small file (prelude load dominates), 0.7 s bench-sized,
1.2 s compiler-sized.  Golden suite 10/10 (t07 diagnostics, t08
live-change lifecycle, t09 exit-code, t10 cross-file summary), M2+
cases compared through `normalize-stream.py` (canonical JSON, repo
root → `@X@`).

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

### The extern floor (11 leaves — the full pre-authorized surface)
`CATS/GO/lsp_floor.cats`; belief-consistent types; the ATS side stays
single-threaded (goroutines only pump I/O into buffers):
- `XATS2GO_LSP_read_chunk() string` — blocking stdin read, "" = EOF
- `XATS2GO_LSP_poll_stdin(ms int) int` — 1 data / 0 timeout / 2 EOF
  (shares a pump goroutine + channel with read_chunk)
- `XATS2GO_LSP_write_out(s string) any` — stdout (protocol)
- `XATS2GO_LSP_write_log(s string) any` — stderr (log)
- `XATS2GO_LSP_now_ms() int` — monotonic ms
- `XATS2GO_LSP_spawn_check(prog, a1, a2, a3, xhome, input string) int`
  — start `prog a1 [a2] [a3]` ("" omitted) with XATSHOME=xhome, input
  piped to stdin, stderr AND stdout captured; id or -1
- `XATS2GO_LSP_check_done(id) int` / `_check_output(id) string`
  (stderr) / `_check_stdout(id) string` (the --index records) /
  `_check_drop(id) any` (kills if still running)
- `XATS2GO_LSP_exit(code int)` — process exit (LSP exit-code contract)
That completes the pre-authorized set (stdio/clock/spawn).  ANYTHING
else: ask the architect first.

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
| `lsp_util`  | byte-level string helpers (slice, index-of, itoa, atoi…) |
| `lsp_json`  | jval datatype, parse, serialize, accessors |
| `lsp_frame` | Content-Length framing (pure) + frame_wrap |
| `lsp_uri`   | file:// URI ↔ path (byte-level %-codec) |
| `lsp_diag`  | checker stderr report → LSP Diagnostic array |
| `lsp_main`  | event loop, handlers, doc store, check pump (driver) |

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

## M2 (DONE): diagnostics — as built

1. **Check-only driver:** `srcgen2/xats2go/srcgen2/UTIL/xats2go_tcheck01.dats`
   = goemit01 with the backend removed (stops after the PREAD00 report +
   tread3a/trtmp3b/trtmp3c/t3read0 + `f3perr0_d3parsed`); its stderr is
   byte-compatible with the CLI driver's diagnostic surface (verified by
   diff — goemit01 adds only backend noise).  Built by
   `selfhost-build/wire-tcheck.sh` as a SECOND main package
   (`src/tcheck/`) over the same assembled frontend packages (symbol
   stamps are source-location-derived, so it links against them
   unchanged) → `src/xats2go-tcheck`.  ~0.29 s per small-file check
   (prelude load is the floor), no elevated ulimit needed (native Go
   stacks).  Interface: `xats2go-tcheck <abs-file>`; report on stderr.
2. **Event loop:** `serve(buf, st)` — still one tail-recursive loop; all
   state loop-carried in `srvst` (checker config, docs store, pending
   deadlines, the ONE in-flight check).  Between frames it reaps the
   in-flight check (publish + drop), starts the next due check, then
   `lsp_poll_stdin` (block forever when idle; 25 ms tick while work is
   in flight).
3. **Config:** `initialize.params.initializationOptions.{checker,xatshome}`
   (absolute paths).  No env/argv externs — config flows through the
   protocol.
4. **Checks run on the ON-DISK file**, triggered by didOpen/didSave;
   didChange only updates the in-memory store (see the architect
   decision below).  didClose clears diagnostics.  Superseded results
   are version-labeled (`publishDiagnostics.params.version` = the doc
   version at spawn), so clients discard them.
5. **Diagnostics shaping** (`lsp_diag`): scans `PREAD00-ERROR:` /
   `F3PERR0-ERROR:` lines; per line takes the INNERMOST
   (smallest-width) span in the target file — that is the precise
   errck node; dedups repeated spans keep-first (kills the
   PREAD00/F3PERR0 and L2/L3 redundancy); classifies by node text
   (`D3Et2pck` → "type mismatch", `D2Enone1(D1Eid0(x))` → "unbound
   identifier: x", `D0*errck`/PREAD00 → "syntax error", `D3Etim[pq]` →
   "unresolved template").
6. **KEY DISCOVERY — no UTF-16 conversion needed:** the selfhost
   compiler's string model is UTF-16 (JS heritage), so its printed
   columns are 1-based **UTF-16 code-unit** columns (probed: é advances
   offs by 1, 😀 by 2) — exactly LSP's default `positionEncoding`.
   Mapping is `(line-1, offs-1)`.  The planned `lsp_u16` module is
   unnecessary; the multibyte golden (t07's é fixture) guards this
   assumption if the compiler's string model ever changes.

## M2.5 (DONE): the architect's decisions, as built (2026-08-29)

1. **Live-buffer checking — `--stdin` driver mode** (architect's pick).
   `xats2go-tcheck <file> --stdin` reads the text from stdin and parses
   it ATTRIBUTED to the real path: a driver-local
   `my_d0parsed_from_text` replicates `trans00_from_fpath` with the
   lexbuf from the text and `LCSRCsome1(path)` on the tokens AND the
   d0parsed source — diagnostics carry the file identity and relative
   staloads resolve exactly as on-disk (verified: byte-identical error
   lines vs the on-disk mode, and a go-server module's `./../SATS/`
   staloads resolve).  stdin arrives via ONE new runtime leaf
   (`Xats_XATS2GO_tcheck_stdin_readall`, in the leaf-census baseline).
   Server side: every check of a stored document pipes the CURRENT
   buffer (`lsp_spawn_check` gained arg2+input); didChange debounces
   250 ms.  Also fixed while in there: stadyn now follows the extension
   (`.sats` was previously checked as dyn).
2. **Kill superseded checks**: a due check for the uri already being
   checked kills the in-flight one (newest wins); a different uri still
   waits its turn.
3. **Exit codes**: `exit` terminates via an `lsp_exit` floor leaf —
   0 after `shutdown`, 1 without (t09 golden asserts rc=1).
4. **Cross-file diagnostics**: the driver walks the target's
   D3Cstaload/D2Cstaload decls (descending through includes) and for
   every freshly-loaded (shr=0) NON-STDLIB dependency reports its
   errors — running `tread12` on the dep's cached d2parsed first,
   because the staload pipeline skips the proofread and the errck
   wrappers otherwise never exist (`F2PERR0-ERROR` lines; f3perr0 on
   the dep's d3parsed adds L3 expression errors).  Stdlib
   (`$XATSHOME/prelude/`, `/xatslib/`) is excluded at the driver;
   WORKSPACE policy lives in the server: only files under the
   `initialize` rootUri/workspaceFolders root are summarized, one
   diagnostic per foreign file, positioned on the staload's quoted
   basename (t10 golden).

### Traps found (compiler-tree, cost real time)
- A top-level `#typedef` BETWEEN fun groups — and the tuple type
  written INLINE in a fun-param annotation — both survive the native
  binary but the srcgen2 checker errcks the whole consumer chain and
  the emitter ERASES it to an UNHANDLED no-op; and `pfx` is a KEYWORD
  (bit AGAIN — first hit in lsp_uri).  The `{itm:tbox}` topmap
  generics (topmap_strmize) errck the same way from a driver — walk
  the AST instead.
- Judge a preflight by EXIT CODE, not by grepping error lines: the
  jsemit00 reference dies with a different uncaught-throw message than
  the bundle (`cfail` absent), so a grep-only check "passed" a
  crashing file — my bisect chased a comment for two rounds.

## M3 (DONE): hover + go-to-definition, index-dump mode

Every check runs `xats2go-tcheck <file> [--stdin] --index`: the driver
emits, between `//==XLSPIDX-BEGIN==/END==` sentinels on stdout (a
channel the checker otherwise never writes),

    H \t l0 \t c0 \t l1 \t c1 \t <type>
    D \t l0 \t c0 \t l1 \t c1 \t <defpath> \t dl0 \t dc0 \t dl1 \t dc1

0-based positions, UTF-16-unit columns (this compiler's native model —
LSP's default encoding, no conversion anywhere).  Implementation:
`UTIL/xats2go_lspidx.{sats,dats}` (built alongside the driver by
wire-tcheck.sh):
- **the s2typ surface printer** (hover mode, per
  S2TYP-SURFACE-SYNTAX.md): friendly prelude names, per-width int/flt
  from the `T2Ptext` tag, `T2Pfun1` with npf proof-bar and arrow
  flavor, tuple/record sigils by `trcdknd`, quantifiers, solved-xtv
  expansion, depth-capped; prints straight to the FILR (no string
  building — the runtime lacks a compiler-side strn_make_fwork leaf).
- **the d3 walk** (all ~106 D3E/D3P/D3C constructors + the
  gua/cls/gpt/farg/val-var-fun-dcl families): every typed node in the
  target file emits H (T2Pnone0-typed nodes skipped); D3Evar/D3Ecst/
  D3Econ (+ D3Pcon in patterns) also emit D via `entity.lctn()`.
  Resolved template bodies (D3Etimp/timq payloads) are NOT descended.

Server: `lsp_index` parses the records (floor gained
`lsp_check_stdout`; spawn gained a third arg slot); the cache lives in
the loop state per uri; hover/definition answer by INNERMOST
containing span — **~0.1 ms per request** from cache.  Hover returns
markdown (```ats fenced); definition returns a single Location
(cross-file into the prelude works).  Index cost on the checker: none
measurable (1.20 s on a compiler-sized module, same as before).

### More traps for the notebook
- xbasics' `trcdknd` constructors are BARE (no `of ()`) — and
  `TRCDflt1`/`TRCDbox3` are COMMENTED OUT: a pattern naming one errcks
  the whole consumer chain exactly like the ghost-typedef trap.
- Deep JVobj nesting miscounted a paren AGAIN (the cz-era lesson
  holds on this backend too: build big literals with flat vals).

## Remaining minor policies (documented, not blocking)
Framing desync still logs + terminates; a headerless garbage stream
grows the buffer until EOF; buffer append is O(buf) per chunk.

Deferred (per the brief): completion, workspace indexing, incremental
sync.

## M4 (code done): the VSCode client

`../client/` now launches the native binary directly (Chez/Deno-era
backends removed: resolution, settings, build scripts, the stale
`server-dist` payload).  Resolution: `ats3.server.path` setting →
packaged `server-dist/ats3-lsp-server` → dev `go-server/BUILD/`;
checker: `ats3.server.checkerPath` → `server-dist/` →
`$XATSHOME/srcgen2/xats2go/selfhost-build/src/xats2go-tcheck`; XATSHOME:
setting → env → repo root (dev).  The whole server config rides in
`initializationOptions` (`{checker, xatshome}`).  A missing checker is
a WARNING (server runs, diagnostics disabled).  `npm run package`
stages both binaries into the `.vsix`.  tsc + esbuild clean; the human
F5 end-to-end demo is the remaining M4 step (architect).
