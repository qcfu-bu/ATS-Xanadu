# Engineering handbook — building the Python-surface frontend

> The **proven, verified** build/coding rules for `frontend/`, distilled from the
> M0a/M0b/M1 spikes. Read this before writing any frontend ATS3 code. The
> source-of-truth design is PYTHON-FRONTEND-PLAN.md + LOWERING-MAP.md +
> SURFACE-GRAMMAR.md + LOOP-DESUGARING.md; this file is *how to build it without
> re-hitting the traps we already paid for*. Per-milestone detail lives in
> `M0a-REPORT.md`, `M0b-REPORT.md`, `M1-REPORT.md`.

## 0. Non-negotiables
- **Purely additive.** Never modify anything under `srcgen2/` or `language-server/`.
  The frontend only *calls* the compiler-as-a-library. `git status` must show only
  `frontend/` (build artifacts under `frontend/BUILD/` are gitignored). The
  Python→ATS import boundary is one-directional (plan §5.5): the stock compiler
  stays Python-blind.
- **Re-entrant.** The deno `ats-lsp` is a **resident, long-lived process** (plan
  §6.2) — your code is called repeatedly in one warm V8. So: a **fresh
  `tr12env_make_nil()` per check**, **never mutate the global envs**, return a
  self-contained `d2topenv` via `tr12env_free_top`. Lexer/parser passes are **pure
  per call** (take text, return a fresh value; no module-global mutable state).
  Monotonic stamp bumps across checks are fine. Prove re-entrancy where it matters
  (M0a runs the whole check 2× in one process).
- **Evidence or it didn't happen.** Every milestone ships a reproducible
  `build-<m>.sh` and pasted run output. No success claim without captured stdout.

## 1. The build recipe (verified)
Transpiler is **`jsemit00`**, never `jsemit01`:
`xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js`. Always `node --stack-size=8801`.
Reuse the prebuilt `srcgen2/lib/lib2xatsopt.js` (~171 MB) — **do not rebuild it**
(6–9 min). Canonical scripts: `build-m0a.sh` (typecheck-only), `build-m1.sh` (lexer
harness), `build-m0b.sh` (full codegen→JS→run).

