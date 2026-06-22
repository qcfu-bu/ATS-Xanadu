# Advanced surface — dependent (A), linear/view (B), proof (C)

> Workshop output (2026-06-21), lead-architect decisions applied. The syntax for the
> remaining specialist ATS features, to be implemented so it's READY when the canonical
> ATS3 constraint solver (future work; not yet built) lands. Until then these PARSE +
> LOWER + structurally typecheck (matching stock); index/proof obligations are not
> verified (no solver — same as stock). Consistent with the decorator principle
> (SURFACE-GRAMMAR §5.7.1) + the index surface already built (`SInt`/`SBool`, `Vec[A,n]`,
> `[n: SInt | g]` def-param quantifiers, `n+1` arithmetic).

## New keywords (the only 3 — genuine binders/relations, not decorator-izable)
`forall`, `exists`, `at`. Everything else is a decorator or operator.

## A — Dependent / static-type
```python
forall[n: SInt | g] (Vec[A, n]) -> SInt[n]   # explicit UNIVERSAL inside a type
exists[m: SInt | m <= n] Vec[A, m]            # EXISTENTIAL ("a Vec of some m")
@inst[Int, ..] foo(x, y, z)                    # explicit template INSTANTIATION (call site)
@sapp[Int, ..] foo(x, y, z)                    # explicit static `{...}` application (call site)
@sort type Nat = {a: SInt | a >= 0}            # SUBSET sort (refined; -> S2TEXsub)
@sort enum Tree: case Leaf / case Node(...)    # datasort (LOW PRIORITY — needs L1, no-op past trans12)
```
`def f[n: SInt | g](…)` stays the universal-param sugar (a `forall` wrapping the fn type).

### Generic vs template (the A distinction — decided 2026-06-21, refined)
TWO bracket positions, mirroring ATS's two binding sites — the `@template[…]` decorator carries the
TEMPLATE args, the `foo[…]` carries the POLYMORPHIC args. The same fn can carry BOTH:
```python
@template[A, B] def foo[C, D](x: A, y: C) -> D: ...
#         └ template args            └ polymorphic args
```
lowers to `extern fun{A,B} foo{C,D}(x:A, y:C): D` (+ `implement{A,B}{C,D} foo … = …`).
- **`@template[A, B]`** → the `fun{A,B}` template args (BEFORE the name) → MONOMORPHIZED (one
  specialized copy per instantiation), MAY be flat. Sort default `t@ype` (flat-capable) — this is
  exactly where an unboxed param belongs. Overload-by-type lives here.
- **`foo[C, D]`** → the `{C,D}` universal quantifier IN the fn type (`tqas` on `D2Cfundclst`, what
  we lower TODAY) → POLYMORPHIC (one type-erased instance per template-instantiation), BOXED. Sort
  default `type`.
- Both sort defaults overridable (`@template[A: Linear]`, `foo[C: Type]`).
- The three cases: `def foo[C](…)` = pure polymorphic (DEFAULT, no decorator); `@template[A] def foo(…)`
  = pure template; `@template[A] def foo[C](…)` = both.

ALL THREE template operations use the SAME shape — a decorator whose `[…]` carries the type-args:
| operation | surface | ATS |
|---|---|---|
| declare | `@template[A, B] def foo[C, D](…)` | `extern fun{A,B} foo{C,D}(…)` |
| implement | `@impl[Int, Bool] def foo[C, D](…) = …` | `implement{Int,Bool} foo{C,D}(…) = …` |
| instantiate (call) | `@inst[Int, ..] foo(x, y, z)` | `foo<Int,..>(x, y, z)` |
| static apply (call) | `@sapp[C, D] foo(x, y, z)` | `foo{C,D}(x, y, z)` |
- `@impl[…]` is our EXISTING `@impl` (plain implement → `D2Cimplmnt0`) PLUS a template-arg
  instantiation list — bare `@impl def` (no brackets) stays the non-template implement.
- `@inst[Int, ..] foo(x, y, z)` instantiates the TEMPLATE bracket (→ ATS `foo<Int,..>(…)`); the
  polymorphic `[C,D]` bracket is inferred from the value, as polymorphic args always are. No `<>`
  angle-brackets anywhere on the surface.
- `@sapp[C, D] foo(x, y, z)` is the explicit static `{C,D}` call-site application. Pyprint uses it
  when stock ATS code carries explicit or reconstructed static arguments, for example
  `topmap_make_nil{itm}()`.
- BODY rule: an inline body on `@template[…] def foo(…): <body>` IS its generic implementation
  (declare + implement in one shot, like ATS `fn{a} foo(x) = body`). A BODYLESS `@template[…] def
  foo(…)` is declaration-only (→ `extern fun{…}`) and takes its bodies from separate `@impl[…]`s.
- The TEMPLATE mechanism (`@template[…]` → `fun{…}` template args, `@impl[…]` → `implement{…}`,
  `@inst[…]` → `<…>` instantiation; `$`-implicit / `trtmp` L3 resolution) is NEW — needs a SPIKE
  (A-template). The polymorphic `foo[…]` half is the `tqas` we already lower.

## B — Linear / view / pointer
```python
pf: A at l                       # AT-VIEW (keyword `at` — @ stays decorators-only). `view` sort reserved.
case ~VCons(x, rest): ...        # LINEAR CONSUME pattern (~p = free). (`!p` unfold; `@p` flat -> defer/~~p)
&x                               # ADDRESS-OF
!p                               # DEREFERENCE (in expr position; `!p` in a pattern = unfold)
x :=> y                          # MOVE (consume y into x)
x :=: y                          # SWAP
```

## C — Proof
```python
@terminates[n]                   # TERMINATION METRIC (totality) — decorator
def fact[n: SInt](k: SInt[n]) -> SInt: ...

@with[pf: LE(m, n)]              # WITHTYPE (proof-augmented) — decorator
case Node(...)

case VCons{n}(x, rest): ...      # EXISTENTIAL-UNPACK pattern ({n} binds the hidden index)
```

## L2 targets (recipe basis)
- forall/exists → `s2exp_uni0`/`s2exp_exi0(s2vs, s2ps, body)` (the dep-spike P2/P3 proved uni0).
- subset sort → `D2Csortdef(sym, S2TEXsub(s2v, s2ps))` (staexp1.sats S1TDFtsub).
- templates → the `t1qag`/`s1qag` template mechanism + `trtmp` (L3) — SPIKE.
- at-view → `S2Eatx2` / the view sort `the_sort2_view` + an at-view s2exp.
- linear patterns → `D2Pfree`/`D2Pbang`/`D2Pflat` (dynexp2.sats:731-733).
- &/! → `D2Eaddr` / `D2Eeval`/`D3Edp2tr`; swap → `D2Exchng`; move → `D2Exazgn`.
- @terminates → `F2ARGmets`/`S2Emet0`; @with → `withtype` (`wd1eclseq`); {n} unpack → `D2Psapp`.

## Build order
1. **A-quant** (forall/exists + existentials + subset sorts) — extends the proven index/guard lowering.
2. **A-template** (`@template` + `foo<Int>`) — SPIKE the template mechanism first.
3. **C** (`@terminates`/`@with` decorators + `{n}` unpack) — small, decorator-driven; quick L2 spikes.
4. **B** (at-views, linear patterns, `&`/`!`/swap) — most specialist; spike the view/linear L2.
