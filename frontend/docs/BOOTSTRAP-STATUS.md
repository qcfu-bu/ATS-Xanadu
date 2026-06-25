# Bootstrap status and active backlog

Date: 2026-06-23

This note reconciles the older planning docs with the current repository state.
The tree now contains a working Pythonic lexer/parser/elaborator/lowerer, a
partial canonical-ATS-to-Pythonic pretty-printer, and milestone/round-trip
harnesses.

## 2026-06-23 — named-alias module qualification (the SATS interface unblock)

- **The systematic SATS blocker is closed.** ATS interfaces establish a module alias with a
  NAMED staload `#staload SYM = "..."` and qualify types/values by it (`$SYM.sym_t`,
  `$SYM.enlinear`). pyprint had been DROPPING the alias (emitting a bare
  `from "..." import *`) while still emitting `SYM.x` — so `SYM` was never registered and
  cascaded into hundreds of unresolved-name errors. **SATS faithful-reparse green went 6/44 -> 33/44.**
- **Surface (round-trip, extends the existing import grammar):**
  ATS `#staload SYM = "PATH"` <-> Pythonic `import "PATH" as SYM`; ATS `$SYM.x` <-> `SYM.x`.
- **3-layer implementation (frontend-only):**
  1. **pyprint** (`DATS/pyprint.dats`): a NAMED `#staload ALIAS = "..."` (an L0 `D0Cstaload`
     whose `g0exp` is the `ALIAS = "path"` apps-spine) now prints `import "..." as ALIAS`; a bare
     `#staload "..."` stays `from "..." import *`. The qualifier is ALSO kept where it was being
     dropped: qualified dynamic refs `$M.x` -> `M.x` (D0Equal0 inline), and `#symload NAME with
     $M.x` -> `@overload NAME = M.x`.
  2. **parser** (`DATS/pyparsing_decl00.dats` + `_dynexp`): `import modpath as NAME` (reusing the
     existing `PT_KW_AS`); a UIDENT is now accepted after `.` in postfix position so an
     uppercase-named member (`SYM.DLR_symbl`) parses as `PyEfield` instead of splitting; the
     overload-alias target accepts a qualified `M.x`. Type-position `SYM.sym_t` already joined into
     one dotted `PyTcon` name (no change needed).
  3. **lowering** (`DATS/pylower_decl00.dats` + `_dynexp.dats`): `lower_import` registers the
     module f2env under `$ALIAS.` (= `DLRDT(ALIAS)`) instead of the bare `$.` when an alias is
     present (and SKIPS the bare-name symload promotion for the named case) — mirroring stock
     `g1exp_nmspace` + `f0_staload` (trans12_decl00.dats). `PCEfield`/selector-call lowering detects
     a module-alias head (`PCEvar`/`PCEcon` whose name is a registered `$M.` namespace) and resolves
     `M.x` through `tr12env_find_s2itm($M.)` + `f2envlst_find_d2itm` — the d2 mirror of the existing
     `resolve_typ_qualified` (the SAME stock f0_qual0 mechanism). The overload-target resolver does
     the same for `@overload NAME = M.x`.
- **NO compiler logic reimplemented** — every resolution call is a stock `tr12env`/`f2env` API.
  Type/index erasure is the compiler's job; we only build the faithful L2 the stock parser would.
- **Gates:** strict auto gate 173/173 (no regression), dynamic 171/171, the new `pp-corpus-static`
  gate `CORPUS/pp-default-static.files` 33/33 strict; canary `trans12_dynexp.dats` still 1572 lines,
  TODOpp=0. The 11 remaining non-green SATS fail for DISTINCT gaps (template-impr `T2Bimpr`,
  static-cast index, etc.) — NOT the module-alias bug; `xsynoug.sats` is comments-only.

## 2026-06-23 — faithful verification pipeline (the M3 reparse now INVOKES the compiler)

- **Design re-anchored:** the frontend is strictly parser + desugar / pretty-print.
  It does NOT reimplement, work around, or satisfy any compiler pass (no overload
  resolution, no linearity/viewtype checking — there is none at level-1 anyway).
  Verification works by handing our desugared L2 to the compiler's OWN passes and
  letting them typecheck it.
- **Fix:** `pyfront_d3parsed_of_fpath` (frontend/DATS/pyfront_m3.dats) was running
  only 4 of the compiler's 5 post-L2 passes — it skipped `d2parsed_of_tread12`.
  It now runs the exact stock `trans03_from_fpath` sequence (trans23.dats:87-92):
  `tread12 -> trans2a -> trsym2b -> t2read0 -> trans23`. Every line is a stock
  compiler API call.
