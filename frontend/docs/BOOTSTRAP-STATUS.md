# Bootstrap status and active backlog

Date: 2026-06-22

This note reconciles the older planning docs with the current repository state.
`docs/README.md` is stale: it still describes the project as planning-only, while
the tree now contains a working Pythonic lexer/parser/elaborator/lowerer, a
partial canonical-ATS-to-Pythonic pretty-printer, and milestone/round-trip
harnesses.

## Current state

- Pythonic source to ATS compiler pipeline is implemented as:
  `pylexing` / `pylayout` -> `pyparsing` -> `pyelab` -> `pylower` -> L2
  `d2parsed` -> L2 post-passes -> `trans23` -> `tread3a`.
- The primary driver is `DATS/pyfront_m3.dats`; `build-m3.sh` is the closest
  full pipeline gate.
- Current reported green checks include `build-m1.sh`, `build-m3.sh`,
  `build-pp.sh`, `build-m16.sh --reuse-bundle`, and
  `build-robust.sh --reuse-bundle`.
- `build-roundtrip.sh` is a gap-analysis reporter, not a green regression gate.
- Canonical ATS ingestion exists through `pyprint`:
  `d0parsed_from_fpath` -> `DATS/pyprint.dats` -> Pythonic text.
  It is still a tracer-grade surface transliterator with visible `# TODO(pp)`
  fallbacks.

## End-goal blockers

1. Pretty-printer breadth is the main blocker. It must become corpus-grade for
   `srcgen1/prelude` and `srcgen2/{SATS,DATS,UTIL}` before self-hosting is
   meaningful.
2. Include/import/load semantics are not faithful yet. `#include`/`#staload`
   currently print as TODO comments in some pyprint paths, while the Pythonic
   frontend supports only a scoped ATS `.sats` import subset.
3. Identifier fidelity now has the first end-to-end path: pyprint emits ATS `$`
   names as slash-separated Pythonic names, the lexer accepts slash-separated
   identifier segments, and lowering maps them back before symbol lookup. The
   remaining work is collision-policy and corpus-scale validation.
4. Lowercase ATS type/constructor names require systematic pretty-printer
   capitalization plus collision handling. The `xstamp0_ucase` probe proves the
   uppercased variant typechecks; faithful lowercase input still reports errors.
5. Dynamic conversion is still incomplete. `#absimpl` now prints as
   `@impl type`, but `filpath_drpth0.dats` still exposes typecheck gaps around
   dynamic local ordering/import semantics, and richer expression/pattern forms
   need corpus-driven expansion.
6. Full self-host validation needs corpus automation: pretty-print each file,
   reparse/lower/typecheck it, then eventually compare stock vs Pythonic backend
   outputs and stage2/stage3 compiler artifacts.

## Active workstreams

- Round-trip reporter hygiene: keep `build-roundtrip.sh` current with actual
  outcomes and make stale expected-failure comments disappear.
- Pretty-printer corpus audit: add a reporting harness that summarizes per-file
  `# TODO(pp)` count and reparse `nerror`.
- Slash-identifier fidelity: keep `$` <-> `/` round-trip support covered by
  regression tests and expand the corpus audit around collision-prone names.

## Priority order

1. Stabilize reporting harnesses so every known gap is visible and current.
2. Close small pyprint TODOs that already have parser/lowering support
   (import comment forms, overload precedence output, more local-head decls).
3. Implement identifier fidelity and collision checks for pretty-printer naming.
4. Expand pyprint declaration/expression coverage against the prelude corpus.
5. Add corpus-level round-trip/typecheck automation, then backend diffing.
6. Convert prelude first, then compiler sources, then attempt the stage2/stage3
   fixpoint.
