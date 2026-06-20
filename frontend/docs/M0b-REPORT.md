# M0b — codegen seam: hand-built L2 → JS, end-to-end — implementation report

> **Status: DONE.** A type-checked `d3parsed` for `val x = 1 ; val y = x` drives
> cleanly through the **in-memory `xats2js` backend** (8 passes, replicating
> `mymain_work` in `xats2js_jsemit01.dats`), emits the user program's JavaScript
> with **0 errors / 0 errck**, and the emitted JS **runs on `node` and exits 0**.
> The emitted JS visibly contains the `x`/`y` bindings
> (`jsxtnm1 = XATSINT1(1)`; `jsxtnm2 = jsxtnm1`), and a runtime probe confirms
> `x=1, y=1` actually bind at run time. Purely additive: `git status` shows only
> `frontend/`; the stock backend `lib/` dirs still hold only `.keeper`. M0a still
> passes (`RE-ENTRANCY: PASS`).

This closes the end-to-end "compile to JS" tracer bullet and retires R1 (the
in-memory codegen seam): the frontend can hand a `d3parsed` to the real
`xats2js` backend, linked as a library, and get runnable JavaScript out — no
file round-trip, no stock `mymain` driver.

---

## 1. What was built (all new files under `frontend/`)

| File | Role |
|---|---|
| `frontend/DATS/pyfront_m0b.dats` | The codegen driver: builds a codegen-correct L2 `val x=1; val y=x`, runs `d3parsed_of_trans23`, then the 8 xats2js backend passes, and `i1parsed_js1emit` to stdout. REUSES `pyfront_m0a_check()`. |
| `frontend/SATS/pyfront_m0b.sats` | Documents the M0b surface (`pyfront_m0b_emit`). Not staloaded by the DATS (see §5.2). |
| `frontend/CATS/pyfront_m0b.cats` | FFI glue: `PYF2_log*` → `process.stderr` (progress), `PYF2_mark` → `process.stdout` (the JS sentinels). |
| `frontend/build-m0b.sh` | One command: build backend libs → transpile drivers → link → emit JS → run emitted JS. |
| `frontend/BUILD/lib2xats2cc.js`, `lib2xats2js.js` | The two backend libs, **built from source** (the stock `lib/` dirs ship only `.keeper`). |
| `frontend/BUILD/pyfront-m0b.js` | The linked compiler bundle (~207 MB). |
| `frontend/BUILD/emitted-user.js` | The emitted user-program JS (extracted between sentinels). |
| `frontend/BUILD/run-emitted.js` | The emitted program + prepended ATS→JS runtime, ready to run on node. |

`build-m0b.sh` runs in ~1 min (≈33 backend DATS transpiled at ~1.5 s each + link).

---

## 2. The xats2js link recipe (seed for ENGINEERING.md)

**The crux of M0b.** `xats2js` is a separate source tree
(`srcgen2/xats2cc/srcgen1/` for intrep0 + L3→intrep0, and
`srcgen2/xats2js/srcgen2/` for intrep1 + intrep0→intrep1 + JS emit). Its
functions are **not** in `lib2xatsopt.js`. The stock `xats2js_jsemit01` is built
by `srcgen2/xats2js/srcgen2/UTIL/Makefile_xjsemit` (target `xats2js_jsemit01`):
it links **three** libraries, each in its own `js{1,2,3}` namespace, on top of
the runtime.

**No prebuilt backend libs ship.** `srcgen2/xats2cc/srcgen1/lib/` and
`srcgen2/xats2js/srcgen2/lib/` contain only `.keeper` (and a prebuilt
`lib2xats2js.js` does NOT exist). So M0b **builds the two backend libs from
source**, then links them exactly as the stock Makefile does. (A fully-linked
prebuilt `xassets/JS/xats2js/xats2js_jsemit01_ats3_opt1.js` does exist and was
used only as a *reference oracle* to confirm the target JS shape — it is not
linked into our bundle, because its `mymain` reads a file path and cannot be fed
an in-memory `d3parsed`.)

### 2.1 Building each backend lib (mirrors `{xats2cc,xats2js}/.../Makefile_xjsemit`)

For each DATS in the stock `SRCDATS` list, in dependency order:
1. transpile via **jsemit00** (`xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js`),
   `node --stack-size=8801`;