**Typecheck/lexer bundle** (no codegen) = link, in order:
```
runtime[5] + lib2xatsopt.js(sed jsx(...)tnm→js1\1tnm) + frontend .cats glue + driver
```
`runtime[5]` (verbatim, from the resident/xats2js build):
```
srcgen2/xats2js/srcgenx/xshared/runtime/xats2js_js1emit.js
srcgen2/xats2js/srcgenx/xshared/runtime/srcgen2_precats.js
srcgen1/xats2js/srcgenx/xshared/runtime/srcgen1_prelude.js
srcgen1/xats2js/srcgenx/xshared/runtime/srcgen1_prelude_node.js
srcgen1/xats2js/srcgenx/xshared/runtime/srcgen1_xatslib_node.js
```
`.cats` glue must precede the driver (its `require()`d consts are used by the
driver's top-level vals on load; `require` is not hoisted).

## 2. ATS3-Xanadu dialect gotchas (each cost us a debugging cycle)
- **`#implfun NAME(...) = ...`** to implement a SATS-declared function — there is **no
  `implement` keyword** (using it parses into an errck).
- **Three headers** for a standalone driver, not one:
  `#include "srcgen2/HATS/libxatsopt.hats"` (SATS only) **plus**
  `#include ".../xatsopt_sats.hats"` **plus** `#include ".../xatsopt_dpre.hats"`.
  The latter two pull in the prelude **DATS** = template *implementations*; without
  them `=`, `prerrsln`, `list_cons`, `FILR`, etc. are left un-instantiated and
  wrapped in `TIMPLall1(...; T2JAG($list()))` errck. Then `#staload` `locinfo.sats`
  / `lexing0.sats` (and for codegen `t3read0.sats`) which `libxatsopt.hats` omits.
- **Negative literal is `(-1)`, not `~1`.** Anonymous record `'{…}` does **not**
  parse in a standalone DATS — use `@(…)` tuples. Short-circuit `&&`/`||` aren't
  available standalone (stock-parser fixity aliases) — use eager `band`/`bor` or
  nested `if`.
- **A `.sats`'s nested `#staload`s don't re-export** to a DATS that staloads it —
  put backend `#staload`s directly in the DATS that calls them.
- Export `XATSHOME` in the environment before invoking the transpiler.

## 3. Lowering rules (PyAST/PyCore → L2)
- **Use TOKEN-based literal nodes** — `D2Eint`/`D2Eflt`/`D2Estr`/`D2Echr`/`D2Ebtf`
  (synthesize via `token_make_node(loc, T_INT01 "…")` etc.). **Do NOT use the unboxed
  `D2Ei00`/`D2E*00` forms** — M0b observed a bad JS emit from an unboxed int
  (LOWERING-MAP §2.1). The token forms are what the stock parser/`trans12` emit and
  are proven end-to-end.
- **`npf = -1`** on every application/tuple/record (no proof args in v1; plan §6.7).
- **Real `loctn` everywhere.** Thread the lexer's Python span into every L2 node so
  diagnostics land on the `.py` source (plan §6.3). `loctn_dummy()` only for
  genuinely synthetic nodes.
- **nil `d1topenv` = `tr01env_free_top(tr01env_make_nil())`** (plan §6.6).
- Build the `d2parsed` only via `d2parsed_make_args(stadyn, nerror, source, t1penv,
  t2penv, parsed)` — it is an `#abstbox` (opaque). Hand to `d3parsed_of_trans23`.
- Mirror `trans12_*.dats` scope/binding order exactly (LOWERING-MAP §4): push/pop
  scopes, bind-before-RHS only for recursive groups, register cons/csts with
  `tr12env_add1_*`.

## 4. Codegen seam (M0b — R1 retired)
In-memory L3→JS, replicating `xats2js/srcgen2/UTIL/xats2js_jsemit01.dats` `mymain_work`:
```
d3parsed → tread3a → trtmp3b → trtmp3c → t3read0
        → i0parsed_of_trxd3i0 → i0parsed_of_tryd3i0
        → i1parsed_of_trxi0i1 → i1parsed_js1emit(ipar, filr)
```
The backend is a **separate source tree** with no shipped prebuilt lib, so it is
built from source into two libs and linked with **distinct namespaces** js2/js3
(lib2xatsopt is js1):
- `lib2xats2cc.js` ← `srcgen2/xats2cc/srcgen1/DATS/*` (intrep0 + trxd3i0/tryd3i0)
- `lib2xats2js.js` ← `srcgen2/xats2js/srcgen2/DATS/*` (intrep1 + trxi0i1 + js1emit)
**Per-file namespace counter starts at 100** (3-digit tokens `jsx100tnm…`) — required
so the final `sed -E 's/jsx(...)tnm/jsN\1tnm/g'` (exactly 3 chars) remaps them and the
two libs don't collide. See `build-m0b.sh` for the exact source sets/order.
> **Backend-lib caching: DONE** — M3 caches `lib2xats2cc.js`/`lib2xats2js.js` in
> `frontend/BUILD` and reuses them across runs (`--rebuild-libs` forces a rebuild).

### 4.1 Known codegen-infra limits (M3 — the residual of R1)
The in-memory direct-L2 → JS path works for **`val`/`let` + literals + var refs** (M0b,
M3-4a verified). It does **NOT** yet run **functions / arithmetic / `print`**, for two
independent, characterized reasons (M3-REPORT §6.1, build-spike.sh):
1. **`$`-template instantiation.** Prelude operators/`print` are `fun<>` template-implicits
   (`sint_add$sint`, `sint_print`). The stock parser fills the `$sint` arg during trans12
   overload resolution; a **directly-constructed** L2 node leaves an **empty template-arg
   jag** (`T2JAG($list())`) that `tread3a` errcks before `trtmp3b` can instantiate.
2. **funset `fun`-codegen gap.** The **from-source** `lib2xats2cc.js` can't lower a `fun`
   decl — `intrep0_utils0`'s funset-based `#implfun`s (`i0varfst_mklst`, …) transpile to
   errck in isolation under jsemit00. `build-spike.sh` works around it via the prebuilt
   stock `xats2js_jsemit01` oracle (PATH B) — which reads a SOURCE FILE, so it does NOT
   help an in-memory `d3parsed`.

Both are limits of the **from-source backend build + direct-L2 construction** not replicating
what the stock source→JS pipeline does (template fill, funset instantiation) — NOT frontend
bugs. The **LSP/diagnostics path does not need them** (it ends at the typechecked `d3parsed`
+ `f3perr0`, which works on real `.py` — M3-4b).

### 4.2 Error detection in a direct-L2 driver: run `tread3a` FIRST
`d3parsed_of_trans23` records type errors as **errck NODES**, not in the `d2parsed` `nerror`
field (our maker hardcodes 0); `f3perr0_d3parsed` only prints when `nerror>0`. So a direct-L2
driver MUST run **`d3parsed_of_tread3a`** (it scans errck nodes and updates `nerror`) **before**
reading `nerror` / calling `f3perr0` — else errors are silently missed (a false PASS). M0a/M0b
never hit this (error-free programs); M3 found and fixed it.

## 5. Testing
- **Golden tests** for the lexer (token+span dumps; M1 has 7) and parser (PyAST dumps).
- **Differential oracle** (plan §11): write each program twice (ATS surface + Python
  surface), assert identical L2/L3 + identical emitted JS / diagnostics. The stock
  `d2parsed_of_fildats` is the oracle.
- **End-to-end run**: `.py` → JS → `node` → compare stdout to golden.

## 6. Deno ats-lsp integration (M6 target)
Three touch-points (plan §13): (1) `is_python_surface(path)` branch in
`language-server/server/resident/DATS/xats_lsp_resident.dats` `text_validator`(~L600)
+ `live_validator`(~L630); (2) link `frontend/` into `server/resident/build.sh` then
`deno compile --v8-flags=--stack-size=8801`; (3) register `.pats`/`.py` lang-id +
`onLanguage` activation in `language-server/client/{package.json,src/extension.ts}`.
