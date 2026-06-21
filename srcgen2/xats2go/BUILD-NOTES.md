# xats2go — BUILD NOTES (durable runbook)

Status after **M1**: walking skeleton ("Hello World") GREEN + reproducible. The
real emitter `go1emit` now TRAVERSES the intrep1 IR for a top-level
`val () = strn_print("...")` + `the_print_store_log()` program and emits real
Go that, built with `go build`/`go vet` and run, prints output **byte-equal to
the JS backend** (the differential oracle). See the **M1** section at the bottom.

Status after **M0**: green pipeline tracer bullet. The frontend → trxd3i0 →
tryd3i0 → trxi0i1 → `go1emit` spine runs end-to-end and emits a fixed minimal
`package main` / `func main`. The M0 `go1emit` is a STUB — it ignores the IR
(but it *does* consume the real `i1parsed`), so this proves build/link/pipeline
wiring, not codegen. The M0 runbook below is preserved verbatim.

---

## How to run

```bash
bash srcgen2/xats2go/build-go-m0.sh
```

Exit 0 + the `xats2go M0 GREEN` banner ⇒ pipeline ran and
`srcgen2/xats2go/srcgen2/BUILD/GO/test00.go` was written.

No `go` toolchain required for M0 (the *emitter* runs on Node; it only writes
text). `go` is **not installed** here — see "Gotchas / M1 prerequisites".

---

## Toolchain paths (all verified present)

| Role | Path |
|---|---|
| ATS3→JS transpiler (jsemit00) | `xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js` |
| Frontend lib (171MB, **reuse, never rebuild**) | `srcgen2/lib/lib2xatsopt.js` |
| intrep0 + trxd3i0 + tryd3i0 lib (**reuse**) | `frontend/BUILD/lib2xats2cc.js` |
| Node invocation | `node --stack-size=8801` |

Runtime files prepended to the **emitter** bundle (the emitter is itself JS),
verbatim from `frontend/build-m0b.sh`'s `RUNTIME=(...)`:

```
srcgen2/xats2js/srcgenx/xshared/runtime/xats2js_js1emit.js
srcgen2/xats2js/srcgenx/xshared/runtime/srcgen2_precats.js
srcgen1/xats2js/srcgenx/xshared/runtime/srcgen1_prelude.js
srcgen1/xats2js/srcgenx/xshared/runtime/srcgen1_prelude_node.js
srcgen1/xats2js/srcgenx/xshared/runtime/srcgen1_xatslib_node.js
```

---

## lib2xats2go.js — source order (built by `build_backend_lib`)

From `srcgen2/xats2go/srcgen2/DATS/`, in this dependency order (mirrors the
xats2js Makefile SRCDATS: intrep1 group, trxi0i1 group, env, emitter, tmplib):

```
intrep1.dats            (copied verbatim from xats2js)
intrep1_print0.dats     (copied)
intrep1_utils0.dats     (copied)
trxi0i1.dats            (copied)
trxi0i1_myenv0.dats     (copied)
trxi0i1_dynexp.dats     (copied)
trxi0i1_decl00.dats     (copied)
xats2go_myenv0.dats     (NEW — minimal envx2go)
go1emit.dats            (NEW — M0 stub emitter)
xats2go_tmplib.dats     (copied from xats2js_tmplib.dats, backend-agnostic)
```

`xats2go_tmplib.dats` is included via `HATS/mytmplib00.hats` (which several of
the copied files `#include`), so it MUST be in the lib. It only defines
`g_print`/`g_cmp` template instances for intrep0/intrep1 nodes — no backend
specifics.

**Driver** (transpiled separately, not part of the lib):
`srcgen2/xats2go/srcgen2/UTIL/xats2go_goemit01.dats`.

---

## Namespace-sed scheme (critical, copied from build-m0b.sh)

`build_backend_lib` transpiles each `.dats` via jsemit00, then per-file does
`sed s/jsxtnm/jsx<NNN>tnm/g` with **NNN starting at 100 (3-digit, REQUIRED)**.
3 digits is mandatory because the link-time regex below matches exactly 3 chars
(`jsx(...)tnm`); 1-/2-digit tokens would NOT be remapped and would collide.

**Link order** (concatenated into one bundle), each lib re-namespaced into its
own `js{1,2,3}` slot via `sed -E 's/jsx(...)tnm/js{N}\1tnm/g'`:

```
RUNTIME (5 js files, above)
  + js1 · lib2xatsopt.js        (frontend, reused)
  + js2 · lib2xats2cc.js        (intrep0/trxd3i0/tryd3i0, reused)
  + js3 · lib2xats2go.js        (intrep1/trxi0i1/env/go1emit, built here)
  + driver transpile            (xats2go_goemit01_dats.js)
```

Run the bundle on `node --stack-size=8801`. The driver's `mymain_main`
auto-runs at load.

---

## argv / entry-point contract

`process.argv = [node, bundle.js, SOURCE]`. The driver (mirroring
`xats2js_jsemit01.dats`) reads `argv[2]` as the source path and requires
`length(argv) >= 3`. So invoke with EXACTLY ONE arg (the `.dats`):

```bash
node --stack-size=8801 BUNDLE.js  path/to/test00_xats2go.dats
```

The driver sets `--_XATS2JS_` and `--_SRCGEN2_XATS2JS_` flags (kept identical to
the JS driver because trxd3i0/trxi0i1 are backend-agnostic and these flags drive
frontend behavior, not JS-specific emission).

Emitted Go is bracketed by `//==XATS2GO-BEGIN==` / `//==XATS2GO-END==`
sentinels on stdout; progress/trace goes to stderr. The build script `awk`-
extracts between sentinels into `BUILD/GO/test00.go`.

---

## What was copied verbatim vs. written new

- **Copied verbatim** (backend-agnostic; relative `./../../../` staload paths
  resolve identically because `xats2go/srcgen2` is at the same depth as
  `xats2js/srcgen2`): `SATS/intrep1.sats`, `SATS/trxi0i1.sats`,
  `DATS/{intrep1,intrep1_print0,intrep1_utils0,trxi0i1,trxi0i1_myenv0,trxi0i1_dynexp,trxi0i1_decl00}.dats`,
  `HATS/libxatsopt.hats`, and `DATS/xats2go_tmplib.dats` (= `xats2js_tmplib.dats`).
  The only `xats2js` strings remaining in copied files are end-of-file comment
  banners (harmless).
- **Written new**: `SATS/xats2go.sats` + `DATS/xats2go_myenv0.dats` (minimal
  `envx2go` vtype + getters/make/free/indent + `strnfpr`/`nindfpr`),
  `SATS/go1emit.sats` + `DATS/go1emit.dats` (`i1parsed_go1emit` stub),
  `UTIL/xats2go_goemit01.dats` (CLI driver), `HATS/mytmplib00.hats`,
  `TEST/test00_xats2go.dats`.

---

## Gotchas hit / lessons

1. **3-digit namespace counter is non-negotiable** — same trap documented in
   build-m0b.sh; reused exactly.
2. **mytmplib00.hats pulls in a tmplib** — several copied files
   `#include "./../HATS/mytmplib00.hats"`, and that hats `#staload`s a
   `*_tmplib.dats`. You can't just drop it; copy the (backend-agnostic) tmplib
   and point mytmplib00.hats at it.
3. **argv[2], not argv[1]** — `process.argv[0]=node, [1]=bundle, [2]=source`.
   Pass the source as the single CLI arg; passing an extra leading token makes
   the driver try to open the wrong path.
4. **Transpile `.err` files are non-empty but benign** — jsemit00 streams the
   prelude-loading trace (`d0parsed_from_fpath: ...`) to stderr. The build
   guards on output line-count + errck markers, not on `.err` emptiness.

---

## M1 prerequisites / what will bite

- **Install Go** (`brew install go`). M0 emits `.go` but cannot `go build`/
  `go vet`/run it; the differential harness (vs the JS backend) needs a working
  `go`. The build script already auto-`go build`s when `go` is on PATH.
- **The driver runs the FULL pipeline** (not a shortcut): the build log shows
  the frontend loading the prelude, `t3read0` template-resolution, the
  `F3PERR0_D3PARSED` error-check pass, then `go1emit` reporting
  `stadyn=1 nerror=0` (proving it consumed the real `i1parsed`). M1 only needs
  to replace the fixed-text body of `i1parsed_go1emit` with real IR traversal —
  the spine is already correct.
- **go1emit is the ONLY stubbed stage.** `envx2go` already mirrors `envx2js`
  (incl. lvl0/nind indent machinery) so M1 can start emitting indented Go
  immediately. The xats2js `js1emit.{sats,dats}` + `xats2js.{sats,dats}` files
  are the templates to mirror for the real emitter functions.
```

---

# M1 — Walking skeleton ("Hello World"), REAL emission + runtime + oracle

## How to run

```bash
bash srcgen2/xats2go/build-go-m1.sh
```

Exit 0 + the `xats2go M1 GREEN` banner ⇒ the pipeline ran, `go1emit` emitted
real Go BY TRAVERSING the IR, `go build`+`go vet` passed, the program ran
(exit 0), and its stdout was **byte-equal to the JS backend's** (differential
oracle). Requires `go` on PATH (Go 1.26.x verified).

## What M1 added (all additive under `srcgen2/xats2go/`)

- **Test program** `srcgen2/TEST/test01_xats2go.dats` — the SIMPLEST real
  prelude print path: `val () = strn_print("Hello from [test01_xats2go]!\n")`
  then `val () = the_print_store_log()`. Includes `prelude/HATS/prelude_dats.hats`
  + `prelude_JS_dats.hats` (same surface as the xats2js test00).
- **Real `go1emit`**, split to mirror the js1emit files:
  - `DATS/go1emit.dats` — `i1parsed_go1emit` (Go preamble + sentinels + IR-DUMP
    to stderr) + list/optn iterators (`i1dclistopt/i1dclist/i1valdclist`).
  - `DATS/go1emit_decl00.dats` — `i1dcl_go1emit` (dispatch; only `I1Dvaldclst`
    is executable, others → Go comment) + `i1valdcl_go1emit` (unit-pattern val).
  - `DATS/go1emit_dynexp.dats` — `i1cmp_go1emit`/`i1letlst_go1emit`/
    `i1let_go1emit` (`I1LETnew0`/`I1LETnew1`) + `i1insgo1` (`I1INStimp`,
    `I1INSdapp`) + `i1valgo1` (`I1Vtnm/I1Vstr/I1Vs00/I1Vnil/I1Vcst/I1Vfid`).
    Any unhandled ctor emits `/* UNHANDLED: ... */ nil` AND a stderr `prerrln`.
  - `DATS/go1emit_utils0.dats` — naming/leaf emission: `i1tnmgo1`
    (`goxtnm<stamp>`), `d2cstgo1` (`xatsgo.Xats_<sym>`), `d2vargo1`,
    `i0strgo1`/`i0s00go1` (Go-escaped string literals), `xsymgo1` (Go-ident
    sanitizer).
  - `SATS/go1emit.sats` — interface for the above (replaces the M0 stub sig).
- **`xatsgo` Go runtime** `runtime/xatsgo/` (`go.mod` + `xatsgo.go`): the print
  store (`Xats_strn_print` → push, `Xats_the_print_store_log` →
  `console_log(flush())`), `XATSSTRN`/`XATSSTR0`/`XATSNIL`. Reproduces the JS
  runtime's OBSERVABLE bytes exactly (flush + a trailing `\n` from console.log).
- **`build-go-m1.sh`** — adapts M0: builds `lib2xats2go.js` from the new source
  set, links the bundle (+ the JS shim, below), runs the emitter on test01,
  extracts `BUILD/GO/test01.go`, assembles a scratch Go module
  (`BUILD/GOMOD/{go.mod,test01.go}` with `replace xatsgo => runtime/xatsgo`),
  `go vet`+`go build`+run, builds the JS backend reference (`lib2xats2js.js` +
  `xats2js_jsemit01` driver), runs it, and asserts byte-equality. Refreshes the
  golden `TEST/OUTS/test01.expected` from the verified run (used as a fallback
  oracle if the JS side is unavailable).

## lib2xats2go.js — M1 source order (build_backend_lib)

```
intrep1.dats  intrep1_print0.dats  intrep1_utils0.dats   (copied)
trxi0i1.dats  trxi0i1_myenv0.dats  trxi0i1_dynexp.dats  trxi0i1_decl00.dats (copied)
xats2go_myenv0.dats           (env; nindfpr now emits a TAB per level → gofmt-clean)
go1emit_utils0.dats  go1emit_dynexp.dats  go1emit_decl00.dats  go1emit.dats  (NEW)
xats2go_tmplib.dats           (copied, backend-agnostic; MUST be last)
```
The emitter files go AFTER `xats2go_myenv0.dats` and BEFORE `xats2go_tmplib.dats`,
mirroring the xats2js Makefile (`js1emit*` after env, tmplib last).

## CRITICAL gotcha — the missing `i0varfst_*` funset helpers (JS shim)

The prebuilt `frontend/BUILD/lib2xats2cc.js` **references but never defines** 6
functions: `i0varfst_mknil/mklst/addvar/addlst/listize/strmize`. `trxd3i0`
calls these to compute the free-variable set of ANY function declaration; their
impls (in `intrep0_utils0.dats`, backed by the avltree funset/funmap library)
failed template resolution when `lib2xats2cc.js` was built and landed inside a
commented-out `// I1Dnone1(...)` errck blob — while the call sites survived. So
**any program containing a function** (incl. the whole prelude, hence test01)
crashes with `ReferenceError: i0varfst_mklst_NNNNN is not defined`. test00
(`val theAnswer=42`, no functions) never hit this; that's why M0 looked fine.

