# Where the scattered dependencies live

> Status: VERIFIED 2026-06-25. The include/staload chain was traced from the
> backend driver; the prelude/xatslib paths match the compile-time
> `d0parsed_from_fpath: source = …` log lines emitted during the from-scratch
> build; runtime file sizes are `wc -l`. Paths absolute from
> `XATSHOME = /Users/qcfu/Projects/ATS-Xanadu`.

When the seed compiles one backend `.dats`, it pulls in source from ~five
different trees. This is the "scattered dependencies" the task warned about. There
are two distinct dependency sets:

- **Compile-time sources** (`#include`/`#staload`): prelude + xatslib + frontend
  SATS, read by the seed while compiling. These determine *what type-checks*.
- **Runtime JS** (`cat`-ed to make a runnable program): the hand-written JS that
  *implements* the `$extnam` primitive floor and the prelude at runtime.

`xats2cz` must replicate the **runtime** set in Scheme; the **compile-time** set is
reused unchanged (the seed reads it for both backends).

---

## 1. The HATS include chain (compile-time glue)

Starting from the backend driver
`srcgen2/xats2js/srcgen1/UTIL/xats2js_jsemit00.dats:38-61`:

| `#include` / `#staload` | Resolves to | Brings in |
|---|---|---|
| `../../../HATS/xatsopt_sats.hats` | `srcgen2/HATS/xatsopt_sats.hats` | the **static interfaces**: prelude `SATS/*` + xatslib `SATS/*` (see below) |
| `../../../HATS/xatsopt_dpre.hats` | `srcgen2/HATS/xatsopt_dpre.hats` | the **prelude/library implementations** (`DATS/*`), incl. JS-guarded CATS |
| `../HATS/libxatsopt.hats` | `srcgen2/xats2js/srcgen1/HATS/libxatsopt.hats` | the **frontend interface chain** (`srcgen2/SATS/*.sats`) the backend links against |
| `../SATS/{intrep0,intrep1,trxd3i0,trxi0i1,xats2js,js1emit}.sats` | backend interfaces | the six backend stages |

### 1a. `srcgen2/HATS/xatsopt_sats.hats` (static interfaces)
- staloads the **prelude SATS** from `srcgen1/prelude/SATS/`: `gbas000`, `gord000`,
  `gnum000`, `gseq000`, `bool000`, `char000`, `gint000`, `gflt000`, `strn000`,
  `arrn000/001`, `list000`, `optn000`, `strm000`, `synoug0`, `tupl000`, plus the
  `VT/` linear variants.
- staloads **xatslib SATS**: `srcgen1/xatslib/libcats/SATS/{libcats,synoug0}.sats`,
  `srcgen1/xatslib/githwxi/SATS/githwxi.sats`.

### 1b. `srcgen2/HATS/xatsopt_dpre.hats` (implementations + backend selection)
- `#include`s **prelude DATS** from `srcgen1/prelude/DATS/`: `gbas000`, `gord000`,
  `gnum000`, `gseq000`, `gmap000`, `genv000`, `bool000`, `char000`, `gint000`,
  `gflt000`, `strn000`, `arrn000`, `axsz000`, `list000`, `optn000`, `strm000`,
  `synoug0`, `tupl000`, `unsafex`, the `CATS/*.dats`, and the `VT/` linear DATS.
- **`#if defq(_XATS2JS_)`** block → includes
  `srcgen1/prelude/DATS/CATS/JS/{basics1,basics2,basics3,g_eqref,g_print}.dats`.
  *(This is where the backend-selection flags from the driver matter; the chez
  build will need an analogous `_XATS2CZ_` arm or to reuse the JS arm + a chez
  runtime — a design decision, see `03-ir-and-templates.md`.)*
- `#include`s **xatslib DATS**: `xatslib/libcats/DATS/synoug0.dats`,
  `xatslib/githwxi/DATS/{genv000,f00path,g00iout}.dats`,
  `xatslib/libcats/DATS/CATS/libcats.dats`; JS-guarded:
  `xatslib/libcats/DATS/CATS/JS/NODE/libcats.dats`,
  `xatslib/githwxi/DATS/CATS/JS/NODE/basics0.dats`.
- staloads the local template libs `../DATS/xlibext_tmplib.dats`,
  `../DATS/xatsopt_tmplib.dats`, and (JS) `../DATS/xlibext_jsemit.dats`.

### 1c. `libxatsopt.hats` (frontend interfaces) — all resolve to `srcgen2/SATS/`
`xbasics`, `xstamp0`, `xsymbol`, `xsymmap`, `xlabel0`, `locinfo`, `lexing0`,
`parsing`, `staexp0/1/2`, `statyp2`, `dynexp0/1/2/3`, `trans01/12/23/3a` + `tread*`,
`trtmp3b/3c`, `t3read0`, `f3perr0`, `xatsopt.sats`, `xglobal.sats`.

---

## 2. The prelude source tree (read by the seed at compile time)

Root: `srcgen1/prelude/` (subdirs `SATS/`, `DATS/`, `HATS/`, `INIT/`, `DATS/VT/`,
`DATS/CATS/JS/`). Plus a root `prelude/` tree and a `srcgen2/prelude/` bridge.

