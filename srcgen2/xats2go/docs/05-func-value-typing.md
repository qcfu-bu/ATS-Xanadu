# Typing function values — design options (step-3 continuation)

*2026-08-27.  The last unaddressed population from the step-3 coercion
census: ~10k `func(any) any` / `func(any, any) any` values in the
self-hosted assembly.  This is a DESIGN note, not a landed change.*

## 1. Where the `any`-signatures come from, and what they cost

Every function that can FLOW AS A VALUE emits with an `any` signature:

- template-instance literals (hook values, the dominant class);
- lambdas / local closures assigned or passed;
- top-level functions referenced as values (`val f = g`).

Costs at run time: call-through asserts (`tmp.(func(any) any)(x)`), one
interface boxing per argument and result, and an inlining barrier (the
Go inliner will not devirtualize through the assert).  The coercing-param
prologue (03/04 docs, commits d081c2a68..186b41a55) already removed the
*callee-side* per-use cost — a typed signature would additionally remove
the *boundary* cost.

## 2. The constraint

Go function types are **invariant**: `func(*XatsCon) any` is not
assignable/assertable where `func(any) any` is expected.  A typed
signature is only sound if EVERY flow point agrees — direct calls,
value bindings, hook registrations, cross-module references, and the
`Xats_applyN` fallbacks.  A single missed flow is a runtime panic, not
a compile error, whenever the value crosses through `any`.

## 3. Options

**A. Adapter pairs.**  For a function whose params/result have concrete
Go types, emit the typed definition plus an `any`-adapter:

    func f_t(x *xatsgo.XatsCon) int { ... }
    var  f_5931 = func(x any) any { return f_t(xatsgo.Xats_as_con(x)) }

Known-callee call sites call `f_t` directly (full native boundary);
every VALUE reference emits the adapter.  Needs: a value-escape scan
(zzfv-style: any reference outside dapp-callee position), a naming
convention, and call-site routing.  Doubles the declaration count for
escaping functions.  This is the full win, at the highest complexity.

**B. Direct-call-only subset.**  Typed signatures ONLY for functions
that provably never escape as values (module-private, all references
are `I1Vfenv` callees).  Same escape scan as A, no adapters, no
call-site ambiguity.  Smaller win (escaping hooks — the biggest class —
are excluded by construction), much smaller blast radius.

**C. Do nothing further.**  The prologue already collapsed the per-use
callee-side cost to one conversion per call; the boundary boxing that
remains is the same cost the JS backend pays universally.  Revisit only
if profiling shows call-boundary boxing dominating.

## 4. Recommendation

B first (it is A's prerequisite anyway: the escape scan), measured on
the compiler self-compile before deciding whether A's adapters are
worth their complexity.  Profile first (`go build` + pprof on a
compiler-sized module) to size the actual boundary cost — the scalar
campaign's lesson (two measured null/negative results) is that this
codebase's coercion costs concentrate in fewer places than static
counts suggest.
