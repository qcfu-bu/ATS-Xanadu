# L2-DIFF — proving the Pythonic-ATS round-trip is FAITHFUL by structural L2 compare

The existing round-trip gate (`build-pp.sh` / `build-pp-dyn.sh`) only checks that the
pretty-printed pythonic **typechecks** (`nerror == 0`). That is weak: a file can
typecheck while lowering to a *different* L2 than stock would. This harness is the
much stronger automated form of the by-hand "diff our L2 vs stock" that has found
every fidelity bug: for a source file `F` it compares the **raw lowered L2** two ways
and reports whether they are structurally identical.

```
  stock L2    = trans02_from_fpath(stadyn, F)                  -- the STOCK compiler
  pythonic L2 = pyfront_d2parsed_of_fpath(stadyn, pyprint(F))  -- OUR frontend, from
                                                                  the pretty-printed pythonic
```

If the two normalized dumps are identical, the round-trip is provably faithful — both
`pyprint` AND our lowering. If they differ, the diff pinpoints the exact diverging
construct.

We compare the **raw d2parsed BEFORE the post-passes** (`tread12` / `trans2a` /
`trsym2b` / `t2read0`), because that is exactly what our lowering produces and what we
want to validate. `trans02_from_fpath` (trans12.sats:1126) is the stock raw-L2 entry
(parse + trans01 + trans12); `pyfront_d2parsed_of_fpath` (pyfront_m3.sats) is our raw-L2
entry — the same one the M3 pipeline lowers to **before** its `_d3parsed_` post-passes.
If the raw L2 matches, everything downstream matches.

## Pieces

| file | role |
|------|------|
| `frontend/DATS/pyfront_l2dump.dats` | the driver: two modes (`stock`, `pyfront`), each prints `d2parsed_fprint(...)` of the raw L2 |
| `frontend/CATS/pyfront_l2dump.cats` | tiny FFI glue (argv + readfile + stderr log) |
| `frontend/build-l2dump.sh` | transpile + link the driver into `BUILD/pyfront-l2dump.js` |
| `frontend/build-l2diff.sh` | the wrapper: pyprint → dump twice → normalize → diff (exit 0 = faithful) |
| `frontend/TEST/l2diff/lets.dats` | the FAITHFUL fixture (`val a=7; val b=a; val c=b`) used to validate zero-diff |
| `frontend/TEST/l2diff/mini.sats` | a DIVERGENCE fixture (`datatype color = Red | Green | Blue`) |

### The serializer

Both sides serialize with the SAME printer, **`d2parsed_fprint`** (dynexp2.sats:1945),
which unconditionally dumps the full node tree
`D2PARSED(stadyn;nerror;source;parsed)` where `parsed` recursively prints every
`D2C.../D2E.../D2P.../S2E...` node and prints d2con/d2cst/d2var as `name(STAMP)` /
`name[STAMP]`. We deliberately do **not** use `f2perr0_d2parsed` (the function named in
the brief): that one only emits anything when `nerror>0` (f2perr0.dats:103), so a clean
file would print nothing. `d2parsed_fprint` is the unconditional structural serializer
and is the alternative the brief lists.

### Why the driver re-implements `pyfront_d2parsed_of_fpath`

The lowering entry lives in `pyfront_m3.dats`, but that file ends in
`val ((*entry*)) = mymain_m3()` and its `main` runs the xats2js **codegen** backend
(`i0parsed_of_trxd3i0` …) which we do not bundle. So instead of linking
`pyfront_m3.dats` (which would execute its codegen main and crash), the L2DUMP driver
re-implements `pyfront_d2parsed_of_fpath` with a body **identical** to
`pyfront_m3.dats:88`, and does not link the M3 driver. The M3 pipeline itself is
untouched.

## Usage

```bash
export XATSHOME=/Users/qcfu/Projects/ATS-Xanadu

# one-time: build the dumper (no backend libs; reuses srcgen2/lib/lib2xatsopt.js)
bash frontend/build-l2dump.sh

# pyprint-driven compare (needs BUILD/pp.js or BUILD/pp-dyn.js from build-pp[-dyn].sh):
bash frontend/build-l2diff.sh srcgen2/SATS/xstamp0.sats 0       # static .sats
bash frontend/build-l2diff.sh srcgen2/DATS/filpath.dats 1       # dynamic .dats

# hand-pythonic compare (validate the harness independent of pyprint fidelity):
bash frontend/build-l2diff.sh frontend/TEST/l2diff/lets.dats 1 \
     --pythonic frontend/TEST/m3/m3_run.py
#   -> L2DIFF: FAITHFUL — zero structural diff   (exit 0)
```