| Entry HATS | Path | Role |
|---|---|---|
| static-interface entry | `srcgen1/prelude/INIT/prelude_sats.hats` | `#include`s all `srcgen1/prelude/SATS/*.sats` (incl. `VT/`) |
| DATS-loading entry | `srcgen1/prelude/HATS/prelude_dats.hats` | staloads prelude `DATS/*` implementations |
| JS DATS entry | `srcgen1/prelude/HATS/CATS/JS/prelude_dats.hats` | JS-flavored prelude_dats (PY/Xint siblings exist) |
| **what user files include** | `prelude/HATS/prelude_dats.hats`, `prelude/HATS/prelude_JS_dats.hats` | the root prelude entry; staloads `prelude/DATS/CATS/JS/{xtop000,gbas000,gdbg000,bool000,char000,gint000,gflt000,strn000,list000,optn000,strm000,strx000,axrf000,axsz000}.dats` |
| srcgen2 bridge | `srcgen2/prelude/HATS/prelude_JS_dats.hats:14-15` | `#include`s `../../../prelude/HATS/prelude_JS_dats.hats` |

A test program's header is simply:
```
#staload _ = "prelude/DATS/gdbg000.dats"
#include  "prelude/HATS/prelude_dats.hats"
#include  "prelude/HATS/prelude_JS_dats.hats"
```
(`xats2cz` tests will need a `prelude_CZ_dats.hats` analog, or reuse the JS one
with a chez runtime.)

---

## 3. xatslib (compile-time, the bits seen in the build log)

- `srcgen1/xatslib/githwxi/DATS/` — `genv000.dats`, `f00path.dats`, `g00iout.dats`
  (the three actually included), plus `dvdcnq0/mygist0/myrand0/mytest0/mytree0/
  parcmb1/xdebug0.dats`.
- `srcgen1/xatslib/githwxi/DATS/CATS/JS/NODE/basics0.dats` (+ `.cats`) — JS/Node glue.
- `srcgen1/xatslib/libcats/DATS/` — `synoug0.dats`, `CATS/libcats.dats`;
  `CATS/JS/NODE/libcats.dats` (+ `.cats`) JS-guarded; `CATS/PY/libcats.dats` is the
  PY counterpart (→ a `CATS/CHEZ/` counterpart is what `xats2cz` adds).

---

## 4. The runtime JS (cat-ed into a runnable program) — REPLICATE IN SCHEME

Two sets, both under `…/xshared/runtime/` (`srcgenx` is a symlink to `srcgen1`).
The `srcgen2_*.js` are built by that dir's `Makefile` from the prelude/xatslib
`.cats` outputs (each = a date line + a `*_hd` header + cat of `.cats`).

### Used by the assembled `jsemit00` compiler (driver §4 of `01-bootstrap.md`)
| File | Lines | Role |
|---|---|---|
| `srcgen2/xats2js/srcgen1/xshared/runtime/xats2js_js1emit.js` | 259 | the JS backend's own emit-runtime shim (print store, helpers) |
| `…/srcgen1/xshared/runtime/srcgen2_precats.js` | 1039 | **precats**: the `XATS000_*` / `XATSDAPP` primitive floor |
| `srcgen1/xats2js/srcgenx/xshared/runtime/srcgen1_prelude.js` | 1734 | prelude runtime (gbas/gint/bool/char/strn/list/optn/strm/…) |
| `…/srcgen1_prelude_node.js` | 166 | Node bindings: `g_print`, stdio |
| `…/srcgen1_xatslib_node.js` | 151 | xatslib for Node (maps, buffers) |

### Used to RUN an emitted user program (the differential JS oracle)
All from `srcgen2/xats2js/srcgen1/xshared/runtime/`, in order:
`srcgen2_prelude.js` (1527) · `srcgen2_prelude_node.js` (123) · `srcgen2_precats.js`
(1039) · `srcgen2_xatslib.js` (392) · `xats2js_js1emit.js` (259) · then the emitted
file. (Verified: this prefix + the emitted `test79` JS prints `3`.)

> **The primitive floor for `xats2cz` is finite and statically determinable.**
> Everything emitted as `XATS000_*` or a bare-`$extnam` name (from `d2cstjs1`'s
> external-name branch) must be provided by a hand-written Scheme runtime — the
> chez analog of `srcgen2_precats.js` + `srcgen2_prelude.js` + the prelude
> `CATS/JS/*.cats`. The prior attempt ported these from the `.cats`/`.js` sources;
> they live (per backend) under `srcgen1/prelude/DATS/CATS/{JS,PY,Xint,CHEZ}/` and
> `…/xatslib/libcats/DATS/CATS/{JS,PY}/`.

---

## 5. One-glance dependency diagram

```
                 srcgen2/HATS/xatsopt_sats.hats ──> prelude/SATS/* , xatslib/SATS/*
                 srcgen2/HATS/xatsopt_dpre.hats ──> prelude/DATS/* , prelude/DATS/CATS/JS/* ,
 backend .dats ──┤                                   xatslib/DATS/* , (JS-guarded NODE cats)
   (seed reads)  ├─ libxatsopt.hats ─────────────> srcgen2/SATS/* (frontend interfaces)
                 └─ ../SATS/{intrep0,1, trxd3i0, trxi0i1, xats2js, js1emit}.sats

 runnable program = [runtime JS: js1emit + precats + prelude + prelude_node + xatslib]
                  ++ js1(lib2xatsopt) ++ js2(lib2xats2js) ++ driver        (see 01-bootstrap.md)
```
