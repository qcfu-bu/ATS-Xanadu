# M16 — Desugared loops + list literals LOWER + TYPECHECK at `nerror=0`

**Status: DONE (with two precisely-scoped deferrals — both the pre-existing operator gap,
not pyrt).** `pyrt` now RESOLVES; a `while` loop, a `for` loop (over a list **and** a `range`),
and list literals `[1,2,3]` all LOWER + TYPECHECK at `nerror=0`. All prior builds stay green.

This is purely additive (only `frontend/`; nothing in `srcgen2`/`language-server`).

---

## 1. The pyrt-load mechanism chosen — and why

**Mechanism: load the pyrt INTERFACE `pyrt.sats` into the global env ONCE at driver startup,
via the stock loader `filpath_pvsload`** (the exported wrapper of `f0_pvsload`,
`srcgen2/SATS/xglobal.sats:172` / `srcgen2/DATS/xglobal.dats:736-807,898-901`). The driver
(`frontend/DATS/pyfront_m3.dats`, `mymain_m3`) calls, right after the prelude bootstrap:

```
val () = filpath_pvsload(0(*static*), "/frontend/pyrt/pyrt.sats")
```

This mirrors exactly how `the_tr12env_pvsl00d()` loads the stock prelude
(`xglobal.dats:1040-1068`: `f0_pvsload(0, "/prelude/basics0.sats")` etc.): parse →
`trans01`/`trans12` → merge the resulting `t2penv` (`tenv`/`senv`/`denv`) into the GLOBAL
`the_sortenv`/`the_sexpenv`/`the_dexpenv` via `*_pvsmrgw`. After this, the desugared loops'
pyrt names (`flow_next`, `flow_break`, `iter_open`, `iter_step`, `iter_done`, `iter_more`,
`list_foldleft`, `range`) resolve through the ordinary `tr12env` GLOBAL fall-through —
**no per-file `staload` needed**, so the elaborator's `PCCstaload("pyrt")` lowering correctly
stays a no-op (`pylower_decl00.dats`), and the load happens **once** (a module-level `a0ref`
gate, the same pattern as the compiler's own `the_ntime`).

This is the **preferred** mechanism the task lists, and the one plan §5.5 describes (the
stock ATS-dependency load path). The `--reuse`/global-fall-through framing is identical to how
the prelude itself resolves.

### Why `.sats` (the interface), not `.dats` — the load-bearing M16 finding

The first attempt loaded `pyrt.dats` (`filpath_pvsload(1(*dynamic*), ".../pyrt.dats")`). pyrt's
names resolved (no "unbound"), and the flow **constructors** type-checked — but the pyrt
**functions** errcked on use:

```
D3Et2pck(D3Evar(range(4790)); none; T2Pfun1(sint,sint -> ?))     // range used as an untyped value
```

Root cause: a top-level `fun foo(...) = ...` in a **`.dats`** binds a *local function*
`d2var` — a value with **no exported type**. A USE from another module resolves to `D2ITMvar`,
whose type is unknown at the call site, so `trans23` checks the bare function value against the
expected type and errcks. By contrast, a **`.sats`** `fun foo(...): T` declares a typed
**`d2cst` CONSTANT** (→ `D2ITMcst`), which resolves + type-checks at the call site exactly like
the stock prelude's `strn_append`/`list_cons`.

So `pyrt.sats` (NEW) holds the runtime contract — the `flow(a,r)` and `iterstep(x)` datatypes
(their `d2con`s) **plus the `fun` signatures** — and is what the driver loads. Because M16
verifies **LOWER + TYPECHECK only** (codegen is parked, #13b), the `.sats` interface is
sufficient: `trans23` type-checks the desugared loops against the signatures with no `.dats`
implementation needed. `pyrt.dats` is retained as the (reference) implementation for the
eventual codegen milestone.

---

## 2. What resolved / typechecked (captured evidence)

All run through the M3 driver (`frontend/TEST/m16/*.py`); `nerror` is the authoritative count
the driver prints *after* `tread3a`. `build-m16.sh` automates all five.

**pyrt RESOLVES** (`m16_pyrt.py`):
```
let m = flow_next(0)
let r = flow_break(m)
let xs = range(0, 3)
--
[m16] loading pyrt runtime prelude (filpath_pvsload) ...
[m16] pyrt loaded (flow/iter/foldleft now resolve via global fall-through)
[m3] d3parsed nerror (after tread3a) = 0
```

**A `while` loop** (`m16_while.py`):
```
def f():
    let mut acc = 0
    while acc < 5:
        acc = 9
    acc
--
[m3] d3parsed nerror (after tread3a) = 0
[m3] typecheck OK (nerror=0) -> running codegen
```
(The pure `while` desugars to a plain recursive `loop(acc)`; `acc < 5` resolves because the
literal `5` constrains `acc`.)

**A `for` loop over a list** (`m16_for.py`) — list_foldleft fast path:
```
def sumlist():
    let xs = [1, 2, 3]
    let mut acc = 0
    for x in xs:
        acc = acc + x
    acc
--
[m3] d3parsed nerror (after tread3a) = 0
```
(`list_foldleft`'s typed signature `(xs, a0, (a,x)->a): a` types the folder, so even
`acc + x` over the iteration element resolves.)

**A `for` loop over a `range`** (`m16_for_range.py`):
```
def sumrange():
    let mut acc = 0
    for i in range(0, 5):
        acc = acc + i
    acc
--
[m3] d3parsed nerror (after tread3a) = 0
```

**List literals** (`m16_list.py`):
```
let xs = [1, 2, 3]
let ys = [10, 20]
--
[m3] d3parsed nerror (after tread3a) = 0
```

**Builds still green** (no regressions):
```
>> M1 GOLDEN: PASS      >> M2 GOLDEN: PASS      >> M2.5 GOLDEN: PASS
>> M3: PASS (4a: .py -> JS -> node runs ... ; 4b: type error on the .py span)
>> M4: PASS (match incl. guarded arm + if/elif/else + tuple + record/field ...)
>> #13a: PASS (arithmetic + comparison operators RESOLVE + TYPECHECK at nerror=0)
>> M16: PASS (pyrt RESOLVES via filpath_pvsload; while + for(list/range) loops + list literals ...)
```

---

## 3. The two purely-additive code changes

1. **`frontend/DATS/pyfront_m3.dats`** — the pyrt-load wiring. A `local`-scoped `pyrt_pvsload()`
   with an `a0ref`-gated load-once (mirrors `the_ntime`; `ref<bool>` would hit the same prelude
   `$`-template backend gap the operators do and errck the driver build). Called once in
   `mymain_m3` after `the_tr12env_pvsl00d()`. `filpath_pvsload`/`the_XATSHOME` are already in
   scope via `libxatsopt.hats` (`#staload xglobal.sats`).
2. **`frontend/DATS/pylower_dynexp.dats`** (`pl_list`) — the list-literal fix the #13a operator
   unblock EXPOSED. The empty list `[]` must lower to the zero-arg APPLICATION
   `D2Edap0(list_nil)`, not the bare constructor `d2exp_con(list_nil)` (a function value
   `() -> list(a)` that `trans23` then checks against the expected `list(a)` and errcks —
   `T2Pfun1(...)->list` vs `list`). One-line change; mirrors `pl_app`'s `list_nil()` arm.

New files: **`frontend/pyrt/pyrt.sats`** (the interface — datatypes + fun signatures),
**`frontend/TEST/m16/*.py`** (5 tests), **`frontend/build-m16.sh`**. `frontend/pyrt/pyrt.dats`
gained matching bare `iter_open`/`iter_step` entries (the elaborator emits the bare names;
pyrt's `.dats` previously had only the `_list`-suffixed ones) — kept in sync with the `.sats`
for the eventual codegen milestone.

---

## 4. Deferred (both the SAME pre-existing operator gap — NOT pyrt, NOT M16)

pyrt resolution + the loop/list lowering are complete. Two loop *shapes* still errck, and both
trace to the documented overload-resolution-needs-concrete-types gap (M4-REPORT §"Deferred",
M3-REPORT §6.1 blocker #1), exposed here because loop accumulators are UNTYPED (the
type-annotation gap, M3-REPORT: the elaborator drops `def` param/return annotations):

- **An operator with BOTH operands untyped loop-vars.** The task's exact pure `while` example —
  `while i < n: acc = acc + i; i = i + 1` — desugars to a plain recursive `loop(i, acc)` whose
  params `i`/`acc`/`n` have no concrete type when `trans2a` resolves `acc + i` / `i < n`, so the
  overload stays a `D2Esym0` (unresolved) → errck. The for loop ESCAPES this because
  `list_foldleft`'s typed signature constrains the folder; a `while` has no typed combinator, so
  it needs at least one concrete-typed operand (`acc < 5` works; `acc + i` does not). **Fix =
  the same `trans2a` overload/`$`-template fill the operator work targets, OR carrying the
  dropped type annotations into PyCore so loop accumulators are typed.** Both are
  architect/wire-format work, out of M16's additive scope.

- **A control-bearing `while` in VALUE position** (`while ...: ...; break` where the while is
  not the function tail in flow mode). The M2.5 elaborator's `wh_value` (the fast path) always
  uses `elab_pure`, which CANNOT express `break` → it poisons `"break outside a loop"`
  (verified via the M2.5 PyCore dump). `for_value` HAS the control-purity routing (TASK #14 fix)
  that sends break-bearing loops to the flow path; **`wh_value` lacks the symmetric routing.**
  This is an **M2.5 elaborator** gap (a missing `control_any` check + route-to-`wh_flow` in
  `pyelab_loop.dats:wh_value`), not pyrt and not M16's lowering. When the `while` IS in flow
  mode (a `return`-using function, like the `m25_while_break` golden shape), it routes to
  `wh_flow` correctly and the flow ctors resolve — the residual there is the `flow(a,r)`
  return-type-`r` vs fall-off-`void` unification, also an elaborator/flow-typing concern.

Neither deferral is a pyrt-resolution problem: the flow constructors, `list_foldleft`, `range`,
and `iter_*` all RESOLVE and TYPECHECK (proven by `m16_pyrt` + the passing for-loops).

---

## 5. Verified API notes / discrepancies found

- **`filpath_pvsload(knd0: sint, fpth: strn): void`** (`xglobal.sats:172`) is the public export
  of the `local` `f0_pvsload`; it prepends `the_XATSHOME()` to `fpth` (so the path is
  XATSHOME-relative) and merges the loaded module's `t2penv` into the global env. Works for a
  `.sats` (`knd0=0`) loaded after the prelude bootstrap — the loaded module's own prelude
  `#include` resolves against the already-configured XATSHOME search dirs. **Requires `XATSHOME`
  to be set in the process env** (the build scripts already `export` it; a bare `node …` without
  it fails with `ENOENT /prelude/basics0.sats` because `the_XATSHOME()` returns `""`).
- **Name discrepancy (fixed in pyrt):** the loop elaborator (`pyelab_loop.dats`) emits the BARE
  `iter_open`/`iter_step`, but the original `pyrt.dats` defined only `iter_open_list`/
  `iter_step_list`. `pyrt.sats` declares the bare names (v1's only container is the list, so the
  bare entries ARE the list-backed ones).
- **`.dats fun` → `d2var` vs `.sats fun` → `d2cst`** (§1.2): the decisive fact for the
  dependency-load mechanism. Any future Python-imports-ATS dependency (plan §5.5) that exposes
  *functions* must be reached through a `.sats` interface for its names to type at the call site
  — exactly the "ATS-surface `.sats` interface" escape valve the plan already names (§5.5).
- **M4-REPORT obsolete notes (now fixed by #13a + M16):** "checked bool-position operators
  errck" and "list literals blocked by the `$`-template gap" — `if 1 < 2: …` and `[1,2,3]` both
  now TYPECHECK at `nerror=0` (the #13a `trans2a` pass fills the operator `$`-templates; the
  `pl_list` `D2Edap0` fix handles the empty-list constructor).

---

## 6. Standards compliance

- **Purely additive:** only `frontend/` (`pyfront_m3.dats`, `pylower_dynexp.dats`, `pyrt.dats`,
  `pyrt.sats`, `TEST/m16/*`, `build-m16.sh`, this report). Nothing in `srcgen2`/`language-server`.
- **Re-entrant:** the pyrt load is gated by a module-level `a0ref` (load-once), so a resident
  re-invocation does not double-merge pyrt into the global env. The driver builds a fresh
  `tr12env` per file; pyrt lives in the global env (read via fall-through), never re-merged.
- **Verified APIs; real `loctn`** preserved by the unchanged elaborator/lowering. Codegen NOT
  run (LOWER + TYPECHECK / `nerror=0` only, per the brief).
