# JS-model residue audit (2026-08-22)

A comb through the runtime package, the emitter, and 445k lines of emitted
compiler, looking for what the JS backend's model still costs us: live
reflection, redundant boxing, and JS-shaped runtime concepts.

Counts are from the emitted self-host compiler (`selfhost-build/src/`, 445206
lines) unless marked *(sample)*, which means the 12-module `typecheck-sample`
package (45655 lines) emitted AFTER the layout-`p` flip.

---

## A. Live reflection

### A1. `Xats_p2tr_get`/`_set` fall through to reflection for datatype cells — REGRESSION

```go
switch q := p.(type) {
case *any:  ...
case *int, *bool, *string, *int32, *float64: ...
}
return reflect.ValueOf(p).Elem().Interface()   // <- everything else
```

The switch has no case for `**XatsHdr`. Before the layout-`p` flip a by-ref
datatype cell was declared `any`, so `&cell` was `*any` and hit the first case.
The flip made that cell `*xatsgo.XatsCon`, so `&cell` is now
`**xatsgo.XatsCon` — which lands in the reflection default.

**928 call sites** (`p2tr_get` 454, `p2tr_set` 474). The consumers are
`func(x any) any` wrappers, so the dynamic type depends on the caller and
inspection cannot prove the case is reached; adding it is correct regardless
and costs one switch arm.

### A2. `Xats_tup_get` — 47 sites

Reads the i-th field of a flat tuple that reached the callee erased to `any`,
via `reflect.ValueOf(t).Field(i)`. Needed only because the root was erased;
a typed root emits `root.F<i>` directly.

### A3. `Xats_as_tup2` — 38 sites

The anonymous-struct identity repack. This is the same mechanism that cost
`b11_tup` its entire margin (fixed at that one site in `08f638203` by
recording callee return types); 38 sites remain where the producer's type is
still unknown to the emitter.

### A4. Dead reflection

`Xats_call_fun`'s `reflect.Call` fallback and `Xats_as_tup3` have **zero**
references across every emission source. Unreachable, not worth removing on
its own — but do not let the fallback grow.

---

## B. Redundant boxing — the dominant cost

**57584 coercion calls** total, of which **`Xats_as_con` is 46538** (81%).
Everything else is small: `as_int` 6558, `as_bool` 3228, `as_str` 758,
`as_rune` 480, `as_dflt` 22. Plus 7256 bare `.(T)` assertions.

Tracing every `Xats_as_con(<temp>)` back to its binding *(sample)*:

| operand | share | redundant? |
|---|---|---|
| bound by `Xats_as_con(..)` or a construction | 26.2% | **yes — already `*XatsCon`** |
| a parameter already typed `*xatsgo.XatsCon` | 11.0% | **yes** |
| a projection result | 1.4% | yes when the slot is `p` |
| a parameter typed `any` | 4.3% | no |
| some other call result | 57.1% | only if the callee's return type is recorded |

So **~37% are provably redundant with information the emitter already holds**,
before counting call results. Three specific causes:

### B1. The structural-pattern bind records the wrong type

`i1valdcl_go1emit` emits `itnm := xatsgo.Xats_as_con(ival)` but records
`itnm`'s type by *copying the source temp's* recorded type — which for an
`any` parameter is `"any"`. The recorded type therefore contradicts the text
just emitted, and every projection rooted at that temp re-coerces:

```go
gs2tnm239 := xatsgo.Xats_as_con(gs2tnm238)
_ = gs2tnm239
return zzpzzs_aaipaaaa(xatsgo.Xats_as_con(gs2tnm239)).F1
                       ^^^^^^^^^^^^^^^^^^ re-coerces a *XatsCon
```

This is the same class of defect as the return-boundary bug fixed earlier in
this cycle: an emitted-type table that does not describe the emitted text.

### B2. The projection root coerces unconditionally

`i1con_proj_go1emit` always wraps its root in `Xats_as_con`. 4757 of those
wrap a `zzpzzs_` projection, whose slot is a typed `*xatsgo.XatsCon` field
after the `p` flip.

### B3. The constructor-argument boundary uses the weak type function

`i1valgo1_list_argtyped` decides elision with `gotype_of_ival` — which types
only *literals* — while every other boundary in the emitter
(`go1emit_dynexp` lines 1323, 2354, 5547, 5759) uses `go_ival_goty`, which
consults the recorded-type table. It is the sole holdout. *(sample)*: 178 of
310 constructions into a layout with a `p` slot carry a coercion.

---

## C. JS-model concepts still in the runtime

### C1. UTF-16 string view — intentional, tied to the JS oracle

`strn_get_at`/`strn_length` index `utf16.Encode([]rune(s))` behind a
single-entry cache, because the JS model's string is UTF-16 and a Go byte
model shifts every diagnostic offset after any non-ASCII character. **515
sites.** The cache hit is O(1) only because Go short-circuits string
comparison on equal data pointers; alternating two same-length strings would
make each access a full memcmp. Retire when byte-equality against the JS
backend stops being the oracle — not before.

### C2. `map[any]any` in `jshmap`

Reproduces JS `Object.keys` enumeration order (integer-like keys ascending,
then string keys by insertion) because that order is observable in
template-instance emission order. Interface-keyed hashing is slower than a
typed map, but there are only ~23 sites. Low priority.

### C3. Print store

`xatsStorePut` emulates the JS driver's store-then-flush so interleaving
matches byte-for-byte. Deliberate, same lifetime as C1.

### C4. Cosmetic

