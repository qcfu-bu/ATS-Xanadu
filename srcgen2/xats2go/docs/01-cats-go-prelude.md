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

## How arm selection ACTUALLY works (verified 2026-06-29 — corrects earlier notes)

Two distinct layers, easy to conflate:

- **Target prelude arm — per-program, RUNTIME, no rebuild.** A program targeting
  a backend `#include`s `prelude/HATS/prelude_<B>_dats.hats`; e.g.
  `test01_xats2go.dats:24` includes `prelude_JS_dats.hats`, which `#staload`s the
  `CATS/JS/*.dats` arms (`sint_neg → XATS2JS_sint_neg`, …). The emitter reads the
  program + its includes at runtime, so **switching a program to the GO arm is
  just `#include prelude_GO_dats.hats`** — **no `lib2xatsopt` rebuild.**
- **The compiler's OWN runtime** (`#if defq(_XATS2JS_)` in `basics0-3.dats` etc.,
  baked into `lib2xatsopt`). These are how the *compiler* runs — and it runs on
  **Node/JS**, so they correctly stay `_XATS2JS_`. They become `_XATS2GO_` work
  only when compiling **the compiler itself** to Go (true self-hosting) — a later
  milestone, NOT a prerequisite for compiling a user program to Go.

So my earlier "needs a `lib2xatsopt` rebuild / `_XATS2GO_` dispatch in dpre.hats"
note was wrong for the user-program case. The pivot is **emitter-side**.

## The real crux: the emitter must USE the floor

Verified emitter facts:
- `I1Vextnam(_tk, ivin, _gnam) ⇒ i1valgo1(filr, ivin)` — an `$extnam` reference
  emits the resolved external NAME, so an `XATS2GO_*` extern emits as a bare call.
- The Go emitter has **no `#extcode` handling** (`grep extcode` ⇒ none): it does
  **not** splice the `.cats` floor into the output.
- Native ops are **shortcut** to Go operators (`a+b`), bypassing the arm — which
  we *keep* (optimal). CATS/GO matters for the **non-native** prelude
  (`list/optn/strm/strn`), today served by `runtime/xatsgo`'s `Xats_*`.
- **The exact bridge today** (`go1emit_dynexp.dats`): `t1imp_func_literal_go1emit`
  emits a template instance's body as a Go func literal **except** when
  `t1imp_xats2js_runtimeq(timp)` (the d2cst name starts `XATS2JS_`) **or**
  `i1dcl_preludeq(idcl)` — both send the call to the `xatsgo.Xats_*` shortcut.
  So the CATS/GO pivot is: add a parallel `t1imp_xats2go_runtimeq` that emits the
  bare `XATS2GO_*` primitive (from the linked `.cats`), and let the chosen
  prelude bodies emit (relax `i1dcl_preludeq` for them) so they reach that leaf.
  **Open integration decision:** the GO precats print store must be SHARED with
  (or replace) `runtime/xatsgo`'s store, else `prints` output won't flush
  consistently — a self-contained CATS/GO I/O path needs `the_print_store_log`
  covered too (xtop000/precats), so the first end-to-end test is an
  int-print program over `gint000` + a GO precats.

## Vertical slice — the corrected, ordered steps

1. **`CATS/GO/gint000.{dats,cats}` + `prelude_GO_{cats,dats}.hats`** — ✅
   (additive; the first module + both manifests).
2. **Emitter `.cats` linking** — assemble the `prelude_GO_cats.hats` floor into
   the emitted Go module (build-harness step, analog of `runtime/xatsgo`), with
   the same `$`→`_` identifier mangling the emitter uses for extern names + a GO
   precats (`XATS2GO_the_print_store`, `import "strconv"`).
   - **Floor validated as real Go (2026-06-29):** the typed `gint000.cats`,
     `$`→`_`-mangled and assembled into a `package main` with the print store +
     `strconv`, passes `gofmt`/`go vet`/`go build` and RUNS correctly
     (`sint_add(3,4)=7`, `sint_mul(7,2)=14`, `sint_neg(14)=-14` → store
     `[14 -14]`). So the typed primitive floor is sound and linkable; the
     remaining work is the *emitter* using it (next).
3. **Route one non-native prelude function through the arm** — emit its template
   body (bottoming at an `XATS2GO_*` primitive) instead of the `xatsgo.Xats_*`
   shortcut; `#include prelude_GO_dats.hats` in that test.
4. **Prove** byte-equal through the oracle (`make run/<test>`), prelude now
   flowing through `CATS/GO`.
5. **Scale** — the remaining 13 modules (mechanical: copy the JS arm,
   `XATS2JS`→`XATS2GO`; translate the one-line `.cats` bodies to typed Go).

No `lib2xatsopt` rebuild on this path. The work is concentrated in the emitter
(`.cats` linking + template-body emission for the non-native prelude) — the
M3/M4 milestone — oracle-gated per construct.

## Are we ready to self‑host?

Not yet — but the remaining prelude work is the **small** floor above plus the
compile‑the‑prelude pivot, **not** a from‑scratch Go prelude. After that: the
Class‑C cross‑module frontend accessors (docs/00 §self‑hosting) and scaling up
the escalation ladder (large programs → a prelude module → the emitter's own
sources → the full compiler).
