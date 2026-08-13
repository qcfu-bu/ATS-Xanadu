# Self-hosting status: Go-hosted, rung-verified; self-compile NOT yet reached

_Updated 2026-08-12.  Supersedes the nerror=86 investigation this file
previously documented (that bug — module-init effects stripped by
assemble.sh — and its successors are fixed; see the branch log)._

## What is PROVEN

The full compiler pipeline (frontend + go1emit, 194 modules: 18 emitter +
162 frontend + 13 xats2cc + the CLI driver), compiled to Go by the
JS-bootstrapped bundle, builds into a working native binary
(`selfhost-build/src/xats2go-selfhost`) that compiles ATS3 **user
programs** with output **byte-identical** to the bundle:

- **All 12 go-arm rungs byte-equal** to the bundle's emission, invoked
  identically (same relative test path — the path text is embedded in
  location comments).  Since the gate compiles + runs each reference
  emission against its golden, byte-equality transitively proves the
  self-emitted Go builds and runs correctly.
- Every fix that got here stayed gated: 12/12 rungs + psuite 75/75.

The closing fixes (see commit c75fc09d7 and its predecessors): byref
params for inline template-instance literals, reflective flat-tuple
repack (arg boundary + datacon-field projections), lazy group streams,
int-aware `g_parse`, the sort2 `g_lte` hook, stdout write/print channel
unification (`xatsStoreWriter`), the digit-guarded namespace sed, the
trtmp3b/c concrete-instance body resolution, and the single-arg `print`
rewrites in `locinfo_print0` + the two excptcon-Name emitter sites.

## What is NOT yet reached: the self-compile fixpoint

**The binary cannot yet compile its own sources.**  Sweeping all 194
assemble.sh modules through it (2026-08-12): the frontend raises
`F3PERR0-ERROR`s on most compiler-scale modules and the erroring decls
are errck-erased, so the emissions collapse to header stubs
(`trans2a_utils0`: 10 lines vs the bundle's 9,856).  Failing-module
error counts range from 1 (`xsynoug`, a 46-line staload-only module —
the best entry probe) to ~43 (`trans2a_utils0`).  These are fidelity
bugs in the binary (the same ATS3 frontend compiled via jsemit00
compiles every module clean) on paths that rung-scale programs never
exercise.  Prime suspects: the ~81 bridged `g_eq` sites (runtime
`reflect.DeepEqual` vs the frontend's semantic/identity equality;
DeepEqual over closure-bearing payloads is always-false) and other
unexercised runtime bridges.

Benchmark note (P=3, warm NODE_COMPILE_CACHE): the bundle's real
self-compile cost is 834s for the 194-module sweep; the binary's 24s is
NOT comparable (it bailed early on the errors).  On the verified-equal
rung workload both are ~1s/compile (startup-dominated).

## Known resolver limitation (worked around, not fixed)

srcgen1-prelude's `gs_print_nN` defaults are ALIAS-form template impls
with a QUANTIFIED hook impl (`gs_print_nN = gs_fproc_nN<..> where {
#impltmp {a0:t0} g_fproc<a0> = g_print<a0> }`), which trtmp3b/c cannot
instantiate.  Multi-arg `prints(...)` therefore bridges to the runtime —
fine for scalar args, WRONG for constructor args (generic printer).
Workaround pattern (byte-identical output): rewrite as SEQUENCED
single-arg `print(x)`, which resolves per-value through the
`xatsopt_tmplib` `g_print<T>` instances.  Applied so far:
`locinfo_print0` (lcsrc/postn/loctn_fprint), go1emit's two excptcon-Name
sites, and the three `F3PERR0-ERROR` reporters (f3perr0_decl00 :300,
f3perr0_dynexp :258/:1056) — the reporters previously printed their
location + payload as `list()`, leaving the diagnostics MUTE.

## The campaign to the fixpoint

1. Un-mute diagnostics (the reporter rewrite above) — DONE in source.
2. Probe `xsynoug` (1 error), read the real error text, fix the runtime/
   emitter/frontend gap it names; regate (12 rungs + psuite).
3. March up the failing-module list; finish line = all 194 modules emit
   with 0 F3PERR errors AND byte-match the bundle's `emit/*.go`
   (invoked with the same paths assemble.sh uses).
4. Then generation 2: assemble from self-produced sources, `go build`,
   verify the gen-2 binary reproduces gen-1's outputs.