- **Consequence — honest baseline dropped 166 -> 158.** The previously-skipped
  `tread12` check exposed 8 FALSE GREENS: files that passed the partial pipeline
  but have a genuine pretty-print/desugar fidelity bug (our emitted L2 differs
  from what stock `trans02_from_fpath` produces). They are moved OUT of the strict
  gate into `CORPUS/pp-faithful-pending.files` (documented per-file) until fixed.
  The default auto corpus is now **158/158 green** (dynamic 156/156), honestly.
- **Real fidelity fix landed:** pyprint was DROPPING function static quantifiers —
  `fun f {n:nat} .<n>. (...: list_vt(t, n))` rendered without the `{n:nat}` binder,
  leaving the index `n` unbound. pyprint now emits `def f[N: SInt](...)` (sorts
  `nat`/`int`->`SInt`, `bool`->`SBool`). This is necessary but not sufficient for
  the 8 pending files; their residuals are distinct (template-impl param/signature
  unification `S2Eimpr` ×5, `@impl` instantiation, datatype head sort, `list_vt`
  dual-arity) — see `pp-faithful-pending.files`.
- **Selector files** (`staexp0`/`staexp2`/`trans23_dynexp`) still fail under the
  faithful pipeline (only `trans12_decl00` improved 4->2). They lower the dotted
  selectors FAITHFULLY (byte-identical `D2Esym0` overload bucket — verified) so
  resolution is the compiler's job; their residual is a separate desugar gap to
  diagnose, not overload-resolution logic for us to write. See `OVERLOAD-13A.md`.

## 2026-06-22 session checkpoint

- **Bundle builds now closure-minify.** `build-pp-corpus.sh` runs
  `google-closure-compiler --compilation_level SIMPLE` after linking the pyprint
  bundle (183MB raw -> ~5MB), falling back to raw on failure. Output is
  semantics-preserving and it collapses generated-code frame overhead, hardening
  the deep-recursive pyprint passes against Node stack overflow on large files.
- **Default auto corpus = 166/166 green (TODOpp=0, m3_nerror=0); dynamic = 164/164.**
  Newly closed this session: `trans12.dats`, `xglobal_ext000.dats` (promotions),
  `trsym2b_utils0.dats` (where-wrapped if-condition decls hoisted into scope),
  `xfixity.dats` (local `exception` decls in body suites were silently dropped by
  `el_local_decl` in `pyelab_core.dats` — now registered), and
  `t3read0_myenv0.dats` (pyprint dropped a datatype's `where { ... }` forward-ref
  helper datatype — now emitted + name-registered).
- **Remaining uncovered srcgen2 (15 files), now triaged into clusters:**
  1. **#13a overload/template residual (5):** `staexp0`, `staexp2`,
     `lexing0_utils1`, `trans12_decl00`, `trans23_dynexp`. Operator/print/selector
     names left unresolved (the long-standing `$`-template/overload-resolution gap).
     Deepest.
  2. **`#if defq(_XATS2JS_)` backend conditional-compilation (3):** `xglobal`,
     `xatsopt_tcheck00`, `xatsopt_tcheck01`. pyprint can't evaluate the `#if defq`
     and emits BOTH backend branches (e.g. `type Argv = jsa1sz[String]` AND
     `pya1sz[String]`), so later uses typecheck against the wrong array type. Needs
     a build-flag selector that emits only the active backend branch. Bounded.
  3. **Infra-crash, fail before an m3 verdict (7):** `lexing0_print0`,
     `trans01_dynexp`, `trans01_staexp`, `xlibext`, `xlibext_jsemit`,
     `xlibext_pyemit`, `xlibext_tmplib`. Need crash classification (pyprint
     overflow vs M3 parse crash vs driver/empty-output) — end-goal blocker #7.
- **Next frontier mapped: `srcgen1/prelude` (124 files).** See
  `PRELUDE-FRONTIER.md`. 96/124 emit marker-free but only ~6/16 sampled reparse
  clean; genuinely new work is the static/sort kernel declaration emitters
  (`#abssort`/`#stacst0`/`#sexpdef`/`#sortdef`/`#abstype`, 73% in
  `basics0.sats`+`fixity0.sats`), the `?T` top-type parse error, the
  `$extnam()+#impltmp where{}` FFI-shim crash, and the fixity DSL.