This is a **pre-existing frontend-bundling defect, independent of the Go
emitter.** Rebuilding `lib2xatsopt.js` is forbidden and rebuilding
`lib2xats2cc.js` is out of M1 scope, so M1 supplies the 6 impls as a small,
semantically-faithful JS shim generated by
`runtime/jsshim/gen-i0varfst-shim.sh` and PREPENDED to the emitter bundle.
The shim represents `i0varfst` as a JS array sorted+deduped by var stamp
(`stamp_get_uint(d2var_get_stmp(i0var_dvar$get(v)))`); `listize` → a JS
`list_vt` (`nil=[0]`, `cons=[1,h,t]`); `strmize` → a real lazy `strm_vt` built
from the existing `XATS2JS_lazy_vt_make_f0un` + `XATS2JS_strmcon_vt_{cons,nil}`
so the inlined `strm_vt_listize0` in `trxd3i0_decl00` can walk it. Stamps differ
per `lib2xats2cc` build, so the generator DISCOVERS the exact stamped names from
the bundle at generation time (robust to rebuilds). The same shim is reused for
the JS reference build. **M2 should fix this properly at the source** (rebuild
`lib2xats2cc.js` once the funset library transpiles, or staload a JS impl).

## Build guard added

`build-go-m1.sh`'s `build_backend_lib` now greps each OUR-file transpile `.err`
for `F3PERR0-ERROR`/`PREAD00-ERROR` tagged with that file and FAILS fast. (M0's
guard only checked line count, so a parse error in our own `.dats` silently
dropped the offending decl and surfaced as a late runtime `ReferenceError` —
which is exactly how the first M1 iterations failed.)

## The IR-DUMP technique (the emitter's spec)

`i1parsed_go1emit` prints `i1parsed_fprint(ipar, g_stderr())` between
`[go1emit] IR-DUMP-BEGIN/END` on stderr. For test01 the salient nodes are:
```
I1Dvaldclst(...; I1VALDCL(
  I1BNDcons(I1TNM(7); I0Ptup0(-1;$list()); ...);          // val () pattern (unit)
  TEQI1CMPsome(_; I1CMPcons(
    [ I1LETnew1(I1TNM(5); I1INStimp(I0Ecst(strn_print(1040)); ...))   // resolve fn
    , I1LETnew1(I1TNM(6); I1INSdapp(I1Vtnm(I1TNM(5));                  // call it
                                    [I1Vstr("Hello from [test01_xats2go]!\n")]))]
  ; I1Vtnm(I1TNM(6))))))                                  // result (unit)
```
which maps 1:1 onto the emitted Go:
```go
goxtnm5 := xatsgo.Xats_strn_print                                  // I1INStimp
_ = goxtnm5
goxtnm6 := goxtnm5(xatsgo.XATSSTRN("Hello from [test01_xats2go]!\n")) // I1INSdapp+I1Vstr
_ = goxtnm6
_ = goxtnm6                                                        // I1CMPcons result
```
The `[go1emit] IR-DUMP-*` lines are harmless (stderr only) and are left ON — the
dump is the spec the emitter mirrors. To silence later, delete the IR-DUMP
`val ()` block in `go1emit.dats`.

## Go module / layout

- Runtime package: `runtime/xatsgo/` is its own Go module (`module xatsgo`).
- The emitter writes `import "xatsgo"`; the build's scratch module
  (`BUILD/GOMOD/go.mod`) does `require xatsgo v0.0.0` + `replace xatsgo =>
  ../../../runtime/xatsgo` (absolute path injected by the script), so `go build`
  resolves it with no network. M2 may switch to a single in-tree module.

## Honest coverage (M1)

Handled (real code): `i1dclistopt/i1dclist/i1dcl`, `I1Dvaldclst`,
`i1valdclist/i1valdcl` (unit pattern only), `i1cmp` (`I1CMPcons`), `i1letlst`,
`i1let` (`I1LETnew0`, `I1LETnew1`), `i1ins` (`I1INStimp` via its resolved dcst,
`I1INSdapp`), `i1val` (`I1Vtnm`, `I1Vstr`, `I1Vs00`, `I1Vnil`, `I1Vcst`,
`I1Vfid`). Everything else → `/* UNHANDLED */` + stderr note. **Not yet
handled** (M2): non-unit val patterns; functions/`I1Dfundclst`/closures/TCO;
`if`/`case`/`I1INSlet0`; primops (`I1INSopr`); tuples/records/datacons/
projections (the layout-aware core); exceptions; lazy; templates beyond the
single-extern timp; concrete Go types (M1 is uniform-`any`, Regime A).
**Real-vs-stub:** the IR walk and the string-literal flow are REAL; the timp is
resolved to a named `xatsgo` runtime fn via its real `t1imp_dcst$get` (not
inlined like the JS backend, and not an FFI shortcut — the dcst comes from the
pipeline). M2 should generalize the timp to faithful inlining once functions land.

---

# M2.0 — Reusable harness + liveness pass + `s2typ → Go type` scaffold

Status after **M2.0**: the differential pipeline is now a REUSABLE harness
(`build-go.sh <src.dats>`) that runs ANY source through both backends and
asserts byte-equal stdout; the M1 dead-code noise (`_ = goxtnmN` double
lines) is gone via a real liveness pass; and the scalar `s2typ → Go type`
scaffold compiles. test01 stays GREEN and byte-equal-vs-JS throughout.

## How to run (M2.0)

```bash
# one source through both backends + byte-equal oracle:
bash srcgen2/xats2go/build-go.sh srcgen2/xats2go/srcgen2/TEST/test01_xats2go.dats
# add --force to force a clean lib2xats2go.js rebuild (otherwise mtime-cached)

# the conformance suite (extend its DEFAULT_SUITE as new chunks land):
bash srcgen2/xats2go/srcgen2/TEST/run-suite.sh
```

`build-go-m0.sh` / `build-go-m1.sh` are now thin wrappers that `exec` the
generalized `build-go.sh` on test01 (M0's standalone stub path was retired
at M1; both entry points still exit 0).

## `build-go.sh` interface

- **Arg:** `<source.dats>` (abs or rel) + optional `--force`.
- **DATS source set** for `lib2xats2go.js` lives in ONE place — the
  `GO_DATS=(...)` array near the top. To add an emitter file, drop it into
  the array in dependency order (emitter files go after `xats2go_myenv0`,
  before `xats2go_tmplib`, which MUST stay last). `go1emit_styp0.dats` is
  the M2.0 addition (right after `xats2go_myenv0`).
- **Steps:** (1) build/cache `lib2xats2go.js`; (2) transpile+link the Go
  emitter bundle (runtime + `js1·`lib2xatsopt + `js2·`lib2xats2cc +
  `js3·`lib2xats2go + driver + i0varfst shim); (3) run on the source →
  extract `.go` between the sentinels; (4) assemble a scratch Go module
  (`replace xatsgo => runtime/xatsgo`), run `gofmt -l`/`go vet`/`go build`/
  the program → GO stdout; (5) build the JS reference (`lib2xats2js`) and
  run the emitted JS on node → JS stdout; (6) assert byte-equal (xxd+diff
  on mismatch), refreshing `TEST/OUTS/<name>.expected`.
- **Caching:** `lib2xats2go.js` and the driver transpile are rebuilt only
  when a source `.dats` (or `build-go.sh` itself) is newer, or under
  `--force`. A warm cache turns the per-test cost from ~2 min (lib build)
  into ~25–30 s (link + both backends + go build + node).
- **Per-test isolation:** outputs go under `srcgen2/BUILD/<name>/` so
  multiple tests don't clobber. Shared/cached libs stay in `srcgen2/BUILD/`.
- **Exit:** 0 + PASS banner iff green & byte-equal; nonzero on any failure
  (transpile / our-source parse error / go vet/build / run / mismatch).

## Liveness pass (deliverable 2 — REAL)

New file `DATS/go1emit_styp0.dats` provides
`i1tnm_used_in_cmp(itnm, icmp): bool` — a mutually-recursive walk over
`i1ins`/`i1val`/`i1cmp`/`i1let`/`i1cls` that answers "is the temp [itnm]
referenced (as an `I1Vtnm`) anywhere in [icmp]?". `i1cmp_go1emit` passes
the enclosing `i1cmp` down as the liveness **scope** to
`i1letlst_go1emit`/`i1let_go1emit`; the `I1LETnew1(tnm, ins)` rule is:

- `tnm` referenced later in the scope → `goxtnm<N> := <ins-expr>`
- `tnm` NOT referenced → `_ = <ins-expr>`  (assign-to-blank is legal Go
  for any expression, so this one rule drops BOTH the dead decl and the
  redundant suppressor, and never trips `declared and not used`).

Because intrep1 is ANF/SSA (bindings flow forward only), querying the whole
enclosing cmp is a sound over-approximation. The walk descends into nested
cmps / clauses / lets, so it stays correct when M2.1+ adds if/case/let/lam
(those ins emit as multi-statement BLOCKS and will keep the existing
"pre-declare temp, block assigns to it" pattern — the liveness rule above
governs only ins that emit as a single Go EXPRESSION, which is exactly when
`:=`-vs-`_ =` is the live/dead choice).

