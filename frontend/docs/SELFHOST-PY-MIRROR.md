# Pythonic self-host: the PY/ mirror + chez compiler

Date: 2026-06-27

Goal: a `frontend/PY/` pythonic mirror of the ATS3 compiler (the xats2cz bootstrap set) +
a working chez `.scm`/`.so` compiler built by compiling that mirror through the pythonic
frontend. This is the BOOTSTRAP-PLAN P3→P4 at full scale.

## Component set (171 + interfaces)
The xats2cz bootstrap list: **162 frontend SRCDATS** (`srcgen2/DATS/`) + **7 xats2js srcgen1
backend** (`intrep0`/`trxd3i0` family) + **cz0emit** + the **driver** = 171 `.dats`, plus all
the `.sats` interfaces they depend on (`srcgen2/SATS`, `xats2js/srcgen1/SATS`, `xats2cz/SATS`).

## Harnesses (frontend/)
- **`convert-py.sh`** — Phase A: pyprint every `.sats`→`.psats` + `.dats`→`.pdats` into `PY/`,
  mirroring the tree. (`--rebuild-pp` to rebuild the pyprint bundle; `--force` to overwrite.)
  Run pyprint from CWD=XATSHOME with XATSHOME exported (it resolves the source path vs CWD and
  the prelude vs XATSHOME).
- **`compile-py.sh`** — Phase C: compile each `PY/*.pdats` through `pyfront_cz` in MIRROR MODE
  (`PYL_MIRROR_ROOT=PY`) → a `.scm` fragment in `BUILD/py-scm/NNNN_<kind>_<base>.scm` (NNNN =
  component order, for assembly). Reports PASS/FAIL per file. (Run ONE at a time — concurrent
  runs corrupt the shared report; the loop reads the file list on fd 3 and runs node `</dev/null`.)
- **`assemble-py.sh`** — Phase D: cat the chez runtime + all fragments (in order) →
  `PY/chez_py_selfhost.scm`, precompile → `PY/chez_py_selfhost.so`. (`--check` diffs vs the seed.)

## Mirror-mode loader (the key new frontend capability)
A pythonic `.pdats` must import its sibling pythonic `.psats`/`.pdats` from `PY/`. Implemented:
- **`PYL_mirror_psats(path)`** (CATS/pylexing.cats): when `PYL_MIRROR_ROOT` is set, rebase an
  XATSHOME-relative `.sats`→`.psats` (interface) or `.dats`→`.pdats` (impl) under the mirror root;
  returns "" if absent (so `fpath_rexists("")` is false → lower_import falls back to the ATS file).
- **`cz_load_pysats` + `lower_import_pysats`** (DATS/pylower_decl00.dats): load a `.psats`/`.pdats`
  through OUR pipeline (pyparse → pyelab → pylower → trans2a → trsym2b), cache it, build its f2env,
  scoped-merge, emit a `D2Cstaload`. This finally lands the once-DEFERRED `is_python` import loader.
  An impl-`.pdats` loaded anonymously becomes an `S2TALOADdpar` that trans23/trans3a process, so its
  cross-module template impltmps resolve at codegen.

## Status: PASS = 117 / 171  (compile pythonic → Chez, mirror mode)
Driven 85 → 111 → 117 via two root-cause frontend fixes:
1. **Anonymous staload `import "X.dats" as _`** (the `_` = anonymous `#staload _ = "X"`): the parser
   diag'd on `_` after `as` (it became a stray `D3Etop`). Fix: `p_import` accepts `PT_USCORE` after
   `as` → bare staload; `PYL_mirror_psats` maps `.dats`→`.pdats` so the impl loads. (+26 files.)
2. **Bodyless dynamic `val NAME: T` in a .sats** was pyprinted as `@static let` (→ PCCstacst, a
   STATIC constant, unbound in dynamic position). Fix: pyprint emits `@extern let`; new PyCore node
   `PCCexternval` + `extern_let_decl` (elab) + `build_extern_val` (lower) → `D2Cdynconst` (VAL). (+6.)

## Remaining failures (54), by category
- **`_symbl`/sort/token constants unbound** (~16): `INT0_symbl`, `SRP_symbl`, `ADD_symbl`,
  `BRCKT_symbl`, `DLRDT_symbl`, `T0IDALP_NONE`, `T0IDSYM_AT0`, `TRUE`/`TRUE_symbl`, `PROPSORT`,
  `TYPESORT`, `P1TR_TBOX_symbl`, `C0FPTR`, … — likely `#stacst` / `#define` / `val=…` decls that
  pyprint renders in a form the consumer can't resolve. NEXT to triage (find the decl shape).
- **F2PERR0 (12)** — parse/lower-level failures (per-file investigation).
- **D3Et2pck (8)** — type mismatches (faithfulness gaps in specific constructs).
- 2 pyprint-side: `xsynoug.psats` empty (comments-only — fine), `xlibext.pdats` crash;
  `trxd3i0_dynexp.pdats` has 1 `# TODO(pp)` marker.

## Stamp-consistency note (why all 171 must pass for a working .so)
Mirror mode stamps names by the `.psats` declaration offset. A working assembled compiler needs
ALL 171 fragments mirror-mode-consistent (can't mix with stock `.sats`-stamped seed fragments).
So Phase D requires 171/171 (or accept a self-consistent pythonic fixpoint distinct from the stock
seed). Keep driving Phase C to 171, then assemble + verify (`assemble-py.sh --check`).
