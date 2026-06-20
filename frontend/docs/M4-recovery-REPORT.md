# M4 Recovery — Regression Restore (build-m3 4b)

**Goal:** restore ALL frontend builds to GREEN after milestone M4 was abandoned mid-edit by a
stalled agent, leaving `build-m3.sh` failing at step **4b** (the unbound-name type-error test).

**Outcome:** GREEN-RESTORED. `build-m1`, `build-m2`, `build-m2_5` PASS; `build-m3` PASSES both
**4a** (`.py -> JS -> node`, bindings `a=7 b=7 c=7`) and **4b** (unbound name reported on the
`.py` span with `nerror=1`).

---

## 1. The regression

`frontend/TEST/m3/m3_typeerr.py`:

```python
let ok = 1
let bad = no_such_name
```

`no_such_name` must be reported as an **unbound-name error on its `.py` span** (line 2,
cols 11–23), giving **`nerror=1`**. Before the fix it produced **`nerror=0`** — the driver
treated the program as clean and even ran codegen (`RESULT: PASS`).

The intended M3 mechanism (M3-REPORT §5.2, [E3]): `no_such_name` lowers to `d2exp_none0(loc)`
(pl_var's nil arm, `pylower_dynexp.dats:93`), which `trans23` flags as a `D3Et2pck` errck;
`tread3a` then SCANS the parsed decls for errck nodes and bumps `nerror`. With the fix the
diagnostic is restored verbatim to the M3-verified shape:

```
F3PERR0-ERROR:LCSRCsome1(.../m3_typeerr.py)@(22(line=2,offs=11)--34(line=2,offs=23)):D3Eerrck(1;D3Et2pck(D3Enone0();T2Pcst(the_s2exp_void);T2Pnone0()))
```

## 2. Root cause

The stalled agent's M4 WIP edited the **driver** `frontend/DATS/pyfront_m3.dats` (its newest
file, mtime ~06:24): it wrapped the L2→L3 entry in a new `pyfront_pre23` stage that ran
`trans2a` (overload/literal-TYPE stamping) + `trsym2b` (symbol resolution) over the parsed
list **before** `d3parsed_of_trans23`, on the (incorrect) premise that those passes are
mandatory for the direct-L2 pipeline.

That extra pre-pass is what suppressed 4b: running `trans2a`/`trsym2b` over the directly-
constructed L2 mutated the val-declaration carrying the `d2exp_none0` recovery node such that
`trans23` no longer emitted a `D3Et2pck` errck for it — so `tread3a` counted nothing and
`nerror` stayed 0.

The M3-verified driver (and the sibling `pyfront_m0b.dats` / `pyfront.dats` drivers, and the
SATS contract in `pyfront_m3.sats:15`) call `d3parsed_of_trans23(...)` **directly** with no
`pre23` wrapper. `d3parsed_of_trans23` (`srcgen2/DATS/trans23.dats:104-137`) drives the L2→L3
check that produces the errck; the from-file `trans2a`/`trsym2b` (`trans23.dats:89-90`) are a
different driver's concern and are not needed (nor wanted) for this recovery path.

## 3. What was changed

**Reverted the dead agent's M4 driver edit in `frontend/DATS/pyfront_m3.dats` to the
M3/#12-verified behavior:**

- Removed the `pyfront_pre23` function (the explicit `trans2a` + `trsym2b` pre-pass).
- Restored `pyfront_d3parsed_of_fpath` to `d3parsed_of_trans23(pyfront_d2parsed_of_fpath(...))`.
- Removed the now-unused `#staload`s of `trans2a.sats` / `trsym2b.sats`.

No other file was touched. Change is purely additive to the repo (only `frontend/`); nothing in
`srcgen2`/`language-server`.

## 4. WIP preserved (compiles, unrelated to the regression)

- **`pylower_dynexp.dats` `pl_pat` pattern-lowering** (PCPcon/PCPtup/PCPrec/PCPlit + the
  `pl_patlst`/`pl_pfieldlst` helpers): kept. It is structurally complete, is wired to the
  existing `pylower_pat`/`pylower_patlst` SATS entries, compiles cleanly, and is exercised by
  4a's `PCPvar` lets. Not entangled with the driver regression.
- **`pyelab_core.dats` `PySexpr` "M4 FIX"** (a trailing expression-statement is the suite tail,
  not double-emitted as a `PCEseq` init): kept. It only affects function-body suites, not the
  top-level `let` path that 4b exercises, and `build-m2_5` (the elaborator goldens) stays green.

The full M4 match/pattern-lowering feature remains a separate follow-up; this recovery only
restored green.

## 5. Evidence (all four builds)

- **build-m3 4a:** `>> 4a PASS  (.py -> JS -> node, exit 0, bindings a=7 b=7 c=7)`
- **build-m3 4b:** `[m3] d3parsed nerror (after tread3a) = 1` →
  `>> 4b PASS  (type error reported on the Python source m3_typeerr.py with a line:col span)` →
  `>> M3: PASS`
- **build-m1 / build-m2 / build-m2_5:** PASS (see §6 below).
</content>
