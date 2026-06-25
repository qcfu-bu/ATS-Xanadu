# M5a — type-annotation carrying: typed `def` + typed loop LOWER + TYPECHECK at `nerror=0`

> **Status: DONE — both (a) and (b) landed.** The surface type annotations the elaborator used
> to DROP (M3-REPORT §4) are now THREADED through PyCore into L2 and RESPECTED. A typed `def`
> typechecks with its annotations (its `x + x` resolves), and a typed multi-accumulator `while`
> loop typechecks (the M16 untyped-loop-var deferral is FIXED). Annotations remain OPTIONAL: an
> unannotated binding/param lowers exactly as before. All prior builds stay green
> (m1/m2/m2_5/m3/m4/m13a/m16). Purely additive — only `frontend/`.

---

## 1. What type fields were added (PyCore, `frontend/SATS/pycore.sats`)

Three additive, OPTIONAL fields, using the project's monomorphic-option style (`pytypopt =
PyTypNone() | PyTypSome(pytyp)`, reused from the PyAST):

| Node | Before | After (M5a) |
|---|---|---|
| `PCFundcl` | `(loctn, strn, list(strn), pcexp, bool)` | `(loctn, strn, list(strn), `**`list(pytypopt)`**`, `**`pytypopt`**`, pcexp, bool)` |
| `PCElet` | `(loctn, pcpat, pcexp, pcexp)` | `(loctn, pcpat, `**`pytypopt`**`, pcexp, pcexp)` |
| `PCElam` | `(loctn, list(strn), pcexp)` | `(loctn, list(strn), `**`list(pytypopt)`**`, pcexp)` |

- `PCFundcl`'s new `list(pytypopt)` is PARALLEL to its `params` (same length, one per param,
  `PyTypNone()` for an unannotated param); the new `pytypopt` is the function's optional return
  type. `PCElam`'s `list(pytypopt)` is likewise parallel to its param names. `PCElet`'s
  `pytypopt` is the binding annotation (`let p : T = e`).
- The PyCore PRINTER (`pyelab_print.dats`) renders them only when present: `name:Type` for a
  typed param, ` -> Type` for a return, `:Type` for a `let`. Untyped code prints identically to
  before, so the only golden churn is the 9 typed-`def` headers (§5).

---

## 2. How def / let / loop-accumulator annotations flow through

### 2a. Elaborator (`frontend/DATS/pyelab_*.dats`) — stop dropping, start threading

- **`def`** (`pyelab_decl.dats`, top level; `pyelab_core.dats`/`pyelab_loop.dats`, nested
  `PySdecl`): `PyCfun`'s params → `param_types_*` (the parallel `list(pytypopt)`), its `-> T` →
  the `PCFundcl` return field. Previously `param_names_d` dropped each `PyParam`'s type and the
  `_ret` was discarded (M3-REPORT §4).
- **`let`** (`pyelab_core.dats el_pure`, `pyelab_loop.dats fl_suite`): `PyDlet`'s `pytypopt`
  annotation → the `PCElet` field. An SSA-rebind `PCElet` (from a reassignment) carries
  `PyTypNone()`.
- **`lambda`** (`pyelab_core.dats`): `PyElam`'s params → `el_param_types`.
- **Loop accumulators (the M16 fix)** — a NEW threaded `muttypes` map records every
  `let mut x : T` annotation (`pyelab.sats`: `muttypes = list(@(strn, pytyp))`, with
  `muttypes_add`/`_find`/`accs_types` in `pyelab_util.dats`). It is threaded ALONGSIDE the
  existing `muts` nameset through `el_pure` / `fl_suite` / the loop combinators. When a loop is
  synthesized, `accs_types(accs, mts)` produces the loop param's parallel type list, so the
  generated `loop`'s accumulator params are TYPED from the user's `let mut … : T`. (The `for`
  loop's threaded `it` slot is left untyped — its type flows from `iter_open`; the fold fast
  path types only the accumulator param, leaving the element param inferred.)

### 2b. Lowering (`frontend/DATS/pylower_*.dats`) — consume the carried types

- A typed param → an annotated f2arg binder `D2Pannot(D2Pvar, s1exp_none0(loc), <s2 T>)` via the
  pre-built `pylower_typ` (`pl_one_param`/`pl_params_typed` in `pylower_dynexp.dats`). trans2a's
  `f0_annot` reads the `s2exp` → the binder's `styp`, so a typed `x` makes `x + x` resolve (the
  `s1exp` "given" part is a benign `s1exp_none0` placeholder — trans2a/trans23 type from the
  `s2exp`, never the `s1exp`; verified trans2a_dynexp.dats f0_annot).
- A return type → the d2fundcl's `s2res` via `pylower_sres` (`pl_sres`); `PyTypNone() →
  S2RESnone()`.
- A typed `let` → the RHS wrapped in `D2Eannot(rhs, s1exp_none0, <s2 T>)` (PCElet lowering).

### 2c. The N-accumulator loop calling-convention fix (also unblocks UNtyped 2-acc loops)

A generated `loop` is CALLED with a SINGLE argument that is the accumulator TUPLE (`accs_tuple_exp`
= a bare var for one acc, an N-tuple for N>1) and its result is destructured by `accs_tuple_pat`.
But the loop's params were lowered FLAT (N separate params), so a 2+-acc loop received its single
tuple arg against the FIRST param only — a pre-existing arity mismatch that kept even UNtyped 2-acc
loops failing (this is the structural half of the M16 deferral). `pl_loop_params` now lowers a
loop with 2+ accumulators as ONE TUPLE parameter `(acc, i)` (with the per-element type
annotations riding on the tuple's binders), matching the call. One acc stays a bare param (1 arg =
1 param, already correct). Net: typed AND untyped 2-acc loops now typecheck.

---

## 3. The load-bearing API discrepancy: built-ins alias to `the_s2exp_*0`, NOT `int`/`bool`

`pylower_typ`'s capitalized-built-in alias (`pylower_staexp.dats typ_alias`) was changed from
`Int→int` (M3-REPORT) to **`Int→the_s2exp_sint0`** (and `Bool→the_s2exp_bool0`,
`String→the_s2exp_strn0`, `Char→the_s2exp_char0`, `Float→the_s2exp_dflt0`).

**Why (verified by a hard crash):** an int literal's TYPE is `the_s2typ_sint() =
T2Pcst(<the_s2exp_sint0 s2cst>)` (statyp2_inits0.dats). The surface `int` is a sexpdef chain
`int = sint0 = gint0(sint_k) = [i:i0] gint_type(sint_k, i)` — an EXISTENTIAL over the abstract
`gint_type`. A direct-L2 annotation built from `int` stpizes to `T2Ps2exp(int)` and never HNFs
symmetrically with the literal's already-built `T2Pcst`; `unify00_s2typ` then compares the
literal's HNF (which reaches the abstract `gint_type`, a `T2Pbas`) and has NO `T2Pbas` arm → a
hard `XATS000_cfail` JS throw (reproduced: `def f() -> Int: 1` crashed before this fix). Aliasing
to `the_s2exp_sint0` makes the annotation the SAME `T2Pcst(the_s2exp_sint0)` the literal carries,
so unify short-circuits on stamp equality (`s2c1 = s2c2`) with no deep HNF. These `the_s2exp_*0`
names are registered in the global sexpenv by `prelude/INIT/srcgen2_xsetup0.sats` (loaded in the
prelude bootstrap) and resolve via the ordinary `tr12env_find_s2itm` fall-through.

> This was the first time `pylower_typ`'s output reached trans23 (M3 deferred all type lowering;
> "built but not fed" — M3-REPORT §4). The crash was therefore a latent `pylower_typ` bug, fixed
> here, not a regression.

### Other verified API notes

- `D2Pannot`/`D2Eannot of (d2pat/d2exp, s1exp(*given*), s2exp(*trans*))` — the `s1exp` is a
  placeholder; `s1exp_none0(loc)` (staexp1.sats, NOT in `libxatsopt.hats`, so
  `#staload staexp1.sats` was added to `pylower_dynexp.dats`). `loc_t` ≡ `loctn` (both
  `loctn_tbox`), so a `loctn` is accepted directly.
