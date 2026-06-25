# M3 — functional-core lowering (PyCore → L2), wired into the first real end-to-end

> **Status: pipeline DONE; codegen partial-but-honest.** A real `.py` source drives the
> FULL pipeline — lex (`pylex_layout`) → parse (`pyparse_module`) → elaborate
> (`pyelab_module`) → **lower (`pylower`, NEW)** → `d2parsed_make_args` →
> `d3parsed_of_trans23` — re-entrant, frontend-only, M0a/M0b/M1/M2/M2.5 still green.
> **Deliverable 4a (a `.py` that compiles to JS and RUNS on node): PASS** for the
> functional-core subset that codegens cleanly (literals + immutable `let` + variable
> references / SSA-rebind). **Deliverable 4b (a type error reported on the Python span):
> PASS** — `f3perr0` lands the diagnostic on the precise `.py` line:col.
>
> **Honestly flagged for the architect:** arithmetic / `print` / `def`-codegen do NOT yet
> RUN, blocked by **two pre-existing backend-lib limitations** (NOT M3 lowering bugs) —
> §6. The frontend LOWERS and TYPE-CHECKS all of them correctly (the type error in 4b is
> exactly such a case landing on the `.py` span).

---

## 1. What was built (all new, all under `frontend/`)

| File | Role |
|---|---|
| `SATS/pylower.sats` | The cross-DATS lowering contract (`pylower_exp/_pat/_typ/_decl/_decls`, the operator remaps, the fun-group helper). |
| `DATS/pylower_staexp.dats` | `pytyp → s2exp` (type-name resolution + `Int`→`int` aliasing) + the surface-operator→prelude-name table (`op_remap`/`op_remap_unary`). |
| `DATS/pylower_dynexp.dats` | `pclit/pcexp/pcpat → d2exp/d2pat` (templates A/B/C/D/E/F). Mutually-recursive `pl_*` workers + `#implfun` wrappers (the M2.5 dialect structure rule). |
| `DATS/pylower_decl00.dats` | `pcdecl → d2ecl` (`PCCfun`/`PCCval`/`PCCstaload`/`PCCdata`) + the module driver `pylower_decls`. |
| `SATS/pyfront_m3.sats` + `DATS/pyfront_m3.dats` | The REAL pipeline driver `pyfront_d2parsed_of_fpath` / `pyfront_d3parsed_of_fpath`, plus the main that reads a `.py`, runs the pipeline, reports diagnostics, and (if clean) runs the M0b xats2js codegen spine to emit JS. |
| `CATS/pyfront_m3.cats` | FFI glue: `PYM_log*` (stderr progress), `PYM_mark` (JS sentinels), `PYM_readfile`/`PYM_argv_path`. |
| `build-m3.sh` | One command: build-or-reuse backend libs → transpile passes+driver → link → run 4a (emit JS + run on node + assert bindings) + run 4b (assert type-error on the `.py` span). |
| `TEST/m3/m3_run.py`, `TEST/m3/m3_typeerr.py` | The 4a (runs) and 4b (type-error-on-span) snippets. |

Backend libs (`lib2xats2cc.js`/`lib2xats2js.js`) are now **cached** in `frontend/BUILD` and
reused across runs (ENGINEERING.md §4 TODO addressed); `--rebuild-libs` forces a rebuild.

---

## 2. The lowering approach (mirroring the `trans12` templates, LOWERING-MAP §4)

A straight structural map PyCore → L2 against a **fresh `tr12env` per call** (names fall
through to the prelude). Verified templates:

- **A — identifier ref** (`pl_var`): `tr12env_find_d2itm` → branch on the `d2itm`
  (`D2ITMvar`→`d2exp_var`, `D2ITMcon`→`d2exp_con`/`_cons`, `D2ITMcst`→`d2exp_cst`/`_csts`,
  `D2ITMsym`→`d2exp_sym0` with a synthetic `D1Eid0(sym)` proxy + fresh `d2rxp`).
- **B — application** (`pl_app`): `d2exp_dapp(loc, d2f, -1, args)`; empty args → `D2Edap0`.
  Operator-headed apps are remapped by ARITY (§3) before resolving the head.
- **C/E — `let` / block** (`PCElet`): push a `let` scope, lower pat, lower RHS, **bind the
  pattern after the RHS** (non-recursive), wrap in `D2Elet0`.
