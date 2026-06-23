# xats2chez — a Chez Scheme backend for ATS3

Goal: lower the ATS3 IR to **Chez Scheme**, en route to a self-hosting ATS3
compiler that runs entirely on Chez (no Node). Bootstrapping uses the existing
**NodeJS-hosted** ATS3→JS transpiler to compile the (ATS3-written) Chez emitter
into JS; that bundle runs on Node and emits Scheme. The far milestone replaces
Node by compiling the whole compiler to Scheme.

This backend is modeled on `xats2js` (the JS backend) and `xats2go` (the Go
backend), reusing their **bootstrap/build/oracle scaffolding** but making one
decisive architectural departure (below).

---

## 1. Key architectural decision: emit from **intrep0**, not intrep1

The ATS3 codegen pipeline has two backend IRs:

```
source.{dats,sats}
  → [shared xatsopt frontend: parse + typecheck]            (lib2xatsopt.js, prebuilt)
  → d3parsed                                                (fully typechecked)
  → trxd3i0  →  i0parsed   (intrep0)                        (lib2xats2cc.js; FLAT/BOXED layout decided here)
  → tryd3i0  →  i0parsed   (intrep0, normalized)            (lib2xats2cc.js)
  → trxi0i1  →  i1parsed   (intrep1: ANF/SSA, imperative)   (copied into each backend)
  → {js1emit | go1emit} → target text
```

- **intrep1** is an A-normal, statement-oriented, imperative IR: `let`-instruction
  lists, `do{…break}while(false)` dispatch, explicit assignment and `return`,
  with tail-call→jump rewriting and closure-conversion (env-lifting) baked in.
  It exists to fit **imperative targets** (JS/Go) that historically lack
  guaranteed tail calls and first-class nested functions.
- **intrep0** is **expression-shaped**: `I0Elet0`, `I0Eift0`, `I0Ecas0`,
  `I0Elam0`, `I0Efix0`, `I0Edapp`, tuples/records, projections. It still carries
  types (`i0typ`) and pre-computed free-variable lists and tail-call markers.

**Chez Scheme is an expression language with native proper tail calls and native
lexical closures.** Therefore the entire reason intrep1 exists evaporates:

| intrep1 does this (for JS/Go) | Chez gives it for free |
|---|---|
| ANF flattening into statement lists | Scheme is expression-based (`let*`, nesting) |
| tail-call → `for{…continue}` jump | native **proper tail calls** (ignore `I0Erturn`/`i0cal`) |
| closure-conversion / env-lifting | native **lexical closures** (ignore the `i0varlst` FV lists) |
| `do{…break}while(false)` match dispatch | `cond` / `case` |

So **xats2chez emits Scheme directly from intrep0** and **skips `trxi0i1` and
`intrep1` entirely** — dropping ~7000 LOC of IR + lowering from the build, and
producing idiomatic, smaller, simpler Scheme.

Pipeline for this backend:

```
… → tryd3i0 → i0parsed (intrep0) → chez0emit → Scheme text → chez/petite
```

### intrep0 → Scheme mapping (the emitter contract)

Definitions: `xats2cc/srcgen1/SATS/intrep0.sats`.