BEFORE (M1) vs AFTER (M2.0) for test01's first val:
```go
// BEFORE                              // AFTER
goxtnm5 := xatsgo.Xats_strn_print      goxtnm5 := xatsgo.Xats_strn_print
_ = goxtnm5                            goxtnm6 := goxtnm5(xatsgo.XATSSTRN("...\n"))
goxtnm6 := goxtnm5(xatsgo.XATSSTRN(…)) _ = goxtnm6
_ = goxtnm6
_ = goxtnm6
```
`goxtnm5` stays live (used by `goxtnm6`'s call); the dead `_ = goxtnm5` and
the redundant double `_ = goxtnm6` are gone. `go vet` clean, gofmt-clean,
stdout still byte-equal to JS.

## `s2typ → Go type` scaffold (deliverable 3 — STUB, compiles)

Also in `go1emit_styp0.dats`:
- `gotype_of_styp(s2typ): strn` — recognizes the scalar base cases the
  static type spells out as `T2Pcst(s2cst)` (s2cst *name* = "int"/"bool"/
  "char"/"double"/"float"/"string"/…), chasing through trivial wrappers
  (`T2Ptop0/1`, `T2Plft`, `T2Pnone1`); returns `int`/`bool`/`rune`/
  `float64`/`string`, else `any`.
- `gotype_of_ival(i1val): strn` — recovers a Go type from a LITERAL i1val
  node (`I1Vint`/`I1Vi00`→`int`, `I1Vbtf`/`I1Vb00`→`bool`,
  `I1Vchr`/`I1Vc00`→`rune`, `I1Vflt`/`I1Vf00`→`float64`,
  `I1Vstr`/`I1Vs00`→`string`), else `any`.

These COMPILE and link into `lib2xats2go.js` but are **not yet wired into
emission** — M2.1 calls them when emitting concrete-scalar temps/literals.
This is honestly a stub: it stands the type layer up; it does not yet change
any emitted Go.

## type availability — WHAT static type info survives into intrep1 (CRUCIAL)

This gates how far Regime B (value-typed Go) can go, and was verified
against the IR definitions (`intrep1.sats`, `xats2cc/srcgen1/SATS/intrep0.sats`,
`statyp2.sats`, `dynexp2.sats`) plus the lowering (`trxd3i0_dynexp.dats`,
`trxi0i1_dynexp.dats`).

**The headline: the per-expression static type is FULLY present at intrep0
and DROPPED at intrep1.**

- **intrep0** (`i0exp`) carries an `i0typ` on EVERY expression
  (`i0exp_ityp$get`; built in `trxd3i0` as `s2typ_trxd3i0(d3e0.styp())`).
  `i0typ` is a near-mirror of `s2typ` and crucially includes the
  layout-bearing nodes: `I0Tcst of s2cst` (scalars), `I0Ttcon of (d2con,
  i0typlst)` (datatype constructors — carries the d2con!), and **`I0Ttrcd of
  (trcdknd, npf, l0i0tlst)`** (records/tuples WITH the actual `trcdknd`
  flat/boxed kind + field types). So at intrep0, full type+layout is known.
- **intrep1** (`i1val`) carries ONLY `lctn + node` — NO styp/ityp getter
  exists (`i1val_lctn$get`, `i1val_node$get`, full stop; confirmed in
  `intrep1.sats`). The `i0typ` is **not threaded** into `i1ins`/`i1val`.
  The result of a computed temp (`I1Vtnm`) therefore has **no recoverable
  static type at the i1val level** — it must be inferred from the producing
  `i1ins`, or threaded from upstream.

**Where the emitter CAN still recover a concrete type at intrep1:**

| signal | IR node | what it gives |
|---|---|---|
| literal kind | `I1Vint/btf/chr/flt/str`, `I1Vi00/b00/c00/f00/s00` | the scalar Go type directly (the node kind IS the type) — `gotype_of_ival` |
| flat-vs-boxed split | `I1INStup0(vs)` vs `I1INStup1(token,vs)` | the **constructor choice itself** encodes flat (value struct) vs boxed (pointer). The `token` on tup1/rcd2 is the `trcdknd` kind token (originates from `D3Etup1/D3Ercd2` → `I0Etup1(token,…)`). Flat tuples are a distinct ctor with NO token (no box). |
| record kind | `I1INSrcd2(token, l1i1vlst)` | boxed-record `trcdknd` token + ordered labelled fields |
| datacon | `I1Vcon(d2con)`, `I1INSpcon(label, conroot)` | `d2con` getters: `ctag` (tag), `narg` (value arity), `nprg` (erased proof arity), `styp`/`xtyp` (parent datatype s2typ, carries its own `trcdknd`). Enough to emit a typed tagged struct + typed projection. |
| constant / fn signature | `I1Vcst(d2cst)`, `I1INStimp` (resolved d2cst) | `d2cst_get_styp` → the FULL function `s2typ` (`T2Pfun1(…, arg s2typlst, res s2typ)`). So function ARG and RESULT types ARE recoverable for any named cst/prelude call → concrete Go signatures + the result type of a `dapp` whose callee is a cst. |
| projection field index | `I1INSpflt/proj(label, root)`, `I1Vp0rj/p1rj/p2rj` | the label/index; the field TYPE needs the root's type (recoverable only if the root is itself a typed producer, else `any`). |

**Where the emitter must fall back to `any` (or thread type info downstream):**

- A plain computed temp result (`I1Vtnm`) used as a `dapp` argument when the
  callee is itself a temp (not a cst): the temp's type is unknown locally.
- Tuple/record FIELD types when projecting through a value whose own type is
  an opaque temp.
- Anything polymorphic before monomorphization (`s2var`/`T2Pvar`).

**Architectural implication for M2.1–M2.7 (the key input):**

The honest cheap win at intrep1 is *local*: literals (`gotype_of_ival`),
the tup0/tup1 layout split, and `d2con`/`d2cst` signatures give concrete
types for **producers** without any new plumbing. But to type **computed
temps** (`I1Vtnm` results) — which is what Regime B needs to avoid `any`
everywhere — the clean fix is to **thread `i0typ` from intrep0 into
intrep1**: either (a) add an `ityp` field to `i1tnm`/`i1ins` results in the
copied `trxi0i1` lowering (intrep0 already has it on the producing `i0exp`,
so it's a *carry-through*, not a re-inference), or (b) keep a side-table
`i1tnm stamp → i0typ` populated during `trxi0i1`. Option (b) is the less
invasive (no IR shape change, no re-copy of intrep1.sats) and is the
recommended M2.1/M2.6 approach: the lowering in `trxi0i1_dynexp.dats`
already names every temp (`i1tnm_new0`) right where the typed `i0exp`/`i0typ`
is in scope, so the table can be filled there with zero new analysis.
Until then, M2.1 should rely on `gotype_of_ival` + `d2cst` signatures and
accept `any` for opaque temps; M2.6 (layout-aware tuples/records) is where
the side-table pays off, because that is the first chunk that genuinely
needs the type of an arbitrary temp to pick value-struct vs pointer.

## Honest coverage / real-vs-stub (M2.0)

- **REAL:** the reusable `build-go.sh` harness + caching + per-test isolation;
  `run-suite.sh`; the liveness pass (`i1tnm_used_in_cmp` + the `:=`-vs-`_ =`
  rule) — verified on test01 (clean Go, go vet OK, byte-equal-vs-JS); the
  m0/m1 wrappers; the type-availability investigation above.
- **STUB (compiles, not yet wired):** `gotype_of_styp`/`gotype_of_ival` —
  they link but no emission path calls them yet (M2.1 wires scalars).
- **Unchanged from M1 / deferred to later M2 chunks:** non-unit val
  patterns; functions/closures/TCO; if/case/let; primops; the layout-aware
  data core; exceptions; lazy. The i0varfst JS shim is retained (per PLAN,
  oracle-validated; first real stress at M2.2).
- **Deviation:** `build-go-m0.sh` no longer runs the original M0 stub path
  (that path was retired at M1 when the stub `go1emit.dats` became the real
  split emitter); it now delegates to `build-go.sh` on test01 so the entry
  point stays green. The liveness scope is threaded as an explicit `scp`
  argument (signature change to `i1letlst_go1emit`/`i1let_go1emit` in
  `go1emit.sats`) rather than added as an `envx2go` field, to avoid touching
  the linear env vtype — slightly less "stateful" but simpler and local.

---

# M2.1 — Scalars & primops, concretely typed (native Go operators)

Status after **M2.1**: ATS scalar literals emit as **concrete Go types**
(`int`/`bool`/`rune`/`float64`) and arithmetic/comparison/logic over them
emit as **native Go operators** `(a OP b)` — the Regime-B payoff — gated by
the differential-vs-JS oracle. All additive under `srcgen2/xats2go/`.

## How to run (M2.1)

```bash
bash srcgen2/xats2go/srcgen2/TEST/run-suite.sh     # ALL GREEN (6 tests)
# or one test through the oracle:
bash srcgen2/xats2go/build-go.sh srcgen2/xats2go/srcgen2/TEST/test02_arith_xats2go.dats
```

Suite: test01 (M1 print) + test02_arith, test03_compare, test04_logic,
test05_float, test06_char (M2.1). Each prints a deterministic result and
is **byte-equal to the JS backend**; gofmt-clean; `go vet` OK.

## THE KEY IR FINDING (reusable): how arith/compare lower

They do **NOT** surface as `I1INSopr`. The IR dump (capture via the
emitter's stderr `[go1emit] IR-DUMP-BEGIN/END`, written to
`BUILD/<name>/go-stderr.txt`) shows `1 + 2 * 3` lowering to:

```
I1LETnew1(opT1; I1INStimp(I0Ecst(sint_add$sint(936)); ...))   // resolve +
I1LETnew1(opT2; I1INStimp(I0Ecst(sint_mul$sint(938)); ...))   // resolve *
I1LETnew1(rT1;  I1INSdapp(I1Vtnm(opT2); [I1Vint(T_INT01(2)), I1Vint(T_INT01(3))]))  // 2*3
I1LETnew1(rT2;  I1INSdapp(I1Vtnm(opT1); [I1Vint(T_INT01(1)), I1Vtnm(rT1)]))         // 1+(2*3)
```

i.e. **the operator is a RESOLVED prelude d2cst whose NAME identifies the
op**, bound to a temp by an `I1INStimp`, then applied by an `I1INSdapp`.
Literals are `I1Vint(T_INT01(rep))` (rep = raw decimal text). The d2cst
names discovered (the `$` is a template separator, printed verbatim):

| ATS op | d2cst name | Go operator |
|---|---|---|
| `+ - * / %` (int) | `sint_{add,sub,mul,div,mod}$sint` | `+ - * / %` |
| `< > <= >= = !=` (int) | `sint_{lt,gt,lte,gte,eq,neq}$sint` | `< > <= >= == !=` |
| `+ - * /` (float) | `dflt_{add,sub,mul,div}$dflt` | `+ - * /` |
| `< > <= >= = !=` (float) | `dflt_{lt,gt,lte,gte,eq,neq}$dflt` | `< > <= >= == !=` |
| `< > <= >= = !=` (char) | `char_{lt,gt,lte,gte,eq,neq}` (NO `$` suffix!) | `< > <= >= == !=` |
| `= !=` (bool) | `bool_{eq,neq}` (NO `$` suffix!) | `== !=` |

Per-type PRINTS are plain external prelude fns (M1 timp→named-runtime
pattern): `sint_print`, `bool_print`, `char_print`, `dflt_print`,
`strn_print`. The variadic `prints`/`gs_print_aN` is a TEMPLATE-WITH-BODY
(inlines `g_print<xi>` per arg) — AVOIDED in M2.1 tests by using the
single-type prints (which route cleanly to runtime); faithful template
inlining is M2.2+.

## The operator→Go mapping (native vs runtime-fallback split)

In `go1emit_styp0.dats`:
- `goop_of_name(d2cst-name) : strn` — the mapping table above; returns the
  Go operator string or "" (not native-able).
- `binop_of_callee(callee, scp)` / `is_native_binop_dapp(...)` — walk the
  enclosing cmp's flat let-list to find the callee tnm's binding `I1INStimp`
  and resolve its op; native iff op≠"" AND exactly 2 args.
- `i1binop_of_dapp(callee, args, scp)` — PUBLIC entry the emitter calls.

In `go1emit_dynexp.dats` (`i1insgo1`, now threaded with `scp`):
- `I1INSdapp` native path → `(a OP b)`; else plain call `<f>(<args>)`.

**Native** (emit `(a OP b)`, concrete scalar types, NO boxing): all int /
float / char / bool arithmetic+comparison whose operands are literals or
typed temps — i.e. everything M2.1 exercises.
**Runtime fallback** (`xatsgo.Xats_<name>`): the boxed/higher-order path
for the SAME ops (kept so a first-class op value still works), plus the
per-type prints and `strn_append`. Every native-inlined op-temp's binding
drops to `_ = xatsgo.Xats_<name>` via the op-aware liveness rule.

## Op-aware liveness (the one subtlety)

The op-temp (`opT := <op>`) is referenced by the `I1INSdapp` callee, but
when that dapp inlines natively the Go code does NOT reference `opT`. So
`used_in_ins`'s `I1INSdapp` case SKIPS counting the callee when
`is_native_binop_dapp` holds (the 2 args ARE still counted). The op-temp
thus becomes "dead" and its binding emits as `_ = xatsgo.Xats_<name>`
(legal Go; the runtime fn exists). The liveness walk now threads `scp`
(the enclosing cmp) so it can resolve op-temps; it re-roots `scp` at each
nested-cmp boundary (let/if/case/lam bodies are their own op scopes).

## Emitted-Go evidence (Regime-B)

```go
// test02_arith:                       // test03_compare:
goxtnm20 := (2 * 3)                     goxtnm23 := (1 < 2)
goxtnm21 := (1 + goxtnm20)              goxtnm183 := (5 == 5)
goxtnm95 := (7 / 2)                     // test05_float:
goxtnm147 := (goxtnm146 / 2)  // (0-7)/2 -> -3   goxtnm13 := (1.5 + 2.25)
// test06_char:                              goxtnm79 := (7.5 / 2.0)
goxtnm51 := ('a' < 'b')                 // op-temps (dead) ->
goxtnm6 := goxtnm5('A')  // char_print  _ = xatsgo.Xats_sint_add_sint
```

## Division / mod semantics (verified vs JS)

Go int `/` truncates toward zero == JS `Math.trunc(i1/i2)`; Go int `%`
takes the sign of the dividend == JS `%`. test02_arith checks `(0-7)/2 ==
-3` and `(0-7)%2 == -1` and is byte-equal to JS. (Negation `~` on a
literal is a special form / errck'd in this surface, so `-7` is written
`0 - 7`.)

## xatsgo runtime additions (`runtime/xatsgo/xatsgo.go`)

- Per-type prints (push onto the print store): `Xats_sint_print`
  (strconv.Itoa), `Xats_bool_print` ("true"/"false"), `Xats_char_print`
  (`string(rune(c))`), `Xats_dflt_print` (`XatsFloatToString` ==
  JS `Number.toString()` for ordinary decimals via `strconv.FormatFloat(f,
  'g', -1, 64)`).
- `Xats_strn_append` (string `+`), `Xats_strn_length`.
- `any`-typed op fallbacks: `Xats_sint_{add,sub,mul,div,mod,lt,gt,lte,gte,
  eq,neq}_sint` (the `$`→`_` mangled names), `Xats_dflt_*_dflt`,
  `Xats_char_{lt,gt,lte,gte,eq,neq}` (no suffix), `Xats_bool_{eq,neq}`.
  These exist so the dead op-temp `_ = xatsgo.Xats_<name>` resolves and so
  any non-inlined (higher-order) op use stays correct.

## JS-ORACLE infrastructure: a SECOND prebuilt-bundle defect (tokenfpr)

`frontend/BUILD/lib2xats2js.js` (the JS differential REFERENCE) REFERENCES
but never DEFINES `tokenfpr` (the token pretty-printer), so js1emit crashes
(`ReferenceError: tokenfpr_NNNN is not defined`) the moment it emits an
`I1INSlam0`/`I1INSfix0` — which the primop/print TEMPLATES instantiate.
Same defect class as the `i0varfst` issue (Go emitter unaffected; this only
restores the oracle). FIX: `runtime/jsshim/gen-i0varfst-shim.sh` now ALSO
emits a no-op `tokenfpr` (defined only if the bundle references it; it
writes solely into a JS `// comment`, so it's byte-safe). M2.x should fix
both at the source by rebuilding lib2xats2js.js once the funset library +
the missing util impls transpile.

**String concat caveat:** `strn_append` (`"a"+"b"`) triggers a THIRD,
distinct JS-backend bug (`env1` undefined inside the emitted
`strn_make_fwork` closure), which the shim does not address. So string
concat/length are kept OUT of the oracle-gated suite for now; the Go side
emits them correctly, they just lack JS-oracle validation until the JS
backend's closure emission is fixed/rebuilt.

## Honest coverage / real-vs-stub (M2.1)

- **REAL (native-typed, oracle-validated):** int +,-,*,/,%; int
  <,>,<=,>=,=,!=; float +,-,*,/ and compare; char literals + char compare;
  bool eq/neq; bool comparison results; per-type prints. All emit native Go
  operators on concrete `int`/`float64`/`rune`/`bool` and are BYTE-EQUAL to
  the JS backend (the 6-test suite). `gotype_of_ival` is now wired (drives
  literal emission); `gotype_of_styp` still scaffold (no styp-typed temps
  reach the scalar path yet — that's the M2.6 side-table).
- **REAL but NOT oracle-validated:** `strn_append`/`strn_length` emission
  (Go correct; JS backend can't run it — see caveat). Kept out of the suite.
- **`any`-FALLBACK / deferred:** any op whose operand is an opaque computed
  temp from a NON-native producer (none arise in M2.1's literal-driven
  tests, but the runtime fallbacks exist for it); the variadic `prints`
  template (needs faithful timp inlining — M2.2); negation `~`, `&&`/`||`
  (special forms). Functions/closures/TCO/if/case/tuples/datatypes/
  exceptions/lazy remain for M2.2–M2.8.

## What M2.2 (functions) should pick up

- Faithful `I1INStimp` template INLINING (body via `t1imp_i1cmpq`) so the
  variadic `prints`/`gs_print_aN` and other template-bodied prelude fns
  work (today only plain external-cst timps route to named runtime fns).
- `I1Dfundclst`/`i1fundcl`, `fjarglst`/`FJARGdarg`, `I1INSdapp` to user
  functions, `I1Vfid`/`I1Vcst` — and the FIRST real stress of the i0varfst
  shim (free-var sets). Concrete function SIGNATURES become recoverable via
  `d2cst_get_styp` → `T2Pfun1` arg/result types (feeds `gotype_of_styp`).

---

# M2.2 — User-defined functions & calls (NON-recursive), Regime-B typed

Status after **M2.2**: top-level `fun`/`fn` declarations emit as
**package-level** Go functions with **concrete-typed signatures where
recoverable**, and calls to them work, gated by the differential-vs-JS
oracle. All additive under `srcgen2/xats2go/`. `run-suite.sh` = 10 GREEN.

## How to run (M2.2)

```bash
bash srcgen2/xats2go/srcgen2/TEST/run-suite.sh   # 10 GREEN
# or one test through the oracle:
bash srcgen2/xats2go/build-go.sh srcgen2/xats2go/srcgen2/TEST/test07_fun1_xats2go.dats
```

Suite adds test07 (one arg, one call), test08 (one fn called multiple times +
result fed into arithmetic), test09 (a fn calling another fn), test10 (multiple
args, mixed scalar types int+float64). Each prints a deterministic result and is
**byte-equal to the JS backend**; gofmt-clean; `go vet` OK.

## THE KEY IR FINDINGS (reusable; capture via the emitter's stderr IR-DUMP)

A top-level `fun dbl(x: sint): sint = x + x` lowers to (locations elided):

```
I1Ddclenv(                                     // (A) ENV WRAPPER -- unwrap!
  I1Dfundclst(
    T_FUN(FNKfn1); 0;                          // token; lvl0
    $list();                                   // t2qaglst -- EMPTY => a FUNCTION
                                               //   (non-empty => TEMPLATE, M3)
    $list(dbl(2699));                          // d2cstlst -- the SIGNATURE source,
                                               //   POSITIONAL with i1fundclist
    $list(I1FUNDCL(
      dbl(5204);                               // d2var (dpid) -- the fn NAME
      $list(FJARGdarg($list(                   // fjarglst
        I1BNDcons(I1TNM(1); I0Pvar(x(5205)); ...)))),  // one param, tnm stamp=1
      TEQI1CMPsome(T_EQ0(); I1CMPcons(         // (B) BODY
        $list(I1LETnew0(I1INSrturn(            //   single rturn ins
          I0CALfun(dbl(5204); $list(dbl(5204)));   // call/tail info
          I1CMPcons(                           //   the INNER cmp (real compute):
            $list( I1LETnew1(I1TNM(8); I1INStimp(sint_add$sint)),
                   I1LETnew1(I1TNM(9); I1INSdapp(I1Vtnm(8); [I1Vtnm(1),I1Vtnm(1)])) );
            I1Vtnm(I1TNM(9))))));              //   inner result = x+x
        I1Vnil())))))                          //   outer result = unit (discarded)
  ; $list())                                   // (A) i0varlst = FREE-VAR SET (empty)
```

The call `dbl(21)` lowers to:
```
I1INSdapp(I1Vfenv(dbl(5204); $list()); $list(I1Vint(T_INT01(21))))
```

1. **`I1Ddclenv(idcl, i0varlst)` wraps every top-level fn.** The `i0varlst` is
   the **i0varfst free-var set** (the shim's output). The pass-1 walk must UNWRAP
   `I1Ddclenv`/`I1Dtmpsub`/`I1Dstatic` to reach the inner `I1Dfundclst` (a bare
   `I1Dfundclst` check misses every real top-level function). For a non-closure
   top-level fn the set is empty -> no captured-env Go params.
2. **The body is `I1CMPcons([I1LETnew0(I1INSrturn(i0cal, innerCmp))], I1Vnil())`.**
   The real computation is the **inner** cmp of the `I1INSrturn`; the outer cmp's
   result is unit and discarded. `i1cmp_go1emit_ret` unwraps this canonical
   single-rturn shape -> emits the inner cmp's lets then `return <inner.result>`.
   (A non-rturn body falls back to "emit lets then return the cmp's own result".)
3. **A call's callee is `I1Vfenv(d2var, envs)`** (function value = its d2var +
   captured-env values), **NOT `I1Vfid`**. For a non-closure fn `envs=$list()`,
   so the call emits `<d2vargo1(d2var)>(<args>)` with args straight through; the
   env values would be appended after the args (lst2 order) for M2.5 closures.
4. **Params need NO `arg<N>` indirection.** Each `i1bnd`'s own `i1tnm`
   (`goxtnm<stamp>`) IS the Go param name, and the body references the param
   through that SAME `i1tnm` -> decl and use agree by construction. (The JS
   backend binds `let jsxtnm<stamp> = arg<N>` as a prologue; Go skips that.)
5. **Name mangling agreement:** the decl's `i1fundcl_dpid` (`dbl(5204)`) and the
   call's `I1Vfenv` d2var (`dbl(5204)`) are the SAME d2var, so routing both
   through `d2vargo1` (`<sym>_<loc-stamp>`, e.g. `dbl_695`) guarantees the call
   site and decl name match.

## Package-level emission (the Go-vs-JS structural divergence)

Go forbids named `func` declarations inside a function body (only `name :=
func(){}` closures). So unlike the JS backend (which nests everything in IIFEs),
`i1parsed_go1emit` does a **TWO-PASS** walk over the single flat `i1dclist`:
- **PASS 1** (`i1dclistopt_go1emit_funs`, nind=0, BEFORE `func main`): emits ONLY
  the function groups (unwrapping `I1Ddclenv`), as package-level `func`s.
- **PASS 2** (`i1dclistopt_go1emit`, inside `func main`): emits everything else;
  `i1dcl_go1emit` SKIPS `I1Dfundclst` (already emitted in pass 1).
This also makes recursion's self-call resolve naturally (a package func is
visible regardless of textual order), de-risking the M2.4 stopgap.

## Regime-B signature typing (concrete vs `any`)

`gotypes_of_funstyp(d2cst_get_styp(dcst))` (in `go1emit_styp0.dats`) recovers the
Go arg-type list + result type from the function's `T2Pfun1(f2clknd, npf, args,
res)` (chasing quantifier/instantiation wrappers `T2Puni0/exi0/apps/lam1` + the
init/lvalue wrappers first). It DROPS the leading `npf` proof args (erased), then
maps each value arg + result through `gotype_of_styp`. **Crucial scalar finding:**
the prelude scalar types are NOT bare `T2Pcst("sint")` -- they are applied
abstract type-constructors:
- `sint` = `gint_type(sint_k, i)` = `T2Papps(T2Pcst("gint_type"), [T2Ptext("xats_sint_t"), idx])`
- `dflt` = `gflt_type(dflt_k)`   = `T2Papps(T2Pcst("gflt_type"), [T2Ptext("xats_double_t")])`
- `bool` = `bool_type(b)`        = `T2Papps(T2Pcst("bool_type"), [idx])`
- `char` = `char_type(c)`        = `T2Papps(T2Pcst("char_type"), [idx])`

So `gotype_of_styp` now handles `T2Papps(T2Pcst(name), args)`: for the gint/gflt
family the precise width comes from the first-arg `T2Ptext` ($extype) name
(`xats_sint_t`->int, `xats_double_t`->float64, all int widths -> Go `int`);
`bool_type`/`char_type` map by head name. Everything else still -> `any`.

Emitted-Go evidence:
```go
func dbl_695(goxtnm1 int) int { goxtnm9 := (goxtnm1 + goxtnm1); return goxtnm9 }
func axpy_569(goxtnm1 int, goxtnm2 int, goxtnm3 int) int { ... return ... }
func favg_626(goxtnm20 float64, goxtnm21 float64) float64 { ... return ... }
// call sites:  dbl_695(21)   inc2_767(40)   axpy_569(3, 4, 5)   favg_626(1.0, 4.0)
// fn result in arithmetic:  goxtnm31 := (goxtnm29 + goxtnm30)  // sqr(2)+sqr(3)
```

**What's concrete vs `any`:** ALL of M2.2's tested surface (sint/dflt args+results)
types CONCRETELY (`int`/`float64`). `any` is the documented fallback for: a fn
whose static type isn't a recognizable `T2Pfun1`; an arg/result of a type outside
the scalar table (datatypes/tuples -> M2.6/M2.7); and a polymorphic (`s2var`)
arg before monomorphization. Full concrete typing of arbitrary LOCAL temps still
waits on the M2.6 `i1tnm->i0typ` side-table (the result of a `dapp` whose callee
is an opaque temp is still `any`); but a NAMED function's signature is fully
recoverable today, which is the M2.2 Regime-B payoff.

## i0varfst shim status (the M2.2-mandated validation)

**VALIDATED, no divergence.** Real multi-function programs exercised the shim
cleanly: `trxd3i0` computed each function's free-var set, `lib2xats2cc.js`
linked (with the shim) without `i0varfst_*` ReferenceErrors, and the set
surfaced in the IR as the `i0varlst` tail of `I1Ddclenv`. Because every M2.2 test
is byte-equal-vs-JS (and the JS reference uses the SAME shim), any shim semantic
divergence would have shown as a byte mismatch -- none did. (For the M2.2 surface
the sets are all empty, since top-level functions capture nothing; M2.5 closures
will stress the set's CONTENTS, not just its presence.)

## Recursion stopgap (probe test11, NOT in the green suite)

`test11_fun_rec` (`fact` via `if`) confirms the M2.4/M2.3 boundary precisely: the
function body is an `I1INSift0` (if-then-else) -> currently UNHANDLED (that's
M2.3 control flow), so test11 emits a clean `/* UNHANDLED: i1ins */ nil` marker +
a loud stderr note and is correctly EXCLUDED from the oracle-gated suite. The IR
dump shows the recursion plumbing already in place: the self-call is
`I1INSdapp(I1Vfenv(fact(5204); $list()); ...)` -> resolves to `fact_729(...)` (a
package-level Go recursive call, the stopgap), and each `if` branch carries its
OWN `I1INSrturn`. So **M2.3 must emit `I1INSift0` in return-mode** (`if cond {
...; return X } else { ...; return Y }`), after which simple recursion runs as a
plain Go recursive call with NO new call plumbing; **M2.4** then layers the TCO
loop on the tail case (`i1cmp_tailq` + `I0CALfun`/`I0CALfix`).

## Honest coverage / real-vs-stub (M2.2)

- **REAL (Regime-B-typed, oracle-validated):** `I1Dfundclst`/`i1fundcl` (the
  function group walk, unwrapping `I1Ddclenv`/`I1Dtmpsub`/`I1Dstatic`);
  `fjarglst`/`FJARGdarg`/`i1bnd` -> typed Go params; the function-body return
  mode (`i1cmp_go1emit_ret`, unwrapping the canonical `I1INSrturn`); `I1INSdapp`
  to user fns via `I1Vfenv` (+ `I1Vfenv` as a standalone fn value);
  `gotypes_of_funstyp` concrete signature recovery (incl. the prelude
  `gint_type`/`gflt_type`/`bool_type`/`char_type` abstype mapping). All emit
  package-level Go funcs with concrete `int`/`float64` signatures and are
  byte-equal-vs-JS (10-test suite).
- **DOCUMENTED `any` fallback:** non-`T2Pfun1` styps; non-scalar arg/result
  types (datatypes/tuples, M2.6/M2.7); polymorphic args (`s2var`) pre-mono;
  arbitrary local temps from opaque producers (the M2.6 side-table debt).
- **STOPGAP / out of scope (reported, not silently wrong):** template fundclst
  (non-empty `t2qaglst`) -> `// UNHANDLED: template fundclst` (M3); a fn body
  shaped as `if`/`case`/`let` (`I1INSift0` etc.) -> `/* UNHANDLED: i1ins */ nil`
  (M2.3) -- which is why recursion (test11) is excluded; closures (`I1Vfenv` with
  a non-empty capture) -> bare name + a stderr NOTE (M2.5); faithful template
  `I1INStimp` inlining still deferred (M2.x); no-body fn -> `panic(...)` stub.

## What M2.3 / M2.4 / M2.5 must pick up (precise hand-off)

- **M2.3 (control flow):** `I1INSift0`/`I1INScas0`/`I1INSlet0`, AND their
  **return-mode** variants -- each `if`/`case` branch in a function body carries
  its own `I1INSrturn` (verified in test11's IR), so the cmp emitter needs a
  return-aware path that turns branch rturns into per-branch `return`s. This
  immediately unblocks simple (non-tail) recursion.
- **M2.4 (recursion + TCO):** `I1INSfix0` (self-ref via `I0CALfix`) and the
  tail case of `I1INSrturn` (`i1cmp_tailq`/`i1val_tailq` + `I0CALfun`) ->
  `for { … args = …; continue }`. The package-level emission already makes the
  non-tail self-call work as a plain Go recursive call (the stopgap); M2.4 only
  adds the loop for the tail case (no new call plumbing).
- **M2.5 (closures):** `I1INSlam0` + `I1Vfenv` with a NON-empty capture (the
  `i0varlst`/`envs` tail). The plumbing is staged: `i1valgo1_lst2` already
  appends env values after args at the call site, and the `I1Vfenv` standalone
  case already emits the name + a NOTE -- M2.5 wires the actual closure
  conversion (capture struct / Go func literal) and the env-value binding. This
  is the first chunk that stresses the i0varfst set's CONTENTS (not just
  presence).

---

# BUILD INFRASTRUCTURE — incremental Makefile (the fast dev cycle)

Status: the sequential shell harness (`build-go.sh`) is now backed by a
**GNU-make Makefile** at `srcgen2/xats2go/Makefile` that does **separate /
incremental compilation**. Across an edit cycle the ONLY things that change are
our `srcgen2/DATS/*.dats` emitter sources (usually ONE at a time); the Makefile
re-transpiles JUST the changed file, re-concats `lib2xats2go.js`, re-links the
emitter bundle, and runs the test(s) — it never re-transpiles the other 13
files and never rebuilds any fixed lib.

## How to run (the new fast path)

```bash
cd srcgen2/xats2go
make -j            # cold parallel build of the emitter bundle
make               # incremental: rebuild only what a .dats edit invalidated
make suite         # the 10-test differential-vs-JS oracle + pass/fail summary
make run/test07_fun1_xats2go         # one test through the oracle
make TEST=srcgen2/TEST/test01_xats2go.dats test   # one test by path
make clean         # remove emitter artifacts (KEEP cached fixed libs)
make cleanall      # also remove cached fixed libs (NEVER lib2xatsopt.js)
```

`make` is GNU make 3.81 (macOS system make) — only 3.81-safe features are used
(pattern rules, `$(patsubst ...)`, `.SECONDARY`/`.PRECIOUS`, `-j`).

## Target graph (brief)

```
DATS/%.dats ──(jsemit00, parallel, guarded)──► BUILD/JS/%_dats_out0.js   [STEP A]
                                                      │ (sed jsxtnm→jsx<NNN>tnm,
                                                      │  index = position in GO_DATS)
                                                      ▼
                                              BUILD/JS/%_dats_ns.js        [STEP B]
                                                      │ (concat in GO_DATS order)
   all _ns.js ───────────────────────────────────────┴──► BUILD/lib2xats2go.js  [STEP C]

DRIVER ──(jsemit00)──► BUILD/xats2go_goemit01_dats.js                     [STEP D]
frontend/BUILD/lib2xats2cc.js ──(symlink/copy)──► BUILD/lib2xats2cc.js    [FIXED]
frontend/BUILD/lib2xats2js.js ──(symlink/copy)──► BUILD/lib2xats2js.js    [FIXED, JS oracle]

lib2xats2go.js + goemit01_dats.js + lib2xats2cc.js + lib2xatsopt.js
   ──(cat runtime + sed js1·opt + js2·cc + js3·go + driver + i0varfst shim)──►
                                              BUILD/xats2go-bundle.patched.js  [BUNDLE]

bundle + lib2xats2js.js + jsemit01_dats.js ──(per test)──► _oracle:
   run emitter→.go→gofmt/vet/build/run→GO stdout ; run JS backend→JS stdout ;
   assert byte-equal (xxd diff on mismatch); refresh OUTS/<name>.expected.
```

The emitter source list is the single `GO_DATS := ...` variable (mirrors
build-go.sh's `GO_DATS`). To add an emitter file, append it there in dependency
order (after `xats2go_myenv0`, before `xats2go_tmplib`, which stays LAST).

## The cached-vs-rebuilt split (what stays fixed)

- **`lib2xatsopt.js`** (171 MB) — a content prerequisite of the bundle so an
  edit to it WOULD relink, but it never changes. There is NO target that
  rebuilds it. `cleanall` never touches it.
- **`lib2xats2cc.js`** — `BUILD/lib2xats2cc.js` is a symlink to
  `frontend/BUILD/lib2xats2cc.js`; rebuilt only if missing/stale vs the
  prebuilt. The emitter `.dats` are NOT prerequisites, so a normal edit leaves
  it untouched.
- **`lib2xats2js.js`** (the JS oracle) — symlink to
  `frontend/BUILD/lib2xats2js.js`. If that prebuilt is ever absent, the recipe
  builds it ONCE from the xats2js source set (`XATS2JS_DATS`, the build-m0b.sh
  recipe) and caches it; here it is present, so that fallback is dormant.
- **The i0varfst+tokenfpr shim** — regenerated by the bundle link step (it
  discovers the per-build stamped names from the bundle), i.e. only when the
  bundle is relinked.

## Namespace-index STABILITY (the critical hazard, GUARANTEED)

The per-file namespace token (`jsxtnm → jsx<NNN>tnm`) must be **unique + stable
per filename** — a collision across files clashes temp names and corrupts
output. Guarantee: the index is a **pure function of the filename's position in
`GO_DATS`** (100, 101, … by position), computed in STEP B independently of build
order. So `make -j` (which transpiles in arbitrary order) yields the SAME
assignment as a sequential build, and appending a file never renumbers an
existing one.

**Proof:** a Makefile-built `BUILD/lib2xats2go.js` is **byte-identical**
(`md5 = 0ed89c3dab083e627d1d06bd35d05960`, 127 564 lines) to the known-good
shell-built (`build-go.sh`) `lib2xats2go.js`. Same content ⇒ same per-file
index assignment ⇒ the suite stays green.

## Measured speedup (the win)

| scenario | command | wall |
|---|---|---|
| cold, parallel | `make -j18 bundle` | ~24 s |
| cold, sequential | `make -j1 bundle` | ~40 s |
| incremental (touch ONE `go1emit_*.dats`) | `make bundle` | ~15 s |
| warm no-op (nothing changed) | `make bundle` | ~0.02 s |

A single jsemit00 transpile costs ~1.4 s (real) / ~2.6 s (user); the
incremental path re-transpiles exactly ONE file (verified by mtime: only
`go1emit_dynexp_dats_out0.js` changed) and rebuilds NO fixed lib
(`lib2xats2cc.js` and `lib2xatsopt.js` mtimes unchanged). The residual ~15 s of
the incremental build is the unavoidable bundle relink — three `sed -E` passes
over the 171 MB `lib2xatsopt` + 16 MB cc + 14 MB go — the same cost the shell
harness pays; the win is the 13 skipped transpiles (~18 s of jsemit00 work).

## Intermediate-file persistence (subtle make trap)

`BUILD/JS/%_dats_out0.js` and `%_dats_ns.js` sit in a `.dats → _out0 → _ns →
lib` chain, so make would treat them as throwaway intermediates and DELETE them
after each build — forcing a full re-transpile every time and destroying
incrementality. They are kept via `.SECONDARY:` (disables intermediate deletion
globally) plus an explicit `.PRECIOUS:` for the two lists.

## jsemit00 needs XATSHOME in the ENV

jsemit00 resolves `/prelude/*.sats` relative to `$XATSHOME`; if unset it opens
`/prelude/basics0.sats` and dies (`ENOENT`). build-go.sh `export`s it; the
Makefile does `export XATSHOME` (not just a make-var assignment) so every
recipe's node invocation sees it.

## Legacy entry points (kept working)

`build-go.sh`, `run-suite.sh`, `build-go-m0.sh`, `build-go-m1.sh` are UNCHANGED
and still function as before (they write their per-file transpiles into
`BUILD/DATS__*_out0.js`, a different namespace from the Makefile's
`BUILD/JS/*_out0.js`, so the two harnesses never clash). They are now the
**legacy / reference oracle** path; the Makefile is the fast dev path and
reproduces the same byte-equal-vs-JS results. `build-go.sh` remains the
differential ground truth that the Makefile's namespace-index assignment was
validated against (byte-identical lib2xats2go.js).

---

# M2.3 — Control flow: if / let-in / case (simple patterns), return-vs-value mode

Status after **M2.3**: `I1INSift0` / `I1INSlet0` / `I1INScas0` emit as idiomatic
Go (`if`/`else`, local-decl block, expression-less `switch`) in BOTH value- and
return-position; the **recursive factorial is green** (`fact(5)=120`,
byte-equal-vs-JS). `make suite` = 16/16. All additive under `srcgen2/xats2go/`.

## How to run (M2.3)

```bash
cd srcgen2/xats2go
make suite                       # 16 GREEN (10 prior + 6 control-flow)
make run/test14_fact_xats2go     # the HEADLINE recursive factorial
```

Suite adds test12 (if RETURN mode), test13 (if VALUE position), **test14 the
recursive factorial**, test15 (case int/char + default), test16 (case guards),
test17 (let-in). Each prints a deterministic result, byte-equal-vs-JS,
gofmt-clean, `go vet` OK.

## THE crux: return-mode vs value-mode (and the recursion subtlety)

A value-position if/case/let surfaces as `I1LETnew1(tnm, ift0/cas0/let0)`; a
return-position one has every branch body ending in `I1INSrturn`. The mode is
decided LOCALLY by **`i1ins_fully_returnsq(iins)`** (do all present branches
`i1cmp_retq`?):
- **return mode** -> each branch via `i1cmp_go1emit_ret` (emits its own
  `return`); NO pre-declared result temp.
- **value mode** -> pre-declare `var goxtnm<tnm> <T>`; each branch via
  `i1cmp_go1emit_tnm` (`goxtnm<tnm> = <result>`), or the effect form if dead.

The recursion crux: a `fun = if … then … else …` body lowers to a cmp whose
LAST let is `I1LETnew1(tnm, fully-returning ift0)` and whose result is
`I1Vtnm(tnm)`. Stock **`i1cmp_retq` returns FALSE** for this (it only inspects
`I1LETnew0`), so the function-body emitter would append a dangling `return
goxtnm<tnm>` reading an unassigned var. Fix = **`i1cmp_tail_returns`** (in
`go1emit_styp0.dats`): `i1cmp_retq(icmp) OR (last let is I1LETnew1(tnm,
fully-returning if/case) AND result == I1Vtnm(tnm))`. All three cmp emitters
(`_ret`/`_tnm`/effect) suppress their trailing result when it holds. (Verified:
test14/test11 emit `if … { return 1 } else { … return n*fact(n-1) }` with NO
dangling return; `fact_<stamp>` is a real Go recursive call.)

## case -> expression-less switch (+ guards folded into the condition)

`switch { case <i0pckgo1(casval, pat)>: <body>; …; default: panic("xats2go:
XATS000_cfail") }`. **`i0pckgo1`** mirrors js1emit's `i0pckjs1` for SIMPLE
patterns: var/wildcard -> `true`; int/char/bool/float literal -> native
`<casval> == <lit>`; transparent `!`/flat/free -> recurse; **datacon/tuple/record
-> `false` test + stderr NOTE (M2.7)**. The `default:` arm is a LITERAL
`panic(...)` (a Go TERMINATING statement) so a return-position switch where every
real case returns is seen as exhaustive (else `go vet`: "missing return") -- the
named `xatsgo.Xats_cfail` runtime fn is kept as the documented sentinel but no
longer emitted. **Guards** (`I1GPTgua`) are FOLDED into the case condition:
guard-lets are pre-emitted ABOVE the switch (the guard references the scrutinee
temp, already in scope), and the result i1val joins the pattern test as `case
<patcond> && <guard>:` -- so a failed guard falls through to the NEXT clause,
matching the JS backend's retry. (test16 emits `case true && goxtnm10: return 1`
/ `case true && goxtnm19: return 0` / `case true: return 5`.)

## value-position type recovery (avoids `any` on computed results)

A value-position result temp needs a Go TYPE for `var goxtnm<tnm> <T>`.
`gotype_of_ift0type` takes the branch/clause RESULT types; literals type
directly, but a COMPUTED result (e.g. let-in's `a * a`) is `I1Vtnm`. Improved
**`gotype_of_cmp`** scans the cmp's lets for the result temp's producer
(`gotype_of_tnm_in_lets2`, threading the FULL let-list so an op-temp callee that
precedes its use in ANF still resolves) and types it: a native-op dapp ->
`op_result_goty` (compares -> `bool`, arithmetic -> operand type); a nested
block -> its branch type; else `any`. (test17 emits `var goxtnm26 int`, not
`any`, so `(goxtnm26 + 100)` type-checks.)

## non-unit `val x = CMP` patterns (needed by let-in inner decls)

`i1valdcl_go1emit` now handles `I0Pvar` (`val x = …`): emit the cmp lets then
`goxtnm<itnm> := <result>` + a `_ = goxtnm<itnm>` suppressor (the body references
`x` through that SAME i1tnm). `I0Pany` (`val _ = …`) -> effect form.
Tuple/record/datacon `val` patterns still -> UNHANDLED (M2.6/M2.7).

## BUILD GOTCHA (bit twice): a SATS change shifts ALL stamps

`go1emit.sats` gained new `fun` decls. The transpiler assigns each SATS function
a stamp by position, so adding a decl SHIFTS the stamps of later ones. The
Makefile's per-`.dats` transpile rule does NOT depend on the SATS, so files that
didn't themselves change keep a STALE stamp -> link-time `ReferenceError:
<fn>_<oldstamp> is not defined` (hit for `i1cmp_go1emit_ret`, then
`i1parsed_go1emit` in the driver). **After ANY `go1emit.sats` edit, force a clean
transpile of ALL GO_DATS + the driver:**
```bash
rm -f srcgen2/BUILD/JS/*_dats_out0.js srcgen2/BUILD/JS/*_dats_ns.js \
      srcgen2/BUILD/lib2xats2go.js srcgen2/BUILD/xats2go_goemit01_dats.js \
      srcgen2/BUILD/xats2go-bundle.patched.js
make -j
```
(A DATS-only edit is fine incrementally -- stamps are stable.) A clean rebuild +
`make suite` was run as the definitive 16/16 check.

## emitter structure note (mutual recursion)

The new if/case/let/clause emitters are all TOP-LEVEL functions (the SATS-declared
ones as `#implfun`, the helpers as standalone `fun`s ordered before their callers
or routed through SATS-declared functions), mirroring how the original four
cmp/let emitters were mutually recursive -- NOT one `fun…and` group (you cannot
put `#implfun` in an `and` chain). Local `env0.nind()` after a `val nind = …`
binding SHADOWS the `#symload nind`, so inline current-indent reads use
`envx2go_nind$get(env0)` directly.

## Honest coverage / real-vs-stub (M2.3)

- **REAL (oracle-validated):** `I1INSift0` (value + return), `I1INSlet0` (value),
  `I1INScas0` over int/char/bool/float LITERAL patterns + var/wildcard + a default;
  guards folded into the case condition; the return-vs-value-vs-effect mode
  threading + `i1cmp_tail_returns` recursion fix; `gotype_of_cmp` computed-result
  typing; non-unit `val x =` (var) patterns. Recursive factorial green.
- **DEFERRED (reported, not silently wrong):** datacon/tuple/record case patterns
  (`I0Pcon`/`I0Pdapp`/`I0Ptup*`/`I0Prcd2`) -> `false` test + stderr NOTE (M2.7);
  tuple/record `val` patterns -> UNHANDLED (M2.6/M2.7); multi-guard clauses use
  the FIRST guard (the rest would need &&-joining at the case site -- a small
  follow-up; M2.3 tests are single-guard); a TOP-LEVEL `val x = if/let/case`
  doesn't lower (front-end leaves `I1Vnone1`) so value-position tests are
  function-bodied. TCO (the tail case of `I1INSrturn`) is M2.4.

---

# BUILD-PERF — cache the FIXED sed work; build the JS oracle ONCE (no output change)

Status: the Makefile relink and the per-test JS-oracle build no longer re-`sed`
~200 MB of FIXED content on every edit / every test. The emitter bundle and the
JS-oracle bundle are now assembled in a SINGLE write from cached pieces; the
~200 MB of namespace-sed is done exactly ONCE. **`make suite` = 16/16
byte-equal-vs-JS, gofmt-clean, `go vet` OK; the emitter bundle is byte-identical
(md5) to the pre-optimization one — output is provably unchanged.**

## What was cached / restructured (target-graph delta)

- **`BUILD/lib2xatsopt.js1.js`** := `sed js1 lib2xatsopt.js` — prereq `lib2xatsopt.js`
  ONLY (the 171 MB → cached once, ~10 s one-time). Never rebuilt on an emitter edit.
- **`BUILD/lib2xats2cc.js2.js`** := `sed js2 lib2xats2cc.js` — prereq the cached cc
  ONLY (16 MB → cached once).
- **`BUILD/i0varfst-shim.go.js` / `.js.js`** — the i0varfst(+tokenfpr) shims,
  generated ONCE. VERIFIED the shim resolves ONLY names from FIXED libs and that
  none of those names contains a `jsx<NNN>tnm` token (so the namespace-sed never
  rewrites them → stamps identical in raw lib, cached js1/js2 lib, and final
  bundle). The shim's grep targets split across two FIXED libs:
  `i0varfst_*`/`i0var_dvar$get` (cc), `d2var_get_stmp`/`stamp_get_uint` (opt),
  `tokenfpr` (lib2xats2js, JS-oracle only). gen-i0varfst-shim.sh scans ONE file,
  so a tiny `BUILD/i0varfst-shim.optnames.js` extract (the 2 opt-resident names,
  grepped once from opt) is concatenated with cc.js2 (GO shim) or cc.js2 + the JS
  lib (JS shim) as the scan input. **None of this depends on the CHANGING
  lib2xats2go**, so an emitter edit regenerates NO shim. (The Go bundle never
  references tokenfpr — verified 0 refs in lib2xats2go/driver/runtime — so its
  shim omits the tokenfpr block, byte-identical to the old per-bundle shim.)
- **`$(GOPATCHED)` single-pass relink**: `cat GO_SHIM RUNTIME opt.js1 cc.js2
  <(sed js3 lib2xats2go) DRV_GO > GOPATCHED` in ONE write. Only the 14 MB
  lib2xats2go is re-sed'd per edit; the 200 MB intermediate `GOBUNDLE` and its
  second 200 MB copy are GONE. Byte-order identical to the old recipe.
- **`$(JSPATCHED) = BUILD/xats2js-ref.patched.js`** — the JS-oracle reference
  bundle, built ONCE (it is test-INDEPENDENT: the source is passed as `argv`).
  `_oracle` step [3/5] now just `node $(JSPATCHED) "$SRC"` instead of rebuilding
  the ~200 MB bundle per test. `test`/`run/%`/`suite` depend on `$(JSPATCHED)` so
  it's linked once up front.
- **`NODE_COMPILE_CACHE=$(BUILD)/.v8cache`** exported for all node runs — caches
  the ~200 MB bundle's V8 bytecode so repeated runs skip parse/compile.
- **`make -jN psuite`** — a PARALLEL suite (per-test stamp targets fan out once
  the shared bundles are built); sequential `make suite` is unchanged.

## BEFORE / AFTER (measured, Node 26.3 / Go 1.26, 18-core)

| scenario | BEFORE | AFTER |
|---|---|---|
| incremental relink (touch ONE go1emit_*.dats) | **14.70 s** | **1.69 s** |
| single test, warm bundle (`make run/NAME`) | **18.61 s** | **3.01 s** |
| single test, cold-ish (relink + test) | ~33 s | **4.90 s** |
| full suite, sequential (`make suite`) | **270.58 s** | **47.07 s** |
| full suite, parallel (`make -j psuite`) | — | **9.85 s** |
| cold bundle (`make -j bundle`) | ~23 s | ~9.5 s |
| cold from scratch (`cleanall` → `make suite`) | — | ~84 s |

The relink win: the per-edit cost is now ONE jsemit transpile + concat + a single
`cat` of cached pieces (only the 14 MB go lib re-sed'd) — no 171 MB + 16 MB seds,
no 200 MB double-write. The suite win: the per-test ~200 MB JS-ref rebuild (×16)
collapses to a single cached bundle + a `node` run.

## NODE_COMPILE_CACHE — measured, KEPT

Running the emitter bundle directly: ~0.57 s without the cache vs ~0.34 s warm
(populate run ~0.61 s) — ≈40 % off node startup on the ~200 MB bundle. Each test
invokes node twice (emitter + oracle), so it compounds across the suite. Kept.

## Correctness proofs

- **Go emitter bundle byte-identical:** `md5(xats2go-bundle.patched.js) =
  46bc04d373b3812bc475ae2e10bb64d3`, unchanged across the inline (pre-opt) build,
  the optimized cold build, the incremental relink, and a `clean`+rebuild.
- **JS-oracle bundle byte-identical:** the cached `$(JSPATCHED)` is byte-equal
  (`md5 b6ff5bec…`) to a freshly inline-built JS-ref bundle (old `_oracle` [3/5]
  linkage). The namespace-sed semantics are preserved exactly (caching the sed
  output IS the sed output).
- **Suite:** 16/16 byte-equal-vs-JS, gofmt clean, `go vet` OK — sequential AND
  parallel, cold AND warm.
- **mtime proof:** after `touch`-ing one `go1emit_*.dats`, the cached
  `lib2xatsopt.js1.js`, `lib2xats2cc.js2.js`, both shims, the opt-names extract,
  and the go-driver transpile keep IDENTICAL mtimes — only the edited file
  re-transpiles, lib2xats2go reconcats, and the bundle relinks.
- **`lib2xatsopt.js` (171 MB) never touched** — no target rebuilds it; `cleanall`
  removes the namespaced caches/shims but NEVER the prebuilt source.

## clean / cleanall split

- **`clean`** removes emitter artifacts (`GOPATCHED`, `JSPATCHED`, lib2xats2go,
  suite stamps/logs) but KEEPS the cached FIXED artifacts (opt.js1, cc.js2, the
  shims, the opt-names extract) — a post-`clean` rebuild re-transpiles only the
  emitter and reuses the ~10 s of cached sed.
- **`cleanall`** additionally removes opt.js1 / cc.js2 / both shims / opt-names /
  the cc·js cached copies — but NEVER `lib2xatsopt.js`.

## Real-vs-stub

Everything here is REAL (cached make targets + measured timings + md5 proofs); no
stubs. Deviation from the brief: the shim's helper names live in TWO fixed libs
(not just lib2xats2cc as the brief assumed) — `d2var_get_stmp`/`stamp_get_uint`
are in opt — so the cached shim scans cc.js2 + a tiny once-grepped opt-names
extract rather than cc alone. Output is byte-identical regardless. The legacy
`build-go.sh`/`run-suite.sh` are untouched (separate `BUILD/DATS__*` namespace)
and still work as the reference oracle path.

---

# M2.4 — Tail-call optimization (TCO): tail self-call -> for{...continue} loop

Status after **M2.4**: a TAIL-recursive self-call emits as a Go `for { ...
goxtnm<param>=newval; continue }` loop (O(1) stack) instead of a recursive
call; non-tail recursion stays a plain Go recursive call. A DEEP tail loop
(50_000_000 iters) runs instantly without stack-overflow. `make -j psuite` =
18/18 GREEN, byte-equal-vs-JS. All additive under `srcgen2/xats2go/`.

## How to run (M2.4)

```bash
cd srcgen2/xats2go
make -j psuite                       # 18 GREEN (16 prior + 2 TCO)
make run/test18_tail_loop_xats2go    # HEADLINE deep loop (sum 1..50M, no overflow)
make run/test19_tail_acc_xats2go     # tail accumulator (fac(10)=3628800)
```

## THE IR signal a TAIL self-call keys on (vs non-tail factorial)

Dump IR via the emitter's stderr (`node bundle <src> 2>dump`). For
`fun fac(n,acc) = if n<=0 then acc else fac(n-1, acc*n)` the ELSE branch is
`I1INSrturn(I0CALfun(fac;[fac]), inner)` where `inner` is
```
I1CMPcons(
  [ I1LETnew1(T17, I1INStimp(sint_sub$sint)),  I1LETnew1(T18, dapp(T17,[n,1]))   // n-1
  , I1LETnew1(T25, I1INStimp(sint_mul$sint)),  I1LETnew1(T26, dapp(T25,[acc,n])) // acc*n
  , I1LETnew1(T27, I1INSdapp(I1Vfenv(fac;[]), [T18, T26])) ]  // the SELF-call
; I1Vtnm(T27))                                               // result = T27
```
`i1cmp_tailq(inner, ical)` is TRUE because the LAST let binds the cmp result
(`I1Vtnm(T27)`) via a dapp whose callee `I1Vfenv(fac)` is the self d2var
(`d2var_tailq(fac, I0CALfun(fac;[fac]))`). The THEN branch
`I1INSrturn(ical, I1CMPcons([], I1Vtnm(acc)))` is NOT tail (no last-let dapp)
-> plain `return acc`. The NON-tail factorial (`n*fact(n-1)`) lowers with the
self-call dapp BOUND to a temp that is then MULTIPLIED -> the cmp result is the
multiply temp, not the call temp, so `i1cmp_tailq` is FALSE -> a plain Go
recursive call (no `for`). This is the exact `i1cmp_tailq`/`I0CALfun` signal we
keyed on (impl: `intrep1_utils0.dats:407`).

## Emitted Go (the shapes)

```go
// TAIL (test19): for{...continue} loop, NOT a recursive call
func fac_757(goxtnm1 int, goxtnm2 int) int {
	for {
		goxtnm10 := (goxtnm1 <= 0)
		if goxtnm10 { return goxtnm2 } else {
			goxtnm18 := (goxtnm1 - 1)      // pre-compute new args into temps
			goxtnm26 := (goxtnm2 * goxtnm1) //   (reads OLD params)
			goxtnm1 = goxtnm18              // THEN reassign params
			goxtnm2 = goxtnm26
			continue
		}
	}
}
// NON-TAIL (test14): plain Go recursive call, NO for-loop (no regression)
func fact_590(goxtnm1 int) int {
	goxtnm9 := (goxtnm1 <= 0)
	if goxtnm9 { return 1 } else {
		goxtnm24 := (goxtnm1 - 1)
		goxtnm25 := fact_590(goxtnm24)   // real recursive call
		goxtnm26 := (goxtnm1 * goxtnm25)
		return goxtnm26
	}
}
```
A case-bodied tail fn emits `for { switch { case ...: return ...; case true:
...; goxtnm<p>=...; continue; default: panic(...) } }` (verified via a probe).

## SIMULTANEITY HAZARD — handled by the IR's ANF (no spill needed)

`loop(i-1, acc+i)` must NOT become `i=i-1; acc=acc+i` (the 2nd line would read
the already-decremented i). The IR PRE-COMPUTES each new arg into its OWN temp
(`T18=i-1`, `T26=acc+i`) via lets that PRECEDE the self-call dapp, and those
temps reference the OLD params. So `rturn_tail_args` returns BOTH the preceding
lets (emitted FIRST: `goxtnm18 := (goxtnm1-1)` etc.) and the call args
(`[T18,T26]`), and the param reassignment uses those temps -- safe regardless
of order. Verified in every emitted TCO function (the `goxtnm<p>=goxtnm<temp>`
lines always follow the pre-compute lines). No spill is ever needed because the
args are always pre-bound temps; if a future IR ever inlined an arg expression
referencing a param, the pre-bind invariant would be the place to re-check.

## Where the hook lives (minimal, local)

- `go1emit_styp0.dats` (pure logic, M2.4 block): `i1cmp_body_has_tailcall`
  (does a body cmp contain a reachable tail self-call -- walks the
  return-position structure: top rturn / if-branch rturn / case-clause rturn);
  `rturn_tail_args` (split a tail rturn's inner cmp into (preceding-lets, args));
  `params_of_fjarglst` (the function's param i1tnms in order).
- `i1fundcl_go1emit` (`go1emit_decl00.dats`): if `i1cmp_body_has_tailcall`,
  wrap the body in `for { ... }` and thread the param tnms; else plain return
  mode with `params=list_nil()` (no loop). Go treats a `for {}` whose paths all
  `return`/`continue` as terminating -> no "missing return".
- `i1cmp_go1emit_ret` now takes `params: i1tnmlst`. When the unwrapped
  `I1INSrturn` is a tail self-call AND params is non-empty: emit
  `emit_param_reassign` + `continue`; else `emit_ret_plain` (the M2.3 return).
  `params` is threaded down the WHOLE return-position chain
  (`emit_ret_plain` -> `i1letlst_go1emit_p`/`i1let_go1emit_p` ->
  `i1ins_go1emit_block` -> `f0_branch`/`i1clslst_go1emit_g` -> `i1cmp_go1emit_ret`)
  so a tail call nested in a trailing if/case branch also becomes a loop
  continue. EMPTY params = TCO off (M2.3 behavior preserved exactly: value-
  position `i1cmp_go1emit_tnm` is untouched). The `_p` workers + `emit_ret_plain`
  + `emit_param_reassign` are DECLARED in `go1emit.sats` so the plain variants'
  forward references to them resolve (top-level plain-`fun` forward refs do NOT
  resolve here -- the transpiler errored until they were SATS-declared #implfun).

## I1INSfix0 status — DEFERRED to M2.5 (closures), with reason

Every tail-recursive test routes through `I1Dfundclst` (package-level fn group);
the IR dumps show **0 `I1INSfix0` nodes** in test14/test18/test19. `I1INSfix0`
is a LOCAL named recursive function value (a `fun`/`fix` bound inside a body,
needing self-reference + capture) -- it only arises for local recursive
CLOSURES, which is M2.5. `i1insgo1` now has an explicit `I1INSfix0` case that
emits `/* UNHANDLED: I1INSfix0(local-rec-closure -> M2.5) */ nil` + a stderr
NOTE (never silently-wrong Go). So M2.4's package-level TCO is complete; M2.5
must add `var f F; f = func(...){... f(...) ...}` self-reference for I1INSfix0.

## Honest coverage / real-vs-stub (M2.4)

- **REAL (oracle-validated):** tail self-call detection (`i1cmp_tailq` +
  `I0CALfun`/`I0CALfix`); `for { ... param=newval; continue }` loop emission for
  if-bodied AND case-bodied tail recursion; simultaneity-safe param reassignment
  (IR pre-binds args into temps -- verified, no spill); non-tail recursion stays
  a plain Go recursive call (test14 factorial, no regression). test18 deep loop
  (50M iters) does NOT overflow; a standalone non-TCO recursive Go version at the
  SAME depth crashes (`goroutine stack exceeds 1000000000-byte limit`) -- proving
  the loop was really emitted. 18/18 byte-equal-vs-JS, gofmt-clean, go vet OK.
- **DEFERRED (reported, not silently wrong):** `I1INSfix0` (local recursive
  closures) -> M2.5; mutually-recursive tail calls across DIFFERENT functions
  (`I0CALfun(self, mutuals)` carries the mutual set, but a tail call to a
  DIFFERENT fn is not a self-loop -- it stays a plain Go call, which is correct
  but not loop-optimized); a tail call in a let-in TAIL position (let-in is
  emitted value-mode; rare, untested) -> would stay a plain return. Closures
  (`I1Vfenv` with capture), datatypes, exceptions, lazy remain for M2.5-M2.8.

---

# M2.5 — Closures (BUG-1 fix): lambda return-type recovery for captures + nested lambdas

Status after **M2.5 BUG-1 fix**: a lambda whose body result is NOT a native-op
scalar -- it RETURNS a captured/param variable (`lam u => a`) or RETURNS another
lambda (curried `lam b => lam c => ...`) -- now emits with a CONCRETE Go return
type (`func(int) int`, `func(int) func(int) int`, ...) instead of `any`. The
prior `any` collided with the enclosing function's correct concrete signature
(`func(int) func(int) int` etc.), so `go vet`/`go build` FAILED. `make -j
psuite` = **30/30 GREEN, gofmt-clean, `go vet` OK on every emitted program**.
All additive under `srcgen2/xats2go/`. The capture LOWERING (`trxi0i1_myenv0`)
was already correct; this fix is purely the EMITTER's return-type recovery.

## How to run (M2.5)

```bash
cd srcgen2/xats2go
make -j psuite                        # 30 GREEN (22 prior + test30-37)
make run/test35_const_xats2go         # const-fn MWE (any -> func(int) int)
make run/test30_nested_cap_xats2go    # 2-level nested capture (123)
```

## THE BUG (BUG-1, diagnosed by review; reproduced + fixed)

Before the fix, for `test35` (`konst(a) = lam u => a`) the emitter produced:
```go
func konst_214(goxtnm1 int) func(int) int {      // CORRECT (from konst's T2Pfun1 sig)
	goxtnm3 := func(goxtnm2 int) any { return goxtnm1 }   // <-- BUG: `any`
	return goxtnm3                                         // any != func(int) int -> go vet FAIL
}
```
Two ROOT CAUSES, both in `go1emit_styp0.dats`'s return-type recovery
(`gotype_of_lam_ret` -> `gotype_of_cmp` -> `gotype_of_tnm_in_lets` /
`gotype_of_ins_local`), which is a PURE analysis run at the lambda emit site
(`go1emit_dynexp.dats`, the `I1INSlam0`/`I1INSfix0` cases of
`i1ins_go1emit_block`):
1. **No `I1INSlam0`/`I1INSfix0` case in `gotype_of_ins_local`** -> a result temp
   bound to a NESTED lambda (`lam b => lam c => ...`) typed as `any` (test30's
   middle lambda was `func(int) any`).
2. **`gotype_of_cmp`/`gotype_of_tnm_in_lets` could not type a result temp that
   is a FREE parameter/capture** -- a bare `I1Vtnm` NOT bound in the cmp's lets
   (the body of `lam u => a` returns `I1Vtnm(konst's param a)`) -> not found ->
   `any`.

## THE FIX (general; functions changed)

`go1emit_styp0.dats` (the recovery cluster, now a `bnds`-threaded
mutually-recursive `and`-chain + thin no-`bnds` wrappers):
- **`binds_of_fjarglst(fjas)`** (`#implfun`, SATS-declared): the param binds
  (`i1bnd` of each `I1BNDcons` across every `FJARGdarg`) of a lambda/fix --
  parallel to `params_of_fjarglst`/`gotypes_of_fjarglst`.
- **`gotype_of_capture_bnd(stmp, bnds)`**: type a bare result temp that is a
  free param/capture -- match `stmp` against the in-scope param binds [bnds],
  read the matched bind's `I0Pvar(d2var)` -> `d2var_get_styp` ->
  `gotype_of_styp`. THE general rule the task asked for (param/capture via
  `d2var_get_styp`). This is what types `lam u => a`'s body to the captured
  var's declared type (int, float64, ...).
- **`gotype_of_ins_local`** gained **`I1INSlam0`/`I1INSfix0` cases**: a result
  temp that is itself a nested lambda recurses -- `gotypes_of_fjarglst` +
  `gotype_of_lam_ret2(body, bnds ++ own-params)` (for fix0,
  `goargtys_of_funvar`/`goretty_of_funvar` from the fix-var's declared
  signature, exactly as the fix0 emit site) -> `gofunctype_of_fjarglst` = the
  Go `func(<argtys>) <ret>` type. THE nested-lambda-recursion rule.
- The whole recovery chain (`gotype_of_ins_local`, `gotype_of_tnm_in_lets2/_`,
  `gotype_of_cmp2`, `gotype_of_cmpopt2`, `gotype_of_clss2`,
  `gotype_of_ift0type2`, `gotype_of_lam_ret2`) now threads `bnds: i1bndlst` =
  the in-scope param binds (own lambda params + every enclosing function/lambda
  param). `gotype_of_tnm_in_lets2`'s `list_nil` base case (temp NOT in the lets)
  now falls back to `gotype_of_capture_bnd(stmp, bnds)`. The no-`bnds` public
  wrappers (`gotype_of_cmp`, `gotype_of_ift0type`) call the `_2` form with
  `list_nil()` (value-position if/case/let -- no captured params to resolve).

`go1emit.sats` + `go1emit_dynexp.dats` + `go1emit_decl00.dats` (THREADING the
in-scope binds to the lambda emit site -- so each nested lambda's emit knows
its enclosing captures):
- `gotype_of_lam_ret` now takes `(icmp, bnds)`; `binds_of_fjarglst` SATS-declared.
- A new `bnds: i1bndlst` arg is threaded PARALLEL to the existing M2.4
  `params: i1tnmlst` through the return-position emit chain:
  `i1cmp_go1emit_ret` -> `emit_ret_plain` -> `i1letlst_go1emit_p` ->
  `i1let_go1emit_p` -> `i1ins_go1emit_block` (+ the if/case branch helpers
  `f0_branch`, `i1cls_go1emit_g`, `i1clslst_go1emit_g`, and the
  `i1cls_go1emit`/`i1clslst_go1emit` SATS wrappers). `emit_lam_body` carries it
  too. `i1fundcl_go1emit` SEEDS it with `binds_of_fjarglst(fjas)` (the
  function's own params). At each `I1INSlam0`/`I1INSfix0`, the body's binds are
  `binds_of_fjarglst(this-lambda-params) ++ enclosing-bnds`, so a body that
  returns a captured var (from ANY enclosing level) and a NESTED lambda emitted
  inside the body both resolve. (Threaded as an explicit arg, not an `envx2go`
  field, matching the M2.3 `scp` precedent of not touching the linear env vtype.)

The task also mentioned threading the enclosing `T2Pfun1` declared result type
as the lambda's expected return: NOT NEEDED for the surface here -- recovering
from the actual param/capture types (`d2var_get_styp`) + nested-lambda recursion
covers every test concretely, which the task says to PREFER over the threaded
guess. The top-level lambda IS already typed from the enclosing function's
`T2Pfun1` (its outermost `func(...)...` return type comes from
`gotypes_of_funstyp` in `i1fundcl_go1emit`, unchanged from M2.2).

## BEFORE / AFTER (emitted Go)

```go
// test35  BEFORE:  goxtnm3 := func(goxtnm2 int) any { return goxtnm1 }   // go vet FAIL
// test35  AFTER:   goxtnm3 := func(goxtnm2 int) int { return goxtnm1 }   // captured int

// test30 (nested) AFTER:
func f_598(goxtnm1 int) func(int) func(int) int {
	goxtnm21 := func(goxtnm2 int) func(int) int {        // was func(int) any
		goxtnm20 := func(goxtnm3 int) int {
			goxtnm18 := (goxtnm1 + goxtnm2)
			goxtnm19 := (goxtnm18 + goxtnm3)
			return goxtnm19
		}
		return goxtnm20
	}
	return goxtnm21
}
```

## VALIDATION — golden, because the JS oracle is BROKEN for capturing lambdas

The JS backend crashes on `I1INSlam0` capture (`env1 undefined` in the emitted
closure), so a capturing-closure test produces NO JS stdout and CANNOT be
byte-equal-vs-JS. These tests are therefore **GOLDEN-validated**: the golden
(`TEST/OUTS/<name>.expected`) encodes the **HAND-COMPUTED-correct** value, and
the oracle's golden-fallback path (`build-go.sh`/`Makefile _oracle`: when JS
stdout is empty, `cmp` Go stdout vs the golden) gates them. For test30/34/35/36/
37 the procedure was: emit -> `gofmt`/`go vet`/`go build` clean -> RUN the Go ->
confirm the printed value equals the hand-computed truth -> ONLY THEN set the
golden. test31/32 were likewise confirmed correct then wired. test33 (non-
capturing `fix`) is byte-equal-vs-JS (the JS backend handles non-capturing fix).

| test | program | HAND-COMPUTED golden | validation |
|---|---|---|---|
| test30_nested_cap | `f(a)=lam b=>lam c=>a+b+c`; f(100)(20)(3) | `nest=123` | golden (JS broken) |
| test31_shadow | `shdw(n)=lam k=>(lam n=>n+1)(k)+n`; shdw(100)(7) | `shadow=108` | golden (JS broken) |
| test32_multi_clos | `adder(d)=lam x=>x+d`; add5/add10 + mix | `a=105 b=110 mix=15` | golden (JS broken) |
| test33_fix_multi | `fix f(x)=if x>0 then x+f(x-1) else 0`; T(0,1,5,10) | `tri 0 1 15 55` | BYTE-EQUAL-vs-JS |
| test34_cap_timing | `mk(a)=lam u=>a`; k7,k42,k7 (capture-by-value) | `t0=7 t1=42 t2=7` | golden (JS broken) |
| test35_const | `konst(a)=lam u=>a`; konst(9)(0) | `k=9` | golden (JS broken) |
| test36_cap_float | `mkf(a:double)=lam u=>a`; mkf(3.5)(0) [anti-overfit] | `kf=3.5` | golden (JS broken) |
| test37_nest3 | `g(a)=lam b=>lam c=>lam d=>a+b+c+d`; g(1000)(200)(30)(4) [anti-overfit] | `nest3=1234` | golden (JS broken) |

The 2 ANTI-OVERFIT shapes guard the fix's generality: **test36** proves the
captured-var type is recovered from the param's static type (a `double` ->
`func(int) float64`, NOT hard-wired to `int` or `any`); **test37** proves the
nested-lambda recursion works at depth 3 (`func(int) func(int) func(int) int`).

## Wiring

`Makefile` `SUITE_NAMES` and `srcgen2/TEST/run-suite.sh` `DEFAULT_SUITE` both
gained test30-37. `make -j psuite` = 30/30 GREEN. The goldens for the 5
JS-broken capture tests + test36/37 live in `TEST/OUTS/*.expected`; test33's
golden was already present (it also byte-equals JS).

## Honest coverage / real-vs-stub (M2.5 BUG-1)

- **REAL (oracle/golden-validated):** captured-scalar return-type recovery
  (int + float64) via `d2var_get_styp`; nested-lambda return-type recovery
  (depth 2 and 3) via the `gotype_of_ins_local` lam0/fix0 cases; the in-scope
  bind threading (own params + enclosing captures) from `i1fundcl_go1emit` down
  to every lambda emit site; shadowing (inner param shadows outer capture);
  capture-by-value timing; multiple independent closures from one generator;
  local recursive `fix`. 30/30 suite GREEN, gofmt-clean, `go vet` OK on EVERY
  emitted program (the BUG-1 gate).
- **STILL `any` (genuine last-resort fallback, unchanged):** a captured/param
  var whose `d2var_get_styp` is NOT a recognized scalar/fun type (datatypes /
  tuples -> M2.6/M2.7; polymorphic `s2var` pre-monomorphization); a lambda body
  whose result is an opaque computed temp from a non-native producer (the M2.6
  `i1tnm->i0typ` side-table debt). The `// UNHANDLED`/stderr discipline is kept.
  A lambda emitted INSIDE a let-in value-position body still types its return
  with the no-`bnds` `gotype_of_ift0type` wrapper (rare; not in the M2.5 surface)
  -- the captured-var recovery there would need `bnds` threaded through the
  let0 value-mode path too (a small follow-up; no current test needs it).
- **Untouched (per the brief):** `trxi0i1_myenv0.dats` (capture lowering -- it
  is correct) and the JS backend.
