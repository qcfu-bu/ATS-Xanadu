# Self-hosting status: binary runs; one elaborator-fidelity bug remains

## Milestone reached (build48)

The full ATS2/Xanadu compiler, transpiled to Go through `xats2go`, now
**compiles cleanly and runs end-to-end**:

- `selfhost-build/assemble.sh` + `wire-driver.sh` assemble **194 modules**
  (18 emitter + 162 frontend + 13 xats2cc D3->intrep0 + the CLI driver)
  into one Go package.
- `go build` produces a working **11.8 MB `xats2go-selfhost` binary**
  with **zero build errors** (down from 2,383 error lines at the start).
- The binary runs the **complete frontend pipeline** on real input —
  lexing, parsing, fixity resolution, the trans12 preload, the whole
  D0->D1->D2->D3 elaboration, and the tread/trtmp template-resolution
  passes — to completion (exit 0), reaching `i1parsed_go1emit`.

Every fix stayed **gated**: 12/12 go-arm rungs byte-equal against goldens
and the 75-test JS-oracle psuite green.

Reaching this took ~9 runtime-gap iterations after the build hit zero:
Go initialization order (module globals emitted as IIFE var initializers,
not `func init()`), nullary-instance thunk peeling, lazy call-by-name
streams (`strn_strmize`/`strx_vt_map0`/`strm_vt_map0`), `strn_head$opt`
returning the head rune, and worker-forwarding bridges
(`map$fopr0`, `iforitm$work`, `gseq_foritm`, the `foritm$e1nv$work`
default hook, `list_make_fwork`).

## The remaining bug (blocks byte-matching emission)

Running the binary on `test_goarm01_xats2go.dats --go-arm`:

- **JS bootstrap bundle** (same driver, same input): `nerror = 0`, emits
  valid Go between the `//==XATS2GO-BEGIN==` sentinels (150 lines).
- **Self-hosted Go binary**: `nerror = 86`, emits **no** sentinels — the
  86 errors degrade the intrep0 lowering so `i1parsed_go1emit` produces
  nothing.

### Precisely localized

Instrumenting `d3parsed_get_nerror` after each driver pass:

```
NERR fildats 86      <- all 86 created here
NERR tread3a 86      <- adds none
NERR trtmp3b 86      <- adds none
NERR trtmp3c 86      <- adds none
NERR t3read0 86      <- adds none
```

So **every one of the 86 errors is created inside `d3parsed_of_fildats`**
(the core parse + D0->D1->D2->D3 elaboration). None of the post-processing
tread/trtmp passes contribute — confirmed separately by instrumenting the
tread3a errck constructors (`d3exp_errck`/`d3pat_errck`/`d3ecl_errck`),
none of which fire.

### What the errors are

Decoding the `D3Eerrck` nodes (the generic runtime formatter renders any
XatsCon as `list(...)`, so this needed a reflection dump):

```
F3PERR0-ERROR:
  #0(#1("...test_goarm01_xats2go.dats"),#0(3,3,0),#0(3,3,0))   <- location
  :#0(...,#21(1,#0(#0(loc,#20(...)))))                          <- errck node
```

All 86 are **identical**: a **level-1** `D3Eerrck` wrapping a **dynamic
application** node (`D3Edapp`=tag21 / `D3Edap0`=tag20), at a **synthetic /
lost location** (line 3 — the file's comment header — with zero-width
offsets, i.e. the default location assigned when the real origin is lost).

### Traced through the pass chain

`nerror` is a **field** on the parsed structure, read by
`d3parsed_get_nerror`, and each later pass **preserves** it:

- `d3parsed_of_trans3a`/`tread3a`/`trtmp3b`/`trtmp3c`/`t3read0` all carry
  `nerror` forward unchanged (verified: none of the D3-level
  `d3exp_errck`/`dapp_errck`/`dap0_errck` builder copies — in
  `tread3a`/`tread23`/`trans3a` — fire during the run; the only Tag-63
  `D3Eerrck` node constructions in the assembly are those 3 builders,
  and they are never called).
- So the count is already 86 when `d3parsed_of_fildats` returns, carried
  through `trans23` (D2->D3) from the `d2parsed`'s `nerror`, which comes
  from **`trans2a` (D1->D2)**.

The 86 is therefore the **D1->D2 type-checking error count**: `trans2a`
increments it while elaborating the go-arm application/template
instantiations, and it rides the field verbatim to the end where
`f3perr0` walks the tree and prints the errck-wrapped application nodes.

### Interpretation

The Go-compiled **application-elaboration** path (overload resolution /
template instantiation / application type-inference in the D2->D3 stage:
`trans2a` / `trsym2b` / `t2read0` / `trans3a`) produces level-1 errck-
wrapped dynamic-application nodes that the JS-interpreted elaborator
resolves cleanly. The go-arm test's applications are exactly
`sint_print(42)`, `the_print_store_log()`, `sint_add$sint(100,23)` — the
prelude template calls that go-arm is meant to emit; JS elaborates them to
resolved D3Edapp, Go leaves them errck'd.

This is the same *class* as the F3PERR0-TIMQ template-resolution work
(tasks #12/#13) but now surfacing **inside the self-hosted binary's own
elaborator**, i.e. a Go-vs-JS fidelity gap in how one of the D2->D3
elaboration functions was compiled.

## Next step

The origin is **`trans2a` (D1->D2 type-checking)** — it increments the
`nerror` field 86 times while elaborating the go-arm applications. Find
where `trans2a` bumps the error count (the D1->D2 overload/application
type-inference that fails in Go but resolves in JS) and fix the diverging
function at the ATS source.

Fast-iteration setup: the binary rebuilds locally in ~1 min (`go build`
in `selfhost-build/src`, no bundle/reassembly), so instrument the
generated `emitter_all.go` directly to probe. Confirmed-useful probes:
`d3parsed_get_nerror` after each driver pass (localizes the pass);
reflection-dumping `D3Eerrck` nodes (the generic runtime formatter renders
XatsCon as `list(...)`, so a Tag/arg dump is needed to read them). Only an
**emitter** source change needs the ~95-min bundle+reassembly cycle; a
runtime-only fix is a ~1-min binary rebuild.
