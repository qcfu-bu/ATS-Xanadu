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
| M5a — completion: lexical core + scope-aware locals | **DONE** (2026-08-29) |
| M5b — completion: member/dot | **DONE** (2026-08-29) |
| M4 — wire the VSCode client | **code done** (2026-08-28); the human F5 demo remains |
| M6 — in-process compiler (architect ruling 2026-08-29) | **DONE** (2026-08-29) |

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

**Completion (M5a+M5b):** the --index pass also emits candidate
records — P (pervasives: topmap_strmize over the loaded
the_dexpenv/the_sexpenv, ~3300 names with kinds), S (target-file +
transitive non-stdlib dep top-level decls, incl. datatype
constructors), L (locals with visibility spans: fun/lam/fix/implfun
args, let/where val binders, case-clause pattern vars), and M
(record/tuple field labels keyed by the receiver expression's span).
The server extracts the partial word (UTF-16 → byte offset → scan
back over identifier bytes) and assembles ranked tiers — locals >
file decls > dep decls > pervasives > keywords > buffer words —
case-insensitive prefix, name-dedup, 200-cap + isIncomplete, in
0.2–1.2 ms.  After a `.` it answers ONLY the receiver's fields (M
records whose span ends at the dot); triggerCharacters: ["."].

**Semantic tokens (M3.5):** the --index walk also emits
`T \t l0 \t c0 \t l1 \t c1 \t kind` for every identifier
(0 variable / 1 function / 2 enumMember; fun-vs-var by peeling the
entity's styp to T2Pfun1).  The server merge-sorts (O(n log n) — the
index-perf lesson), drops same-start duplicates, delta-encodes, and
declares the legend in semanticTokensProvider.  Tokens refresh per
check; VSCode blends the TextMate grammar between refreshes.
COMPLETION IS BUILT (M5a+M5b below).  Historical note on the earlier
false blocker: the
prelude-name enumeration (topmap_strmize over the_dexpenv) works from
a driver — the earlier "errck-erases" claim was two conflated
artifacts: (a) a missing-staload errck poisoning the enclosing decl
(generic errck-erasure: emitted as UNHANDLED nil, build succeeds
silently), and (b) RELATIVE-path emitter invocations degrading
d2cst_package_sourceq's path-substring test to the runtime-bridge
route.  With absolute input paths (what wire-tcheck/assemble use) the
call emits the stamped Z_topmap_strmize and links.  TRAP FOR THE
NOTEBOOK: the package classifier is path-TEXT-dependent — always
invoke the emitter with ABSOLUTE source paths for compiler/server
modules.

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

## M6 (in progress): in-process compiler — the architect's ruling (2026-08-29)

**Why.** The go-vs-chez benchmark (see the session bench + memory) showed the
~290 ms per-check floor is ENTIRELY prelude load: an empty file costs the same
286 ms as a real one; the actual small-file check is ~10 ms.  The resurrected
Chez resident (prelude in-process, warm re-checks) did tiny-file re-checks in
~8 ms but real modules 5x SLOWER and 15x the RSS.  The architect ruled: adopt
the Chez architecture on the Go backend — link libxatsopt into the server,
load the prelude once, check in-process.  Best of both: warm ~10 ms tiny
checks AND the 5x-faster Go frontend on real files.

