# Pythonic → Chez bootstrap — integration status

Date: 2026-06-27

This note covers wiring the **Pythonic frontend** to the **xats2cz Chez backend** —
steps 2–4 of the BOOTSTRAP-PLAN ("swap the frontend to pythonic", "compile pythonic
with the pythonic frontend", "emit chez"). It follows the xats2cz bootstrap model
(see the `xats2cz-project` memory + `srcgen2/xats2cz/docs/`).

## Architecture (the load-bearing invariant)

The Pythonic frontend is **purely parse → lower to a faithful L2 `d2parsed`**. Everything
from L2 onward — overload/symbol resolution, the L2→L3 read, **template resolution
(trtmp3b/trtmp3c)**, `trxd3i0`, `cz0emit` — is the **stock compiler, run UNCHANGED**. We
never touch or special-case L3. If something fails downstream, the cause is that our L2
`d2parsed` is not faithful, and the fix belongs in the frontend's lowering.

## ★ Result: pythonic `m0_hello` compiles to Chez, byte-identical to stock ★

```
# frontend/TEST/cz/cz_hello.pdats  (faithful pythonic m0_hello — the SAME #includes)
include "prelude/HATS/prelude_dats.hats"
include "prelude/HATS/prelude_JS_dats.hats"
sint_print(42)
strn_print("\n")
the_print_store_log()
```
→ `pyfront` (parse/elaborate/lower/typecheck, nerror=0) → `i0parsed_of_trxd3i0` →
`i0parsed_cz0emit` emits:
```scheme
((lambda ( i0_4945_3649) (XATS2JS_sint_print i0_4945_3649)) 42)
((lambda ( cs_5081_2144) (XATS2JS_strn_print cs_5081_2144)) "\n")
((lambda () ((lambda ( x0_4773_1615) (XATS2JS_console_log x0_4773_1615)) ((lambda () (XATS2JS_the_print_store_flush))))))
```
which is **BYTE-IDENTICAL** to stock `srcgen2/xats2cz/TEST/m0_hello.dats`'s emitted Scheme
(stamps and all), runs on Chez, and prints `42`. **Full prelude-template resolution works**
through the unchanged backend (`sint_print`/`strn_print`/`the_print_store_log`/`console_log`/
`the_print_store_flush` all inline as nested closures). Green gate: `bash frontend/build-cz.sh`.

## What was built (frontend-only, additive)

- **`frontend/DATS/pyfront_cz.dats`** — the combined driver: pyfront's frontend half
  (`pyparse_module` → `pyelab_module` → `pylower_decls` → `d2parsed_make_args`) then the
  **COMPLETE stock codegen pipeline** — the exact sequence stock `d3parsed_of_fildats` runs via
  `d3parsed_of_trans03` (xatsopt_utils0.dats): `tread12 → trans2a → trsym2b → t2read0 → trans23
  → tread23 → trans3a → tread3a → trtmp3b → trtmp3c → t3read0` → **`i0parsed_of_trxd3i0`**
  [xats2js **srcgen1**] → **`i0parsed_cz0emit`**. Sets the `--_XATS2JS_` flags. The prelude is
  brought in by the SOURCE's own `include` decls. Every pass is a stock call — no L3 code is
  modified; the driver just runs the stock pipeline in full.
- **`frontend/build-cz.sh`** — build/run harness. Reuses xats2cz's prebuilt pre-namespaced
  libs `srcgen2/xats2cz/BUILD/{opt.js1,js.js2,lib2xats2cz}.js`; transpiles frontend passes +
  driver; links + closure-minifies; runs the test → extracts Scheme between the
  `;;==XATS2CZ-BEGIN/END==` sentinels → runs on Chez → asserts output.
- **`frontend/TEST/cz/cz_hello.pdats`** — the faithful pythonic `m0_hello`.

## Why the cz path is the right backend

It uses **only `i0parsed_of_trxd3i0`** (NO `tryd3i0`) → sidesteps the `i0varfst_mklst`
codegen-lib gap that the xats2cc/intrep1 JS path hits; and `cz0emit` is the COMPLETE,
self-hosting backend (77/77 tests, recompiles its own 171 files byte-identically).

## Two integration gotchas (resolved)

1. **Stale-cache stamp drift ([[ats3-jsemit-clean-build]]).** The gitignored
   `frontend/BUILD/*_dats.js` cache was transpiled against an older srcgen2 than the current
   `lib2xatsopt` (`d2pat_make_node_17190` vs `_17194`) → `ReferenceError`. Fix:
   `build-cz.sh --retranspile` re-transpiles the frontend so stamps align with the prebuilt
   libs. Always re-transpile the frontend when reusing a fresh `lib2xatsopt`.
2. **The prelude is brought in via the source's own `include`.** `the_tr12env_pvsl00d`
   loads only the prelude *interfaces*; a Pythonic file gets the BACKEND impls (the `#impltmp`s)
   the same way a stock file does — via its `include` decls, which `lower_include` splices into
   the `d2parsed`. An earlier attempt to merge the JS prelude into the *global* env
   (`filpath_pvsload`) was WRONG: it half-resolved names but mangled `fun<>` schemes
   (`T2Pnone0`) and never reached the template-resolution env. Removed.

## ★ THE root cause of the "templates don't codegen" gap (#13b) — RESOLVED ★

It was **not** a template-resolution problem and **not** a `lower_include` problem. The driver
was replicating **`trans03_from_fpath`** (trans23.dats) — the **typecheck-only** pipeline, which
deliberately omits `trans3a`. The *codegen* pipeline stock uses is **`d3parsed_of_trans03`**
(xatsopt_utils0.dats, what `d3parsed_of_fildats` runs): it adds **`tread23` + `trans3a`** after
`trans23`. **`trans3a` builds the template env (`t3penv`)** — and recurses into staloads
(trans3a_decl00.dats:338) to build *their* `t3penv`s. The backend's template resolution reads
that `t3penv` (`static_search_dcst` → `topmap_search$opt` over the staload module's
`D3TOPENVsome(tmap)`). Without `trans3a`, every staloaded prelude template instance resolved to
nothing → dropped at codegen. (Direct `.dats` includes happened to work anyway because their
impls land as top-level `D3Cimplmnt0`, found by `tmpstk_search_dcst`'s `test` without needing the
staload `t3penv`.)

**Fix (driver-only, no L3 change):** `cz_d3parsed_of_fpath` now runs the full stock pipeline,
matching `d3parsed_of_trans03` exactly (`…trans23 → tread23 → trans3a → tread3a → trtmp3b →
trtmp3c → t3read0`). Result: the natural `#include "prelude/HATS/prelude_JS_dats.hats"` codegens,
byte-identical to stock. NB this likely fixes the JS path (`pyfront_m3`) too — it had the same
incomplete pipeline.

## Next steps (toward stage2==stage3)

1. (Optional cleanup) name the post-d2 stock pass sequence once in the driver rather than
   hand-listing it, so it can't silently drift out of sync with stock again — or wire the
   pythonic frontend in as an alternate frontend of the stock driver.
2. Per-file round-trip with a Chez oracle: `pyprint` a real source file → compile through
   `pyfront_cz` → diff the emitted Scheme against stock xats2cz for the same file.
3. Corpus round-trip, then the fixpoint (pythonic-built compiler recompiles the pythonic
   compiler source; stage2==stage3).