`build-l2diff.sh <F> [stadyn] [--pythonic P] [--triage]`: `stadyn` 0=static/1=dynamic
(inferred from the extension when omitted); `--pythonic P` supplies a hand-written
pythonic for the pyfront side instead of `pyprint(F)`. Exit 0 = structurally identical =
faithful; exit 1 = divergent (the diff at `BUILD/<base>.l2diff.diff` pinpoints the node).

### `--triage` — the cascade-immune root-divergence view

The default normalizer **canonicalizes** stamps by first occurrence (rule 4 below), which
is exactly right for an exact-faithfulness proof but has one hazard: **a single
inserted/removed node shifts every later stamp by one**, so one root divergence cascades
into thousands of changed lines. `filpath_drpth0.dats`'s lone `#define`→value-binding
extra binder shifts `x(2)→x(3)→…` through the whole body → **9965 changed lines**, almost
all cascade.

`--triage` **strips** every stamp to a single placeholder instead — paren-stamp
`name(NNN)→name(#)` (keep the load-bearing name), bracket-stamp `name[NNN]→[#]` (drop the
synthesized name) — with **no positional counter and no digit guard**, so even the low
1–2-digit binder stamps collapse and an inserted/removed node is **one** diff line, not a
cascade. Token-literal carriers whose paren holds a value not a stamp (`T_INT01(0)`,
`LABint(1)`, `T_TRCD10(…)`, any `T_*`) are left intact. On `filpath_drpth0.dats` the diff
drops **9965 → 21**, surfacing the two real roots (the `#define`→`D2Cvaldclst`, the
include-path strings) instead of burying them.

Use the default (canonicalize) mode for the exact-faithfulness gate; use `--triage` to MAP
the diverging constructs. The two modes write **separate** artifacts
(`BUILD/<base>.l2diff.diff` vs `BUILD/<base>.l2triage.diff`) so they never clobber each
other. The corpus-wide triage MAP is `frontend/docs/L2-FAITHFULNESS.md` — the
faithfulness analog of `CONSTRUCT-COVERAGE.md`.

## Normalization (the crux)

The raw dump differs from stock in several *incidental*, non-structural ways. The
wrapper's `normalize()` (BSD-`sed` + BSD-`awk`, no gawk) canonicalizes them so that an
otherwise-identical structure compares equal. Each rule and its rationale:

1. **one node per line** — a newline before every Uppercase node constructor
   (`D2C...(`, `S2E...(`, …). Purely cosmetic; localizes the diff to the diverging node.
2. **locations** — `LCSRCsome1(...)@(N(line=..,offs=..)--N(line=..,offs=..))` → `@LOC`,
   and the bare header `LCSRCsome1(<path>)` source-identity → `@SRC`. The source PATH
   (the `.sats` vs the `.pdats`) and the line:col spans are incidental.
3. **absolute paths** — `FPATH(/abs/.../x.sats)` → `FPATH(@P/x.sats)` (machine path).
4. **stamps** — `name(NNNNN)` / `name[NNNNN]`. The d2var/d2con/d2cst stamp ids differ
   between stock and pyfront because they are assigned in different orders. Each
   **distinct** stamp is mapped to a sequential id `SK` **by first occurrence within
   each dump**, so identical structures (traversed in the same order) yield identical
   canonical stamps. Prelude d2csts print by NAME and are already stable; for a
   *bracket*-stamp `name[NNNN]` (the synthesized/internal s2var/typaram binders, whose
   name AND leading-case vary with order + pyprint's capitalize-scoping — `itm`/`Itm`,
   `X0`/`x0`) the synthesized name is dropped (`[SK]`); for a *paren*-stamp
   `name(NNNN)` the symbol name is kept (`name(SK)`) since d2cst/d2con names are
   load-bearing. The 3-digit guard means token lengths like `T_STRN1_clsd("..";29) are
   never touched.
5. **binding-token carrier** — `TEQD2EXPsome(<tok>; …)`: the first slot is the token
   recorded for a binding's `=`. Stock keeps the `=` (`T_EQ0()`); our lowering keeps
   the binder keyword (`T_VAL(VLKval)`/…). It is a cosmetic carrier, not structure →
   canonicalized to `TEQD2EXPsome(@BINDTOK; …)`.
6. **EOF terminator** — stock appends a trailing `,D2Cnone0()` top-level declaration
   that our lowering omits; it is a no-op → stripped inline (keeping paren balance).

The normalization was iterated against the known-faithful `lets.dats` pair until it
showed **zero** structural diff, while confirming the divergence fixtures still report
DIVERGENT (i.e. the rules do not over-collapse).

## Validation + first findings

**The harness works.** The faithful fixture shows zero diff:

```
$ bash frontend/build-l2diff.sh frontend/TEST/l2diff/lets.dats 1 \
       --pythonic frontend/TEST/m3/m3_run.py
