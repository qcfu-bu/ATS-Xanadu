# M0a — typecheck-spine: implementation report

> **Status: DONE.** A hand-built L2 `d2parsed` for `val x = 1 ; val y = x`
> (binding + a use-site resolved through the env) drives cleanly through the
> reused L2→L3 entry `d3parsed_of_trans23`, reports `nerror = 0` via the stock
> `f3perr0_d3parsed`, and does so **twice in one process** with identical output
> (re-entrancy proven). Purely additive: `git status` shows only `frontend/`.

---

## 1. What was built

| File | Role |
|---|---|
| `frontend/SATS/pyfront.sats` | Driver API: `pyfront_m0a_check(): d3parsed`, `pyfront_m0a_run(iter): sint`. |
| `frontend/DATS/pyfront.dats` | The hand-builder (`build_d2parsed`), the template-A resolver (`resolve_dexp`), the two `#implfun` driver bodies, and `mymain_main` (the 2× re-entrancy loop + global bootstrap). |
| `frontend/CATS/pyfront.cats` | Minimal FFI glue: `PYF_print/println/println_int` → `process.stdout`. No argv needed (no source file in M0a). |
| `frontend/build-m0a.sh` | One-command transpile (jsemit00) + cat-link + run. |
| `frontend/BUILD/` | `pyfront_dats.js` (transpiled), `pyfront-m0a.js` (linked bundle, ~180 MB), `transpile.err`, `README.md`. |

The program lowered (LOWERING-MAP §4 templates **C** "val binding" and **A**
"identifier reference", mirroring `srcgen2/DATS/trans12_decl00.dats` `f0_valdclst`):

```
val x = 1     // D2Pvar(fresh d2var x)  =  D2Ei00 1   ; bound AFTER RHS (non-rec)
val y = x     // x RESOLVED via tr12env_find_d2itm -> D2ITMvar -> d2exp_var ; then bind y
```

---

## 2. The exact working build/link/run commands

`bash frontend/build-m0a.sh` does all of this (XATSHOME defaults to the repo root):

```bash
# [1/3] transpile the driver with jsemit00 (NOT jsemit01), stack-size 8801
node --stack-size=8801 \
  xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js \
  frontend/DATS/pyfront.dats > frontend/BUILD/pyfront_dats.js

# [2/3] cat-link: runtime + lib2xatsopt(SED-namespaced) + .cats glue + driver
cat \
  srcgen2/xats2js/srcgenx/xshared/runtime/xats2js_js1emit.js \
  srcgen2/xats2js/srcgenx/xshared/runtime/srcgen2_precats.js \
  srcgen1/xats2js/srcgenx/xshared/runtime/srcgen1_prelude.js \
  srcgen1/xats2js/srcgenx/xshared/runtime/srcgen1_prelude_node.js \
  srcgen1/xats2js/srcgenx/xshared/runtime/srcgen1_xatslib_node.js \
  > frontend/BUILD/pyfront-m0a.js
sed -E 's/jsx(...)tnm/js1\1tnm/g' srcgen2/lib/lib2xatsopt.js >> frontend/BUILD/pyfront-m0a.js
cat frontend/CATS/pyfront.cats        >> frontend/BUILD/pyfront-m0a.js
cat frontend/BUILD/pyfront_dats.js    >> frontend/BUILD/pyfront-m0a.js

# [3/3] run
node --stack-size=8801 frontend/BUILD/pyfront-m0a.js
```

This is **identical in shape** to `language-server/server/resident/build.sh`
(same runtime list, same `sed` namespacing, same jsemit00, same `--stack-size=8801`),
trimmed to the M0a spine (no Closure minify; no xats2js backend — that is M0b).

**`srcgen2/lib/lib2xatsopt.js` was REUSED** (present, ~171 MB, dated Jun 19); it was
**not** rebuilt.

---

## 3. The resolved nil `d1topenv` (plan §6.6 / open Q2)

**Approach used:** `tr01env_free_top(tr01env_make_nil())`.

- `fun tr01env_make_nil(): tr01env` — `srcgen2/SATS/trans01.sats:386`
- `fun tr01env_free_top(tr01env): d1topenv` — `srcgen2/SATS/trans01.sats:388`

