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

## Higher-order prelude (`prints`/`g_print`) — partial; the typed-param frontier

The higher-order template path (variadic `prints`, the `g_print`/`map$fopr`
hooks) has two facets in go-arm mode:

1. **Value-like (nullary) instance application — ✅ FIXED.** A nullary template
   instance is emitted as a Go thunk `func() T {..}` bound to a temp; when that
   temp is applied WITH ARGS (a hook that returns a function), the call must be
   `tmp()(args)` (invoke the thunk, then apply), not `tmp(args)` (an arity
   mismatch). Implemented via a go-arm `nullary_inst` stamp set
   (`t1imp_nullaryq` at the `I1INStimp` dispatch) + an `I1INSdapp` rule that
   inserts `()` for a non-empty arg list. A 0-arg application stays `tmp()`. The
   JS-arm suite is byte-identical (the set is go-arm-only). The AVL test's hook
   applications now emit correctly (`goxtnm77()(goxtnm46)`).
2. **Typed-param boundary — THE FRONTIER (unsolved).** An instantiated template
   like `gs_print_a3(s, b, s)` has its params typed **generically `any`** (the
   param's static type is the template's type variable; `gotype_of_param_bnd`
   reads `d2var_get_styp` which is the generic param, not the monomorphic
   instance type). But the typed hooks inside want concrete types (the bool
   printer is `func(goxtnm62 bool)`, using `if goxtnm62`). So passing the `any`
   param to the typed hook fails: `cannot use goxtnm46 (any) as bool ... need
   type assertion`. This is the M3 "monomorphized param typing" work: either
   (a) type instantiated-template params from the concrete instance types
   (`t2jaglst` / the typed-IR param gotyp) instead of the generic `d2var_get_styp`,
   or (b) insert `arg.(T)` assertions at the typed-hook application (recover the
   hook's result-func param type at `nullary_inst` registration and assert).
   Until then, programs using variadic `prints` over heterogeneous args don't
   compile through go-arm (direct `sint_print`/`strn_print` do — rungs 1-5). This
   is the critical-path item for self-hosting (the compiler uses `prints`
   pervasively).

## Go-arm escalation ladder (programs proven through CATS/GO)

A repeatable runner `run-goarm.sh <test>` (canonical Makefile bundle + `--go-arm`
+ floor splice + golden) drives these. The JS-arm suite stays **75/75** at every
step (gate default-off).

- **Rung 1 — `test_goarm01`** (int print): `42`/`123`. ✅
- **Rung 2 — `test_goarm02_fact`** (recursion + if + native ops): `fact(5)=120`,
  `fact(10)=3628800`. ✅ — proves the emitter's fun/if/recursion machinery runs
  *together with* prelude-body emission.
- **Rung 3 — `test_goarm03_strn`** (strings: `strn_print`, `strn_length`):
  `hello, go!\n\n10\n`. ✅ — added `CATS/GO/strn000`; `console_log`(=`fmt.Println`)
  adds a newline exactly like JS `console.log` (so a `"...\n"` literal flushes
  `\n\n`, matching the JS backend).
  - *Known typing gap:* the string `.cats` prims take `any` (asserted to
    `string`), because an ATS `strn` param's static type is an existential the
    current param-recovery maps to `any` (unlike `sint`'s `gint_type` path). The
    floor is correct; tightening to typed `string` params is gated on the
    emitter's existential-chase / typed-temp param path. (`gotype_of_symname`
    now maps `strn`/`nint`, which helps direct `T2Pcst` cases.)

## ✅ VERTICAL SLICE PROVEN END-TO-END (2026-06-29)

`test_goarm01_xats2go.dats` (`#include prelude_GO_dats.hats`; `sint_print` +
`the_print_store_log`) compiled through the CATS/GO arm with the emitter in
`--go-arm` mode: the prelude template bodies are EMITTED (not shortcut),
bottoming at the typed `XATS2GO_*` floor — including the composed
`the_print_store_log → console_log(the_print_store_flush())`. The emitted Go +
the self-contained `gint000`+`xtop000` floor builds (`go build`) and runs:
**`42\n123\n`, byte-equal to golden.** The JS-arm suite stayed **75/75** (the
`go_arm` gate is default-off → byte-identical). The full pivot:
- `d2cstgo1`: an `XATS2GO_*` leaf emits the bare `$`→`_`-mangled name (the linked
  `.cats` primitive), not `xatsgo.Xats_*`.
- `go_arm_set`/`go_arm_getq` (go1emit_byref0): process-global flag, default off.
- `t1imp_func_literal_go1emit`: relax the `i1dcl_preludeq` shortcut **only** in
  go-arm mode → prelude bodies emit down to the `XATS2GO_*` leaves.
- driver (`--go-arm`) + `build-go.sh --go-arm` (splice the floor) + a golden.
- **Bug fixed:** void prims (`sint_print`/`console_log`) must return `any` (nil),
  matching the emitter's "every body result is bindable" contract (as
  `xatsgo.Xats_*` do).
