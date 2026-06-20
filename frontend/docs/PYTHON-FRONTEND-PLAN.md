# A Python-surface frontend for ATS3 — design & implementation plan

> **Goal.** Add an alternative frontend to the ATS3 (ATS-Xanadu) compiler that
> accepts a **Python-like surface syntax** and feeds the existing compiler at the
> **level-2 (L2) AST** — *after symbol resolution, before type-checking* — so the
> entire type-checker, codegen (JS/C/Python), and LSP tooling are reused unchanged.
>
> All compiler facts below were verified against the source at
> `/Users/qcfu/Projects/ATS-Xanadu` (branch `LSP`). File:line citations are
> **hints that drift**; the stable anchors are the **named functions/datatypes** —
> re-grep if a line is off. This mirrors the convention in
> `language-server/docs/ATS3-COMPILER-PRIMER.md`.

---

## 1. The one-line architecture

```
Python-like source
  │  [NEW]  pylexer        → Python tokens + INDENT/DEDENT (carry real source loc)
  ▼
  │  [NEW]  pyparser       → PyAST  (a dedicated surface AST)
  ▼
  │  [NEW]  pylower        → L2 d2parsed   (own symbol resolution, reusing tr12env)
  ▼
======================= the existing compiler, untouched =======================
  │  [reuse] d3parsed_of_trans23   (trans23.sats:254)   →  L3, type-checked
  ▼
  │  [reuse] trans3a → trtmp3b/3c → js1emit              →  runnable JavaScript
```

The **only new code** is the three `[NEW]` stages (lexer, parser, lowering) plus a
thin driver. They live in a new `frontend/` ATS3 package and call the compiler as
a library. The seam — the **integration contract** — is a single value: a
`d2parsed` handle handed to `d3parsed_of_trans23`.

---

## 2. The hook point: what "level-2" means here, and why it is clean

### 2.1 The pipeline and the exact entry point

The ATS3 front-end is a pipeline of AST translations, each paired with a
non-fail-fast "proofread" pass that wraps bad nodes in `…errck` constructors
instead of throwing (see primer §2):

```
text → L0 (parse) → L1 (trans01: fixity) → L2 (trans12: binding) → L3 (trans23: typecheck)
```

- **L2** is the first level with real semantic identity: identifiers are resolved
  to **entities** — `d2var` (a bound variable), `d2cst` (a constant/function),
  `d2con` (a data constructor), `s2cst` (a type constant). Use sites embed the
  *same entity object* that the binding site created.
- The compiler exposes a **clean L2→L3 entry point**:

  ```
  fun d3parsed_of_trans23(dpar: d2parsed): d3parsed     // SATS/trans23.sats:254
  ```

  This is literally "give me a binding-resolved program and I will type-check it."
  It is exactly the *after-symbol-resolution, before-type-checking* boundary the
  frontend targets.

So the frontend's job reduces to: **produce a valid `d2parsed`.** Everything
downstream is reused.

### 2.2 The `d2parsed` we must build

