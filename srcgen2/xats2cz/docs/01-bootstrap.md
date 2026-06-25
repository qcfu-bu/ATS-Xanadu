# How the ATS3 `xats2js` compiler bootstraps from the JS seed

> Status: VERIFIED end-to-end on 2026-06-25 by re-running the bootstrap from
> scratch in this tree. Every command, timing, and artifact size below is
> reproduced, not quoted from memory. Paths are absolute from
> `XATSHOME = /Users/qcfu/Projects/ATS-Xanadu`.

This document is the foundation for the 3rd backend attempt (`xats2cz`, Chez
Scheme). It explains *exactly* how an ATS3-source compiler turns into a runnable
JavaScript program with no pre-existing ATS3 binary — i.e. how the chicken/egg of
"a compiler written in the language it compiles" is broken by a prebuilt seed.

---

## 0. The bootstrapping equations (from `srcgen2/README.md`)

ATS3 was bootstrapped (29 Mar 2025) *via JavaScript*. Two compiler sources exist:
`srcgen1` (written in ATS2) and `srcgen2` (written in ATS3). With `C.compile(S)`
meaning "compiler `C` compiles source `S`":

```
exe1 = ATS2compiler.compile(srcgen1-src)     # ATS2 builds the ATS3-in-ATS2 compiler
exe2 = exe1.compile(srcgen2-src)             # that builds the ATS3-in-ATS3 compiler
exe3 = exe2.compile(srcgen2-src)             # which rebuilds itself
exe3 = exe3.compile(srcgen2-src)             # FIXPOINT: output is stable
```

The fixpoint (last line) is the proof of a successful bootstrap. Everything in
this tree is the `exe2`/`exe3` regime: a **prebuilt JS seed** plays the role of
"a working ATS3→JS compiler" and is used to compile the current `srcgen2` source.

---

## 1. The two seeds (the egg)

Bootstrapping needs a *running* ATS3 compiler before we have one. That is the
**seed**: a checked-in, prebuilt JS file produced by an earlier generation.

| Seed | Path | Size | Role |
|------|------|------|------|
| Type-checker | `xassets/JS/xatsopt/xatsopt_tcheck00_ats2_opt1.js` | 2.3 MB | front-end only: parse + typecheck a `.sats`/`.dats`, emit nothing runnable; used to validate `.sats` interfaces |
| **JS emitter** | `xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js` | 2.5 MB | **the real workhorse**: full front-end + JS backend; `node SEED file.dats > out.js` |

- `_ats2` = this seed was itself produced by the ATS2 chain (`exe1`); `_opt1` =
  run through `google-closure-compiler --compilation_level SIMPLE` (shrinks +
  speeds up). The non-opt `_ats2.js` variants the inner makefiles default to do
  **not** exist in this tree — always override to the `xassets/.../*_opt1.js`.
- Also present: `*_ats3_opt1.js` (4.0–4.5 MB) — newer self-compiled (`exe3`)
  generations, kept as references.

