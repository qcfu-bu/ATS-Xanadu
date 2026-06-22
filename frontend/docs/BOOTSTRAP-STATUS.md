# Bootstrap status and active backlog

Date: 2026-06-22

This note reconciles the older planning docs with the current repository state.
The tree now contains a working Pythonic lexer/parser/elaborator/lowerer, a
partial canonical-ATS-to-Pythonic pretty-printer, and milestone/round-trip
harnesses.

## Current state

- Pythonic source to ATS compiler pipeline is implemented as:
  `pylexing` / `pylayout` -> `pyparsing` -> `pyelab` -> `pylower` -> L2
  `d2parsed` -> L2 post-passes -> `trans23` -> `tread3a`.
- The primary driver is `DATS/pyfront_m3.dats`; `build-m3.sh` is the closest
  full pipeline gate.
- Current reported green checks include `build-m1.sh`, `build-m3.sh`,
  `build-pp.sh`, `build-pp-corpus.sh --reuse-bundle`,
  `build-m16.sh --reuse-bundle`, and `build-robust.sh --reuse-bundle`.
- `build-roundtrip.sh` is a gap-analysis reporter, not a green regression gate.
- Canonical ATS ingestion exists through `pyprint`:
  `d0parsed_from_fpath` -> `DATS/pyprint.dats` -> Pythonic text.
  It is still a corpus-driven surface transliterator, but the currently audited
  static interface and dynamic compiler/utility slices have no visible
  `# TODO(pp)` fallbacks.
- The default corpus audit now pretty-prints and reparses/typechecks both
  `srcgen2/SATS/xstamp0.sats` and the dynamic compiler files
  `srcgen2/DATS/filpath_drpth0.dats` and `srcgen2/DATS/parsing_tokbuf.dats`
  with `TODOpp=0` and `m3_nerror=0`.
- The expanded static interface slice
  `srcgen2/SATS/{filpath,xsymbol,locinfo,lexing0}.sats` now also reaches
  `TODOpp=0` and `m3_nerror=0`. This covers aliased `#staload`, symbolic
  `#symload + ... of 1000`, plain function-type arrows, outer `<obj:vt>`
  template binders on extern constants, and parsed/erased `!T` viewtype
  parameter syntax.
- The next static interface slice
  `srcgen2/SATS/{xbasics,lexbuf0,xfixity,staexp0,dynexp0,parsing}.sats`
  now reaches
  `TODOpp=0` and `m3_nerror=0`. This adds symbolic overload aliases for
  `&`, `<<`, `>>`, and `>>>`, unary static `#define` expressions such as
  `-1`, parsed/erased `~T` linear/viewtype parameter syntax, by-reference
  view-change argument syntax such as `&SInt >> _`, and arrow result spines
  whose result is itself an applied type.
- The full `srcgen2/SATS/*.sats` interface corpus now reaches `TODOpp=0`.
  A fresh audit on 2026-06-22 reported 44 files pretty-printed, with 43/44
  emitted files reparsing/typechecking at `m3_nerror=0`; the remaining file,
  `xsynoug.sats`, is comments-only and emits an empty Pythonic file. This
  closes the real static blockers found in `trtmp3b.sats`, `trtmp3c.sats`,
  and `xsymmap.sats`: generalized view-change printing now covers `!T >> _`
  and parameterized `&T[A] >> _`, while the type parser erases `>> target`
  tails consistently.
- The Pythonic raw lexer now uses an iterative JS-backed scanner in
  `CATS/pylexing.cats`. The ATS scanner remains as the readable spec, but the
  production path no longer exhausts Node's stack on large pretty-printed
  compiler interfaces such as `dynexp0.sats`.
- The dynamic compiler/utility pyprint-only sweep now has a concrete baseline:
  `build-pp-corpus.sh --dynamic --no-reparse` over 166 `srcgen2/DATS` and
  `srcgen2/UTIL` files reports 0 visible `# TODO(pp)` marker lines. Printing ATS
  `when` guards as Pythonic `case ... if ...:` removed the largest previous
  TODO class, and selector left-hand sides such as `buf.N := ...` now print
  without `d0exp-inline` fallbacks. Value RHSs shaped as
  `let ... in ... end` now emit their local declarations before binding the
  final RHS. Local `#define` constants now reuse the `@static let` printer;
  symbolic macro aliases such as `#define :: list_cons` are preserved as
  comments rather than emitted as invalid Pythonic binders. Local exception
  constructors now print in `let` and `where` scopes, clearing `xfixity.dats`
  to `TODOpp=0`. `#staload` declarations in `local` heads now print inside the
  generated `private:` block. `local ... in ... end` declarations inside
  dynamic `let` setup lists now emit an indented `private:` setup followed by
  the local body declarations. Nested `local` declarations in `where` blocks
  and private heads now print with the same `private:` structure, clearing the
  remaining structural declaration fallbacks. Value RHS `if` expressions with
  `let`/`case` branches now print through indentation-aware block emitters.
  ATS `$llazy(case ...)` call-argument forms now print as Pythonic `llazy:`
  block expressions in `lexbuf0_cstrx1.dats` and `lexing0_utils2.dats`, closing
  the last visible dynamic DATS/UTIL pyprint markers.
