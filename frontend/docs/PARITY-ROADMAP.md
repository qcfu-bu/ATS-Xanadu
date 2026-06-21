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

## Batch D — dependent types & proofs (the ATS depth) — SYNTAX PARITY ACHIEVED (Stage 4 solver still out of scope)
All express + lower + STRUCTURALLY typecheck (nerror=0, matching stock); index/proof/view
obligations are NOT solver-verified — the constraint solver is unbuilt in stock too. See
`ADVANCED-SURFACE.md` for the full settled surface.
- ✅ **Dependent indices** — `SInt`/`SBool` index sorts, index args (`Vec[A,n]`/`SInt[n]`), arithmetic (`n+1`), guards (`{n|g}`) (DEP, DEP2). `the_s2exp_sint1`/static-op map.
- ✅ **Quantifiers** — `def f[n: SInt | g]` universal sugar + explicit `forall[n|g] T` / `exists[m|g] T` in types (`s2exp_uni0`/`s2exp_exi0`) + **subset sorts** `@sort type Nat = {a|g}` (`S2TEXsub`) (A-quant, `d8002a68a`).
- ✅ **Templates** — `@template[A] def foo[C]` (decl, `tqas` via `t2qag_make_s2vs`) / `@impl[Int] def` (`tias`) / `@inst[Int] foo(…)` (`d2exp_tapp`); resolution deferred to trtmp3b/3c (after tread3a), so all reach nerror=0 (A-template, `29d3794d5`). Negative control proves the instantiation is really typechecked.
- ✅ **`dataprop` / `dataview`** — `@prop`/`@view enum` (DEP2). `@sort enum` datasort ⏸ (needs L1; no-op past trans12 — low priority).
- ✅ **Proofs** — `@proof def`=prfun / `@proof let`=prval / `@proof @extern def`=praxi (STAT/PROOF). `@terminates[n]` totality metric (`F2ARGmets`) + `VCons{n}(…)` existential-unpack (`d2pat_sapp`) (C-proof, `9e9ae3906`). `@with` on case arms ⏸ DEFERRED (no per-clause withtype slot in `D2CLScls`).
- ✅ **Views / linear** — `A at l` at-views (`S2Eatx2`), `~p` consume (`D2Pfree`), `&x`/`!p` (`D2Eaddr`/`D2Eeval`), `:=>`/`:=:` move/swap (`D2Exazgn`/`D2Exchng`) (B-linear, `4094aa171`). Proof-linked bare-ptr deref ⏸ DEFERRED (needs view solver); `!p`-unfold + `@p` flat patterns ⏸ out of scope.

## Sort-vocabulary note (for Batch D naming)
Static `int`/`bool` are SORTS (index terms), NOT runtime types — name them **`SInt`/`SBool`**
on the surface to avoid the classic conflation with runtime `Int`/`Bool` (gap-analysis ruling).
`Type`/`Linear`/`Prop` for the type sorts; `View` reserved for the view sort.
