# CFAIL investigation — `XATS000_cfail` on round-tripped compiler files

Investigation of the `Error: XATS000_cfail` crash that the stock compiler-as-library throws
when the M3 bundle reparses the pretty-printed Pythonic for 7 bootstrap compiler files.

- Working dir / `XATSHOME`: `/Users/qcfu/Projects/ATS-Xanadu`
- Raw (readable-trace) bundle: `frontend/BUILD/pyfront-m3.raw.js`
- Probe recipe: `cd frontend && bash build-pp-corpus.sh --stadyn auto --reuse-bundle --no-reparse --out-dir BUILD/_cf <file>`,
  then `node --stack-size=8801 BUILD/pyfront-m3.raw.js <emitted>.pp.pdats`

---

## UPDATE (2026-06-23 — srcgen2 tail: `nmspace` CLOSED + `local…in…end` body-scope FIXED)

Three more fidelity gaps were pinned and two closed (one rebuild, `frontend/` only).

### (1) `nmspace.dats` (was nerror 4 → **0**, CLOSED) — applied type-con ARITY selection
**Divergence.** `list_vt` is registered under ONE name at TWO arities (`#vwtpdef list_vt(a)` arity-1
AND the datavtype `list_vt(a, n)` arity-2, `prelude/basics0.sats`). Both sorts are *functional*, so
`s2cstlst_pick` (which only prefers a NON-functional s2cst, stock's `s2cst_select$any`) skipped both
and fell back to `s2cs.head()` — the **arity-1** alias. Applied to two args `list_vt[Nmitmlst_vt, N]`,
the stray index `N` was cast to the missing 2nd param's sort → `S2Ecast(N; int0; S2Tnone0)`.
**Verdict: FIDELITY.** Stock's APPLIED-con path uses a DIFFERENT selector — `s2cst_selects_list`
(`f0_a1pp_els2`, trans12_staexp.dats:1186) — that filters the bucket by **arity + per-arg sort
match** (`f0_test1`/`f0_test2`). Our `pylower_typ` `PyTcon` applied arm only did the bare-name pick.
**Fix** (`pylower_staexp.dats`): added `resolve_typ_s2cstlst` (raw bucket, same alias/dual-key lookup
as `resolve_typ`) + `s2cst_select_typ` (ports `s2cst_selects_list` faithfully), and route the
applied arm through it (args lowered first; none0 → fall back to `pytcon_head`; primitives skipped
via `pytcon_is_special` to preserve the `the_s2exp_*1` routing). MWE bypassing our frontend (a
hand-written `type Nmitmlst_vt = list_vt[nmitm]` + 2-arg use) reproduced the exact `S2Tnone0` cast,
and the fix takes it to nerror=0. Added to both corpus lists.

### (2) `trans12_decl00.dats` (was nerror 2 → 3) — `local…in…end` body-suite scope, FIDELITY (fixed)
**Divergence.** ATS `local D1 in D2 end` makes D1 visible to D2. In a FUNCTION BODY our lowering
emitted `private:` + following stmts, but `el_local_decl`/`fl_suite`'s `PySdecl` arm had a
catch-all `| _ => kont` that **silently dropped** a body `PyCprivate` block — so `s2td` (bound in the
private head, used in the next stmt `S2Tbas(T2Btdat(s2td))`) resolved to an UNBOUND name. A
hand-written `.pdats` (`private:` head + a use in the next stmt) reproduced the unbound `y`.
**Verdict: FIDELITY (fixed).** Added a `PyCprivate` arm to both `el_local_decl` (pyelab_core) and
`fl_suite`'s `PySdecl` (pyelab_loop) that backwards-scopes the privates over the rest-of-suite via
`PCEwhere` (→ `D2Ewhere`), the SAME recipe as the existing `PyCtype`/`PyCexcept` arms — privates
visible to D2, not leaking past it = exact `local…end` semantics. This closes the `s2td` bug; the
file's REMAINING residual is the compiler-side `char`-vs-`cgtz` gap below (#3), NOT a regression —
the file was never green here (it also hits the #13a indexing gap).

### (3) `xlibext_pyemit.dats` / `xlibext_jsemit.dats` (nerror 1, both) — `char`-vs-`cgtz`, COMPILER-SIDE
**Divergence.** `fpath_char$strmize`'s `if` joins `strm_vt_nil() : strm_vt(a)` (generic) with
`strn_strmize(…) : strm_vt(cgtz)`, then checks the join against the declared `strm_vt(char)`. The M3
driver leaves the if-join as `strm_vt(cgtz)` and must unify `cgtz = [c|c>0]char(c)` with bare
`char = char_type($none0)` — i.e. reconcile the refined-index `char_type` with the unindexed one.
**Verdict: COMPILER-SIDE (documented, not hacked).** A **hand-written `.pdats`** that bypasses our
frontend entirely reproduces the EXACT nerror=1 with the same `strm_vt(cgtz)` vs
`lazy_vt_vx(strmcon_vt(char_type($none0)))` mismatch — and a variant WITHOUT the `if`-join (single
`strn_strmize` body) passes at nerror=0. So our emission is byte-faithful; the residual is the M3
direct-L2 driver not making both sides HNF + the cgtz/char subtyping the full
`trans03_from_fpath`/solver would do. Stock compiles the original `.dats` (it is live xats2py/xats2js
source). The same `char`/`cgtz` refinement is what blocks `trans12_decl00`'s `strn_tabulate$f1un`
(fopr returns `char`, the template wants `nintlt(n) -> cgtz`). **No frontend change can close these.**

---

## UPDATE (2026-06 — re-diagnosis under the FULL stock pipeline) — C2 was a FRONTEND BUG, now FIXED

The C2 cluster below was *mis-attributed* to a stock/M3-driver limitation. Re-diagnosis under the
current M3 driver (`pyfront_m3.dats` now runs the FULL stock `tread12 -> trans2a -> trsym2b ->
t2read0 -> trans23` sequence, identical to `trans03_from_fpath`) shows C2 was a **frontend
fidelity bug in our type-name resolution**, and it is now **FIXED** in `pylower_staexp.dats`.

### The real root cause — wrong overloaded-`#typedef` selection (a `T2Plam1`, not a `T2Pbas`)

The crash is **not** about a `T2Pbas` head at all. The crashing node is a **`T2Plam1`**
(`s2varlst(*arg*), s2typ` — an *un-applied parametric typedef body*). `tread3a_s2typ`
(`tread3a_staexp.dats:259`) has no `T2Plam1` arm (just like it has no `T2Pbas` arm) and no
catch-all, so a `T2Plam1` falls through its exhaustive `case+` to `XATS000_cfail`.

How a `T2Plam1` reached `tread3a`: a `#typedef T` can be registered **twice under the same name
with different arities** — e.g. in `prelude/basics0.sats`:
```
#typedef nint = [i:i0 | i >= 0] sint(i)      // line 732, sort `type`           (bare, NON-functional)
#typedef nint(n:i0) = [ n >= 0 ] sint(n)     // line 742, sort `(i0) -> type`    (parametric, FUNCTIONAL)
```
A **bare** annotation `x: nint` must select the NON-functional `nint`. Our `resolve_typ_key` /
`resolve_typ_name` / `s2itm_to_typ` (`pylower_staexp.dats`) took a blind `s2cs.head()`, which
picked the **functional** `nint(n:i0)`. Its styp is a `T2Plam1`. `trans2a`'s `f0_annot`
(`trans2a_dynexp.dats`) does `t2p2 = s2typ_hnfiz0(s2exp_stpize(s2e2))` and stores `t2p2` as the
pattern var's styp; the lambda survives into the var's styp, and `tread3a_s2typ` later cfails on it.

Stock never does this: `s2cst_select$any` (`trans12.dats:96-134`, comment *“HX-2019-02: a
non-functional s2cst is preferred over functional ones”*) walks the overload list, **skips every
functional s2cst**, and takes the first non-functional one (falling back to the head only if all
are functional). So stock keeps `nint` as `T2Pcst(nint)` (`tread3a` handles `T2Pcst`).

### Evidence (faithful-vs-fidelity, decisive)

A harness that drives the **stock** `trans03_from_fpath` (from the same raw bundle) on
`fun foo(i0: nint): void = ()`:
```
[STOCK] nerror = 0    T2Plam1(tag9) reached tread3a: 0 times
```
Our pipeline on the equivalent `def foo(i0: nint) -> Void: ()`: cfail, with the crashing node
captured as `[9 (=T2Plam1), <s2var n:int0>, <body T2Papps(sint,...)>]` = the functional
`nint(n:i0)` definiens. Instrumenting `s2typ_hnfiz0` confirmed our pipeline HNFs
`T2Pcst("nint"@basics0.sats:740, sort (i0)->type)` → `T2Plam1`, while stock’s `nint` is the bare
`T2Pcst@basics0.sats:730, sort type` and never becomes a lambda. **Same source, different
selection → fidelity bug, frontend-fixable.**

### The fix (purely additive, `frontend/DATS/pylower_staexp.dats`)

Added `s2cstlst_pick(s2cs)` — a faithful port of stock’s `s2cst_select$any`: prefer the first
s2cst whose `.sort()` is **not** `sort2_funq`, else fall back to the head. Routed the three
type-name resolvers (`resolve_typ_name`, `resolve_typ_key`, `s2itm_to_typ`) through it instead of
`s2cs.head()`. `sort2_funq`/`s2cst_get_sort` come in via `libxatsopt.hats` (already included).

### Result

- `def foo(i0: nint/Nint/sint) -> Void: ()` — was cfail, now **nerror=0**.
- **Files closed (cfail → nerror=0): `lexing0_print0.dats`, `trans01_dynexp.dats`,
  `trans01_staexp.dats`** — all three added to `pp-default-auto.files` + `pp-default-dynamic.files`.
- Strict gate `make -j8 pp-corpus-auto PP_STRICT=1`: **167 / 167** (was 164), exit 0, no regression.
- `xlibext_jsemit.dats` / `xlibext_pyemit.dats`: the cfail is **gone** (was a crash, now a clean
  `nerror=1` graceful type-error). The residual is a *different* gap: the `fpath_char$strmize`
  template result `strn_strmize(...) : strm_vt(char)` vs the template’s expected
  `lazy_vt_vx(strmcon_vt(char))` does not HNF-unify in the M3 driver’s template-result path
  (`strm_vt`/`stream_vt` `#sexpdef` chain + the `cgtz`-vs-`char_type` char refinement). Stock
  closes the original file at `nerror=0`; this is a separate template-result-unification residual,
  not the `T2Plam1` selection bug, and is left uncovered for now.

The historical (now-superseded) two-cluster diagnosis follows below for context.

---

## TL;DR

There are **two distinct root causes**, both surfacing as the *same* stock crash
(`unify00_s2typ` / `tread3a_s2typ` has **no `T2Pbas` arm** — the constructor case is
commented out in stock source, so a base/abstract-type node falls through the
exhaustive-checked `case+` to `XATS000_cfail`).

| Cluster | Files | Root cause | Verdict |
|---|---|---|---|
| **C1 — dropped `#if defq(_XATS2JS_)` branch** | `xatsopt_tcheck00`, `xatsopt_tcheck01`, `xlibext_jsemit` (guard layer) | **Frontend lowering bug** in `pyprint.dats`: the ACTIVE backend branch of an `#if defq(...)` block was silently dropped, so a `#typedef`/`#extern` shim vanished and its later uses resolved to an undefined (`T2Pbas`-headed) type. | **(A) frontend-fixable — FIXED** |
| **C2 — abstract-type alias reaching `unify`** | `lexing0_print0`, `trans01_staexp`, `trans01_dynexp`, `xlibext_jsemit` (residual), `xlibext_pyemit` | **Stock/M3-driver limitation** (the M5a-documented `T2Pbas` issue): a value whose type HNFs to an abstract `gint_type`/`fxitm`/array type is unified by the M3 direct-L2 driver, which (unlike full stock `trans03_from_fpath`) never makes the two sides HNF symmetrically, so a raw `T2Pbas` reaches the armless `unify00_s2typ`. Not fixable from the frontend. | **(B) stock/M3 limitation** |

The C1 fix is committed (purely additive, `frontend/DATS/pyprint.dats` only). It removes the
**crash** for the JS-backend files (cfail → graceful type-error). It does **not** get any file
to `m3_nerror=0`, because every one of the 7 files also uses overloaded `length(...)` / `x[i]`
indexing that the M3 driver can't resolve (the known **#13a** overload-resolution gap,
ENGINEERING.md §4.1) and/or hits C2. **No new corpus files could be added** — none reach 0.

## The crashing stock function

`unify00_s2typ` (impl in `srcgen2/DATS/statyp2_tmplib.dats:1500`) and `tread3a_s2typ`
(impl in `srcgen2/DATS/tread3a_staexp.dats:259`). Both dispatch on `t2p0.node()` with the
**`T2Pbas` arm commented out**:

```
// tread3a_staexp.dats:266-268
(*
|T2Pbas _ => t2p0
*)
```
```
// statyp2_tmplib.dats:1520-1529  (unify00_s2typ outer case)
(*
| T2Pbas(tbs1) => (case+ t2p2.node() of | T2Pbas(tbs2) => (tbs1 = tbs2) | _ => false)
*)
```

`s2typ_node` (`srcgen2/SATS/statyp2.sats:264`) does have a `T2Pbas of sym_t` constructor.
Because the surrounding `case+` is exhaustive-checked and the catch-all `_` arm is *also*
commented out, a `T2Pbas` node has **no matching arm** → the compiled `do/while(false)`
switch reaches its trailing `XATS000_cfail()`.

Readable trace (C1, `xatsopt_tcheck00` before the fix):
```
Error: XATS000_cfail
    at XATS000_cfail (.../pyfront-m3.raw.js:173:11)
    at unify00_s2typ_21236 (...:1175371:19)
    at unify2a_s2typ_10808
    at d2exp_t2pckify_5486
    at trans2a_d2exp_tpck_11531
    at trans2a_d2explst_tpcks_11961
    at f0_dapp_elses_32742          # checking a function-application argument's type
    at f0_dapp_31526
    at trans2a_d2exp_7621
```
Readable trace (C2, bare `nint`/`fxitm`/array annotation — `tread3a` path):
```
Error: XATS000_cfail
    at XATS000_cfail (.../pyfront-m3.raw.js:173:11)
    at tread3a_s2typ_3735 (...:1509222:7)
    at f0_annot_28570               # tread3a-checking a parameter annotation `x: <abstract>`
    at tread3a_d3pat_3880
```
All 7 files crash inside one of these two functions; the trigger differs per cluster.

---

## Cluster C1 — dropped `#if defq(_XATS2JS_)` branch  →  (A) FRONTEND-FIXABLE (FIXED)

### Files
`srcgen2/UTIL/xatsopt_tcheck00.dats`, `srcgen2/UTIL/xatsopt_tcheck01.dats`,
`srcgen2/DATS/xlibext_jsemit.dats` (its first, guard-layer crash).

### Reproducer + responsible construct
`xatsopt_tcheck00.dats:110-123`:
```
#if
defq(_XATS2JS_)
#typedef argv=jsa1sz(strn)
#endif
#if
defq(_XATS2PY_)
#typedef argv=pya1sz(strn)
#endif
#extern fun XATSOPT_argv$get(): argv = $extnam()
... fun argv$loop(argv: argv): void = ... length(argv) ... argv[i0] ...
```
Pyprint **dropped the typedef entirely** — the emitted `.pdats` used `Argv` as a type but
never defined it. `Argv` then resolved (via `resolve_typ`/`ats_type_sym` uncapitalize → `argv`)
to *something* abstract; its HNF reached a `T2Pbas`, and `argv[i]`/`length(argv)` unification
cfailed.

Minimal reproducer (pyprint a tiny file) — emits `def foo(x: Argv) -> Void` with **no**
`type Argv = …`, i.e. the active-branch typedef is gone:
```
#include "./../srcgen2/HATS/libxatsopt.hats"
#if
defq(_XATS2JS_)
#typedef argv=jsa1sz(strn)
#endif
fun foo(x: argv): void = ()
```
With an `#if/#else`, the **wrong** (else/`_XATS2PY_`) branch was emitted — proving the
`_XATS2JS_` guard was being evaluated as **inactive**.

### The bug (in `frontend/DATS/pyprint.dats`)
`pp_walk` correctly intercepts `D0Cifexp` and calls `pp_walk_ifexp(out, active, …)` with
`active = ifexp_guard_active(gexp)`. But `ifexp_guard_active` mis-read the guard argument:

The level-0 parse of `defq(_XATS2JS_)` is
`G0Eapps([ G0Eid0("defq"), G0Elpar(lp, [G0Eid0("_XATS2JS_")], rp) ])` — the argument is a
**parenthesized group `G0Elpar`**, not a bare `G0Eid0` (verified against stock
`trans01_staexp.dats` `f0_apps`, and the `G0Elpar of (token, g0explst, token)` datatype at
`staexp0.sats:408`). The old code did `backend_defq_active(g0exp_lexeme(arg))`, and
`g0exp_lexeme` on a `G0Elpar` falls to its `_ => "?"` arm. So `backend_defq_active("?") =
false`, the active `_XATS2JS_` branch was treated as inactive and **dropped**, taking its
`#typedef`/`#extern` with it.

### The fix (purely additive)
Added `g0exp_guard_arg_lexeme`, which unwraps a single-element `G0Elpar`/`G0Eapps` (and a
pread-error `G0Eerrck`) down to the inner id before reading its lexeme, and routed
`ifexp_guard_active` through it. After the fix the active `_XATS2JS_` branch emits correctly
(`type Argv = jsa1sz[String]` reappears), and the **crash is gone**:

- `xatsopt_tcheck00` / `xatsopt_tcheck01`: `XATS000_cfail` → clean `nerror=9`
  (the residual 9 are #13a: `length`→mis-resolved `strm_length`, `argv[i]`→mis-resolved
  `a1ptr_get$at1`, neither a crash).
- `xlibext_jsemit`: the `XATSOPT_a0ref_set` JS shim now emits (previously dropped); the
  guard-layer crash is fixed. (It then hits a *separate* C2 crash — see below.)

### No-regression
`make -j8 pp-corpus-auto PP_STRICT=1` → **166 / 166** reach `nerror=0` (unchanged). 7 of the
corpus files use `#if defq` and are exercised by the change; none regressed.

---

## Cluster C2 — abstract-type alias reaching the armless `unify`  →  (B) STOCK / M3-DRIVER LIMITATION

### Files
`srcgen2/DATS/lexing0_print0.dats`, `srcgen2/DATS/trans01_staexp.dats`,
`srcgen2/DATS/trans01_dynexp.dats`, `srcgen2/DATS/xlibext_jsemit.dats` (residual, after C1),
`srcgen2/DATS/xlibext_pyemit.dats`.

### Responsible constructs (minimized)
A bare type whose HNF reaches an **abstract `T2Pbas`** head, used where the M3 driver unifies
it. Verified by probing single annotations through the raw bundle:

```
def foo(x: nint) -> Void: ()      # CFAILS   (nint = [i:i0|i>=0] sint(i)  →  gint_type, a T2Pbas)
def foo(x: sint) -> Void: ()      # CFAILS   (sint = sint0 = gint0(sint_k) = gint_type(…), a T2Pbas)
def foo(x: gint) -> Void: ()      # CFAILS
def foo(x: list0) -> Void: ()     # CFAILS
def foo(x: strn1) -> Void: ()     # CFAILS
def foo(x: list_vt) -> Void: ()   # CFAILS
# controls that do NOT cfail:
def foo(x: Sint) -> Void: ()      # OK  (typ_alias maps Sint → the_s2exp_sint0, a T2Pcst)
def foo(x: strn) -> Void: ()      # OK  (typ_alias maps strn → the_s2exp_strn0)
def foo(x: Zorglub) -> Void: ()   # OK  (truly unbound → T2Pnone0, which IS handled)
```

- `lexing0_print0.dats`: `def loop1(i0: nint)` (param annotated `nint`) — first cfail isolated
  by line-bisection to `tnode_fprint`'s `where:` helper. `nint` (`prelude/basics0.sats:732`)
  is the existential non-negative `sint`, HNF = `gint_type` (`#abstype`, `basics0.sats:645`).
- `trans01_staexp.dats` / `trans01_dynexp.dats`: `#typedef g1efx = fxitm(g1exp)` (an alias to
  the **abstract** `fxitm`) used as the result of a function-typed `#extern` and as a template
  arg `list_map$e1nv<g0exp,g1efx>`. Bisected to `trans01_d0qid`'s nested
  `#extern fun f0_main: (!tr01env,g0exp) -> g1efx` + `f0_g0es` (`@inst[…] list_map/e1nv`).
- `xlibext_jsemit.dats` (residual): after C1 re-enables the `_XATS2JS_` shim, its
  `a0ref[A]` / `XATS2JS_a0ref_set` template applications unify an abstract type → same crash.
- `xlibext_pyemit.dats`: defines `XATSOPT_a0ref_set` inside `#if defq(_XATS2PY_)`. The M3/
  frontend pipeline targets the **JS** backend, so this branch is *correctly* inactive (dropped)
  — leaving `XATSOPT_a0ref_set` undefined for the rest of the file (`#impltmp fpath_char$strmize`),
  which then cfails. This file is the **PY-backend variant**; it can only typecheck with
  `_XATS2PY_` active, which would break the JS files. A genuine backend-policy conflict, not a
  pyprint bug.

### Why this is (B), not (A)
The exact same source (`fxitm`, `a0ref`, `nint`, arrays) is used pervasively throughout the
self-hosted `srcgen2` compiler and **compiles fine** through the full stock pipeline. The
difference is the pipeline, not the construct, and it is documented in ENGINEERING.md §4.1
(M5a/M4) + the long comment at `frontend/DATS/pylower_staexp.dats:93-104`:

> An int literal's TYPE is `T2Pcst(the_s2exp_sint0)`. A direct-L2 annotation built from an
> existential/abstract name stpizes to a node that **never HNFs symmetrically** with the
> literal's already-built `T2Pcst`; unify then reaches the abstract `gint_type` (a `T2Pbas`)
> and `unify00_s2typ` has **no `T2Pbas` arm** → a hard `XATS000_cfail`.

Stock avoids it because overload/template/`trans2a` resolution (which lives in
`trans03_from_fpath`, **not** in the `trans23` the M3 driver calls — §4.1 / §4.2) makes the two
sides head-normalize to the same `T2Pcst`/`T2Papps` before deep unify. The M3 reparse driver is
a deliberately reduced subset of passes and does not replicate that, so the frontend **cannot**
fix C2: the `T2Pbas` arms are commented out in *stock* source we may not touch, and there is no
frontend lowering that makes the M3 driver run the missing resolution pass.

### Note: a narrow, M5a-style mitigation exists for the `nint`/`sint` sub-case
`typ_alias` (`pylower_staexp.dats:106`) already maps `Int`/`SInt`/`Sint`/`String`/… to the
concrete `the_s2exp_*0` `T2Pcst` to dodge exactly this crash. Adding `nint`/`Nint`/`sint`
→ `the_s2exp_sint0` would remove the *crash* for `lexing0_print0`'s `loop1(i0: nint)` in the
same spirit. It is **deliberately not included** here because (a) it does not get the file to
`nerror=0` — `rep[i0]` string-indexing still hits the #13a overload gap — and (b) it widens the
"monomorphize-to-`sint`" approximation. It is the obvious next purely-additive step if/when #13a
lands and these files become closeable. The `fxitm`/`a0ref`/array sub-cases have **no** concrete
`the_s2exp_*0` to alias to (they are genuinely opaque abstract types), so they remain pure (B).

---

## Bottom line for scoping

- **C1 is fixed** (the dropped-active-`#if`-branch lowering bug). Crash eliminated for the
  JS-backend files; no corpus regression (166/166).
- **C2 is known-blocked** at the M3-driver level: it needs the #13a overload/template
  resolution pass (and, for the operator/indexing residue, the same #13a). Until #13a lands,
  these 7 files cannot reach `m3_nerror=0`, independent of any frontend change.
- `xatsopt_tcheck00/01` and `xlibext_jsemit` now fail *gracefully* (type-errors, no crash);
  `lexing0_print0`, `trans01_staexp`, `trans01_dynexp`, `xlibext_pyemit` still crash on C2.

---

## RE-DIAGNOSIS 2026-06-23 — `xatsopt_tcheck00/01`: the residual is `jsa1sz` (a JS-prelude abstype) unresolved in the verification prelude, NOT the C2/#13a overload gap

The C2 framing above lumped `xatsopt_tcheck00/01` in with the abstract-alias / `#13a` cluster.
A direct probe (`node --stack-size=8801 BUILD/pyfront-m3.js <emitted>.pp.pdats`, grep
`F2PERR0`) pins it **more precisely**, and the verdict is **FAITHFUL lowering / context-side
(harness-prelude) residual**, the same shape as OVERLOAD-13A — not a desugar bug and not the
armless-`unify` C2 crash (these two files type-*error* gracefully, they do not cfail).

### The single root error (everything else cascades from it)
Both files have (under the `#if defq(_XATS2JS_)` backend branch our pp **correctly** selects):

```
type Argv = jsa1sz[String]          # original: `#typedef argv=jsa1sz(strn)`  (xatsopt_tcheck00.dats:112)
def argv/loop(argv: Argv) -> ...    # length(argv) / argv[i] over an Argv
```

The L2 our frontend emits is **byte-faithful** to stock — `D2Csexpdef(argv; S2Eapps(HEAD;
$list(the_s2exp_strn0)))` — the exact shape stock `trans12_from_fpath` produces for
`#typedef argv=jsa1sz(strn)`. The ONLY divergence is the HEAD: ours is `S2Eerrck(1;S2Enone0())`
(jsa1sz **unbound**) where stock's would be `S2Ecst(jsa1sz)`. The downstream `S2Ecst(argv)` errck
on the param annotation and the `length(argv)` failure are pure cascades of that one unbound head
(`argv`'s type is errck → its uses errck). The `length` overload itself resolves fine — the
`D2Esym0(length; …)` bucket is fully populated (`a1sz_length`, `strm_length`, … all present).

### Why `jsa1sz` is unbound (the real cause — harness prelude, not lowering)
`jsa1sz` is declared **only in the JS-backend prelude** `srcgen1/prelude/DATS/CATS/JS/basics3.dats`
(`abstype jsa1sz_tbox` + `typedef jsa1sz = jsa1sz_tbox`; verified in the lib2xatsopt L1 dump,
`srcgen2/lib/lib2xatsopt.js:4685`). The M3 verification driver's prelude bootstrap
`the_tr12env_pvsl00d` (`srcgen2/DATS/xglobal.dats:1040-1068`) loads only the **stock C-backend**
prelude — `/prelude/basics0.sats`, `xsetup0.sats`, `excptn0.sats`, `prelude_sats.hats` — where the
analogous type is `a1sz` (`prelude/SATS/axsz000.sats:53`), **not** `jsa1sz`. So `jsa1sz`/`pya1sz`
have no static declaration in the reparse context.

Minimal-reproducer matrix (hand-written `.pdats`, no frontend involvement, M3 driver):
- `type Argv = a1sz[String]   ; … length(argv)` → **nerror=0 PASS** (stock C-prelude type)
- `type Argv = jsa1sz[String] ; … length(argv)` → **nerror=8 FAIL** (`S2Enone0` head)
- `type Argv = pya1sz[String] ; … length(argv)` → **nerror=8 FAIL** (`S2Enone0` head)

This isolates the failure to *which prelude is loaded*, independent of our pretty-print/lowering.

### Verdict: FAITHFUL (our side) / context-side (harness prelude) — left uncovered
Our pp is right to select `_XATS2JS_` and emit `jsa1sz`: stock builds `xatsopt_tcheck00.dats`
with the **JS backend** (`xats2js_jsemit00`, Makefile `srcgen2/xats2js/srcgen2/Makefile:69`),
which loads the JS prelude that declares `jsa1sz`. Emitting the inactive `_XATS2PY_` branch
(`pya1sz`) would not help (also unbound), and emitting both re-declares `Argv`. The fix would be
to additionally `f0_pvsload` the JS prelude (`srcgen1/prelude/DATS/CATS/JS/basics3.dats`) into the
M3 global env — a `pyrt_pvsload`-style out-of-band load — but `pyrt_pvsload` and the prelude
bootstrap live in the **M3 pipeline driver `pyfront_m3.dats`, which is out of scope** for this
task (the verification pipeline must not be modified). No green corpus file depends on any
JS-only prelude type (`jsa1sz`/`pya1sz`/`jsobj`/`jshmap`), so these two `tcheck` files are the
first to cross that boundary. **Left uncovered** (harness-prelude gap), exactly like #13a.

> NB: the comment block at `frontend/DATS/pyprint.dats:3641` previously claimed "the M3 reparse
> prelude … is srcgen1's JS one". That is **inaccurate** for the static prelude: `pvsl00d`
> loads the stock C prelude (`a1sz`), so JS-only abstypes like `jsa1sz` are unbound at reparse.
> The comment has been corrected to state this precisely (the active-backend SELECTION is still
> `_XATS2JS_`, which is correct for codegen; only the static-decl availability is the gap).

### Side win (same probe pass): `xglobal.dats` is now GREEN (nerror 0)
`srcgen2/DATS/xglobal.dats` (the prelude-bootstrap module: `Sexpenv = topmap[s2itm]` used as a
param/result type, `the_tsdenv/reset`, `f0_pvsload`) was nerror=12 in an earlier survey; under the
current pipeline (after the non-functional-s2cst-preference + applied-con arity-selector
`s2cst_selects_list` fidelity fixes, commits 6dc752f47 / nmspace) it reaches **m3_nerror=0**.
Its `topmap[s2itm]` typedef-as-param resolves cleanly — those constructs are in the stock C
prelude, so the harness-prelude gap above does not apply. Added to both corpus lists.

---

## UPDATE (2026-06-23 — srcgen2 tail: datatype-head sort, viewtype-ref params, `@impl[..]` type-vars)

Four more fidelity gaps pinned; **two closed** (`lexing0_utils1`, `xatsopt_tmplib`), one nearly
(`xlibext_tmplib` 37→1), one structural-surface-limit (`parsing_tokbuf`). One rebuild, `frontend/`
only. The `T2Bimpr` "improper base" in the early probes was a RED HERRING — `T2Bimpr(knd; sym)` is
the legitimate sort2 representation of the box/vtbx PRIMITIVE sorts (staexp2.sats:201), dumped by
the `f3perr0` reporter only as the *context* of the real errck, not itself the error.

### (1) `lexing0_utils1.dats` (was nerror 5 → **0**, CLOSED) — viewtype-ref `!obj` template-binder USE
**Divergence.** An `#extern fun <obj:vt> NAME(buf: !obj, …)` round-tripped to
`@extern def NAME[Obj: Vt](buf: !obj, …)` — the template-binder DECLARATION capitalized to `[Obj]`
but the param-type USE stayed lowercase `!obj`. So `obj` in `!obj` was an UNBOUND type (not the
bound `Obj`), and the callee template's `<obj>` could not be inferred at a bare call
`lexing_CMNT3_ccbl(buf, …)` → `T2Pvar(Obj)` vs `T2Pnone0()` t2pck failures.
**Verdict: FIDELITY (pyprint).** The IMPL bodies already capitalized `!Obj` (they `push_binders`
the farg sapp raws), but the bodyless `#extern fun` path (`pp_dexp_extern_fundcl`, via
`D0Cextern(D0Cfundclst(tqas, …))`) pushed only the per-fun `{…}` sapp binders, NOT the OUTER
`<obj:vt>` (tqas) ones. **Fix** (`pyprint.dats`): thread the outer `tqag_raw_names(tqas)` through
`pp_dexp_extern_decl → …fundcl_list → …fundcl` and `push_binders` them around the signature.
(Also added the analogous `push_binders` to `pp_dynconst_fun` for the `D0Cdynconst` extern variant.)

### (2) `xatsopt_tmplib.dats` (was nerror 58 → **0**, CLOSED) and
### (3) `xlibext_tmplib.dats` (was nerror 37 → **1**) — `@impl[..]` lowercase type-VARS
**Divergence.** A `#impltmp {k0:t0}{x0:t0} NAME <topmap(k0)>(map) = …` round-tripped to
`@impl[topmap[k0]] def NAME[…](map)` with the instance-arg type vars LOWERCASE; M3 read `k0`/`x0`
as type CONSTRUCTORS rather than the bound template type VARIABLES, so the instance arg resolved to
`S2Enone0`. TWO root causes, BOTH fixed:
  * **(3a) pyprint** dropped the SECOND `D0Cimplmnt0` field — the `s0qaglst` UNIVERSALS `{k0:t0}`
    (the `{…}` binders, distinct from the `<…>` t0qaglst). The dispatch destructured them as `_`,
    so `k0`/`x0` were never registered as binders and stayed lowercase in both the def `[…]` and the
    `@impl[…]`. **Fix:** added `s0qag_names`/`s0qag_raw_names`, threaded the `sqas` field through
    `pp_impl`/`pp_impl_n`/`pp_dexp_impl_local` (+ their 4 `D0Cimplmnt0` destructures), and folded the
    universals into `impl_farg_{names,raw_names}`. This capitalized the vars but left a deeper bug:
  * **(3b) pylower** (`pl_implement`, `pylower_dynexp.dats`): the `@impl[…]` instance-arg types
    (`tia_s2es = pylower_typlst(env, tias_typs)`) were lowered BEFORE the def's type-vars
    (`tv_s2vs`) were added to the env (`tr12env_add0_s2varlst`). So even a correctly-capitalized
    `topmap[X0]` had its `X0` unbound (`S2Enone0`). **Fix:** moved the `pshlam0` + `add0_tqas` +
    `add0_s2varlst(tv_s2vs)` BEFORE the `tia_s2es`/`tias`/`sigargs` computation, so instance args
    lower with the def's type params in scope. (Rebuilt via `build-m3.sh`; `M3: PASS`.)
**Verdict: FIDELITY (pyprint 3a + pylower 3b).** Together these take `xatsopt_tmplib` to nerror=0
and `xlibext_tmplib` to a single residual.

`xlibext_tmplib` residual (1 errck at `mydict_make_nil`, **left uncovered**): the impl RESULT type
is the abstract `mydict` whose rep is `#sexpdef mydict = mydict_tbox` over `#abstbox mydict_tbox`.
The impl body returns `mydict[K0,X0]` (FOLDED) but the impl-target d2cst wants `mydict_tbox[K0,X0]`
(UNFOLDED) → `T2Pcst(mydict)` vs `T2Pcst(mydict_tbox)`. The sibling impls that merely TAKE `mydict`
as a param (`mydict_get_keys`, `mydict_search/opt`, …) all pass; only the abstype-alias in RESULT
position fails. Our pyprint+pylower faithfully reproduce the original structure; this is a t2pck
sexpdef-alias-unfolding asymmetry in the M3 reparse typechecker (result position), not a
pretty-print/lowering gap. **Left uncovered** (not added to the corpus).

### (4) `parsing_tokbuf.dats` (was nerror 7 → 7) — datatype-head sort fixed; per-con existentials gap
**Two parts.** (4a, FIXED) a `datavwtp tkbf0_` (a LINEAR datatype) round-tripped to a BARE `enum`,
which M3 lowered as BOXED (`PCMbox → tbox`) — the head sort came out `S2Tbas(T2Bimpr(1;tbox))`
instead of the linear `vtbx`. **Fix** (`pyprint.dats`): read the `D0Cdatatype` token's
`T_DATATYPE(knd)` sort and emit the matching prefix decorator (`@linear` for VWTPSORT/VTBXSORT,
`@prop` for PROPSORT, `@view` for VIEWSORT) on its own line before `enum` (M3's `mode_of_decos` →
PCMlin/PCMprop/PCMview → the correct head sort). Verified: the head moves from `T2Bimpr(1;tbox)` to
`T2Bimpr(3;vtbx)`. NB: the `dt_kind_deco` `if/else if` chain MUST be wrapped in parens as a
case-clause body and use a `knd_eq(int,int):bool` application (the xats2js bootstrap front-end
rejects a bare `(knd = N)` paren-condition after `else if`, and an unparenthesized multi-branch `if`
as a `=>` clause body).
(4b, **NOT FIXED — surface-syntax limitation, left uncovered**) the constructor carries PER-CON
EXISTENTIAL quantifiers `{n:pos}{i:nat} TKBF0 of (a1ptr(token,n), sint(n), sint(i))`. The Pythonic
`enum` grammar (`casedecl ::= 'case' UIDENT [ '(' type … ')' ]`, pyparsing_decl00.dats) has NO
per-constructor existential syntax, so `n`/`i` are dropped and `SInt[n]`/`SInt[i]` reference unbound
static vars. This needs a NEW grammar + parser + elaborator/lowering feature (bind the con's
existential s2vars), beyond pretty-print/desugar scope. **Left uncovered** (not added to the corpus).
