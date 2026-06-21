# Bootstrap plan — a fully pythonic ATS3 compiler (self-host)

> **Goal.** Re-author the ATS3 compiler's own source in the pythonic surface and recompile it
> with our Python-surface frontend, reaching a **fixpoint** (the pythonic-built compiler rebuilds
> the pythonic compiler source, stage2==stage3). This turns *asserted* syntax parity into *proven*
> parity. **FAITHFUL** approach (decided 2026-06-21): pretty-print canonical ATS → pythonic at the
> SURFACE level (preserve macros/fixity/structure), so the port is human-maintainable — no
> flattened throwaway. Recon agents on 2026-06-21 produced the requirement set below.

## How it works
Pretty-printer = the INVERSE of our pipeline. Ours: `pythonic → PyAST → PyCore → L2`. The
pretty-printer: `canonical ATS → stock L0 AST (d0parsed) → pythonic text`. Both ATS and pythonic
are SURFACE forms of the same constructs, so it's a **surface→surface transliteration**: walk the
stock L0 declaration tree, emit the pythonic spelling of each node. Then OUR parser re-parses that
pythonic and lowers to L2 — and for correctness we diff the resulting codegen against stock.

## Scale + corpus (the port target)
- **Compiler** = `srcgen2/{SATS,DATS,UTIL}/**` — **210 files / ~178k lines** (the trans01→12→23→2a→3a
  passes; biggest are `trans12_decl00.dats` 4845, `trans12_dynexp.dats` 4457, `trans2a_dynexp.dats` 4178).
- **Real prelude** = `/Users/qcfu/Projects/srcgen1/prelude/` — **130 files / ~62.5k lines** (the FFI,
  fixity, abstract types actually live here; `srcgen2/prelude/` is a 45-file `#include` shim).
- **~340 files / ~241k lines total.** First round-trip CORPUS = the prelude (smaller, exercises FFI/
  fixity/abstract types); then the compiler; then the fixpoint.

## ★ The de-risk — the feared categories are mostly ABSENT in the actual corpus ★
Empirical counts over the compiler + both preludes:
- **NO `%{ C %}` blocks anywhere (0).** ATS3 self-hosts with zero inline C. FFI is *name-binding*:
  `#extern fun NAME{a:t0}(…): T = $extnam()` + `#impltmp NAME<a> = XATS000_NAME` per-backend
  dispatch; the per-backend files (`prelude/DATS/CATS/{C,JS,PY}/`) are PURE ATS shims, not raw C.
  ⇒ **no C-block renderer / raw-block lexer mode needed.**
- **NO real macros (0 `macdef`/`macrodef` bodies).** `#define` (256) is purely named constants /
  bit-flags (`#define KINFIXL 1`, `#define BOXKIND 0x001`). ⇒ map `#define`→ typed `const`/enum;
  **no macro-expansion engine needed.**
- **`#if` (25) is backend-selection only** — `#if defq(_XATS2JS_) … #endif` picking the JS/PY/C
  prelude. No `#then`/`#elif`/`#else` arithmetic. ⇒ a small **build-flag/`defq` selector**, not a
  general preprocessor.

## The REAL backlog — mundane, high-volume, ranked by usage
| construct | occ (target) | covered? | work |
|---|---|---|---|
| `where … { … }` | **2394** / 155 files | 🟡 NO | design scoping surface + lower (`D0Ewhere`→`D2Ewhere`) |
| `#typedef` / `#sexpdef` | 2035 | ✅ mostly (`type`) | verify hash-form round-trips |
| `#symload` | 2012 | ✅ (`@overload`) | verify per-file re-export volume |
| `local … in … end` | **1141** / 78 files | 🟡 NO | design surface (`D2Clocal0` lowering EXISTS, used for import-scoping — surface-only gap) |
| `#impltmp` | 934 | ✅ (`@impl[…]`) | verify template-impl hash-form |
| `#include` | 408 | 🟡 NO | textual-include / module story (build-time) |
| `#extern` + `$extnam` FFI | 335 / 665-in-prelude | 🟡 partial | round out foreign-name binding (`#extern…=$extnam()`, `#impltmp`) |
| fixity `#infixl/#infixr/#prefix/#nonfix` | ~40 / in `fixity0.sats` | 🟡 NO | pythonic fixity DSL + make our fixed Pratt table SOURCE-CONFIGURABLE |
| `#define` constants | 256 | 🟡 NO | → typed `const`/enum surface |
| `#if defq(…)` | 25 | 🟡 NO | build-flag selector |

