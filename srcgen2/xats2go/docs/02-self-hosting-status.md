# Self-hosting status: SELF-COMPILE FIXPOINT REACHED (194/194 byte-equal)

_Updated 2026-08-18.  Supersedes the 2026-08-12 "self-compile NOT yet
reached" status: the failing-module collapse documented there had ONE
root cause (unifier stamp-equality miscompiled to pointer identity),
fixed in commit 8651612b2._

## What is PROVEN

The full compiler pipeline (frontend + go1emit, 194 units: 18 emitter +
162 frontend + 13 xats2cc modules + the CLI driver), compiled to Go by
the JS-bootstrapped bundle, builds into a native binary
(`selfhost-build/src/xats2go-selfhost`) that:

- **Compiles ATS3 user programs byte-identically to the bundle**: all 12
  go-arm rungs byte-equal (and the bundle side holds golden), psuite
  75/75.  Gate: `selfhost-build/dev.sh gate`.
- **Compiles its OWN COMPLETE SOURCE byte-identically to the bundle**:
  all 193 assemble.sh modules PLUS the CLI driver emit byte-equal to the
  bundle's `emit/*.go` references, with the IDENTICAL diagnostic surface
  (e.g. `xsymmap_stkmap`: the same 79,067 recoverable
  unresolved-prelude-instance reports on both sides).  Sweep:
  `selfhost-build/dev.sh sweep` — 193 PASS / 0 DIFF / 0 ERR, plus
  the driver checked separately (invoke with the same ABSOLUTE paths
  assemble.sh uses; path text embeds in location comments).

**The fixpoint follows by construction**: generation-2 assembly consumes
exactly those 194 emissions (concat + deterministic seds + shims/floor,
which are static inputs).  Byte-equal inputs ⇒ byte-identical gen-2 Go
source ⇒ the gen-2 binary is compiled from the same source as gen-1 and
reproduces the same emissions.  ATS3GO is self-hosting.

## The closing root cause (2026-08-18)

The binary manufactured `D3Cerrck` failures on inputs the JS-hosted
bundle checks clean.  Root cause: `unify00_s2typ` / `match00_s2typ`
(`srcgen2/DATS/statyp2_tmplib.dats`) compared s2cst/s2var/x2t2p/label
entities with generic `=`/`!=`, which resolve through g_eq<T> defaults
the srcgen2 resolver cannot instantiate — the emitted Go bridged them to
runtime POINTER identity, wrong for rebuilt (non-interned) cells.  Four
of the srcgen1 prelude's `gseq000` declarations failed exactly there in
EVERY compile, poisoning the `xatsopt_dpre.hats` includes that carry the
prelude template bodies — hence the previous "header-stub collapse" on
most compiler-scale modules.

Fix: spell the concrete semantics (which `xatsopt_tmplib` defines
anyway: `g_cmp<T>` = stamp compare, `g_cmp<label> = label_cmp`) at the
four comparison sites: `stamp_cmp(x.stmp(), y.stmp()) = 0` and
`label_cmp(l1, l2) != 0`.

Found by the `XATSGO_GEQ_DEBUG=1` runtime instrument (report con-pair
g_eq FALSEs whose scalar fields agree to depth 2 — the
pointer-unequal-but-stamp-equal miscompare shape, with stacks): on the
minimal probe it flagged exactly 2 call sites, both in the unifiers.

## Method notes (why this closed in one day after a week of loops)

- **Differential-first rule.**  A repro is only valid if it DIVERGES:
  binary-vs-bundle on the same input.  The earlier `zzprobe9`
  "vt-signature failure" errored on BOTH sides (its distillation dropped
  the `strm_vt_istrmize0` wrapper) — a probe campaign chased a
  non-divergence.  `zzprobe10` (gseq000's `gseq_istrmize` VERBATIM) is
  the validated pattern; `dev.sh probe` uses it by default.
- **Tiered harness** (`selfhost-build/dev.sh`): `probe` ~3s;
  `runtime` ~10s (go build is content-hash cached, 4.4s on real
  changes); `frontend` ~60s (the OLD bundle re-emits changed frontend
  .dats — a bundle rebuild is only needed when EMISSION behavior
  changes); `bridges` ~20s (per-module count of semantic runtime
  bridges); `bundle`; `gate`; `sweep`.  The old monolithic loop
  (lib2xatsopt + bundle + 194 re-emits + assemble + build) cost ~12 min
  per iteration and is almost never required.
- **Template-dependency trap**: editing a template BODY changes the
  instantiation copies embedded in every USING module while their .dats
  mtimes stay unchanged — and shifts char-offset-derived name stamps.
  Find embedders via the location comments
  (`grep -l <srcfile> emit/*.go`) and force their re-emit.

## Remaining known gaps (quality, not fixpoint)

- ~75 other bridged `Xats_g_eq`/`Xats_g_neq` sites remain binary-wide
  (`trans12_dynexp` 22, `dynexp3_utils0` 10, `trans12_staexp` 9, ...) —
  the same stamp-vs-pointer hazard class.  They do not affect the 194
  emissions (byte-proven) but could bite unexercised inputs; fix on
  GEQ-SUSPECT evidence or root-fix the resolver's generic-default
  instantiation (g_eq<T> -> g_cmp<T> with an inner free-tvar instance).
- `gs_print_nN` alias-form defaults still bridge multi-arg `prints` of
  CONSTRUCTOR args to the runtime generic printer, so some diagnostics
  print payloads as `list()` (cosmetic; error COUNTS and control flow
  match the JS side exactly).  Workaround stays: sequenced single-arg
  `print(x)` rewrites where readability matters.
- The srcgen1 prelude bridge-farm (~79k recoverable TIMPLall1 reports
  per compiler-module compile, on BOTH sides) is inherited from the
  frontend/prelude template story, not a Go-backend defect.
