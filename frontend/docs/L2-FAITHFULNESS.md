# L2-FAITHFULNESS — the corpus-wide map of which constructs lower faithfully

This is the faithfulness analog of `CONSTRUCT-COVERAGE.md`. Where `L2-DIFF.md` documents
the *harness* that compares stock L2 vs pythonic L2 for one file, this document is the
*result* of running that harness — in cascade-immune **triage** mode — over a
representative sample of the typecheck-green corpus, and **classifying the structural
divergences by construct class** so the fixes are per-class, not per-file.

The deliverable here is the MAP (what is faithful vs what diverges and *how*). It does
**not** fix the divergences — that is follow-up, and each class below names the
responsible frontend pass so the fix has an address.

## TL;DR

* **Triage mode (`build-l2diff.sh … --triage`) kills the stamp-shift cascade.** On
  `filpath_drpth0.dats` the structural diff drops from **9965 changed lines → 21**, with
  the real roots (`#define`→value-binding, the include-path strings) now plainly visible
  instead of buried under ~9900 cascade lines.
* **Of the 28 sampled green files, 0 are byte-structurally FAITHFUL.** But every
  divergence falls into **6 well-defined construct classes**, and **2 of them
  (DEFINE, GSRC) are driven entirely by the standard file header** (the `#define
  ATS_PACKNAME` + the relative `#include`/`#staload` paths), not by the bodies.
* **The big positive: real `.dats` bodies lower faithfully.** Every one of the 13 sampled
  `.dats` impl bodies is structurally identical to stock **once the cosmetic header
  classes are set aside** — e.g. `t2read0.dats` has **706 matching
  `D2Cfundclst`/`D2Cimplmnt0`/`D2FUNDCL` nodes on both sides** and its *only* diff is the
  two `#include` path-string lexemes. The function/implementation lowering is faithful.
* The interface (`.sats`) divergences (FUNSIG, EXTERN) are a single shape choice in the
  `extern def` lowering, and the datatype-body (DATATYPE) divergence touches a field the
  back-end verifiably never reads. **None of the 6 classes is a typecheck-breaking
  fidelity bug**; they range COSMETIC → SEMANTICALLY-EQUIVALENT-shape.

## Triage mode (Step 1) — cascade-immune root-divergence view

The default normalizer **canonicalizes** stamps by first occurrence: every distinct
`name(NNNN)`/`name[NNNN]` stamp is renumbered `S1,S2,…` in traversal order, so identical
structures compare equal (exact-faithfulness proof). The hazard: **one inserted or
removed node shifts every later stamp by one**, so a single root divergence cascades into
thousands of changed lines. `filpath_drpth0.dats`'s lone `#define`→value-binding extra
binder shifts `x(2)→x(3)`, `x(3)→x(4)`, … through the whole body → **9965 changed lines,
almost all cascade.**

`--triage` instead **strips** every stamp to a single placeholder — paren-stamp
`name(NNN)→name(#)` (keep the load-bearing d2cst/d2con name), bracket-stamp
`name[NNN]→[#]` (drop the synthesized binder name, as canonicalize does) — with **no
positional counter and no digit guard**, so even the low 1–2-digit binder stamps
collapse. Token-literal carriers whose paren holds a *value* not a stamp (`T_INT01(0)`,
`LABint(1)`, `T_TRCD10(2)`, any `T_*`) are left intact. With no counter, an
inserted/removed node is **one** diff line, not a cascade.

Keep the default canonicalize mode for the exact-faithfulness gate; use `--triage` to MAP
the roots. The two modes write to separate artifacts (`*.l2diff.diff` vs
`*.l2triage.diff`) so they never clobber each other.

### Cascade kill — before/after (canonicalize vs triage, changed lines)

| file | canonicalize | triage | note |
|------|-------------:|-------:|------|
| `filpath_drpth0.dats` | **9965** | **21** | the `#define` sits before the body → full stamp cascade; triage removes it |
| `lexbuf0.dats`        | **9965** | **21** | same `#define`-before-body cascade |
| `xstamp0.sats`        | 256 | 240 | modest (per-decl divergences, only a small shared cascade) |
| `nmspace.sats`        | 102 | 102 | no single-insertion cascade (per-decl FUNSIG, stamps already local) |
| `t2read0.dats`        | 6 | 6 | already minimal (its `#define` aligned away; body faithful) |
| `trans01.dats`        | 6 | 6 | already minimal |

