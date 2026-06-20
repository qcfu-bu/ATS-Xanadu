# ATS3 Python-surface frontend — design docs

This folder holds the design for a **new, alternative frontend** for the ATS3
(ATS-Xanadu) compiler that accepts a **Python-like surface syntax** (indentation
blocks, `def`, `match`, Pythonic call/operator forms) while reusing the existing
ATS3 type-checker, codegen, and tooling unchanged.

The frontend **lowers directly to the compiler's level-2 (L2) AST** — the
binding-resolved, pre-typecheck representation — and hands the resulting
`d2parsed` to the stock type-checker `d3parsed_of_trans23`. Everything from
type-checking onward (L3, template resolution, JS/C/Python codegen, the LSP
harvester) is reused verbatim.

## Read in this order

1. **[PYTHON-FRONTEND-PLAN.md](PYTHON-FRONTEND-PLAN.md)** — the plan: the L2 hook
   point and integration contract, the architectural decisions, the new
   lexer/parser/lowering components, the v1 surface scope, the codegen-to-JS
   path, milestones, tests, and risks.
2. **[LOWERING-MAP.md](LOWERING-MAP.md)** — the concrete reference: construct-by-
   construct *Python surface → L2 node* mapping tables, plus the recipes for
   synthesizing L2 leaves (tokens/identifiers/literals) and creating/looking-up
   entities (`d2var`/`d2cst`/`d2con`/`s2cst`) via the reused `tr12env`.
3. **[LOOP-DESUGARING.md](LOOP-DESUGARING.md)** — the imperative-surface elaborator:
   `let mut` and `while`/`for`/`break`/`continue`/`return`/loop-`else` desugared
   (control-flow-complete, in one shot) to tail-recursive functions over a
   threaded accumulator — which the JS backend turns back into real `while` loops.
4. **[SURFACE-GRAMMAR.md](SURFACE-GRAMMAR.md)** — the surface decisions log
   (Python/Scala fusion): `let`/`let mut` bindings, `=>` lambdas with block bodies,
   and the indentation/block-opener layout rule.

## Companion material (in `language-server/docs/`)

The LSP project already mapped the compiler internals this plan depends on. Treat
these as authoritative for the *back half* of the pipeline:

- `ATS3-COMPILER-PRIMER.md` — pipeline (`L0→L1→L2→L3`), the non-fail-fast
  `…errck` diagnostics model, the location model (0-based internal `postn`), the
  type model (`s2typ`), the JS FFI + compiler-linking build recipe (§10.5).
- `S2TYP-SURFACE-SYNTAX.md` — the type pretty-printer spec (useful when the
  Python surface needs to *print* types, e.g. for hover).

## Status

Planning only. No frontend code exists yet (`frontend/` currently contains only
`docs/`). The plan front-loads an end-to-end "tracer bullet" (M0) that proves the
hand-built-L2 → typecheck → JS spine before any lexer/parser is written.
</content>
</invoke>
