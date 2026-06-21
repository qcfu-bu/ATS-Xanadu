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
- ⬜ **Exceptions** — `exception E(T)` / `raise` / `try…except` (`D2Cexcptcon` `dynexp2.sats:1556`, `D2Eraise` `:1102`, `D2Etry0` `:1021`). Handlers reuse case-clause lowering.
- ⬜ **`var` / mutation** — `var x = e`, `x := e`, `!p` deref, `&x` addr (`D2Cvardclst` `:1522`, `D2Eassgn` `:1061`). The address/view world — likely a spike (linearity).
- ⬜ **`where` / `local…in…end`** — post-hoc + private decls (`D2Ewhere` `:1054`, `D2Clocal0` `:1455`).
- ⬜ **`op` qualified name** — operator as a first-class value (`reduce(xs, op+)`) (`T_OP1` `lexing0.sats:181`).

## Batch B — abstraction / modularity (library authors)
- ⬜ **Abstract types** — `abstype`/`abst@ype`/`absvtype`/`absprop` + `assume`/`#absimpl` (`D2Cabstype` `:1467`, `D2Cabsimpl` `:1471`). Opaque type + hidden rep.
- ⬜ **`stadef` / `sortdef` / `stacst`** — static-level definitions (`D2Csexpdef`/`D2Csortdef`/`D2Cstacst0`).
- ⬜ **`#symload` / overloading** — overload a name onto multiple impls (`D2Csymload` `:1476`).
- ⬜ **`implement` / `#implfun`** — user surface to implement a template/extern fn (`D2Cimplmnt0` `:1542`).
- ⬜ **FFI** — `extern` decls, `%{…%}` C-code, `$extnam` (`D2Cextern` `:1449`, `D2Cextcode` `:1510`). Needs lexer `$`/`#`/`%{` token classes.

## Batch C — fixity / macros / lexical
- ⬜ **Fixity** — `infixl`/`infixr`/`prefix`/`postfix`/`nonfix` (`D0Cfixity`). Interacts with our fixed Pratt table.
- ⬜ **Macros** — `macdef`, `#define`, `#if`/`#then`/`#else` (`D1Cmacdef`/`D1Cdefine`/`D1Cifexp`).
- ⬜ **`dynload` / `#include`** (`D2Cdyninit`/`D2Cinclude`).
- ⬜ **Lexical parity** — `//` line + `(* *)` block comments (alongside `#`-to-EOL); char/string escape decoding; `$`/`#`-identifier classes.

## Batch D — dependent types & proofs (the ATS depth)
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