```
d2parsed = D2PARSED of
  ( sint        stadyn     // 0 = static (.sats-like) / 1 = dynamic (.dats-like)
  , sint        nerror     // error count (we set this from our own diagnostics)
  , lcsrc       source     // the source identity (LCSRCfpath for a real file)
  , d1topenv    t1penv     // L1 top env (fixity) — we supply an empty one; see §6.6
  , d2topenv    t2penv     // L2 top env — the top-level bindings we created
  , d2eclistopt parsed )   // the lowered top-level declaration list
// maker: d2parsed_make_args(...)  (srcgen2/SATS/dynexp2.sats:1972; symload `d2parsed`)
// NB: d2parsed is an `#abstbox` (OPAQUE) — the `D2PARSED of (...)` above is conceptual,
// not a visible constructor. You CANNOT pattern-match or build it directly; the ONLY
// way to construct one is d2parsed_make_args(...). (Verified 2026-06-20.)
```

`d2topenv` is four name→item maps `(g1mac, s2tex, s2itm, d2itm)`
(`SATS/dynexp2.sats:1905`). We do **not** build it by hand — we obtain it from the
reused environment via `tr12env_free_top(env)` (see §4).

---

## 3. Decisions (locked with the lead architect)

| # | Decision | Choice | Consequence |
|---|---|---|---|
| **D1** | Who owns **symbol resolution**? | **The frontend lowers directly to L2**, performing its own name resolution. Only `trans23` onward is reused. | Maximum control over scoping; the lowering pass is a "`trans12` for PyAST". It **reuses the `tr12env` machinery** (env, scopes, lookup, entity makers) — it does *not* reinvent environments or re-derive prelude entities. See §4. |
| **D2** | How **Python-faithful** is v1? | **Pythonic *skin* over ATS3 semantics.** | v1 = indentation + `def`/`return`/`if`/`elif`/`else`/`match`/`case` + Pythonic call & operator syntax, but the *semantics* stay ATS3: functional, expression-oriented, ATS datatypes & types. Imperative Python (mutating loops, classes/OOP, comprehensions) is **out of v1**. Every v1 construct maps to one L2 node. |
| **D3** | What does milestone order optimize for? | **End-to-end compile to JS first.** | M0 is a tracer bullet that drives a *hand-built* L2 program all the way to runnable JS, de-risking the codegen seam before any parser exists. See §10. |

> **Recorded fallback (not chosen, but cheap insurance).** If the direct-to-L2
> lowering (D1) proves too costly to keep correct as the surface grows, there is a
> strictly-smaller-effort variant: lower PyAST to **L1** (or to L0) and reuse the
> stock `trans01`+`trans12` (`d2parsed_of_trans02`, `xatsopt.sats:132`) to reach
> L2. This trades scoping control for reuse. The component split in this plan
> (lexer / parser / **lowering**) is deliberately the same for both, so only the
> lowering target changes if we ever switch. Do not switch without cause.

---

## 4. Why direct-to-L2 is feasible: reuse `tr12env`, don't reinvent it

The expensive part of binding resolution is **not** the tree-walk — it is the
environment: lexical scopes, the symbol intern tables, overload sets, and
**prelude visibility**. All of that already exists and is reusable. The lowering
pass `pylower` is "`trans12`, but walking PyAST instead of L1," using the **same
`tr12env` API** that `trans12` uses.

The decisive fact that makes prelude names resolve for free:

> A freshly-made `tr12env_make_nil()` already sees the whole prelude, because the
> lookup functions **fall through to the global environments** when a name is not
> found locally or in an enclosing scope:
>
> ```
> tr12env_find_s2itm(env, k):                 // DATS/trans12_myenv0.dats (~1654)
>   local → enclosing → the_sexpenv_pvsfind(k)   // global prelude  (xglobal.dats ~950)
> tr12env_find_d2itm(env, k):                 // dynamic side, same shape
>   local → enclosing → the_dexpenv_pvsfind(k)   // (xglobal.dats ~975)
> ```
>
> The globals are populated **once** by `the_tr12env_pvsl00d()`
> (`DATS/xglobal.dats:1019`), gated by `the_ntime`. The frontend driver calls it
> once at startup, exactly as the stock driver `mymain_main` does
> (`UTIL/xatsopt_tcheck00.dats:217`).

So the frontend **does not** touch `the_sexpenv` / `the_dexpenv` / `the_d2cstmap`
directly and **does not** re-implement scoping. It uses this reused surface:

| Need | Reused `tr12env` API (`SATS/trans12.sats`) |
|---|---|
| lifecycle | `tr12env_make_nil()` · `tr12env_free_top(env): d2topenv` · `tr12env_free_nil` |
| scope push/pop | lambda/fun: `tr12env_pshlam0`/`poplam0` · let/local: `tr12env_pshlet0`/`poplet0` |
| resolve a dynamic name | `tr12env_find_d2itm(env, sym): d2itmopt_vt` (+ qualified `tr12env_qfind_d2itm`) |
| resolve a static/type name | `tr12env_find_s2itm(env, sym): s2itmopt_vt` |
| bind a new var / pattern / arg | `tr12env_add0_d2var` · `tr12env_add0_d2pat` · `tr12env_add0_f2arg` (+ `…lst`) |
| bind a constructor / constant | `tr12env_add1_d2con` · `tr12env_add1_d2cst` · `tr12env_add1_s2cst` |
| name → symbol key | `symbl_make_name(strn): sym_t` (`SATS/xsymbol.sats`) |

`d2itm` (the lookup result) is `D2ITMvar of d2var | D2ITMcon of d2conlst |
D2ITMcst of d2cstlst | D2ITMsym of (sym_t, d2ptmlst)`
(`SATS/dynexp2.sats:600`). Resolving an identifier is: intern the name → `find` →
branch on the `d2itm` → build `D2Evar`/`D2Econ(s)`/`D2Ecst(s)`/`D2Esym0`. This is
the *exact* shape of `trans12_dynexp.dats:1920-2037`, which is the implementation
template (see **LOWERING-MAP.md** §4 and the anchors there).

**Net:** the new symbol-resolution code is the *driving* of `tr12env` (scope
discipline + entity creation order), not the *machinery*. That is a few hundred
lines mirroring `trans12_dynexp.dats` / `trans12_decl00.dats`, not a reimplementation
of the compiler.

---

## 5. Components & package layout

The frontend is **ATS3 code** (it must construct ATS3 AST values, so it has to be
in the language that owns those datatypes). It is built and linked exactly like
the LSP checker: link against the compiler-as-a-library and run on `node`
(primer §10.5). New package under `frontend/`:

```
frontend/
  docs/                         ← this plan
  SATS/
    pylexing.sats               token datatype for the Python surface + lexer entry
    pylayout.sats               INDENT/DEDENT layout algorithm
    pyparsing.sats              PyAST datatypes + parser entry points
    pylower.sats                PyAST → L2 lowering (the "trans12 for PyAST")
    pyfront.sats                driver API: pyfront_d2parsed_of_{fpath,atext}
  DATS/
    pylexing_*.dats
    pylayout.dats
    pyparsing_{dynexp,staexp,decl00}.dats
    pylower_{dynexp,staexp,decl00}.dats     ← split mirrors trans12_*.dats
    pyfront.dats
  TEST/                         golden + differential tests (see §11)
  BUILD/                        linked checker+codegen bundle (mirrors language-server/server/BUILD)
```

The `pylower_*` split intentionally mirrors `srcgen2/DATS/trans12_*.dats` so each
lowering file has its `trans12` counterpart open beside it as the reference.

### 5.1 `pylexer` — tokens with layout (NEW; do **not** reuse the ATS lexer)

ATS3 is **entirely free-form**: its lexer (`atext_tokenize`, `lexing0.sats:461`)
emits whitespace/EOL/comment tokens and then **discards** them in
`lexing_preping_all` (`lexing0_utils2.dats`), so there is *no* layout information
to recover downstream. The Python surface has a different lexical grammar anyway
(`def`, `:` block headers, indentation, `#` comments, `lambda`). Therefore:

- Write a **fresh lexer** producing a **Python-specific token stream** with
  explicit `INDENT` / `DEDENT` / `NEWLINE` tokens (the off-side rule), brackets
  suppressing layout, and continuation handling.
- **Carry real source locations.** Reuse the compiler's `postn`/`loctn` model
  (`SATS/locinfo.sats`): 0-based `(ntot, nrow, ncol)`, `ncol` counted in UTF-8
  **bytes**, newline resets `ncol`. Building `loctn` from real Python spans is
  what makes every downstream diagnostic land on the **Python** source for free
  (see §6.3).
