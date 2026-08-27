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

### Typing datatype fields ("p" instead of "a") — TRIED 2026-08-22, REVERTED

Flipping `go_layout_code` so a datatype field gets its own code `p`
(`*xatsgo.XatsCon`) instead of sharing the erased `a` slot removes a
`.(*xatsgo.XatsCon)` unbox on every read (1971 in the emitted compiler, the
largest assertion class) and halves the slot to 8 bytes. Measured: b08_bst
24% faster, b05_tree 14%. It passed psuite 75/75 and a 15-module typecheck.

**It does not survive full-verify, and the reason is not the layout rule.**

Construction and projection can derive DIFFERENT layout names for what is at
runtime the same constructor:

```go
// lexbuf0_cstrx1.dats:219  -- built as zzs_aa (F1 is a 16-byte any)
gof30tnm64 := &(&zzs_aa{XatsHdr{Tag: 1}, ...F0.(rune), ...F1}).XatsHdr
// list000_vt.dats:399, same module -- read as zzs_ap (F1 is an 8-byte pointer)
gof30tnm83 := zzpzzs_ap(xatsgo.Xats_as_con(gof30tnm79)).F1
```

**ROOT CAUSE, measured.** Instrumenting `i1con_construct_go1emit` and the
`I1Vp1cn` arm to print the constructor's name, stamp and computed field types
gives this for `lexbuf0_cstrx1`:

```
CON  list_vt_nil      stmp=10  lay=zzs_    f1=any
CON  strmcon_vt_nil   stmp=15  lay=zzs_    f1=any
CON  strmcon_vt_cons  stmp=16  lay=zzs_aa  f1=any               <- 5 constructions
CON  strxcon_vt_cons  stmp=17  lay=zzs_aa  f1=any               <- 6 constructions
PRJ  list_vt_cons     stmp=11  lay=zzs_aa  f1=*xatsgo.XatsCon   <- 7 projections, ZERO constructions
PRJ  strmcon_vt_cons  stmp=16  lay=zzs_aa  f1=any
PRJ  strxcon_vt_cons  stmp=17  lay=zzs_aa  f1=any
```

Every constructor has a unique stamp, and each one's field types are identical
at its construction and projection sites. So the layout function is NOT
context-sensitive, and there are NO duplicate `d2con` objects — both of the
obvious hypotheses are refuted.

What the data shows instead: **the module builds these cells with a STREAM
constructor and reads them with a LIST constructor.**

Counting markers alone does not establish that, since this file also builds
`strxcon_vt_cons` legitimately (lines 309/319/322).  What settles it is that
the marker is emitted INLINE at the construction site, so it maps to a source
span.  All four `cons_vt` sites bind `strmcon_vt_cons`:

```
line=109      (cons_vt(cc1, buf.1) at :112)   => CON strmcon_vt_cons
line=159      (cons_vt(cc1, buf.2) at :162)   => CON strmcon_vt_cons
line=182      (buf.2 := cons_vt(..) at :185)  => CON strmcon_vt_cons
line=219--221 (buf.1 := cons_vt(..))          => CON strmcon_vt_cons
```

with `nil_vt()` at :236/:244 correctly emitting `list_vt_nil` as the control.
The single emitted line for :219--221 carries both halves of the mix-up:

```go
goxtnm64 := /*ZZDBG-CON name=strmcon_vt_cons stmp=16 lay=zzs_aa f0=any f1=any*/
            &(&zzs_aa{XatsHdr{Tag: 1},
              /*ZZDBG-PRJ name=list_vt_cons stmp=11 lay=zzs_aa f0=any f1=*xatsgo.XatsCon*/
              zzpzzs_aa(Xats_as_con(goxtnm62)).F0.(rune), ...}).XatsHdr
```

The source is

```ats
LXBF1 of (strx_vt(sint), list_vt(char), list_vt(char))   // buf.1, buf.2 are list_vt
...
buf.2 := cons_vt(cc1, buf.2)      // resolves to strxcon_vt_cons / strmcon_vt_cons
...
val clst = list_vt_reverse0(buf.2)  // consumes them as list_vt_cons
```

and the field types differ exactly where it matters: a stream cons's tail is
`streax_vt(a)`/`stream_vt(a)`, a LAZY typedef, so `f1 = any`; a list cons's
tail is the datatype `list_vt_i0_vx(a, n)`, so `f1 = *xatsgo.XatsCon`.