- Explicit static application is now a first-class Pythonic expression decorator:
  `@sapp[T] f(...)` lowers to ATS `{T}` static application. Pyprint reconstructs
  static map-initializer calls such as `topmap_make_nil{itm}()` as
  `@sapp[Itm] topmap_make_nil()`. The focused dynamic compiler-environment slice
  `lexbuf0_cstrx1.dats`, `lexing0_utils2.dats`, `trans12_myenv0.dats`,
  `trans23_myenv0.dats`, and `trtmp3c_myenv0.dats` now reaches `TODOpp=0` and
  `m3_nerror=0`.
- The first focused parser implementation slice
  `srcgen2/DATS/{parsing_basics,parsing_tokbuf,parsing_utils0,parsing_staexp,parsing_dynexp,parsing_decl00}.dats`
  now has `TODOpp=0` across all six generated Pythonic files. Inline
  dot-selector printing preserves record/tuple-slot update targets such as
  `buf.2 := i0 + 1`, which clears and typechecks `parsing_tokbuf.dats`.
  Expression-position ATS `~(...)` boolean negation now prints as Pythonic
  `not (...)`, and the parser accepts `~expr` as a compatibility alias so older
  generated code does not crash M2. The generated-JS layout pass now runs
  iteratively, so the larger generated parser files no longer segfault during
  M1/M2/M3 reparse. They now reach ordinary M3 diagnostics:
  `parsing_staexp.dats` reports `m3_nerror=27`, `parsing_dynexp.dats` reports
  `m3_nerror=48`, and `parsing_decl00.dats` reports `m3_nerror=35`.
- `build-pp-corpus.sh --out-dir RELPATH` now normalizes the report directory
  against `frontend/` before running pyprint from `XATSHOME`, so separate static
  and dynamic corpus summaries can be kept without path breakage.

## End-goal blockers

1. Pretty-printer breadth is now marker-free for the audited `srcgen2/SATS`
   interface corpus and the 166-file `srcgen2/DATS`/`srcgen2/UTIL` pyprint-only
   slice. The parser implementation slice no longer crashes in layout/reparse;
   its remaining blockers are now concrete M3 type/elaboration diagnostics in
   the larger generated parser files. After those reach `m3_nerror=0`, extend
   the same treatment to `srcgen1/prelude` and backend comparison.
2. Include/import/load semantics are not faithful yet. Bare and aliased
   `#staload` now pretty-print to scoped ATS `.sats` imports, but `#include`
   still prints as an inert comment and needs a real Pythonic load/include
   story.
3. Identifier fidelity now has the first end-to-end path: pyprint emits ATS `$`
   names as slash-separated Pythonic names, the lexer accepts slash-separated
   identifier segments, and lowering maps them back before symbol lookup. The
   remaining work is collision-policy and corpus-scale validation.
4. Lowercase ATS type/constructor names require systematic policy. The frontend
   now handles Pythonic capitalized local types lowered back to ATS names and
   whitelisted lowercase prelude constructor patterns (`list_cons`, `list_nil`,
   `optn_*`, plus `_vt` variants). Applied lowercase pattern heads are now
   constructor-shaped and resolve in lowering, but faithful lowercase type
   declarations in hand-written round-trip fixtures still report parser errors.
5. Dynamic conversion is still incomplete, but the first real dynamic compiler
   file is now green: `#absimpl` prints as `@impl type`, `#staload` imports the
   interface, and `filpath_drpth0.dats` reparses/typechecks with `nerror=0`.
   `#implfun` bodies with ATS `where { ... }` now print as trailing Pythonic
   `where:` blocks and lower through `@impl def`, and ATS match `when` guards now
   print as Pythonic `case ... if ...:`. Richer expression/pattern forms still
   need corpus-driven expansion.
6. Full self-host validation needs corpus automation: pretty-print each file,
   reparse/lower/typecheck it, then eventually compare stock vs Pythonic backend
   outputs and stage2/stage3 compiler artifacts.
7. Dynamic reparse/typecheck at corpus scale still needs crash classification:
   a `TODOpp=0` generated file can still fail before an `m3_nerror` verdict, so
   the reporter needs to distinguish parse/type errors from driver/runtime
   crashes.

## Active workstreams

- Round-trip reporter hygiene: keep `build-roundtrip.sh` current with actual
  outcomes and make stale expected-failure comments disappear.
- Pretty-printer corpus audit: keep expanding `build-pp-corpus.sh` beyond the
  current two-file smoke corpus and track per-file `# TODO(pp)` count and
  reparse `nerror`.
- Dynamic reparse/typecheck triage: protect the 166-file DATS/UTIL
  `TODOpp=0` pyprint-only baseline while classifying M3 type errors versus
  driver/runtime crashes. Generated pattern forms such as `@(C)(...)`, `!p`,
  `~C(...)`, applied lowercase constructor patterns, and generated `fold(e)`
  calls now parse/elaborate/lower; the next high-value targets are the remaining
  typecheck errors and unresolved dynamic helper names surfaced by generated
  Pythonic files.
- Slash-identifier fidelity: keep `$` <-> `/` round-trip support covered by
  regression tests and expand the corpus audit around collision-prone names.

## Priority order

1. Stabilize reporting harnesses so every known gap is visible and current.
2. Close small pyprint TODOs that already have parser/lowering support
   (include/load forms, more local-head decls, effect-arrow tags).
3. Implement identifier fidelity and collision checks for pretty-printer naming.
4. Expand pyprint declaration/expression coverage against the prelude corpus.
5. Add corpus-level round-trip/typecheck automation, then backend diffing.
6. Convert prelude first, then compiler sources, then attempt the stage2/stage3
   fixpoint.
