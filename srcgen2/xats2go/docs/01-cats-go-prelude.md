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

### Route 1 reality check — the floor does NOT serve the emitter's own prims
Investigating go-arm self-emission surfaced three facts that invalidate the
"≈48 prims discharged for free by the floor" premise:

1. **Separate prelude namespaces.**  The emitter sources stalload the COMPILER
   prelude (`srcgen1/prelude/SATS`, e.g. `bool_neg of 1001`); the `XATS2GO_*`
   floor this work built rebinds the USER prelude (`prelude/SATS`, `bool_neg of
   1000`).  The GO arm `#impltmp`s target user-prelude templates, so they never
   apply to the emitter's compiler-prelude templates.

2. **Name + coverage mismatch.**  The emitter references `Xats_gint_add_sint_sint`,
   `Xats_bool_neg`, `Xats_gint_mod_sint_sint`, … ; the floor `.cats` exposes
   `XATS2GO_sint_add_sint`, `XATS2GO_bool_eq`, … — different names, and the floor
   has NO `bool_neg` / no `gint` arithmetic at all (only comparisons).  The floor
   is a USER-prelude vertical slice, not a compiler-prelude floor.

3. **Wrong emission path.**  The emitter uses these prims mostly as FIRST-CLASS
   VALUES — `goxtnm196 := xatsgo.Xats_bool_neg` (a hook passed to a higher-order
   prim) — emitted by `d2cstgo1`, which routes a d2cst NAME to `xatsgo.Xats_*`.
   The go-arm body-emission (`t1imp_func_literal_go1emit`) only fires for
   `I1INStimp` APPLICATIONS, so even a compiler-prelude GO arm + `--go-arm` would
   not reroute a value reference.  (Verified: emitting `intrep1_utils0.dats` with
   `--go-arm` is byte-identical to without — `bool_neg` stays `xatsgo.Xats_bool_neg`.)

CONSEQUENCE.  A buildable Go emitter needs the compiler-prelude prim leaves as
real Go functions that `d2cstgo1`'s target (`xatsgo.Xats_<name>`) resolves to —
i.e. **xatsgo runtime leaves** (`Xats_bool_neg = !b`, `Xats_gint_add_sint_sint =
a+b`, …), most of them one-liners.  This is the SAME `xatsgo.Xats_*` ABI the
"full-build distance" section counted (129 referenced, 16 defined).  Building a
SECOND `XATS2GO_*` floor for the compiler prelude + teaching `d2cstgo1` a
name-map would be strictly more work for the same result.  So the prim half of
self-hosting is a **runtime-leaf** job, not a floor job; the go-arm floor remains
the right model for USER programs targeting Go, which is what it was built for.

The frontend-node ABI (~52 accessors + ~23 symbol-table funcs) is the dominant
remaining work under EITHER route, and is unchanged by this finding.

### Prim-leaf runtime (Route 1, prim half) — 12 leaves implemented
With the floor ruled out for the emitter's own prims, the prim half of
self-hosting is a runtime-leaf job (the `xatsgo.Xats_*` ABI `d2cstgo1` already
targets).  A corrected audit (the first pass under-counted: it matched only
`func Xats_*`, missing the runtime's many `var Xats_* = func(...)` defs) showed
the runtime already defines 98 of the referenced symbols; only **18 prelude
prims were truly missing**.  Implemented **12** of them in
`runtime/xatsgo/xatsgo.go`, ported from the ATS prelude source against the
runtime's value model (list = `*XatsCon`, char = `int32`, symbl = interned name
string):
  `bool_neg`, `symbl_cmp`, `TRUE_symbl`, `DLR_EXTNAM_symbl`, `g_print`,
  `gs_print1_n2/n3/n5`, `list_sing`, `list_consq`, `list_append`,
  `strn_make_list`.
Signatures were pinned from the emitted call sites (e.g. `symbl_cmp(_, TRUE_symbl)
== 0`, `list_consq(xs)` consumed as a Go `bool`).  The runtime package compiles
+ vets clean; rungs 1‑11 stay byte-equal and the JS suite is 75/75 (the new
defs are additive — nothing referenced them before).

The **6 left** are NOT simple leaves:
  - `list_exists`, `list_sortedq`, `list_map_e1nv`, `optn_map_e1nv`,
    `list_mergesort` carry a per-call TEMPLATE METHOD (`$pred`/`$fopr`/`$cmp`)
    that the runtime routing DROPS — they must be emitted INLINE by the
    backend, not implemented as runtime leaves (an emitter-inlining gap, not a
    runtime gap).
  - `strn_fprint` needs the FILR output model, deferred with the frontend ABI.

VERIFICATION CAVEAT: prim leaves are exercised only when the WHOLE Go emitter is
built+run (which still needs the frontend-node ABI), so they are compile-checked
+ semantics-ported, not yet end-to-end runtime-validated.  The runtime-`Xats_*`
ABI for the PRELUDE half of self-hosting is now down to those 6; the frontend-node
ABI remains the dominant block.

### Rung 12 + template-method prim inlining (Task #8 progress)
Probed whether go-arm body-emission can inline a TEMPLATE-METHOD prelude prim
(the `exists`/`sortedq`/`map_e1nv`/`mergesort` family the emitter's own sources
use, whose `$pred`/`$fopr`/`$cmp` method the runtime routing drops).  Rung 12
(`list_exists(xs)` with an inline `exists$test<sint>(x) = x >= 10`) showed go-arm
DOES inline the body WITH its predicate — so these are NOT runtime leaves, they
inline correctly.  The only obstacle was an arg-boundary type error: the inlined
predicate is `func(int) bool`, but the list head `x` (an `I1Vp1cn` datacon-field
projection on a `list(sint)`) is emitted as a bare `.Args[0]` (`any`, the erased
element type `a`), so `pred(.Args[0])` failed Go's type check.

Fix: extend the go-arm generic-call arg-assertion to handle an `I1Vp1cn`
projection arg — when the callee's first param is CONCRETE and the projection's
own recovered field type is "any" (a polymorphic field, emitted bare), assert
`<proj>.(T)`.  Guarded by the existing concrete-`pty` gate (empty off-arm) and by
the projection's field type being "any" (else it already self-asserts; a double
assert is invalid Go).

Result: rung 12 → `true false`, byte-equal.  Rungs 1‑11 byte-equal; JS suite
75/75.  This is the user-program proof that the 5 template-method prims inline
correctly under go-arm; the emitter's OWN sources route them to runtime only
because selfhost-smoke emits WITHOUT `--go-arm` (the prelude-shortcut path).  So
Task #8's real fix is to emit the emitter sources WITH go-arm body-emission (the
same compiler-prelude-arm integration the Route-1 analysis describes), at which
point these inline with their methods — no runtime leaves needed.