## Fidelity gaps — round-trip LOSSINESS to fix (faithful demands these)
1. **Effect-annotated arrows** — `f0unarrw` carries an effect/kind list inline: `-<cloref1>`,
   `-<fun1>`, `=<lin>`, etc. (`dynexp0.sats:571`). The compiler uses these PERVASIVELY in fn
   signatures; our `PyTfun` is bare `(A)->B` with no effect slot. **Needs a pythonic arrow-effect
   spelling.** (We already lower closures as uniform cloref, but the explicit annotations must round-trip.)
2. **Flat/boxed/linear tuple & record variants** — `@(…)`/`$(…)`/`@{…}`/`${…}` pack box/flat/linear
   into the `T_TRCD10/20` token int (`lexing0.sats:168`). Our surface has ONE tuple + ONE record
   form ⇒ lossy. Need the prefix variants.
3. **Keyword↔kind-int decoding (pretty-printer side)** — `fun`/`fn`/`fnx`/`prfun`/`castfn` are ALL
   `D0Cfundclst`+`funkind`; `val`/`prval` all `D0Cvaldclst`+`valkind`; `case`/`case+`/`case-` via
   `caskind`. The pretty-printer must read the token's KIND enum (`xbasics.sats:143-247`) to recover
   which keyword to emit — a naive node→keyword map is impossible.
4. **`(a;b)` seq vs `(a,b)` tuple vs `(a|b)` prop-bar** share `D0Elpar`, distinguished by the
   RPAREN-cons terminator — pretty-printer inspects the tag.

## Long tail (low/zero count — defer, error-cleanly if hit)
`fix`/`fix@` recursive lambdas, `absopen`/`abssort`/`static`, `castfn` (1), `$exists{…}`,
`$showtype`/`$d2ctype`, `datasort` (needs L1), `@with` (no `D2CLScls` slot), `sif`/`scaseof`,
`$effmask` — none appear (or appear once) in the corpus; the pretty-printer should emit a clean
"unsupported construct" marker rather than silently dropping, so coverage gaps are visible.

## Design agenda (decorator-consistent, to settle BEFORE porting — "design once, no debt")
1. **Scoping**: `where` + `local…in…end` (highest leverage — 3535 combined occurrences).
2. **Fixity**: a pythonic fixity-declaration surface + source-configurable operator table.
3. **Arrow effects**: spelling for `-<cloref1>`/`-<fun>`/etc.
4. **FFI**: `#extern…=$extnam()` + `#impltmp` foreign-name binding (round out Batch B).
5. **Constants / `#define`**: typed `const`/enum.
6. **Tuple/record variants**: flat/boxed/linear prefixes.
7. **Include / module story**: `#include` + `#staload`/`dynload` build graph.

## Verification ladder
1. **Per-file round-trip**: pretty-print `F` → re-parse → compile both to codegen → DIFF vs stock.
2. **Corpus**: round-trip the prelude (130 files), then the compiler (210), each file a regression test.
3. **Fixpoint**: pythonic-built compiler compiles the pythonic compiler source; stage2==stage3 ⇒ self-hosting, parity PROVEN.

## Phased plan
- **P0 (design)**: settle the design-agenda surface (esp. scoping, fixity, arrow-effects) — workshop like A/B/C.
- **P1 (parser breadth)**: implement the settled surface in our parser+lowering (where/local/fixity/effects/FFI/consts/tuple-variants), each spike→wire→regress.
- **P2 (pretty-printer)**: build the L0→pythonic emitter, validated by round-tripping the prelude corpus file-by-file (diff codegen vs stock).
- **P3 (compiler round-trip)**: round-trip all 210 compiler files.
- **P4 (fixpoint)**: build the pythonic compiler with itself; reach stage2==stage3.