- **Recommended order:** (a) `#if defq` selector (closes 3, bounded); (b) infra-crash
  classifier (makes the 7 legible); (c) the #13a overload residual (hardest, 5);
  then the prelude static/sort-kernel emitters.

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
- The default corpus audit now pretty-prints and reparses/typechecks
  `srcgen2/SATS/xstamp0.sats`, `srcgen2/DATS/filpath_drpth0.dats`, the full
  `srcgen2/DATS/parsing*.dats` parser implementation slice, the green
  `pread00*`, `tread01*`, `tread12*`, `tread23*`, and `tread3a*`
  reader/checker slices, the focused compiler-environment slice
  `lexbuf0_cstrx1.dats`, `lexing0_utils2.dats`, `trans12_myenv0.dats`,
  `trans23_myenv0.dats`, and `trtmp3c_myenv0.dats`, the first green
  `dynexp0`/`dynexp1`/`dynexp2`/`dynexp3` helper sub-slice, the reporter and reader
  expansion slices, the `trtmp3b`/`trtmp3c` template-pass slice, the
  support/type-kernel `statyp2` plus `xstamp0`/`xsymbol`/`xlabel0` slice, the
  compiler-support expansion slice covering green `trans*`, `staexp*`,
  `xsymmap*`, `filpath*`, `gmacro1*`, `locinfo*`, `nmspace`, and `lexing0`
  helpers, and the focused round-trip fixtures with `TODOpp=0` and
  `m3_nerror=0`.
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
  final RHS. Local `#define` constants now print as dynamic `let` bindings,
  matching the compiler's macro-expansion behavior for corpus constants such as
  `STA`, `DYN`, and bit flags; symbolic macro aliases such as
  `#define :: list_cons` are preserved as comments rather than emitted as
  invalid Pythonic binders. Local exception
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
  `srcgen2/DATS/{parsing_basics,parsing_tokbuf,parsing_utils0,parsing_staexp,parsing_dynexp,parsing_decl00,parsing}.dats`
  now has `TODOpp=0` across all seven generated Pythonic files. Inline
  dot-selector printing preserves record/tuple-slot update targets such as
  `buf.2 := i0 + 1`, which clears and typechecks `parsing_tokbuf.dats`.
  Expression-position ATS `~(...)` boolean negation now prints as Pythonic
  `not (...)`, and the parser accepts `~expr` as a compatibility alias so older
  generated code does not crash M2. The generated-JS layout pass now runs
  iteratively, so the larger generated parser files no longer segfault during
  M1/M2/M3 reparse. Function-typed ATS declarations such as
  `fun p1_i0dntseq: p1_fun(i0dntlst)` now lower from the pyprinted
  `@extern def p1_i0dntseq() -> p1_fun[...]` shape without adding an extra
  nullary function layer. Function type parsing now follows ATS3 arity:
  `(A, B) -> C` is a native two-argument function, while `((A, B)) -> C`
  is the explicit unary tuple-argument form. Local `#define` constants now emit
  dynamic bindings, so `parsing_decl00.dats` no longer has unresolved
  `STA`/`DYN` references. Expression-position ATS `_` now elaborates as a
  contextual top/omitted value and lowers to `D2Etop(WCARD_symbl)`, not unit,
  so generated calls such as `T0ENDINVsome(_, tinv)` typecheck. As a result,
  the focused parser slice now has all seven generated files reparsing/typechecking
  at `m3_nerror=0`:
  `parsing_basics.dats`, `parsing_tokbuf.dats`, `parsing_utils0.dats`,
  `parsing_staexp.dats`, `parsing_dynexp.dats`, `parsing_decl00.dats`, and
  `parsing.dats`.
- The reader/checker expansion slice
  `srcgen2/DATS/{pread00,tread01,tread12,tread23,tread3a}*.dats` now reaches
  `TODOpp=0` and `m3_nerror=0` across twenty-three generated files. The last
  blocker in the first part of that slice was statement-`if` continuation
  handling: a side-effecting branch body must sequence into the following suite
  tail instead of replacing the function value.
- The reporter, t2/t3 reader, and template-pass expansion slices now sit in the
  default corpus and reach `TODOpp=0` and `m3_nerror=0`. This covers
  `f2perr0*`, `f3perr0*`, `t2read0*`, `t3read0.dats`,
  `t3read0_decl00.dats`, `t3read0_dynexp.dats`, `trtmp3b*`, and the green
  `trtmp3c` files except `trtmp3c_myenv0.dats`, which was already in the
  focused compiler-environment slice.