Triage's win is concentrated exactly where it should be: the `.dats` bodies whose
file-leading `#define` inserts a binder ahead of the body (9965 → 21). Where the
divergence is per-declaration rather than a single insertion (`.sats` interfaces), the two
counts coincide — there was never a cascade to kill there.

## The sample (Step 2)

28 green files spanning the variety: tiny→large; `.sats` interfaces and `.dats` impl
bodies; with/without `#include`; datatype-heavy, signature-heavy, `#define`-heavy. (Three
bases — `xstamp0`, `locinfo`, `parsing` — exist as both `.sats` and `.dats`; both were run
and snapshotted to distinct artifacts.)

```
.sats interfaces:  nmspace xsymenv xlibext xerrory xstamp0 xlabel0 locinfo filpath
                   lexing0 statyp2 xbasics xsymbol parsing trans12 tread01
.dats impl bodies: xsynoug xstamp0 lexbuf0 f2perr0 filpath_drpth0 filpath_fpath0
                   lexing0_token0 locinfo trsym2b parsing t2read0 trans01 tread12
```

### Faithful vs divergent

* **Structurally FAITHFUL (0 diff): 0 / 28.**
* **DIVERGENT: 28 / 28** — but the divergence is, for **13 / 13 sampled `.dats` bodies**,
  *only* the cosmetic header classes (GSRC ± DEFINE ± STALOAD): the function- and
  implementation-body lowering is structurally identical to stock. The genuine body/sig
  shape choices (FUNSIG, EXTERN, DATATYPE) are confined to `.sats` interfaces and to
  declaration forms, never to a `.dats` function *body*.

So the honest headline is: **no file is byte-faithful end-to-end, but the bodies are
faithful; the residue is a handful of construct-class shape choices, two of which are pure
header cosmetics.**

## Divergence classes (Step 3), ranked by sampled files affected

Detected by node-shape signatures over the raw/triage dumps. Counts are over the 28-file
sample. `present` is conservative for DEFINE/DATATYPE: when a class lands next to a
matching prelude node the unified-`diff` can *align it away* (so the file still has the
divergence in the raw dump but it does not appear as a changed line) — those cases are
noted; they do not change the verdict.

| # | class | files | node shape: **stock** → **pyfront** | pass | verdict |
|---|-------|------:|--------------------------------------|------|---------|
| 1 | **GSRC** include/staload path string | 23 | `T_STRN1_clsd("./../HATS/x.hats";29)` → `T_STRN1_clsd("srcgen2/HATS/x.hats";32)` (the `gsrc` `G1Estr` lexeme; **`FPATH(...)` already matches**) | pyprint (path normalization) | **COSMETIC** |
| 2 | **DEFINE** `#define`→value-binding | 21 | `D2Cd1ecl(D1Cdefine(T_SRP_DEFINE();T_IDALP(ATS_PACKNAME);…G1Estr…))` → `D2Cvaldclst(T_VAL(VLKval);D2VALDCL(D2Pvar(xatsv_ATS_PACKNAME(#));…D2Estr…))` | pyprint (`pp_define`) | **SEM-EQUIV shape** (value-defines); macro-aliases out of scope |
| 3 | **FUNSIG** function-signature relocation | 15 | `T_FUN(FNKfn1);…D2CSTDCL(f;$list(D2ARGdyn2(-1;$list(…)));S2RESsome(S2EFFnone();S2Ecst(T)))` → `T_FUN(FNKfn2);…D2CSTDCL(f;$list();S2RESnone())` | pylower (`pylower_decl00`) | **SEM-EQUIV shape** (type kept on the d2cst, not the D2CSTDCL slots) |
| 4 | **EXTERN** dynconst wrapper | 15 | bare `D2Cdynconst(…)` → `D2Cextern(T_SRP_EXTERN();D2Cdynconst(…))` | pylower (`pylower_decl00`) | **COSMETIC** (transparent wrapper) |
| 5 | **STALOAD** staload token + gsrc shape | 11 | `T_SRP_STALOAD();G1Estr(…)` / `G1Ea2pp(G1Eid0(=);G1Eid0(ALIAS);G1Estr(…))` → `T_VAL(VLKval);G1Eid0(/abs/path)` | pylower (`pylower_decl00`) | **COSMETIC** (`token`/`gsrc` vestigial; readers use `knd0`/`fopt`/`dopt`) |
| 6 | **DATATYPE** vestigial datatype-body field | 6 | `D2Cdatatype(D1Cdatatype(…cons…);$list(T))` → `D2Cdatatype(D1Cnone0();$list(T))` | pylower (`pylower_decl00`) | **COSMETIC — codegen verdict below** |

