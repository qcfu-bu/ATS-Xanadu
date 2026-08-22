# Datatype representation: per-layout structs over a common header

**Decision (2026-08-21):** replace the singular
`XatsCon{Tag int; Args []any; Name string}` with ATS2's model — a common
header, one struct per constructor *layout*, typed exact-sized fields, tag
dispatch, and a cast on projection.

An earlier draft of this document proposed one Go interface per datatype.
**That was wrong**, for the reason recorded under "Why not interfaces" below.

## Why the current shape goes

`XatsCon` is a transliteration of the JS backend's tagged array
(`XATSCAPP("mycons",[1,x,xs])`). JS has one aggregate and no static types; the
Go backend copied the model so the byte-equality oracle against the JS backend
would hold during bootstrap. Sound bootstrapping, wrong endpoint. It costs:
boxed scalars, positional `Args[i]` + assert at ~17k sites, a uniform 96-byte
value whatever the arity, and a Go typechecker that cannot tell a `mylist`
from a `mytree`.

## Why not interfaces: no-op representation casts

ATS depends on layout-compatible types casting for free — `list_vt` (linear)
to `list` (non-linear) is *nothing at all* at runtime. Measured in the emitted
compiler, **620 such cast sites, every one an identity**:

    Xats_list_vt2t 302   Xats_UN_strn_vt_cast 124   Xats_cast01 79
    Xats_castlin10 47    Xats_optn_vt2t 31          Xats_castlin01 21
    Xats_cast10 10       Xats_datacopy 6

Under per-datatype interfaces, `list_vt_cons` and `list_cons` are distinct Go
types with distinct method sets, so the cast becomes either a per-cell rebuild
or an interface→interface assertion (itab lookup, can fail). Turning 620
free operations into runtime work is disqualifying.

A common handle makes every such cast free by construction. That is exactly
why ATS2 does it this way.

## What ATS2's C backend does (verified in ATS-Postiats)

    typedef void* atstype_boxed ;        // no universal struct at all
    typedef void* atstype_datconptr ;

    #define ATStysum() struct{ int contag; }
    #define ATSSELcon(pmv, tysum, lab)  (((tysum*)pmv)->lab)
    #define ATSCKpat_con1(pmv, tag) \
      ((pmv)>=(void*)ATS_DATACONMAX && ((ATStysum()*)(pmv))->contag==tag)

    #define ATS_DATACONMAX 1024
    #define ATSINSmove_con0(tmp, tag)  (tmp = ((void*)tag))   // NULLARY = the tag
    #define ATSCKpat_con0(pmv, tag)    ((pmv)==(void*)tag)

- handle is an untyped pointer; every access casts to the constructor's struct;
- constructor structs are named by a **structural hash** (`postiats_tysum_<h>`),
  so identical layouts SHARE a type — this is what makes the casts free;
- `contag` sits inside `#if(tgd)`: a single-constructor datatype carries no tag;
- **nullary constructors are the tag itself as a pointer** — zero allocation,
  zero memory, guarded by the `>= ATS_DATACONMAX` test;
- **polymorphism is uniform boxing, not monomorphization**: a type variable is
  `atstype_var` (a zero-length array of a huge struct, unusable by value), and
  polymorphic fields are `void*`.

That last point matters for expectations: our 51.4% `any` fields are faithful
to the reference implementation, not a Go-backend deficiency.

## The Go design

```go
// common header — what every handle points at
type XatsHdr struct{ Tag int }

// per-LAYOUT constructor struct: header first, typed exact fields
type zzs_ap struct {
    XatsHdr
    F0 any          // polymorphic payload
    F1 *XatsHdr     // datatype/recursive field
}

// per-datatype NAMED handle types, all over *XatsHdr
type zzt_list    *XatsHdr
type zzt_list_vt *XatsHdr
```

- **casts are free**: `zzt_list(x)` converts between named types with the same
  underlying type — compile-time only, zero instructions;
- **layout sharing** is automatic from the layout key, so `list_cons` and
  `list_vt_cons` are the same struct and the cast is free all the way down;
- **Go still catches accidental mixing** — a `zzt_mytree` where `zzt_list` is
  expected is a compile error unless the conversion is written;
- **tag dispatch is unchanged**, so all ~12.7k emitted tag tests keep working
  and this is far cheaper to land than an interface rewrite;
- **projection** is `(*zzs_ap)(unsafe.Pointer(v)).F1`. That `unsafe` buys the
  free casts and is exactly what ATS2 does — C's cast is the same operation
  without the keyword. Only the emitter writes it.

### Layout key

Encode the constructor's Go field types compactly, so identical layouts share
a struct name: `int`→`i`, `bool`→`b`, `rune`→`r`, `string`→`s`,
`float64`→`f`, datatype/recursive→`p`, polymorphic→`a`, other→`x`.
`mycons of (sint, mylist)` → fields `[int, *XatsHdr]` → **`zzs_ip`**.

### Take from ATS2

- **zero-cost nullary constructors** — ATS2 uses the tag as a pointer; Go
  can't forge pointers, but a shared singleton per tag gives the same result
  (0 bytes, no allocation) and retires the interning table;
- **no tag word for single-constructor datatypes** (`#if(tgd)`).

## Expected payoff (measured — see `bench/repr/`)

300k-cons list, per-layout structs vs today:

| payload | build | traverse | memory |
|---|---|---|---|
| scalar | **2.0x**, half the allocs | **2.3x** | 4.3x less |
| polymorphic (dominant) | **1.6x** | **1.9x** | 3x less |

The win is the *container* — dropping the `Args` slice header and `Name`, and
exact sizing — not scalar unboxing, which reaches only 6.6% of field accesses.

## Structural constraints

**intrep1 has no datatype-declaration node.** Declarations are erased into
`I1Dnone1` before the emitter runs. So drive emission from encountered
`d2con`s: register each one's layout, and emit the struct declarations at the
END of the module (Go does not care about package-level declaration order).
`assemble.sh` dedups by type name across modules — which also covers prelude
datatypes, whose declarations no module owns.

**The xatsgo package constructs two datatypes.** `jshmap_search$opt` builds an
`optn_vt` and `xatsStrmFrom` builds `strmcon_vt` cells. Emitted types live in
`package main`, which `xatsgo` cannot import. **Invert the dependency** with
constructor hooks the emitted code registers at init — the same move the JS
runtime already makes when it calls `XATS2JS_optn_vt_cons` instead of building
a layout inline.

## Work order

1. **Layout key + registry** — `go_dcon_layout_name`, per-module set. *(additive)*
2. **Declaration emission** + assemble dedup. *(additive: unused Go types are legal)*
3. **Construction** — `&zzs_ip{XatsHdr{1}, x, xs}` replacing `XatsCon<n>(...)`.
4. **Projection / field set** — cast + `F<i>` replacing `Args[i]` + assert.
5. **Handle types** — per-datatype named types; cast sites become conversions.
6. **Nullary singletons**; drop the tag for single-constructor datatypes.
7. **Constructor hooks** for `optn_vt`/`strmcon_vt`; delete the two xatsgo sites.
8. **Retire** `XatsCon`, `Args`, `Xats_as_con`, `XatsCon0..N`, interning.

Steps 1-2 are additive and land green on their own; 3-4 must land together per
layout, since construction and projection must agree.

## Verification

`iterate.sh quick` (~55s, psuite 75/75 byte-equal vs the JS backend) per edit;
`bench` (`b04`/`b05`/`b08`/`b11`) as the allocation scoreboard; `bench/repr`
for representation-level questions; `iterate.sh full-verify` before committing
anything that changes emission shape.