Under the erased model both render `zzs_aa` and the mix-up is byte-identical
and harmless. Typed slots make them `zzs_aa` (40 B, F1 a 16-byte interface)
versus `zzs_ap` (32 B, F1 an 8-byte pointer). Reading the interface's *type*
word as a pointer makes `.Tag` garbage: `panic: XATS000_cfail` in the
linear-list reverse loop.

THE CONSUMERS come from two places, and only one was instrumented:

1. **hand-written, in-file** -- `case+ buf.N of | list_vt_cons(cc1, ccs)` at
   lexbuf0_cstrx1.dats:121 / :171 / :212 (lxbf1_getc0 / getc1 / unget).  The
   d2con is carried by the pattern; these produced the 7 PRJ markers.
2. **the prelude, instantiated** -- `lxbf1_take_clst` calls
   `list_vt_reverse0(buf.2)`, inlining list000_vt.dats:393-402 at `char`.  It
   reads via `xs0.1`, a LABEL projection, which lowers to I1Vlpcn -- a
   different emitter arm than the I1Vp1cn path the experiment hooked, so it
   emitted no markers.  **This is the path that panics.**

Path 2 matters for the fix.  A label projection has no pattern to carry the
constructor, so it is RECOVERED from the root's static type by
`zzdcon_of_i0pat` / `zzdcon_theonly` / `zzdcon_of_ityp`.  `zzdcon_theonly`
returns the datatype's unique field-bearing constructor, and the root is
declared `list_vt(char)` -- so it answers `list_vt_cons` BY CONSTRUCTION,
whatever actually allocated the cell.  It structurally cannot observe that a
`strmcon_vt_cons` built it.  Uniform boxing made that blindness free; typed
layouts turn it into a wrong offset.

WHERE THE MIS-BINDING COMES FROM (measured; corrects two earlier guesses).

`cons_vt` IS legitimately overloaded — both symloads are ACTIVE, spelled
across two lines, which is why `grep '#symload cons_vt'` misses them:

    srcgen1/prelude/SATS/VT/list000_vt.sats:503-504   cons_vt with list_vt_cons
    srcgen1/prelude/SATS/VT/strm000_vt.sats:576-577   cons_vt with strmcon_vt_cons

Neither carries a precedence (`of N`).  But overloading alone is not the bug.
A minimal probe

    fun zzmk(c0: char, xs: list_vt(char)): list_vt(char) = cons_vt(c0, xs)

resolves CORRECTLY to `list_vt_cons` (d3exp `T2Papps(T2Pcst(list_vt_i0_vx)..)`),
with or without an explicit result annotation.  The declared target type does
constrain the overload in ordinary contexts.

The failure is specific to ASSIGNMENT INTO A LINEAR RECORD FIELD.  d3exp for
the lvalue at three sites in lexbuf0_cstrx1, all the same LXBF1 field declared
`list_vt(char)`:

    :184  buf.1 := ccs                  lvalue : list_vt_i0_vx(char,..)  CORRECT
    :111  buf.1 := cons_vt(cc1, buf.1)  lvalue : strmcon_vt(char)        WRONG
    :161  buf.2 := cons_vt(cc1, buf.2)  lvalue : strmcon_vt(char)        WRONG

Where the RHS has a known type (`ccs`, bound by a `list_vt_cons` pattern) the
field types correctly; where the RHS is the overloaded `cons_vt`, the
overload's choice appears to determine the field's type rather than the
reverse.  The declared field type is not constraining the resolution.

That is a FRONT-END inference/overload defect, not a backend one: d3exp is
printed by the shared front end before any emitter runs, so the Go backend is
reporting the d3 layer faithfully.  (The xats2js reference bundle cannot serve
as a second oracle here — it resolves a different prelude root and recurses
unboundedly on this module at any stack size; it is CC_JS2_OLD in the
Makefile.)

Uniform boxing made two different datatypes' constructors interchangeable, so
this has been latent and harmless; typed slots turn it into a wrong offset.

Under the erased model this was invisible, because `a` and `p` both mapped to
`a` — the flip did not create the inconsistency, it exposed one.

**Why `go build` cannot catch this class.** `zzs_aa` and `zzs_ap` are both
valid Go, and storing a `*XatsCon` into an `any` field is legal. The mismatch
is semantic, so `typecheck-sample` is structurally blind to it; only running
the binary (regress/sweep) fails. Any future attempt needs a *layout-agreement
check* — assert one canonical name per `d2con` across a module — not more
typechecking.

