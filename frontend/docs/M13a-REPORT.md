# #13a SPIKE — Operator resolution via the L2 post-passes

**Verdict: DONE.** Arithmetic + comparison operators now resolve and typecheck at
`nerror=0`; the 4b unbound-name diagnostic is preserved (`nerror>0`, on the
identifier's `.py` span); m1/m2/m2_5 + M3 4a/4b + M4 all green. Purely additive
(`frontend/` only; nothing under `srcgen2/`).

---

## 1. Root cause (verified from source)

The pyfront driver built a hand-constructed L2 `d2parsed` and called
`d3parsed_of_trans23(dpar)` **directly**. `d3parsed_of_trans23`
(`srcgen2/DATS/trans23.dats:104-137`) is ONLY the L2→L3 translation; it does **not**
run the L2 post-passes. The stock file-path driver `trans03_from_fpath`
(`trans23.dats:77-99`) runs them between trans12 and trans23:

```
val dpar = trans02_from_fpath(stadyn, source)   // -> reaches L2
val dpar = d2parsed_of_tread12(dpar)
val dpar = d2parsed_of_trans2a(dpar)            // ← OVERLOAD RESOLUTION (L2) — we SKIPPED
val ()   = d2parsed_by_trsym2b(dpar)            // ← symbol resolution (L2)   — we SKIPPED
val dpar = d2parsed_of_t2read0(dpar)            // ← L2 read/check            — we SKIPPED
// then: d3parsed_of_trans23(dpar)
```

Every operator (`+ - * / == < <= …`) resolves in `pl_var` to a `D2ITMsym`
(overload symbol) and is lowered to `d2exp_sym0(loc, drxp, D1Eid0(sym), dpis)`.
**`trans2a` is the pass that resolves a `D2ITMsym` to a concrete `d2cst`.** Without
it the operator head stayed an unresolved symbol → `trans23` lowered the application
head to `D3Edapp(D3Enone0(); …)` → `tread3a` errcked. Captured before the fix
(operators FAIL):

```
$ node pyfront-m3.js m13a_arith.py        # let a = 1 + 2 / let b = a < 5
[m3] d3parsed nerror (after tread3a) = 1
F3PERR0-ERROR:...m13a_arith.py)@(23(line=2,offs=9)--28...):D3Eerrck(2;D3Edapp(D3Enone0();-1;...))
RESULT: TYPE-ERROR
```

## 2. The fix — pass order added

`frontend/DATS/pyfront_m3.dats`, `pyfront_d3parsed_of_fpath`. Mirrors
`trans03_from_fpath:89-92` exactly:

```
val dpar = pyfront_d2parsed_of_fpath(stadyn, src, text)
val dpar = d2parsed_of_trans2a(dpar)   // overload resolution (L2)
val ( ) = d2parsed_by_trsym2b(dpar)    // symbol resolution (L2)
val dpar = d2parsed_of_t2read0(dpar)   // L2 read/check
d3parsed_of_trans23(dpar)
```

No new staload needed: all three are already exported through `libxatsopt.hats`
(`d2parsed_of_trans2a` / `d2parsed_by_trsym2b` from `SATS/trans12.sats:366,369`;
`d2parsed_of_t2read0` from `SATS/t2read0.sats:162`). Note the commented-out
duplicate sigs in `trans2a.sats:271` / `trsym2b.sats:68` are dead — the LIVE ones
are in `trans12.sats`.

We did **not** add `d2parsed_of_tread12` (the stock driver runs it before trans2a).
Our lowering does not produce the raw nodes tread12 glean-checks; the unbound-name
errck is instead carried end-to-end by the recovery node (§3) and counted by
`tread3a`. Adding tread12 was unnecessary and the build is green without it.

## 3. The wrinkle — unbound-name recovery reconciled (the 4b fix)

**Prior finding (M4-recovery):** a naive add of these passes broke `build-m3` 4b,
because `trans2a` swallowed the unbound-name errck.

**Why it broke.** Our old `pl_var` emitted a *bare* `d2exp_none0(loc)` (`D2Enone0`)
for an unbound name. Two `trans2a` behaviors then conspired to erase the error:
- `trans2a`'s `f0_none0` (`trans2a_dynexp.dats:3546-3552`) keeps `D2Enone0` but
  STAMPS its styp to `void`.
- `trans2a`'s `f0_var` binder path (`trans2a_dynexp.dats:546-574`) gives a binder
  whose styp is `T2Pnone0` a **fresh existential tyvar** (`s2typ_xtv`).

So after trans2a the `let bad = <unbound>` binder had a fresh xtv and the RHS had
styp `void`; `unify(void, xtv)` SUCCEEDS (xtv solves to void) → the `t2pck` errck
that 4b counted **vanished** (`nerror=0`). This is exactly the M4-recovery HARD
LESSON: the old detection was coupled to the binder keeping styp `none`.

**The model — what STOCK trans12 emits.** `trans12_dynexp.dats` `f0_id0_d1eid`
(1950-1981): the unbound `optn_vt_nil()` arm calls `f0_id0_d1sym` (1984-2004), whose
else-branch returns **`d2exp_none1(d1e0)`** (line 2003, `// HX:error`) — NOT
`d2exp_none0`. `d2exp_none1` is `D2Enone1 of (d1exp)`, carrying the original
`D1Eid0(sym)` (and its `.py` loctn).

**The fix.** `frontend/DATS/pylower_dynexp.dats`, `pl_var`'s nil arm now emits the
SAME node trans12 does:

```
| ~optn_vt_nil() => d2exp_none1(d1exp_make_node(loc, D1Eid0(sym)))   // was: d2exp_none0(loc)
```

`D2Enone1` is **immune** to the trans2a erasure because trans2a never rewrites it:
- `trans2a_d2exp` has NO `D2Enone1` arm → falls to `_(*otherwise*)` →
  `d2exp_none2(d2e0)` (`trans2a_dynexp.dats:1352`).
- `trans23_d2exp` has NO `D2Enone1`/`D2Enone2` arm → `_(*otherwise*)` →
  `d3exp_none1(d2e0)` (`trans23_dynexp.dats:1237`).
- `tread3a` has NO `D3Enone1` arm → its `_(*otherwise*)` runs
  `err := err+1; d3exp_errck(lvl0, d3e0)` (`tread3a_dynexp.dats:2077-2083`) — **the
  error is COUNTED**, independent of any binder-styp unification.

The diagnostic now lands on the **identifier span** (`no_such_name`) rather than the
whole RHS, observed end-to-end:

```
D2Eerrck(...m3_typeerr.py)@(22(line=2,offs=11)--34(line=2,offs=23);1;
         D2Enone2(D2Enone1(D1Eid0(no_such_name))))
```

The old `bind_let_styp` / `is_d2enone0` special-case (keep `none` on a `D2Enone0`
RHS) is now inert for unbound names (they are `D2Enone1`, so the binder gets a fresh
tyvar) and is left in place: it is harmless and still guards the rare bare-`D2Enone0`
fallbacks (`pl_app` unary no-op, `PCEerror` poison) from the trcd-vs-none spurious
errck described in M4.

## 4. What `trans2a` required from our nodes

Nothing extra — our directly-constructed L2 nodes already satisfy trans2a:
- Operator references are real `d2exp_sym0(loc, d2rxp_new1, D1Eid0(sym), dpis)`
  nodes (template A's `D2ITMsym` arm), which is precisely what trans2a's overload
  resolver consumes.
- `let`-binders are `D2Pvar(d2var)` with styp `T2Pnone0`, which trans2a's `f0_var`
  fills with a fresh tyvar (so concrete RHS types flow in cleanly — this also
  obsoletes the M4 hand-stamped binder tyvar; both coexist harmlessly).
- The one node trans2a mishandled was the bare `D2Enone0` recovery (§3); switching
  to the stock `D2Enone1` resolved it. **No structural gap remained** — trans2a runs
  cleanly on the hand-built `d2parsed`.

## 5. Verified API table

| symbol | declared in | signature | used |
|---|---|---|---|
| `d2parsed_of_trans2a` | `SATS/trans12.sats:366` | `(d2parsed): d2parsed` | driver |
| `d2parsed_by_trsym2b` | `SATS/trans12.sats:369` | `(d2parsed): void` | driver |
| `d2parsed_of_t2read0` | `SATS/t2read0.sats:162` | `(d2parsed): d2parsed` | driver |
| `d3parsed_of_trans23` | `SATS/trans23.sats` (via libxatsopt) | `(d2parsed): d3parsed` | driver |
| `d2exp_none1` | `SATS/dynexp2.sats:1231` | `(d1exp): d2exp` | pl_var |
| `d1exp_make_node` | `SATS/dynexp1.sats:677` | `(loc_t, d1exp_node): d1exp` | pl_var |
| `D1Eid0` | `SATS/dynexp1.sats:503` | `D1Eid0 of sym_t` | pl_var |

All already reachable through the existing staloads (`libxatsopt.hats` +
`dynexp1.sats`, already in `pylower_dynexp.dats`). No discrepancies found, except the
dead commented-out sigs in `trans2a.sats` / `trsym2b.sats` noted in §2.

## 6. Captured evidence

**Arithmetic/comparison TYPECHECK at nerror=0 (the success criterion):**
```
$ bash frontend/build-m13a.sh --reuse-bundle
>> [valid] .../frontend/TEST/m13a/m13a_arith.py
-- source --
let a = 1 + 2
let b = a < 5
>> nerror (after tread3a) = 0
>> PASS  (m13a_arith LOWERS + TYPECHECKS with operators RESOLVED, nerror=0)
>> #13a: PASS
```
Richer set `+ - * / == <=` (ad-hoc `/tmp/m13a_more.py`) also → `RESULT: PASS (nerror=0)`.

**4b preserved — unbound name diagnostic on its span (nerror>0):**
```
$ node pyfront-m3.js m3_typeerr.py
[m3] d3parsed nerror (after tread3a) = 2
F3PERR0-ERROR:...m3_typeerr.py)@(22(line=2,offs=11)--34(line=2,offs=23)):
  ...D2Enone2(D2Enone1(D1Eid0(no_such_name)))...
RESULT: TYPE-ERROR
>> 4b PASS  (type error reported on the Python source m3_typeerr.py with a line:col span)
```

**Builds green:**
```
>> M1 GOLDEN: PASS
>> M2 GOLDEN: PASS
>> M2.5 GOLDEN: PASS
>> M3: PASS   (4a: .py -> JS -> node runs a=7 b=7 c=7; 4b: type error on the .py span)
>> M4: PASS   (match incl. guarded arm + if/elif/else + tuple + record/field, all nerror=0)
>> #13a: PASS (arithmetic + comparison operators RESOLVE + TYPECHECK at nerror=0)
```

## 7. Files changed (purely additive, frontend/ only)

- `frontend/DATS/pyfront_m3.dats` — inserted the three L2 post-passes before
  `d3parsed_of_trans23`.
- `frontend/DATS/pylower_dynexp.dats` — `pl_var` unbound arm now emits
  `d2exp_none1(D1Eid0(sym))` (the stock trans12 recovery node) instead of
  `d2exp_none0(loc)`.
- `frontend/TEST/m13a/m13a_arith.py` — new arithmetic + comparison test.
- `frontend/build-m13a.sh` — asserts `m13a_arith.py` typechecks at `nerror=0`.

## 8. Impact

Operators are unblocked end-to-end at the typecheck level. This is the gate for
loops and list literals (which lower to operator-bearing + `list_cons`/`list_nil`
chains) and for a clean LSP that reports real type errors on operator expressions.
Codegen of operators remains parked on the pre-existing `$`-template backend gap
(M3-REPORT §6.1) — out of scope for this spike, which targets FRONTEND typecheck.
