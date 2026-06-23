# xats2go — Go backend for ATS3 — Architecture & Roadmap

Status: **M2/M3 IN PROGRESS** — M2.0–M2.7 ✅; M2.8 underway (exceptions green; non-linear lazy stream forcing green; linear `list_vt` datacon-field mutation green); first M3 user-template body rung ✅; xats2js-style top-level `prints` auto-flush ✅ · M0/M1 done · Go 1.26.4. **suite = 74/74 GREEN.**
Self-hosting probe → full categorized gap inventory (see §"Gap tracker"); P1 string-literal `case`
patterns ✅ (keystone: `goop_of_name` 107 dead-`false` markers → 0) + P2 native generic-int `gint_*$sint$sint`
ops ✅ + B1 string prims (`strn_eq` native / `strn_get_at`, test92) ✅ + B2 `gs_print_n*` ✅ landed
→ **go1emit_utils0 undefined runtime symbols 10 → 1** (lone remainder `strn_foritm` = M3 template item).
**M5 Phase-1 (frontend shim bridge) ✅**: an `any`-typed shim resolves ALL 16 Class-C frontend accessors;
`go1emit_strn_contains` extracted VERBATIM from emitted Go RUNS correct under a Go test (10 cases) — first
end-to-end proof emitted backend logic executes. Harness: `tools/selfhost-run-probe.sh`.
**Native-op soundness fix ✅ (test93)**: a native ordered/arith op on an `any`-returning prelude scalar-query
result (`strn_length(s) >= n`) emitted illegal `int >= any`. Root cause: `Xats_strn_length` was the LONE
runtime that returned `any` for a scalar-QUERY fn (sint_abs/list_length/gseq_folditm all return concrete `int`,
which the emitter relies on). Fixed by making `strn_length` return `int` (convention now documented in xatsgo.go).
DEFERRED (real, rarer): native ordered op on a genuinely-polymorphic `any` (user fn returning a type-var) would
need a `bnds`-threaded emitter assertion — the `scp`-only discriminator is UNSOUND (would assert `sint_abs`'s
concrete int → `int.(int)`, regressing test84). Needs a `.sats` change + `make clean`; not yet required.
Deep blocker remaining = Class C cross-module frontend accessors (shimmable; M5 Phase-2 = stable `xatsfront.`
routing to scale across files, then ultimately EMIT the frontend type layer for true fixpoint).
M2.7 notes: datatypes → a single boxed runtime type `*xatsgo.XatsCon{Tag int; Args []any}` (mirrors the JS tag+array model; nails the LAYOUT = boxed pointer with ZERO per-datatype type-decl infra). Construction `&XatsCon{Tag: ctag, Args: []any{..}}` (`d2con_get_ctag`); matching `v.Tag == ctag` in the `switch{}`; projection `v.Args[i].(<fieldGoType>)` — TYPED assertions recovered from `d2con` field types (`d2con_get_styp`→drop proof prefix→field s2typ; datatype fields → `*xatsgo.XatsCon` for recursion; polymorphic field → `any`, faithful). Headline: recursive list-sum/tree work, byte-equal-vs-JS. **DEFERRED → M2.7b/M3: per-datatype TYPED structs** (`Args` stays `[]any`; interface+ctor-structs or typed tagged struct is the idiomatic refinement) + polymorphic-payload concretization. KEY FIXES found: (1) **datacon GUARDS rewrote** to an inline short-circuited IIFE `case v.Tag==ctag && func()bool{..proj..}():` — M2.3's design pre-ran guard projections unconditionally → panic on a non-matching ctor; adversarially validated (test64: guard clause FIRST, nil flows through safely via `&&`). (2) **`go1emit_tytab0.dats` was missing from `build-go.sh`'s GO_DATS** (legacy path only — the Makefile had it, so `make psuite` milestones were genuinely green); fixed. (3) datacon sub-pattern vars don't bind a temp — accessed via `I1Vp1cn(pat, root, pind)` projections (pind = post-proof-drop value index). (4) `I1Vlpcn` datacon-field mutation is now proven by **test85_list_vt_mut_xats2go** (`list_vt_cons(!x1,xs)` then `x1 := x1 + 1`).
M2.6c notes: lvalues/assignment via DIRECT addressable Go (`p.F0 = v`) — NO path-simulation runtime (Go has real lvalues, cleaner than the JS backend's `XATSLP*`/`lvget`/`lvset`/copy-on-write). KEY semantic finding: an ATS `var` is itself a mutable cell, so the frontend BOXES every var-stored tuple (`I1Vlpbx`, emitted `*struct`) regardless of flat/boxed — mutation is correctly shared, byte-equal-vs-JS (test51: boxed-alias mutation `104/141`). So M2.6b's VALUE structs are for immutable `val`-bound tuples (never mutated → value semantics fine); var-bound → pointer (mutable cell). Self-consistent; oracle-validated. Datacon lvalues (`I1Vlpcn`) are now green for linear list_vt mutation (test85). Also fixed: a multi-let return-body (effect lets + trailing `I1INSrturn`) now routes to return-mode. The build's IR-DUMP debug (`i1parsed_fprint`) was disabled — it crashes on lvalue nodes (the build-local `i1val_fprint` lacks lval cases + is errck'd-to-comment in the prebuilt bundle, same defect class as i0varfst/tokenfpr); `intrep1_print0.dats` kept pristine.
M2.6b notes: KEY IR fact — even a flat `@(..)` lowers to `I1INStup1`/`I1INSrcd2` with a FLAT-kind token; flat-vs-boxed = `trcdknd_fltq(token)` (and the recorded `i0typ` = `I0Tnone1(T2Ptrcd(TRCDflt0/box1,...))`), NOT the tup0/tup1 ctor. Uses ANONYMOUS Go structs (structural typing → no named-type decls/dedup); construction (`<struct>{..}` flat / `&<struct>{..}` boxed), projection (`.F<lab>`), nested, and tuple-typed fn params/results all driven by ONE translator so all sites' struct types agree (Go build = the consistency oracle). **Adversarially reviewed (mine):** non-int (float64) fields + mixed flat-of-boxed nesting (`struct{F0 *struct{...}; F1 int}`) both correct. NOTE: harness now runs `gofmt -w` on output (gofmt always multi-lines inline struct types; cosmetic). Caveat: for READ-only tuples value-vs-pointer gives identical output, so flat/boxed correctness is verified by EMITTED CODE, not the oracle (mutation semantics gated at M2.6c).
M2.6a notes: side-table built at the `i0exp_trxi0i1` chokepoint (record `iexp.ityp()` under the result temp's stamp; conservative — record only freshly-minted `I1Vtnm`, nothing otherwise); `gotype_of_i0typ` translates → Go (scalars+arrows concrete; aggregates/datatypes still `any` → M2.6b/M2.7); consulted as a BACKSTOP only when local recovery gives `any` (can only ADD concreteness). **Adversarial review (mine, reviewer agent rate-limited) PASSED**: validated correct types on float/char/if-value-float/mixed-chain/**function-value (`func(int)int`)** backstops; design sound (last-write-wins always consistent). Review also caught + FIXED a separate **let0-return-mode unreachable-code** bug (general extension of `i1ins_fully_returnsq`/`i1cmp_tail_returns` into `I1INSlet0`). **FOLLOW-UP DONE:** type annotation `(e:T)` now erases to the inner runtime value (test75).
M2.5 notes: capture relies on Go lexical capture (NO closure conversion) via a sound divergence in our copy of `trxi0i1_myenv0.dats` (captured var → outer Go local, not `I1Venv` env-slot). **Adversarial review caught a compile-breaking lambda-return-type-`any` bug** (all 4 initial closure tests dodged it); fixed generally (param/capture type via `d2var_get_styp`, nested-lambda recursion). **Capturing-closure tests are golden-validated (hand-computed), NOT byte-equal-vs-JS — the JS backend itself is broken for `I1INSlam0` capture (`env1` undefined).** TODO: fixing the JS backend's closure conversion would restore the differential oracle for capture (currently the one class without it).
History: v1 arch → decisions (layout-aware; emitter in ATS3) → M0 → Go installed → M1 (byte-equal-vs-JS) → M2.0 (harness+liveness+type findings) → M2.1 (scalars/primops, native Go ops) → M2.2 (functions; 10 tests green) → Makefile separate-compilation build (cold `make -j` ~24s, incremental ~15s, byte-identical lib) → M2.3 next.
Build (OPTIMIZED): `make` (incremental relink **~1.7s**) · `make run/NAME` (**~3s**) · `make suite` (47s historical) · `make -j 8 psuite` (**71/71 GREEN**). Cached sed-namespaced fixed libs (opt.js1/cc.js2/shim) + JS-oracle bundle built once + `NODE_COMPILE_CACHE`; emitter bundle md5-identical to pre-opt (output provably unchanged). Legacy `build-go.sh`/`run-suite.sh` still work.
Owner/architect: (you) — implementation delegated to subagents.
Reference backend: `srcgen2/xats2js/srcgen2` (the IR-based JS emitter with TCO).

---

## 1. Goal & scope

Build `xats2go`: a compiler backend that translates ATS3 to **idiomatic, efficient Go**,
mirroring the structure of `xats2js`. The differentiator vs JS/Python: **exploit the
boxed/unboxed data-layout metadata** already present in the IR to emit value types where
possible (Go structs/arrays on the stack) instead of uniformly heap-boxing everything.

Like every ATS3 backend, the **emitter itself is written in ATS3** (self-hosted), compiled
to JS by the bootstrap `srcgen1/xats2js` compiler, and run on Node to emit `.go` files.
We are **not** writing the emitter in Go. (Decision: §4.)

---

## 2. The pipeline (what we reuse vs. what we build)

```
source.dats/.sats
  │   shared xatsopt frontend  (parse + typecheck; srcgen2/SATS, srcgen2/DATS)
  ▼
d3parsed              (D3 = fully typechecked dynamic exprs, carry s2exp/s2typ)
  │   trxd3i0   (D3 → intrep0; lives in xats2cc/srcgen1)  ← FLAT/BOXED decided HERE
  ▼
i0parsed  (intrep0)   layout already materialized: I0Etup0 vs I0Etup1, I0Epflt vs I0Eproj
  │   trxi0i1   (intrep0 → intrep1; currently under xats2js, backend-AGNOSTIC)
  ▼
i1parsed  (intrep1)   ANF/SSA-ish, TCO-ready, layout fully explicit
  │   *** js1emit  (intrep1 → JS text) ***  ← THE ONLY backend-specific stage
  ▼
.js  +  hand-written JS runtime  →  node
```

**Reusable verbatim (backend-agnostic):**
- `intrep1.sats` + `intrep1.dats` + `intrep1_utils0.dats` + `intrep1_print0.dats` (the IR).
- `trxi0i1.sats` + `trxi0i1.dats` + `trxi0i1_myenv0.dats` + `trxi0i1_dynexp.dats` + `trxi0i1_decl00.dats` (intrep0→intrep1 lowering, **including tail-call detection**).
- The entire xatsopt frontend + `trxd3i0` + intrep0 (already shared with xats2cc/xats2js).

**Backend-specific (we write, replacing the `js1emit`/`xats2js` files):**
- `go1emit.{sats,dats}` + `go1emit_{dynexp,decl00,utils0}.dats` — intrep1 → Go text.
- `xats2go.{sats,dats}` + `xats2go_{myenv0,utils0,tmplib,dynexp,decl00}.dats` — driver/env/orchestration.
- `UTIL/xats2go_goemit01.dats` — CLI entry (mirrors `xats2js_jsemit01.dats`).
- A hand-written **Go runtime package** (replaces `srcgen2_prelude.js` + `srcgen2_precats.js` + `srcgen2_xatslib.js` + `xats2js_js1emit.js`).
- Makefiles (mirror `Makefile_xjsemit` at each level).

---

## 3. The central insight: layout metadata Go can exploit

The flat-vs-boxed decision is made **upstream** (trans12/23 → `trxd3i0`) via the record-kind
`trcdknd` and the predicate `d3exp_trcdfltq`, and is **materialized as distinct IR
constructors**. The JS backend then **throws this away** (everything becomes a JS array;
`XATSTUP0([...])` and `XATSTUP1(knd,[...])` are both arrays). **Go does not have to.**

`trcdknd` (`srcgen2/SATS/xbasics.sats:320`):
`TRCDflt0` (flat/unboxed) · `TRCDbox0` (boxed nonlinear) · `TRCDbox1` (boxed linear) ·
`TRCDbox2` (refcounted nonlinear) · `TRCDbox3` (refcounted linear). Predicate `trcdknd_fltq`.

### Layout → Go mapping (the design target)

| ATS / IR signal | IR node | Go (Phase 2, uniform) | Go (Phase 3+, idiomatic) |
|---|---|---|---|
| flat tuple `@(a,b)` | `I1INStup0(vs)` | `[]any{...}` | value struct `struct{F0 T0;F1 T1}` (stack) |
| boxed tuple `'(a,b)` | `I1INStup1(knd,vs)` | `[]any{...}` | `*struct{...}` (heap pointer) |
| flat record `@{..}` | `I1INSrcd2(knd,..)` flat | `map`/slice | value struct, named fields |
| boxed record `'{..}` | `I1INSrcd2(knd,..)` box | slice | `*struct{...}` |
| flat projection | `I1INSpflt(lab,v)` | `v[lab]` | `v.Flab` (value field) |
| boxed projection | `I1INSproj(lab,v)` | `v[lab]` | `v.Flab` (through ptr) |
| constructor proj | `I1INSpcon(lab,v)` | `v.Args[lab]` | typed field after tag/type switch |
| datacon `C(a,b)` | `I1INSdapp(I1Vcon,vs)` | `&Con{Tag,Args:[]any}` | typed `&C{F0,F1}` (tag `ctag`) |
| flat lval | `I1Vlpft(lab,v)` | path-encoded | addressable value field |
| boxed lval | `I1Vlpbx(lab,v)` | path-encoded | pointer field |
| consed lval | `I1Vlpcn(lab,v)` | path-encoded | datacon field (in-place set) |

Metadata sources for the emitter:
- `d2con` getters (`srcgen2/SATS/dynexp2.sats`): `ctag` (`d2con_get_ctag`), `narg`
  (`d2con_get_narg`, value arity), `nprg` (`d2con_get_nprg`, proof arity — **erased**),
  `styp` (`d2con_get_styp` → parent datatype, carries `trcdknd`).
- The `token` payload on `I1INStup1`/`I1INSrcd2` encodes the `trcdknd`.
- Static types `s2typ`/`s2exp` reachable from D3/intrep0 nodes for type reconstruction.

---

## 4. Strategy: *correct-first, idiomatic-incrementally*

Go's hard constraint vs JS/Python: **static typing** + **no unused vars/imports** +
**statement-oriented**. The ANF shape of intrep1 (each `i1let` is a statement; if/case
assign to a pre-declared temp) maps cleanly onto Go statements, which de-risks a lot.

Two representation regimes; we sequence them:

- **Regime A (uniform `any`):** every temp is `any` (interface{}); tuples are `[]any`;
  datacons are `&Con{Tag int; Args []any}`; primops via runtime calls. This is essentially
  a dynamically-typed runtime in Go — **mirrors JS closely, compiles & runs, gets the whole
  toolchain green fast.** Pay boxing/assertion cost; not idiomatic.
- **Regime B (layout/type-aware):** use `trcdknd` + `s2typ` to emit value structs vs
  pointers, concrete scalar types (`int`/`float64`/`rune`/`string`/`bool`), typed datatype
  structs, and monomorphized/generic functions. **This is the "efficient idiomatic Go" goal.**

**DECISION (chosen): layout-aware from the start.** Regime B is built *with* the first real
programs, not deferred. M0 (scaffolding) is regime-independent and proceeds as-is; from M2
onward we stand up the `s2typ → Go type` + `trcdknd` layout layer so emitted data is
value-typed (flat → value struct, boxed → pointer, datatype → typed tagged struct) from the
outset, and scalars get concrete Go types wherever the static type is known. Regime A
(`any`-typed) survives only as a **local fallback** for constructs whose static type isn't yet
recoverable — never as a whole-program phase. The differential-vs-JS harness still gates every
step, so "working at all times" is preserved via the test suite rather than via a uniform-boxing
phase.

**Decision — emitter language:** ATS3, self-hosted, exactly like `js1emit`. Writing it in Go
would break self-hosting and force a second intrep1 reader. Not viable.

---

## 5. Go-specific lowering concerns (bake into the emitter from day one)

1. **Unused vars/imports are compile errors.** Strategy: after each binding emit a usage
   suppressor, or run a liveness pass. Pragmatic default: emit `_ = _tnmN` for temps not
   otherwise consumed, and centralize imports through the runtime package so user code needs
   few/no direct imports. Revisit with a real liveness pass in Phase 3.
2. **Case/switch.** JS uses `do{…}while(false)`+`break`. Go: emit an **expression-less
   `switch { case cond1: …; case cond2: … }`** (implicit break = exactly an if-else chain),
   or labeled block. No `do/while` in Go.
3. **Recursive functions (`I1INSfix0`).** Go func literals can't self-reference via `:=`.
   Emit `var f F; f = func(...){ … f(...) … }`.
4. **TCO.** Reuse `trxi0i1`'s tail detection (`i1cmp_tailq`/`i1val_tailq` + `i0cal`). Emit
   `for { … arg0 = v0; arg1 = v1; continue }` — same shape as the JS `while(true)` loop.
5. **Exceptions.** `I1INSraise` → `panic(x)`; `I1INStry0` → `func() (…){ defer recover()… }()`
   or an explicit recover wrapper. Map the `$TRY` machinery onto panic/recover.
6. **Scalars.** sint→`int`, bool→`bool`, char→`rune` (or byte), float→`float64`,
   string→`string`. (Go is *more* correct than JS here — no float64 ints.)
7. **Closures.** Go has func literals capturing by reference; **no closure conversion**
   (same family as JS/Python). `I1Vfenv`/`I1INSlam0` → Go func literal. (Go ≥1.22
   per-iteration loop var semantics assumed.)
8. **Package & formatting.** Emit `package main` (or per-module packages later) + managed
   imports. Run `gofmt` on output as a convenience (Go is whitespace-insensitive, so not
   required for correctness, but good for diffing/review).
9. **Naming/mangling.** Mirror JS: `<symbol>_<stamp>` with symbol-char escaping; temps
   `goxtnmNNNNN`. Ensure results are valid Go identifiers (Go export rules: capitalization
   controls visibility — keep everything in one package initially so case doesn't matter).
10. **nil/none, equality, division/mod semantics** — define precisely in the runtime; match
    ATS semantics (and cross-check against JS backend output).

---

## 6. Directory layout to create (mirror xats2js)

```
srcgen2/xats2go/srcgen2/
  SATS/  intrep1.sats trxi0i1.sats          (copy)
         xats2go.sats go1emit.sats          (new)
  DATS/  intrep1.dats intrep1_utils0.dats intrep1_print0.dats   (copy)
         trxi0i1.dats trxi0i1_myenv0.dats trxi0i1_dynexp.dats trxi0i1_decl00.dats (copy)
         xats2go.dats xats2go_myenv0.dats xats2go_utils0.dats
         xats2go_tmplib.dats xats2go_dynexp.dats xats2go_decl00.dats   (new)
         go1emit.dats go1emit_utils0.dats go1emit_dynexp.dats go1emit_decl00.dats (new)
  HATS/  libxatsopt.hats mytmplib00.hats    (copy/adapt)
  UTIL/  xats2go_goemit01.dats Makefile_xgoemit   (new)
  TEST/  test0{0..N}_xats2go.dats Makefile_goemit01 OUTS/   (new)
  BUILD/GO/   lib/   (output dirs)
  Makefile_xgoemit
srcgen1/xshared/runtime/   (new Go runtime; analog of srcgen2_*.js)
  xatsgo_runtime.go  xatsgo_prelude.go  xatsgo_precats.go  xatsgo_node.go
```

Build/bootstrap mirrors `Makefile_xjsemit`: srcgen1/xats2js compiles each new `.dats` to JS;
concat runtime-JS + lib2xatsopt (`go1` prefix) + lib2xats2cc (`go2`) + lib2xats2go (`go3`) +
entry; run on node with `--stack-size`. **The emitter runs on node and writes `.go`.** The
*compiled user program* is `.go` + Go runtime package, built with `go build`.

---

## 6a. Build reality (supersedes the stale Makefiles)

The `xats2js/.../Makefile_xjsemit` toolchain paths (`xats2js_jsemit00_ats2.js`,
`xatsopt_tcheck00_ats2.js`, the `lib/` libs) **do not exist in this checkout**. The live,
working build is the `frontend/build-m*.sh` script family. The canonical template for wiring a
backend onto the frontend spine is **`frontend/build-m0b.sh`**. Concrete facts:
- **Transpiler (jsemit00):** `xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js` (run on
  `node --stack-size=8801`). This is the ATS3→JS transpiler `lib2xatsopt.js` was built with.
- **`lib2xatsopt.js`** (171 MB, the whole frontend) is prebuilt at `srcgen2/lib/lib2xatsopt.js`
  — **never rebuild** (6–9 min; use `language-server/server/build-lib2xatsopt.sh` only if absent).
- **`lib2xats2cc.js`** (intrep0 + trxd3i0 + tryd3i0 + intrep1) is prebuilt today at
  `frontend/BUILD/lib2xats2cc.js` — **reuse it** (identical source set; it provides intrep0 etc.).
- **`build_backend_lib` recipe:** transpile each `.dats` via jsemit00, then per-file
  `sed s/jsxtnm/jsx<NNN>tnm/` with NNN starting at **100** (3-digit, required so the link-time
  `jsx(...)tnm` regex matches), concat in dependency order.
- **Link order:** `runtime` then `sed 's/jsx(...)tnm/js1\1tnm/' lib2xatsopt` then `js2·lib2xats2cc`
  then `js3·lib2xats2go` then `.cats` glue then driver. Run bundle → it prints emitted target code
  between sentinels → extract → (for output programs) prepend runtime + run.
- **Runtime list (for running the *emitter*, which is JS):** `xats2js_js1emit.js`,
  `srcgen2_precats.js` (under `srcgen2/xats2js/srcgenx/xshared/runtime`), `srcgen1_prelude.js`,
  `srcgen1_prelude_node.js`, `srcgen1_xatslib_node.js` (under `srcgen1/.../runtime`).
- **`go` is NOT installed** in this environment. M0 emits a `.go` file but cannot `go build` it
  yet; installing Go (`brew install go`) is a prerequisite for M1 validation. Until then,
  validation is by inspection + (later) the differential harness once Go is available.

xats2go reuses this verbatim, swapping `lib2xats2js` → `lib2xats2go` (built from
`xats2go/srcgen2/DATS`: copied intrep1 + trxi0i1 + new xats2go + go1emit) and the driver's final
call `i1parsed_js1emit` → `i1parsed_go1emit`. Build is driven by `srcgen2/xats2go/build-go-m*.sh`
scripts mirroring `frontend/build-m*.sh` (not the Makefiles).

## 7. Milestone roadmap

Each milestone: a delegated implementation chunk + reviewer pass + integration. Exit criteria
are **executable** (something compiles/runs/diffs-clean), never "looks done".

- **M0 — Scaffolding & green pipeline. ✅ DONE (verified).** Dir tree created; intrep1 +
  trxi0i1 copied verbatim (staloads resolve at the same depth); minimal `envx2go` +
  stub `i1parsed_go1emit` (consumes the real `i1parsed`, emits `package main`/`func main`
  between `//==XATS2GO-BEGIN/END==` sentinels); driver `UTIL/xats2go_goemit01.dats` mirrors
  `xats2js_jsemit01.dats`; build via **`srcgen2/xats2go/build-go-m0.sh`** (adapted from
  `frontend/build-m0b.sh`); runbook in `srcgen2/xats2go/BUILD-NOTES.md`. **Verified:** build
  reproducibly green (node exit 0; pipeline ran: `stadyn=1, nerror=0`), additive-only, stub is
  honest. **Carry-over:** `go` not installed (gates M1 `go build`/differential); driver still
  passes `--_XATS2JS_` frontend flags (fine — backend-agnostic spine; revisit if a `--_XATS2GO_`
  flag is ever needed).

- **M1 — Walking skeleton ("Hello World"). ✅ DONE (verified).** `go1emit` REAL emission:
  it walks `i1dclistopt → i1dclist → i1dcl → I1Dvaldclst → i1valdcl → i1cmp → i1let →
  i1ins → i1val` for `srcgen2/TEST/test01_xats2go.dats`
  (`val () = strn_print("…\n")` + `val () = the_print_store_log()`), emitting real Go.
  Minimal `xatsgo` Go runtime (`runtime/xatsgo/`: print store + `Xats_strn_print` +
  `Xats_the_print_store_log` + `XATSSTRN/XATSSTR0/XATSNIL`) reproduces the JS runtime's
  observable bytes. Harness `build-go-m1.sh`: emits `test01.go`, assembles a scratch Go
  module (`replace xatsgo => runtime/xatsgo`), `go vet`+`go build`+run, AND builds the JS
  backend (`lib2xats2js.js`) to run the SAME source. **Exit MET:** `go build`+`go vet`
  pass, program exits 0, and its stdout is **byte-equal to the JS backend's**
  (`Hello from [test01_xats2go]!\n\n`) — the real differential oracle. gofmt-clean.
  - **Decision (M1):** the timp (`I1INStimp`) is resolved to a NAMED `xatsgo` runtime fn
    via its real `t1imp_dcst$get` (not inlined like the JS backend). The dcst comes from
    the pipeline, so this is a real prelude call, not an FFI shortcut. M2 generalizes to
    faithful timp inlining once functions land.
  - **CARRY-OVER / blocker for M2 (important):** the prebuilt `lib2xats2cc.js` REFERENCES
    but never DEFINES 6 `i0varfst_*` funset helpers (`mknil/mklst/addvar/addlst/listize/
    strmize`), which `trxd3i0` calls for the free-var set of ANY function decl — so any
    program with a function (incl. the prelude) `ReferenceError`s. (test00 escaped because
    it has no functions.) M1 works around it with a generated JS shim
    (`runtime/jsshim/gen-i0varfst-shim.sh`, prepended to the bundle); **M2 should fix this
    at the source** — rebuild `lib2xats2cc.js` once the avltree funset/funmap library
    transpiles, or staload a JS impl. See BUILD-NOTES.md "CRITICAL gotcha".

- **M2 — Core constructs, layout-aware (Regime B from the start).** Build the
  `s2typ → Go type` translation layer + the `trcdknd`/`d2con` layout layer up front, then emit:
  functions/calls, let/if/case(switch), primops, recursion + TCO loops, closures; and
  **value-typed data** — flat tuples → value structs/arrays, boxed → pointers, records → typed
  structs, datatypes → typed tagged structs (`ctag`/`narg`), projections → field access, lvalues
  → addressable fields/pointers; exceptions (panic/recover); lazy thunks. Scalars get concrete Go
  types where the static type is known; `any` is a *local* fallback only. Includes a liveness pass
  to drop unused temps. **Exit:** a growing corpus (reuse xats2js TEST + new suite) compiles &
  runs with **stdout matching the JS backend** (differential harness, §8); emitted Go passes
  `go vet`; representative datatypes are value-typed (not uniform boxing).

  **M2 decomposition** (delegable chunks, each = one emitter concern + a differential test;
  rough dependency order — M2.0 first, then M2.1→M2.2 gate the rest):
  - **M2.0 — Harness + liveness + scalar-type scaffold.** Generalize `build-go-m*.sh` into a
    reusable `build-go.sh <test.dats>` that compiles a source through BOTH backends and asserts
    byte-equal stdout (the differential oracle for every later chunk). Add a liveness pass so
    temps are bound only when used (kill the `_ = goxtnmN` noise). Stand up the skeletal
    `s2typ → Go type` map (scaffolding for concrete scalars). Exit: harness runs any test; M1's
    test01 still byte-equal; emitted Go has no dead `_ =` lines.
  - **M2.1 — Scalars & primops. ✅ DONE (verified).** `I1Vint/btf/chr/flt` + evaluated
    `I1Vi00/b00/c00/f00` emit as concrete Go (`int`/`bool`/`rune`/`float64`); literals are native
    Go literal syntax (int verbatim, `true`/`false`, rune literal, float verbatim). **KEY IR
    finding:** arithmetic/compare do NOT surface as `I1INSopr` — they lower as `I1INStimp`
    resolving to a prelude d2cst whose NAME identifies the op (`sint_add$sint`, `sint_lt$sint`,
    `dflt_add$dflt`, `char_lt`, `bool_eq`, ...), then an `I1INSdapp` applies the op-temp. The
    emitter recognizes this (scope-walk over the enclosing cmp's flat let-list) and emits **NATIVE
    Go operators** `(a OP b)` when the callee is a native-able op with 2 args (Regime-B payoff: no
    boxing); else a runtime call (`xatsgo.Xats_<name>`, the boxed/higher-order fallback, always
    provided). Liveness is op-aware: an inlined op-temp is not counted as a callee use, so its
    binding drops to `_ = xatsgo.Xats_<name>`. Runtime: per-type prints (sint/bool/char/dflt) +
    int/float/char/bool arithmetic/compare matching JS observable bytes; integer `/`(trunc) and
    `%`(remainder) verified vs JS over negatives. **Exit MET:** `run-suite.sh` ALL GREEN
    (test01 + test02_arith/test03_compare/test04_logic/test05_float/test06_char), each
    BYTE-EQUAL-vs-JS, gofmt-clean, `go vet` OK; emitted Go uses native operators on concrete
    scalars (not `[]any`). See BUILD-NOTES "M2.1".
    - **Deviation/finding:** the JS REFERENCE backend (`lib2xats2js.js`) has its own pre-existing
      bundling defect — `tokenfpr` is referenced but undefined, crashing whenever js1emit emits an
      `I1INSlam0`/`I1INSfix0` (which the primop/print TEMPLATES instantiate). The i0varfst JS shim
      was extended to also define a no-op `tokenfpr` (it writes only into a JS comment, so it's
      byte-safe for the oracle). String CONCAT (`strn_append`) additionally triggers a SEPARATE JS
      backend closure bug (`env1` undefined in `strn_make_fwork`); string concat/length are
      therefore deferred (kept out of the oracle-gated suite) — the Go side emits them correctly
      (`Xats_strn_append`), they just can't be JS-oracle-validated yet. Negation `~` and `&&`/`||`
      are special syntactic forms (not plain d2cst calls) and are out of M2.1 scope.
  - **M2.2 — Functions & calls (non-recursive). ✅ DONE (verified).** Top-level `fun`/`fn`
    emit as **package-level** Go `func <name>(<typed params>) <ret> { <lets>; return <result> }`
    (hoisted out of `main` via a two-pass walk, since Go forbids named funcs inside a func body;
    this also makes self-calls resolve naturally for the M2.4 stopgap). **KEY IR findings:**
    (a) a top-level function surfaces **wrapped** as `I1Ddclenv(I1Dfundclst(...), i0varlst)` — the
    `i0varlst` is the **i0varfst free-var set** (the shim's output; empty for a non-closure
    top-level fn), so the pass-1 walk MUST unwrap `I1Ddclenv`/`I1Dtmpsub`/`I1Dstatic`; (b) the
    function BODY is `I1CMPcons([I1LETnew0(I1INSrturn(i0cal, innerCmp))], I1Vnil())` — the real
    computation is the **inner** cmp of an `I1INSrturn`, which `i1cmp_go1emit_ret` unwraps →
    emits inner lets then `return <inner.result>`; (c) a call lowers to
    `I1INSdapp(I1Vfenv(d2var, envs), args)` — **`I1Vfenv`** (fn value = d2var + captured env),
    NOT `I1Vfid`; for a non-closure fn `envs` is empty so the callee emits as the d2var's Go
    name and args pass straight through (env tail appended for M2.5). (d) Params: each `i1bnd`'s
    own `i1tnm` becomes the Go param name (`goxtnm<stamp>`), and the body references the param
    through that SAME `i1tnm`, so decl/use agree with **no `arg<N>` indirection**. **Regime-B
    typing:** concrete arg/result Go types are recovered from the function d2cst's `T2Pfun1` via
    `gotypes_of_funstyp` (drops `npf` proof args; maps the prelude scalar abstypes
    `gint_type(xats_sint_t,…)`→`int`, `gflt_type`→`float64`, `bool_type`→`bool`, `char_type`→`rune`);
    `any` only where unrecoverable. **i0varfst shim: VALIDATED** — real multi-function programs
    exercised it cleanly (lib built; free-var sets surfaced as the `I1Ddclenv` env list; all
    tests byte-equal-vs-JS, so no shim divergence). Tests test07–test10 (one-arg/one-call;
    one-fn-multi-call + result-in-arithmetic; fn-calling-fn; multi-arg mixed int+float64), each
    BYTE-EQUAL-vs-JS, gofmt-clean, `go vet` OK. See BUILD-NOTES "M2.2".
  - **M2.3 — Control flow. ✅ DONE (verified).** `I1INSift0` (if), `I1INSlet0` (let-in),
    `I1INScas0` → Go expression-less `switch` + clause/pattern machinery
    (`i1cls`/`i1gpt`/`i1gua`, `i0pckgo1` = the `i0pck`-analog boolean test). Emitted in
    BOTH **return-position** (each branch `return`s) and **value-position** (pre-declare
    `var goxtnm<N> <T>`; branches assign), threaded by `i1ins_fully_returnsq` (every
    branch retq?) — `i1cmp_tail_returns` (a STRONGER `i1cmp_retq` that also recognizes a
    trailing `I1LETnew1(tnm, fully-returning if/case)` whose result is that tnm — the
    recursion crux `i1cmp_retq` misses) suppresses the dangling trailing return. **KEY IR
    findings:** value-position if/case/let surface as `I1LETnew1(tnm, ift0/cas0/let0)` with
    plain-value branches; return-position have each branch = `I1CMPcons([I1LETnew0(I1INSrturn
    (ical, body))], I1Vnil())`; a recursive `fun = if...` lowers to a fully-returning
    `I1LETnew1(tnm, ift0)` with cmp result `I1Vtnm(tnm)` (NOT `I1LETnew0`, so stock
    `i1cmp_retq` returns false — hence `i1cmp_tail_returns`). **Case:** expression-less
    `switch { case <casval == lit>: …; case true: …; default: panic("…cfail") }` (literal
    `panic` is a Go TERMINATING statement, so a return-position switch is seen exhaustive —
    no "missing return"). **Guards:** FOLDED into the case condition `case <patcond> && <g>:`
    (guard-lets pre-emitted above the switch; the guard references the scrutinee temp
    directly, already in scope), so a failed guard falls through to the next clause — matching
    the JS backend's retry. **SIMPLE patterns only** (var/wildcard → `true`; int/char/bool/
    float literal → native `==`; transparent `!`/flat/free wrappers); **datacon patterns →
    M2.7** (emit `false` test + stderr NOTE). **Value-position type recovery** improved:
    `gotype_of_cmp` scans the cmp's lets for the result temp's producer (native op →
    bool/int/float64 by op; nested block → its branch type), so a value-position `let`/`if`
    result temp is typed concretely (e.g. `(a*a)` → `int`) instead of `any`. Also: **non-unit
    `val x = CMP` patterns** (`I0Pvar`) now emit (needed for let-in's inner decls) → `goxtnm
    := <result>` + a `_ =` suppressor. Tests test12 (if return), test13 (if value), **test14
    recursive factorial `fact(5)=120` — the headline**, test15 (case int/char + default),
    test16 (case guards), test17 (let-in) — all byte-equal-vs-JS, gofmt-clean, `go vet` OK
    (`make suite` = 16/16 GREEN, no regressions). **LIMITATION:** a TOP-LEVEL `val x = if/
    let/case …` does NOT lower to `I1INSift0` etc. — the front-end leaves it as an un-lowered
    `I1Vnone1(D3Eift0(…))` (verified); these forms only lower INSIDE function bodies, so the
    value-position tests are function-bodied (which exercises value-position binding fully).
    **HAND-OFF:** M2.4 (TCO) reuses `i1cmp_tailq`/`i1val_tailq` + `I0CALfun`/`I0CALfix` for
    the tail case (the if/return path + package-level self-call already make NON-tail
    recursion a real Go recursive call); M2.7 picks up datacon patterns (`I0Pcon`/`I0Pdapp`/
    tuple/record) — currently a `false`-test + NOTE — via `d2con` `ctag`/`narg` + typed
    projections, and tuple/record `val` patterns.
  - **M2.4 — Recursion + TCO. ✅ DONE (verified).** A TAIL self-call (`I1INSrturn` whose inner
    cmp is `i1cmp_tailq` -- its last let binds the cmp result via an `I1INSdapp` on `I1Vfenv(self)`,
    `d2var_tailq` matching the enclosing `I0CALfun`/`I0CALfix`) now emits as a Go `for { …
    goxtnm<param>=newval; continue }` loop (O(1) stack) instead of a recursive call; NON-tail
    recursion stays a plain Go recursive call (no `for`), so test14 factorial is unchanged.
    **KEY hook:** `i1fundcl_go1emit` wraps the body in `for {}` + threads the param i1tnms
    (`params_of_fjarglst`) iff `i1cmp_body_has_tailcall`; `i1cmp_go1emit_ret` (now carrying
    `params: i1tnmlst`, threaded down the whole return-position chain incl. if/case branches)
    turns the unwrapped tail `I1INSrturn` into `emit_param_reassign` + `continue`. **SIMULTANEITY:**
    the IR pre-binds each new arg into its own temp BEFORE the self-call (verified: `t1=i-1; t2=acc+i`
    emitted first, then `i=t1; acc=t2; continue`), so the reassignment is safe with no spill.
    **HEADLINE test18** (sum 1..50_000_000 via tail recursion) runs instantly and does NOT
    stack-overflow -- a standalone non-TCO recursive Go version at the SAME depth crashes
    (`goroutine stack exceeds`), proving the loop was really emitted; **test19** tail accumulator
    (`fac(10)=3628800`). `make -j psuite` = 18/18 GREEN, byte-equal-vs-JS, gofmt/vet clean.
    **`I1INSfix0` DEFERRED to M2.5** (local recursive closures): 0 `I1INSfix0` nodes in any tail
    test (all route through `I1Dfundclst`); `i1insgo1` emits an explicit `// UNHANDLED ... M2.5`
    marker for it. See BUILD-NOTES "M2.4".
  - **M2.5 — Closures.** `I1INSlam0`, `I1Vfenv` env capture (uses `i0varfst`). Test:
    higher-order / closure-returning programs.
  - **M2.6 — Layout-aware tuples/records.** Flesh out `s2typ → Go type`; `I1INStup0` → value
    struct/array, `I1INStup1`(`trcdknd`) → pointer, `I1INSrcd2` → typed struct; projections
    `I1INSpflt`/`I1INSproj` → field access; lvalues `I1Vlpft`/`lpbx`/`lpcn` + `I1INSassgn`. Test:
    tuple/record programs; **assert value-typed (not `[]any`)**.
  - **M2.7 — Datatypes & pattern matching.** `I1Vcon` construction + `I1INSpcon` projection →
    typed tagged structs via `d2con` `ctag`/`narg`; case over datacons. Test: list/tree programs.
  - **M2.8 — Exceptions + lazy.** `I1INSraise`/`I1INStry0` → panic/recover; `I1INSl0azy`/`l1azy`/
    `dl0az`/`dl1az` → thunks. Test: exception + lazy/stream programs.
  - **M2.0 — ✅ DONE (verified).** Reusable differential harness `build-go.sh <src>` (both
    backends → byte-equal assert; mtime-cached; per-test isolated under `BUILD/<name>/`) +
    `TEST/run-suite.sh` conformance runner. Liveness pass: `I1LETnew1(tnm,ins)` → `goxtnm := ins`
    if used else `_ = ins` (kills the dead `_ =` noise; `go vet` clean). `gotype_of_styp/ival`
    scaffold (stub, scalar cases + `any`). test01 still byte-equal.
  - **Type-recovery decision (KEY for Regime B):** per-expression static type is **present at
    intrep0** (`i0exp` carries `i0typ`, incl. layout-bearing `I0Ttrcd(trcdknd,…)`) but **dropped
    at intrep1** (`i1val` = `lctn+node`, no styp). The *layout distinction* (flat vs boxed) DOES
    survive via the `I1INStup0`/`tup1`(token) constructor split + `d2con`/`d2cst` getters, so data
    layout is recoverable. But concretely typing *computed temps* (else `any`) needs the type
    threaded. **Plan:** M2.1–M2.5 use literal-kinds + `d2cst` signatures + `any` fallback for
    opaque temps. **At M2.6, introduce an `i1tnm stamp → i0typ` side-table built in our
    (already-diverged-by-then) copy of `trxi0i1_dynexp.dats`** — each temp is minted right where
    the typed `i0exp` is in scope, so it's a carry-through, not re-inference. This is the main
    Regime-B enabler; deferring it keeps M2.1–M2.5 simpler. (Full findings in BUILD-NOTES.md.)
  - **Decision (`i0varfst` debt):** KEEP the JS shim through M2; it is **oracle-validated** —
    M2.2/M2.5 differential tests exercise real free-var sets against the JS backend, so any
    shim divergence shows up as a byte mismatch. Cross-check the shim's stamp-sorted-dedup
    semantics against `xats2cc/srcgen1/DATS/intrep0_utils0.dats` during M2.2 review. Invest in
    the source fix (rebuild `lib2xats2cc.js`) only if the oracle flags divergence.

- **M3 — Static-typing completeness.** *(CORRECTED framing — the backend does NOT monomorphize.)*
  The ATS frontend ALREADY monomorphizes templates: the template-resolution passes
  (`trtmp3b`/`trtmp3c`/`t3read0`) resolve each `fun{T}` use to a concrete instance, materialized at
  intrep1 as **`t1imp = T1IMPall1(d2cst, t2jaglst, i1dclopt)`** — the resolved constant + concrete
  TYPE ARGUMENTS + the per-instance instantiated BODY (already lowered). So the `$T`-suffixed d2csts
  (`sint_add$sint`, …) ARE the monomorphic instances; the backend just **emits each resolved
  instance with its concrete types** (the M2.6a side-table + `d2cst` signatures already do most of
  this for prelude templates). M3's real work: (1) **emit user-defined template instantiated bodies**
  (`t1imp_i1dclq`/`i1dclopt`) as concrete Go funcs; first proof is now green via **test84**
  (the xats2js AVL `tree_isAVL<a>` template body: local exception, local helper functions,
  recursive datatype matching, raise/catch). Prelude template bodies are intentionally NOT inlined
  yet; they stay on the runtime/operator path to avoid JS-CATS/prelude-body leakage. (2) drive `any`
  out of remaining recoverable temps. **The
  genuine residual `any` is `I0Tvar`/`s2var` — universally-quantified polymorphic functions
  (`fun f{a:type}(x:a)`), which ATS represents UNIFORMLY/BOXED (type var erased). `any` there is
  FAITHFUL to ATS's own representation, not a defect**; Go generics (`[T any]`) are an OPTIONAL
  optimization for the cases where a type var maps cleanly, never a correctness requirement. **Exit:**
  user-template instances emit concrete Go; resolved-monomorphic code is `any`-free; `I0Tvar` code
  uses `any`/uniform (or opt-in generics); `go vet` clean; perf within target factor of hand-Go.

- **M4 — Runtime completeness & scale.** Flesh out the Go runtime to cover the ATS prelude
  surface (lists, options, arrays, strings, streams, refs, hashmaps, file/IO). Push toward
  compiling large programs; stretch goal: self-host (compile the compiler). **Exit:** broad
  prelude-backed programs run; documented coverage matrix vs JS backend.

  *(Roadmap revised per the "layout-aware from the start" decision: the former standalone
  "layout-aware data" milestone is folded into M2; subsequent milestones renumbered M3/M4.)*

Cross-cutting throughout: the differential test harness (§8), CI, and a coverage matrix of
intrep1 constructors handled.

### Self-hosting drive (the north star — user-directed)

**Goal:** xats2go compiles the ATS3 compiler/emitter's own sources to Go → a native Go binary
of the compiler that can compile itself. This reorders the back half of the roadmap around a
**forcing function**: stop inventing small tests; point xats2go at *real, increasingly-large
ATS3 code* and fix whatever breaks. The failure set IS the prioritized work list.

**Escalation ladder (each rung gated by byte-equal-vs-JS where the program has output):**
1. **The JS backend's own test programs** (`xats2js/srcgen2/TEST/test01–03_xats2js.dats`, 126–161
   lines: prelude `list(sint)`, `list_length<T>`, local `fun`, nested ctor patterns, `var` loops).
2. Larger standalone real programs (algorithms over lists/strings/arrays/options).
3. A real prelude/library **module** compiled + exercised.
4. **The emitter's own source files** (`go1emit_*.dats`, `trxi0i1_*.dats`, …) — the literal
   self-hosting target.
5. The full compiler (frontend + intrep0/1 + go1emit + driver) → a Go binary that self-hosts.

**Gap tracker (seeded by the first probe on test01–03 — fix in priority order):**
- **[lang] Local functions — ✅ DONE (M-selfhost.1).** A `fun` declared inside `let`/`where`
  (capturing locals) now emits as a Go LOCAL CLOSURE at its declaration point — the M2.5 fix0 idiom
  `var f F; f = func(..){.. f(..) ..}` (pre-declared `var` => self/mutual recursion; Go lexical
  capture => surrounding locals). A NESTED `I1Dfundclst` is routed via a NEW
  `i1dclist_go1emit_local`/`i1dcl_go1emit_local` entry (used by the `I1INSlet0` decl walk) ->
  `f0_localfun` (in `go1emit_decl00.dats`); TOP-level funs keep the M2.2 package-level hoisting
  (distinguished by ENTRY POINT, never double-emitted). A tail-recursive local closure reuses the
  M2.4 `for{..continue}` TCO loop. PROVEN byte-equal-vs-JS by **test74** (`fact`'s `loop` captures +
  mutates the enclosing `var res`; `summ`'s `aux` is a tail-recursive local closure), and on test70's
  `fact1/fact2/fact3` (the JS test01 copy).
- **[bug] String escaping — ✅ DONE (M-selfhost.1).** The string-literal TOKEN emitter
  (`i0strgo1`/`f0_strn` in `go1emit_utils0.dats`) now normalizes the RAW SOURCE rep to a valid Go
  double-quoted literal (mirrors the JS backend's `f0_strn`, retargeted to Go): a source
  line-continuation `\<NL>` is DROPPED; an already-two-char source escape (`\n` `\t` `\"` `\\` `\r`)
  passes through (valid Go); a RAW control byte -> the Go escape. (The previous code copied the rep
  verbatim -> `\<NL>` -> `string literal not terminated`, +16 more.) PROVEN byte-equal-vs-JS by
  **test73** (line-continuation + tab + escaped quote/backslash + `\n`) and test70.
- **[lang] Type annotations/casts — ✅ DONE (M-selfhost.2).** `D3Eannot`/`D3Et2pck`/
  `D3Elabck` now lower to real intrep0 wrapper nodes instead of `I0Enone1`, and `tryd3i0`
  recurses through `I0Eannot`/`I0Et2pck`/`I0Elabck`/`I0Et2ped` instead of clobbering them
  to `I0Enone2`. `trxi0i1` then erases the type-only wrapper to the inner value. PROVEN by
  **test75** (`(x : sint)`, `(1 : sint)`, annotated call args, annotated compound exprs);
  JS oracle is deferred because the current JS reference still emits invalid JS for this D3
  annotation shape, so test75 uses a golden.
- **[runtime] variadic `prints`/`gs_print_aN` — ✅ ADDED (bounded, required for ALL three rungs).**
  `prints(..)` resolves to `gs_print_aN` (a template whose body is `g_print<x_i>(x_i)` per arg).
  The Go backend resolves the whole call to ONE runtime fn; added `Xats_gs_print_a0..a4` to
  `runtime/xatsgo/xatsgo.go` — a per-arg `gsPrintOne(any)` type-switch (string/int/bool/float64/rune
  -> the same bytes the per-type prints push). Needed because every rung's OUTPUT goes through
  `prints`. (Faithful template INLINING is still the longer-term M3 path.)
- **[runtime] Prelude coverage (M4)** — missing `xatsgo.<fn>` (e.g. `list_length`, list ops). The
  big ongoing runtime build: implement the ATS prelude surface in Go (mine the JS runtime
  `srcgen2_prelude.js`/`precats.js`/`xatslib.js` for the contract). Also: `list_length<sint>` is a
  *template* instantiation — verify whether its instantiated body emits (then needs no runtime) or
  resolves to a prelude d2cst (then needs a runtime fn). This ties into M3 (emit user-template bodies).
- **[lang] User `#impltmp` template body emission — ✅ FIRST RUNG (M3.1).** `I1INStimp`'s
  `t1imp` really does carry the instantiated body (`T1IMPall1(..., i1dclopt)`); the Go emitter now
  emits a non-prelude `I1Dimplmnt0` payload as an inline Go function literal at the temp-binding site.
  Guardrails: skip prelude-sourced impls (runtime/operator path remains authoritative), always bind
  datacon clause roots so `I1Vp1cn` projections in instantiated bodies have a Go local, and add
  concrete `Xats_sint_abs`. PROVEN by **test84_poly_avl_xats2go** (adapted from xats2js
  `test07_xats2js`: polymorphic `tree_isAVL<a>`, local `NotAVL`, local `max`/`auxlst`, recursive
  datatype case, `$raise`/`try`). Golden output: `isAVL(t5) = true\nisAVL(t6) = false\n\n`.
- **[lang/runtime] Linear `list_vt` datacon-field mutation — ✅ DONE (M2.7/M2.8 rung).**
  The xats2js `test02` shape `list_vt_cons(!x1, xs)` followed by `x1 := x1 + 1` now compiles:
  `I1INSflat(I1Vlpcn(...))` raw `Args[i]` reads are asserted when a native scalar op supplies the
  concrete type (`goxtnm.(int) + 1`), and `I1Vlpcn` assignment writes back to the same cons cell.
  Runtime support added `list_vt_make_{1,2,3}val`, `list_vt2t`, direct
  `console_log(the_print_store_flush())` names, and list/list_vt printing. PROVEN by
  **test85_list_vt_mut_xats2go**: `xs = list(1,2,3)\nxs = list(2,3,4)\n\n`.
- **[runtime] Top-level `prints` auto-flush — ✅ DONE (xats2js parity rung).**
  xats2js programs such as `test05_xats2js.dats` can call `prints(...)` without an explicit
  `the_print_store_log()`.  The Go backend now emits an end-of-main `xatsgo.XATS2GO_flush_pending()`
  and the runtime drains the store with `fmt.Print`, preserving source bytes without appending a
  console-log newline.  PROVEN byte-equal-vs-JS by **test86_autoflush_tpl_xats2go**:
  `fibo4(10) = 55\n`.
- **[self-hosting parity] xats2js test03 full fact/fibo/by-ref rung — ✅ PROMOTED.**
  The broader xats2js `test03_xats2js.dats` source now lives as
  **test87_xats2js03_full_xats2go**.  It combines ordinary recursion, tail-recursive local tuple
  and record loops, repeated top-level `prints` auto-flushed at exit, and
  `&(?int) >> int` initialization (`foo(x0)`).  PROVEN byte-equal-vs-JS.
- **[lang/runtime] Non-linear lazy stream forcing — ✅ DONE (M2.8 rung).**
  `$lazy(...)` and `!thunk` now survive `trxd3i0`/`tryd3i0`, lower through intrep1 as
  `I1INSl0azy`/`I1INSdl0az`, and emit `xatsgo.Xats_l0azy`/`Xats_dl0az`.  User names containing
  `$` are mangled through the Go-safe symbol path for both declarations and references.  Runtime
  support added `gs_println_a{0..4}` on top of the existing print-store model.  PROVEN by
  **test88_lazy_xats2go**: the stream thunk body prints once and the memoized head prints twice.
- **[self-hosting] Top-level `#implfun` / `I1Dimplmnt0` emission — ✅ FIRST RUNG.**
  Resolved, non-template `#implfun` declarations now emit package-level Go
  functions named from the resolved `d2cst` (`<symbol>_<locstamp>`), typed from
  `d2cst_get_styp`, with by-reference params registered and the same return/TCO
  path as ordinary `fun`.  Pass 2 skips them so they are not emitted inside
  `main`.  `make selfhost-smoke` is now the structural guard against vacuous
  backend-source probes: `go1emit_utils0.dats` emits real package-level funcs
  instead of only skip-comments.  `make selfhost-strict` is now **GREEN** for
  this probe: compiler-internal constants such as `d2cst_get_name`,
  `d2var_get_lctn`, `token_get_node`, `strnfpr`, and
  `fprint_loctn_as_stamp` emit package symbols instead of fake
  `xatsgo.Xats_*` runtime hooks; `i0s00go1` no longer routes through the private
  `f0_gostr` helper; and `f0_gochr` calls the backend-owned
  `XATS2GO_gochar_esc` hook supplied by both the JS shim and the Go runtime.
  The strict gate still asserts that `i0s00go1` and `i0c00go1` are emitted so
  inlining/skipping them cannot create a false green.  Rejected experiments:
  adding `mytmplib00.hats` did not improve the probe, promoting the helpers
  directly to `#implfun` surfaced unresolved `strn_fprint`/`char_fprint`
  templates, and use-site env-miss guessing was rejected because it hides scope
  bugs.  Conformance suite remains **71/71 GREEN**.
- **[self-hosting] Go compile probe — ✅ ADDED, FAILING USEFULLY.**
  `tools/selfhost-go-compile.sh` runs strict selfhost emission for `go1emit_dynexp.dats` and
  `go1emit_decl00.dats`, then builds each emitted file in an isolated scratch Go module under
  `srcgen2/BUILD/selfhost-go-compile` with `replace xatsgo => runtime/xatsgo`.  The old raw-`$`
  syntax blocker is gone; the current frontier is unresolved helper/package symbols such as
  `strnfpr_1691`, `envx2go_filr_get_1189`, `i1dcl_lctn_get_13791`, and
  `xatsgo.Xats_gs_prerrln_n2`.
- **[rung-1 RESULT — ✅ GREEN]** the three real JS-backend programs copied as
  `test70/71/72_jsbk*_xats2go` are now byte-equal-vs-JS and live in the Makefile suite:
  1. **test70**: by-reference params (`&sint`) map to Go pointers (`*T`, `&x`, `*p`), so `fact4(10)`
     mutates the caller cells and matches JS.
  2. **test71**: tuple/record-pattern function params emit `I1Vp0rj`/`I1Vp1rj` projections, so
     `loop@(x,r)`-style local recursion compiles and runs.
  3. **test72**: polymorphic datacon patterns unwrap `I0Ptapq`; recursive datacon-tail projections
     assert to `*xatsgo.XatsCon`; prelude `list_length` and the current list-counting
     `gseq_folditm` runtime hooks resolve; uninitialized aggregate vars recover tuple/record static
     types and tuple-element lvalues compile.
  **Caveat:** `Xats_gseq_folditm` is still a bounded runtime fallback for this list-counting surface.
  The general solution is broader M3: emit more resolved template bodies / user `#impltmp` instances
  as concrete Go, not a single runtime hook for every possible `folditm$fopr`.
- **[M3/M4] FAITHFUL TEMPLATE-INSTANCE INLINING (chosen direction; `strn_foritm` is the first probe).**
  The frontend DOES carry the resolved template body — via **`t1imp_i1dclq`** (the DECL form), NOT
  `t1imp_i1cmpq` (which is `None` for these). `js1emit` reaches it the same way: `cmpq` None → falls
  to `f0_t1imp` → `dclq`. The Go M3 path (`t1imp_func_literal_go1emit`) already reads `dclq` but
  GUARDS prelude bodies off (`i1dcl_preludeq` → runtime name) — that guard is why `strn_foritm` emits
  the undefined `xatsgo.Xats_strn_foritm`. **The chain is alias-collapsible and bottoms out cleanly**
  (traced through the prelude): `strn_foritm<> = gseq_foritm<strn><cgtz>` → `gseq_foritm<a1ref(a,n)><a>
  = a1ref_foritm<a>{n}` → `a1ref_foritm` is a tail-recursive index loop `loop(0)` /
  `if i0<a1ref_length(A0) then { foritm$work(get$at(A0,i0)); loop(i0+1) }`. Every bottom is a primitive
  we ALREADY have: `a1ref_length`→`strn_length`, `get$at`→`strn_get_at`, `suc`/`<`→native ops,
  `foritm$work`→the emittable user body; the tail loop → a Go `for` (reuse M2.4 TCO). **No generic
  `a1ref`/`cgtz` Go runtime is required.** Design: recursively inline `dclq` bodies, COLLAPSING the
  template-alias chain (the prior wall — `func() func(any) any { gseq_foritm }` — was stopping after
  ONE alias level), bottoming out at a name-gated PRIMITIVE set (native ops, the print fns,
  `strn_length`/`strn_get_at`/…, `$work` hooks → emit user body) which also keeps `sint_print`/
  `strn_print` (whose bodies bottom out in print primitives) correctly on the runtime path. NOTE a
  measured inconsistency to resolve: a toy `strn_foritm` test shows `dclq=Y` but the real
  `go1emit_utils0` target showed `dclq=n` — confirm the body is reliably present for the real target.
- **[M3] `foritm`/`$work` family — ✅ DONE (test94), via TYPED RECONSTRUCTION not faithful inlining.**
  KEY FINDINGS that reframed this: (1) faithful `dclq`-body inlining (js1emit's mechanism) STRUCTURALLY
  works but does NOT transfer to typed Go — broad inlining regressed to 3/75 on three walls untyped JS
  never faces: type-threading (`char`→`rune` not carried into inlined sigs), curried-alias arity
  (`func() func(any)`), and CATS-primitive coverage. (2) The `$e1nv` linear-capture failure
  (`go1emit_utils0`'s `strn_foritm`) is a SHARED assembled-pipeline limitation — BOTH the GO bundle and
  the JS-oracle bundle hit the IDENTICAL 50 `$e1nv` errcks; only the complete `jsemit00` (same intrep1
  pipeline) resolves it. So `lib2xats2cc` rebuilds are a dead end and the linear-capture case is not
  differentially testable. (3) **The "monomorphization wall" was a framing error — the types are NOT
  lost.** intrep0 carries full per-expression typing (`i0exp_ityp`, `i0typ_node` with `I0Tcst`/`I0Tapps`/
  `I0Ttrcd`/`I0Ttcon`), and we already translate it (`gotype_of_i0typ`) + thread it across `trxi0i1`
  (`go_tytab_record` captures `i0exp_ityp` at the chokepoint). intrep0 even carries the resolved template
  instances (`I0Etimp`/`t0imp`, the analog of `t1imp`); intrep1's only edge is ANF+TCO. SOLUTION (Route B,
  selective, typed): recognize the `foritm`/`$work` family BY NAME and emit a TYPED Go loop —
  `foritm$work<char>` → `XATS_foritm_work := func(c0 rune) any {body}` (the `char`→`rune` comes from the
  param d2var's styp via `gotypes_of_fjarglst` — exactly the "types are upstream" point), and
  `strn_foritm(s)` → `func() any { n0 := strn_length(s); for i:=0;i<n0;i++ { XATS_foritm_work(strn_get_at(s,i).(int32)) }; return XATSNIL() }()`. Bottoms out only in existing primitives; sidesteps the curried-alias
  wall by reconstruction. Name-gated so the 74 are untouched → **suite 75/75**. Supporting: `binop_of_callee`
  now also recognizes a direct-`I1Vcst` native-op callee (closure bodies apply e.g. `char_gte` directly),
  + a `strn_foritm_callee_q` liveness skip. test94 is GOLDEN-validated (`8 0 3`): js1emit inlines the
  `gseq`/`a1ref` loop but its emitted JS references an undefined `env1` → runtime `ReferenceError` (the
  documented js1emit closure-conversion bug, same precedent as test84/test75). **BONUS:** this also
  resolved `strn_foritm` in the real `go1emit_utils0` self-host target (reconstruction needs only the
  `foritm$work` `#impltmp`, present even when `dclq=n`), exposing 2 NEW unrelated gaps there (a
  `goxtnm136` var-scope issue + an unknown string-escape) — fresh forcing-function discoveries.
  **OPEN (architecture):** GENERAL faithful template inlining (beyond name-gated families) still needs
  the typed-from-side-table path — confirm instance-body temps are `go_tytab`-recorded; if not, either
  extend coverage or (the principled fallback for a typed backend) lower from intrep0 directly.
- **[self-hosting] COMPLETE GAP INVENTORY (architect probe, all 16 GO_DATS emitted to Go).**
  Emitting every backend source through the bundle and diffing referenced-vs-defined `xatsgo.Xats_*`
  symbols (+ real `case false /* UNHANDLED */` codegen markers) yields the prioritized work map.
  Repro: `XATSHOME=… node --stack-size=8801 BUILD/xats2go-bundle.patched.js <src> | awk sentinels`
  for each GO_DATS file, then `grep -oE 'xatsgo\.Xats_[A-Za-z0-9_]+'` minus the runtime's `var Xats_…`.
  **Four classes:**
  - **D — string-literal `case` patterns (✅ FIXED, P1, test91).** Was the keystone: `goop_of_name`
    (the 107-case op-name→Go-operator dispatch) compiled to `case false /* UNHANDLED pat: non-datacon
    structural */` for EVERY branch — the self-hosted op layer was dead. `i0pckgo1` now has an
    `I0Pstr(tstr)` case mirroring `I0Pint`/`I0Pflt`: `<casval> == <i0strgo1 literal>`. `XATSSTRN` is
    identity on the Go string, so it's a native string `==`; JS oracle via `f0_str0`. styp0 markers
    107→0; suite 71→72 GREEN (test91_strpat). NOTE: tuple/record patterns *in `case`* are a separate,
    still-open structural-pattern gap (a handful of markers in go1emit_dynexp.go).
  - **A — native generic-int ops (✅ FIXED, P2).** The real (generic) sources use `gint_<op>$sint$sint`
    (the g0int/gint interface instantiated at sint), NOT the monomorphic `sint_<op>$sint` the suite
    exercised — so they fell through `goop_of_name` to UNDEFINED `xatsgo.Xats_gint_*` calls. Added the
    full `gint_*$sint$sint` → native-operator block to `goop_of_name` + uniform `any` runtime fallbacks
    `Xats_gint_*_sint_sint` (superseding a one-off `bool`-returning `gint_eq` stopgap now covered by
    native inlining). go1emit_utils0 re-emit: 0 gint runtime apply-calls left, native `(a OP b)` in
    their place (19 dead `_ =` op-temp suppressors). Regime-B win for ALL programs, not just self-host.
    Suite stays 72 GREEN (inert for `sint_*` tests = the no-regression proof).
  - **B — prelude runtime completeness (IN PROGRESS).** Pure `runtime/xatsgo` additions, zero emitter
    risk (except where an op is native-inlinable, which is an emitter+runtime pair). Conventions:
    strings = Go `string` (`XATSSTRN`=identity, byte-indexed `len`/`s[i]`), char = `int32`, op fallback
    shape `func(a,b any) any { return a.(T) OP b.(T) }`.
    - **✅ B1 (string prims, oracle-verified, test92):** `strn_eq`/`strn_neq` — Go `==`/`!=` ARE native
      on `string`, so added to `goop_of_name` (inline like `char_eq`) + `any` runtime fallbacks; this
      also makes `if s = "lit"` emit a native bool test instead of an `any`-returning call. `strn_get_at`
      (byte-at-index → char/int32) added as a runtime fn. test92_strops byte-equal-vs-JS (`1 3 0 true
      false`); go1emit_utils0's `(sname = "…")` chains now emit native `(s == xatsgo.XATSSTRN("…"))`.
    - **✅ B2 (`gs_print_n1..n10`):** the `prints` overload the generic sources resolve to. Prelude
      `gs_print_n<N> = gs_fproc_n<N> where g_fproc = g_print` → observably IDENTICAL to the
      oracle-validated `gs_print_a<N>` twins, so mirrored exactly (each arg via `gsPrintOne`).
    - **RESULT: go1emit_utils0 undefined runtime symbols 10 → 1.** The lone remainder is `strn_foritm`
      (see next) — every other `xatsgo.Xats_*` it references is now defined. (Its `go build` is still
      Class-C-blocked by frontend accessors.)
    - **OPEN:** `strn_foritm` is NOT a runtime fn — it is a TEMPLATE with an implicit `foritm$work<char>`
      body (same class as `gseq_folditm`); faking it with a runtime stub is the bounded hack this plan
      already rejects. It belongs to M3 (emit resolved template bodies with their `$work` inlined).
      Also still open: `strn_fprint`, `bool_neg` (a UNARY op — wants a native-unary-op emitter path,
      analogous to the binop path, else an `any`/bool runtime fn), lists/options (`list_{append,consq,
      exists,map_e1nv,mergesort,sing,sortedq}`, `optn_map_e1nv` — several are higher-order = M3-class).
  - **C — cross-module frontend accessors (OPEN, the DEEP M5 blocker, ~35 syms):** backend sources
    call frontend getters — `d2cst_get_name`, `d2var_get_lctn`, `token_get_node`, `fprint_loctn_as_stamp`,
    `i0exp_node_get`, `i0pat_*`, `t0imp_*`, … — which are **defined nowhere in any emitted file** (they
    live in `lib2xatsopt`/the local xats2cc intrep0 stage, NOT in GO_DATS). So **no backend `.dats` can
    `go build` standalone yet**, even with B done: e.g. go1emit_utils0's residual after A+B is purely
    these dangling frontend symbols. **Reframes the roadmap:** true fixpoint (M5) requires emitting the
    intrep0/frontend type layer to Go *or* a hand-written Go shim package giving Go reps for the frontend
    data types (`d2cst`/`d2var`/`token`/`s2typ`/…) + their accessors. This is the next architectural
    decision (emit-the-frontend vs shim-the-frontend); pick before chasing more leaf symbols.
- **[lang] Still owed for self-hosting:** Class B/C above; structural (tuple/record) patterns in `case`;
  remaining M2.8 linear-lazy cleanup coverage, modules/`staload`, abstract types (`abstype`/`assume`),
  FFI/`extern`, the full pattern language, polymorphic-function uniform repr. Discover the rest via the
  forcing function.

**Methodology:** keep `xats2js/.../TEST/*.dats` (and a growing real-program corpus) as conformance
rungs in the suite; each rung that breaks → categorize gaps (emit-time `// UNHANDLED` + `go build`
`undefined:`/type errors) → fix → escalate. Update this tracker each rung.

---

## 8. Test / conformance strategy

**Primary oracle: differential testing against the JS backend.** For each source `T.dats`:
compile with `xats2js` → run on node → capture stdout; compile with `xats2go` → `go build` →
run → capture stdout; **assert byte-equal**. The print-store mechanism makes output
deterministic, so this is a strong, low-effort correctness signal.

Layers:
1. **Constructor coverage corpus** — one tiny program per intrep1 construct (each tuple/proj
   flavor, each datatype shape, TCO, exceptions, lazy, closures…). Drives M2/M3.
2. **Reuse xats2js TEST/** programs as shared conformance cases.
3. **`go vet` + `gofmt -l`** gates on all emitted output (catches unused vars, bad types).
4. **Allocation/perf microbenchmarks** to validate the Regime-B payoff (M3/M4).

A test is "passing" only when: emitted `.go` builds, runs, and stdout matches JS byte-for-byte.

---

## 9. Delegation protocol (how this gets built)

Per the operating model — **architect plans, agents implement, reviewers verify, architect
composes**:

1. **Plan** a milestone into self-contained chunks with explicit exit criteria + the exact
   reference files/APIs (this doc + §11) so agents don't re-discover.
2. **Delegate** each chunk to an implementation agent with: the reference js1emit/xats2js file
   to mirror, the intrep1 nodes in scope, the target Go shapes (§3/§5), and the test to make
   pass.
3. **Review** with reviewer agents: (a) correctness vs IR semantics & the JS backend; (b) Go
   idiom/`go vet`; (c) does it actually exploit layout metadata where M3+ requires.
4. **Compose**: integrate, run the differential suite, update the coverage matrix + this PLAN.

Keep each delegated chunk scoped to one emitter concern (e.g., "emit `I1INScas0` as a Go
switch + pattern binding") with a failing test that defines done.

---

## 10. Key API reference (so agents start from facts, not search)

Layout / metadata:
- `srcgen2/SATS/xbasics.sats:320` — `datatype trcdknd` (`TRCDflt0` + `TRCDbox0..3`);
  `:342` `trcdknd_fltq`, `:345` `trcdknd_equal`.
- `srcgen2/DATS/dynexp3_utils0.dats:103` — `d3exp_trcdfltq` (extracts `trcdknd` from
  `T2Ptrcd` static type; the canonical "is this flat?" query).
- `srcgen2/SATS/dynexp2.sats:381` `d2con_get_ctag`, `:389` `d2con_get_styp`,
  `:433` `d2con_get_narg`, `:435` `d2con_get_nprg` (`#symload` as `ctag`/`styp`/`narg`/`nprg`).

IR (already studied; in `xats2js/srcgen2/SATS/intrep1.sats`):
- `i1cmp = I1CMPcons(i1letlst, i1val)`; `i1let = I1LETnew0(ins) | I1LETnew1(tnm,ins)`.
- `i1ins`: `I1INSopr`,`I1INSdapp`,`I1INStimp`,`I1INSpcon/pflt/proj`,`I1INSlet0`,`I1INSift0`,
  `I1INScas0`,`I1INStup0/tup1/rcd2`,`I1INSlam0/fix0`,`I1INStry0`,`I1INSflat`,`I1INSfold/free`,
  `I1INSrturn`,`I1INSdp2tr`,`I1INSdl0az/dl1az/l0azy/l1azy`,`I1INSraise`,`I1INSassgn`.
- `i1val_node`: `I1Vint/btf/chr/flt/str` + evaluated `I1Vi00/b00/c00/f00/s00`, `I1Vtop`,
  `I1Venv`,`I1Vtnm`,`I1Vcon`,`I1Vcst`,`I1Vfid`,`I1Vfenv`,`I1Vaddr`,`I1Vaexp`,
  `I1Vp0rj/p1cn/p1rj/p2rj`, `I1Vlpft/lpbx/lpcn`, `I1Vextnam`.
- `i1dcl_node`: `I1Di0dcl`,`I1Dextern/static`,`I1Ddclst0/local0`,`I1Ddclenv`,`I1Dtmpsub`,
  `I1Dinclude`,`I1Dvaldclst/vardclst/fundclst`,`I1Dimplmnt0`.
- TCO predicates: `i1cmp_tailq`,`i1val_tailq`,`d2var_tailq` (`:563-570`).

Driver pipeline (`xats2js/srcgen2/UTIL/xats2js_jsemit01.dats`):
`d3parsed_of_fildats` → tread3a/trtmp3b/c/t3read0 → `i0parsed_of_trxd3i0` →
`i0parsed_of_tryd3i0` → `i1parsed_of_trxi0i1` → `i1parsed_js1emit`. The Go driver swaps the
last call for `i1parsed_go1emit`.

Emit env (`xats2js/srcgen2/SATS/xats2js.sats` / `…_myenv0.dats`):
`envx2js = ENVX2JS(FILR, lvl0:sint, nind:sint)`; `envx2js_make_out`, `_free_nil`,
`_incnind/_decnind`, `_pshlam0/_poplam0`, `_filr$get/_lvl0$get/_nind$get`. Helpers:
`nindfpr`,`strnfpr`,`nindstrnfpr`,`tokenfpr`,`d2confpr/d2cstfpr/d2varfpr`. Naming:
`d2conjs1/d2cstjs1/d2varjs1` (`<sym>_<stamp>`), `i1tnmjs1` (`jsxtnmNNN`).

JS runtime to re-implement in Go (`srcgen1/xshared/runtime/`): `srcgen2_prelude.js` (1527 L,
core primitives/IO/strings/arrays), `srcgen2_precats.js` (1039 L, datacons/lval-paths/lazy),
`srcgen2_xatslib.js` (392 L, dynarray/hashmap), `xats2js_js1emit.js` (259 L, low-level
helpers), `srcgen2_prelude_node.js` (123 L, node IO). Lval path encoding (`ctag` 0=root,
1=flat-field, 2=box, 3=consd) is the model for Go lvalues; `fold`/`free` are GC no-ops.

---

## 11. Open decisions (resolve as we hit them; current defaults in **bold**)

1. Datatype repr: **tagged struct (`Tag int` + typed fields)** per datatype vs interface +
   per-constructor structs. Default tagged-struct (matches IR `ctag`; revisit for M3).
2. Unused-temp handling: **`_ = x` suppressor in A**, real liveness pass in M3.
3. Templates: **the FRONTEND already monomorphizes** (resolved `t1imp` instances at intrep1) — the
   backend emits resolved instances with concrete types, it does NOT monomorphize. Genuine
   polymorphism (`I0Tvar`/`s2var`, universally-quantified fns) → **`any`/uniform-boxed (faithful to
   ATS)**; Go generics only as an opt-in optimization. (See M3, corrected.)
4. Exceptions: **panic/recover** (vs error-return threading).
5. Module/package layout: **single `package main`** initially; per-module packages later.
6. Runtime packaging: **a `xatsgo` Go module** imported by emitted code (vs concatenated
   source like JS). Go's package model favors a real imported module.

---

*This document is the durable source of truth. Update it at the end of every milestone:
move items from roadmap → done, record decisions, and keep the API reference accurate
(verify symbols still exist before citing them to agents).*