Both are already in scope via `libxatsopt.hats` (which staloads `trans01.sats`).

**Why not the `D1TOPENV` constructor:** `d1topenv` is now a *visible* datatype
`D1TOPENV of ($MAP.topmap($FIX.fixty))` (`srcgen2/SATS/dynexp1.sats:1224-1226`;
the old `#abstbox` form is commented out). Building it directly would require the
`$MAP.topmap` nil maker plus `$MAP`/`$FIX` namespace plumbing from the frontend —
fragile. `tr01env_free_top(tr01env_make_nil())` is self-contained and is exactly
the route plan §6.6 endorses. **Confirmed nothing downstream reads it:** trans23
type-checks from `t2penv` + `parsed`; with the empty fixity env, `nerror = 0`.

---

## 4. Every compiler API used — VERIFIED signature + file:line

All re-grepped against the live SATS on 2026-06-20. ✓ = matched the design docs;
Δ = discrepancy (see §5).

| API | Verified signature | Location |
|---|---|---|
| `d2parsed_make_args` | `(stadyn:sint, nerror:sint, source:lcsrc, t1penv:d1topenv, t2penv:d2topenv, parsed:d2eclistopt): d2parsed` ✓ | `SATS/dynexp2.sats:1972` |
| `d3parsed_of_trans23` | `(dpar: d2parsed): d3parsed` ✓ | `SATS/trans23.sats:255` |
| `d3parsed_get_nerror` | `(d3parsed) -> sint` ✓ | `SATS/dynexp3.sats:1200` |
| `f3perr0_d3parsed` | `(out: FILR, dpar: d3parsed): void` ✓ | `SATS/f3perr0.sats:217` |
| `the_fxtyenv_pvsl00d` / `the_tr12env_pvsl00d` | `() -> sint` (idempotent global bootstrap) ✓ | called as in `UTIL/xatsopt_tcheck00.dats:217` |
| `tr12env_make_nil` | `(): tr12env` ✓ | `SATS/trans12.sats:376` |
| `tr12env_free_top` | `(env0: tr12env): d2topenv` ✓ | `SATS/trans12.sats:379` |
| `tr12env_add0_d2pat` | `(env0: !tr12env, d2p0: d2pat): void` ✓ | `SATS/trans12.sats:565` |
| `tr12env_find_d2itm` | `(env: !tr12env, key: sym_t): d2itmopt_vt` ✓ | `SATS/trans12.sats:457` |
| `d2itmopt_vt` | `= optn_vt(d2itm)`; matched `~optn_vt_cons(d2i1)` / `~optn_vt_nil()` ✓ | `SATS/trans12.sats:311` |
| `d2itm` ctors | `D2ITMvar of d2var \| D2ITMcon of d2conlst \| D2ITMcst of d2cstlst \| D2ITMsym of (sym_t, d2ptmlst)` ✓ | `SATS/dynexp2.sats:600-608` |
| `d2var_new2_name` | `(loc0: loc_t, name: sym_t): d2var` ✓ | `SATS/dynexp2.sats:593` |
| `d2pat_var` | `(loc0: loc_t, d2v1: d2var): d2pat` ✓ | `SATS/dynexp2.sats:862` |
| `d2exp_var` | `(loc0: loc_t, d2v1: d2var): d2exp` ✓ | `SATS/dynexp2.sats:1236` |
| `d2exp_csts` / `d2exp_cons` / `d2exp_none0` | `(loc, d2cstlst/d2conlst): d2exp` / `(loc): d2exp` ✓ | `SATS/dynexp2.sats:1263/1257/1229` |
| `d2exp_make_node` (`#symload d2exp`) | `(loc0: loc_t, nod1: d2exp_node): d2exp` ✓ | `SATS/dynexp2.sats:1297` |
| `D2Ei00` | `D2Ei00 of (sint)` (unboxed int literal) ✓ | `SATS/dynexp2.sats:923` |
| `d2pat_make_node` / `d2ecl_make_node` | `(loc, node): d2pat/d2ecl` ✓ | `SATS/dynexp2.sats:907 / 1653` |
| `d2valdcl_make_args` | `(lctn:loc_t, dpat:d2pat, tdxp:teqd2exp, wsxp:wths2exp): d2valdcl` **Δ** (see §5.1) | `SATS/dynexp2.sats:1846` |
| `TEQD2EXPsome` / `TEQD2EXPnone` | `TEQD2EXPsome of (token, d2exp)` / `TEQD2EXPnone of ()` ✓ | `SATS/dynexp2.sats:1428 / 1426` |
| `WTHS2EXPnone` | `WTHS2EXPnone of ()` ✓ | `SATS/dynexp2.sats:1432` |
| `D2Cvaldclst` | `D2Cvaldclst of (token, d2valdclist)` (`d2valdclist = list(d2valdcl)`) ✓ | `SATS/dynexp2.sats:1519 / 324` |
| `token_make_node` (`#symload token`) | `(loc: loc_t, tnd: tnode): token` ✓ | `SATS/lexing0.sats:352` |
| `T_VAL` / `valkind VLKval` | `T_VAL of (valkind)`; `VLKval` | `SATS/lexing0.sats:226`; `SATS/xbasics.sats:146` |
| `symbl_make_name` (`#symload symbl`) | `(name: strn): symbl` ✓ | `SATS/xsymbol.sats:102` |
| `loctn_dummy` | `(): loctn` ✓ | `SATS/locinfo.sats:129` |
| `LCSRCnone0` | `LCSRCnone0 of ()` (lcsrc ctor) ✓ | `SATS/locinfo.sats:71` |
| `tr01env_make_nil` / `tr01env_free_top` | `(): tr01env` / `(tr01env): d1topenv` ✓ | `SATS/trans01.sats:386 / 388` |
| `g_stderr` / `FILR` | `g_stderr(): FILR`; `FILR = FILEref` ✓ | `srcgen1/xatslib/libcats/SATS/libcats.sats:71 / 58` |