- `tr12env_add0_d2pat` recurses into `D2Ptup0` and `D2Pannot` (trans12_myenv0.dats:2051/2065),
  so the tuple-of-annotated-binders loop parameter correctly registers `acc`/`i` for the body.
- `s2exp_stpize` `f0_impr` has an `S2Ecst → T2Pcst` arm; a non-impredicative sort yields
  `T2Pnone0` ("matches anything") — both are crash-safe; only the existential-`int` HNF path was
  not.

---

## 4. Deferred / not changed

- **Module-level `let x : T = e`** (`PCCval`): `PCCval` carries no annotation field (it is not on
  the typed-`def`/typed-loop path and an inferred module binding already typechecks). Adding it
  would widen the wire format with no test win; left for a later milestone. (An unannotated
  module-level `let` is unaffected.)
- Surface type forms `pylower_typ` still places as benign `s2exp_none0` (function/tuple/record
  types, dependent indices) are unchanged from M3 — only NAME types (the built-ins + applied
  cons like `List[Int]`) carry through. A `List[Int]` param annotation lowers to
  `s2exp_apps(list, [the_s2exp_sint0])`; an unresolved con name stays a benign placeholder
  trans23 reports on the span. (Tests use `Int`/`Bool`/`String`; `m25_for_break` etc. carry
  `List[Int]`/`Grid`/`Pair` through to PyCore — see the goldens — exercising the carrying even
  where the L2 type is a placeholder.)

Nothing about the two task wins is deferred.

---

## 5. Captured evidence

### [E1] All M5a tests at `nerror=0` (the M3 driver's post-`tread3a` authoritative count)

