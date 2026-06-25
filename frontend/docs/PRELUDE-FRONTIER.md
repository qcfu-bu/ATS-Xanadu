# Prelude pretty-printer frontier map

Date: 2026-06-22
Scope: `srcgen1/prelude/**` — the real ATS3 prelude, the next pyprint
frontier after the `srcgen2/{SATS,DATS,UTIL}` compiler corpus.
Status: INVESTIGATION ONLY. No source was edited, no bundle rebuilt.

This note maps which prelude constructs the current pyprint
(`DATS/pyprint.dats`) can and cannot render, ranks the gaps, and
classifies the round-trip failures of the files it *can* render.

Raw artifacts (durable):
- File list: `/tmp/prelude-files.txt` (124 paths, XATSHOME-relative).
- No-reparse audit: `frontend/BUILD/prelude-map/summary.tsv` (124 rows)
  plus per-file `*.pp.{psats,pdats}`, `*.pyprint.err`.
- Reparse sample (16 files): `frontend/BUILD/prelude-map/reparse-sample/summary.tsv`
  plus per-file `*.m3-reparse.log`.
- Run logs: `frontend/BUILD/prelude-map/_run-noreparse.log`,
  `frontend/BUILD/prelude-map/_run-reparse.log`.

Harness: `frontend/build-pp-corpus.sh --stadyn auto --reuse-bundle`
over the shared, prebuilt `frontend/BUILD/pp-corpus.js` (pyprint) and
`frontend/BUILD/pyfront-m3.js` (M3) bundles. `node --stack-size=8801`.
Note: `--out-dir` prefixes a *relative* path with `frontend/`; pass an
absolute path to land output exactly where intended.

---

## 1. Summary table (no-reparse pyprint over all 124 files)

| metric | count |
|---|---:|
| total prelude files (.sats + .dats, .hats excluded) | 124 |
| .sats / .dats | 64 / 60 |
| pyprint succeeded (rc=0) | 121 |
| pyprint crashed (rc!=0) | 3 |
| pyprint-CLEAN (rc=0 AND TODOpp=0) | 96 |
| pyprint OK but TODOpp>0 | 25 |
| total `# TODO(pp)` markers emitted | 282 |

So pyprint runs to completion on 121/124 (98%) and emits a marker-free
file for 96/124 (77%). But "marker-free" is a much weaker signal here
than in the compiler corpus — see section 4.

`.hats` (6 files) were excluded per task scope.

---

## 2. Ranked pretty-printer gaps — distinct `# TODO(pp)` markers

282 markers fall into six gap classes (grouped by the node-type token
after the colon):

| rank | gap class | markers | what it is |
|---:|---|---:|---|
| 1 | `unmapped d0ecl` | 108 | declaration node-types with **no emitter case at all** in `pyprint.dats` |
| 2 | `s0exp[...]` | 133 | static (type-level) expressions the printer cannot reconstruct |
| 3 | `d0exp-inline` | 18 | dynamic-expression fallbacks (raw-node escape) |
| 4 | `vardcl-no-rhs` | 16 | `var x: T` declarations with no initializer |
| 5 | `where-decl` | 11 | declarations appearing inside a `where { ... }` block |
| 6 | `g0exp` | 1 | a guard expression |

### 2a. Class 1 — `unmapped d0ecl` (108, the dominant blocker)

These are concentrated in the two foundational static-kernel files and
are exactly the prelude's bootstrap declarations that the compiler corpus
never exercised. In `basics0.sats` (174 total markers) and
`fixity0.sats` (33 markers) the printer emits a bare
`# TODO(pp): unmapped d0ecl` for each of:

- `#abssort` (20 in basics0) — abstract **sort** declarations (the very
  bottom of the type kernel: `bool`, `int`, `addr`, `char`, ...).
- `#stacst0` (57) — static constant declarations, i.e. the **static-level
  FFI**: `cast_b0_i0:(b0)->i0`, `add_b0_b0:(b0,b0)->b0`, ...