#### But the emitter's OWN template-method prims still route to runtime
Re-emitting `intrep1_utils0.dats` (which has the SAME `list_exists(icls) where {
exists$test ... }` shape as rung 12) WITH `--go-arm` still yields
`goxtnm92 := xatsgo.Xats_list_exists` — it does NOT inline, unlike the user
program.  The only difference is the prelude NAMESPACE: rung 12 uses the USER
prelude (whose `list_exists` template instance carries a resolved body the go-arm
`t1imp_func_literal_go1emit` path emits), while the emitter uses the COMPILER
prelude, whose instance reaches the emitter as a d2cst VALUE reference with no
attached body (`t1imp_i1dclq` is empty) — so go-arm has nothing to inline and it
falls through to `d2cstgo1` → `xatsgo.Xats_*`.

So Task #8 (inline the emitter's template-method prims) CONVERGES with the Route-1
compiler-prelude integration: both need the compiler-prelude templates to resolve
their bodies under go-arm (the `_XATS2GO_` compiler-prelude arm).  Until then the
emitter's own `exists`/`sortedq`/`map_e1nv`/`mergesort` route to runtime, where
they cannot be correct leaves (the `$pred`/`$fopr`/`$cmp` method is lost).  The
rung-12 arg-boundary fix is still a real, byte-equal-verified win for ANY go-arm
program using a template-method prim over a polymorphic container.

### Frontend-node ABI RESOLVED — emit it, don't hand-write it
The frontend-node ABI looked like a hand-written ~52-accessor wall.  Inspecting
the frontend reveals it is not:
  - `d2con = d2con_tbox`, and `d2con_tbox` is `#absimpl`'d to a `D2CON` datatype
    with 8 POSITIONAL fields `(loc, sym, ctag, tqas, s2e, stmp, t2p, xt2p)`.
  - `d2con_get_ctag(c)` is just `let val+ D2CON(...,ctag,...) = c in ctag end` —
    the 3rd field.
Compiling the frontend module `dynexp2.dats` through the go-emitter confirms it:
**162 funcs, 0 real UNHANDLED markers**, and the accessor emits as a clean field
read:
```
func d2con_get_ctag_8344(c any) int { return xatsgo.Xats_as_con(c).Args[2].(int) }
```
So the frontend-node accessors are NOT a separate ABI to author — they EMIT
automatically (as `*XatsCon` field reads) when the frontend datatypes are
compiled to Go, exactly like the emitter's own datatypes.  (Standalone emission
of `dynexp2.dats` also prints some `F3PERR0` type-check errors — `castlin10`
linear casts, `$extnam` leaves — that come from emitting the module in ISOLATION
without its full xatsopt staload context; in the real `lib2xats2cc` build they
resolve.  They are an emit-in-isolation artifact, not an UNHANDLED gap.)

CONCLUSION — the path to full self-hosting needs NO frontend-ABI design decision:
compile the WHOLE pipeline (frontend `lib2xatsopt` + the 18 emitter modules) to
Go, link, run.  The accessors + symbol tables come for free from emitting the
frontend DATS.  The remaining work is therefore SCALE (emit + assemble every
pipeline module, supply the handful of irreducible runtime leaves like the 12
already added + the FILR model + the linear-cast `castlin10` primitive), not a
new architecture.  The go-emitter already emits every module tried so far
UNHANDLED-free, which is the core capability self-hosting rests on.

### First multi-module build — assembly works; surfaces the first real codegen bug
`selfhost-build/assemble.sh` emits all 18 emitter modules and concatenates them
into ONE Go package (493 funcs, ~20.7k lines).  The ASSEMBLY mechanism is sound:
  - cross-module calls link by identical stamp-mangled names (`byref_add_2781`
    in the def and every caller),
  - ZERO duplicate function definitions across the 18 modules,
so they concatenate without redefinition or linkage errors.

`go build` then surfaced the FIRST genuine self-hosting CODEGEN bug — and it is in
the emitter's OWN output, not the assembly.  Even a SINGLE module (`go1emit_byref0.go`)
fails to compile standalone:
```
undefined: goxtnm16        // = the_go_byref_ref, a module-private a0ref global
```
ROOT CAUSE: the side-table pattern the emitter leans on everywhere —
```
local val the_go_byref_ref = a0ref_make_1val<...>(list_nil()) in <funcs> end
```
is an `I1Dlocal0(head, body)` node.  PASS 1 hoists the body FUNCTIONS to package
level (so `byref_add` etc. are emitted), but `i1dcl_go1emit`'s PASS-2 walk has NO
`I1Dlocal0` case, so the whole block falls to `f0_otherwise` → `// (skipped non-
val dcl)`.  The HEAD val (`the_go_byref_ref`) is therefore NEVER emitted, while
the package-level functions reference its temp (`goxtnm16`) — undefined.

WHY IT NEVER SHOWED BEFORE: the `_oracle`/`suite` tests compile+run EMITTED Go
for simple TEST programs that have no module-level `local val` globals referenced
by package-level functions; and selfhost-smoke only EMITS modules, never compiles
them.  The multi-module build is the first time the emitter's own
side-table-heavy code is actually `go build`'d — exactly what self-hosting is for.

THE FIX (next): emit module-level globals as PACKAGE-LEVEL Go vars.  A top-level
`val`/`local`-head `val x = init` must become `var goxtnm<x> <T>` at package scope
plus its initialization (single-expression inits inline as `var x = <init>`;
multi-statement inits go in a per-module `func init()`), instead of a main-local
(or skipped).  PASS 2's `i1dcl_go1emit` needs an `I1Dlocal0` case (recurse head +
body) and a package-level-val emission mode.  This is the load-bearing feature for
the side-table modules (byref0/tytab0) and the frontend's stamp/symbol-table
globals.

### Package-globals fixed → byref0 now reaches the type-boundary tail
With PASS-1.5 emitting module-level globals (`var goxtnm16 any` + `func init()`),
`go1emit_byref0.go`'s `undefined: goxtnm16` is gone.  Compiling it now surfaces
the NEXT layer — all the same "an `any` value used at a CONCRETE boundary needs a
`.(T)` assertion" class, but in the emitter's NON-go-arm self-emission (which has
far more such boundaries than the simple oracle test programs ever did):
  - `Xats_stamp_cmp` — missing runtime leaf (added: a stamp is an abstract id over
    `uint`; compare → sint, tolerant of the concrete Go int width).
  - `Xats_as_con(x).Args[0].F0` — a TUPLE projection off a datacon-field
    projection: `Args[0]` is `any` (erased field), so `.F0` needs
    `Args[0].(<struct>).F0`.
  - `goxtnm48 (any) as bool in return` — an `a0ref_get`/forwarded result returned
    where a concrete `bool` is expected.
  - `nient_memq(any, ...)` wanting `*xatsgo.XatsCon`; `... = any` wanting `string`
    — `a0ref_get` returns `any`; the read of a side-table's contents must assert
    to the recorded element type.

