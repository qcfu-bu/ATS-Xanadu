# xats2go — status summary (for review)

*2026-08-27.  Follow-up to the template-resolution review; companion to
`03-template-resolution.md` (the full resolver story).*

## 1. Template resolution: the pristine model, adopted

All ad-hoc "re-resolution" machinery is **removed** (the emitter-side
`f0_timp` re-resolution, in-place concrete-instance resolution, the
`zzprefer0` preference hack, `D3Cerrck` recursion).  Resolution is now
exactly the copy-per-instantiation model: each use site copies the impl
body, inner templates resolve recursively in the instantiation scope, no
sharing of resolved bodies across sites at the semantic level.

The residual undefined leaves (`g_stdout`, `fprint_ref`'s `g_print$out`
hook, …) were a single **emitter** defect in three sightings: raw
registered hook bodies were emitted as dead `tmpw` workers instead of
their resolved instances.  Worker emission is now gated to compiler
package source only.

The **GO arm of libcats** is constructed
(`srcgen1/xatslib/libcats/DATS/CATS/GO/libcats.dats`, analog of the
NODE/PY arms), included via a `_XATS2GO_` overlay in `xatsopt_dpre.hats`.

## 2. An instance cache that preserves the model

Copy-per-instantiation is semantically right and quadratically expensive
in emitted code.  The backend adds a cache in `trtmp3c` that memoizes an
instantiation **only when it is observationally identical to the copy
the pristine resolver would make**:

- the cache key is the chosen impl's stamp plus template-argument
  equality;
- each entry records the transitive set of template constants its
  resolution consulted; registering a new top-level impl for any of
  them **purges** the affected entries (a later `#impltmp` override is
  never shadowed by a stale copy);
- an instantiation inside any local scope frame (svts / let / local) is
  never cached (local hook overrides stay per-site);
- every attached body gets a **fresh instance stamp**, so downstream
  passes still see distinct instances.

About 40% of instantiation walks hit the cache on compiler-sized
modules.  The emitter additionally lifts capture-free instance bodies to
named package-level functions (one definition, N references).  Combined
effect: the self-hosted assembly's default-optimization object went
**5.2 GB → 1.74 GB**, which put the Go inliner back in play.

## 3. Faithfulness and typing

The value model is unchanged and faithful: datatypes are the uniform
boxed `*xatsgo.XatsCon{Tag, Args}`; genuine polymorphism stays `any`.
What changed is how much the emitter *knows*: temps minted by the
lowering now carry their Go-relevant type (including inside resolved
instance bodies, where template variables resolve through the
instance's substitution), so the emitted code declares concrete types
where the frontend proves them and coerces **once per binding** instead
of once per use.  Runtime coercion sites in the largest emitted package
dropped ~30%.  Function signatures deliberately stay `func(any...)`:
functions flow as template-hook values, and Go's function types are
invariant.

## 4. Verification

Everything above is gated by the standing ladder, all green:

- **sweep**: 193 compiler-source modules, self-hosted binary emission
  byte-equal to the reference bundle's;
- **psuite**: 75 programs, output byte-equal vs the JS backend (the
  differential oracle);
- **selfhost probe**: the Go-built compiler front-ends a compiler
  module end-to-end (0 errors);
- **leaf census**: the runtime's CATS-leaf surface is pinned; prelude
  and library semantics come from compiled ATS source, the runtime
  supplies leaves only.
