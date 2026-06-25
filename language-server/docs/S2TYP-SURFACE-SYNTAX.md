# `s2typ` → ATS3 surface syntax — pretty-printer spec

Authoritative mapping (grounded in the lexer/parser) for printing post-typecheck types
(`s2typ`, `SATS/statyp2.sats:264-340`) as ATS3 source syntax. The pretty-printer must be the
**inverse of `p1_s0exp`** (`srcgen2/DATS/parsing_staexp.dats`). No stock printer is
source-faithful (all emit debug `T2P…(…)`), so the grammar is the only reference.

## Grammar facts
- **Application** is `f(a, b)` — head then parenthesized comma-list. NOT juxtaposition `f a b`.
- **Function arrow** `->` (token `T_MSGT`). Effectful: `-<eff,…>`. Closures: `-<cloref>` / `-<cloptr>`.
- **Proof-arg separator `|`** comes from `npf`: first `npf` args precede `|`. `npf = -1` ⇒ no `|`
  at all; `npf = 0` ⇒ `(| a, b)`; `npf = k>0` ⇒ `(pf1..pfk | a, b)`.
- **Tuple/record sigils** (lexer-fused): flat `@(`/`@{`, boxed `#(`/`#{`, keyword `$tup`/`$rec`,
  ref `$tuprf`/`$recrf`. **No `'(`/`'{` in ATS3** — boxed uses `#`. Tuple vs record = integer
  labels vs name labels.
- **Existential `[ … ]`**, **universal `{ … }`**; quantifier vars `a,b:srt`.
- **Arg modifiers** `!t` (call-by-value lval), `&t` (by-ref), transition `bef >> aft`.
- **Fixity** (`srcgen2/DATS/xfixity.dats`): application prec **70** (left); arrow prec **10**
  (right-assoc). ⇒ parenthesize an argument or the arrow's **left arm** iff it is itself a
  function type (`T2Pfun1`).

## Node → surface form (the table)
Forward map evidence: `f0_impr` in `srcgen2/DATS/statyp2_utils1.dats:549-775`.

| Constructor | Surface form | Notes |
|---|---|---|
| `T2Pcst s2c` | constant name (friendly, see below) | `s2cst_get_name` |
| `T2Pvar s2v` | variable name | |
| `T2Papps(f, [a,b])` | `f(a, b)` | parenthesized; if head is `gint_type`/`gflt_type` with rep params, print just the width name |
| `T2Pfun1(f2cl, npf, args, res)` | `(pf \| a, b) -> r` | honor `npf` (`-1`=no bar, `0`=`(\| …)`); arrow flavor from `f2cl`; paren an arg/left-arm iff it's a `T2Pfun1` |
| `T2Pf2cl knd` | `F2CLfun`→`->`; `F2CLclo(1\|0)`→`-<cloptr>`; `F2CLclo(-1)`→`-<cloref>` | the arrow token in `T2Pfun1` |
| `T2Ptrcd(knd, npf, fields)` | tuple `@(a,b)`/`#(a,b)`; record `@{l=a, m=b}`/`#{…}` | branch on `trcdknd` (sub-table) + int-vs-name labels; honor `npf` `\|` |
| `T2Pexi0(vars, body)` | `[v1, v2] body` | quantifier prec 0; constraints already dropped |
| `T2Puni0(vars, body)` | `{v1, v2} body` | same |
| `T2Parg1(knd, t)` | `knd=0`→`t`; `1`→`!t`; `-1`→`&t` | only as a `T2Pfun1` arg |
| `T2Patx2(bef, aft)` | `bef >> aft` | only as a `T2Pfun1` arg |
| `T2Ptext(name, args)` | `$extype("name")` (or `name(args)` for hover; bare `name` if nullary) | from `$extype`/`$extbox` |
| `T2Plam1(vars, body)` | `lam(v1, v2) => body` | parameterized type defs |
| `T2Pxtv x` | solved → its `styp`; unsolved → `[#stamp]` | not user-written |
| `T2Ps2exp e` | delegate to the s2exp surface printer (int/bool/char/str literal or index term) | |
| `T2Ptop0 t` / `T2Ptop1 t` | `t?` / top-of `t` (value position: descend to `t`) | uninit / delinearized |
| `T2Plft t`, `T2Pnone1 t`, `T2Perrck(lvl,t)` | **transparent** — print inner `t` | wrappers |
| `T2Pnone0()` | `_` | |