- *Caveat:* the automated `build-go.sh --go-arm` path hits the pre-existing
  `build-go.sh` `lib2xats2cc` stamp-mismatch (`i0parsed_of_trxd3i0` undefined —
  the Makefile is the canonical builder); the proof used the correct Makefile
  bundle run with `--go-arm`, then the same floor-splice/assemble/build steps.

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
     `[14 -14]`). So the typed primitive floor is sound and linkable.
   - **Self-contained runtime (user choice) — built + validated:**
     `CATS/GO/xtop000.{dats,cats}` is the self-contained I/O floor (its OWN
     print/prout/prerr stores + `the_print_store_flush` + `console_log =
     fmt.Println`); it does NOT share `runtime/xatsgo`'s store. Assembled with
     `gint000` and the emitted-style composed body `the_print_store_log() =
     console_log(the_print_store_flush())`, an int-print program compiles
     (`gofmt`/`vet`/`build` clean) and RUNS correctly: `sint_print(42)` → `42`,
     `sint_print(sint_add(100,23))` → `123` (each flushed on its own line). The
     self-contained floor is proven sound.
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

---

## Progress log — go-arm rungs (2026-06-29)

The CATS/GO prelude pivot is now proven END-TO-END across an escalation ladder
of programs, each compiled `--go-arm` (prelude template bodies emitted down to
the typed `XATS2GO_*` leaves of the linked `.cats` floor) and verified
byte-equal to a golden. The JS oracle suite stays **75/75 byte-equal** at every
step (the go-arm gate + all go-arm-only side-tables are default-off, so the JS
arm is untouched).

| rung | program | exercises |
|------|---------|-----------|
| 1 | int arithmetic | native scalar ops, print store |
| 2 | factorial | recursion, TCO |
| 3 | strings | `strn_print` / `strn_length` |
| 4 | datatypes | boxed cons, tag dispatch |
| 5 | lists | recursive datatype + list ops |
| 6 | AVL (`isAVL`) | higher-order `prints`/`g_print` hooks |
| 7 | scalar floor | bool / char / float (`bool000`/`char000`/`gflt000`) |
| 8 | references | `a0rf` get/set/mutate (`axrf000`) |

### CATS/GO floor modules wired so far
`xtop000` (I/O store), `gint000` (sint), `bool000`, `char000` (rune),
`gflt000` (float64, JS-parity printing), `strn000` (string), `axrf000`
(reference). Remaining: `gbas000`, `gdbg000`, `strm000`, `strx000`,
`optn000`/`list000` (mostly pure-ATS, may need no `.cats`), `axsz000`,
`a1rf` arrays.

### Two general emitter capabilities built for the typed pivot

Both are the SAME shape — recover a concrete Go type at a typed boundary the
`any`-erased IR drops, and bridge it with a Go type assertion — gated on
go-arm so the JS arm is byte-identical.

1. **Typed-param hook boundary** (rung 6). A value-like (nullary) template
   instance returning a typed function (`g_print<bool>` → `func() func(bool)
   any`) applied to an `any`-typed generic param: emitted `tmp()(arg.(T))`,
   recovering `T` from the instance's result-lambda signature
   (`t1imp_hook_paramty` → `gotype_of_lam_ret` → `go_first_param`).

2. **any→concrete RESULT boundary** (rung 8). A template instance is emitted as
   a func literal whose return type is body-derived `gotype_of_lam_ret` — for a
   forwarder over an `any`-returning leaf (`a0rf_get`) that is `"any"`, while the
   instance temp's recorded gotyp carries the CONCRETE type. We record
   (instance-temp stamp → emitted return type) at the `I1INStimp` emission
   (`inst_retty_add`, go1emit_byref0); at the application, if the callee's
   recorded emitted-return is `"any"` and the result temp has a concrete gotyp,
   the call is asserted `tmp(args).(T)`.