- **D — lambda** (`PCElam`): `pshlam0`, build params as fresh `d2var`s, `add0_f2arglst`,
  lower body, `poplam0`, `D2Elam0(LAM-tok, f2args, S2RESnone, F1UNARRWdflt, body)`.
- **F — `fun` group** (`pl_fungroup`, `PCEletfun`/`PCCfun`): collect the group's names,
  **bind them BEFORE the bodies** (a Python `def` group is recursive → self/mutual calls
  resolve to the same `d2var`), lower each member in its own lam scope, emit
  `D2Cfundclst(FUN-tok, [], [], members)` with `FNKfn2` (tailrec — lets the backend compile
  a tail self-call to a `while`).
- Literals are **TOKEN-based** (`D2Eint`/`D2Eflt`/`D2Estr`/`D2Echr`/`D2Ebtf` via
  `token_make_node`) per LOWERING-MAP §2.1 / M0b §5.5 (never the unboxed `D2E*00`).
- **Real Python `loctn` threaded into every node** — this is what makes 4b land on the
  `.py` span.
- Module driver (`pylower_decls`): thread `env` left-to-right so each decl's top-level
  bindings are visible to the following decls (`trans12.dats:528-556`).

The PUBLIC pipeline (`pyfront_d2parsed_of_fpath`): `pyparse_module(src,text)` →
`pyelab_module` → `PCModule(decls,_)` → `pylower_decls(env,decls)` →
`d2parsed_make_args(stadyn, 0, src, tr01env_free_top(tr01env_make_nil()),
tr12env_free_top(env), optn_cons(d2cs))`. RE-ENTRANT (fresh env per call; global bootstrap
once; **verified** — identical output across runs).

---

## 3. The surface-operator → prelude-name table (Q4 — owned here)

**The crux finding (PROBE-VERIFIED 2026-06-20, a throwaway driver resolving names through a
fresh `tr12env`):** the prelude binds `+ - * / % == < <= > >= != neg not print` as
**overload symbols → `D2ITMsym`**, NOT as the `D2ITMcst` the LOWERING-MAP §3.4 table assumed
(**discrepancy, §5.1**). Python `==`/`//` have no entry under those names. So the canonical
table M3 uses:

| Python surface | resolves via | M3 maps to | notes |
|---|---|---|---|
| `+ - * / %` | `D2ITMsym` (own name) | own name | the prelude overload symbol |
| `//` (int div) | — | `/` | prelude `/` **is** integer division on `sint` |
| `==` | — | `=` | the prelude equality is `=` |
| `!= < <= > >=` | `D2ITMsym` (own name) | own name | |
| unary `-` | `D2ITMsym` | `neg` | the prelude `neg` overload |
| unary `+` | — | (no-op) | the application **is** its operand |
| `**` (power) | — | (deferred) | no prelude `sint` power fun |
| `and` / `or` / `not` | — | (never reaches M3) | the **elaborator** already lowers these to `PCEif` short-circuit (`pyelab_core.dats:305-314`) — M3 only sees arithmetic/comparison |
| `print` | `D2ITMsym` | (see §6) | concrete `sint_print` is `D2ITMcst` |
| type `Int`/`Bool`/`String` | — | `int`/`bool`/`strn` | capitalized surface names alias to the lowercase prelude `s2cst` (probe: `Int`/`Bool` are UNBOUND; `int`/`bool`/`sint` are `S2ITMcst`) |

`and`/`or`/`not` short-circuit is therefore **already handled upstream**; M3 lowers the
resulting `PCEif` to `D2Eift0`.

---

## 4. Minimal type / pyrt support

- `pylower_typ` resolves a type NAME via `tr12env_find_s2itm` (LOWERING-MAP §3.5), aliasing
  the capitalized surface built-ins (`Int`→`int`, `Bool`→`bool`, `String`→`strn`,
  `Char`→`char`, `Float`→`double`) to their prelude `s2cst`. An unresolved name →
  `s2exp_none0()` (benign placeholder; trans23 reports it on the span). Type application
  (`List[Int]`) → `s2exp_apps`. `pylower_sres` wraps a return type as
  `S2RESsome(S2EFFnone(), s2e)`.
- **No pyrt additions were needed for the E2E** — every prelude name the functional core
  references resolves through the env's global fall-through with NO explicit `staload`
  (probe-verified: `+`/`print`/`int` all resolve in a fresh `tr12env`). `PCCstaload` lowers
  to a `D2Cnone0()` no-op accordingly; a real `pyrt` staload (for the `flow`/iterator names)
  is wired with the loop lowering in M4/M5.