(FUNSIG and EXTERN are perfectly correlated — same 15 `.sats` files — because both are
emitted by the *same* `extern def` lowering. STALOAD's 11 are files with `#staload`/aliased
imports. DATATYPE's 6 are the datatype-bearing interfaces; in `.dats` the same divergence
occurs but is diff-aligned-away on the matching `$list(T)` tail.)

### Per-file class matrix (sample)

```
file                   | DEFINE  FUNSIG  DATATYPE  EXTERN  STALOAD  GSRC
-----------------------+--------------------------------------------------
nmspace.sats           |   .       Y        .        Y       .       .
xsymenv.sats           |   .       Y        .        Y       Y       .
xlibext.sats           |   .       Y        .        Y       .       .
xerrory.sats           |   Y       Y        .        Y       .       Y
xstamp0.sats           |   Y       Y        .        Y       .       Y
xlabel0.sats           |   Y       Y        Y        Y       Y       Y
locinfo.sats           |   Y       Y        Y        Y       Y       Y
filpath.sats           |   Y       Y        Y        Y       Y       Y
lexing0.sats           |   Y       Y        Y        Y       Y       Y
statyp2.sats           |   Y       Y        Y        Y       Y       Y
xbasics.sats           |   Y       Y        Y        Y       .       Y
xsymbol.sats           |   Y       Y        .        Y       Y       Y
parsing.sats           |   Y       Y        .        Y       Y       .
trans12.sats           |   Y       Y        .        Y       Y       Y
tread01.sats           |   Y       Y        .        Y       Y       Y
xsynoug.dats           |   Y       .        .        .       Y       .
xstamp0.dats           |   Y       .        .        .       .       Y
lexbuf0.dats           |   Y       .        .        .       .       Y
f2perr0.dats           |   Y       .        .        .       .       Y
filpath_drpth0.dats    |   Y       .        .        .       .       Y
filpath_fpath0.dats    |   Y       .        .        .       .       Y
lexing0_token0.dats    |   Y       .       (Y)       .       .       Y
locinfo.dats           |   Y       .       (Y)       .       .       Y
trsym2b.dats           |  (Y)      .        .        .       .       Y
parsing.dats           |   Y       .        .        .       Y       Y
t2read0.dats           |  (Y)      .        .        .       .       Y
trans01.dats           |  (Y)      .        .        .       .       Y
tread12.dats           |  (Y)      .        .        .       .       Y
```

`(Y)` = present in the raw dump but diff-aligned-away in the triage diff (a `diff`
alignment artifact next to a matching prelude node, not a real absence). Notably **every
`.dats` row carries only header classes** — no FUNSIG/EXTERN, and DATATYPE only as the
vestigial-field `(Y)`.

## Class details, minimal examples, and verdicts

### 1. GSRC — include/staload path-string lexeme — COSMETIC

`#include "x"` / `#staload "x"` round-trips with the **same node shape** (`G1Estr` of a
`T_STRN1_clsd`), and the resolved `FPATH(...)` is **identical** on both sides. Only the
*string content* of the source lexeme differs: stock keeps the original source-relative
lexeme `"./../HATS/xatsopt_sats.hats"`, pyprint normalizes it to the workspace-relative
`"srcgen2/HATS/xatsopt_sats.hats"`.

```
- T_STRN1_clsd("./../HATS/xatsopt_sats.hats";29)
+ T_STRN1_clsd("srcgen2/HATS/xatsopt_sats.hats";32)
```

Responsible pass: **pyprint** path normalization (see `pylower_decl00.dats:1056-1061`,
which explicitly documents this as "a pyprint path-normalization artifact, not an
include-structure divergence; the NODE SHAPE … matches"). Fix is a normalize-only step (or
have pyprint preserve the original lexeme).

### 2. DEFINE — `#define NAME val` → `let NAME = val` — SEMANTICALLY-EQUIVALENT shape