- 105 leaves still named `Xats_XATS2JS_*` (naming only — the arm is chosen by
  the source's `.hats` include, not by these names).
- `XATSNIL()` (3015), `XATSSTRN` (7273), `XATSSTR0` — identity/constant
  functions Go inlines away. Noise in the source, free at runtime.
- Stale comments in `xatsgo.go` describing `Args`, nullary interning, and
  `conInline` inline storage — all mechanisms that no longer exist. The
  `Args` field itself survives only inside `XatsExn`, where an open sum with
  a variadic payload genuinely wants it.

---

## D. Structural: the closure model

**57901 func literals against 4689 top-level functions — 12.3 : 1.**

- `X := func(...)` bound to a temp: **39357**
- `_ = func(...)` emitted and immediately discarded: **3873**
- passed inline as an argument: 103

This is the JS model's signature — a template instance becomes a nested
closure rather than a monomorphized top-level function. It is the largest
remaining structural residue and the most plausible remaining allocation
source, which matters because profiling put allocation/GC at the top of the
compiler's own cost. The 3873 discarded literals are pure waste in the
emitted source: they exist so an instance's temp binding resolves, then are
thrown away.

A representative slice, carrying five findings at once:

```go
_ = func() any {                                    // D: discarded thunk
    return xatsgo.Xats_XATS2JS_gint_eq_sint_sint
}
go0tnm91 := stamp_cmp_1903(xatsgo.Xats_tup_get(...), go0tnm87)   // A2: reflection
go0tnm92 := (xatsgo.Xats_as_int(go0tnm91) == 0)                  // B: unbox of a call result
go0tnm86 = xatsgo.Xats_as_con(zzpzzs_aa(...).F1.(*xatsgo.XatsCon)) // B2: assert AND coerce
go0tnm87 = go0tnm87                                              // self-assignment (TCO rebind)
```

---

## E. Clean — checked, nothing to do

- **Numbers are native Go `int`**, not JS float64. `Xats_as_int` is
  rune-tolerant only at the int boundary, which is deliberate.
- **No dead exported runtime surface.** Of 193 exported names, 31 are
  unreferenced by emitted code, and every one of those is a delegation target
  of a live `XATS2JS_` alias. The 2026-08-20 prune (`fcfc6d376`) was complete.
- **Scalar arithmetic is not boxed** in the compiler: zero `sint_*` fallback
  calls — the native-infix path covers every site.
- **Flat tuples and records are already unboxed** — anonymous Go structs with
  typed fields, passed by value.

---

## F. Found by full-verify, not by the audit — two defects the typed-`p` slot exposed

Both were invisible to any single-module check and to the audit's static
reading; only the 194-module assembly surfaced them.

### F1. Abstract types have a SPLIT VIEW inside the module that assumes them

`iltstk` is a local `datavwtp` in `trxi0i1_myenv0.dats`, assumed to the SATS
`#absvtbx iltstk_vtbx` by `#absimpl`. So the same value is typed two ways in
one module: a constructor **field** holding it types from the local datatype
(`*xatsgo.XatsCon`), while a **SATS-declared signature** over it types from
the abstract box (`any`). Both are right from their own vantage point, and
under erased fields both landed on `any`, so nothing noticed. With typed `p`
slots, `&field` is a `**XatsCon` meeting a `*any` parameter — **36 errors**
across `trxi0i1_myenv0`, `trtmp3b_myenv0`, `trtmp3c_myenv0`.

Fixed by resolving the `#absimpl` history (`s2abs_get_styp`) — but **only in
the by-reference position**. Resolving it by value splits the signature across
modules instead: `#absimpl d2cst_tbox = d2cst` would make `d2cst_get_stmp`
take a `*XatsCon` inside `dynexp2.dats` while every other module, seeing only
the SATS, passes `any`. That was tried and immediately produced a fresh error
class. By-ref is safe because `&`-taking of these abstract boxes is
intra-module — they are the module's own private state.

Two traps in the fix itself, both costing a rebuild cycle:
- the `>>` consumption wraps the type in `T2Patx2`, which `gotype_of_arg`
  unwraps before handing the inner on, so the chase needs that arm;
- the new test must precede the `g1 = "any"` arm, which would otherwise
  answer `*any` first — an abstract inner ALWAYS types to `"any"`.

### F2. The read-projection never registered its layout

`i1con_construct_go1emit` and the lvalue/assign arms call `layout_add`; the
read path in `i1con_proj_go1emit` did not. A module that only ever *projects*
a layout therefore emitted `zzpzzs_<lay>(..)` with no struct or cast helper
declared — `undefined: zzpzzs_aia` at link time. Invisible per-module,
because the failure only exists once the modules are assembled together.

### A note on the hand-written shims

`assemble.sh` contains glue that hardcodes layout names (`zzpzzs_aa`,
`zzpzzs_ia`, `zzpzzs_aia`) for walking `i0pat`/list structures. Layout keys
are **derived from field types**, so the `p` flip renames them. A *missing*
name is a loud link error, but a name that still exists with a *different*
shape is silent corruption: `zzpzzs_aa` on a cell whose real layout is
`zzs_ap` reads a 16-byte `any` where an 8-byte pointer lives, running past the
allocation. The sweep (which runs the binary) is what would catch it. Worth
retiring the hardcoding.

## Priority

1. **A1** — a regression this cycle introduced; one switch arm.
2. **B1 + B2** — together they remove the redundant-coercion chain at its
   source. Staged as `patch-A-projroot.py`.
3. **B3** — one identifier (`gotype_of_ival` -> `go_ival_goty`).
4. **D** — the closure model. Large, and the right next structural project
   rather than a fix.
5. **C4** — cosmetic; fold into whatever touches those lines next.
6. **C1/C2/C3** — blocked on retiring the JS byte-equality oracle.
