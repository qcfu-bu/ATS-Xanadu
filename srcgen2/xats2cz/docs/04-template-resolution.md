# Template/instance resolution — the root cause of "failed to resolve symbol", and the durable fix

> Status: VERIFIED 2026-06-25 from both sides — the frontend resolution code
> (`trtmp3b/3c`, `xglobal`, `dynexp2/3`) and the backend behaviour (compiling real
> files + a deliberately-unresolvable case through the working JS compiler and
> reading the emitted output). This document exists because dropped template
> instances ("failed to resolve symbol at link time") killed the two prior
> attempts. The fix is **upstream config + emitter discipline**, NOT re-implementing
> dropped instances. Citations: `srcgen2/SATS`, `srcgen2/DATS`,
> `srcgen2/xats2js/srcgen1/DATS`.

---

## 1. The full lifecycle of a template use

```
source:    foo<T>(args)                            -- a template call
trans2a/b: D3Etapq(d3f0=D3Ecst(foo), t2js=[T])     -- typechecked template application
trtmp3b:   D3Etimp(d3f0, TIMPLall1(foo, t2js, BODY))   -- resolve, attach 1-layer body
trtmp3c:   D3Etimp(d3f0, TIMPLallx(foo, t2js, BODY))   -- recursively resolve the body
trxd3i0:   I0Etimp(i0f0,  t0imp{stamp; T0IMPallx(foo, t2js, i0dclopt BODY)})
trxi0i1:   I1INStimp(i0f0, t1imp{stamp; T1IMPallx(foo, t2js, i1dclopt BODY)})
js1emit:   let jsxtnmN = function(args){ /* timp: foo */ <BODY inlined> }   -- nested closure
```
- A template use enters resolution as **`D3Etapq(cst, t2jaglst)`** (`dynexp3.sats:441`).
- **`trtmp3b`** (non-recursive) resolves it to **`D3Etimp(cst, TIMPLall1(d2cst, t2jaglst, d3eclist))`**: `tr3benv_t3apq_resolve` (`trtmp3b_utils0.dats:103-138`) calls `tr3benv_search_dcst` to collect candidate impl decls, `myfilter` keeps those whose template args unify (`tmpmatch_d3cl_t2js`) and whose substitution type-checks (`s2vts_stleq`), and returns `TIMPLall1(d2c0, t2js, dcls)`. The body `dcls` is one layer deep (not descended).
- **`trtmp3c`** (recursive) re-resolves and runs `tr3cenv_timpl_process` (`trtmp3c_utils0.dats:74-183`), which pushes the substitution, **registers the in-progress instance** (`tr3cenv_insert_timp`, lets recursion terminate), recursively resolves the body via `trtmp3c_tmpd3ecl`, and rebuilds as **`TIMPLallx(d2c0, t2js, dcls)`**.
- The instance descriptor `timpl = TIMPL(stamp, timpl_node)` (`dynexp3.sats:787-817`) carries the **stamp** (unique id) and the **body** as a `d3eclist` of `D3Ctmpsub`-wrapped impl decls.
- `trxd3i0_timpl` (`trxd3i0_decl00.dats:79-137`) maps `timpl → t0imp`, preserving the stamp; `trxi0i1_t0imp` maps `t0imp → t1imp`, preserving the stamp; `js1emit` inlines the body as a nested closure (see `03-ir-and-templates.md §4`).

**The body CAN be empty.** If `t3apq_resolve` finds no matching candidate, it returns
`TIMPLall1(d2c0, t2js, list_nil)` (`trtmp3c_utils0.dats:281-284`), and `trtmp3c`
leaves it untouched (`:126-130` `list_nil => (timp) // HX: ~found`). An empty-bodied
instance therefore survives to the backend. **This is the seed of every dropped
symbol.**

---

## 2. Three kinds of constant reference — how each must be emitted

A backend must classify every `d2cst` reference. The classification is **structural
and decidable from the IR + global maps** — no heuristics, no name-string matching.

| reference | predicate | emit |
|---|---|---|
| **template** | `d2cst_tempq(d2c)` = `list_consq(d2cst_get_tqas(d2c))` is **true** — i.e. it has template quantifiers (`dynexp2_utils0.dats:171-175`) | nothing standalone; **every use is an `I0Etimp` whose body is inlined** at the use site (a bare `I0Ecst` to a template is a bug — see §4) |
| **external primitive** | `the_d2cstmap_xnmfind(d2cst.stmp())` = `X2NAMsome(_)` — declared `… = $extnam "name"` (recorded by trans12, `trans12_decl00.dats:3058-3076`; API `xglobal.sats:285-294`) | the **bare external name** → links to the hand-written runtime floor (`XATS000_*`/precats). Never dropped. |
| **plain top-level def** | `tempq` false **and** `X2NAMnone` | the mangled name `xsymjs1(name)_<location-stamp>`; **resolved by the defining file's top-level `define`** (a non-template `I0Dimplmnt0`). Cross-file-safe because the stamp is the d2cst's canonical declaration location (identical at def and every use). |