### Reference design note (`axrf000`)

The JS arm provides only the linear leaves `a0rf_lget`/`a0rf_lset` and lets
`a0rf_get`/`a0rf_set` be base pure-ATS impls built on an `(owed(a) | a)` PROOF
tuple. Emitting THOSE bodies through go-arm hits an un-erased proof-tuple
(`I1Vnone` proof token → `UNHANDLED i1val`; `struct{F1}` vs `.F0` layout
mismatch) — linear-proof erasure the Go value-emit surface does not yet model.
The GO arm sidesteps this by ALSO overriding `a0rf_get`/`a0rf_set` directly to
typed Go primitives (ATS3 accepts the arm `#impltmp` override of the base): a
reference is a length-1 `[]any` whose shared backing array gives the mutation
semantics. **Open item for full self-hosting:** proper linear/proof-tuple
erasure in the go-emitter, if any compiler code uses the `owed`-proof leaves
directly rather than `a0rf_get`/`set`.

### Path forward to self-hosting

The ladder from here: finish the small primitive floor (above) → compile a real
prelude module end-to-end → the emitter's own sources → the full compiler. Each
new module/feature tends to surface one more `any`↔concrete boundary; the two
capabilities above are the reusable tools for them. The frontend (lib2xatsopt)
is still JS-hosted; a fully self-hosted Go binary additionally needs the
frontend through go-arm (the large remaining piece).

---

## Rung 9 (in progress) — container structural printing → the `$eval`/p2tr + boxing frontier

Target: `prints(..., someOptn, ...)` (the prelude's `g_print<optn>`), which is
EXACTLY how the emitter's own IR printers work (`intrep1_print0.dats`:
`prints("I1CMPcons(", ilts, ...)` over a LIST) — so this is squarely on the
self-hosting critical path for the emitter's own sources.

Structural container printing pulls in `gseq` (generic-sequence iteration),
whose hot loop uses a STACK COUNTER via an address + unsafe pointer:
`var i0: ni = 0 ; val p0 = $addr(i0) ; $UN.p2tr_get(p0) ; $UN.p2tr_set(p0, …)`.

### Fixed this pass (the `$eval`/p2tr IR-lowering gaps — committed)
xats2cc is an incomplete backend, so `$eval(p)` = `D3Edp2tr` had no lowering:
  1. **trxd3i0** (`xats2cc` d3→i0): added `f0_dp2tr` (`D3Edp2tr` → `I0Edp2tr`),
     mirroring `f0_addr`. Without it `$eval` fell to `I0Enone1`.
  2. **tryd3i0** (the i0 normalization pass): added an `I0Edp2tr` PASS-THROUGH
     (`f0_dp2tr`); its `_(*otherwise*)` arm was clobbering `I0Edp2tr` into
     `I0Enone2` (same class of bug as the earlier try/raise migration).
  3. **trxi0i1** (i0→i1): added the VALUE-position `I0Edp2tr` case
     (`f0_dp2tr_v` → `i1val_dp2tr` → `I1INSdp2tr`); only the lvalue path existed.
  4. **emitter**: `I1INSdp2tr` now emits Go `*p` (deref); it previously emitted
     `&` (address-of) as untested dead code. Deref-ASSIGN `$eval(p):=x` → `*p=x`
     via a dp2tr-pointer side-table (`dp2tr_ptr_add/has`, populated at lowering,
     read by the assignment emitter — same cross-phase idiom as the tytab).
  5. `p2tr(a)` now maps to Go `*a` in the gotyp engine (`gotyp_of_styp`).

These erase the `UNHANDLED i1val` / `I1Vaexp` markers — `$eval` lowers and
emits a real Go deref. Verified: rungs 1-8 byte-equal, JS suite 75/75 (all gated
/ only fire for `$eval`, unused elsewhere).

### The remaining barrier — addressable-var BOXING (generic pointer compat)
`gseq` instantiates `p2tr_get<ni>`/`p2tr_set<ni>`, but the typed pipeline ERASES
the template's pointer param to `any` (exactly as it does `a0rf`'s param). For
`a0rf` that was fine — its handle is a `[]any` BOX, which is `any`-compatible.
But `$addr(i0)` produces a REAL Go pointer `*int`, and:
  - Go has no pointer covariance: a `*int` is NOT assignable to an `any`/`*any`
    param, and you cannot `*` an `any`.

