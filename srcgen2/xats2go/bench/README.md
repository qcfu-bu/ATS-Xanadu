# bench — emitted-code micro-benchmarks: Go backend vs Chez backend

Compares the RUNTIME performance of code emitted from the SAME ATS3 source
by the two backends:

- **Go**: `xats2go-selfhost -o b.go b.dats` → `go build` → native binary
  (the post-fallback-removal emitter: typed function signatures, native
  infix operators, resolved-prelude bodies).
- **Chez**: node-hosted `xats2cz-bundle` → Scheme body ++ `xats2cz_runtime.scm`
  → `chez (compile-file ...)` → `chez --script b.so` (precompiled native).

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

Reference results (M-series macOS, 2026-08; chez/go > 1 = Go faster):

    bench           go-net(s) chez-net(s) chez/go
    b00_null(startup)   0.017      0.041      -
    b01_fib             0.019      0.076    4.0x
    b02_tak             0.009      0.034    3.8x
    b03_loop            0.295      2.384    8.1x
    b04_list            0.060      1.671   27.9x
    b05_tree            0.962      1.816    1.9x
    b06_hof             0.126      0.588    4.7x
    b07_str             1.805      0.734    0.4x   (Chez faster)

Why (verified in the emitted artifacts):
- Go wins recursion/arith because the typed emission gives real
  `func fib(n int) int` with native operators — Go's optimizer then inlines
  the idempotent `Xats_as_*` coercions away (C-level speed on fib).
- The b04 blowout is the cz emitter's per-call `call/1cc` return protocol
  plus vector-tagged cons cells with per-field accessor lambdas — costly in
  a 120M-node traversal.
- b07 is the one Go loss: `strn_get_at` mirrors the JS UTF-16 unit model
  through the runtime's cached `[]uint16` view, an interface-typed leaf call
  per character; the cz runtime indexes host strings directly.