- `#sexpdef` (104) — static-expression defs incl. symbolic overload names
  (`~`, `+`, `*`, `b2i`).
- `#vwtpdef` (63), `#sortdef` (22) — viewtype/sort definitions.
- `#abstype`/`#absvwtp`/`#absvtbx`/`#abstbox` (≈32) — abstract type decls.
- `datasort` (1) — `ints_sort` (needs L1; flagged "needs L1" in the plan).
- fixity DSL (`fixity0.sats`): `#infixl` (19), `#prefix` (13), `#infix0`
  (10), `#infixr` (6) — the operator-precedence declarations.

These node-types are simply not yet handled by the pyprint walker.

### 2b. Class 2 — `s0exp[...]` (133)

The bracketed payload names the static head the printer choked on. The
recurring ones (with counts) are prelude type constructors the printer
has no spelling for:

- size/index ints: `SInt` (10), `Size` (7), `Ssize`, `Slint`, `Sllint`.
- list/seq families: `List`/`List_vt`/`Llist`/`Loptn` `[A,I|N|K|B]`
  (≈40 combined).
- string families: `Strq`/`Strq_vt`/`String_i0_*`/`Stropt_i0_*`/`Strtmp_*`.
- pointer/view families: `P1tr1`/`P2tr1`/`Cp1tr1`/`Cp2tr1` and their
  `_tbox` variants, `P2at_view`, `Arrvw`.
- array-size families: `A1rsz`/`A1psz`/`A2rsz`/`A2psz`/`T1rsz`/`T2rsz`.
- scalars: `Void` (3), `Char[C]`, `Bool_type[B]`, `Gint_type`.

A handful nest (`s0exp[...][...][!Arrvw[...] >> ...]`), i.e. the printer
fell through on an applied/view-changing static type and recursively
emitted markers for each sub-expression. These mostly live in the VT
(linear/viewtype) and array files (`arrn*`, `list000`, `strn000`,
`gseq000`, `strm000`), not just the kernel.

### 2c. Classes 3–6 (45 total)

`d0exp-inline` (18), `vardcl-no-rhs` (16), `where-decl` (11), `g0exp` (1)
— smaller, scattered dynamic-side fallbacks; lower leverage than 1 & 2.

### Marker concentration by file (top)

| markers | file |
|---:|---|
| 174 | `basics0.sats` (static/sort kernel) |
| 33 | `fixity0.sats` (fixity DSL) |
| 16 | `SATS/CC/basics0.sats` |
| 12 | `DATS/gseq000.dats` |
| 5 | `DATS/strm000.dats` |

`basics0.sats` + `fixity0.sats` alone account for 207 of 282 markers
(73%). Closing those two files closes most of the marker surface.

---

## 3. pyprint crash list (rc!=0)

3 files, all `SyntaxError: Unexpected end of input` (the emitted text is
malformed/truncated JS — pyprint did not finish emitting a well-formed
file). Error class: **emitter crash on FFI-shim shape**, not a stack
overflow.

| file | lines emitted | error |
|---|---:|---|
| `srcgen1/prelude/DATS/CATS/bool000.dats` | 0 | SyntaxError: Unexpected end of input |
| `srcgen1/prelude/DATS/CATS/CC/basics0.dats` | 0 | SyntaxError: Unexpected end of input |
| `srcgen1/prelude/DATS/CATS/gflt000.dats` | 0 | SyntaxError: Unexpected end of input |

All three are per-backend FFI shim files under `DATS/CATS/`. Their
distinguishing content is the **`#extern fun NAME ... = $extnam()`
binding combined with `#impltmp NAME<...> = TARGET where { ... }`** — the
foreign-name-binding pattern the plan calls out as Batch B. The other 53
files that use `#impltmp` (in its plain `@impl[...]` form) pyprint fine;
only the `#extern ... = $extnam()` (+ `where{}`-wrapped) shape crashes.
This is the genuine FFI emitter frontier.

---

## 4. Reparse (m3_nerror) on a 16-file pyprint-clean sample