### `trcdknd` sub-table (`xbasics.sats:320-336`)
| kind | tuple (int labels) | record (name labels) | boxity |
|---|---|---|---|
| `TRCDflt0` | `@(a, b)` | `@{l=a, m=b}` | flat |
| `TRCDbox0` / `TRCDbox1` | `#(a, b)` | `#{…}` | boxed (**linearity erased** — box0≡box1 in surface; `statyp2.sats:42-45`) |
| `TRCDbox2` | `$tuprf(…)` | `$recrf(…)` | ref-counted |
| `TRCDflt1 s` | named-flat | — | flat |

## Friendly constant names (grounded in `prelude/basics0.sats`)
Head `s2cst_get_name` → surface: `xats_void_t`→`void`, `bool_type`→`bool`, `char_type`→`char`,
`gflt_type`→`double`, `string_i0_tx`→`string`, `p1tr_tbox`→`ptr`, `p2tr_tbox`→`p2tr`,
`list_t0_i0_tx`→`list`, `list_vt_i0_vx`→`list_vt`, `optn_t0_i0_tx`→`optn`, `lazy_t0_tx`→`lazy`, …
⚠️ **All integer widths share head `gint_type`** — distinguish `int`/`uint`/`lint`/… by inspecting
the `_k` arg tag (`xats_sint_t`→int, `xats_uint_t`→uint, `xats_slint_t`→lint, … `basics0.sats:589-606`).
A head-name-only map collapses every int to `int`.

## Discrepancies in the current printer to fix
(`language-server/server/DATS/xats_lsp_check.dats:223-314` `typ_p`; JS map `CATS/xats_lsp_check.cats:53-81`)
1. `T2Ptrcd` printed as bare `(a,b)` — drops `@`/`#`/`$` sigil, tuple-vs-record, and record labels.
2. `npf`/proof `|` discarded in `T2Pfun1` and `T2Ptrcd`.
3. Arrow flavor (`f2cl`) ignored — always `->`.
4. `T2Parg1`/`T2Patx2` modifiers (`!`/`&`/`>>`) dropped.
5. Quantifiers `T2Pexi0`/`T2Puni0` print body only (drop `[…]`/`{…}`).
6. `T2Pf2cl` hard-codes `<cloref>`.
7. `prim_head_nameq` lists non-existent `void_type`/`string_type` (real: `xats_void_t`/`string_i0_tx`).
8. JS map has stale keys (`the_s2exp_void0`→`the_s2exp_void`, `lazy_t0_vx`→`lazy_t0_tx`); missing
   `p1tr_tbox`/`p2tr_tbox`/per-width int tags.
9. `T2Papps` doesn't special-case tuple-constructor heads.

## Round-trip verification
Wrap a printed type `T` as **`typedef _RT = T`** (a `typedef` body is exactly an `s0exp`, parsed by
`p1_s0exp`), run `trans01→trans12→trans23`, recover `_RT`'s `s2typ`, and compare to the original
with `unify00_s2typ_e1nv` (`statyp2.sats:590-594`). Lossy-by-construction (compare *up to* these,
which `unify00` already handles structurally): linearity (box0≡box1), dropped quantifier
constraints, unsolved `T2Pxtv`, `T2Pnone0`/`T2Perrck` placeholders. For a strict round-trip, print
the **resolvable** surface name (`uint`, `lint`) not the collapsed friendly `int`.

## Hover vs round-trip
Hover wants *readable* (friendly names, drop noise); round-trip wants *exact* (resolvable names,
keep quantifiers). Suggest one printer with a `mode` flag: `Hover` (friendly, may drop empty
quantifiers/top wrappers) vs `Exact` (round-trippable). Test in `Exact`, display in `Hover`.