These are localized codegen fixes (assert at each boundary — the same shape as the
rung-12 `I1Vp1cn` arg-assertion and the M2.7 datacon-field assertions, extended to
tuple-projection roots and `a0ref_get` results), each with regression risk against
the 12 byte-equal rungs + 75 JS-suite, so they want careful per-class verification.
The KEY structural blocker (package globals) is solved; the rest of self-hosting is
this type-boundary tail across the 18 emitter + frontend modules plus a handful of
runtime leaves.

### The type-coercion pass — byref0 from 11 to 3 build errors
The "any value at a concrete boundary" tail is being closed by a systematic
coercion pass (each step keyed on the EMITTED type so a concretely-emitted value
is never mis-asserted; all regression-clean against 12 rungs + 75 JS-suite):

1. **Result boundary of any-returning accessors** (`a0ref_get`/`p2tr_get`).
   Materialized as a value, they record emitted return type "any"
   (`t1imp_anyret_accessorq` → `inst_retty`), so the existing result-boundary
   assertion fires: `goxtnm := tmp(args).(T)`.  Fixes every `return a0ref_get(..)
   as bool` and `nient_memq(a0ref_get(..))` wanting `*XatsCon`.

2. **Erased-tuple field projection.**  A flat-tuple field read off an erased
   `any` root (a tuple stored as a `list`/datacon field) cannot emit `root.F<i>`;
   `tup_proj_go1emit` emits `xatsgo.Xats_tup_get(root, i)` (reflection).  Fixes
   `Args[0].F0/F1 undefined`.

3. **Assign boundary.**  Each if/case/let-in result var records its DECLARED Go
   type in `goemit_ty`; the value-mode branch-result assignment asserts
   `<ival>.(T)` when [itnm] is concrete and the assigned value is recorded "any".
   Fixes `goxtnm80 = goxtnm79.(string)`.

REMAINING (byref0's last 3): the **return boundary** — `return <r>` where the
function returns a concrete type but `r` is a LOCAL helper's `any` result (a
d2cst-less `fun` like `nient_find` defaults its Go signature to `func(..) any`).
The clean fix is to RECORD each function's emitted return type (keyed by its
d2var stamp) and assert at the CALL binding (`goxtnm := nient_find(..).(string)`,
making the result concrete) -- the same shape as step 1 but for a local-function
(I1Vfenv) callee.  That needs a small cross-module return-type table (a SATS
addition + the d2var-stamp accessor + extending the result-boundary's callee
case), which is the next focused step.

The first 3 steps are GENERAL (they help every module, not just byref0); byref0
is the proving ground because its side-tables exercise the a0ref/tuple/assoc-list
patterns densely.

### Milestone: byref0 is the first emitter module to COMPILE as Go
The type-coercion pass closed `go1emit_byref0.go` to a clean `go build` -- the
first of the 18 emitter modules to compile end-to-end.  Four GENERAL coercion
steps got there (each keyed on the EMITTED type, each regression-clean: 12 rungs
+ JS suite 75/75):
  1. result boundary of any-returning accessors (`a0ref_get`/`p2tr_get`),
  2. erased-tuple field projection via reflection (`Xats_tup_get`),
  3. assign boundary (emitted-`any` value into a concrete result var),
  4. return boundary (`funretty` per-function emitted retty + a `cur_funretty`
     global -> `return <r>.(T)`).

GENERALITY (the whole-pipeline assembly, all 18 modules in one Go package):
  - `has no field` (the erased-tuple class) -> **0** (cleared everywhere by
    step 2),
  - the build's remaining shape: ~419 undefined (the FRONTEND boundary --
    `stkmap`/`topmap` symbol tables + node accessors), ~156 codegen-tail errors
    (type assertions + cannot-use) in the heavier modules (intrep1/trxi0i1/
    styp0/dynexp), which the next coercion-pass iterations target.

### The emit-in-ISOLATION limitation (next build-pipeline step)
Extending past byref0 hits a structural wall: a module that uses a FRONTEND type
emits with `F3PERR0` type-check errors when emitted STANDALONE (`node bundle
module.dats`).  E.g. `tytab0` is byref0's twin but its side-table holds
`list(@(stamp, i0typ))`; `i0typ` (a frontend tbox) does not fully resolve in
isolation, so `a0ref_make_1val<list(@(stamp,i0typ))>` fails to type and the module
emits only partially.  byref0 compiled BECAUSE it uses only `stamp`/`strn`/`list`
(which resolve standalone).  So the `selfhost-build/assemble.sh` harness
(standalone `node bundle module.dats` per module) is sufficient ONLY for
frontend-type-free modules; the rest need emission WITH the full xatsopt staload
context (the Makefile's `$(JSDIR)/%_dats_out0.js` transpile path provides exactly
this for the JS build).  Wiring a full-context Go-emit path is the next
build-pipeline step before the coercion pass can be driven across the remaining
modules.

### Correction: the "emit-in-isolation" wall was a concurrency artifact
The earlier `tytab0` "emits empty / F3PERR0" observation was a FALSE alarm -- it
happened while the 18-module assembly job was hammering the emitter concurrently.
Re-run alone, `tytab0` emits fully (93 lines) and **compiles cleanly** -- the
SECOND fully-compiling emitter module.  (F3PERR0 lines on stderr are benign here:
byref0 emits 191 of them yet builds fine; the emitter recovers and the Go between
the sentinels is complete.)  So both self-contained side-table modules
(byref0, tytab0) now build as Go from the general coercion fixes; no full-context
emission is needed for them.  The remaining work is the codegen tail in the
cross-referencing heavy modules (measured in the whole-assembly build) plus the
frontend boundary.

### Coercion-pass results + the comprehensive-tracking conclusion
Six GENERAL coercion boundaries now land (a0ref-result, erased-tuple, assign,
return, arg, param-emitted-type), each regression-clean (12 rungs + 75 suite).
They got the two SELF-CONTAINED side-table modules (byref0, tytab0) to compile
cleanly as Go and cleared whole error CLASSES across the assembly (`has no
field` -> 0).  But on the whole-assembly codegen tail the per-source recording
shows DIMINISHING RETURNS:
  - whole-assembly codegen errors: 103 -> 96 (arg boundary) -> 95 (param
    recording).