Selected 16 of the 96 clean files (rc=0, TODOpp=0) with ≥30 emitted lines,
spread across .sats/.dats and dirs; reparsed sequentially through M3.

**Headline: 6/16 reach `m3_nerror=0`. TODOpp=0 does NOT imply round-trip.**

| m3_status | count | meaning |
|---|---:|---|
| ok (nerror=0) | 6 | clean round-trip |
| parse-error | 4 | emitted Pythonic rejected by OUR M2 parser |
| type-error | 3 | parses, fails M3 elaborate/lower (nerror>0) |
| driver-nonzero | 3 | crashes before any nerror verdict |

Per-file:

| file | lines | nerror | status |
|---|---:|---|---|
| arrn001.sats | 42 | 0 | ok |
| DATS/CATS/JS/g_print.dats | 55 | 0 | ok |
| utpl000.sats | 75 | 0 | ok |
| gbas000.dats | 95 | 0 | ok |
| VT/strm001_vt.sats | 137 | 0 | ok |
| VT/gcls000_vt.sats | 223 | 0 | ok |
| axsz000.dats | 59 | 2 | type-error |
| char000.dats | 106 | 16 | type-error |
| DATS/CATS/JS/basics0.dats | 196 | 2 | type-error |
| unsafex.sats | 156 | 26 | parse-error |
| VT/arrn000_vt.sats | 172 | 71 | parse-error |
| VT/list000_vt.sats | 263 | 6 | parse-error |
| list000.sats | 352 | 22 | parse-error |
| rand000.dats | 30 | ? | driver-nonzero |
| DATS/CATS/strn000.dats | 126 | ? | driver-nonzero |
| tupl000.dats | 490 | ? | driver-nonzero |

### Concrete failure characterizations

