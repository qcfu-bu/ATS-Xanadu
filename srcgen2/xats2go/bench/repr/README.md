# repr — datatype representation microbenchmark

Standalone Go benchmark behind the decision in
`docs/11-datatype-representation.md`. Three representations of
`datatype mylist = mynil | mycons of (payload, mylist)`, built (300k cons)
and traversed:

- **A** — today: one universal `ConA{Tag int; Args []any; Name string}` with
  the inline arity buffer.
- **B** — per-ctor struct embedding a `{Tag int}` header; handle stays
  `*Hdr`; projection via `unsafe.Pointer` cast.
- **C** — per-datatype interface; one struct per constructor; match by type
  switch. **(the chosen design)**

`r_test.go` uses an `int` payload (unboxing possible). `p_test.go` uses a
polymorphic `any` payload — the compiler's dominant case, since 51.4% of its
field accesses are on fields whose type is unrecoverable — and so isolates
the CONTAINER win from the unboxing win.

    go test -bench=. -benchmem -run='^$'

Reference results (M-series macOS, 2026-08; 300k-cons list):

    payload      case      A (today)          C (interface)      gain
    int          build     9.17ms  600k alloc  4.69ms 300k alloc  2.0x, half the allocs
    int          traverse  630us               271us              2.3x
    any (poly)   build     8.22ms  28.8MB      5.17ms  9.6MB      1.6x, 3x less memory
    any (poly)   traverse  593us               305us              1.9x

B vs C (unsafe cast vs interface): within 4% on build, C ~19% slower on
traversal. That 19% is the price of type safety and no `unsafe`; the compiler
is allocation-bound rather than traversal-bound, and the container win
(1.6-3x) dominates it.

Note the `int` build does TWO allocations per cons under A: the container and
the boxed payload (Go heap-boxes ints >= 256). Unboxing removes one of them.