So real Go pointers cannot flow through an `any`-erased generic instance. The
fix is to BOX address-taken locals exactly like `a0rf`:
  - escape-analysis pre-pass: collect vars `v` with `$addr(v)` taken;
  - emit such a `var v` as `goxtnmV := []any{init}`; reads → `goxtnmV[0].(T)`,
    writes → `goxtnmV[0] = x`; `$addr(v)` → `goxtnmV` (the box);
  - `$eval(box)` → `box[0]` (so `I1INSdp2tr` emits `box[0]` for a boxed pointer,
    keeping `*p` only for a genuine monomorphic/by-ref pointer);
  - override `$UN.p2tr_get`/`p2tr_set` in a GO arm to `[]any` box ops (literally
    the `a0rf` bodies).

This is a multi-site feature (var decl/read/write + escape analysis) touching the
hot var path, so it is the next focused effort. Once it lands, container
structural printing — and therefore the emitter's own `prints`-based IR dumps —
compiles through go-arm, clearing the path to compiling the emitter's sources.

---

## Rung 9 update — p2tr by REFLECTION dissolves the boxing frontier

The "addressable-var boxing" barrier (previous section) turned out to be
AVOIDABLE. Boxing was only needed because a real Go `*int` cannot flow through
an `any`-erased generic `p2tr_get<a>`/`p2tr_set<a>` instance (no pointer
covariance). But the pointer CAN be carried as `any` and dereferenced by
REFLECTION — so the `a0rf`-style arm override applies after all:

**`CATS/GO/unsfx00` arm** overrides the two unsafe leaves `$UN.p2tr_get` /
`$UN.p2tr_set` (the base impls are `$eval(p)` / `$eval(p):=x`) to typed Go
primitives:
```
func XATS2GO_p2tr_get(p0 any) any { return reflect.ValueOf(p0).Elem().Interface() }
func XATS2GO_p2tr_set(p0 any, x0 any) any { reflect.ValueOf(p0).Elem().Set(reflect.ValueOf(x0)); return nil }
```
`$addr(v)` stays a real Go `&v`; it flows into the generic instance as `any`
holding a `*int`, and `reflect.ValueOf(p).Elem()` reads/writes the pointed-to
cell generically. The higher p2tr ops (`p2tr_ret`, `p2tr_set_list_*`) are pure
ATS on top of these two leaves, so they ride the override for free. (`p2tr` is
mapped back to `any`, NOT `*a`, so the `any` reflection signature is consistent;
the earlier `$eval`/`*p` IR-lowering remains correct foundation for any genuine
MONOMORPHIC `$eval`, but the gseq generic counter now never reaches it.)

Result: the gseq stack-counter loop compiles and runs — **no var-boxing pass
needed**. Verified rungs 1-8 byte-equal + JS suite 75/75 (the override + p2tr-as-
any only affect p2tr-using programs).