`dimpl_tempq(dimp)` (`dynexp2_utils0.dats:189-206`: `DIMPLone1/2 → d2cst_tempq(d2c1)`,
`DIMPLnon1 → false`) is the same predicate applied to a *definition*. The JS backend
uses exactly it to split top-level `I0Dimplmnt0`: **template → emit nothing**
(materialized inline at uses); **non-template → emit the top-level `define`**
(`js1emit_decl00.dats:646`).

> Verified mangling agreement: `lexing_lctnize_all` is defined in
> `lexing0_utils2.js` as `let lexing_lctnize_all_9811 = function…` and referenced in
> `lexing0.js` as `lexing_lctnize_all_9811(…)` — same `_9811` (the d2cst's decl
> location). Cross-file links resolve because both sides derive the name from the
> same canonical location.

---

## 3. The persistent stores (`pvsl00d`) — why the prelude tree must match

Before compiling, the driver calls `the_fxtyenv_pvsl00d()` and
`the_tr12env_pvsl00d()` (`xats2js_jsemit00.dats:188-201`).
- `the_tr12env` holds the **binding/elaboration environments** (`the_sortenv` /
  `the_sexpenv` / `the_dexpenv`) built by translating the prelude through
  trans01→trans12 (`xglobal.dats:735-807`, `f0_pvsload` merges
  `D2TOPENV(tr11,tenv,senv,denv)` into the global maps). These maps are **exactly
  what `tr3benv_search_dcst` walks to find impl candidates** during resolution.
- `the_fxtyenv` holds the fixity table only.
- Loaded lazily, gated by `the_ntime`.
- **`00d` vs `01d` differ only in WHICH prelude tree they load**:
  `the_tr12env_pvsl00d` loads `/srcgen2/prelude/INIT/…` (`xglobal.dats:1046-1068`);
  `the_tr12env_pvsl01d` loads the legacy `/prelude/INIT/…` (`:1108-1129`). Loading
  `01d` populates `the_dexpenv` from the **wrong** tree, so impl-template chains that
  exist only in the srcgen2 tree are **invisible to `search_dcst`** → they resolve to
  empty bodies → drop.

**This single mismatch was the prior "dropped-functions wall."** The fix is one line:
the driver must use `…_pvsl00d`, so the prelude tree that *defines* the impls is the
one resolution *searches*.

### Env-capturing templates (`$e1nv`) — the canonical victim
`gseq_foritm$e1nv`, `gseq_map$e1nv`, … are environment-passing variants: a template
that threads an extra captured-env arg `<e1:vt>`. They are implemented by delegating
to the plain base template while re-binding the per-call hook to an env-aware hook
(`gseq001.dats:1993-2008`: `gseq_map$e1nv_list = gseq_map_list<…>(xs) where {
#impltmp map$fopr<…> = map$e1nv$fopr<…>(x0,e1) }`). They resolve to NONE when (a) the
inner re-bound hook has no in-scope `#impltmp` for the actual types, or (b) the base
impl lives only in a different prelude tree — i.e. the `00d/01d` mismatch.

---

## 4. The exact failure mode (empirically reproduced)

Take `gseq_folditm<xs><x0><r0>(xs,0)` and **omit** its required `#impltmp
folditm$fopr` hook. Compiling through the working JS compiler:

- The frontend prints **27 `F3PERR0-ERROR`** diagnostics. The unresolved instance is
  wrapped in **`D3Eerrck`** (`dynexp3.sats:599`), the wrapper propagates up the
  expression, and the **whole enclosing function declaration** becomes
  `D3Cerrck → I0Dnone1 → I1Dnone1`.
- The emitter then prints only `// I1Dnone1(…length_bad…)` — a comment. **No
  `let length_bad_<loc> = …` is emitted: the function is dropped.**
- Its caller references `length_bad_<loc>`, which is now undefined →
  **"failed to resolve symbol" at link/run time.**
- `XATS000_undef` count is **0** — the drop happens via the *errck → `I1Dnone1`* path
  (whole declaration dropped), **not** via a bodiless-instance marker. (The
  `XATS000_undef` path — `f0_t1imp` on an empty `t1imp`, `js1emit_dynexp.dats:1501` —
  is a *different*, rarer symptom for an instance that survives standalone without a
  body; it is a loud runtime trap, not a silent drop.)

So there are two symptoms, one root:
| symptom | trigger | observable |
|---|---|---|
| **function dropped → dangling caller ref** | unresolved instance poisons its enclosing decl → `D3Cerrck`→`I1Dnone1` | `F3PERR0-ERROR` at compile; missing `define`; link error at the *caller* |
| `XATS000_undef()` called | a bare empty-bodied `I0Etimp` that did *not* poison its decl | `XATS000_undef` in output; runtime trap |