```
- D2Cd1ecl(D1Cdefine(T_SRP_DEFINE();T_IDALP(ATS_PACKNAME);$list();$optn(G1Estr(…"…20220500"…))))
+ D2Cvaldclst(T_VAL(VLKval);$list(D2VALDCL(D2Pvar(xatsv_ATS_PACKNAME(#));TEQD2EXPsome(@BINDTOK;D2Estr(…"…20220500"…));WTHS2EXPnone())))
```

stock keeps the `#define` as a **static compile-time macro** (`D1Cdefine`, macro-expanded
before dynamic typechecking); pyfront models it as a **dynamic value binding**
(`D2Cvaldclst`). Responsible pass: **pyprint** `pp_define` (`pyprint.dats:2024-2046`),
which deliberately maps `#define NAME val → let NAME = val` because "modeling them as
dynamic value bindings matches the corpus use sites". For the corpus value-defines
(strings, ints, flags) the two are observationally equivalent. The one *non*-equivalent
subset — a `#define` used as a **macro alias** (`#define :: list_cons`) — is not
representable as a `let` and pyprint already side-steps it (emits an inert comment), so it
does not appear here. Verdict: SEMANTICALLY-EQUIVALENT-shape for value-defines.

### 3. FUNSIG — function-signature relocation — SEMANTICALLY-EQUIVALENT shape

```
- T_FUN(FNKfn1);$list();$list(D2CSTDCL(f(#);$list(D2ARGdyn2(-1;$list(D2Pann…S2Ecst(int))));S2RESsome(S2EFFnone();S2Ecst(int));TEQD2EXPnone()))
+ T_FUN(FNKfn2);$list();$list(D2CSTDCL(f(#);$list();S2RESnone();TEQD2EXPnone()))
```