>> L2DIFF: FAITHFUL — zero structural diff for lets      (exit 0)
```

`val a=7; val b=a; val c=b` and its hand-pythonic `let a=7; let b=a; let c=b` lower to
byte-identical raw L2 after normalization (the var-binding stamps `a/b/c` line up, the
`=`-vs-`val` binding token and the trailing `D2Cnone0()` are the only incidental
differences and are absorbed).

### Auto-pyprint corpus sweep (10 green files)

Every typecheck-green file is currently **DIVERGENT** under auto-pyprint:

| file | verdict | changed lines |
|------|---------|--------------:|
| `xstamp0.sats`        | DIVERGENT | 254 |
| `filpath.dats`        | DIVERGENT | ~18004 |
| `filpath_drpth0.dats` | DIVERGENT | ~18005 |
| `lexbuf0.dats`        | DIVERGENT | ~17967 |
| `dynexp0.dats`        | DIVERGENT | ~17969 |
| `dynexp0_print0.dats` | DIVERGENT | ~17967 |
| `lexing0_utils1.dats` | DIVERGENT | ~18027 |
| `lexing0_utils2.dats` | DIVERGENT | ~17981 |
| `nmspace.dats`        | DIVERGENT | ~17997 |
| `statyp2.dats`        | DIVERGENT | ~17975 |

**0 / 10 are byte-structurally identical.** The findings, in order of impact:

* **`#include` inline-expansion dominates (the ~18000).** Stock expands
  `#include "xatsopt_sats.hats"` textually, so the included header's *entire*
  transitive prelude-declaration set lands inline in the stock L2 tree. The
  pyprint→pyfront path translates `#include`/`#staload` to Koka-style `import`s that
  lower to single `D2Cstaload`/`D2Cimpload` nodes and do **not** re-inline the header.
  So a header-bearing file's whole-file dump is swamped by prelude `-` lines that exist
  only on the stock side — the body-level signal is buried. (To compare bodies, the
  next iteration should diff a header-stripped slice, or have pyprint NOT translate the
  expanding `#include`.)

* **`enum` drops the datatype body at raw-L2 (clean, header-free example).**
  `datatype color = Red | Green | Blue` →
  - stock: `D2Cdatatype(D1Cdatatype(... D1TCNnode(...Red), ...Green, ...Blue ...); $list(color))`
  - pyfront: `D2Cdatatype(D1Cnone0(); $list(color))`

  Our `enum` lowering emits a `D1Cnone0()` datatype body — the constructors are
  **dropped** at the raw-L2 level (the type name is still registered). It evidently
  typechecks only because a later pass / the prelude fills it in, but the raw lowering
  is not faithful. This is a genuine fidelity gap surfaced by the harness, not a
  pretty-printer cosmetic.

* **lossy pyprint of signatures.** `fun f(x: int): int = …` pyprints to `def f(x): …`
  (param/return types dropped) → the pyfront L2 has `FNKfn2` + empty `$list()` args +
  `S2RESnone()` where stock has `FNKfn1` + `D2ARGdyn2(... S2Ecst(int))` +
  `S2RESsome(...int)`. Top-level `val` may pyprint to `@static let` → a static
  `D2Csexpdef` instead of a dynamic `D2Cvaldclst`.

These residual diffs on typecheck-green files are exactly the "we lower differently
than stock but it happens to typecheck" findings the harness is meant to expose. This
deliverable is the working harness + this first report; fixing the divergences is
follow-up.
