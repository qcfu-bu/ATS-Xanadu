# Backend dev workflow (Go-centric emitter work)

The campaign: monomorphize to native Go types, unbox flat tuples/records, cut
`any`, and emit real per-constructor structs instead of the uniform
`XatsCon{Tag int; Args []any}`.

The premise that shapes this workflow: **the ATS frontend and middle-end are
not being touched.** Only `srcgen2/xats2go/srcgen2/DATS/go1emit_*` (the
emitter), `trxi0i1_*` (the lowering), and `runtime/xatsgo` change.

## The loop: ~1 minute

```
iterate.sh quick          # bundle relink (3-4s) + psuite (75 programs, ~50s)
iterate.sh quick bench    # + the 11-kernel perf suite vs Chez and JS
```

`psuite` emits each of 75 programs, builds them, runs them, and byte-compares
stdout against the **JS backend** running the same source. That is the right
judge for emitter work: a backend change is correct iff what it emits still
computes the same answers. Nothing here rebuilds the self-hosted compiler.

Single program while chasing one bug:

```
cd srcgen2/xats2go && make run/test61_list_sum_xats2go   # emit->build->run->diff
```

## What NOT to do per edit

Do **not** rebuild the selfhost binary on every emitter edit. That means
re-emitting 194 modules — ~55 minutes — and it answers a different question
("does the compiler still reproduce itself"), which is a milestone check, not
an edit check. The binary is also only ~1.1x faster than the node bundle, so
keeping it current buys no iteration speed.

## Milestone check: does the new backend still self-host?

```
iterate.sh selfcycle      # node-free: prewarm-self -> build -> fixpoint -> tests
iterate.sh full-verify    # same but emissions come from the bundle; sweep
                          # proves binary == JS-hosted bundle (the JS oracle)
```

Run one of these when a representation change is complete, not while it is in
progress. Expect **two bootstrap rounds** after an emitter change: round 1
emits the new emitter *source* using the old emitter *logic*, so the binary
built from it still emits differently; `selfcycle` iterates until stable.

## When a change has a narrow blast radius

Mtime invalidation is content-blind: relinking the bundle marks all 194
emissions stale even though a typical fix changes a handful. Measured blast
radius of real fixes from the fallback-removal campaign:

| change | modules whose emission contains the construct |
|---|---|
| TCO byref rebind | 2 / 194 (1.0%) |
| jshmap leaf typing | 5 / 194 (2.6%) |
| float64 coercer | 12 / 194 (6.2%) |
| return func-adapter | 14 / 194 (7.2%) |
| addr-of-field | 53 / 194 (27%) |

```
iterate.sh prewarm-touching 'Xats_p2tr' 3    # re-emit only matching modules
```

Measured: `prewarm-touching goxtco` = 2 re-emitted, 191 skipped, 42s (vs
~55 min). It is a heuristic; `fixpoint`/`sweep` re-emit everything and
byte-compare, so a miss turns the pre-commit verify red rather than shipping.

**The representation items (unboxed cons, per-constructor structs) change
essentially every emission**, so this shortcut will not apply to them — budget
a full pass for those milestones.

## Why the build is slow, and what actually fixes it

Measured on 18 cores / 48GB:

- Compiling one 293-line module allocates **~2.9 GB** over 107 GC cycles with
  ~190 MB live: ~94% of allocation is short-lived garbage.
- The compiler is therefore **memory-bandwidth bound, not CPU bound**. 8
  modules: 81s serial, 62s P2, **59s P3**, 73s P4, 111s P8. Past P3,
  parallelism is *worse than serial*. `-j` is not a lever; all defaults are 3.
- Per module: selfhost binary 8.7s vs node bundle 9.5s — only 1.1x apart,
  because both run the same allocation-bound algorithm.
- ~3.3s of every compile re-parses the same 424 prelude/SATS files: ~11 min
  per full build spent re-reading identical input (the interface-caching
  target).

So build speed comes from (1) not rebuilding what did not change, and (2)
making each compile cheaper. **The compiler is itself emitted Go**, so every
item in this campaign — fewer `any`, unboxed fields, real structs — reduces
that 2.9 GB and speeds up the build. The two goals are the same work.

## Perf regression harness

`bench/` holds 11 kernels compiled by both backends from one source, run
natively, byte-equal-checked. `b04_list`, `b08_bst`, `b10_queue`, `b11_tup`
are the allocation-dominated ones — the direct scoreboard for the
representation work. Today V8 beats Go on exactly those (bst 2.2x, tup 2.7x,
queue 3.9x) while Go wins compute kernels 2.6-5.6x; closing that gap is the
measurable goal.
