# xats2go — Go backend for ATS3 — Architecture & Roadmap

Status: **M2 IN PROGRESS** — M2.0–M2.4 ✅ (harness+liveness; scalars/primops native-typed; user functions, package-level hoisting, typed sigs, i0varfst shim validated; if/let-in/case control flow + recursive factorial, return-vs-value mode threaded; **TCO: tail self-call → `for{…param=…;continue}` loop, non-tail → recursive call, deep 50M loop no stack-overflow**) · **build = incremental Makefile** (separate compilation) · M2.5 (closures) next · M0/M1 complete · Go 1.26.4. **suite = 18/18 GREEN, byte-equal-vs-JS.**
History: v1 arch → decisions (layout-aware; emitter in ATS3) → M0 → Go installed → M1 (byte-equal-vs-JS) → M2.0 (harness+liveness+type findings) → M2.1 (scalars/primops, native Go ops) → M2.2 (functions; 10 tests green) → Makefile separate-compilation build (cold `make -j` ~24s, incremental ~15s, byte-identical lib) → M2.3 next.
Build (OPTIMIZED): `make` (incremental relink **~1.7s**) · `make run/NAME` (**~3s**) · `make suite` (47s) · `make -j psuite` (**~10s, 16/16**). Cached sed-namespaced fixed libs (opt.js1/cc.js2/shim) + JS-oracle bundle built once + `NODE_COMPILE_CACHE`; emitter bundle md5-identical to pre-opt (output provably unchanged). Legacy `build-go.sh`/`run-suite.sh` still work.
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

- **M3 — Static-typing completeness & monomorphization.** Drive `any` out of the remaining
  monomorphic code; handle templates (`I1INStimp`/`t1imp`) via monomorphized concrete functions
  (Go generics as an optimization); concrete function signatures throughout. **Exit:** core suite
  emits `any`-free Go for monomorphic code; `go vet` clean; allocations/perf within target factor
  of hand-written Go on benchmarks.

- **M4 — Runtime completeness & scale.** Flesh out the Go runtime to cover the ATS prelude
  surface (lists, options, arrays, strings, streams, refs, hashmaps, file/IO). Push toward
  compiling large programs; stretch goal: self-host (compile the compiler). **Exit:** broad
  prelude-backed programs run; documented coverage matrix vs JS backend.

  *(Roadmap revised per the "layout-aware from the start" decision: the former standalone
  "layout-aware data" milestone is folded into M2; subsequent milestones renumbered M3/M4.)*

Cross-cutting throughout: the differential test harness (§8), CI, and a coverage matrix of
intrep1 constructors handled.

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
3. Templates: **monomorphized concrete funcs first**, Go generics as an optimization (M4).
4. Exceptions: **panic/recover** (vs error-return threading).
5. Module/package layout: **single `package main`** initially; per-module packages later.
6. Runtime packaging: **a `xatsgo` Go module** imported by emitted code (vs concatenated
   source like JS). Go's package model favors a real imported module.

---

*This document is the durable source of truth. Update it at the end of every milestone:
move items from roadmap → done, record decisions, and keep the API reference accurate
(verify symbols still exist before citing them to agents).*