- **parse-error — `?[A0]` top/uninitialized type.** `unsafex.sats`,
  `arrn000_vt.sats`, `list000.sats` all error at the emitted `@extern def
  f[A0](a: ?[A0]) -> A0`. Pyprint renders ATS `(?a)` (the "top/maybe-
  uninitialized" type) as `?[A0]`, but the M2 parser reports
  `parse: expected a type` at the `?`. The `?`-prefixed type has no
  surface form in the Pythonic grammar yet. This is a fidelity gap that
  affects the unsafe/array/list slice broadly.
- **type-error — `char000.dats` (16), `axsz000.dats` (2),
  `JS/basics0.dats` (2).** Emitted code parses but lowering/typecheck
  produces nerror>0 (unresolved names / arity / overload-resolution),
  same family of issues already triaged in the compiler-corpus dynamic
  sweep, now resurfacing on prelude-specific helpers.
- **driver-nonzero — `tupl000.dats` throws `Error: XATS000_patck`** (a
  pattern-match-exhaustiveness failure inside the pyfront driver itself,
  not an nerror verdict). `rand000.dats` and `CATS/strn000.dats` exit
  nonzero with no nerror line. These need the crash-classification work
  the STATUS doc lists as open blocker #7.

Implication: the prelude reparse frontier is materially harder than the
compiler corpus. A `TODOpp=0` prelude file has only ~38% odds of
round-tripping in this sample, vs near-100% in the audited compiler
slices.

---

## 5. What is genuinely NEW vs the compiler corpus

Construct census over the 124 prelude files (authoritative; counts via
`xargs -0 grep`):

| construct | prelude count | files | new vs corpus? |
|---|---:|---:|---|
| `#extern` | 687 | — | **NEW** surface (corpus had it only erased) |
| `$extnam()` FFI binding | 665 | 22 | **NEW — primary FFI frontier** |
| `$extype` | 20 | — | **NEW** |
| `#impltmp` | 2620 | 56 | partial — plain form OK, `where{}`-FFI form crashes |
| `#symload` | 1357 | — | covered (`@overload`); volume is new |
| `#abssort` | 20 | — | **NEW — no emitter case** |
| `#abstype`/box/flat/vtbx/vwtp | 64 | — | **NEW — no emitter case** |
| `#stacst0` | 57 | — | **NEW — static-level FFI, no emitter** |
| fixity (`#infixl/r/0`,`#prefix`) | 48 | 1 | **NEW — no emitter case** |
| `datasort` | 1 | — | **NEW** (needs L1) |
| `#include` | 21 | — | partial (prints as comment) |
| `#staload` | 73 | — | covered |
| `#if/#then/#endif` | 6 | — | **NEW** (small; backend-selection) |
| `#define` | 2 | — | covered |
| `%{ C %}` blocks | **0** | — | confirmed ABSENT |
| `macdef`/`macrodef` | **0** | — | confirmed ABSENT |

**Plan de-risk claims VERIFIED on the real prelude:** zero `%{ C %}`
blocks, zero real macros. FFI is name-binding (`#extern...=$extnam()`),
exactly as the plan predicted.

**Numbers that differ from the plan's estimates:** `#impltmp` is 2620
here (plan said 934 corpus-wide) — the prelude is FFI/impl-dense. `$extnam`
is 665 (matches the plan's "665-in-prelude" figure). `#symload` 1357 and
fixity-in-one-file (`fixity0.sats`) also match the plan.

**The genuinely new emitter work**, ranked by leverage, is the
**static/sort kernel** (`#abssort`, `#stacst0`, `#sexpdef`, `#sortdef`,
`#vwtpdef`, `#abstype` family, `datasort`) and the **fixity DSL** — none
of which the compiler-corpus audit ever hit, because the corpus *uses*
the prelude's sorts/operators rather than *declaring* them.

---

## 6. Recommended next steps (ranked)

1. **Add `pyprint.dats` emitter cases for the static/sort kernel
   declarations** (`#abssort`, `#stacst0`, `#sexpdef`, `#vwtpdef`,
   `#sortdef`, `#abstype`/box/flat/vtbx/vwtp). This is 108 markers / class 1,
   73% of them in `basics0.sats`+`fixity0.sats`. Highest leverage; turns
   the unmapped-d0ecl class from "silent fallthrough" into real surface.
   Requires deciding the Pythonic spelling for each (design-agenda item:
   constants/abstract-types), then a walker case each.

2. **Render the `?T` (top/uninitialized) type.** Single small fidelity gap
   that converts ≥4 sample files from parse-error to potentially-clean
   (`unsafex`, `arrn000_vt`, `list000`, and the array/unsafe slice).
   Pyprint already emits `?[A0]`; either teach the M2 parser to accept a
   `?`-type, or change the printer to an accepted spelling. (Investigation
   only — pick one with the parser owner.)

3. **Fix the `#extern...=$extnam() where{}` FFI-shim emitter crash.**
   3 files crash outright (`DATS/CATS/{bool000,gflt000,CC/basics0}.dats`).
   This is the foreign-name-binding pattern (plan Batch B). The plain
   `#impltmp` form already works; the crash is specific to the
   `#extern` + `$extnam()` (+ `where{}`) combination producing truncated
   output.

4. **Add the fixity DSL surface + emitter** (`#infixl/r/0`, `#prefix`),
   48 decls all in `fixity0.sats`. This is design-agenda item 2
   (source-configurable Pratt table). Needed before any prelude file that
   *uses* prelude operators can round-trip faithfully.

5. **Build the prelude crash-classifier** (STATUS blocker #7). The
   `driver-nonzero` outcomes (`XATS000_patck`, silent nonzero) hide
   whether the emitted file is wrong or the driver is incomplete. Without
   this, reparse triage at prelude scale is guesswork.

6. **Then sweep the `s0exp[...]` type-constructor gaps** (class 2, 133
   markers across the list/string/pointer/array/view families). Lower
   priority than 1–4 because they are spread thin and many will be fixed
   incidentally once the kernel types have surface spellings.

7. **Only after 1–6**, expand the reparse pass from the 16-file sample to
   all 96 clean files, then to the marker-bearing files as their emitters
   land — and update `BOOTSTRAP-STATUS.md` end-goal blocker #1 (which
   currently names `srcgen1/prelude` as the next breadth target).
