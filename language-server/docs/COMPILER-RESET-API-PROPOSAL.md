# Proposal: a reset / reload API for ATS3-Xanadu (compiler re-entrancy)

> **Status:** proposal only — **requires Hongwei's approval** before any `srcgen2/` change.
> Scoped out of the ATS3 LSP work (it would otherwise need a separate, sandboxed effort).
> This document is meant to be shareable with Hongwei as an upstream-enhancement proposal.

## Problem

The compiler is **strictly one-shot**: it correctly type-checks one file per process, then must
exit. There is **no reset/clear/init API** anywhere (repo-wide grep for `_reset`/`_clear`/`_init0`
finds nothing). Global mutable state accumulates and is never cleared, so a second run in the same
process sees the first run's state (the prelude *and* the first file's top-level definitions) as
if it were the environment. (Primer §4, §12.)

This forces every re-entrant tool to **spawn a fresh process per check** — paying full node
startup + bundle parse + **prelude reload (~0.3 s)** every time. It also makes **in-process
prelude reload impossible**, so an LSP whose workspace *is* the prelude can only refresh by
restarting (see LSP plan §R2, "workspace IS the prelude").

A reset API would benefit the compiler **broadly**, not just the LSP: re-entrant batch checkers,
test harnesses that check many files in one process, a future REPL/interpreter, and any
long-running analysis tool.

## Goal

Add a small API to `xglobal` (+ helpers in the modules that own state) that returns the compiler
to a clean state in-process, enabling repeated, isolated runs without restarting.

## Inventory of global mutable state to clear

(From the LSP research; anchors are hints — re-grep to confirm.)

| Store | Where | Notes |
|---|---|---|
| Stamp counters | `xstamp0.dats` (`stamper_getinc`); per-module `mytmper` in `xsymbol.dats`, `staexp2.dats`, `statyp2.dats`, `dynexp2.dats`, `dynexp3.dats`, `trtmp3b/3c_myenv0.dats` | monotonic `a0ref(uint)`; `stamper_tmpset` already exists (only a test calls it) |
| Symbol intern tables | `xsymbol_mymap0.dats` (`_MYMAP_` name→symbol), `xsymbol.dats` (`the_xsymbls` stamp→symbol) | append-only; arguably safe to keep, but unbounded growth |
| Global envs | `xglobal.dats`: `the_fxtyenv`, `the_gmacenv`, `the_sortenv`/`the_sexpenv`/`the_dexpenv`, `the_d2cstmap` | accumulate top-level defs (prelude + user) |
| Per-file caches | `xglobal.dats`: `the_d1parenv`, `the_d2parenv`, `the_d3parenv`, `the_d3tmpenv` | keyed by `fnm2`; already individually evictable via the LSP's `env_reset` |
| Prelude load gates | `xglobal.dats`: `the_ntime` counters | make `the_fxtyenv_pvsload`/`the_tr12env_pvsl00d` load-once; **must reset to re-run prelude** |
| Dir-path stack | `filpath_drpth0.dats` | push/pop; can leak on error paths |
| Lazy memo caches | `staexp2_inits0.dats`, `statyp2_inits0.dats` | `a0ref` caches of pointers **into** `the_sexpenv` — must be invalidated on reset or they dangle |

## Proposed API (two tiers)

**Tier 1 — full reset (simpler; ship first).**
```
fun xglobal_reset_all((*void*)): void
```
Clears every store above to its pristine (pre-prelude) value and resets `the_ntime` gates to 0.
Caller then re-runs `the_fxtyenv_pvsload()` / `the_tr12env_pvsl00d()` to reload the prelude.
- Unblocks: **in-process prelude reload** (no LSP restart); a guaranteed-clean (cold) re-check.
- Most stores are `a0ref`-backed → reassign to empty; maps → clear; stampers → `tmpset` to a base;
  **invalidate the `*_inits0` lazy caches** (or they point into a freed env).

**Tier 2 — checkpoint / restore (higher value, harder; evaluate after Tier 1).**
```
fun xglobal_checkpoint((*void*)): void   // snapshot state right AFTER prelude load
fun xglobal_restore((*void*)): void      // roll back to that snapshot
```
Rolls back only the **user-file** accumulations while keeping the warm prelude. This is the prize
for the resident LSP: **clean *and* fast per-file re-checks** (no prelude reload, no cross-file
contamination). Requires the envs/stampers to support a checkpoint (e.g., record sizes/marks and
truncate, or layer user defs in a removable scope).

## Testing
- check A → `reset_all` → reload prelude → check B; assert B sees **none** of A's top-level defs.
- load prelude → edit a prelude file → `reset_all` → reload; assert the edit is reflected.
- check the same file twice (with reset between); assert **identical** diagnostics (idempotent).
- (Tier 2) `checkpoint` after prelude → check A → `restore` → check A again; identical results, and
  the prelude was not reloaded.

## Risks / notes
- Invasive, compiler-internal; **needs Hongwei's sign-off** and careful review of every `a0ref`
  owner. The lazy `*_inits0` caches are the most error-prone (dangling-pointer risk).
- Tier 1 alone already removes the need to restart for prelude reload and gives correct cold
  re-checks; recommend landing it first and measuring before attempting Tier 2.
- If accepted, the LSP could **drop process-per-check entirely** and unify on the resident model,
  and R2's "workspace IS the prelude" special-case collapses to a normal invalidation.