The seed is **slow but adequate** (Hongwei Xi's words). A single backend file
compiles in ~1.4 s; the whole frontend (~240 files) is minutes.

### The seed needs `XATSHOME`
The seed resolves prelude `#include`/`#staload` paths (e.g.
`prelude/HATS/prelude_dats.hats`) relative to `$XATSHOME`. **`XATSHOME` must be
exported** or every compile fails to find the prelude. (`PATSHOME` is unrelated /
unset here.)

```bash
export XATSHOME=/Users/qcfu/Projects/ATS-Xanadu
node --stack-size=8801 \
  $XATSHOME/xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js  some.dats > some.js
```
`--stack-size=8801` is mandatory: the compiler (and its emitted prelude loader)
is deeply recursive and overflows Node's default stack otherwise.

---

## 2. The compiler is two halves: FRONTEND and BACKEND

The full compiler = **frontend** (language-independent) ++ **backend**
(target-specific). They are built separately and live in different trees.

### Frontend — `lib2xatsopt.js`
- Source: `srcgen2/SATS/*.sats` + `srcgen2/DATS/*.dats` (~42 SATS, ~200 DATS).
- Stages (see `srcgen2/README.md`): lexing (`lexbuf0`,`lexing0`) → parsing
  (`parsing`,`pread00`) → fixity (`trans01`/`tread01`) → binding
  (`trans12`/`tread12`) → pre-typecheck + overload resolution
  (`trans2a`/`trsym2b`) → simple typecheck (`trans23`/`tread23`) → **template
  resolution** (`trans3a`, then `trtmp3b` non-recursive + `trtmp3c` recursive) →
  `t3read0`/`f3perr0`. Output of the frontend is **`d3parsed`** (the level-3,
  type-checked, template-resolved AST).
- Built artifact: `srcgen2/lib/lib2xatsopt.js` (≈177 MB in this tree; it is the
  concatenation of ~200 separately-compiled, un-minified files).

### Backend — `lib2xats2js.js`
- **Canonical, self-contained source: `srcgen2/xats2js/srcgen1/{SATS,DATS}/`.**
  6 SATS, 24 DATS. This is what the official `Makefile_buildjs` STEP 2 bootstraps
  and the tree we base `xats2cz` on.
- The backend pipeline (the 6 SATS, in order):
  `intrep0` → `intrep1` → `trxd3i0` → `trxi0i1` → `xats2js` → `js1emit`.
  - `trxd3i0` : `d3parsed` → **intrep0** (expression-shaped IR; *types erased*).
  - `trxi0i1` : intrep0 → **intrep1** (A-Normal-Form IR for imperative targets).
  - `xats2js` + `js1emit` : intrep1 → JavaScript text.
- Built artifact: `srcgen2/xats2js/srcgen1/lib/lib2xats2js.js` (27 MB, 247 887
  lines after a clean build here).

> NOTE — there are two backend trees: `srcgen2/xats2js/srcgen1/` (COMPLETE: has
> `intrep0`+`trxd3i0`) and `srcgen2/xats2js/srcgen2/` (lacks them — it shares the
> `d3→intrep0` stage with the C backend via `lib2xats2cc.js`). For a standalone,
> understandable bootstrap, **use `srcgen1/`**. There is also a prebuilt
> `frontend/BUILD/lib2xats2js.js` (19 MB) and `lib2xats2cc.js` (16 MB) produced by
> the user's concurrent `frontend/` work — treat those as read-only references.

---

## 3. The per-file pipeline: separate-compile → namespace → concat

This is the mechanical core, in `srcgen2/xats2js/srcgen1/Makefile_xjsemit`
(identical pattern in `srcgen2/Makefile_xjsemit` for the frontend). For each
source file:

```
DATS/foo.dats  --(node SEED)-->  BUILD/JS/foo_dats_out0.js   # STEP A: transpile
foo_dats_out0.js  --(sed jsxtnm→jsxNNNtnm)-->  foo_dats_out1.js   # STEP B: namespace
cat(all *_out1.js in source order)  >  lib/lib2xats2js.js          # STEP C: concat
```

### Why the namespacing exists (critical!)
Each file is compiled **independently**, so the seed emits the *same* temp-var
base name `jsxtnm` in every file. Concatenating ~24 (or ~200) files would collide
those temps. STEP B rewrites `jsxtnm → jsx<NNN>tnm` with a **distinct 3-digit
`NNN` per file**, making every file's temp namespace disjoint. Verified: the
built `lib2xats2js.js` contains `jsx101tnm … jsx124tnm` (one per backend file).

- The official makefile computes `NNN` with a stateful counter
  (`$(eval NFILE=$(NFILE) X)` + `$(words …)`, base 100). This is **order-dependent
  and fragile under `make -j`**. The `xats2chez` Makefile improved on it: `NNN =
  100 + position-in-list`, a pure function of position — parallel-safe and
  reproducible. **`xats2cz` should use the position-based form.**
- Two backend files (`xats2js_utils0`, `xats2js_tmplib`) emit no `jsxtnm` at all
  (no temps), so only 22 distinct namespaces appear — harmless.

### Real STEP-A/B trace (from the verified build)
```
node --stack-size=8801 .../xats2js_jsemit00_ats2_opt1.js DATS/intrep0.dats > BUILD/JS/intrep0_dats_out0.js
sed -e 's/jsxtnm/jsx101tnm/g' BUILD/JS/intrep0_dats_out0.js > BUILD/JS/intrep0_dats_out1.js
... (102 intrep0_print0, 103 intrep0_utils0, 104 intrep1, ... 124 js1emit_decl00)
cat BUILD/JS/*_dats_out1.js  > lib/lib2xats2js.js
```
SATS files are compiled to `*_sats_out0.js` (by the tcheck seed) **only for
interface validation** — they are NOT concatenated into the lib (the seed reads
`.sats` source directly via `#staload` when compiling a `.dats`).

---

## 4. Assembling a *runnable* compiler (`jsemit00`)

`lib2xatsopt.js` and `lib2xats2js.js` are libraries, not runnable. The runnable
compiler is assembled in `srcgen2/xats2js/srcgen1/UTIL/Makefile_xjsemit`
(target `xats2js_jsemit00`) by concatenating, in order:

```
1. xats2js_js1emit.js        # JS backend runtime: the print-store, emit helpers
2. srcgen2_precats.js        # CATS primitive floor (the $extnam leaf primitives)
3. srcgen1_prelude.js        # the ATS prelude, as JS
4. srcgen1_prelude_node.js   # Node bindings (file I/O, argv, ...)
5. srcgen1_xatslib_node.js   # xatslib (maps, buffers, ...) for Node
6. sed 'jsx(...)tnm→js1\1tnm'  lib2xatsopt.js      # FRONTEND, namespace-prefixed js1
7. sed 'jsx(...)tnm→js2\1tnm'  lib2xats2js.js       # BACKEND,  namespace-prefixed js2
8. node SEED xats2js_jsemit00.dats                  # the DRIVER (main), seed-compiled
```
→ `xats2js_jsemit00_ats3.js` (≈202 MB here). `jsemit01` is identical except a
different driver (`xats2js_jsemit01.dats`).

### The second-level namespacing: `js1` / `js2` / `js3`
Step 6/7 rewrite the already-3-digit `jsxNNNtnm` to **`js1NNNtnm`** (frontend) and
**`js2NNNtnm`** (backend). This keeps frontend temps disjoint from backend temps
when both libs are concatenated into one image. (When a *third* lib is added —
e.g. the chez emitter in `xats2chez` — it uses the `js3` prefix.) Runtime files
(steps 1–5) are hand-written JS and need no namespacing.

### Runtime path resolution
- `S2XSHRD = srcgen2/xats2js/srcgenx/xshared/runtime` (`srcgenx → srcgen1`
  symlink) supplies `xats2js_js1emit.js`, `srcgen2_precats.js`.
- `S1XSHRD = srcgen1/xats2js/srcgenx/xshared/runtime` supplies
  `srcgen1_prelude.js`, `srcgen1_prelude_node.js`, `srcgen1_xatslib_node.js`.
  (The srcgen1 runtime is used because `srcgen1/prelude` code requires it — a
  bootstrap artifact Xi notes he intends to clean up.)

---

## 5. The driver pipeline (`xats2js_jsemit00.dats`)

`srcgen2/xats2js/srcgen1/UTIL/xats2js_jsemit00.dats`. `mymain_main` then
`mymain_work(fpath)` is the whole compiler invocation for one source file:

```
mymain_main:
  the_fxtyenv_pvsl00d()     # load persisted fixity defs (the "00d" store)
  the_tr12env_pvsl00d()     # load persisted trans12/binding defs  (00d, NOT 01d!)
  xatsopt_flag$pvsadd0("--_XATS2JS_")           # select the JS backend
  xatsopt_flag$pvsadd0("--_SRCGEN2_XATS2JS_")
  mymain_work(argv[2])

mymain_work(fpth):
  dpar = d3parsed_of_fildats(fpth)   # FRONTEND: lex→parse→typecheck→template-resolve
  dpar = d3parsed_of_tread3a(dpar)
  dpar = d3parsed_of_trtmp3b(dpar)   # template resolution phase 1 (non-recursive)
  dpar = d3parsed_of_trtmp3c(dpar)   # template resolution phase 2 (recursive)
  dpar = d3parsed_of_t3read0(dpar)
  f3perr0_d3parsed(stderr, dpar)     # report errors (the "F3PERR0_D3PARSED:" banner)
  ipar = i0parsed_of_trxd3i0(dpar)   # d3 → intrep0
  ipar = i1parsed_of_trxi0i1(ipar)   # intrep0 → intrep1
  js1emit_i1parsed(stdout, ipar)     # intrep1 → JS text  (to stdout)
```

> **The "00d vs 01d" trap** (recorded in prior-attempt memory and reconfirmed
> here): the driver loads `the_tr12env_pvsl00d`. Loading the wrong store
> (`01d`) selects the wrong prelude tree, which mis-resolves env-capturing
> templates and silently drops whole function chains. Any `xats2cz` driver
> adapted from this MUST keep `_pvsl00d`.

This stage list IS the architecture: `xats2cz` keeps stages 1–6 (frontend +
`trxd3i0`) and the flag/store setup verbatim, and replaces only
`trxi0i1 → intrep1 → js1emit` with a Chez-adapted `trxi0i1cz → intrep1cz →
cz1emit`. See `docs/03-ir-and-templates.md`.

---

## 6. Verified from-scratch reproduction (2026-06-25)

| Step | Command (XATSHOME exported, opt1 seeds) | Result |
|------|------|--------|
| single-file sanity | `node --stack-size=8801 $SEED DATS/intrep1.dats` | 6 597 lines, **0 errors**, 1.4 s |
| backend clean build | `make -f Makefile_xjsemit cleanall lib2xats2js` (serial) | `lib2xats2js.js` 27 MB / 247 887 lines, **42.9 s**, namespaces `jsx101–124` |
| assemble driver | `make -C .../srcgen1/UTIL -f Makefile_xjsemit xats2js_jsemit00` | `xats2js_jsemit00_ats3.js` 202 MB |
| compile a program | `node $NEWC test07_fun1.dats` | 348 lines JS, 0 errors |
| **run it** | `cat <node-runtime> emitted.js \| node` | prints `42` ✓ |
| self-application | `node $NEWC DATS/trxi0i1.dats` (exe2 recompiles its own source) | 6 963 lines, 0 errors |

**Generation drift is cosmetic.** Diffing the freshly-built `exe2`'s output for
`trxi0i1.dats` against the seed's output: identical line count (6 963), and the
*only* differences (724 lines) are in comments — the current source emits
`// I1FUNDCL: XATS000_char_eq(2349)` (name + stamp) where the older seed emits a
bare `// I1FUNDCL`. The emitted **code is identical**. The seed is simply an
older generation with poorer diagnostics; the source tree is self-consistent and
the seed is adequate to bootstrap it. (This also reveals that `js1emit` annotates
every emitted function decl with its mangled name + a stamp — see the IR doc.)

To run emitted JS for a program, prepend (order matters), all from
`srcgen2/xats2js/srcgen1/xshared/runtime/`:
`srcgen2_prelude.js`, `srcgen2_prelude_node.js`, `srcgen2_precats.js`,
`srcgen2_xatslib.js`, `xats2js_js1emit.js`, then the emitted file.

---

## 7. Makefile map (which file does what)

| Makefile | Dir | Role |
|----------|-----|------|
| `Makefile_buildjs` | top level | orchestrates the whole bootstrap: STEP 1 frontend `lib2xatsopt` + tcheck00/01, STEP 2 backend `lib2xats2js` + jsemit00/01, STEP 3 py backend. Sets `XATS2JS_JSEMIT00` to the `xassets` opt1 seed via relative paths. |
| `srcgen2/Makefile_xjsemit` | frontend | per-file separate-compile of `srcgen2/{SATS,DATS}` → `lib2xatsopt.js`. SATS via tcheck seed, DATS via jsemit seed; namespace-sed; concat. |
| `srcgen2/xats2js/srcgen1/Makefile_xjsemit` | backend | same pattern for the 6 backend SATS / 24 DATS → `lib2xats2js.js`. |
| `srcgen2/xats2js/srcgen1/UTIL/Makefile_xjsemit` | driver | assembles runtime ++ js1(frontend) ++ js2(backend) ++ seed-compiled driver → `xats2js_jsemit0{0,1}_ats3.js`; `_opt1` target runs closure-compiler. |
| `srcgen2/{,xats2js/srcgen1/}Makefile_xats2js` | — | the *other* path: compile with a real ATS2-built `bin/xats2js` (srcgen1), producing `lib1xatsopt`. Not used for the JS-seed bootstrap; kept for the ATS2→ATS3 hop. |

---

## 8. Engineering takeaways for `xats2cz`

1. **Keep the separate-compile → namespace → concat structure**; it is what makes
   independent per-file compilation composable. Use **Makefiles** (separate
   compilation + caching), not sequential shell scripts.
2. **Namespace by position**, not a stateful counter (parallel-safe, reproducible).
   Use a fresh prefix (`js3…` or `cz…`) so the chez emitter lib never collides
   with frontend (`js1`) / shared-backend (`js2`) temps in one image.
3. **One frozen seed** (`xats2js_jsemit00_ats2_opt1.js`) compiles *everything*,
   including the new chez emitter source — we never need a chez binary to build
   the chez emitter (it is ATS3 source transpiled to JS, run on Node, emitting
   Scheme). The Chez compiler only runs the *emitted* programs.
4. **Reuse the frontend + `trxd3i0` verbatim.** `lib2xatsopt.js` (frontend) and
   the `d3→intrep0` stage are target-independent. The chez work is confined to
   replacing `trxi0i1/intrep1/js1emit`.
5. **`XATSHOME` exported + `--stack-size`** are non-negotiable invocation
   prerequisites.
6. **The driver must load `_pvsl00d` and set the right backend flags.**

See `docs/02-dependencies.md` for the scattered prelude/runtime/xatslib file
inventory, and `docs/03-ir-and-templates.md` for intrep0/intrep1 and template
emission.