**Root in both cases: the frontend failed to resolve the instance** (empty
`TIMPLall1`), almost always because of (a) the `00d/01d` store/prelude mismatch, (b)
a genuinely missing `#impltmp`, or (c) wrong/absent backend flags so the
backend-specific impls (`prelude/DATS/CATS/JS/…`) aren't in scope.

---

## 5. The durable, patch-free fix (three pillars)

**Do NOT** re-implement dropped instances in the runtime, hoist/lift/seed instances,
alpha-rename continuation maps, or pattern-match on name strings. Those are the
"various reasons / nonsense patches" that made the prior emitters unmaintainable.
The root fix is:

### Pillar 1 — Correct frontend invocation (the driver)
The `xats2cz` driver, adapted from `xats2js_jsemit00.dats`, MUST:
- call `the_fxtyenv_pvsl00d()` and `the_tr12env_pvsl00d()` (the **`00d`** srcgen2 tree);
- set the backend-selection flags so the right `#if defq(_XATS2…_)` prelude arms load
  (the JS build uses `--_XATS2JS_` + `--_SRCGEN2_XATS2JS_`; `xats2cz` needs the
  analogous arm — reuse the JS arm initially, or add `_XATS2CZ_` in
  `xatsopt_dpre.hats`, a deliberate design choice, not a shim);
- run the same `tread3a/trtmp3b/trtmp3c/t3read0` pipeline so instances are fully
  resolved before `trxd3i0`.
With this, **every legitimate template resolves; there are no spurious errcks** (the
verified compiles of `lexing0`/`lexing0_utils2`/`test72`: 0 errors, 0 `XATS000_undef`,
all instances inlined).

### Pillar 2 — The build harness fails loud on errcks
A per-file compile that produced any `F3PERR0-ERROR` (i.e. an `I0Dnone1`/dropped
function) **must fail the build**, never silently contribute a partial object with
dangling references. The `xats2chez` Makefile already did this
(`grep -qE "F3PERR0-ERROR.*$file" … exit 1`); `xats2cz` keeps it. A clean image is
one where **no file dropped anything** — then the only cross-file symbols are
well-defined non-template top-level names (§2) and runtime primitives.

### Pillar 3 — Emitter discipline (the `cz0emit` rules)
For every intrep0 reference/decl node, branch structurally — never guess:
- **`I0Etimp(tapp, t0imp)`** → inline `t0imp`'s body as a nested lambda. If the body
  is absent (empty `T0IMP*`), that is an **upstream resolution failure**: emit a loud
  marker and make the build fail (mirror `XATS000_undef`, but treat it as fatal in CI
  — it must never reach a shipped image). Do **not** fabricate a body.
- **`I0Ecst(d2cst)`** → classify by §2: `the_d2cstmap_xnmfind(stmp)` `X2NAMsome` →
  emit the bare external name; else if `d2cst_tempq` is **false** → emit
  `name_<location-stamp>` (resolved by a top-level `define`); else (`tempq` true but
  reached here as a bare cst) → **assert/error**: a template should always arrive as
  `I0Etimp`, so a bare template cst is an upstream bug to surface, not a name to dangle.
- **`I0Econ(d2con)`** → datacon representation.
- **`I0Dimplmnt0`** → `dimpl_tempq` true → emit nothing (inlined at uses); false →
  emit a top-level `(define name_<loc> …)`.
- **`I0Dnone0/I0Dnone1`** (and `I0Enone*`) → these are **error markers**; a clean
  compile has none. Emit a comment and, in CI, fail — never emit runnable code that
  references something an error marker stands in for.
- **Unhandled node** → fail loud (print the node), never silently skip.

The result is an emitter with **no instance bookkeeping at all** — no hoist set, no
lift map, no seed phase, no scope stack. Lexical nesting of inlined closures (§4 of
`03`) does everything, exactly as the JS backend does. This is the maintainable,
human-auditable design.

---

## 6. Why this is certain (evidence)
- Correct compiles inline 100% of instances with 0 drops: `lexing0_utils2.dats`
  (the prior "dropped-chain" file) → 35 inlined, 0 `XATS000_undef`, 0 errors;
  `lexing0.dats` (lazy char streams) → 255, 0, 0; `test72` (higher-order
  `gseq_folditm` + `folditm$fopr` continuation hook) → 16, 0, 0.
- The continuation hook that drove xats2chez's lambda-lifting is just an inlined
  nested closure (`// timp: folditm$fopr(55)`), resolving lexically.
- Deliberately removing a required hook reproduces the failure exactly: 27
  `F3PERR0-ERROR`, the function becomes `I1Dnone1`, no definition emitted, caller
  would dangle — and the frontend was **loud** about it the whole time.
- The whole compiler (frontend + backend), built per-file and concatenated, links and
  runs (it self-compiles `trxi0i1.dats`), because every file is errck-free and
  cross-file names agree by canonical-location stamp.

The lesson: "failed to resolve symbol" is **always** a symptom of an upstream
resolution failure (config or genuinely-missing impl) that the prior pipelines
swallowed silently. Resolve it at the source and fail loud; the emitter itself stays
trivial.
