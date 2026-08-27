# Backend dev workflow (Go-centric emitter work)

The campaign: monomorphize to native Go types, unbox flat tuples/records, cut
`any`, and emit real per-constructor structs instead of the uniform
`XatsCon{Tag int; Args []any}`.

The premise that shapes this workflow: **the ATS frontend and middle-end are
not being touched.** Only `srcgen2/xats2go/srcgen2/DATS/go1emit_*` (the
emitter), `trxi0i1_*` (the lowering), and `runtime/xatsgo` change.

## The loop: ~1 minute

```
dev.sh quick          # bundle relink (3-4s) + psuite (75 programs, ~50s)
dev.sh quick bench    # + the 11-kernel perf suite vs Chez and JS
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
dev.sh selfcycle      # node-free: prewarm-self -> build -> fixpoint -> tests
dev.sh full-verify    # same but emissions come from the bundle; sweep
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
dev.sh prewarm-touching 'Xats_p2tr' 3    # re-emit only matching modules
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

## Harness blind spot: `regress` compares us against ourselves

`dev.sh regress` runs each `tests/*.dats` probe through **the selfhost
binary and our own patched bundle**, then demands byte-equal output. That
pins binary-vs-bundle *fixpoint* fidelity — but both sides are built from the
same sources, so a behaviour missing from **both** is invisible to it.

That is exactly how the parse-error gap survived: `xats2go_goemit01.dats`
called `d3parsed_of_fildats(fpth)`, which is

    d3parsed_of_trans03(d0parsed_of_pread00(d0parsed_from_fpath(1, fpth)))

The `d0parsed` threaded through it carries the parse-error count, and
`d0parsed_fpemsg` (pread00.sats:515, defined pread00.dats:141) prints those
as `PREAD00-ERROR`. **Nothing in srcgen2 calls it** — not our driver, not
xats2js's. So the value was built, consumed by trans03, and the parse-level
report was never produced. Both sides agreed, and regress stayed green.

The only oracle that caught it is the prebuilt **xats2js asset**:

    xassets/JS/xats2js/xats2js_jsemit01_ats3_opt1.js

It predates this tree and still calls all four reporters. On a
malformed-pattern probe it prints PREAD00 / TREAD01 / F2PERR0 / F3PERR0;
we printed F3PERR0 alone.

**Rule of thumb: when the question is "do we report X at all?", regress
cannot answer it — diff against the xassets JS reference instead.**

Two things worth knowing about the four reporters:

- They are **not** four independent error sets. On a malformed-pattern probe
  TREAD01/F2PERR0/F3PERR0 flag the *same three spans*, at 2x/4x/6x
  multiplicity — the same errors re-reported as the tree is lowered. So
  F3PERR0 alone loses no *location*; what it loses is the **classification**
  (parse error vs type error), which is precisely what an LSP needs.
- A parse error still reaches level 3 as a `D3Cerrck` node, so this was a
  *reporting* gap, not a *detection* gap. Nothing was ever silently accepted.

`tests/err04_badpat.dats` is the probe that goes red if the parse-level
reporter is unwired again. Note it can only catch a *divergence* between
binary and bundle — re-check against the xassets asset when touching the
driver's phase sequencing.