---

## 5. Discrepancies vs the design docs (all REAL fixes, not workarounds)

### 5.1 `d2valdcl_make_args` arity — no separate `eqtok` argument **(Δ, doc-stated)**

LOWERING-MAP §1.3 lists `d2valdcl_make_args(loc, dpat, teqd2exp, wths2exp)` — and
that is exactly the live signature (`SATS/dynexp2.sats:1846`). The PLAN §5.4 narrative
text and the LOWERING-MAP §4 template C pseudocode read as if an `eqtok` is passed
*alongside* the `teqd2exp`; it is not. **The `=` token lives INSIDE `TEQD2EXPsome(token, d2exp)`.**
Handled correctly: `d2valdcl_make_args(loc, pat, TEQD2EXPsome(eqtok, rhs), WTHS2EXPnone())`.

### 5.2 The implementation keyword is `#implfun`, NOT `implement` **(Δ, blocking)**

ATS3/Xanadu does **not** use the ATS2 `implement` keyword — it does not appear in
the Xanadu prelude or compiler. A SATS-declared function is given its body in the
DATS with **`#implfun NAME(...) = ...`** (confirmed: `xats_lsp_resident.dats` uses
`#implfun reload_prelude(...) = ...`; plain local helpers use `fun`). My first draft
used `implement`, which the parser wrapped in `D2Eerrck(D2Enone1(D1Eid0(implement)))`.
Switching the two driver bodies to `#implfun` fixed it. **The docs never state which
keyword to use; this is a Xanadu-specific fact worth recording.**

### 5.3 A standalone driver needs `xatsopt_sats.hats` + `xatsopt_dpre.hats`, not just `libxatsopt.hats` **(Δ, blocking)**

The plan's anchor index and §5.4 cite `libxatsopt.hats` as *the* compiler header.
That header is **SATS-only**. A standalone `.dats` transpiled by jsemit00 that *uses*
prelude **template** functions — `=` (`gint_eq$sint$sint`), `prerrsln`/`proutsln`
(`gs_*`), `list_cons`, etc. — leaves them **un-instantiated**, and every use is
wrapped in a `TIMPLall1(...; T2JAG($list()))` errck (empty template-arg jag). The fix,
mirroring `language-server/server/DATS/xats_lsp_check.dats`, is to also `#include`:

