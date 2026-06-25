# M4 — Control-flow & data lowering (PyCore → L2)

**Scope (R1.5 — CODEGEN PARKED):** M4's exit is **LOWER + TYPECHECK + DIAGNOSTICS-ON-PYTHON-
SPANS**, verified through the M3 driver path (`frontend/DATS/pyfront_m3.dats`): build a
`d3parsed`, run `tread3a` (the driver does this internally), assert `nerror=0` for valid
programs and a diagnostic on the exact `.py` span for the invalid one. We do **not** run JS for
arithmetic/functions (the two backend-infra blockers from M3-REPORT §6.1 are still in force).

**Outcome:** GREEN. `match` (literals/tuples/wildcards **incl. a guarded arm**), `if/elif/else`,
**tuples**, and **record + field projection** all LOWER + TYPECHECK to `nerror=0`. The invalid
program reports a diagnostic on the exact `.py` span. All prior builds stay green:
`build-m1` PASS, `build-m2` PASS, `build-m2_5` PASS, `build-m3` PASS (4a + 4b), `build-m4` PASS.

---

## 1. What the preserved WIP already had (assessed, kept, built on)

The M4-recovery baseline's `pylower_dynexp.dats` was **already structurally complete** for every
M4 construct (this was more than the brief implied). Verified correct and kept verbatim:

- **`PCEcase` → `D2Ecas0`** with per-arm `d2cls` clauses (`pl_arm`/`pl_armlst`): the scrutinee is
  lowered in the OUTER scope; each arm builds a guarded-pattern (`d2gpt`) then a matched clause
  (`D2CLScls`). An **unguarded** arm → `D2GPTpat(d2p)`; a **guarded** arm → `D2GPTgua(d2p, [guard])`
  — ATS's native guarded clause with the correct **fall-through** to the next arm (architect
  ruling iv). The guard is lowered in its own scope (`pshlam0` + `add0_d2pat` so the pattern vars
  are visible to the guard, then `poplam0`); the body in a second scope (`pshlam0` + `add0_d2gpt`).
  This mirrors `trans12`'s clause handling exactly.
- **`PCEif` → `D2Eift0(c, Some t, Some e)`** (a value; elif nests).
- **`PCEtup` → `D2Etup0(-1, …)`**, **`PCErec` → `D2Ercd2(tok, -1, [D2LAB(LABsym l, e), …])`**
  (NAME labels), **`PCEfield` → `D2Eproj(tok, d2rxp, LABsym name, e)`**, **`PCElist`** → a prelude
  `list_cons`/`list_nil` chain, plus full pattern lowering (`PCPcon`/`PCPtup`/`PCPrec`/`PCPlit`/
  `PCPvar`/`PCPwild`).

**The preserved code COMPILED but several constructs did NOT typecheck** when actually run through
the driver (the WIP was never exercised E2E). M4's real work was finding *why* and fixing it with
**targeted, purely-additive** lowering changes (no `trans2a` pre-pass — that breaks 4b).

---

## 2. The crux discovery — `d3parsed_of_trans23` does NOT run `trans2a`

M3-REPORT §5.3 claimed "`d3parsed_of_trans23` internally runs trans2a + trsym2b". **This is
wrong** (verified `trans23.dats`): those passes live in `trans03_from_fpath` (`trans23.dats:89-90`),
the *from-file* driver. `d3parsed_of_trans23` (`trans23.dats:104-137`) goes **straight** from the
directly-constructed `d2parsed` to `trans23_d2eclistopt` with **no `trans2a`**.

