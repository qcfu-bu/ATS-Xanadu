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

Reference results (M-series macOS, 2026-08; chez/go > 1 = Go faster):

    bench           go-net(s) chez-net(s) chez/go
    b00_null(startup)   0.016      0.040      -
    b01_fib             0.019      0.077    4.1x
    b02_tak             0.010      0.033    3.3x
    b03_loop            0.292      2.311    7.9x
    b04_list            0.060      1.688   28.1x
    b05_tree            0.966      1.808    1.9x
    b06_hof             0.126      0.589    4.7x
    b07_str             0.092      0.729    7.9x

Why (verified in the emitted artifacts):
- Go wins recursion/arith because the typed emission gives real
  `func fib(n int) int` with native operators — Go's optimizer then inlines
  the idempotent `Xats_as_*` coercions away (C-level speed on fib).
- The b04 blowout is the cz emitter's per-call `call/1cc` return protocol
  plus vector-tagged cons cells with per-field accessor lambdas — costly in
  a 120M-node traversal.
- b07 is arm-sensitive: under the JS arm the Go side ran 1.805s (0.4x —
  the ONE loss), because each character read went through the JS-model
  UTF-16-unit leaf (an interface-typed runtime call + cached []uint16
  view).  The CATS/GO arm's typed floor indexes the host string directly
  and inlines: 20x faster, flipping the kernel to a 7.9x win.