```
#include "./../../srcgen2/HATS/xatsopt_sats.hats"   // prelude SATS
#include "./../../srcgen2/HATS/xatsopt_dpre.hats"   // prelude DATS (= the template IMPLS)
```

`xatsopt_dpre.hats` pulls in the prelude **DATS** (`gbas000.dats`, `gint000.dats`,
`gmap000.dats`, …) so the template implementations are present and instantiable.
With all three headers: **0 errck**. This is the single most important build fact
for any future standalone frontend driver and should be added to the plan's anchor
index.

### 5.4 `loctn_dummy()` yields `LCSRCsome1(<file>)`-tagged spans, not `LCSRCnone0`

Observed in the errck dumps during debugging: nodes built with `loctn_dummy()` print
their source as `LCSRCsome1(frontend/DATS/pyfront.dats)`. This is cosmetic for M0a
(synthetic nodes have no Python origin yet); M1+ threads real Python spans. Noted so
it is not mistaken for a bug later.

---

## 6. Re-entrancy (plan §6.2) — proven

`mymain_main` runs the **entire** build+check twice (`pyfront_m0a_run(1)`,
`pyfront_m0a_run(2)`), each with a **fresh `tr12env_make_nil()`** and **no global
mutation** (resolution only *reads* the prelude via fall-through). The global
bootstrap (`the_fxtyenv_pvsl00d` / `the_tr12env_pvsl00d`) runs once at startup and is
idempotent (gated by `the_ntime`). Both iterations: `nerror = 0`, identical output ⇒
**no state leak**. A divergence would have printed
`RE-ENTRANCY: FAIL (... STATE LEAK)`; it printed `PASS`.

---

## 7. Negative control (lookup is load-bearing, not trivially passing)

Temporarily resolving an **unbound** name (`z` instead of `x`) made `resolve_dexp`
hit the `optn_vt_nil()` arm and print
`!! M0a: 'x' did NOT resolve through the env (unbound)` — confirming the env lookup
genuinely returns `nil` for an unbound name and `D2ITMvar(d2v)` for the bound one.
The positive run prints **no** such line, i.e. `x` resolves to the same `d2var` the
`val x = 1` binding created. This is the heart of direct-to-L2 (binding + lookup
share one entity), and it is exercised, not assumed.

---

## 8. Captured evidence — `nerror=0` on BOTH iterations

`node --stack-size=8801 frontend/BUILD/pyfront-m0a.js` (stdout; exit 0):

```
######## M0a typecheck-spine driver ########
program (hand-built L2): val x = 1 ; val y = x
== M0a iteration == 1
-- f3perr0_d3parsed (stock reporter, stderr) --
nerror = 0
RESULT: PASS (nerror=0) -- L2->L3 typecheck spine OK
== M0a iteration == 2
-- f3perr0_d3parsed (stock reporter, stderr) --
nerror = 0
RESULT: PASS (nerror=0) -- L2->L3 typecheck spine OK
######## re-entrancy summary ########
iteration 1 nerror = 0
iteration 2 nerror = 0
RE-ENTRANCY: PASS (both iterations nerror=0, identical)
```

- Transpile: jsemit00 emitted **5997 lines, 0 errck**; `transpile.err` has no
  `F2PERR0-ERROR`/`F3PERR0-ERROR` lines.
- Runtime stderr: only benign `d0parsed_from_fpath:` prelude-load traces; **no**
  `F3PERR0-ERROR`/`errck` (the stock reporter found nothing — clean type-check).

---

## 9. Purely-additive check

`git status --short` after the work:

```
 M frontend/docs/PYTHON-FRONTEND-PLAN.md   (pre-existing architect edit)
?? frontend/BUILD/
?? frontend/CATS/
?? frontend/DATS/
?? frontend/SATS/
?? frontend/build-m0a.sh
```

**Zero modifications under `srcgen2/` or `language-server/`.** Requirement met.

---

## 10. Scope boundary

M0a is the typecheck spine only. **No codegen** (no xats2js link, no `.js` emission,
no `node`-run of generated code) — that is M0b and was deliberately not touched.
`frontend/SATS/pyfront.sats:9` (`#include libxatsopt.hats`) +
`frontend/DATS/pyfront.dats` headers are the seam M0b will extend with the
`xats2js` backend pieces.