2. per-file-namespace it with `sed 's/jsxtnm/jsx<NNN>tnm/g'`, where `<NNN>`
   **starts at 100** (the stock Makefile's `NFILE = N064 N032 N004 = 100`);
3. concatenate.

- **`lib2xats2cc.js`** ← `srcgen2/xats2cc/srcgen1/DATS/` source set (16 files):
  `intrep0[, _print0, _utils0]`, `trxd3i0[, _print0, _myenv0, _statyp, _dynexp,
  _decl00]`, `tryd3i0[, _myenv0, _dynexp, _decl00]`, `intrep1[, _print0]`,
  `xats2cc_tmplib`.
- **`lib2xats2js.js`** ← `srcgen2/xats2js/srcgen2/DATS/` source set (17 files):
  `intrep1[, _print0, _utils0]`, `trxi0i1[, _myenv0, _dynexp, _decl00]`,
  `xats2js[, _myenv0, _utils0, _dynexp, _decl00]`, `js1emit[, _utils0, _dynexp,
  _decl00]`, `xats2js_tmplib`.

**Why the counter MUST start at 100** (verified-the-hard-way discrepancy):
`lib2xatsopt.js` uses `jsx<NNN>tnm` with **3-digit** suffixes (jsx100tnm…); the
final link sed is `jsx(...)tnm` — **exactly three chars**. A 1-based counter
produced `jsx1tnm`/`jsx12tnm` (1–2 digit) which (a) the final sed could not
remap into js2/js3 and (b) **collided** between the two backend libs. Starting
at 100 makes every per-file token 3-digit, so the final sed remaps them and the
namespaces stay disjoint. (See §5.1.)

### 2.2 The final compiler-bundle link (verbatim shape of `Makefile_xjsemit`)

```
cat  runtime/*  >  bundle.js                       # 5 runtime files (see §2.4)
sed -E 's/jsx(...)tnm/js1\1tnm/g'  lib2xatsopt.js  >> bundle.js   # REUSED prebuilt
sed -E 's/jsx(...)tnm/js2\1tnm/g'  lib2xats2cc.js  >> bundle.js   # built in §2.1
sed -E 's/jsx(...)tnm/js3\1tnm/g'  lib2xats2js.js  >> bundle.js   # built in §2.1
cat  frontend/CATS/pyfront.cats  pyfront_m0b.cats  >> bundle.js   # FFI glue
cat  pyfront_dats.js  pyfront_m0b_dats.js          >> bundle.js   # M0a + M0b drivers
```

After linking, the bundle has `js1100…`, `js2100…`, `js3100…` tokens (61 / 15 /
16 distinct). The 87 leftover bare `jsx1tnm…jsx99tnm` tokens are
**lib2xatsopt-internal** (it carries both 3-digit and 1–2-digit forms); the stock
3-char sed leaves the 1–2-digit ones un-prefixed too — they live in the js1 space
and collide with nothing (the backend libs contribute no bare `jsx` tokens after
§2.1's 3-digit fix). This is identical to stock `xats2js_jsemit01` behaviour.

### 2.3 The verified pass sequence (replicates `mymain_work`)

`srcgen2/xats2js/srcgen2/UTIL/xats2js_jsemit01.dats:96-170`. Every name/signature
re-verified against the live SATS (2026-06-20); `i0parsed_of_tryd3i0` is included
(the stock `mymain_work` body inlines it as `tryd3i0`). The driver feeds
`d3parsed_of_trans23(build_d2parsed_codegen())` in place of `d3parsed_of_fildats(fpth)`:

| Pass | Verified signature | Location |
|---|---|---|
| `d3parsed_of_tread3a` | `(dpar: d3parsed): (d3parsed)` | `srcgen2/SATS/tread3a.sats:119` |
| `d3parsed_of_trtmp3b` | `(dpar: d3parsed): d3parsed` | `srcgen2/SATS/trtmp3b.sats:212` |
| `d3parsed_of_trtmp3c` | `(dpar: d3parsed): d3parsed` | `srcgen2/SATS/trtmp3c.sats:266` |
| `d3parsed_of_t3read0` | `(dpar: d3parsed): (d3parsed)` | `srcgen2/SATS/t3read0.sats:122` |
| `i0parsed_of_trxd3i0` | `(dpar: d3parsed): i0parsed` | `srcgen2/xats2cc/srcgen1/SATS/trxd3i0.sats:53` |
| `i0parsed_of_tryd3i0` | `(ipar: i0parsed): i0parsed` | `srcgen2/xats2cc/srcgen1/SATS/tryd3i0.sats:53` |
| `i1parsed_of_trxi0i1` | `(ipar: i0parsed): i1parsed` | `srcgen2/xats2js/srcgen2/SATS/trxi0i1.sats:124` |
| `i1parsed_js1emit` | `(ipar: i1parsed, filr: FILR): void` | `srcgen2/xats2js/srcgen2/SATS/js1emit.sats:202` |

### 2.4 The runtime to RUN the emitted program

The emitted user-program JS references the same ATS→JS runtime the compiler uses
(`XATSINT1`, `XATS000_patck`, …) plus the L2 prelude's JS impls. `build-m0b.sh`
makes `run-emitted.js` = the 5 runtime files + `lib2xatsopt.js` (sed→js1) +
`emitted-user.js`, then runs it on node. The 5 runtime files (verbatim from
`Makefile_xjsemit`):
`srcgen2/.../runtime/xats2js_js1emit.js`, `srcgen2_precats.js`,
`srcgen1/.../runtime/srcgen1_prelude.js`, `srcgen1_prelude_node.js`,
`srcgen1_xatslib_node.js`. (`g_stdout()` → `process.stdout`,
`strn_fprint` → `out.write` — so `i1parsed_js1emit` writes JS text to stdout.)

---

## 3. Captured evidence

### [E1] M0b driver transpile — 0 errors, 0 errck
```
transpile exit=0  lines=6025
F2/F3 errors: 0   errck-in-JS: 0
```

### [E2] compiler-bundle stderr — the 8-pass codegen spine
```
######## M0b codegen-spine driver ########
program (reused from M0a): val x = 1 ; val y = x
[m0b] (reused) pyfront_m0a_check nerror = 0
[m0b] codegen d3parsed nerror = 0
[m0b] tread3a done
[m0b] trtmp3b done
[m0b] trtmp3c done
[m0b] t3read0 done
[m0b] trxd3i0 (L3 -> intrep0) done
[m0b] tryd3i0 (intrep0 resolve) done
[m0b] trxi0i1 (intrep0 -> intrep1) done
[m0b] js1emit done (emitted user-program JS to stdout)
RESULT: PASS (codegen spine: d3parsed -> xats2js -> JS, nerror=0)
>> compiler-bundle exit code: 0
```

### [E3] emitted user-program JS (`frontend/BUILD/emitted-user.js`)
```js
// I1Dvaldclist(()@(0(line=0,offs=0)--0(line=0,offs=0)))
// I1VALDCL
let jsxtnm1
jsxtnm1 = XATSINT1(1)
XATS000_patck(true)
// I1Dvaldclist(()@(0(line=0,offs=0)--0(line=0,offs=0)))
// I1VALDCL
let jsxtnm2
jsxtnm2 = jsxtnm1
XATS000_patck(true)
```
The `x` binding is `jsxtnm1 = XATSINT1(1)`; the `y` binding is `jsxtnm2 = jsxtnm1`
(`y` copies the *same* runtime slot `x` bound — direct-to-L2 binding+lookup share
one entity). This matches the stock `xats2js_jsemit01` output for the real
`val x=1; val y=x` byte-for-byte (modulo location comments).

### [E4]/[E5]/[E6] grep + run + runtime probe
```
grep:  3:let jsxtnm1   4:jsxtnm1 = XATSINT1(1)   8:let jsxtnm2   9:jsxtnm2 = jsxtnm1
run:   emitted-program exit code: 0
probe: RUNTIME-PROBE x=1 y=1     # appended console.error proves bindings took effect
```

---

## 4. Purely-additive + M0a-still-passes checks

```
$ git status --short        # only frontend/ ; NO srcgen2/ or language-server/
 M frontend/docs/PYTHON-FRONTEND-PLAN.md     (pre-existing architect edit)
?? frontend/{BUILD,CATS,DATS,SATS}/  frontend/build-m0b.sh  frontend/docs/M0b-REPORT.md
$ ls srcgen2/xats2cc/srcgen1/lib  srcgen2/xats2js/srcgen2/lib   # still .keeper only
$ bash frontend/build-m0a.sh | grep RE-ENTRANCY
RE-ENTRANCY: PASS (both iterations nerror=0, identical)
```
The backend libs are written into `frontend/BUILD/`, never into the stock `lib/`
dirs. `pyfront.dats`/`pyfront.sats`/`build-m0a.sh` are untouched.

---

## 5. Discrepancies vs the docs / the M0a inheritance (all REAL fixes)

### 5.1 Backend-lib per-file namespace counter MUST start at 100 (Δ, blocking)
The stock `Makefile_xjsemit` `NFILE` arithmetic (`N064 N032 N004`) means the
per-file `jsx<NNN>tnm` counter starts at **100**, making every token 3-digit so
the final `jsx(...)tnm` (3-char) sed remaps it into js2/js3. A naive 1-based
counter silently breaks namespacing (js2/js3 empty; `jsx1tnm` collides across the
two backend libs). Not obvious from reading the Makefile; verified by inspecting
the linked bundle's token spaces.

### 5.2 A `.sats`'s nested `#staload`s do NOT re-export to a DATS that staloads it (Δ, blocking)
First attempt put all backend `#staload`s inside `pyfront_m0b.sats` and had the
DATS `#staload` that one SATS. Result: every backend call lowered to
`D2Eerrck(D2Enone1(D1Eid0(...)))` — **the names were not in scope**. Fix: the
backend `#staload`s (and `t3read0`, and `pyfront.sats`) must sit **directly in
the DATS** where they are used, exactly as `xats2js_jsemit01.dats:59-72` does.
(Probes confirmed the same staload set resolves cleanly when placed in the DATS.)

### 5.3 `d3parsed_of_t3read0` is NOT in `srcgen2/HATS/libxatsopt.hats` (Δ)
The top-level `libxatsopt.hats` staloads `tread3a`/`trtmp3b`/`trtmp3c`/`f3perr0`
but **not** `t3read0`. (The *xats2js-local* `libxatsopt.hats` is different.) M0b
staloads `srcgen2/SATS/t3read0.sats` explicitly.

### 5.4 Passing a `FILR` across a SATS-declared boundary tripped a `T2Pnone0` type-pack (Δ)
Calling `pyfront_m0b_emit(filr)` where it was declared in the SATS produced
`D3Et2pck(filr; FILEref_tbox; T2Pnone0())` at the call site (the param type read
as `none`), even though the body's `i1parsed_js1emit(ipar, filr)` typechecked
with the same value. Fix: make `pyfront_m0b_emit` a **local `fun` with an
explicit `: FILR` annotation** in the DATS (not via the SATS). The SATS is kept
as documentation only and is not staloaded.

### 5.5 The big one — `D2Ei00` has NO codegen lowering; codegen needs token-based `D2Eint` (Δ, blocking)
M0a built `val x = 1` with the **unboxed** literal `D2Ei00(sint)`
(`dynexp2.sats:923`). That **type-checks** (M0a nerror=0) but the xats2cc
lowering `trxd3i0_dynexp.dats` has an arm only for **`D3Eint of token`** (line
845); `D3Ei00` (`dynexp3.sats:405`) is handled **nowhere** in the backend, so it
falls through to an `I0Enone1` placeholder and `js1emit` dumps a debug node
(`jsxtnm1 = I1Vnone1(I0Enone2(…; D3Ei00(1)))`) — **invalid JS**.

Fix: M0b rebuilds the *same* program with the **token-based** literal
`D2Eint(token T_INT01("1"))` — exactly what the real parser emits
(`trans23_dynexp.dats:1072` → `D3Eint` → `f0_int` → `I0Eint` → `XATSINT1(1)`). The
binding+resolution machinery (M0a's heart) is replicated unchanged
(`tr12env_add0_d2pat` to bind `x`; `tr12env_find_d2itm` to resolve the use-site
`x`). M0b still **calls** `pyfront_m0a_check()` to exercise and report the reused
typecheck spine (its `nerror = 0` is printed), but feeds the codegen-correct
`d3parsed` to the backend. **Action for M1: lower Python int literals to
token-based `D2Eint` from the start** so the typecheck and codegen spines share
one program builder.

---

## 6. STRETCH goal (observable print) — intentionally deferred to M3
Adding a top-level `val () = <prelude print>("…")` would need (a) resolving a
prelude print `d2cst` via the env's `D2ITMcst` arm and (b) a string-literal node
(`D2Estr(token T_STRN1…)`) with the right lowering. That is real lowering risk
for a tracer bullet whose REQUIRED bar (clean emit + `node` exit 0 + visible
x/y bindings) is already met, so per the brief it is **skipped and logged for
M3**. Observability is instead proven by the runtime probe in [E6]
(`RUNTIME-PROBE x=1 y=1`): the emitted bindings provably take effect at run time.

---

## 7. Reproduce
```bash
XATSHOME=/Users/qcfu/Projects/ATS-Xanadu bash frontend/build-m0b.sh
```
Builds backend libs → transpiles drivers → links → emits JS → runs the emitted
JS, with no manual steps. Uses **jsemit00** and `node --stack-size=8801`
throughout; **reuses** the prebuilt `srcgen2/lib/lib2xatsopt.js` (never rebuilt).
```
