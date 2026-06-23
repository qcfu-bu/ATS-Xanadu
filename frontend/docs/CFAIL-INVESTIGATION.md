# CFAIL investigation — `XATS000_cfail` on round-tripped compiler files

Investigation of the `Error: XATS000_cfail` crash that the stock compiler-as-library throws
when the M3 bundle reparses the pretty-printed Pythonic for 7 bootstrap compiler files.

- Working dir / `XATSHOME`: `/Users/qcfu/Projects/ATS-Xanadu`
- Raw (readable-trace) bundle: `frontend/BUILD/pyfront-m3.raw.js`
- Probe recipe: `cd frontend && bash build-pp-corpus.sh --stadyn auto --reuse-bundle --no-reparse --out-dir BUILD/_cf <file>`,
  then `node --stack-size=8801 BUILD/pyfront-m3.raw.js <emitted>.pp.pdats`

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
