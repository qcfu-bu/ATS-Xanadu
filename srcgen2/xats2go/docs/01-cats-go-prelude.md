# CATS/GO — the typed Go primitive floor (the right prelude model)

> Status: STARTED 2026‑06‑29. Corrects a wrong assumption ("reimplement the
> whole prelude in Go") with the model the JS/Chez/PY backends already use.

## The model (corrected)

The ATS3 prelude is **shared ATS source**. A backend **compiles** it like any
other code; it does **not** reimplement it. The only hand‑written, per‑backend
code is a small **primitive FFI floor** — the `prelude/DATS/CATS/<BACKEND>/`
tree of `.dats` arms + `.cats` primitive bodies:

- **`CATS/<B>/<mod>.dats`** — the backend arm: one `#impltmp` per primitive,
  rebinding the generic `XATS000_*` extern to a backend‑specific `XATS2<B>_*`
  one (e.g. `sint_neg(i1) = XATS2GO_sint_neg(i1)`).
- **`CATS/<B>/<mod>.cats`** — the actual primitive bodies in the target
  language (`func XATS2GO_sint_neg(i1 int) int { return -i1 }`).
- **`prelude/HATS/prelude_<B>_cats.hats`** — `#extcode file`‑splices the `.cats`
  floor into the emitted output.

The whole JS floor is **95 primitives across 14 tiny modules** (`bool/char/
gint/gflt/strn/list/optn/strm/strx/axrf/axsz/xtop/gbas/gdbg`). `CATS/GO` is the
same 14 modules, **typed**. Everything else — `list000.dats`, `optn000.dats`,
`strm000.dats`, the real data‑structure logic — is shared ATS compiled to Go.

**Why typed matters / why now:** Go's `.cats` must carry concrete types
(`func XATS2GO_sint_neg(i1 int) int`). That only links if the *compiled prelude*
also emits concrete Go types — which is exactly what the typed‑intrep1 redesign
(docs/00, S0–S3, 75/75 green) now provides. The current ad‑hoc
`runtime/xatsgo/xatsgo.go` (16 functions) is what this supersedes.

## The pivot it implies (the engine, not just the floor)

Today xats2go **shortcuts** prelude calls — native Go operators for scalar ops,
`xatsgo.Xats_*` runtime calls otherwise — and the driver passes **`--_XATS2JS_`**
(`xats2go_goemit01.dats:205`), so the prelude resolves the *JS* arm. To actually
use `CATS/GO`, the backend must instead **compile the prelude template bodies**
(the xats2cz inline‑template strategy), bottoming at `XATS2GO_*`. `CATS/GO` is
inert without this.

## Vertical slice — the ordered plumbing (shared by all 14 modules)

1. **`CATS/GO/gint000.{dats,cats}` + `prelude_GO_cats.hats`** — ✅ this commit
   (additive; the first module, faithful to `CATS/JS`).
2. **`_XATS2GO_` dispatch** in `srcgen2/HATS/xatsopt_dpre.hats` — mirror the
   `#if defq(_XATS2JS_)` arm (the `basics{1,2,3}`/`g_eqref`/`g_print` includes
   get GO analogs under `prelude/DATS/CATS/GO/`), and add the
   `xlibext_goemit` staload analog.
3. **Driver flag** — `xats2go_goemit01.dats`: pass `--_XATS2GO_`
   (+`--_SRCGEN2_XATS2GO_`) instead of the JS flags, so prelude resolution
   selects the GO arm. (Verify the `pvsl00d`/`pvsl01d` store choice matches the
   tree that *defines* the GO arm, per docs/00 of xats2cz §3.)
4. **Emitter `.cats` linking** — splice `prelude_GO_cats.hats`'s `.cats` floor
   into the emitted Go package (the harness already assembles a Go module; add
   the floor + a GO precats defining `XATS2GO_the_print_store` and imports
   `strconv`). Analog of how `build-go.sh` prepends `runtime/xatsgo`.
5. **Prove** `make run/test02_arith` (an int program) byte‑equal through the
   oracle with the prelude now flowing through `CATS/GO`, not the shortcut.
6. **Scale** — add the remaining 13 modules (mechanical: copy the JS arm,
   `XATS2JS`→`XATS2GO`; translate the one‑line `.cats` bodies to typed Go).

Steps 2–4 likely require a `lib2xatsopt` rebuild (dpre.hats is frontend‑wide)
and careful prelude‑store handling; they are build‑gated and land as a
coordinated, oracle‑validated change — not piecemeal (flipping the driver flag
before the GO arms exist would break the green suite).

## Are we ready to self‑host?

Not yet — but the remaining prelude work is the **small** floor above plus the
compile‑the‑prelude pivot, **not** a from‑scratch Go prelude. After that: the
Class‑C cross‑module frontend accessors (docs/00 §self‑hosting) and scaling up
the escalation ladder (large programs → a prelude module → the emitter's own
sources → the full compiler).