- Layout algorithm in `pylayout`: maintain an indent stack; emit `INDENT` when a
  logical line's indentation exceeds the top, `DEDENT`(s) when it is less; treat
  open `(`/`[`/`{` as suppressing `NEWLINE`/`INDENT` until matched. This is the
  standard CPython tokenizer algorithm; it is self-contained and well-trodden.

### 5.2 `pyparser` — a dedicated surface AST (NEW)

Recursive-descent for statements/declarations, **Pratt/precedence-climbing** for
expressions (the Python parser **owns operator precedence**; this decouples us
from ATS fixity entirely — see LOWERING-MAP §3.4). Output is a **PyAST**: a small
surface datatype family (`pyexp`, `pypat`, `pystmt`/`pydecl`, `pytyp`) that keeps
real locations and is easy to pretty-print for debugging. Parse errors recover by
inserting error nodes and resynchronizing at `NEWLINE`/`DEDENT`, so a broken file
still yields a partial PyAST (matching the compiler's non-fail-fast spirit).

### 5.3 `pylower` — PyAST → L2 (NEW; the core of the work)

Walks PyAST with a `tr12env`, resolving names and constructing L2 nodes
(`d2exp`/`d2pat`/`d2ecl`, `s2exp`, entities). This is where D1's choice lives. The
construct-by-construct mapping and the entity/leaf recipes are in
**LOWERING-MAP.md**; the invariants it must honor are in §6.

### 5.4 `pyfront` — the driver

```
fun pyfront_d2parsed_of_fpath(stadyn: sint, fpath: strn): d2parsed   // file
fun pyfront_d2parsed_of_atext(stadyn: sint, text:  strn): d2parsed   // unsaved buffer (LSP)
```

Mirrors `d2parsed_of_fildats` (`DATS/xatsopt_utils0.dats:268`) but with our three
stages instead of tokenize+parse+trans02. Body shape:

```
pyfront_d2parsed_of_fpath(stadyn, fpath) = let
  val src  = LCSRCfpath(...)                 // source identity for locations
  val toks = pylex_fpath(fpath)              // [NEW] lex + layout
  val pyast= pyparse_eclist(toks)            // [NEW] parse → PyAST
  val env  = tr12env_make_nil()              // reused env (sees prelude via fallthrough)
  val (d2cs, nerr) = pylower_eclist(env, pyast)   // [NEW] lower → L2, count our errors
  val t2penv = tr12env_free_top(env)         // reused: extract top bindings
in
  d2parsed_make_args(stadyn, nerr, src, the_empty_d1topenv(), t2penv, optn_cons(d2cs))
end
```

A second driver `pyfront_d3parsed_of_fpath` simply does
`d3parsed_of_trans23(pyfront_d2parsed_of_fpath(...))`, and the codegen driver runs
the backend on that (see §9).

### 5.5 Frontend selection: the `--py` flag + dependency dispatch

The new frontend is **opt-in and purely additive** — default behavior is the stock
frontend, unchanged. One **combined binary** links the compiler-as-a-library (which
`pyfront` needs anyway) plus `pyfront`, so selecting a frontend is a single branch,
not a second executable.

**The flag changes exactly one decision: which frontend parses the *entry* file.**
Mirror the stock driver `mymain_work` (`UTIL/xatsopt_tcheck00.dats:157`), which today
dispatches by extension (`fpath_satsq` → `d3parsed_of_filsats`, else `…fildats`):

```
val dpar =
  if pyfront_mode || fpath_pyq(fpth)        // `--py`, or a Python extension
    then pyfront_d3parsed_of_fpath(fpth)    // [NEW]
  else if fpath_satsq(fpth)
    then d3parsed_of_filsats(fpth)          // stock, untouched
  else d3parsed_of_fildats(fpth)            // stock, untouched
```

- **Reading the flag:** scan `argv` in our driver and set `pyfront_mode` (the driver
  already loops `argv[3..]`, `xatsopt_tcheck00.dats:180`). **Do not** route `--py`
  through `xatsopt_flag$pvsadd0` — that feeds the *gmacro* env for `#ifdef`/`#ifexp`
  conditional-compilation defines (`xatsopt_utils0.dats:224`), the wrong layer for
  frontend selection.
- Default (`--py` absent, non-Python extension) ⇒ literally the current code path.

**Dependencies dispatch by extension, not by the flag — this is a correctness
requirement.** The prelude and all existing libraries are ATS-surface; a Python
entry file that imports them must still parse *those* with the stock frontend. A
global flag can't be right for a mixed graph. Verified mechanism: transitive
`#staload`/`#include` are parsed on-demand via `d0parsed_from_fpath` (the stock
parser) at `trans01_decl00.dats:462,1515` and `xglobal.dats:758`, keyed by the
dependency's own extension/kind — independent of how the entry file was parsed.

Because we lower the entry file **directly to L2 and skip `trans01`**, the entry
file's imports are **not** loaded by that internal `trans01` path; **`pyfront`'s own
`import` handler triggers the load + env-merge** (reusing the stock loader
`f0_pvsload`, `xglobal.dats:736‑807`: parse → `trans02`/`trans03` → cache → merge
into the env). That handler does the per-dependency dispatch:

- **ATS extension** (`.sats`/`.dats`) → stock loader. ⇒ **Python-imports-ATS works
  with zero compiler changes** (the common case: Python syntax over the existing
  prelude/stdlib). The compiler's internal staload path only ever sees ATS files
  reached from ATS files, so it stays correct and untouched.
- **Python extension** → `pyfront` recursively. ⇒ **Python-imports-Python** works
  because `pyfront` owns the Python part of the graph; this is a localized addition
  in *our* import handler, not a compiler fork.

**Recommendation:** give Python-surface files a **distinct extension** (e.g.
`.pats`/`.pdats`, or `.py`) so dependency routing is unambiguous. Then the
**extension** auto-routes the whole graph, and **`--py`** means "treat the *entry*
file as Python regardless of extension" — the requested opt-in, also useful for
stdin and the LSP unsaved-buffer path (`pyfront_d2parsed_of_atext`).

**Confirmed design rule — the import boundary is one-directional:** Python-surface
code may import ATS-surface modules; **ATS-surface code never imports Python-surface
modules.** The traditional ATS3 frontend therefore never has to parse Pythonic
syntax — it stays completely Python-blind, so the stock lexer/parser/`trans01`/
`trans12` and the internal staload loader need **zero changes** (no fork). The
surface dependency graph is a clean DAG with Python layered *on top of* the ATS
ecosystem. Consequences:

- The whole Python frontend is purely additive code in `frontend/` + one driver
  branch; the compiler proper is untouched.
- Interop is about *parsing*, not *linking*: if an ATS file ever needs to use a
  Python-authored module, the escape valve is an ATS-surface `.sats` **interface**
  for it (hand-written or generated) — ATS imports the interface, not the `.py`.
- An ATS file that does `#staload "foo.py"` is user error for an unsupported combo;
  it simply fails as a parse error. A friendlier diagnostic would be the *only*
  reason to touch the stock loader, and it is **not required** — left out by design.

**v1 scope:** ship `--py` + Python-imports-ATS (no compiler fork). Python-imports-
Python is the follow-up that turns on the recursive branch above.

---

## 6. Invariants the implementer must honor

These are the load-bearing correctness rules. Most are "do what `trans12` does."

### 6.1 One-time global init — call it once, at startup

Before *any* name resolves, the driver must run the same global bootstrap the
stock driver runs (`UTIL/xatsopt_tcheck00.dats:217`):

```
val _ = the_fxtyenv_pvsl00d()      // fixity env (harmless for us; keep parity)
val _ = the_tr12env_pvsl00d()      // loads prelude into the global envs (gated by the_ntime)
```

The keyword/symbol intern tables initialize automatically at module load. Because
we bypass `atext_tokenize`, we inherit **no** lexer-side init — but none is needed
beyond the two calls above (verified: the keyword table is a compile-time-populated
global, independent of our lexer).

### 6.2 Re-entrancy — the LSP is a *resident* process; be safe to re-invoke

**Model corrected (2026-06-20).** Earlier drafts assumed the compiler is strictly
one-shot (process-per-file). The **deno-based `ats-lsp` is now a resident,
long-lived process** (`language-server/server/resident/`): it loads the prelude
**once** at startup and then type-checks every open/edited file **in the same warm
V8 process**, evicting per-URI state between checks (`cache_pruner`, `precheck`, a
dependency graph). The stock `d3parsed_of_fildats`/`_filsats` are already invoked
repeatedly in this resident loop (`xats_lsp_resident.dats:600,630`) without
corruption, so the discipline that makes *that* safe is the discipline the frontend
must also follow — **`pyfront_*` MUST be re-entrant**:

- **Produce a self-contained `d2topenv`** from a *fresh* `tr12env_make_nil()` +
  `tr12env_free_top()` per file. A file's top-level bindings live in its own
  `d2topenv` (carried inside the `d2parsed`), **not** in the global prelude env.
- **Never mutate the global envs** (`the_sexpenv`/`the_dexpenv`/the prelude maps).
  Resolution *reads* them via fall-through (§4); the frontend must not *write* them.
- **Global stamp counters advance monotonically** across checks — this is fine: we
  never depend on specific stamp values, and fresh stamps each call are correct.
- `the_tr12env_pvsl00d()` is idempotent (gated by `the_ntime`), so re-calling the
  global bootstrap on a later check is a no-op.

**M0 must prove this:** check the same hand-built program **twice in one process**
and assert identical results (same `nerror`, same printed L3) with no state
accumulation; a divergence on the 2nd pass is a critical finding. (A batch CLI
compile may still run process-per-file, but the LSP — our primary consumer — does
not, so re-entrancy is a hard requirement.) This **supersedes** the process-per-file
note in memory `ats3-compiler-one-shot` *for the resident LSP path*.

### 6.3 Location fidelity — feed real Python spans into every L2 node

Every L2 node carries a `loctn`, and the stock diagnostics reporter
(`f2perr0`/`f3perr0`) and the LSP harvester read `node.lctn()` to place messages.
If `pylower` threads the **Python source span** into each node's `loctn`, then
**type errors, hovers, and go-to-def all report against the Python source with
zero extra mapping.** This is the single biggest payoff of hooking at L2 with real
locations rather than transpiling to ATS text. Use `loctn_dummy()`
(`SATS/locinfo.sats`) only for genuinely synthetic nodes that have no surface
origin.

### 6.4 Leaf construction — synthesize ATS tokens for literals/identifiers

L2 leaves still wrap ATS `token`s (`D2Eint of token`, `D2Estr of token`, …) or
interned symbols. The lowering synthesizes them:

```
val tok = token_make_node(loc, T_INT01("42"))   // symload `token`; lexing0.sats:352
val e   = d2exp(loc, D2Eint(tok))
```

There are also **unboxed** literal forms that skip the token (`D2Ei00 of sint`,
`D2Es00 of strn`, `D2Eb00 of bool`, …). **Do not use them in v1** — only the
token-based forms (`D2Eint`/`D2Estr`/…) are proven end-to-end through codegen (M0b);
the unboxed path mis-emitted a bare top-level int. Synthesize the token (one call).
Identifiers become `sym_t` via `symbl_make_name`. Full recipes: LOWERING-MAP §2.

### 6.5 Scope & binding order — mirror `trans12` exactly

The subtle correctness rules the lowering must replicate (anchors in LOWERING-MAP §4):

- **Lambda / `def` params:** `pshlam0` → create a `d2var` per param
  (`d2var_new2_name(loc, sym)`) → `tr12env_add0_f2arg` → lower body → `poplam0`.
- **`let`/block:** `pshlet0` → lower decls (they bind) → lower body → `poplet0`.
- **`val`/assignment:** lower the pattern (its `D2Pvar`s are fresh `d2var`s) →
  bind with `tr12env_add0_d2pat` → lower the RHS. For a **recursive** group, bind
  *before* lowering RHS; otherwise *after*.
- **`def` group:** create a `d2var` for each name; if recursive, bind names before
  lowering bodies; build `d2cst_make_dvar` only for **generic** (template) defs.
- **datatype:** create the type `s2cst` (`s2cst_make_idst`) and each constructor
  `d2con` (`d2con_make_idtp`); register with `tr12env_add1_d2con` so later uses
  and patterns resolve. Constructor tags are assigned as `trans12` does.

### 6.6 `t1penv` (the L1 fixity env) — supply an empty one

`d2parsed` carries a `t1penv: d1topenv` produced by `trans01`. We skip L1, so we
supply an **empty** `d1topenv`. `trans23` operates on `t2penv` + `parsed` and does
not consume `t1penv` for type-checking. **Concrete sub-task (M0):** obtain a nil
`d1topenv` — either a `D1TOPENV` nil constructor (`SATS/dynexp1.sats`) or
`tr01env_free_top` on an empty `tr01env` — and confirm nothing downstream reads it.

### 6.7 `npf` (non-proof argument count) — keep it trivial in v1

Application/tuple/record L2 nodes carry an `npf` separating proof args from value
args (`D2Edapp of (d2exp, sint, d2explst)`). The Pythonic skin has **no proof
args**, so always emit `npf = -1` (meaning "no proof bar"), matching how the stock
parser tags ordinary calls. Revisit only if/when a dependent-types surface lands
(M7).

---

## 7. v1 surface language (the Pythonic skin)

The surface is a **Python/Scala fusion, ATS-semantic**: a module is a sequence of
declarations; everything is an expression or a binding; control flow yields values.
The binding/lambda/layout decisions are settled in **SURFACE-GRAMMAR.md**; the table
below is the v1 scope, with precise target constructors in LOWERING-MAP §1.

| Surface | Meaning (ATS3) | Lowers to (L2) |
|---|---|---|
| `let x = e` | immutable binding | `D2Cvaldclst` / `D2Pvar` + RHS |
| `let mut x = e` + reassignment `x = e` | mutable binding (analyzable; reassign-only on `mut`) | desugared away — LOOP-DESUGARING.md |
| `def f(a, b): <block>` | function (recursive group allowed) | `D2Cfundclst` (name→`d2var`, params→`f2arg`) |
| `def f(a: Int) -> Bool: …` | function with type signature | as above + `s2res` from the annotation |
| `(a, b) => e` or `(a) => <block>` | anonymous function (inline **or** block body — same suite as `def`) | `D2Elam0` |
| `return e` / last expr | the block's value | block lowers to its tail expression |
| `f(a, b)` | application | `D2Edapp` (npf = -1) |
| `a + b`, `a < b`, `a and b`, `-a` | operators (Python precedence) | resolve operator name → `D2Edapp` of the `d2cst` |
| `if c: … elif … else …` | conditional **expression** | `D2Eift0` (nested for `elif`) |
| `match e: case P: …` | pattern match | `D2Ecas0` + `d2cls` clauses |
| `(a, b)` / `a, b` | tuple | `D2Etup0` |
| `{l: a, m: b}` record literal | record | `D2Ercd2` |
| `e.field` | field selection | `D2Eproj` (or `D2Edtsel`) |
| `42`, `3.14`, `"s"`, `'c'`, `true`/`false` | literals | `D2Eint`/`D2Eflt`/`D2Estr`/`D2Echr`/`D2Ebtf` |
| `name` | identifier | `D2Evar`/`D2Econ`/`D2Ecst` via `tr12env_find_d2itm` |
| `type Foo = …` / a `data`-style decl | datatype / type def | `D2Cdatatype` (+`d2con`,`s2cst`) / `D2Csexpdef` |
| `from M import *` / `import M` | dependency load | `D2Cstaload` / `D2Cinclude` |
| local block / `where` | local scope | `D2Elet0` / `D2Clocal0` / `D2Ewhere` |
| `while c:` / `for x in it:` (+ `else`) | loops | **desugared** to a tail-recursive `D2Cfundclst` over the accumulator set; backend re-loops it (`while(true)`) |
| `break` / `continue` / `return` (in loops) | structured control flow | desugared via a threaded `flow` result — LOOP-DESUGARING.md |

Imperative control flow (`let mut`, loops, `break`/`continue`/`return`) is **in v1**
but lands as a dedicated **PyAST→PyCore elaborator** (LOOP-DESUGARING.md, milestone
M2.5) that eliminates it before lowering — so `pylower` still sees only the
functional core. The elaborator is done **control-flow-complete in one shot**
(no `break`-less interim) to avoid debt; the JS backend's self-tail-call→`while(true)`
emission (verified — `xats2js/.../intrep1_utils0.dats`, `js1emit_decl00.dats:797`)
makes the desugared loops run as real loops, O(1) stack.

**Explicitly out of v1** (D2): classes/OOP, comprehensions, decorators, async,
`with`, generators. Some have natural ATS lowerings and can be added post-v1; they
are excluded now to keep every remaining construct a one-node lowering or a
self-contained desugaring.

The binding/lambda/layout grammar is settled in **SURFACE-GRAMMAR.md**; the operator
set + precedence table (and the finalized trailing-lambda rule) are an output of
M1–M2 and land there.

---

## 8. The static / type layer

ATS3 is dependently typed; even a Pythonic skin needs a way to write types. v1
scope, smallest-first:

1. **Type annotations** — `x: T`, `def f(a: T) -> U`. Surface type names are
   capitalized (`Int`, `Bool`, `String`, `List`) and resolve through the `pyrt`
   prelude to the ATS prelude's lowercase types (SURFACE-GRAMMAR §5 bridge note).
   Lower `T` to an `s2exp`:
   - a name (`Int`, `Bool`, `String`) → `tr12env_find_s2itm` → `S2Ecst`
     (resolve via the same global fall-through as dynamic names);
   - an application `List[Int]` / `Array(Int, n)` → `S2Eapps`;
   - a function type `(Int) -> Bool` → `S2Efun1`;
   - tuples/records → `S2Etrcd`.
2. **Index terms in types** — the `0` in `Int(0)`: lower an integer literal to
   `S2Eint` (or the wrapped `s2exp_int`). v1 supports literal index terms used in
   prelude types; it does **not** yet parse arbitrary dependent constraints.
3. **Type variables / generics** — `def f[a](x: a) -> a`: create `s2var`s
   (`s2var_make_name`) at the binder, bind them in scope, reference via `S2Evar`.
   Maps onto ATS universal quantification `{a:t@ype}` (`S2Euni0`).
4. **Escape hatch (bridge):** a raw-ATS-static literal form (e.g. `s"{...}"`) that
   embeds an ATS surface type verbatim, lowered by *invoking the stock static
   parser+resolver* on that fragment. This lets advanced dependent types (full
   quantifiers, refinements, proof args) be expressed before the Python surface
   grows native syntax for them. Native dependent-type surface is M7.

The detailed *surface-type → `s2exp`* table is in LOWERING-MAP §1.4.

---

## 9. Codegen to JS (the end-to-end goal, D3)

The "compile to JS" half is **reused**, but wiring it to an *in-memory* `d3parsed`
is the one genuinely **unverified** integration point, so it is de-risked first
(M0) and called out as the top risk (§12, R1).

- The stock JS path normally runs the whole pipeline from a file
  (`xassets/JS/xats2js/xats2js_jsemit01_ats2_opt1.js`, primer §10.4). Our frontend
  instead has a typechecked `d3parsed` already in hand and must invoke **only the
  back half**: `trans3a` (normalize/table top-level templates) → `trtmp3b/3c`
  (template resolution) → IR → `js1emit`.
- **M0 spike task — RESOLVED on paper (2026-06-20); needs a link+run spike.** The
  `xats2js` backend **does** expose an in-memory L3 entry. Verified pass sequence in
  `srcgen2/xats2js/srcgen2/UTIL/xats2js_jsemit01.dats:96-170` (`mymain_work`):
  `d3parsed` → template/read passes (`tread3a`→`trtmp3b`→`trtmp3c`→`t3read0`) →
  `i0parsed_of_trxd3i0(dpar)` → `i0parsed_of_tryd3i0` → `i1parsed_of_trxi0i1` →
  `i1parsed_js1emit(ipar, filr)`. So **outcome (a) holds**: M0b calls this directly
  on our `d3parsed`. The residual work is (i) **linking** the `xats2js` sub-compiler
  pieces — it is a *separate* source tree with its own SATS (`js1emit.sats`,
  `trxd3i0.sats`, …) — into the frontend bundle, and (ii) confirming the template
  passes run cleanly on a hand-built program. Replicate the exact sequence from that
  `mymain_work`.
- **Build & link:** identical recipe to the LSP compiler-linking build
  (primer §10.5): build `srcgen2/lib/lib2xatsopt.js` once with the **`jsemit00`**
  transpiler (not `jsemit01`), `cat`-link the runtime + our `.cats` glue + the
  driver, run with `node --stack-size=8801`. The frontend bundle additionally
  links the `xats2js` backend pieces needed for emission. Closure-`SIMPLE`
  minify as the LSP build does.

Until M0 resolves the backend entry, treat "end-to-end JS" as *planned-but-
unproven*; the typecheck spine (M0a) is provable independently.

---

## 10. Milestones (ordered for end-to-end JS first)

**M0 — Spine tracer bullet (no lexer/parser).** A driver that **hand-builds** the
L2 `d2parsed` for a trivial program (e.g. a top-level `val x = 1` and a `print`
call resolved from the prelude), then:
  - M0a: runs `d3parsed_of_trans23`, asserts `nerror = 0`, prints the result with
    the stock reporter. *Proves lower→typecheck.*
  - M0b: drives codegen on that `d3parsed` to emit `.js` and runs it on `node`.
    *Proves the codegen seam (§9 / R1).*
This de-risks the whole back half before a single token is lexed. It also forces
the build/link recipe to be working first. **Exit:** a hand-built program compiles
and runs as JS.

**M1 — Lexer + layout.** Python token set, INDENT/DEDENT, comments, string/number
literals, real `loctn`s. Golden token-stream tests. **Exit:** representative files
tokenize with correct spans and layout.

**M2 — Parser → PyAST.** Pratt expressions + statement/decl grammar + error
recovery; a PyAST pretty-printer. **Exit:** representative files round-trip
through PyAST; malformed files yield partial PyAST + recovery errors.

**M2.5 — Imperative elaborator + `pyrt` (control-flow-complete).** The PyAST→PyCore
desugaring for `let`/`mut`, `while`/`for`, `break`/`continue`/`return`, and
loop-`else` — done in one shot (full `flow` model + control-pure fast path), with
the tail-position lint and the `pyrt` runtime prelude (`flow`, iterator protocol,
`list_foldleft`). Tested in isolation against a PyCore pretty-printer before
lowering is wired. **Exit:** imperative loops desugar to verifiably self-tail-
recursive core; spec is **LOOP-DESUGARING.md**.

**M3 — Lowering core + first real end-to-end.** `pylower` for: identifiers,
literals, application, operators, `val`, `def` (non-recursive then recursive),
`return`/block-tail, `let`. Wire `pyparse → pylower → trans23 → codegen`. **Exit:**
a real `.py`-surface file (functions + arithmetic + `print`) **compiles to JS and
runs**, and a type error in it reports on the Python source span.

**M4 — Control flow & data.** `if/elif/else`, `match/case` + patterns, tuples,
records, `lambda`, field access. **Exit:** branching/matching programs compile+run.

**M5 — Declarations & types.** Type annotations → `s2exp` (§8.1–8.2), `def`
signatures + return types, datatype/type-def decls (→ `d2con`/`s2cst`), imports
(→ `staload`/`include`), simple generics (§8.3). **Exit:** a multi-file program
with a user datatype and a typed API compiles+runs.

**M6 — Diagnostics & LSP.** Run the existing `…errck` harvester (template
`f3perr0_dynexp.dats`) over our `d3parsed`; because nodes carry Python spans, the
LSP server (already built, see memory `ats3-lsp-project`) serves
diagnostics/hover/go-to-def on the Python surface with little new code. Add
UTF-16 column conversion (primer §5) and error-recovery polish. **Exit:**
hover + diagnostics + go-to-def in the editor on a `.py`-surface file.

**M7 — Advanced & hardening.** Native dependent-type surface (quantifiers,
refinements, proof args) replacing the §8.4 escape hatch; generics/templates;
performance; `.vsix`/CI; broaden the surface toward D2's deferred constructs as
appetite dictates.

---

## 11. Testing strategy

- **Differential oracle (strongest).** Because the Pythonic skin is *semantically
  identical* to ATS3, write each test program **twice** — once in ATS3 surface,
  once in the Python surface — and assert they produce the **same** result at the
  L2/L3 boundary and the **same emitted JS / same diagnostics**. The stock
  `d2parsed_of_fildats` gives the ATS3 oracle; `pyfront_d2parsed_of_fpath` gives
  ours. Equality can be checked structurally (printers) or by running the emitted
  JS and comparing output. This catches lowering bugs precisely.
- **Golden tests** for the lexer (token + span streams) and parser (PyAST dumps).
- **Diagnostics fixtures**: programs with known type errors → assert the reported
  ranges are the Python spans and the messages match the synthesized text.
- **End-to-end run tests**: `.py`-surface → JS → `node` → stdout compared to a
  golden, gated behind the M0/M3 builds.

---

## 12. Risks & open questions

| # | Risk | Mitigation |
|---|---|---|
| **R1** | **In-memory codegen seam (§9).** The in-memory L3 entry **exists** — `i0parsed_of_trxd3i0(d3parsed)` → `…tryd3i0` → `…trxi0i1` → `i1parsed_js1emit` (`xats2js_jsemit01.dats:96-170`). Residual risk: linking the *separate* `xats2js` source tree + running its template passes (`tread3a`/`trtmp3b`/`trtmp3c`) on a hand-built program. | M0b links the xats2js pieces and runs the exact pass sequence from its `mymain_work`. **Downgraded** from "unverified" to "needs a link+run spike". |
| **R2** | The lowering must faithfully replicate `trans12`'s scope/binding **order** (recursion, push/pop, tag assignment). Subtle bugs = wrong resolution, not crashes. | Mirror `trans12_dynexp.dats`/`trans12_decl00.dats` file-for-file; differential oracle (§11) detects divergence. |
| **R3** | `t1penv` / any field `trans23` *does* read from a non-stock `d2parsed`. | M0 verifies a hand-built `d2parsed` type-checks; supply an empty `d1topenv` and confirm (§6.6). |
| **R4** | Operator precedence parity & semantics: Python ops vs ATS prelude ops (e.g. `and`, `%`, `//`, `**`). | Python parser owns precedence (LOWERING-MAP §3.4); map each operator to a named prelude `d2cst`; where no prelude op exists, define one or lower to a function call. Document the operator table in SURFACE-GRAMMAR.md. |
| **R5** | Layout edge cases (implicit line joins in brackets, blank/comment lines, tabs vs spaces, trailing DEDENTs at EOF). | Adopt the CPython tokenizer rules wholesale; fuzz the layout pass; golden tests. |
| **R6** | Token classification driving downstream treatment (alnum identifier vs symbolic operator) — we synthesize `sym_t`s directly, so classification is ours to get right. | Since we resolve names ourselves via `tr12env_find_d2itm`, there is no fixity/operator ambiguity to mis-handle; this is *simpler* than the L0 path. |
| **R7** | Semantic impedance as the surface grows toward real Python (D2 deferral). | Hold the line at "Pythonic skin"; only add constructs with a clean one-node ATS lowering; punt the rest to libraries. |
| **R8** | Compiler internals drift (line anchors, even datatypes) over time. | Anchor on **named** functions/datatypes; the differential oracle re-validates against the live compiler on every test run. |

**Open questions to close early:** (Q1) the exact `xats2js` L3-emit entry (M0b).
(Q2) the nil `d1topenv` maker (M0, §6.6). (Q3) whether `D2Eproj` or `D2Edtsel`
is the right target for `e.field` in the common case (M4). (Q4) the canonical
operator→prelude-`d2cst` table (M3, R4).

---

## 13. LSP synergy — integrating into the deno-based `ats-lsp`

The LSP is now a **resident, in-process Deno server** that already serves
diagnostics/hover/go-to-def/completion for the ATS3 surface end-to-end
(`language-server/server/resident/`; client `language-server/client/`). Because this
frontend (a) hooks at L2 with **real Python locations** threaded through, and (b)
ends at the same `d3parsed` the resident harvester consumes (`harvest_with_deps`),
the Python surface drops in at **three concrete touch-points** — no new
diagnostics/hover/def code:

1. **The dispatch seam (server).** In `xats_lsp_resident.dats`, two validators
   produce the `d3parsed`:
   - `text_validator` (saved file, ~L600):
     `if fpath_is_dats(path) then d3parsed_of_fildats(path) else d3parsed_of_filsats(path)`
   - `live_validator` (unsaved buffer, ~L630):
     `d3parsed_of_trans03(d0parsed_of_pread00(d0parsed_from_atext_named(stadyn,text,path)))`

   Insert a Python branch **above** each:
   `if is_python_surface(path) then pyfront_d3parsed_of_fpath(path)` (resp.
   `…_of_atext(text,path)`) `else …`. The result feeds `harvest_with_deps`
   unchanged. The unsaved-buffer entry is exactly why the driver (§5.4) exposes
   `pyfront_d2parsed_of_atext`.
2. **The build (server bundle).** The resident bundle is cat-linked by
   `server/resident/build.sh` (runtime + `lib2xatsopt.js` + `.cats` glue + driver)
   then packaged by `client/scripts/build-deno.js` →
   `deno compile --v8-flags=--stack-size=8801`. The frontend's `frontend/SATS` +
   `frontend/DATS` must be transpiled (jsemit00) and linked into that bundle, and
   `xats_lsp_resident.dats` must `#staload "pyfront.sats"`. (M0 establishes this
   exact recipe; record it in `ENGINEERING.md` once proven, not before.)
3. **File-type registration (client).** Register the Python-surface extension
   (recommend `.pats`/`.pdats`, or `.py`) as a language id with an
   `onLanguage:…` activation event in `language-server/client/package.json` +
   `extension.ts`, so the resident server is asked to check those files. The
   per-file extension routes the frontend; the `--py` flag (§5.5) remains the
   override for stdin/forced-Python and the LSP unsaved-buffer path.

Re-entrancy (§6.2) is what makes this safe inside the resident loop: each check
builds a fresh env and a self-contained `d2topenv`, so repeated in-process checks of
an edited Python file behave exactly like the stock path. **M6 is therefore mostly
wiring** (the three touch-points above) + UTF-16 column conversion (primer §5).

---

## 14. Quick anchor index (grep targets; lines drift)

| Concern | Stable anchor |
|---|---|
| L2→L3 entry (the hook) | `d3parsed_of_trans23` — `SATS/trans23.sats:254` |
| `d2parsed` record + maker | `d2parsed_make_args`, `D2TOPENV` — `SATS/dynexp2.sats:1905,1972` |
| reused env API | `tr12env_make_nil`/`_free_top`/`_find_d2itm`/`_find_s2itm`/`_add0_*`/`_add1_*`/`_pshlam0`/`_pshlet0` — `SATS/trans12.sats` |
| env→global fall-through | `the_sexpenv_pvsfind`/`the_dexpenv_pvsfind` — `DATS/xglobal.dats`; prelude load `the_tr12env_pvsl00d` — `DATS/xglobal.dats:1019` |
| global bootstrap call site | `mymain_main` — `UTIL/xatsopt_tcheck00.dats:217` |
| L2 nodes + makers | `d2exp`/`d2pat`/`d2ecl` `_make_node` + `d2exp_var`/`_cst`/`_con`/`_dapp` — `SATS/dynexp2.sats`, `DATS/dynexp2.dats` |
| entity makers | `d2var_new2_name`, `d2cst_make_dvar`/`_make_idtp`, `d2con_make_idtp`, `s2cst_make_idst`, `s2var_make_name` — `SATS/dynexp2.sats`, `SATS/staexp2.sats` |
| L2 static nodes | `s2exp_cst`/`_var`/`_apps`/`_fun1_full`, `S2Ecst`/`S2Evar`/`S2Eapps`/`S2Efun1`/`S2Euni0` — `SATS/staexp2.sats` |
| lowering templates (mirror these) | `trans12_dynexp.dats:1920-3283`, `trans12_decl00.dats:2766-3168`, driver `trans12.dats:528` |
| leaf token maker | `token_make_node` (symload `token`) — `SATS/lexing0.sats:352`; literal tnodes `T_INT01`/`T_STRN1_clsd`/… — `SATS/lexing0.sats` |
| location model | `postn`/`loctn`/`lcsrc`, `loctn_dummy` — `SATS/locinfo.sats` |
| diagnostics harvest template | `f3perr0_d3exp`/`auxmain` — `DATS/f3perr0_dynexp.dats` |
| build/link recipe (resident) | `language-server/server/resident/build.sh` + client `scripts/build-deno.js` (`deno compile --v8-flags=--stack-size=8801`) |
| deno LSP dispatch seam | `text_validator`/`live_validator` — `language-server/server/resident/DATS/xats_lsp_resident.dats:600,630` |
| in-memory JS codegen entry | `i0parsed_of_trxd3i0`→`i1parsed_js1emit` — `srcgen2/xats2js/srcgen2/UTIL/xats2js_jsemit01.dats:96-170` |

*All `SATS/`/`DATS/`/`UTIL/` paths above are under `srcgen2/` (the current compiler tree).*

---

*End of plan. The concrete per-construct lowering tables and the leaf/entity
construction recipes are in **LOWERING-MAP.md**.*
</content>