The reason: the two self-contained modules have a SMALL, enumerable set of `any`
sources (their own a0ref/tuple/assoc-list), all now tracked.  The HEAVY modules
(intrep1/trxi0i1/styp0/dynexp) have PERVASIVE `any` flows -- let-bindings of
any-typed sub-results, nested call results, datacon payloads -- arriving from many
sites, so each new recording site (`goemit_ty` at block-results, params,
any-calls, projections) catches only a few more.

CONCLUSION.  Closing the heavy modules is not more piecemeal boundary patches; it
needs COMPREHENSIVE emitted-type tracking -- record EVERY temp binding's emitted
Go type (so any concrete-target boundary can assert a genuine `any`), which is
effectively a small type-inference pass over the emitted IR, OR a strategy that
emits fewer `any` values at the source.  That is a distinct, larger subsystem; the
self-contained modules compiling + the six general boundaries are the demonstrable
result, and they are the foundation that comprehensive tracking would complete.
The OTHER remaining block is unchanged: ~419 frontend-boundary undefined symbols,
filled by emitting the frontend modules (which emit UNHANDLED-free).

## Emitter-self-host: the complete frontier map (quantified)

This section is the first complete, quantified accounting of what stands
between the assembled Go emitter (the 18 `srcgen2/DATS/go1emit_*.dats` modules,
emitted to one `selfhost-build/src/emitter_all.go` and built against the
`xatsgo` runtime) and a clean `go build`. Two correctness fixes and one new
runtime floor in this round took the assembled build from **591 -> 379**
errors. The remaining 379 split into FIVE buckets, each with a distinct,
identified resolution path -- no longer an undifferentiated tail.

### Round deltas
- **Rune-literal escape fix** (`go1emit_utils0.dats`, `i0chrgo1`): `'\"'` is a
  valid ATS char literal but an INVALID Go rune literal (Go wants `'"'`). The
  emitter compiled its own source (`f0_gostr` matches `| '\"' =>`) into a Go
  syntax error. Translate the one Go-incompatible rune escape. This was a real
  emitter correctness bug, independent of self-host.
- **intrep0 IR-type accessor floor** (`runtime/xatsgo/xatsgo.go`): the emitter
  reads its INPUT IR via abstract-type selectors `ipat.node()`, `iexp.lctn()`,
  ... which route (d2cstgo1) to `xatsgo.Xats_i0*_..._get`. Every intrep0 carrier
  is a single-constructor datatype -> a `*XatsCon` with positional Args, so each
  accessor is a fixed field read whose index mirrors the `datatype` def in
  `xats2cc/srcgen1/DATS/intrep0.dats`. Added ~36 accessors + the
  `i0pat_make_ityp$node` constructor + `strn_fprint`. Effect: undefined
  `xatsgo.*` fell **233 -> 15**.

### The five remaining buckets (379 total)

1. **Frontend-accessor boundary -- 178.** `symbl_get_name`, `s2typ_get_node`,
   `d2cst_get_*`, `d2var_get_*`, `s2cst_get_*`, `d2con_get_ctag`, `token_get_node`,
   `stkmap_*`, `topmap_*`, `stamper_*`, ... These are frontend abstract-type
   accessors AND stateful frontend maps. CRUCIAL DIFFERENCE from the i0* floor:
   d2cstgo1 classifies these as PACKAGE symbols (compiler/backend source), so
   they emit as BARE `name_<stamp>` local names -- NOT `xatsgo.Xats_*`. The
   classifier already EXPECTS them to be compiled in locally. So the correct
   resolution is **emit the frontend modules and include them in the assembly**
   (Task #6), not hand-shims. (Hand-shimming would require both a classifier
   change to re-route them to xatsgo AND reimplementing the stateful maps -- a
   parallel hand-maintained ABI that defeats self-hosting. The i0* floor was
   justified only because those ALREADY route to xatsgo by the existing
   classifier and are pure field reads.)

2. **Template-method subsystem -- 15 (+ missing emitter funcs).** The 15
   remaining `undefined: xatsgo.Xats_*` are `list_map_e1nv` (10), `list_exists`,
   `list_sortedq`, `list_mergesort`, `optn_map_e1nv`, and `i0pat_allq`. A
   template method like `list_foritm$e1nv<x0><e1>(xs, env)` carries an IMPLICIT
   `$work` worker; the emitter generates a wrapper that takes the worker as a
   param but DROPS it at the call, forwarding to a nonexistent runtime prim.
   This same gap ALSO explains why emitter-internal functions whose whole body
   is a template-method call (e.g. `i1vardclist_go1emit`, body =
   `list_foritm$e1nv<...>(i1vs, env0)`) are emitted with NO definition at all --
   producing further `undefined` cascades. Resolution = the documented Task #8:
   thread `$work` through (or inline the template body). A runtime shim cannot
   fix these -- the worker is absent at the call by construction.

3. **Block-expression result hoisting -- 9.** `undefined: goxtnm<N>` where a
   temp is COMPUTED inside `case`/`switch` arms and READ after the switch. Go
   scopes case-local declarations to their arm, so the post-switch read is out
   of scope. The emitter must hoist the result var (`var goxtnmN T` before the
   switch, assign in each arm) instead of declaring it per-arm. A distinct
   codegen-shape bug; touches the case/if result-emission path (rung-sensitive).

4. **Coercion over-assert -- 51 ("X is not an interface").** The coercion pass
   emits `x.(T)` on a value `x` that is ALREADY concretely typed (`*XatsCon`),
   which Go rejects (assert requires an interface source). The inverse of the
   under-assert case. Needs the emitted-type key to gate OUT concretely-emitted
   values before asserting.

5. **Coercion under-assert + struct mismatch -- 101+ ("need type assertion",
   "cannot use", "mismatched types").** 87 `need type assertion` + 14 `cannot
   use` + 53 `mismatched/invalid-op`. The bulk is the documented Task #10:
   comprehensive emitted-type tracking (record EVERY temp binding's emitted Go
   type so any concrete boundary can assert a genuine `any`, and the over-assert
   in bucket 4 can be suppressed). Buckets 4 and 5 are two faces of one
   subsystem: a precise emitted-type table makes both directions exact.