### The NEXT frontier — `g_print` generic-dispatch variance
With p2tr cleared, `prints(..., optn, ...)` gets MUCH further but still hits the
generic-print dispatch's TYPE-VARIANCE boundaries (Go function types and pointer
types are INVARIANT):
  1. a typed print hook `func(int) any` returned through a generic slot expecting
     `func(any) any` — Go rejects it (func invariance);
  2. an `any`-typed datatype value passed to a worker whose param is the concrete
     `*xatsgo.XatsCon` — needs a call-arg assertion (the general form of the
     rung-6 hook-arg assertion; the callee's param type is on its recorded gotyp,
     not recoverable via `gotype_of_ival`'s temp→`any` fallback).

Both are the same underlying tension as the pointer case: the emitter is
TYPED-with-boundary-assertions, but `g_print`'s generic dispatch wants uniform
`any` interfaces. The clean resolution is to emit instance/hook funcs with `any`
params (assert INSIDE: `func(x any) any { ... x.(T) ... }`) so every hook is
uniformly `func(any) any` — the JS-erasure shape — instead of typed params +
adapters. This is a focused change to the func-literal emitter (param typing +
internal assertion) and is the next step; it directly enables the emitter's own
`prints(..., list, ...)` IR dumps.

### Rung 9 CROSSED — `prints(..., optn, ...)` compiles AND runs byte-equal
The g_print generic-dispatch chain now compiles end-to-end (rung 9:
`val ns = optn_cons(10); prints("ns = ", ns, "\n"); length; head`). The earlier
func-variance / nested-thunk / arg-boundary pieces (committed in 3219fe8) made it
BUILD; the last defect was a RETURN-MODE bug that dropped the `)` suffix:

  - The gseq `g_print` lowers to a `beg; iterate; end` sequence of **val-decls**
    in a let-block. The `iterate` val-decl's computation is a fully-returning
    if/case (`i1ins_fully_returnsq` = true — both branches end in `I1INSrturn`).
    The block-form emitter therefore emitted it in **return mode** (`return
    goxtnm`), which EXITS the enclosing print function — so the trailing `end`
    val-decl (the `)` print) became dead code. Output: `optn(10` (no close paren).

  - Root cause: a fully-returning if/case is emitted in return mode whenever
    `i1ins_fully_returnsq` holds, but that is only correct in genuine
    FUNCTION-TAIL position. A val-decl's computation is NEVER the function tail
    (the let-body's result is what returns), yet `i1valdcl_go1emit` →
    `i1cmp_go1emit` drove the trailing if straight to return mode.

  - Fix — a process-global `block_force_value` gate (go1emit_byref0), set TRUE
    around any computation that is NOT in tail position, read by the block-form
    emitters to force VALUE mode (assign the result temp) instead of return mode:
      * `i1valdcl_go1emit`  — every val-decl computation is non-tail → force.
      * `i1letlst_go1emit_p` — a NON-LAST let is non-tail → force.
      * `i1cmp_go1emit_ret`  — a function/branch BODY is a fresh tail context →
        RESET to false (so a force from an enclosing sequence does not suppress a
        nested lambda's own tail return).
      * `i1ins_go1emit_block` (if/case/let-in): `retq = if force then false else
        i1ins_fully_returnsq`.
      * `i1cmp_go1emit` / `i1cmp_go1emit_tnm`: when forced, the trailing block
        assigned its temp (did NOT return), so the discard / bridge-assignment
        (`_ = ival` / `itnm = ival`) MUST fire (else the temp is "declared and
        not used"). This bridges the nested value-mode temps (let-in temp ←
        inner-if temp).
    All set-TRUE sites are **gated on `go_arm_getq()`**: this non-tail
    fully-returning-block pattern only arises in the go-arm gseq lowering, so the
    byte-frozen JS suite (75/75) and rungs 1‑8 are provably untouched (the gate
    is never taken off-arm; verified byte-equal).

Result: rung 9 emits `ns = optn(10)\n|ns| = 1\nhead(ns) = 10\n\n` — byte-equal to
the prelude's documented gseq format (`gseq$beg="optn("`, `$sep=","`, `$end=")"`).
The container-structural-print chain (`g_print` over a datatype via the gseq
counter) is now fully self-hosting-ready — the shape the emitter's own
`prints(..., list, ...)` IR dumps need.

### Rungs 10–11 + the SELF-HOSTING FRONTIER MAP
Two more prelude rungs landed (test + golden, byte-equal to the JS twin):
  - **rung 10** `prints(..., <list>, ...)` → `ns = list(1,2,3)` — the multi-element
    gseq `sep=","` path (no emitter change; the rung-9 return-mode fix generalizes
    to multi-element containers, the shape the emitter's own IR dumps use).
  - **rung 11** `strn_foritm` with a `foritm$work` template → `8 0 3` — needed the
    UNSAFE raw indexer `$UN.strn_get$at$raw` (the leaf `strn_foritm` iterates with,
    bypassing the bounds-checked `strn_get$at`) rebound in the GO unsfx00 arm to
    the existing `XATS2GO_strn_get_at_raw` leaf.

With the prelude floor broad enough to print containers and iterate strings, the
question becomes: **how close is the EMITTER ITSELF to self-hosting?**  The new
`srcgen2/TEST/selfhost-frontier-audit.sh` runs the go-emitter on each of its own
18 `srcgen2/DATS` source modules and classifies the output:

```
16/18 modules self-hosting-clean   (REAL_UNH = 0 AND INT_ROUTE = 0)
   0  genuine /* UNHANDLED: */ markers across ALL 18 modules
 660  package-level Go funcs emitted in total
   3  frontend-accessor routing sites remain (the whole remaining frontier)
```

(The word "UNHANDLED" appears 13× in `go1emit_dynexp`'s output, but every one is
a STRING LITERAL — the emitter faithfully reproducing its OWN fallback-marker
strings; the audit's `REAL_UNH` regex excludes string-quoted occurrences, so the
true count is 0.)

The entire remaining frontier is **3 frontend-node-accessor calls** that the
emitter routes through the `xatsgo` runtime instead of emitting natively:
  - `intrep1_utils0.dats:108`  `d2cst_castq(d2c)`     (in `i1val_cfnq` — is this
     dynamic constant a CAST function?)  → `xatsgo.Xats_d2cst_castq`
  - `trxi0i1_myenv0.dats:89`   `d2var_get_unam(d2v)`  (a d2var's unique name)
     → `xatsgo.Xats_d2var_get_unam`  (2 emitted call sites)

These are NOT prelude/emitter gaps — they are inherent **frontend coupling**: the
emitter reads `d2cst`/`d2var` nodes produced by the shared frontend
(lib2xatsopt) and queries them with frontend predicates/accessors.  Crossing this
last boundary is a DISTINCT, larger phase: it needs the frontend's `d2cst`/`d2var`
node types + accessors available in Go (either compiled from the frontend SATS, or
provided as a runtime representation of the deserialized frontend IR).  It cannot
be eliminated at the emitter-source level (the predicate/accessor semantics live in
the frontend).

**Milestone:** the CATS/GO prelude pivot + the emitter's own dynexp/decl/styp
lowering now emit clean, UNHANDLED-free Go for the WHOLE emitter; emitter
self-hosting is gated only on the frontend-node-accessor boundary (3 sites).  Run
`bash srcgen2/TEST/selfhost-frontier-audit.sh` to reproduce the map.

### The full-build distance (runtime ABI breakdown)
The frontier has TWO layers.  The `selfhost-strict` GATE forbids 3 specific
*compiler-internal* routings (above).  A full functional BUILD of the Go emitter
needs more: the emitted Go references **129 distinct `xatsgo.Xats_*` symbols**, of
which the runtime currently defines **16** — leaving **123** to supply.  Broken
down:
  - **~52 frontend-IR node accessors** (`i0exp_node_get`, `i0dcl_lctn_get`,
    `d2con_get_ctag`, `d2cst_castq`, `d2var_get_unam`, `t1imp_*`, `token_*` …) —
    the shared frontend's node ABI; needs the frontend's node types in Go.
  - **~48 prelude prims** (`gint_add_sint_sint`, `bool_neg`, `char_eq`, `g_print`,
    `gs_print_n*`, `a0ref_*`, `list_*`, `optn_*`, `strn_*`, `symbl`) — these are
    exactly the family the **CATS/GO floor already implements as `XATS2GO_*`**.
    The gap is a NAMING/routing convention: the non-go-arm emission routes them to
    `xatsgo.Xats_<name>`, whereas go-arm emission routes them to the typed
    `XATS2GO_*` floor.  So emitting the EMITTER ITSELF in go-arm mode would
    discharge this whole bucket against the floor already built in this work,
    leaving only the frontend-node ABI + symbol tables.
  - **~23 symbol-table / misc** (`stkmap_*`, `topmap_*`, `the_d2cstmap_xnmfind`,
    `t0imp_*`, `x2t2p_get_styp`, `trcdknd_fltq`, `label_fprint`).

So two routes to a buildable Go emitter:
  1. **go-arm self-emission** — emit the emitter sources with the CATS/GO prelude
     arm so prelude prims hit the `XATS2GO_*` floor (≈48 discharged for free);
     supply the ~75 frontend-node + symbol-table funcs as a Go runtime/ABI.
  2. **non-go-arm** — supply all 123 as `xatsgo` runtime funcs.

Route 1 reuses the floor this work has been building, and is the natural
continuation; both still require the frontend node ABI in Go, which is the genuine
remaining bulk of emitter self-hosting.

#### Empirical note: `--go-arm` alone does NOT reroute emitter prelude prims
Emitting `intrep1_utils0.dats` with `--go-arm` yields the SAME 101
`xatsgo.Xats_*` references as without it (and the `d2cst_castq` routing is
unchanged).  Reason: the go-arm floor templates (`XATS2GO_*`) reach a program
only when it manifests `prelude_GO_dats.hats`; the emitter sources stalload the
COMPILER prelude (`xatsopt_sats.hats`/`xatsopt_dpre.hats`), a different regime, so
the `--go-arm` flag has nothing to rebind.  Route 1 (go-arm self-emission) thus
requires the CATS/GO floor to be MANIFESTED INTO the emitter's compiler-prelude
staloading — a real integration step, not a flag flip.  Recorded as a negative
result so the next phase does not assume the flag suffices.