`trans2a` is the literal-TYPE-stamping + binder-typing + overload pass. Skipping it means our
directly-built L2 leaves carry **`styp = T2Pnone0`** and our binders are **untyped**, which is fine
for synthesis-only programs (`let a = 7` — M3's only E2E) but breaks the moment trans23 **checks**
a node against a concrete type. M4 is the first milestone that does checked positions (guards,
tuples bound to lets). We **cannot** just run `trans2a` (the HARD LESSON: it mutates the
`d2exp_none0` recovery node and silently kills the 4b unbound-name errck). So M4 **replicates the
specific `trans2a` effects each construct needs, by hand, at lowering time** — and ONLY those.

### 2.1 Boolean literal styp (the guard fix)
A `case`-guard is checked against `bool` (`trans23_d2gua`, `trans23_dynexp.dats:3189`
`the_s2typ_bool`). An unstamped `D2Ebtf` carries `T2Pnone0` → `unify(none, bool)` fails →
`D3Et2pck` errck. **Fix:** stamp the boolean literal's styp with `the_s2typ_bool()` in `pl_lit`,
mirroring `trans2a_dynexp.dats` `f0_btf` (1395-1407). Bool is the **only** literal we stamp —
int/float/string/char are left UNSTAMPED on purpose (they flow in synthesis position; a precise
stamped type — e.g. the singleton `sint(7)` from `intrep_s2typ_xint` — OVER-CONSTRAINS and
spuriously fails `unify(sint0, none)` against an untyped `let`, regressing `m3_run`'s `let a = 7`;
observed and reverted).

### 2.2 Val-binder styp (the tuple/record fix) — SELECTIVE to preserve 4b
`trans23_d2valdcl` (`trans23_decl00.dats:883`) checks a `val p = rhs` RHS against `dpat.styp()`
(= the binder d2var's styp). `trans2a` `f0_var` (546-574) gives every binder a fresh existential
tyvar so the RHS type flows in; we don't run it, so our binder is `none` → a CONCRETE-typed RHS (a
tuple synthesizing `trcd`) fails `unify(trcd, none)` (observed: `let p = (1,2,3)` errck).

A **blanket** fresh-tyvar binder fixes tuples **but REGRESSES 4b**: an unbound name lowers to
`d2exp_none0` (styp `void`); with a `none` binder `unify(void, none)` FAILS → the errck 4b counts;
with a fresh tyvar `void` unifies → the errck VANISHES. (This is the HARD LESSON manifesting via a
different mechanism — confirmed: blanket binder made 4b report `nerror=0`.)

**Fix — `bind_let_styp(d2p, d2rhs)` (new SATS entry, shared by `PCElet` and `PCCval`):** a
`D2Pvar` binder gets a fresh `s2typ_xtv(x2t2p_make_lctn(loc))` **EXCEPT** when the lowered RHS is
the bare `D2Enone0` recovery node — there the binder is left `none` so the unbound-name errck
survives. This restores stock binding semantics for real values while preserving 4b **verbatim**
(re-verified: 4b still reports `nerror=1` on the `.py` span). Non-`D2Pvar` patterns (tuple/record)
carry their own structural styp, so they need no stamp.

### 2.3 Record kind-token (the crash fix)
`tok_rec` built the record token as `T_LBRACE`. trans23's `f0_rcd2` does a **partial** `case-`
over `T_TRCD20(n)` ONLY (`trans23_dynexp.dats:2230-2242`) — a `T_LBRACE` token caused a **hard
crash** (inexhaustive match in `trans23_d2valdcl`). **Fix:** build the record token as
`T_TRCD20(0)` (→ `TRCDflt0`, the flat/unboxed record the Pythonic `{l=e,…}` lowers to). Same token
now feeds both `D2Ercd2` (literal) and `D2Prcd2` (pattern).

---

## 3. Verified API table (vs the LIVE SATS)

| API | SATS | Used for |
|---|---|---|
| `d2exp_set_styp(d2e, t2p)` | `dynexp2.sats:1221` | stamp the bool literal's styp |
| `d2var_set_styp(d2v, t2p)` | `dynexp2.sats:574` | give a val-binder a fresh tyvar |
| `the_s2typ_bool()` | `statyp2.sats:191` | the bool type for §2.1 |
| `s2typ_xtv(x2t2p)` | `statyp2.sats:399` | wrap a fresh existential var as a type |
| `x2t2p_make_lctn(loc)` | `statyp2.sats:165` | a fresh existential type-var box |
| `d2exp_get_node` / `.node()` | `dynexp2.sats:1200` | detect the `D2Enone0` recovery node |
| `d2pat_get_node` / `.node()` | `dynexp2.sats:818` | match `D2Pvar(d2v)` to set its styp |
| `T_TRCD20(int)` | `lexing0.sats:172` | the record kind-token (§2.3) |
| `D2Ecas0`/`D2CLScls`/`D2GPTpat`/`D2GPTgua`/`D2GUAexp` | `dynexp2.sats` | match clauses + guards |
| `D2Eift0`,`D2Etup0`,`D2Ercd2`,`D2Eproj`,`D2LAB`,`LABsym` | `dynexp2.sats`/`xlabel0.sats` | if/tuple/record/field |

### 3.1 Discrepancies vs the design docs (verified, real)
- **LOWERING-MAP §3.4 / M3-REPORT §5.3 — `d3parsed_of_trans23` runs trans2a:** FALSE (§2 above).
  trans2a is in `trans03_from_fpath`, not `d3parsed_of_trans23`. This is the root reason the M4
  constructs needed hand-stamped types.
- **LOWERING-MAP §1.1 (`e.field` → `D2Eproj` "vs `D2Edtsel`"):** `D2Eproj` is correct for
  record-field projection and typechecks clean (`m4_record` `nerror=0`). `D2Edtsel` not needed.
- **LOWERING-MAP §1.1 (record token):** the table says labels via `label`; it does NOT note the
  record token must be `T_TRCD20`, not `{`/`T_LBRACE` — a real trap (§2.3). Flagged.
- **LOWERING-MAP §1.2/§1.3 (clauses):** `D2CLScls(D2GPTpat …)` / `D2GPTgua(…)` — confirmed exact;
  the preserved `pl_arm` matches `trans12` clause handling and the guard fall-through is correct.

---

## 4. The for-loop fast-path fix (#14) — already correct in the baseline, golden verified

`pyelab_loop.dats` `for_value` (335-369) already carries the **#14 fix**: the fast path
(`list_foldleft`) is gated on `b_and(b_and(single, noelse), control_pure)` where
`control_pure = ~control_any(flags_stmts(body))` — i.e. on the BODY's control-flow flags, NOT
accumulator arity. `pcflags = @(may_return, may_break, may_continue)` (`pyelab_core.dats:114-116`);
a `for` body with a `break` sets `.1 = true`, so `control_pure = false` → it routes through
`for_iter_loop` + the outer flow dispatch (where a single-accumulator `for … break` works), NOT the
fast path (which `elab_pure` cannot express a break in).

**Golden:** `TEST/m2_5/m25_for_break.py` — a **single-accumulator** `for` (`found`) with a
`break` — already exists and is **exactly** the #14 case. Its golden
(`m25_for_break.golden`) shows the desugaring routes through the **flow path** (`iter_step`,
`iter_more`, `flow_break`, the `for_iter_loop` dispatch — 6 flow/iter occurrences) and contains
**zero `list_foldleft`**. `build-m2_5.sh` diffs this golden and **PASSES**, so the #14 fix is
verified. No code change or new golden was needed; the recovery already landed it.

---

## 5. Constructs completed vs deferred

**COMPLETED (LOWER + TYPECHECK, `nerror=0`, verified via the M3 driver):**
- `match` on **int literals**, **tuple patterns**, **wildcards**, and a **GUARDED arm**
  (`case x if true:` → `D2GPTgua(D2Pvar x; D2GUAexp(D2Ebtf true))`, native fall-through).
- `if / elif / else` as a value (nested `D2Eift0`).
- **tuples** (`D2Etup0`) — incl. mixed-type `(true, 4)`.
- **records** (`D2Ercd2`) **+ field projection** (`D2Eproj`).
- **invalid program** → diagnostic on the exact `.py` span (a non-bool guard `case x if 7:`
  → the `7` is checked against `bool`, errck lands on `line=2,offs=15..16`).

**DEFERRED (all blocked by the SAME pre-existing backend-infra gaps, NOT M4 lowering bugs):**
- **Operator-dependent positions** — a guard/if-condition that IS a comparison (`x < 0`,
  `1 < 2` checked against `bool`). The operator resolves through the `D2ITMsym` overload arm to a
  `D2Esym0` that synthesizes `void` because the `$`-template (`sint_lt$sint`) is never instantiated
  (M3-REPORT §6.1 blocker #1 — we don't run trans2a's overload+template resolution). In a *synthesis*
  let (`let b = 1 < 2`) the fresh-tyvar binder masks it (`nerror=0`), but in a *checked* bool
  position it errcks. Real fix = replicate trans2a's overload/`$`-template fill for direct-L2 calls.
- **List literals** (`[1,2,3]`) — desugar to `list_cons`/`list_nil`, themselves `$`-templates with
  unfilled jags (same blocker #1).
- **Loops** (`while`/`for`) typechecking to `nerror=0` — needs TWO things we don't have: (a) the
  `pyrt` flow/iterator names (`flow_next`/`flow_break`/`iter_step`/`iter_open`/`list_foldleft`) in
  scope — `pyrt.dats` is not compiled into the bundle nor staloaded, and these names are NOT in the
  stock prelude, so they resolve UNBOUND; and (b) the loop bodies use operators (`i < 10`, `i + 1`),
  blocked as above. The loop **lowering** itself is correct and exercised at the PyCore level by
  `build-m2_5` (the desugared `PCEletfun`+`PCEcase` shape); typechecking it E2E is gated on
  pyrt-staloading (a driver/build change) + the operator `$`-template fix. Both are M5/architect work.
- **User-datatype constructor patterns E2E** (`PCPcon` on a user `type … = C(…)`) — lowering is
  built (`pl_pat` `PCPcon` → `D2Pcon`/`D2Pdapp`); full E2E needs the datatype-decl lowering
  (`PCCdata`, currently a no-op) + the type layer — M5 per the brief.

---

## 6. Standards compliance
- **Purely additive:** changes only in `frontend/` (`pylower_dynexp.dats`, `pylower_decl00.dats`,
  `pylower.sats`, `TEST/m4/*`, `build-m4.sh`). Nothing in `srcgen2`/`language-server`.
- **No `trans2a`/`trsym2b` pre-pass** — the driver still calls `d3parsed_of_trans23` directly; the
  type-stamping is done at lowering time on individual nodes, so the `d2exp_none0` recovery node is
  untouched and 4b is preserved verbatim.
- **Real Python `loctn`** on every L2 node (the invalid diagnostic lands on `line=2,offs=15`).
- **Re-entrant / token-based literals / npf=-1** — unchanged from M3.
- **No regression:** build-m1 PASS, build-m2 PASS, build-m2_5 PASS, build-m3 PASS (4a **and** 4b).

## 7. Captured evidence
```
# build-m4 (rebuilds the driver via build-m3, then runs the M4 suite):
>> M3: PASS (4a: .py -> JS -> node runs ...; 4b: type error on the .py span)   [driver self-test]
m4_match        nerror (after tread3a) = 0   PASS   (match: lit arm + GUARDED arm + wildcard)
m4_match_tuple  nerror (after tread3a) = 0   PASS   (match on a tuple pattern)
m4_if           nerror (after tread3a) = 0   PASS   (if/elif/else value)
m4_tuple        nerror (after tread3a) = 0   PASS   (D2Etup0, mixed types)
m4_record       nerror (after tread3a) = 0   PASS   (D2Ercd2 + D2Eproj field)
m4_typeerr      nerror (after tread3a) = 1   PASS   (non-bool guard -> diagnostic)
>> M4: PASS

# the guarded-arm lowering (from the m4_typeerr L3 dump; the valid m4_match has the same shape
# with D3Ebtf(true) in place of the bad 7):
D3CLScls(D3GPTgua(D3Pvar(x(2));$list(D3GUAexp( <guard> )));  <body> )
D3CLScls(D3GPTpat(D3Pvar(y(3)));  <body> )

# the invalid-program diagnostic on its EXACT .py span (the `7` in `case x if 7:`):
F3PERR0-ERROR:LCSRCsome1(.../m4_typeerr.py)@(24(line=2,offs=15)--25(line=2,offs=16)):
  D3Eerrck(1;D3Et2pck(D3Eint(T_INT01(7));T2Pnone0();T2Pcst(the_s2exp_bool0)))

# prior builds (run sequentially — a SHARED frontend/BUILD makes concurrent build-m*.sh races):
build-m1   -> M1 GOLDEN: PASS
build-m2   -> M2 GOLDEN: PASS
build-m2_5 -> M2.5 GOLDEN: PASS  (incl. m25_for_break: flow path, no list_foldleft — the #14 golden)
build-m3   -> M3: PASS           (4a a=7 b=7 c=7 ; 4b nerror=1 on the .py span)
```

> **OPERATIONAL NOTE for the harness:** `build-m1`…`build-m3` all write into a SHARED
> `frontend/BUILD/`. Running them **concurrently** corrupts each other's bundles (observed:
> `pylex_text_… is not defined` from a half-written `pylex-m1.js`). Run them **sequentially**.
> `build-m4.sh` reuses the M3 driver bundle, so it is safe after a clean `build-m3`.