**The one-shot problem and its answer.** The compiler has no state reset
(ats3-compiler-one-shot).  Upstream now has Tier-1 `xglobal_reset()`
(HX-C1-2026, xglobal.sats — full reset + prelude RELOAD; correct but pays the
286 ms again).  Tier-2 checkpoint/restore was never built.  We do neither
per check: **targeted eviction, June-Chez style, keyed by staload
freshness** — a check's freshly-loaded dependencies are exactly the staload
nodes with `shr = 0` (prelude/pre-cached hits are shr = 1), the same walk
report_deps already does.  After emitting reports + index, evict from the
four per-file caches (the_d1parenv/the_d2parenv/the_d3parenv pvstmap
topmaps + the_d3tmpenv) the TARGET file's fnm2 stamp and every shr=0 dep
stamp (transitively).  That reproduces process-per-check semantics exactly
(each check re-elaborates its own workspace closure; the prelude stays warm
and immutable), with zero snapshot bookkeeping.  `xglobal_reset()` +
pvsreload is the nuclear fallback (prelude edits; suspected inconsistency).
NB the f2perr0 dep-report path MUTATES cached dep d2parsed ("fine: the
process is one-shot") — eviction discards the mutation, preserving that
assumption.  Stamp counters / symbol intern tables grow monotonically
across checks (append-only; benign per the C1 proposal inventory).

**Plumbing design.**
- Check core extracted from the tcheck driver into
  `UTIL/xats2go_tchecklib.{sats,dats}`: `tchk_prelude_load()` (the same
  eager `the_fxtyenv_pvsl00d` + `the_tr12env_pvsl01d` + flag$pvsadd0
  triple the CLI driver runs), and
  `tchk_check(path, text, stadyn, idxq, errout: FILR, idxout: FILR)`
  (mymain_work parameterized by text + output FILRs, ending with the
  eviction walk).  `xats2go_tcheck01.dats` becomes a thin CLI over the
  lib — its stderr/stdout stay byte-identical.
- In-process output capture: every reporter already takes `out: FILR`,
  and the GO runtime's `xatsWriter` accepts ANY value with a Go
  `Write` method — so a `*bytes.Buffer` IS a FILR.  New runtime leaves:
  `buffilr_make/take` (buffer-backed FILR + drain), plus a capture
  window that routes the prerr/report-channel default-stderr writes
  (xatsStorePut + the direct os.Stderr chokepoints) into the same
  buffer for the check's duration.
- Eviction leaf: the topmap rep is xatsJSHMap (Go map) behind the
  XATS2JS_jshmap_* leaves; a driver-local extern
  (`XATS2GO_lsp_evict(map, keysint)`, the June JS_map_reset pattern)
  deletes one key — no upstream SATS churn.
- Server: floor gains setenv (XATSHOME must be set before prelude
  load; it arrives in initializationOptions) and a panic-guard leaf
  (`lsp_guard(f)`: defer/recover — a frontend crash fails ONE check,
  Chez-glue style).  h_initialize: setenv + tchk_prelude_load (~290 ms,
  once — the Chez resident's 334 ms boot equivalent).  chk_start runs
  the check SYNCHRONOUSLY v1 (debounce already coalesces bursts;
  kill-superseded degrades to drop-queued; goroutine offload is a
  documented follow-up).  The spawn/reap floor leaves and the separate
  tcheck binary path go away from the server (the CLI tcheck stays for
  tests/debug).
- Build: `selfhost-build/wire-server.sh` mirrors wire-tcheck.sh — the
  server modules + floor + tchecklib emissions link against the SAME
  assembled compiler packages by source-location stamps; server binary
  becomes ~190 MB; the vsix ships ONE binary.

**Correctness tests to add** (beyond the 14 golden): t15 idempotence
(same file didChange'd twice with the same text → byte-identical
diagnostics both times — catches stale target caching); t16 isolation
(file A defines a name; file B referencing it WITHOUT staload must
error — catches cross-check pollution); t17 dep re-read (edit dep on
disk between checks of the dependent → new dep errors appear — catches
dep-cache staleness).

**Expected numbers** (from the bench): warm didChange→diags tiny file
~593 → ~260 ms (debounce-bound); didOpen tiny ~308 → ~15 ms; mid file
~1167 → ~880 ms; RSS ~190 MB resident (vs 31+137 transient today, vs
459 MB for the Chez resident).

### M6 as built (deltas from the design above)

**The two-prelude fence (the big deviation).** The server modules could
NOT simply staload the compiler SATS: the server lives in the repo-root
GO prelude world, the compiler in the srcgen1 prelude world, and one
emission unit holding both detonates template resolution (138 errck,
`gint_sub` resolving into srcgen1's gint000.sats).  The bridge is at
the GO SYMBOL level instead: `UTIL/xats2go_lspglue.{sats,dats}`
(compiler world) exports `tchkglue_prelude_load` / `tchkglue_check`
as stamped Z_ symbols; wire-server.sh extracts the stamps from the
emission and GENERATES a shim (`zz_srv_shim.go`) that the server's
plain `XATS2GO_LSP_tchk_*` externs forward to.  Results cross the
fence as strings through a runtime stash
(`Xats_XATS2GO_lsp_stash/take_rep/idx`); the glue runs the check
inside the runtime capture window, so the captured report text is
byte-identical to the old checker's stderr and the whole downstream
(diag_build/idx_parse) is untouched.

**Wiring.** `selfhost-build/wire-server.sh` (called by tools/build.sh
after emission + floor prep): processes the 8 server module emissions
assemble.sh-style into `src/lspserver/` (dot-imports of the compiler
packages; temps `gosrv<N>`; module inits `Zzmodinit_srv_<N>`), layout
structs deduped MINUS those zzbase already exports, tchecklib/lspidx
processed modules shared verbatim with src/tcheck/, glue module +
generated shim, the server extern floor — but NOT the prelude CATS
floor (zzbase already exports the bare XATS2GO_* leaves; a second
copy collides through the dot-import).  Binary: 190 MB, back at
go-server/BUILD/ats3-lsp-server (client path unchanged).

**Runtime leaves added** (census-baselined): capture_begin/end
(stderr-capture window; also resets the report-bracket depth so a
recovered panic can't misroute later prints), buffilr_make/take,
lsp_evict (jshmap key delete), lsp_stash_rep/idx + lsp_take_rep/idx
(take_rep drains a still-open capture window after a panic, so a
crashed check still surfaces its partial report).  Floor delta:
spawn/reap family REMOVED; setenv + guard added; take_rep/take_idx
wrappers.  `lsp_guard` calls a `(sint)->void` closure = `func(int)
any` (the settled convention per CATS/GO/strn000.cats).

**Eviction, as planned:** tchk_check ends by evicting the target +
every fresh (shr = 0) non-stdlib dep from the four per-file caches
(d1/d2/d3parenv + d3tmpenv), transitively — stdlib deps stay warm
under the same immutability assumption as the prelude.  The f2perr0
dep-report mutation is discarded by the same eviction.

**Verified.** Suite 16/16: the 14 goldens re-baselined for two benign
deltas (tokrefresh id now 1000000+version; synchronous checks publish
before refreshing — deterministic ordering), plus the two M6 gates:
t15-recheck-fresh (the BROKEN dep's summary reappears on the second
check of the same uri with the target's error text updated — eviction
works, nothing stale), t16-isolation (a top-level name defined by one
checked file is UNBOUND in the next check — no cross-check pollution).
quick 75/75 + leaf ratchet green; gate rerun with the M6 runtime.

**Measured** (same bench as the go-vs-chez comparison; 250 ms debounce
included): warm didChange→diags tiny file 593 → **267 ms**
(debounce-bound; Chez-resident parity), mid file 1167 → **427 ms**
(11x the resurrected Chez resident's 4750 ms); didOpen tiny 308 →
274 ms cold-including-prelude-load, mid 875 → **615 ms**; RSS
**166 MB** resident, no transient children (vs 31+137 before, 459 MB
Chez).  initialize RTT 2.9 ms (the ~250 ms prelude load happens after
the response).

**Deferred (documented):** kill-superseded degraded to drop-queued
(checks are synchronous; the debounce coalesces bursts — revisit with
a goroutine offload + serialize-with-mutex if mid-file checks ever
block interactivity noticeably); periodic `xglobal_reset()` hygiene +
prelude-edit reload (the June resident's reload_and_revalidate
equivalent); the vsix restage (client no longer stages xats2go-tcheck;
`npm run package` when the architect wants a new vsix).

## M6.1 (DONE 2026-08-29): the deferred items — async checks + prelude reload

**Async check offload.** The check runs on the floor's SINGLE-FLIGHT
goroutine (`lsp_check_start/done/rep/idx/ok/drop`); the loop keeps the
proven CKrun/chk_step reap shape from M2.  Happens-before is free:
the `go` statement orders the goroutine after the loop's prelude load,
and the done-channel close orders the check's writes before the reap;
one goroutine at a time keeps the compiler globals single-threaded.
The goroutine drains the runtime stash itself — the loop never touches
it.  `lsp_check_drop` BLOCKS until the goroutine finishes (a live
compiler goroutine is never abandoned), doubling as the reload drain.
While busy, a due pending entry stays queued and fires on reap —
newest text wins because the queued re-check reads the current buffer.
`lsp_poll_stdin` gained wake code 3 (the in-flight check's done
channel joins the select), so reaping is immediate instead of eating a
poll tick; the CKrun tick is a 1 s fallback.  MEASURED: during a
mid-file check window, 43 hover requests answered at 0.88 ms mean /
11.4 ms max (previously they queued behind the check); warm
change→diags unchanged (~270/~430 ms).

**Prelude reload.** A didSave whose path is under $XATSHOME's
`/prelude/`, `/srcgen1/prelude/`, or `/srcgen2/prelude/` drains the
in-flight check, runs `tchkglue_prelude_reload` (= `xglobal_reset()` —
first GO-arm exercise of the HX-C1-2026 Tier-1 API — then
tchk_prelude_load; duplicate flag re-adds are harmless presence
tests) under the guard, and queues a re-check of every open document.
This also caps the long-session memory creep: a prelude save returns
the compiler to its post-startup baseline.  On reload failure the
server logs "state may be stale; restart recommended" and keeps
serving.  VERIFIED by t17-prelude-reload: same diagnostics
byte-for-byte after the reset+reload+revalidate cycle.  Suite 17/17.

**The pfx trap, THIRD occurrence:** `str_prefixq`'s parameter was
named `pfx` — the proof-fixpoint KEYWORD — and hard-crashed the
parser (cfail, no location).  Bisected via selfhost preflight (judge
by RC).  Never name anything `pfx`.

**Still open (documented, low priority):** framing desync logs +
terminates; a headerless garbage stream grows the buffer until EOF;
O(buf) chunk appends (~8 MB copied for a 1 MB didOpen — negligible).