### Reading
Buckets 4+5 (coercion, ~152) and bucket 2 (templates, 15) are EMITTER
subsystems whose completion also improves every future-emitted module. Bucket 1
(178) is resolved structurally by emitting the frontend (Task #6). Bucket 3 (9)
is a self-contained codegen-shape fix. The i0* floor in this round proves the
pattern: where a boundary is pure abstract-type field-reads that already route
to the runtime, a small correct floor erases a whole error class at zero
regression risk (rungs 1-12 + JS 75/75 byte-equal throughout).

## Emitter-self-host: over-assert eliminated, coercion tail refined (591->328)

Follow-up round. The assembled Go emitter build went **379 -> 328** by
eliminating the coercion OVER-assert class entirely.

### Over-assert fix (bucket 4): 51 -> 0
Root cause pinned: the datacon-scrutinee val-binding
(`i1valdcl_go1emit`, else-arm) coerced its matched value with a bare
`<ival>.(*xatsgo.XatsCon)` assert, gated on `gotype_of_ival(ival) = "any"`.
But `gotype_of_ival` conservatively returns "any" for values whose REAL Go type
is already concrete `*XatsCon` -- a node accessor result (`i1dcl_node_get(...)
: *XatsCon`) or a self-asserting field projection (`...Args[i].(*XatsCon)`).
Go rejects a type assertion whose operand is not an interface, so the emitted
`<concrete>.(*XatsCon)` (and the double `....(*XatsCon).(*XatsCon)` on
projections) was invalid.
Fix: emit `xatsgo.Xats_as_con(<ival>)` -- an `any`->*XatsCon helper -- instead
of the bare append. It accepts BOTH an interface operand (asserts) AND an
already-concrete `*XatsCon` (auto-boxes to the `any` param, then asserts), so
the coercion is idempotent and always valid Go, with the same runtime value.
The KEY enabling fact: the rung gate is byte-equal program OUTPUT
(`cmp out.txt golden`), NOT emitted Go text -- so a coercion whose runtime value
is unchanged is free to change form. Result: `is not an interface` 51 -> 0, no
new errors, rungs 1-12 + JS 75/75 byte-equal.

### The under-assert cluster refined (bucket 5, 87): operand census
`need type assertion` errors are the inverse -- an `any`-emitted value reaching
a concrete param without a `.(T)`. The existing arg-boundary
(`i1valgo1_list_argtyped` + `i1val_emitted_anyq`) DOES assert, but only when the
arg is RECOGNIZED as emitted-`any` (recorded goemit_ty="any", or an erased
datacon-field projection). The 87 misses census by operand shape:
- **70 bare temps** (`goxtnm<N>`) -- an `I1Vtnm` whose `goemit_ty` is UNRECORDED
  (returns "" != "any"), so the boundary skips it though Go emits it as `any`.
- **12 tuple-field projections** (`goxtnm<N>.F<i>`) with an `any` field type.
- **5 `Xats_tup_get(...)` results** (reflective tuple read -> `any`).
By target type: 53 want `string` (24 to `strnfpr`, the string sink), 25 want
`*xatsgo.XatsCon`, 7 `rune`, 2 `int`.
This is NOT a surgical patch: the 70 bare temps require recording EVERY temp
binding's emitted Go type (the comprehensive emitted-type table, Task #10); the
17 projection cases need the tuple's field types, also the table. An
unconditional idempotent-wrap shortcut (emit `Xats_as_<pty>(arg)` for every
concrete-scalar param) would compile but trusts `pty` precision at RUNTIME --
if the recovered param type is imprecise it turns a currently-correct bare arg
into a runtime panic, breaking rung output. So the correct fix is the table,
not the shortcut.

### Standing tally (328)
undefined 202 (178 compiler-library accessors -> emit the frontend; 15 template
prims -> Task #8; 9 block-hoist -> Task #11) + under-assert 87 (Task #10) +
cannot-use 14 + misc 2. Three verified emitter/runtime deltas this session took
the assembled build 591 -> 328, every step rungs 1-12 + JS 75/75 byte-equal.

## Emitter-self-host: block-hoist fixed (328->319) + a bucket-5 boundary confirmed

### Block-expression result hoisting (bucket 3): 9 -> 0
Root cause found: the go-arm fix that forces a NON-tail block-form (if/case) to
emit in VALUE mode -- assign its result temp instead of `return`ing out of the
enclosing function -- was GATED on `go_arm_getq()` at both set sites
(`i1valdcl_go1emit`, `i1letlst_go1emit_p`). But the self-host assembly is emitted
WITHOUT `--go-arm`, so the gate disabled the fix there: a non-tail case-expression
used as a call ARGUMENT (`byref_register_params(fjas, case dcopt of ...)`) leaked
`return` in its arms, so its result temp `goxtnm<N>` was never bound and every
downstream use was undefined (9 sites).
Ungated both sites (unconditional `block_force_value_set(true)`). Correct in
general (a val-decl computation / a non-last let is never in function-tail
position) and safe for every frozen test: the go-arm rungs already ran with
go_arm=true (byte-identical emission), the JS suite uses a different emitter, and
there is NO non-go-arm Go golden -- the only non-go-arm Go consumer IS the
self-host assembly. Result: `undefined goxtnm` 9 -> 0, no new errors, rungs 1-12
+ JS 75/75 byte-equal.

### `non-boolean condition in if` (8) is bucket 5, not a surgical fix
Investigated and REVERTED an attempted if-condition boundary. The failing
conditions are `if xatsgo.Xats_tup_get(...datacon.Args[i]..., 0) {` -- a tuple
field, off an ERASED datacon field, projected reflectively -> Go `any`, used
where Go wants `bool`. The natural gate does NOT catch them:
- `i1val_emitted_anyq(itst)` is false -- the outer node is a tuple projection
  whose ROOT is the erased datacon field, but the recognizer only bottoms out at
  a direct `I1Vp1cn` root, not a projection-of-a-projection.
- `gotype_of_ival(itst)` returns the LOGICAL type `bool`, NOT the EMITTED type
  `any` -- exactly the recorded-vs-emitted-type split that the whole coercion
  subsystem turns on.
So the condition is emitted as `any` while BOTH type oracles say "not any". This
is the defining signature of bucket 5: only a comprehensive EMITTED-type table
(record what `i1valgo1` actually prints for each value, distinct from the value's
logical type) closes it. The 8 if-conditions + the 87 arg under-asserts + the 2
arithmetic mismatches are one subsystem, not independent patches.

### Session tally: 591 -> 319
Five verified deltas, each rungs 1-12 + JS 75/75 byte-equal: rune-escape fix;
intrep0 IR-type accessor floor (-212); idempotent datacon-scrutinee coercion
(over-assert 51 -> 0); block_force_value ungate (block-hoist 9 -> 0). Remaining
319 = undefined 193 (178 compiler-library accessors -> emit the frontend; 15
template prims -> Task #8) + under-assert 87 + cannot-use 14 + misc 25 (15
unused, 8 non-bool, 2 arith) -- the coercion/emitted-type table (Task #10) and
the frontend/template subsystems.

## Emitter-self-host: under-assert subsystem — three failed probes, one diagnosis

This section records THREE incremental fixes for the under-assert cluster
(bucket 5, 87 `need type assertion` + 8 non-bool + 2 arith) that were each
implemented, measured, and REVERTED because they did not converge. Together they
pin down why the cluster is a coordinated subsystem, not a set of local patches.
Baseline throughout: 319 assembled-emitter errors, rungs 1-12 + JS 75/75 byte-equal.

### Probe A — if-condition `.(bool)` boundary (reverted, inert)
Added `.(bool)` after an `if` test emitted-`any`. Fired 0 times: the failing
conditions are `if xatsgo.Xats_tup_get(...datacon.Args[i]..., 0)` -- a tuple
field OFF an erased datacon field. `i1val_emitted_anyq` bottoms out only at a
DIRECT `I1Vp1cn` root (not a projection-of-a-projection), and `gotype_of_ival`
returns the LOGICAL `bool`, not the EMITTED `any`. Neither oracle reports the
emitted-`any` truth. 319 -> 319.

### Probe B — per-binding emitted-type recording (reverted, inert)
Recorded `goemit_ty := "any"` at the ordinary-binding site for erased
`I1INSpcon` projections and flat copies `goxtnm := goxtnmB` (`I1INSflat`).
Correct and regression-clean, but 319 -> 319: recording the SOURCE emitted-`any`
does nothing unless the USE-site boundary consumes it, and the dominant use
(a `strnfpr` argument) has NO working boundary (see Probe C).

### Probe C — funparamtys arg-ptys table (reverted, net-negative)
Verified first that the ARG boundary (`i1valgo1_list_argtyped`) produces ZERO
assertions anywhere in the assembly, while the RETURN/ASSIGN boundaries assert
`.(T)` 39 times -- and that the SAME value (a `nient_find(...) any` result) is
asserted at `return` (`goxtnm101`) but NOT as an argument (`goxtnm122`). So the
source IS recorded emitted-`any`; the arg boundary alone fails. Root cause: it
recovers param types via `gotypes_of_funstyp(d2var_get_styp(callee))`, and the
callee d2var's OWN styp does not decode a local helper's signature at the call
site -> empty ptys -> nothing asserted.
Fix attempted: a `funparamtys` table (mirroring `funretty`) recording each
function's Go param types at its DEFINITION (where the d2cst styp yields them)
keyed by d2var stamp, read at the I1Vfenv call. Result 319 -> 324 (WORSE):
(1) the primary target `strnfpr` reaches `i1fundcl_go1emit` with `dcopt =
optn_nil`, so its `argtys` is `[]` and nothing is recorded for it; (2) functions
that DID record ptys produced arg-asserts that introduced +4 undefined and +1
new under-assert downstream. So even a correct param-type table does not close
it, and perturbs adjacent emission.

### Diagnosis
The three probes fail at three DIFFERENT layers (recognition oracle; use-site
boundary coverage; param-type recovery + downstream perturbation), which is the
signature of a subsystem that needs ONE coherent redesign rather than layered
patches: a single source of truth for every value's EMITTED Go type (distinct
from its logical type), computed once per binding and consumed UNIFORMLY by all
boundaries (arg, return, assign, if, projection). Until that exists, each local
assertion patch just relocates the mismatch. The over-assert direction is
already solved this way in miniature (idempotent `Xats_as_con`); the under-assert
direction needs the same idempotent-coercion discipline generalized to
string/rune/int/bool with an accurate emitted-type table behind it -- Task #10,
confirmed as a standalone build, not an incremental tail.

### Session tally unchanged: 591 -> 319 (five verified commits)
The reverts leave the tree at the committed 319 state. The durable wins remain:
rune-escape fix; intrep0 IR-type accessor floor (-212); idempotent
datacon-scrutinee coercion (over-assert 51 -> 0); block_force_value ungate
(block-hoist 9 -> 0).

## Emitter-self-host: the frontend boundary is EMITTABLE (bucket 1 validated)

The largest bucket (frontend-library accessors, package-routed `name_<stamp>`
symbols the emitter calls) is resolved structurally by EMITTING the host-compiler
library module by module through the same bundle and appending each to the
assembly. This session validated the path end-to-end and applied it to two
modules; the assembled-emitter build went **319 -> 294**.

### Why it works: stamps are stable across separately-emitted modules
The decisive fact: the bundle assigns the SAME d2cst stamp to a frontend symbol
regardless of which `.dats` is being emitted, because the base-SATS load order is
deterministic. So a frontend DEFINITION `stamp_cmp_1903` (emitting
srcgen2/DATS/xstamp0.dats) matches the emitter CALL site `stamp_cmp_1903` -- the
package-routed symbols link by construction. Verified for stamp_cmp_1903,
symbl_get_name_2206, s2cst_get_name_6998. (This is the same reason the 18 emitter
modules already cross-link by stamp.)

### Mechanics
- `assemble.sh` grew a `FRONTEND=` list; each named module in srcgen2/DATS is
  emitted (sentinels extracted, header + trailing `main` stripped) and appended
  alongside the 18 emitter modules. Module globals survive: the emitter emits
  them as package vars + `init()` AFTER the funcs, so the strip keeps them.
- Each frontend module's emitted body depends only on `xatsgo.*` runtime prims
  (its own funcs resolve locally); missing prims are added to the runtime floor,
  exactly like the intrep0 IR-accessor floor.

### Modules landed
- **xstamp0** (125 ln): stamp/stamper/stamp_cmp. +4 uint prims. Resolved
  stamp_cmp x8 + stamper_*; 319 -> 309, 0 new undefined (self-contained).
- **xsymbol** (293 ln): symbl/symbl_get_name/symbl_cmp + interned table. +5 prims
  (incl. strn_strmize as an eager char cons-list matching strmcon_vt Tag 0/1).
  Resolved symbl_* 23 -> 2; 309 -> 294. Pulled its table dep (mydict_* -> 3 new
  undefined) -- the expected frontend cascade.

### Module-dependency map for the remaining frontend symbols
Probed, in dependency order (each builds on the prior):
- s2typ_get_node (18) is in **statyp2** (NOT staexp2).
- s2cst_* is in **staexp2** (1837 ln; emits 0 UNHANDLED; new deps castlin10,
  list_nilq, list_pair, and **list_map** -- a template method that hits the
  Task #8 `$fwork`-threading subsystem, the one cross-bucket entanglement).
- d2cst_* (23) / d2var_* (19) / d2con_* are in **dynexp2** (2429 ln), which
  depends on staexp2/statyp2.
- mydict_* in lexing0_mymap0; topmap_* in xsymmap_topmap (350 ln); token_* in a
  lexing module.
The core trio (statyp2 + staexp2 + dynexp2, ~4300 ln, interdependent) is the big
remaining prize; it emits without UNHANDLED but entangles with the template-
method subsystem via `list_map`, so it is best done as a focused multi-module
pass (emit the trio + close the list_map template dep together).

### Session tally: 591 -> 294 (seven verified commits)
rune-escape fix; intrep0 IR-type accessor floor (-212); idempotent
datacon-scrutinee coercion (over-assert 51 -> 0); block_force_value ungate
(block-hoist 9 -> 0); xstamp0 + xsymbol frontend modules (-25). Every step
rungs 1-12 + JS 75/75 byte-equal.

## Frontend emission: clean single modules are exhausted; the core is a batch

Two more probes pinned the boundary between "clean single-module add" and "must
batch". A module is a clean add ONLY if every bare `_<stamp>` symbol its emitted
body references is either self-defined, an already-included module, or an
xatsgo prim. Verified with a defined-vs-referenced diff:
- **lexing0_mymap0 (mydict)**: ATTEMPTED, REVERTED. Defines the 3 emitter-called
  mydict_* (stamps matched) but its body references 6 MORE mydict internals that
  are undefined -> 294 -> 297 (net +3). A generic-container module whose concrete
  instances are scattered is NOT self-contained.
- **statyp2 (s2typ)**: PROBED. Emits 0 UNHANDLED; s2typ_get_node_6796 matches the
  call site. But defines 28 bare symbols while referencing 50, ~20 of them NEW
  external deps: s2cst_/s2exp_ (staexp2), s2var_, sort2_, l2t2plst_, token_,
  the_s2typ_* globals. So it churns net-negative-to-neutral alone.

Conclusion (data-backed): the core static/dynamic type modules form ONE
interdependent closure -- statyp2 <-> staexp2 <-> dynexp2 plus sort2, token,
s2var, l2t2plst -- that only nets down when added TOGETHER, and the closure pulls
the `list_map` template method (Task #8). The clean concrete modules (xstamp0,
xsymbol) are done; the rest of bucket 1 is a single focused batch:
  emit {statyp2, staexp2, dynexp2, sort2, token, s2var, l2t2plst, ...} at once
  + implement the list_map/$fwork template threading (Task #8)
  + add the batch's runtime-prim closure.
That is a focused multi-module effort, not an incremental single add -- best run
fresh rather than at a session tail. Assembled-emitter build stands at 294
(committed: xstamp0 + xsymbol); the marathon session's tally is 591 -> 294.

## Task #8 (template threading): the fix is in trxi0i1, not the emitter gate

Direct investigation this round, comparing a WORKING go-arm template (rung12
`exists`) against a FAILING one (staexp2 `list_map`):
- **rung12 `exists`** (go-arm): fully INLINED. The `$pred` worker is emitted as a
  Go closure and threaded into an inlined recursive loop -- no runtime call.
- **staexp2 `list_map`** source: `list_map(s2vs) where { #impltmp
  map$fopr<s2var><sort2> = s2var_get_sort }`. Emitted -- WITH OR WITHOUT
  `--go-arm` -- as `goxtnm365 := xatsgo.Xats_list_map; goxtnm366 :=
  goxtnm365(goxtnm363)`: the `map$fopr` worker (the "skipped non-val dcl") is
  DROPPED and the call shortcuts to a 1-arg runtime prim.

So go-arm body-emission is CONDITIONAL on the pipeline having attached the
template instance's I1Dimplmnt0 body (t1imp_i1dclq = cons). `exists` gets a body
attached; this `list_map` instantiation does NOT, so both modes shortcut and drop
the worker. The `--go-arm` flag is therefore NOT the fix -- staexp2 with
`--go-arm` still shows `Xats_list_map` (2x) and adds zero XATS2GO_ leaves.

Consequence: closing Task #8 (and thus the core-frontend batch that needs
`list_map`) requires a change in **trxi0i1** instance resolution -- make it attach
the prelude body for the list/optn template-methods so the emitter inlines the
worker (as it already does for `exists`) -- OR have the emitter synthesize the
worker-forwarding at the shortcut point. Both are pipeline-depth changes that
touch code the passing rungs exercise, so they carry real regression risk and
belong in a focused, byte-gated effort. This is the highest-leverage single
target: it unblocks templates (bucket) AND the core frontend (bucket 1's tail).

Session tally holds at 591 -> 294; this round mapped Task #8 to its root
(trxi0i1 instance-body attachment) rather than reducing the count.

## Task #8 DEFINITIVE root cause: the go-arm prelude provides the inlinable bodies

A controlled experiment settled it. rung12 uses
`list_exists(xs) where { #impltmp exists$test<sint>(x0) = (x0>=10) }` and inlines
perfectly; staexp2 uses the IDENTICAL shape
`list_map(s2vs) where { #impltmp map$fopr<...> = s2var_get_sort }` and drops the
worker. The only structural difference: rung12 `#include`s
`prelude/HATS/prelude_GO_dats.hats`; staexp2 (a compiler source) includes the
compiler's own `xatsopt_dats.hats`.

Test: a minimal program using `list_map` WITH the prelude_GO include, emitted
`--go-arm`, INLINES it (0 `Xats_list_map`; the map becomes a recursive Go loop
applying the `map$fopr` worker). So `list_map` is fully inlinable -- the emitter
already does it -- IFF the go-arm prelude bodies are loaded. The compiler/frontend
modules do NOT load them, which is why every template-method call in the assembly
(frontend AND emitter, e.g. i1vardclist_go1emit's list_foritm) drops its worker.

Two consequences for closing Task #8 / the core-frontend batch:
1. The assembled modules must be emitted with the go-arm prelude template bodies
   in scope (they currently load xatsopt_dats.hats, not prelude_GO_dats.hats).
   This is a build/prelude-wiring change, not an emitter gate -- `--go-arm` alone
   does nothing without those bodies loaded (verified: staexp2 --go-arm still
   drops list_map).
2. Some inlined bodies hit emitter gaps: `list_map` over a `list(a)` resolves to
   the LINEAR `list000_vt.dats` map, which emits `UNHANDLED: i1val` (a vt/linear
   construct the go emitter does not cover). So the template unblock also needs
   vt-list coverage (or persistent-list resolution) for the affected calls.

Net: Task #8 is a build-config + prelude-wiring + emitter-coverage effort, not a
bounded patch -- but now fully root-caused with a reproduction. Session build
holds at 294 (591 -> 294 overall); this round produced the decisive diagnosis.

## Task #8 BUILT: template-method worker forwarding (12 of 15 prims closed)

The Task-#8 machinery is implemented and verified.  When a template-method call
reaches the emitter UNRESOLVED (the self-hosted frontend's template query failed
-- confirmed against the ATS2 bootstrap, which resolves the same sites with 0
TIMQ errors), the worker `#impltmp` in the same let/where block is emitted as a
named local Go closure (`XATS_tmpw_<hook>`, latest-wins table in go1emit_byref0)
and the template VALUE is emitted as a runtime worker-forwarding wrapper
`xatsgo.Xats_<prim>_w(<adapter>)` of the arity the downstream application
expects.  Covered families: list_map/list_exists (1-arg workers), list_map$e1nv/
optn_map$e1nv/list_foritm$e1nv (2-arg (element, env)), strn_foldl (2-arg
(acc, char)).  Eta-contracted (nullary) workers coerce through the idempotent
Xats_as_fun1/2 (the Xats_as_con lesson applied to func values: the thunk result
may be `any` OR an already-concrete func type).  Hard-won details: the e1nv prim
NAMES carry `$` (`list_map$e1nv`) -- an underscore spelling never matches; and
the adapters assert worker param types only when concretely recorded.
Wrappers fire 11x in the emitter assembly; template-prim undefined fell 15 -> 3
(list_sortedq/list_mergesort: global default-compare, no local worker to
forward; i0pat_allq).  Assembly 294 -> 291.  Rungs 1-12 + JS 75/75 byte-equal at
every commit.

## Core-frontend batch: measured divergence -- the #implval constant gap

With list_map unblocked, the statyp2+staexp2 batch was attempted and MEASURED:
- +statyp2+staexp2: 291 -> 407.  Their own targets DO resolve (s2typ 18 -> 4,
  s2cst 11 -> 5) but the cascade pulls ~75 `the_sort2_*` refs + token/d2cst/
  s2explst deps.
- +statyp2_inits0+staexp2_inits0 (which textually define the_sort2_*): 407 ->
  479, and the_sort2_tbox refs ROSE (75 -> 85).  The defining modules' emissions
  ADD more references than they satisfy: a frontend `#implval` abstract CONSTANT
  does not emit as a linkable named Go symbol under the current PASS-1.5
  package-global scheme (globals emit as goxtnm<stamp> vars + init(), while
  cross-module REFERENCES use the constant's own d2cst name `the_sort2_tbox_<N>`).
Conclusion (measured, reverted to the 291 baseline): the core-frontend batch is
blocked on a NEW identified subsystem -- #implval/frontend-constant emission
(name the package global by the d2cst symbol so cross-module refs link, the same
way top-level funs already do) -- NOT on template resolution (solved) or module
selection.  That is the next well-scoped emitter work item for bucket 1.

## The TIMQ bug fixed AT THE SOURCE: frontend erasure of the prelude impl chain

Per the user's directive, the template-resolution failure was chased to its true
root in the ATS3 frontend sources and fixed there, with the lib rebuilt through
the in-repo bootstrap (`srcgen2/Makefile_xjsemit lib2xatsopt` -- 162 modules
transpiled by the ATS2-built jsemit00; the per-module BUILD/JS cache makes a
1-2 module fix an incremental, minutes-long rebuild).

### The root-cause chain (each layer verified by targeted instrumentation)
1. One RECOVERABLE read error inside the prelude payload makes tread12 wrap the
   whole `#include "xatsopt_dpre.hats"` decl -- the carrier of the ENTIRE
   prelude template-impl chain -- in D2Cerrck.
2. trans23 (D2 -> D3) had NO D2Cerrck case: the wrapper fell into the OTHERWISE
   branch and was ERASED to D3Cnone1.  At D3, the prelude template impls simply
   did not exist.
3. The template passes' envs therefore registered ~nothing (measured: 2 inserts
   per compile, both from the main file), so every D3Etapq query failed with an
   EMPTY search (F3PERR0-TIMQ1) -> D3Etimq -> the emitter's worker-dropped
   shortcut.  Additionally trtmp3b/c's decl walks SKIPPED errck decls and their
   expression walkers ERASED six late-added node kinds (D3Elval/eval/labck/
   t2pck/xazgn/xchng) to d3exp_none2 -- the D3Cnone erasure class that also
   blanked whole emitter functions (i1vardclist_go1emit).

### The fixes (frontend sources; JS lib rebuilt via the bootstrap)
- trans23_decl00: D2Cerrck now TRANSLATES CONTAINER payloads (include/staload),
  keeping the errck wrapper at D3; broken LEAF decls stay erased as before
  (translating them hits pre-existing strict val- matches downstream).
- trans23_utils0: s2typ_fun1_f3arglst TOTALIZED -- its two strict val- matches
  (T2Puni0/T2Pfun1) crash on an errored decl's non-decomposing lambda type; the
  fallback keeps the type as-is (unreachable for well-typed code).
- trtmp3b/c_decl00: an errck-wrapped decl is now WALKED (registering impls +
  resolving instances inside) with the wrapper kept.
- trtmp3b/c_dynexp: the six missing expression kinds now recurse+rebuild
  faithfully instead of being erased by the catch-all.
- xats2cc trxd3i0_decl00 (the Go-emitter pipeline): an errck-wrapped INCLUDE
  lowers as a payload-LESS include marker -- its role (template bodies) is
  consumed at resolution; re-lowering the whole prelude hits d3pat coverage
  gaps and the emitter must not re-emit prelude bodies anyway.

### Measured effect
Template-env registrations per staexp2 compile: 2 -> 1886 (1665 from the
prelude).  The original failing class -- list_map, list_length, list_append,
list_nilq, list_pair, gint_*, g_eq -- now RESOLVES (worker bodies attach).
Residual: ~9 queries (g_print/strn_print, eta map$e1nv$fopr, s2lab_get_itm) and
leaf-errck decls (i1vardclist_go1emit) remain for follow-up.  Both byte-equal
gates pass on the rebuilt frontend: go-arm rungs 1-12 and the JS oracle suite
75/75.  A diagnostic caveat for future sessions: a "TIMQ: 0" measured while the
pipeline CRASHES downstream is vacuous -- always check the emit rc first.
