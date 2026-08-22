# Datatype representation: one Go interface per datatype

**Decision (2026-08-21, chief architect):** emit one Go interface per datatype
and one struct per constructor, with statically-sized typed fields. Replaces
the singular `XatsCon{Tag int; Args []any}`.

## Why the current representation exists, and why it goes

`XatsCon` is a transliteration of the JS backend's value model. The JS emitter
emits `XATSCAPP("mycons", [1, x, xs])` — a tagged array — because JavaScript
has one aggregate and no static types. The Go backend was built as a
*differential twin* of the JS backend (every emitted program's stdout is
byte-compared against it), so mirroring that model was the fastest way to make
the byte-equality oracle meaningful. That was sound bootstrapping; it is not a
sound endpoint. Everything wrong downstream follows from that one decision:

- `[]any` fields, so every scalar payload is heap-boxed;
- positional `Args[i]` + a type assertion at ~17k emitted sites;
- one uniform size (96 B) whether the constructor holds 0 fields or 3;
- `Xats_as_con` coercions everywhere, because the handle is universal;
- **Go's typechecker is inert** — it cannot tell a `mylist` from a `mytree`,
  so no emitter bug is ever caught by `go build`.

The frontend always had the information to do better; the JS-shaped target
discarded it.

## The representation

For `datatype mylist = mynil of () | mycons of (sint, mylist)`:

```go
type zzt_mylist interface{ zzi_mylist() }        // the datatype IS the interface

type zzc_mynil struct{}                          // 0 bytes
func (*zzc_mynil) zzi_mylist() {}

type zzc_mycons struct {                         // 24 bytes, 1 alloc
    F0 int                                       // unboxed scalar
    F1 zzt_mylist                                // recursive: same interface
}
func (*zzc_mycons) zzi_mylist() {}
```

| | today | per-datatype interface |
|---|---|---|
| `mycons` | 96 B, scalar boxed | 24 B, unboxed |
| `mynil` | 96 B | 0 B (Go shares empty-struct addresses) |
| construct | `XatsCon2(1,x,xs)` | `&zzc_mycons{x, xs}` |
| match | `v.Tag == 1` | `case *zzc_mycons:` (itab compare) |
| project | `v.Args[1].(*XatsCon)` | `vv.F1` (typed, Go-checked) |
| wrong tag | reads garbage / panics | **compile error** |

A `mytree` cannot be passed where a `mylist` is expected — Go rejects it.

## Everything needed already exists in the frontend

| need | source |
|---|---|
| a datatype's constructors | `s2cst_get_d2cs(s2c0)` (returns `optn_vt` of the d2con list) |
| constructor field types | `gotype_of_dcon_field(dcon, idx)` — already used to synthesise projection asserts |
| constructor ctag / excptn-ness | `d2con_get_ctag`, `d2con_is_excptn` |
| the parent datatype of a con | result type of `d2con_get_styp(dcon)` |
| is this styp a datatype | `styp_is_datatype` / `go_s2cst_is_boxed_datatype` |

Arity is fixed at declaration and never grows, so every struct is statically
sized.

## The two structural problems and their solutions

### 1. Where do type declarations get emitted?

intrep1 has **no** `I1Ddatatype` node — datatype declarations are erased into
`I1Dnone1` before the emitter sees them. So do not drive emission from
declarations. Instead: whenever the emitter encounters a `d2con` (at a
construction or a pattern), register its **parent datatype**; emit the
interface + all constructor structs for every registered datatype, keyed by a
stamp-derived mangled name.

Modules are emitted by independent processes and concatenated by
`assemble.sh`, so the same datatype will be emitted by several modules.
**Deduplicate at assembly time** by type name, keeping the first occurrence.
This also covers prelude datatypes, whose declarations no module owns.

### 2. The xatsgo package constructs two datatypes

`xatsgo` (our support package — *not* Go's runtime) builds cons in exactly two
places, because two CATS leaves return structured data instead of primitives:

- `Xats_XATS2JS_jshmap_search_opt` → an `optn_vt`
- `xatsStrmFrom` → `strmcon_vt` cells

Emitted types live in `package main`; `xatsgo` cannot import `main`, so it
cannot name them. **Invert the dependency** — exactly what the JS runtime
already does when it calls `XATS2JS_optn_vt_cons(itm)` rather than building a
layout inline:

```go
// xatsgo — never names a main type
var XatsMkOptnCons func(any) any
var XatsMkOptnNil  func() any

// emitted main — registers its own structs at init
func init() {
    xatsgo.XatsMkOptnCons = func(x any) any { return &zzc_optn_vt_cons{x} }
    xatsgo.XatsMkOptnNil  = func() any { return &zzc_optn_vt_nil{} }
}
```

No import cycle, no `unsafe`, no curated type-name table. (ATS2's C backend
solves the same acyclic constraint the same way: generated code owns the
layouts, the runtime stays generic over them.)

## Emitter work, in dependency order

1. **Mangling + registry** — stable `zzt_`/`zzc_` names from datatype/con
   stamps; a per-module set of datatypes touched.
2. **Declaration emission** — interface, structs, marker methods; assemble.sh
   dedup by name.
3. **Construction** — `&zzc_x{...}` replacing `XatsCon<n>(tag, ...)`.
4. **Match** — tag tests become type switches / assertions (~12k sites).
5. **Projection + field set** — `vv.F<i>` replacing `Args[i]` + assert.
6. **Constructor hooks** — for `optn_vt` and `strmcon_vt`; delete the two
   `xatsgo` construction sites.
7. **Retire** `XatsCon`, `Xats_as_con`, `XatsCon0..N`, the interning table.

## Open questions (measure before deciding)

- **How many constructor fields are statically scalar?** Decides how much
  unboxing is actually on the table. Polymorphic fields (`list(a)`) stay `any`
  under any representation.
- **Do per-datatype interfaces reach erased/polymorphic code?** A generic
  `list_map` takes `any`; values cross that boundary and must come back with
  an assertion to the datatype interface.
- **Cost of interface indirection** for this workload — expected small (itab
  compare), but unmeasured. Prototype one datatype and run `b04`/`b08`.

## Verification

`iterate.sh quick` (~55s, psuite 75/75 byte-equal vs the JS backend) is the
per-edit gate; `bench` (`b04`/`b05`/`b08`/`b11`) is the allocation scoreboard;
`iterate.sh full-verify` before any commit that changes emission shape.
