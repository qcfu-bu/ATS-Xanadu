# bench — emitted-code micro-benchmarks: Go backend vs Chez backend

Compares the RUNTIME performance of code emitted from the same ATS3 kernel
by the two backends, each on its own native CATS prelude arm:

- **Go** (CATS/GO arm): the runner swaps `prelude_JS_dats.hats` →
  `prelude_GO_dats.hats`, emits with `xats2go-selfhost --go-arm -o b.go`,
  splices the typed CATS/GO `.cats` floor into the module, `go build` →
  native binary (typed signatures, native infix, resolved-prelude bodies).
- **Chez** (JS arm — the surface its runtime implements): node-hosted
  `xats2cz-bundle` → Scheme body ++ `xats2cz_runtime.scm`
  → `chez (compile-file ...)` → `chez --script b.so` (precompiled native).

The `SRC/*.dats` keep the JS-arm include as written (they feed the Chez
side verbatim); the GO-arm variants are derived at build time.

Compile/build time is excluded on both sides; each timed run is a whole
process. `b00_null` reports the per-backend startup floor and the table
shows NET times (raw − floor), min of N reps (default 3).  Correctness:
Go stdout must be byte-equal to Chez stdout on every bench.

    bash run-bench.sh [reps]

Kernels (one checksum print each, sized for ≳0.1 s net on the faster side):

| bench     | exercises                                          |
|-----------|----------------------------------------------------|
| b01_fib   | non-tail recursion + int arith (fib 35)            |
| b02_tak   | deep 3-ary recursion (tak 27 18 9)                 |
| b03_loop  | tail-recursion/TCO, 1e9 iterations                 |
| b04_list  | datatype cons/alloc + match traversal (300k × 20)  |
| b05_tree  | tree alloc + two full traversals (depth 24)        |
| b06_hof   | closure-through-parameter calls (2e8 applies)      |
| b07_str   | string char indexing (49 chars × 3e6 scans)        |
| b08_bst   | persistent BST: 200k path-copying inserts + 10 sums|
| b09_msort | BOTTOM-UP mergesort, 1M list (runs + pass merging) |
| b10_queue | two-list functional queue, 2e6 enq/deq rounds      |
| b11_tup   | flat-tuple make/pass/project, 5e6 rounds           |

A third column runs the JS backend (xats2js — the oracle's reference
pipeline: emit + prelude/runtime concat, run on node).  Reference results
(M-series macOS, 2026-08; ratios > 1 = Go faster):

    bench           go-net(s) chez-net(s) js-net(s) chez/go js/go
    b00_null(startup)   0.018      0.045     0.059       -     -
    b01_fib             0.020      0.075     0.058    3.8x  2.9x
    b02_tak             0.011      0.035     0.029    3.2x  2.6x
    b03_loop            0.302      2.391       DNF    7.9x     -  (js: WRONG SUM)
    b04_list            0.058      1.771     0.169   30.5x  2.9x
    b05_tree            0.986      1.856     0.907    1.9x  0.9x
    b06_hof             0.119      0.588     0.663    4.9x  5.6x
    b07_str             0.091      0.730     0.175    8.0x  1.9x
    b08_bst             0.239      0.109     0.107    0.5x  0.4x
    b09_msort           1.128      7.465       DNF    6.6x     -  (js: RangeError)
    b10_queue           0.149      2.469     0.038   16.6x  0.3x
    b11_tup             0.073      0.032     0.027    0.4x  0.4x

JS-column DNFs are ARCHITECTURAL, not tuning:
- b03: the 1e9-sum accumulator exceeds 2^53 — JS sint is a double, so the
  result is silently WRONG (Go int64 and Chez fixnums stay exact).  The
  loop itself runs fine: the current js1emit DOES emit `while(true)` TCO.
- b09: RangeError at the ~1M-deep non-tail merge — V8's fixed stack cannot
  grow (Go's goroutine stacks and Chez's segmented stacks both absorb it).

Why (verified in the emitted artifacts):
- Go wins recursion/arith because the typed emission gives real
  `func fib(n int) int` with native operators — Go's optimizer then inlines
  the idempotent `Xats_as_*` coercions away (C-level speed on fib).
- The b04/b10 blowouts are the cz emitter's per-call `call/1cc` return
  protocol plus vector-tagged cons cells with per-field accessor lambdas —
  costly wherever `case+` traversal dominates.
- b07 is arm-sensitive: under the JS arm the Go side ran 1.805s (0.4x),
  because each character read went through the JS-model UTF-16-unit leaf
  (an interface-typed runtime call + cached []uint16 view).  The CATS/GO
  arm's typed floor indexes the host string directly and inlines: 20x
  faster, flipping the kernel to a 7.9x win.
- b08/b10/b11 are the honest counter-signal: ALLOCATION-RATE-dominated
  kernels favor the GC'd hosts — and V8 is the strongest of all there
  (best on bst/queue/tup: hidden-class objects + a nursery built for
  exactly this churn), while Go pays two heap objects per con.  A Go con is two heap objects (&XatsCon + its []any Args)
  with every scalar field boxed through `any`, and a flat tuple crossing a
  function boundary boxes into an interface; Chez allocates one vector of
  unboxed fixnums under a generational GC built for exactly this churn.
  Where traversal/compute dominates (b04, b05, b09, b10) Go still wins —
  the split is allocation-bound vs compute-bound, and it marks the next
  Go-emitter optimization target (unboxed scalar con fields).