```
>> [valid] frontend/TEST/m5a/m5a_def.py
-- source --
def double(x: Int) -> Int:
    x + x
>> nerror (after tread3a) = 0
>> PASS  (m5a_def LOWERS + TYPECHECKS with its annotations, nerror=0)

>> [valid] frontend/TEST/m5a/m5a_loop.py
-- source --
def sum_upto(n: Int) -> Int:
    let mut acc: Int = 0
    let mut i: Int = 0
    while i < n:
        acc = acc + i
        i = i + 1
    acc
>> nerror (after tread3a) = 0
>> PASS  (m5a_loop LOWERS + TYPECHECKS with its annotations, nerror=0)   <-- M16 deferral FIXED

>> [valid] frontend/TEST/m5a/m5a_unannotated.py
-- source --
let x = 1
let y = x
>> nerror (after tread3a) = 0
>> PASS  (m5a_unannotated LOWERS + TYPECHECKS — annotations are OPTIONAL, nerror=0)

>> M5a: PASS
```

### [E2] (a) `def double(x: Int) -> Int: x + x` — the typed `x` makes `x + x` RESOLVE

Before M5a the param was UNTYPED (PyCore dropped the annotation), so `x + x` stayed an unresolved
`D2Esym0` overload → errck. Now the param lowers to `D2Pannot(D2Pvar(x); S2Ecst(the_s2exp_sint0))`,
trans2a types `x` as sint, the `sint_add$sint` overload resolves, and the return checks against
`Int`: **`nerror=0`**.

### [E3] (b) Typed 2-accumulator `while` loop — the M16 untyped-loop-var deferral FIXED

The `let mut acc: Int`/`let mut i: Int` annotations flow into the synthesized loop's accumulator
param types (`D3FUNDCL(loop; F3ARGdapp(0; [(acc,i) : (sint,sint) tuple param])))`), so `acc + i`
(both operands now typed) resolves; the N-acc loop now takes one tuple param matching its single
tuple call argument: **`nerror=0`**. (Verified the UNtyped 2-acc loop `def sum_upto(n): …` also
now reaches `nerror=0` — the calling-convention fix is type-agnostic.)

### [E4] (c) + edge cases — annotations are OPTIONAL, partial annotation works

```
m5a_unannotated  (let x = 1; let y = x)                          nerror=0
partial-annot    (def add(x: Int, y) -> Int: x + y)              nerror=0   (y inferred)
typed lets       (let a: Int = 5; let b: Int = a + a)            nerror=0   (D2Eannot path)
String-typed def (def g(s: String) -> String: s)                nerror=0
typed loop+if    (typed 2-acc while with an inner if)            nerror=0
typed 1-acc loop (def count_upto(n: Int) -> Int: …)              nerror=0
```
No `XATS000_cfail` in any case (the `the_s2exp_*0` aliasing fix).

### [E5] All prior builds stay GREEN (no regressions)

```
>> M1 GOLDEN: PASS (all snippets match)
>> M2 GOLDEN: PASS (all snippets match)
>> M2.5 GOLDEN: PASS (all snippets match; §6 tail-lint clean; §3.1 fast-path verified)
>> M3: PASS (4a: .py -> JS -> node runs with correct bindings; 4b: type error on the .py span)
>> M4: PASS (match incl. guarded arm + if/elif/else + tuple + record/field … nerror=0)
>> #13a: PASS (arithmetic + comparison operators RESOLVE + TYPECHECK at nerror=0)
>> M16: PASS (pyrt RESOLVES; while + for(list/range) loops + list literals … nerror=0)
```

The 9 M2.5 goldens were regenerated (`build-m2_5.sh --accept`): each change is ONLY the typed
`def` header now showing its threaded param/return types (e.g.
`(fun count (params n:(Tcon Int…)) -> (Tcon Int…)`), proving the annotations now survive into
PyCore. Bodies are structurally unchanged.

---

## 6. Files (all `frontend/`, purely additive)

- **PyCore:** `SATS/pycore.sats` (the 3 type fields), `DATS/pyelab_print.dats` (render them).
- **Shared:** `SATS/pyelab.sats` + `DATS/pyelab_util.dats` (the `muttypes` map type + helpers;
  loop-combinator signatures gained `mts`).
- **Elaborator threading:** `DATS/pyelab_decl.dats`, `DATS/pyelab_core.dats`,
  `DATS/pyelab_loop.dats` (def/let/lambda/loop-accumulator annotation threading);
  `DATS/pyelab_diag.dats`, `DATS/pyelab_lint.dats` (arity updates for the new constructors).
- **Lowering:** `DATS/pylower_dynexp.dats` (typed params/let, the N-acc loop tuple param,
  `#staload staexp1.sats`), `DATS/pylower_staexp.dats` (the `the_s2exp_*0` built-in aliasing).
- **Tests:** `TEST/m5a/{m5a_def,m5a_loop,m5a_unannotated}.py`, `build-m5a.sh`.
- **Goldens:** `TEST/m2_5/*.golden` regenerated (def headers now carry types).

## 7. Reproduce

```bash
XATSHOME=/Users/qcfu/Projects/ATS-Xanadu bash frontend/build-m5a.sh
# (rides the M3 driver; reuses cached backend libs. --reuse-bundle to skip the driver rebuild.)
```