For an `extern def f(x: T): U`, stock attaches the dynamic args (`D2ARGdyn2`) and result
(`S2RESsome`) **on the `D2CSTDCL` declaration node**; pyfront emits empty args + `S2RESnone`
on the `D2CSTDCL` and instead carries the **full function type on the d2cst's `idtp`**
(`pylower_decl00.dats:615-639` builds `sfun = s2exp_fun1_nil0(argtyps, restyp)` and registers
it via `d2cst_make_idtp`). The type is present — it lives in a different node slot — so a
call to `f` resolves correctly (the comment at :638: "register so a call to `name`
resolves"). It also hard-codes `FNKfn1`→`FNKfn2` (a tail-rec-capable funkind tag).
Responsible pass: **pylower** (`pylower_decl00`). Verdict: SEMANTICALLY-EQUIVALENT-shape
(type relocated, not lost).

### 4. EXTERN — transparent `D2Cextern` wrapper — COSMETIC

```
- D2Cdynconst(T_FUN(…);$list();$list(D2CSTDCL(…)))
+ D2Cextern(T_SRP_EXTERN();D2Cdynconst(T_FUN(…);$list();$list(D2CSTDCL(…))))
```

pyfront wraps every `extern def`'s `D2Cdynconst` in a `D2Cextern(T_SRP_EXTERN(); …)` node;
stock emits the bare `D2Cdynconst`. The wrapper is transparent (it only re-tags the decl as
`extern`). Responsible pass: **pylower** (`pylower_decl00.dats:643`). Verdict: COSMETIC.

### 5. STALOAD — staload `token` + `gsrc` shape — COSMETIC

```
- D2Cstaload(0;T_SRP_STALOAD();G1Estr(T_STRN1_clsd("./lexing0.sats";16));$optn(FPATH(…));…)
+ D2Cstaload(0;T_VAL(VLKval);G1Eid0(/srcgen2/SATS/lexing0.sats);$optn(FPATH(…));…)
# aliased `#staload LEX = "./lexing0.sats"`:
- …G1Ea2pp(G1Eid0(=);G1Eid0(LEX);G1Estr(…))…
```

pyfront emits a `T_VAL(VLKval)` token in the `token` slot (vs stock's `T_SRP_STALOAD`) and a
`G1Eid0(absolute-path-as-symbol)` for `gsrc` (vs stock's `G1Estr`, or `G1Ea2pp` for an
aliased import). The resolved `fopt`/`dopt` (the dep-graph fpath + the staloaded f2env)
**match**. Responsible pass: **pylower** (`pylower_decl00.dats:950-956`), which documents the
`token`/`gsrc` slots as "vestigial for typecheck; … trans23/tread3a/the LSP reader only read
`knd0`/`fopt`/`dopt`". Verdict: COSMETIC.

### 6. DATATYPE — vestigial datatype-body field — COSMETIC (codegen verdict)

```
- D2Cdatatype(D1Cdatatype(T_DATATYPE(0);$list(D1TYPnode(…D1TCNnode(…cons…)…)));$list(label))
+ D2Cdatatype(D1Cnone0();$list(label))
```

pyfront emits `D1Cnone0()` in the **first** field of `D2Cdatatype`, where stock carries the
full `D1Cdatatype(…constructors…)`. The **second** field (`$list(label)` — the datatype's
s2csts) is **identical**, and the constructors themselves are wired onto the s2cst and
registered in the env separately (`pylower_decl00.dats:1169-1181`), so the datatype is fully
usable.

**Codegen verdict — does any back-end pass read the first field?** No. `trans23`'s
`f0_datatype` (`srcgen2/DATS/trans23_decl00.dats:802-814`) destructures
`D2Cdatatype(d1cl, s2cs)` and **binds `d1cl` but never reads it** — its body uses only
`d2cl.lctn()` and re-wraps `D3Cd2ecl(d2cl)`. The `pylower_decl00.dats:31` comment states the
same ("the VESTIGIAL first field of `D2Cdatatype` — trans23's `f0_datatype` binds but never
reads it"). So `D1Cnone0()` vs `D1Cdatatype(…)` is provably inert at the trans23 boundary
the harness compares. Verdict: **COSMETIC** (vestigial field, no reader).

Nuance worth recording: pyfront has **two** datatype-lowering paths. A plain
`enum`/`datatype` (e.g. `a1rsz_dt` in `lexing0_token0.dats`) lowers to a **faithful**
`D1Cdatatype(…)` first field — *byte-identical* to stock — while the abstract-implementing
datatype path (the `token` + `D2Cabsimpl` case) emits the `D1Cnone0()` vestige. So this
class is not uniform across datatypes; only the abstract-impl path drops the (vestigial)
field.

## How to reproduce

```bash
export XATSHOME=/Users/qcfu/Projects/ATS-Xanadu
bash frontend/build-l2dump.sh                    # one-time: build the dumper
bash frontend/build-pp-dyn.sh                     # one-time: dynamic pyprint bundle
bash frontend/build-pp.sh                         # one-time: static  pyprint bundle

# triage one file (cascade-immune root view):
bash frontend/build-l2diff.sh srcgen2/DATS/filpath_drpth0.dats 1 --triage
#   -> L2TRIAGE: DIVERGENT — 21 changed lines  (vs 9965 in default canonicalize mode)

# the two modes write distinct artifacts:
#   BUILD/<base>.l2diff.diff      (canonicalize — exact-faithfulness gate)
#   BUILD/<base>.l2triage.diff    (triage       — root-divergence map)
```

## Verdict summary

| class | verdict | fix kind |
|-------|---------|----------|
| GSRC      | COSMETIC                     | normalize-only / pyprint keep original lexeme |
| DEFINE    | SEM-EQUIV shape (value-defs) | construct-class: lower `let`-from-`#define` to a static `D1Cdefine`, or normalize |
| FUNSIG    | SEM-EQUIV shape              | construct-class: emit args/`S2RESsome` on the `D2CSTDCL`, not only on the d2cst type |
| EXTERN    | COSMETIC                     | normalize-only / drop the transparent wrapper |
| STALOAD   | COSMETIC                     | normalize-only (token/gsrc are vestigial) |
| DATATYPE  | COSMETIC (no reader)         | optional: fill the vestigial `D1Cdatatype` on the abstract-impl path for byte-parity |

**None of the six is a typecheck-breaking fidelity bug.** Two (GSRC, STALOAD) are pure
source-lexeme/vestigial-slot cosmetics; EXTERN is a transparent wrapper; DATATYPE touches a
field no downstream pass reads; DEFINE and FUNSIG are real *shape* relocations that are
semantically equivalent for the corpus. Fixing them is per-class (6 construct fixes), not
per-file (44+ files) — which is the entire point of this map.