- The first dynamic-expression expansion slice
  `srcgen2/DATS/{dynexp0,dynexp0_print0,dynexp1,dynexp1_print0,dynexp2,dynexp2_print0,dynexp2_tmplib,dynexp2_utils0,dynexp3,dynexp3_print0,dynexp3_tmplib,dynexp3_utils0}.dats`
  now reaches `TODOpp=0` and `m3_nerror=0`. ATS qualified static map types such
  as `$MAP.topmap` now pretty-print as `MAP.topmap[...]` and lower through the
  same namespace lookup path as stock ATS. Imported multi-candidate symload call
  heads now prune by unique value-argument arity, so generated calls such as
  `d3pat(loc0, node)` lower to the arity-2 `d3pat_make_node` target instead of
  staying as unresolved `D2Esym0`.
- The support/type-kernel expansion slice now sits in the default corpus and
  reaches `TODOpp=0` and `m3_nerror=0`. It covers the `statyp2*`,
  `xstamp0*`, `xsymbol*`, and `xlabel0*` files now promoted into the default
  manifests.
- The compiler-support expansion slice now sits in the default corpus and
  reaches `TODOpp=0` and `m3_nerror=0`. It adds forty generated compiler
  support files: `trans3a*`, green `trans2a*` helpers, selected
  `trans12`/`trans11`/`trans23` helpers, `xsymmap*`, `staexp0_print0`,
  `staexp1*`, selected `staexp2*` helpers, `filpath_{fpath0,print0,search}`,
  `gmacro1*`, `locinfo*`, `nmspace`, and the green `lexing0` helper subset.
  The default dynamic corpus now validates 143/143 files; the default auto
  corpus validates 144/144 files.
- `srcgen2/DATS/filpath.dats` now sits in the default corpus and reaches
  `TODOpp=0` and `m3_nerror=0`. The blocker was expression-decorator
  precedence: generated code such as
  `@inst[Clst] @inst[cgtz] @inst[String] @inst[cgtz] gseq_z2cmp11(x1, x2) == 0`
  must instantiate the `gseq_z2cmp11(...)` call before applying infix equality.
  `@inst` and `@sapp` now bind as high-precedence expression decorators, with a
  regression in `TEST/atmpl/at_inst_infix_operand.pdats`.
- `srcgen2/DATS/lexing0_kword0.dats` now sits in the default corpus and reaches
  `TODOpp=0` and `m3_nerror=0`. The blocker was top-level `val` emission:
  token-valued aliases such as `val T0CAS0 = T_CASE(CSKcas0)` are dynamic
  values, not `stadef`s, so pyprint now emits plain `let` for top-level
  `D0Cvaldclst` bindings. True static definitions still use explicit
  `@static let`.
- `build-pp-corpus.sh --out-dir RELPATH` now normalizes the report directory
  against `frontend/` before running pyprint from `XATSHOME`, so separate static
  and dynamic corpus summaries can be kept without path breakage.

## End-goal blockers

1. Pretty-printer breadth is now marker-free for the audited `srcgen2/SATS`
   interface corpus and the 166-file `srcgen2/DATS`/`srcgen2/UTIL` pyprint-only
   slice. The parser implementation slice no longer crashes in layout/reparse,
   all seven first parser implementation files now reparse/typecheck, and the
   default dynamic corpus validates 143 generated files. The next breadth
   blocker is scaling that same `TODOpp=0` plus `m3_nerror=0` treatment into the
   remaining compiler/backend slices, then `srcgen1/prelude` and backend
   comparison.
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
  current default corpus and track per-file `# TODO(pp)` count and reparse
  `nerror`.
- Dynamic reparse/typecheck triage: protect the 166-file DATS/UTIL
  `TODOpp=0` pyprint-only baseline while classifying M3 type errors versus
  driver/runtime crashes. Generated pattern forms such as `@(C)(...)`, `!p`,
  `~C(...)`, applied lowercase constructor patterns, and generated `fold(e)`
  calls now parse/elaborate/lower; the next high-value targets are the remaining
  typecheck errors and unresolved dynamic helper names surfaced by generated
  Pythonic files. The previous `dynexp3.dats` imported-symload blocker is now
  covered by the default corpus and `TEST/dyn/dyn_overload_call_arity.pdats`.
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