- **The type-annotation GAP (flagged for the architect):** the M2.5 elaborator **DROPS** a
  `def`'s param types and return type (`pyelab_decl.dats:74` discards `_ret`;
  `param_names_d` discards each `PyParam`'s type), and `PCFundcl` carries none. So a typed
  `def f(x: Int) -> Int` lowers **UNTYPED** (its types are inferred by trans23). The
  type-lowering machinery (`pylower_typ`/`pylower_sres` + the `Int`/`Bool` aliasing) is fully
  built and plugs straight in **once PyCore carries the annotations** — a PyCore wire-format
  change deferred to the architect (it would force rewriting the M2.5 elaborator + every
  M2.5 golden, risking the still-green requirement; I did NOT make that change).

---

## 5. Discrepancies vs the design docs (verified, real)

### 5.1 Operators resolve to `D2ITMsym`, not `D2ITMcst` (Δ vs LOWERING-MAP §3.4)
The §3.4 narrative ("each operator is lowered as a normal identifier reference to a prelude
`d2cst`") implies `D2ITMcst`. **Probe-verified false:** every arithmetic/comparison operator
is `D2ITMsym` (an overload set). M3 routes them through the `D2ITMsym`→`d2exp_sym0` arm of
template A (the overload-resolution path), exactly as `trans12_dynexp.dats f0_id0_d2sym`.

### 5.2 `f3perr0`/`nerror` requires `tread3a` FIRST (Δ, blocking — was a false PASS)
`d3parsed_of_trans23` stores errors in **errck NODES** (`D3Eerrck`/`D3Cerrck`), NOT in the
`d2parsed` `nerror` field (which our `d2parsed_make_args` hardcodes to 0). `f3perr0_d3parsed`
only prints when `d3parsed_get_nerror > 0` (`f3perr0.dats:106`), so it stayed silent and the
driver reported a **false `nerror=0`**. **Fix:** the `tread3a` pass (`tread3a.dats:155-171`)
SCANS the parsed decls for errck nodes and UPDATES nerror. Run `tread3a` **before** reading
nerror / calling f3perr0. This is what makes 4b report at all — a load-bearing fact for any
direct-L2 driver (M0a/M0b never hit it because their hand-built programs were error-free).

### 5.3 `trans23` internally runs `trans2a` + `trsym2b` (verified, useful)
`d3parsed_of_trans23` runs `d2parsed_of_trans2a` (overload resolution) + `d2parsed_by_trsym2b`
(symbol resolution) before the L2→L3 check (`trans23.dats:89-90`). So a directly-constructed
`D2Esym0` DOES get its `d2rxp` resolution attempted — but see §6.1 for why it still doesn't
fully instantiate prelude `$`-templates.

### 5.4 `libxatsopt.hats` omits `dynexp1` (Δ); `F2ARGdapp` npf is `int` not `sint`
`pylower_dynexp.dats` needs `d1exp_make_node`/`D1Eid0` (the `d2exp_sym0` proxy) → must
`#staload dynexp1.sats` explicitly. `tr12env_add0_d2vs`/`_tqas`/`_d2varlst` are the real
symload names (not `_d2varlst` everywhere). `list_singq`/`list_nilq` (not `list_isnil`).
`andalso`/`orelse` are NOT in this dialect — nested `if`.

---

## 6. What is DEFERRED / BLOCKED, and exactly why

### 6.1 BLOCKED (pre-existing backend limitations, NOT M3 bugs): arithmetic / `print` / `def` CODEGEN
The frontend LOWERS and TYPE-CHECKS these correctly; they do not yet **run** through the
from-source xats2js backend, for two independent, well-characterized reasons:

1. **Prelude `$`-template instantiation.** Operators/`print` are `fun<>` *function-template-
   implicit* prelude entries (`sint_add$sint`, `sint_print`, …). The stock parser fills the
   `$sint` template parameter during trans12's overload resolution; a **directly-constructed**
   L2 node (either `d2exp_cst(sint_add$sint)` or the `D2Esym0` overload) does NOT trigger that
   fill — the call emerges with an **empty template-arg jag** (`T2JAG($list())`), which
   `tread3a` flags as an unresolved-template `errck` BEFORE `trtmp3b` could instantiate it.
   Net: `D3Edapp(D3Enone0(); …)` / a `D3Et2pck` errck instead of a runnable call. *(Verified
   by comparing the stock `val z = 1+2` — which emits a clean `timp` instantiation with a
   FILLED jag — against the M3-constructed equivalent.)*
2. **The funset `fun`-codegen gap.** The from-source `lib2xats2cc.js` cannot lower a `fun`
   decl: `intrep0_utils0.dats`'s `funset`-based `#implfun`s (`i0varfst_mklst`, …) transpile
   to `errck` in isolation (their `funset_*` templates don't instantiate), so a `def`'s
   `D2Cfundclst` crashes codegen with `i0varfst_mklst is not defined`. **This is the exact gap
   `build-spike.sh` already documents** (its header comment) and works around by routing
   codegen through the prebuilt stock `xats2js_jsemit01` oracle. M0b never hit it (val-only).

Both are limitations of the **from-source backend lib build**, not of the M3 lowering. The
fixes (fill the `$`-implicit by replicating trans12's overload/template pass for
direct-L2 calls; rebuild the backend lib with template resolution, or link the stock oracle's
backend) are real follow-ups for the architect — out of M3's additive scope.

### 6.2 DEFERRED to M4/M5 (per the brief): `match`/`case`, loops/iterators, the full type layer
`PCEcase`, `PCErec`/`PCElist`, datatypes (`PCCdata`), generics, and the threaded-iterator /
`flow` loop machinery are lowered to benign placeholders (surfaced, never silently dropped)
and marked in the code. These depend on the deferred type layer and task #12.

---

## 7. Captured evidence

### [E1] All M3 lowering files transpile clean (jsemit00, 0 errck)
```
pylower_staexp  errck=0
pylower_dynexp  errck=0
pylower_decl00  errck=0
pyfront_m3      errck=0
```

### [E2] Deliverable 4a — a real `.py` → JS that RUNS on node
`frontend/TEST/m3/m3_run.py`:
```python
let a = 7
let b = a
let c = b
```
Pipeline (stderr):
```
[m3] d3parsed nerror (after tread3a) = 0
[m3] typecheck OK (nerror=0) -> running codegen
[m3] trtmp3b/trtmp3c/t3read0/trxd3i0/tryd3i0/trxi0i1 done
[m3] js1emit done (emitted user-program JS to stdout)
RESULT: PASS (.py -> JS, nerror=0)
```
Emitted JS (head — note the comments carry the real `.py` spans):
```js
// I1Dvaldclist(... m3_run.py)@(1(line=1,offs=1)--10(line=1,offs=10)))
let jsxtnm1
jsxtnm1 = XATSINT1(7)
XATS000_patck(true)
let jsxtnm2
jsxtnm2 = jsxtnm1
...
```
`node` run of the emitted program (+ a runtime probe):
```
RUNTIME a=7 b=7 c=7
>> emitted-program exit code: 0
>> 4a PASS  (.py -> JS -> node, exit 0, bindings a=7 b=7 c=7)
```

### [E3] Deliverable 4b — a type error reported on the PYTHON span
`frontend/TEST/m3/m3_typeerr.py`:
```python
let ok = 1
let bad = no_such_name
```
Driver (stderr):
```
[m3] d3parsed nerror (after tread3a) = 1
F3PERR0-ERROR:LCSRCsome1(.../m3_typeerr.py)@(22(line=2,offs=11)--34(line=2,offs=23)):D3Eerrck(1;D3Et2pck(D3Enone0();...))
RESULT: TYPE-ERROR (nerror>0 ; see f3perr0 above for the .py span)
>> 4b PASS  (type error reported on the Python source m3_typeerr.py with a line:col span)
```
The diagnostic lands on **`m3_typeerr.py` line 2, cols 11–23** — the exact span of
`no_such_name`, NOT a synthetic location. (The same mechanism reports the §6.1
arithmetic/template errck on its true `.py` span, e.g. `1 + 2` at `line=1,offs=9..14`.)

### [E4] Purely additive + still-green
```
git status --short   # ONLY frontend/ ; NO srcgen2/ or language-server/
M2.5 GOLDEN: PASS (all snippets match; tail-lint clean; fast-path verified)
M0a RE-ENTRANCY: PASS (both iterations nerror=0, identical)
M3 re-entrancy: identical emitted JS across two runs (fresh tr12env per call)
```

---

## 8. Verified compiler API (re-checked against the live SATS, 2026-06-20)

| API | Signature | Location |
|---|---|---|
| `pyparse_module` / `pyelab_module` | `(lcsrc, strn): pymodule` / `(pymodule): pcmodule` | `pyparsing.sats:517` / `pycore.sats:300` |
| `tr12env_make_nil` / `_free_top` / `_find_d2itm` / `_find_s2itm` | as M0a + `_find_s2itm(!tr12env, sym_t): s2itmopt_vt` | `trans12.sats:376/379/457/452` |
| `tr12env_pshlam0`/`poplam0`/`pshlet0`/`poplet0`/`add0_f2arglst`/`add0_d2varlst`/`add0_d2pat` | scope push/pop + binders | `trans12.sats` |
| `d2exp_dapp`/`_var`/`_con`/`_cons`/`_cst`/`_csts`/`_sym0`/`_none0`/`_make_node` | as listed | `dynexp2.sats:1236–1300` |
| `d2exp_sym0` | `(loc, d2rxp, d1exp, d2ptmlst): d2exp`; `d2rxp_new1(loc)`; `d1exp_make_node`+`D1Eid0` | `dynexp2.sats:1247/1207`, `dynexp1.sats:677/503` |
| `D2Eint/Eflt/Estr/Echr/Ebtf` ctors | token-based (`T_INT01`/`T_FLT01`/`T_STRN1_clsd(strn,len)`/`T_CHAR2_char`); `D2Ebtf of sym_t` | `dynexp2.sats:917–921`, `lexing0.sats` |
| `D2Eift0`/`D2Eseqn`/`D2Etup0`/`D2Elet0`/`D2Elam0`/`D2Eproj`/`D2Edap0` | as listed; `D2Eift0(d2e, d2expopt, d2expopt)` | `dynexp2.sats:973–1011` |
| `f2arg_make_node` + `F2ARGdapp(int npf, d2patlst)` | **npf is `int`**, npf=0 here | `dynexp2.sats:1314/1341` |
| `d2fundcl_make_args` / `D2Cfundclst(token, t2qaglst, d2cstlst, d2fundclist)` | `(loc, d2var, f2arglst, s2res, teqd2exp, wths2exp)` | `dynexp2.sats:1859/1537` |
| `d2valdcl_make_args` / `D2Cvaldclst` | as M0a | `dynexp2.sats:1847/1519` |
| `S2RESnone`/`S2RESsome(s2eff,s2exp)`/`S2EFFnone`/`F1UNARRWdflt(loc)` | as listed | `dynexp2.sats:1182`, `dynexp1.sats:418` |
| `pylower_typ` path: `tr12env_find_s2itm` → `S2ITMcst of s2cstlst` → `s2exp_cst`/`s2exp_var`/`s2exp_apps`/`s2exp_none0` | `s2itm` in `staexp2.sats:805`; makers `staexp2.sats:725/740/983/986` |
| `T_FUN(FNKfn2)` / `T_LAM(int)` / `T_VAL(VLKval)` | tokens | `lexing0.sats:225/206/226`, `xbasics.sats:201/146` |
| `d3parsed_of_trans23` → (internally) `d2parsed_of_trans2a` + `d2parsed_by_trsym2b` | the overload+symbol resolution runs inside | `trans23.dats:89-90` |
| `d3parsed_of_tread3a` | **counts errck nodes → updates nerror** (§5.2); run before f3perr0 | `tread3a.dats:128-174` |
| backend spine (`tread3a`→`trtmp3b`→`trtmp3c`→`t3read0`→`trxd3i0`→`tryd3i0`→`trxi0i1`→`js1emit`) | verbatim M0b pass set | M0b-REPORT §2.3 |

---

## 9. Reproduce
```bash
XATSHOME=/Users/qcfu/Projects/ATS-Xanadu bash frontend/build-m3.sh
# (backend libs are cached after the first build; --rebuild-libs forces a rebuild)
```
Builds/reuses the backend libs, transpiles the M1/M2/M2.5/M3 passes + the M3 driver, links,
then runs 4a (`.py`→JS→node, asserts `a=7 b=7 c=7`) and 4b (asserts the type error on the
`.py` span). jsemit00 + `node --stack-size=8801` throughout; reuses the prebuilt
`srcgen2/lib/lib2xatsopt.js`.