Prerequisites before re-landing:

1. fix the constructor mix-up first — `cons_vt` must bind `list_vt_cons`
   where the target is a `list_vt`, or the source must stop relying on
   stream/list cons cells being interchangeable. A layout-agreement assertion
   at emission time (one canonical layout per allocation site, checked against
   the consuming pattern) would turn any remaining case into a hard error
   instead of a wrong offset;
2. `&field` and `&local` by-ref shapes must agree — needs the `#absimpl`
   history (`s2abs_get_styp`) consulted in the BY-REFERENCE position only.
   Resolving it by value splits signatures across modules: `#absimpl
   d2cst_tbox = d2cst` makes `d2cst_get_stmp` take a `*XatsCon` inside
   `dynexp2.dats` while every other module passes `any`;
3. `assemble.sh`'s hand-written shims hardcode layout names, which the flip
   renames. A missing name is a loud link error; a surviving name with a
   different shape is silent corruption. These should be emitter-generated.

Kept from the attempt (correct independently of the flip): `layout_add` at the
read-projection site, so a module that only PROJECTS a layout still declares
it; and the `**XatsHdr` arm in the runtime's p2tr type switch.

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

## BLOCKER found attempting steps 3-4: the IR erases constructor identity

Construction and projection must flip together. Construction is fine
(`i1con_construct_go1emit` has the `d2con`), and so is the *typed* projection
`I1Vp1cn(i0pat, root, idx)` — `dcon_of_i0pat` recovers the constructor, hence
the layout. But **two intrep1 nodes carry only a label**:

    |I1INSpcon of (label, i1val)   // generic/untyped projection
    |I1Vlpcn   of (label, i1val)   // datacon field as an assignable LVALUE

Without the constructor there is no layout, and without the layout there is no
field offset — `F1` sits at a different offset in `zzs_ap` (after a 16-byte
`any`) than in `zzs_ip` (after an 8-byte `int`). No generic accessor can work,
which is precisely why `Args []any` was uniform.

`I1Vlpcn` is ~88 emitted sites (the destination-passing field mutations);
`I1INSpcon` is documented as "the generic/untyped projection form kept for
totality" and may be dead in practice — unverified.

The information exists upstream and is dropped:

- `I1Vlpcn` is built in two places (trxi0i1_dynexp): one converts an
  `I1Vp1cn(i0pat, root, idx)` and **has the i0pat in hand**; the other comes
  from `I0Epcon(token, label, i0exp)`, which carries the con *expression*, not
  the `d2con` — so that path needs tracing back through trxd3i0.

Options, in order of principle:

1. **Thread the constructor through the IR** — give `I1INSpcon`/`I1Vlpcn` the
   `i0pat` (or `d2con`) the way `I1Vp1cn` already has it. Correct and
   permanent; touches intrep1.sats (stamp churn — `touch` all emitter DATS
   after) plus trxi0i1, and possibly intrep0/trxd3i0 for the second path.
2. **Recover it at the emitter by scope-walking** — the root temp is bound by
   a pattern, and `tnm_bound_by_pconq` / `i1val_pcon_tempq` already walk the
   scope for exactly this kind of question. No IR change, but fragile: it
   fails silently when the binding is not in the walked scope.
3. **Keep a boxed fallback** for those sites only — reintroduces the uniform
   `Args` representation and forfeits most of the win.

Recommendation: (1). The frontend knows the constructor at every one of these
sites; the IR simply forgets it, and every other consumer would benefit from
it being present.

A runtime prototype of the flip (header alias + layout mirrors + exception
struct) was built and reverted; it confirmed the runtime side is small —
`XatsCon` becomes a type ALIAS of the header, so all ~21k emitted
`*xatsgo.XatsCon` annotations, `Xats_as_con`, and every `v.Tag == N` test keep
working untouched, and xatsgo needs only layout MIRROR structs (an unsafe cast
needs the layout to agree, not the type identity — how ATS2's C runtime works
with generated tysum structs). Liveness check while prototyping: every
stream/list walker in xatsgo that consumed `.Args` is DEAD except
`strm_vt_forall0_f1un`; only `jshmap_search_opt` still constructs a con.

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

`dev.sh quick` (~55s, psuite 75/75 byte-equal vs the JS backend) per edit;
`bench` (`b04`/`b05`/`b08`/`b11`) as the allocation scoreboard; `bench/repr`
for representation-level questions; `dev.sh full-verify` before committing
anything that changes emission shape.
