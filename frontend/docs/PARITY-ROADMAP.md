# Parity roadmap — Python surface → canonical ATS3

> **Goal:** the Python surface can express everything canonical ATS3 can (parse +
> typecheck end-to-end). Tracks the remaining gaps from the 2026-06-20 gap analysis
> (static / dynamic / declarations). Each feature: **spike** (build a hand-made L2 to
> `nerror=0`, if the construction is risky) → **implement** (lexer/parser/AST/elab/
> lower) → **verify** (real-pipeline test) → **commit**. The deep proof/view/dependent
> machinery (Batch D) is the ATS soul and the hardest; it comes last.

Legend: ✅ done · 🔨 in progress · ⬜ todo · ⏸ specialist/deferred

## Already covered (prior + this campaign)
Functions; control flow (`if`/`while`/`for`/`break`/`continue`/`return`/`match`+guards/
loop-`else`); operators; tuples, records, lists; `enum`/`struct`/`type` ×
monomorphic/parametric × boxed/linear/flat modes + param sorts; **function types**
`(A)->B`; **tuple types** `(A,B)`; **as-patterns** `p as x`; **multi-file `import`**
(scoped staload, no LSP leak); **closures** (uniform `cloref`) + **`@func`** non-capture
check. All live in the deno LSP with diagnostics on `.psats`/`.pdats` spans.

## Batch A — imperative / term core
- ✅ **Exceptions** — `exception E(T)` / `raise` / `try…except` (`cd59134a0`). Spike-verified; also fixed the nullary-con-as-value bug (`pl_con_value`→`D2Edap0`).
- ⬜ **`var` / mutation** — `var x = e`, `x := e`, `!p` deref, `&x` addr (`D2Cvardclst` `:1522`, `D2Eassgn` `:1061`). The address/view world — likely a spike (linearity).
- ⬜ **`where` / `local…in…end`** — post-hoc + private decls (`D2Ewhere` `:1054`, `D2Clocal0` `:1455`).
- ⬜ **`op` qualified name** — operator as a first-class value (`reduce(xs, op+)`) (`T_OP1` `lexing0.sats:181`).

## Batch B — abstraction / modularity (library authors)
- ✅ **Abstract types** — `abstype` + `assume` (`7dcb97706`). Opacity holds at typecheck; `@unboxed abstype`→flat. (`@linear absvtype`/`absprop` deferred.)
- ⬜ **`stadef` / `sortdef` / `stacst`** — static-level definitions (`D2Csexpdef`/`D2Csortdef`/`D2Cstacst0`).
- ⬜ **`#symload` / overloading** — overload a name onto multiple impls (`D2Csymload` `:1476`).
- ⬜ **`implement` / `#implfun`** — user surface to implement a template/extern fn (`D2Cimplmnt0` `:1542`).
- ✅/⏸ **FFI** — `extern def foo(…)->T` signature-only DONE (`7dcb97706`, `D2Cextern`→bodyless `d2cst`). Full `%{…%}` C-code + `$extnam` ⏸ deferred to codegen-era (the `#`/`$`/`%{` lexer classes collide with our `#`-comment).

## Batch C — fixity / macros / lexical
- ⬜ **Fixity** — `infixl`/`infixr`/`prefix`/`postfix`/`nonfix` (`D0Cfixity`). Interacts with our fixed Pratt table.
- ⬜ **Macros** — `macdef`, `#define`, `#if`/`#then`/`#else` (`D1Cmacdef`/`D1Cdefine`/`D1Cifexp`).
- ⬜ **`dynload` / `#include`** (`D2Cdyninit`/`D2Cinclude`).
- ⬜ **Lexical parity** — `//` line + `(* *)` block comments (alongside `#`-to-EOL); char/string escape decoding; `$`/`#`-identifier classes.

## ⚠ Batch D reality (investigation 2026-06-21) — the constraint solver does not exist
**This compiler tree has NO dependent-type checking and NO constraint solver** (verified at
source): `trans23`/`trans2a` have zero constraint/solve vocabulary; `srcgen2/xdeptck/` is an
empty README ("This will probably take a while :)"); the L2→L3 `stpize` ERASES the index layer
(`s2varlst_imprq` filters predicative `int`/`bool` vars; guards dropped; `T2Puni0`/`T2Pexi0` have
no prop slot — `statyp2.sats:319`); the only checker is a structural first-order unifier
(`unify00_s2typ`). **The STOCK compiler is in the same boat** — it parses + structurally-matches
indexed types but does NOT verify `n+1=m`/guards either. ⇒ **SYNTAX parity is achievable**
(express + lower the dependent surface to correct L2, matching what stock accepts); **SOUND
index/proof checking = building the solver inside the compiler (the unstarted `xdeptck/`), a
research project that EXCEEDS the canonical compiler — OUT OF SCOPE for "parity".** Stages 1–3
below = surface parity (Stage-0 spike required to navigate the erasure + the M5a `T2Pbas` hazard).

## Batch D — dependent types & proofs (the ATS depth) — STAGES 1–3 = syntax parity; Stage 4 (solver) out of scope
- ⬜ **Dependent indices** — `list(a, n)`, `int(i)` + the **index sub-language** (sort `int`/`bool`, arithmetic, comparisons) (`S2Eint` `staexp2.sats:579`, `PyTidx`). The largest gap.
- ⬜ **Quantifiers** — `{n:int}` universal, `[n:int | g]` existential + guards (`S2Euni0` `:636`, `S2Eexi0` `:632`; `s1qua` guard/var split `staexp1.sats:749`).
- ⬜ **Templates** — `{..}`/`<..>` on functions, `$`-implicit instantiation (`t1qag`/`t1iag` `dynexp1.sats:696/759`).
- ⬜ **`dataprop` / `dataview` / `datasort`** — proof/view/sort datatypes.
- ⬜ **Proofs** — `prfun`/`prval`/`praxi` (`FNKpr*`/`VLKprval`).
- ⏸ **Views** — `view` sort, at-views `a @ l`, linear patterns `!p`/`~p`/`@p` (the linear-memory frontier).
- ⏸ **Termination metrics** — `.<m>.` (totality proofs).

## Sort-vocabulary note (for Batch D naming)
Static `int`/`bool` are SORTS (index terms), NOT runtime types — name them **`SInt`/`SBool`**
on the surface to avoid the classic conflation with runtime `Int`/`Bool` (gap-analysis ruling).
`Type`/`Linear`/`Prop` for the type sorts; `View` reserved for the view sort.