| intrep0 node | Scheme |
|---|---|
| `I0Eint/Echr/Eflt/Estr`, `I0Ei00/Eb00/Ec00/Ef00/Es00` | literals (char = integer code, to match JS) |
| `I0Etop` / `I0Evar` / `I0Ecst` / `I0Econ` | name reference (mangled; see §5) |
| `I0Etimp(tapp, t0imp)` | resolved monomorphic instance → runtime call or inlined `i0dclopt` body |
| `I0Esapp/Esapq/Etapp/Etapq` | **erased** — emit the function part (type application) |
| `I0Edap0` / `I0Edapp(f,npf,args)` | `(f arg…)` (drop `npf` proof args) |
| `I0Epcon(_,lab,con)` | constructor-field proj → `(vector-ref con (+ lab 1))` |
| `I0Epflt/Eproj(_,lab,tup)` | tuple/record field proj → `(vector-ref tup lab)` |
| `I0Elet0(decls, body)` | `(let* (…) body)` / internal defines |
| `I0Eift0(t, th, el)` | `(if t th el)` |
| `I0Ecas0(_, val, cls)` | pattern match → `cond` + tag-tests + projections |
| `I0Eseqn(init, last)` | `(begin init… last)` |
| `I0Etup0/Etup1/Ercd2` | `(vector f0 f1 …)` |
| `I0Elam0(_,_,args,body,_)` | `(lambda (args) body)` |
| `I0Efix0(_,_,fid,args,body,_)` | `(letrec ((fid (lambda (args) body))) fid)` |
| `I0Ewhere(scope, decls)` | `(let* (decls) scope)` |
| `I0Eassgn(lval, rval)` | lvalue set (`set-box!` / path set) |
| `I0Eaddr/Eflat` | lvalue address / content (box ref / unbox) |
| `I0Eraise(_, exn)` | `(raise exn)` |
| `I0Edl0az/Edl1az` / lazy ctor | force / make thunk |
| `I0Efold/Efree` | **no-ops** (linear types; GC'd by Chez) |
| `I0Edprf` | **erased** (proof) |
| `I0Eannot/Elabck/Et2pck/Et2ped` | **erased** (casts/annotations) → emit inner |
| `I0Erturn(ical, e)` | emit `e` (tail position is native; ignore `ical`) |
| `I0Ecenv(e, fvs)` | emit `e` (ignore captured-var list) |
| `I0Eextnam/Esynext` | external name |

Decls (`i0dcl_node`): `I0Dvaldclst`→`define`; `I0Dvardclst`→`define`+box;
`I0Dfundclst`→`define`/`letrec`; `I0Dimplmnt0`→`define` the monomorphic instance;
`I0Dlocal0`→scoped defines; `I0Dstatic/Dextern/Ddclenv/Dtmpsub`→emit inner;
`I0Dinclude`→recurse; `I0Dd3ecl`/`I0Dnone*`→skip.

Patterns (`i0cls`/`i0gpt`/`i0gua`/`i0pat`): a `case` lowers to a `cond` whose
clauses test the scrutinee's constructor tag (`vector-ref v 0`), bind the
projected fields, evaluate guards (`I0GUAexp` bool guard, `I0GUAmat` match guard),
and fall through to a match-failure (`xats_cfail`).

---

## 2. Value-representation runtime contract (mirror the JS backend)

The JS runtime contract lives in
`srcgen2/xats2js/srcgen1/xshared/runtime/xats2js_js1emit.js`. We replicate its
**observable semantics** in Scheme so emitted output matches the JS oracle
byte-for-byte. Representation:

- **Data constructor** `c(f0,f1,…)` → vector `#(tag f0 f1 …)` (tag = small int).
  Tag test `ctgeq v t` = `(= (vector-ref v 0) t)`; field proj = `(vector-ref v (+ i 1))`.
- **Flat tuple / record** → vector `#(f0 f1 …)` (no tag); proj = `(vector-ref v i)`.
- **Boxed tuple** → same vector (boxing distinction is irrelevant in a uniform
  dynamic value world; layout tags `I0Etup0` vs `I0Etup1` both → vector).
- **Mutable var / lvalue** → a path cell, mirroring JS `XATSROOT/LPFT/LPBX/LPCN`
  + `lvget`/`lvset`, so nested in-place mutation of tuple/constructor fields works.
  (Simplest faithful model: a 1-slot box for roots; path nodes for field lvalues.)
- **Lazy** → `l0azy`/`dl0az` memoized thunk; `l1azy`/`dl1az` call-by-name.
- **Exception** → Scheme `raise` + `guard`; the raised value is a constructor vector.
- **Scalars**: int → fixnum/bignum; bool → `#t`/`#f`; float → flonum; string →
  Scheme string; **char → integer code** (JS uses `charCodeAt`; match it).
- **Print store**: `the_print_store` accumulates strings; `the_print_store_log`
  flushes (this is how `prints`/`println` output reaches stdout in both backends).

Runtime is split: a **hand-written core** (`xats2chez_runtime.scm`, the analog of
`xats2js_js1emit.js`) + the **compiled prelude** (the ATS prelude `.dats`/CATS
compiled to Scheme, analog of `srcgen2_precats.js`/`srcgen2_prelude.js`).
Runtime symbols the emitter references use the `Xats_…`/`XATS…` names the emitter
mints (see §5); Scheme has a flat namespace, so no package qualification (unlike
Go's `xatsgo.`).

---

## 3. Bootstrap & build (adapted from xats2go/Makefile)

The Chez emitter is **ATS3 source**, compiled to JS by the prebuilt transpiler,
then run on Node to emit Scheme. Chez is only the language of the *emitted user
program* (until the self-hosting milestone).

Toolchain (all present):
- `XATSHOME=/Users/qcfu/Projects/ATS-Xanadu`
- transpiler `jsemit00`: `xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js`, run as `node --stack-size=8801`
- `lib2xatsopt.js` (179 MB frontend, prebuilt — **never rebuild**)
- `lib2xats2cc.js` (intrep0 + trxd3i0/tryd3i0): `frontend/BUILD/lib2xats2cc.js`
- `lib2xats2js.js` (19 MB JS differential oracle): `frontend/BUILD/lib2xats2js.js`
- Chez: `chez`/`petite` (Homebrew). Node v26.

Build steps (one `node` process per `.dats`, `make -j8`):
1. **transpile** each emitter `.dats` → `BUILD/JS/%_dats_out0.js`
2. **namespace-sed** `jsxtnm`→`jsx<NNN>tnm`, `NNN` = 3-digit index (from **100**) = file's position in `CHEZ_DATS` (pure function of name → `-j` deterministic)
3. **concat** → `lib2xats2chez.js`
4. **link bundle** = `i0varfst-shim` ++ JS-runtime ++ `js1·lib2xatsopt` ++ `js2·lib2xats2cc` ++ `js3·lib2xats2chez` ++ driver
5. **run**: `node --stack-size=8801 bundle.js source.dats > out` ; extract between `;;==XATS2CHEZ-BEGIN==` / `;;==XATS2CHEZ-END==`
6. **execute** emitted Scheme: prepend `xats2chez_runtime.scm` + compiled prelude, run `chez --script`
7. **oracle**: diff stdout against the JS backend byte-for-byte; else hand-golden in `TEST/OUTS/`.

`CHEZ_DATS` (much shorter than xats2go — no intrep1/trxi0i1):
`xats2chez_myenv0`, `chez0emit_utils0`, `chez0emit_dynexp`, `chez0emit_decl00`,
`chez0emit`, `xats2chez_tmplib` (tmplib MUST be last).

---

## 4. Inherited gotchas (from xats2go BUILD-NOTES, all apply here)

1. **3-digit namespace counter from 100 is non-negotiable** — link regex is
   `jsx(...)tnm`; collisions corrupt temp names. Index = pure function of file
   position in `CHEZ_DATS`.
2. **The i0varfst shim is mandatory.** `lib2xats2cc.js` references-but-never-defines
   6 `i0varfst_*` funset helpers; *any program with a function* (incl. the prelude)
   throws `ReferenceError`. Reuse `gen-i0varfst-shim.sh` verbatim (it discovers the
   stamped names from the bundle).
3. **A `*.sats` change shifts ALL later stamps** (the transpiler numbers SATS funs
   by position). After any `chez0emit.sats`/`xats2chez.sats` edit, force a clean
   re-transpile of all `CHEZ_DATS` + driver. **Declare new helpers at the END of
   the SATS.** DATS-only edits are incrementally safe.
4. **The JS oracle is flawed in known ways** (e.g. `tokenfpr` undefined → the shim
   no-op-defines it; capturing-lambda `env1` bug). When the oracle is unavailable,
   fall back to hand-computed goldens in `TEST/OUTS/*.expected`.
5. **Exceptions need a LOCAL fork of the xats2cc D3→intrep0 stage** — the prebuilt
   `lib2xats2cc.js` has `I0Eraise` but no `I0Etry0` / try-lowering. Defer to a later
   milestone; append `I0Etry0` as the LAST `i0exp_node` ctor (preserves tags).
6. **argv contract**: `argv[2]` is the source (`[0]=node,[1]=bundle,[2]=source`).
   Transpile `.err` files are non-empty but benign (prelude-load trace on stderr);
   guard on output line-count + errck markers, not on `.err` emptiness.
7. **Unhandled IR nodes** emit a `;; UNHANDLED: <ctor>` comment **and** a stderr
   `prerrln` — never silently-wrong Scheme.

---

## 5. Naming (mirror js1emit/go1emit leaf emitters)

- temp/intermediate names: not needed (no ANF temps; we emit nested expressions).
- `d2var` (local var) → `<xsym>_<loc-stamp>` (Scheme-safe identifier).
- `d2cst` (constant): if it has a recorded `$extnam`/is a known runtime prim
  (`the_d2cstmap_xnmfind`), emit the **runtime name** (`Xats_<xsym>`), defined in
  `xats2chez_runtime.scm`; else a user impl → `<xsym>_<loc-stamp>`.
- `d2con` (constructor) → its **tag** (small int) for construction/tests; the
  constructor name is informational only.
- `xsym` mangler: map non-`[A-Za-z0-9_]` to a Scheme-safe char; ATS allows `'`,
  `$` etc. in names — Scheme identifiers are permissive but we normalize to
  `[A-Za-z0-9_]` + a few safe extras for stability.

---

## 6. Milestones

- **M0** — toolchain validation. Driver runs frontend→trxd3i0→tryd3i0, dumps
  intrep0 (`i0parsed_fprint`) to stderr, emits a fixed minimal Scheme program
  between the sentinels. Proves the bundle links & runs on Node here; captures
  ground-truth intrep0 for test00 (`val theAnswer=42`) and test01 (`strn_print`).
- **M1** — real emission for test00/test01: leaf emitters + the i0exp/i0dcl walk
  for literals, `val`/`fun` decls, application of a prelude `$extnam` constant,
  string literal, print-store flush. Run on Chez; diff vs JS oracle.
- **M2** — arithmetic, comparison, logic, float, char (scalar primops); `if`,
  `let`, `case`/guards; user `fun` (incl. recursion + tail loops — native TCO).
- **M3** — lambdas/closures/fix, captured vars (native lexical scope), data
  constructors + pattern matching, tuples/records + projection.
- **M4** — `var`/assignment/lvalues (boxes + path set), lazy, references.
- **M5** — exceptions (`$raise`/try): local xats2cc fork adding `I0Etry0`.
- **M6** — breadth: run the whole prelude-backed test corpus; compile the prelude
  itself to Scheme; performance (Chez `compile-file`).
- **M7** — self-hosting: compile the frontend + chez emitter to Scheme; run the
  compiler on Chez with no Node.

---

## 7. Layout

```
xats2chez/
  PLAN.md                         (this file)
  Makefile                        (bootstrap/build/oracle; -j8)
  runtime/
    scheme/xats2chez_runtime.scm  (hand-written core value-rep + print store)
    jsshim/gen-i0varfst-shim.sh   (copied verbatim from xats2go)
  srcgen2/
    HATS/libxatsopt.hats          (copied verbatim — frontend SATS surface)
    HATS/mytmplib00.hats          (→ xats2chez_tmplib.dats)
    SATS/xats2chez.sats           (envx2cz output env + fpr helpers)
    SATS/chez0emit.sats           (emitter interface: i0parsed_chez0emit + leaves)
    DATS/xats2chez_myenv0.dats    (envx2cz impl)
    DATS/xats2chez_tmplib.dats    (g_print/g_cmp instances for intrep0 nodes only)
    DATS/chez0emit_utils0.dats    (naming + leaf-value emission)
    DATS/chez0emit_dynexp.dats    (i0exp walk)
    DATS/chez0emit_decl00.dats    (i0dcl walk)
    DATS/chez0emit.dats           (top-level i0parsed_chez0emit + iterators)
    UTIL/xats2chez_czemit01.dats  (CLI driver)
    BUILD/                        (transpiles, libs, bundle, per-test scratch)
    TEST/                         (testNN_xats2chez.dats + OUTS/)
```
