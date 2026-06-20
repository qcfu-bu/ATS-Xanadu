# Lowering map — Python surface → ATS3 level-2 AST

> Companion to **PYTHON-FRONTEND-PLAN.md**. This is the implementer's reference:
> the construct-by-construct target table, the recipes for building L2 leaves and
> entities, and the `trans12` code shapes to mirror.
>
> Signatures/arities below are transcribed from the SATS but **re-check them
> against the live source at implementation time** — anchor on the *named*
> functions, not the line numbers. Code blocks are **illustrative ATS3-shaped
> pseudocode**, written to read like `trans12_*.dats`; they are not literal.

---

## 0. Conventions

- `loc` = the **Python** source `loctn` for the construct (§2.4). Thread it into
  every node; this is what makes diagnostics land on the `.py` file (plan §6.3).
- `env` = the live `tr12env` (plan §4). Lookups fall through to the prelude.
- `d2exp(loc, NODE)` = `d2exp_make_node(loc, NODE)` (symload `d2exp`). Same for
  `d2pat`, `d2ecl`, `s2exp`. Convenience makers like `d2exp_var(loc, d2v)` exist
  and are preferred where present (`DATS/dynexp2.dats`).
- `npf = -1` everywhere in v1 (no proof args; plan §6.7).

---

## 1. Mapping tables

### 1.1 Expressions (`pyexp` → `d2exp`)

| Python surface | L2 node | Notes |
|---|---|---|
| `name` | `D2Evar d2v` / `D2Econ d2c` / `D2Ecst d2c` / `D2Econs`/`D2Ecsts`/`D2Esym0` | resolve via `tr12env_find_d2itm`; branch on the `d2itm` (§3.1, §4.A) |
| `42` | `D2Eint tok` or `D2Ei00 n` | `tok = token_make_node(loc, T_INT01 "42")`; prefer unboxed `D2Ei00` when value known |
| `3.14` | `D2Eflt tok` / `D2Ef00 f` | `T_FLT01 "3.14"` |
| `"s"` | `D2Estr tok` / `D2Es00 s` | `T_STRN1_clsd("\"s\"", len)` — quotes included in the lexeme |
| `'c'` | `D2Echr tok` / `D2Ec00 c` | `T_CHAR2_char "'c'"` |
| `true` / `false` | `D2Ebtf sym` / `D2Eb00 b` | lowercase literal keywords; `sym = symbl_make_name "true"`/`"false"` |
| `f(a, b)` | `D2Edapp(d2f, -1, [d2a, d2b])` | use `d2exp_dapp(loc, d2f, -1, args)`; empty arg list → `D2Edap0` |
| `a + b`, `a < b`, `-a`, `a and b` | `D2Edapp(D2Ecst op, -1, args)` | resolve the operator **name** like any identifier (§3.4) |
| `lambda a, b: e` | `D2Elam0(tok, f2args, sres, arrw, body)` | params bound in a `pshlam0` scope (§4.D) |
| `if c: t elif … else e` | `D2Eift0(c, Some t, Some e)` | a **value**; nest `D2Eift0` for `elif`; missing `else` → `None` |
| `match e: case P: r …` | `D2Ecas0(tok, d2e, clauses)` | `tok` = match-kind token; clauses are `d2cls` (§1.2 / §4) |
| `(a, b)` / `a, b` | `D2Etup0(-1, [a, b])` | boxed/flat tuple-kind via `D2Etup1(tok, …)` if a sigil is chosen |
| `{l: a, m: b}` | `D2Ercd2(tok, -1, [D2LAB(l,a), …])` | record; labels via `label` (`xlabel0.sats`) |
| `e.field` | `D2Eproj(tok, d2rxp_new1 loc, lab, d2e)` | or `D2Edtsel` for datatype-field selection (Q3, plan §12) |
| block / suite | tail expression, with leading `val`s as `D2Elet0` | a suite of stmts = `let <vals> in <tail-exp>`; see §1.3 |
| `return e` | the enclosing block's tail value | `return` marks the block's result; no distinct node |
| `e1; e2` (sequencing) | `D2Eseqn([e1], e2)` | for side-effecting prefix exprs |
| `x: T` (annotated expr) | `D2Eannot(d2e, s1e, s2e)` | `s2e` = lowered type (§1.4); `s1e` may be a none/wrapper |
| `raise e` / `try … except` | `D2Eraise` / `D2Etry0` | post-v1 unless exceptions are in scope early |

### 1.2 Patterns (`pypat` → `d2pat`)

| Python surface | L2 node | Notes |
|---|---|---|
| `x` (binder) | `D2Pvar d2v` | `d2v = d2var_new2_name(loc, symbl_make_name "x")` — a **fresh** var (§3.1); use `d2pat_var(loc, d2v)` |
| `_` | `D2Pany()` | wildcard |
| `C` / `C(p, q)` | `D2Pcon d2c` / `D2Pdapp(D2Pcon d2c, -1, [p,q])` | constructor resolved via `tr12env_find_d2itm` → `D2ITMcon`; unresolved-overloaded → `D2Pcons(d2rpt_new1 loc, d2cs)` |
| `(p, q)` | `D2Ptup0(-1, [p,q])` | tuple pattern |
| `{l: p, …}` | `D2Prcd2(tok, -1, [D2LAB(l,p),…])` | record pattern |
| `42` / `"s"` / `true` | `D2Pint`/`D2Pstr`/`D2Pbtf` | literal patterns (token-wrapped like exprs) |
| `p as x` | `D2Prfpt(p, tok, D2Pvar d2v)` | as-pattern |
| `p: T` | `D2Pannot(p, s1e, s2e)` | annotated pattern |

> **Binding rule:** every `D2Pvar` in a pattern is a fresh `d2var`. After lowering
> a binding pattern, register it with `tr12env_add0_d2pat(env, d2p)` so the
> pattern's variables are visible in the appropriate scope (§4.C).

### 1.3 Declarations / statements (`pydecl` → `d2ecl`)

| Python surface | L2 node | Notes |
|---|---|---|
| `x = e` | `D2Cvaldclst(tok, [d2valdcl])` | `d2valdcl_make_args(loc, d2pat, TEQD2EXPsome(eqtok, d2e), WTHS2EXPnone())`; bind pattern (§4.C) |
| `def f(args): body` (group) | `D2Cfundclst(tok, tqas, d2csts, [d2fundcl…])` | name→`d2var`, recursion-aware binding; `d2csts` only for generics (§4.F) |
| `lambda …` (expr position) | (see `D2Elam0`, §1.1) | — |
| `match`/`case` clause | `d2cls`: `D2CLScls(D2GPTpat d2p, d2body)` or `D2GPTgua(d2p, guards)` | clause pattern is its own scope: bind pattern vars before lowering the body |
| `type Foo(...) = C1 | C2(...)` | `D2Cdatatype(d1ecl, [s2cst…])` | create the type `s2cst` + each `d2con`; register cons (§3.3, §4.G) |
| `type Foo = T` (alias) | `D2Csexpdef(s2cst, s2e)` | a static definition |
| `import M` / `from M import *` | `D2Cinclude(sd, tok, g1exp, …)` / `D2Cstaload(sd, tok, g1exp, …)` | choose include vs staload by surface form; dependency resolved from disk |
| local block / `where` | `D2Clocal0(head, body)` / `D2Ewhere(e, decls)` | push/pop scope around decls (§4.E) |
| top-level suite | `optn_cons(d2eclist)` | the list handed to `d2parsed_make_args` |

**Declaration record shapes** (build via the `_make_args` makers,
`DATS/dynexp2.dats`):

```
d2valdcl_make_args(loc, dpat:d2pat, tdxp:teqd2exp, wsxp:wths2exp) : d2valdcl
d2vardcl_make_args(loc, dpid:d2var, vpid:d2varopt, sres:s2expopt, dini:teqd2exp) : d2vardcl
d2fundcl_make_args(loc, dpid:d2var, farg:f2arglst, sres:s2res, tdxp:teqd2exp, wsxp:wths2exp) : d2fundcl
```
Helpers: `teqd2exp` = `TEQD2EXPnone() | TEQD2EXPsome(token, d2exp)`;
`wths2exp` = `WTHS2EXPnone() | WTHS2EXPsome(token, s2exp)`;
`s2res` = `S2RESnone() | S2RESsome(s2eff, s2exp)` (return-type signature, §1.4);
`f2arg` node = `F2ARGdapp(int npf, d2patlst) | F2ARGsapp(s2varlst, s2explst) | F2ARGmets(s2explst)`.

### 1.4 Types (`pytyp` → `s2exp`)

| Python surface type | L2 static node | Notes |
|---|---|---|
| `Int`, `Bool`, `String` | `S2Ecst s2c` | surface names (capitalized) resolve via `pyrt`; `tr12env_find_s2itm(env, sym)` → `S2ITMcst [s2c,…]` → `s2exp_cst(s2c)` (§3.5) |
| type var `a` (in `def f[a]…`) | `S2Evar s2v` | `s2v` created at the binder (`s2var_make_name`), bound in scope |
| `F[a, b]` / `List[Int]` | `S2Eapps(s2f, [s2a, s2b])` | `s2exp_apps(loc, s2f, args)` |
| `(A, B) -> C` | `S2Efun1(f2cl, -1, [A,B], C)` | `s2exp_fun1_full(F2CLfun, -1, args, res)`; closures use `F2CLclo …` |
| tuple `(A, B)` | `S2Etrcd(knd, -1, [A,B])` | record type with name labels; tuple with int labels |
| index literal (the `0` in `int(0)`) | `S2Eint n` | `s2exp_int n` |
| generic header `def f[a, b](…)` | wrap result in `S2Euni0([a,b], [], body)` | universal quantification `{a,b:t@ype} …` |
| escape hatch `s"{ … ATS … }"` | (delegate) | parse+resolve the embedded ATS static fragment with the stock static path; splice the resulting `s2exp` (plan §8.4) |

Prebuilt sorts for entity creation (`SATS/staexp2.sats`, `DATS/staexp2_inits0.dats`):
`the_sort2_type` (`t@ype`), `the_sort2_bool`, `the_sort2_int0`, `the_sort2_strn`,
`the_sort2_prop`, … Use these as the `sort2` argument when making `s2cst`/`s2var`.

---

## 2. Leaf construction recipes

### 2.1 Tokens (for literal nodes)

L2 literal nodes carry an ATS `token`. Synthesize one:

```
val tok = token_make_node(loc, T_INT01("42"))     // symload `token`; SATS/lexing0.sats:352
```

tnode constructors for literals (`SATS/lexing0.sats`):
`T_INT01 strn` (base-10 int), `T_FLT01 strn` (float), `T_STRN1_clsd(strn, sint len)`
(string, **quotes included**, `len` = byte length), `T_CHAR2_char strn` (char),
identifiers `T_IDALP strn` (alnum) / `T_IDSYM strn` (symbolic).

> Prefer the **unboxed** literal nodes where the value is already known —
> `D2Ei00 of sint`, `D2Ef00 of dflt`, `D2Es00 of strn`, `D2Eb00 of bool`,
> `D2Ec00 of char` — they skip token synthesis entirely.

### 2.2 Symbols (identifier keys)

```
val sym = symbl_make_name("foo")     // strn → sym_t ; SATS/xsymbol.sats
```

`sym_t` is the key for every `tr12env_find_*` lookup and the `name` field of every
entity. Operators are just symbols too: `symbl_make_name("+")`.

### 2.3 Labels (record/tuple fields, projections)

Field labels are `label` values (`SATS/xlabel0.sats`): integer labels for tuples,
name labels for records. Build them from the field name (`LABsym(sym)`) or index
(`LABint(i)`), matching the `l2d2e`/`l2d2p` = `D2LAB(label, elt)` shape.

### 2.4 Locations

```
postn = POSTN(ntot, nrow, ncol)               // all 0-based; ncol in UTF-8 bytes
loctn = loctn_make_arg3(lcsrc, pbeg, pend)    // half-open [pbeg, pend)
lcsrc = LCSRCfpath(fpath) | LCSRCsome1(strn) | LCSRCnone0()
```

The lexer produces these directly from the Python source; the parser/lowerer just
**propagate and combine** them (`loc1 + loc2` spans a range). Use
`loctn_dummy()` only for nodes with no surface origin (plan §6.3).

---

## 3. Entity construction & lookup

### 3.1 `d2var` — a bound (local) variable

```
val d2v = d2var_new2_name(loc, symbl_make_name("x"))   // SATS/dynexp2.sats:592
```

Fresh stamp; `sexp`/`styp` filled later by the type-checker. Use it both at the
binding site (in a `D2Pvar`/param) and at every use site (`D2Evar`) — but in the
direct-to-L2 design, **use sites are produced by lookup**, which returns the same
`d2var` you bound: resolve the name, get `D2ITMvar d2v`, emit `d2exp_var(loc, d2v)`.

Bind into the current scope so later uses resolve:
`tr12env_add0_d2var(env, d2v)` (single) / `tr12env_add0_d2pat(env, d2p)` (a
pattern's vars) / `tr12env_add0_f2arg(env, f2a)` (a function arg).

### 3.2 `d2cst` — a top-level constant / function name

`trans12` makes top-level `fun` names as `d2var`s and additionally builds a
`d2cst` **only when the definition is generic** (has template/static params):

```
val d2c = d2cst_make_dvar(tknd, d2v, tqas)     // from an existing d2var ; SATS/dynexp2.sats:505
// or, for an extern/spec'd constant:
val d2c = d2cst_make_idtp(tknd, dpidTok, tqas, sexp)
```

For the Pythonic skin, a non-generic `def f` binds `f` as a `d2var` (mirroring
`trans12`); only generic `def f[a]…` produces a `d2cst` registered with
`tr12env_add1_d2cst`.

### 3.3 `d2con` + datatype types

A datatype decl creates the type constant and its constructors:

```
val s2c   = s2cst_make_idst(loc, symbl_make_name "Foo", the_sort2_type)   // the type
val d2con = d2con_make_idtp(conTok, tqas, conSexp)                        // each constructor
val ()    = d2con_set_ctag(d2con, tag)                                    // tag like trans12
val ()    = tr12env_add1_d2con(env, d2con)                               // register so uses resolve
```

Mirror `trans12_decl00.dats` datatype handling for the ordering: make the type
`s2cst`(s) first, then process the constructor body (which creates the `d2con`s),
then finalize. Constructor patterns/uses then resolve via `tr12env_find_d2itm` →
`D2ITMcon`.

### 3.4 Operators & precedence

The Python parser **owns precedence** (Pratt) and emits *already-grouped*
application trees, so there is **no ATS fixity involved** — a major simplification
versus the L0 path. Each operator is lowered as a normal identifier reference to a
prelude `d2cst`:

```
a + b   →   D2Edapp(resolve("+"),  -1, [a, b])
-a      →   D2Edapp(resolve("~"|"neg"), -1, [a])   // pick the prelude unary name
a and b →   D2Edapp(resolve("&&" | "andalso-equivalent"), -1, [a, b])  // or D2Eift0 for short-circuit
```

where `resolve(op) = tr12env_find_d2itm(env, symbl_make_name(op))`. Maintain a
**surface-operator → prelude-name** table in `SURFACE-GRAMMAR.md` (open item Q4,
plan §12). Where Python has an operator with no prelude counterpart, either map it
to a library function call or define the operator in a small prelude shim. Note
`and`/`or` are **short-circuit**, so prefer lowering them to `D2Eift0` rather than
a strict call.

### 3.5 `s2cst` / `s2var` — types and type variables

```
val s2c = s2cst_make_idst(loc, sym, sort2)     // create a fresh type constant
val s2v = s2var_make_name(sym)                 // a type variable (sort filled later)
//        s2var_make_idst(sym, sort2)          // …or with an explicit sort
```

Resolve a prelude type name to its `s2cst`:

```
val opt = tr12env_find_s2itm(env, symbl_make_name "int")   // falls through to prelude
case+ opt of
| ~optn_vt_cons(S2ITMcst(s2cs)) => s2exp_cst(list_head s2cs)   // → S2Ecst
| ~optn_vt_cons(S2ITMvar(s2v))  => s2exp_var(s2v)
| ~optn_vt_nil()                => (* emit an unbound-type error node *) ...
```

---

## 4. The `trans12` templates to mirror

These are the *exact* code shapes `pylower` reproduces (walking PyAST instead of
L1). Open the cited `trans12_*.dats` beside the new `pylower_*.dats` file.

**A. Identifier reference** — `trans12_dynexp.dats:1920-2037`
```
val dopt = tr12env_find_d2itm(env, sym)
case+ dopt of
| ~optn_vt_nil()       => (* unbound: emit error node, keep going *)
| ~optn_vt_cons(d2i1)  =>
  case+ d2i1 of
  | D2ITMvar d2v  => d2exp_var(loc, d2v)
  | D2ITMcon d2cs => if list_singq d2cs then d2exp_con(loc, d2cs.head()) else d2exp_cons(loc, d2cs)
  | D2ITMcst d2cs => if list_singq d2cs then d2exp_cst(loc, d2cs.head()) else d2exp_csts(loc, d2cs)
  | D2ITMsym(_, dpis) => d2exp_sym0(loc, d2rxp_new1 loc, (*d1e proxy*), dpis)
```

**B. Application** — `trans12_dynexp.dats:2557-2607`
```
val d2f   = pylower_exp(env, pyf)
val d2es  = pylower_explst(env, pyargs)
d2exp_dapp(loc, d2f, ~1, d2es)         // npf = -1
```

**C. `val` binding** — `trans12_decl00.dats:2766-2833`
```
val d2p = pylower_pat(env, pypat)               // fresh D2Pvar(s)
val () = if recq then tr12env_add0_d2pat(env, d2p)   // recursive: bind first
val d2e = pylower_exp(env, pyrhs)
val () = if ~recq then tr12env_add0_d2pat(env, d2p)  // else bind after
d2ecl(loc, D2Cvaldclst(tok, list_sing(d2valdcl_make_args(loc, d2p, TEQD2EXPsome(eqtok, d2e), WTHS2EXPnone()))))
```

**D. Lambda / `def` params** — `trans12_dynexp.dats:3238-3283`
```
val () = tr12env_pshlam0(env)
val f2as = pylower_params(env, pyparams)         // each param → fresh d2var
val () = tr12env_add0_f2arglst(env, f2as)
val sres = pylower_sres(env, pyret)
val body = pylower_exp(env, pybody)
val () = tr12env_poplam0(env)
d2exp(loc, D2Elam0(tok, f2as, sres, arrw, body))
```

**E. `let` / block / `local`** — `trans12_dynexp.dats:2878-2942`
```
val () = tr12env_pshlet0(env)
val d2cs = pylower_eclist(env, pydecls)          // these bind
val d2e1 = pylower_exp(env, pybody)
val () = tr12env_poplet0(env)
d2exp(loc, D2Elet0(d2cs, d2e1))
```

**F. `def` group (recursion-aware)** — `trans12_decl00.dats:2898-3027`
```
val d2vs = list_map(names) (\n. d2var_new2_name(n.loc, symbl_make_name n.text))
val () = if recq then tr12env_add0_d2varlst(env, d2vs)      // recursive: names visible in bodies
val () = tr12env_pshlam0(env)
val tqas = pylower_tqaglst(env, pygenerics)                 // generic params, if any
val () = tr12env_add0_tqas(env, tqas)
val d2fs = pylower_fundclist(env, d2vs, pyfuns)             // lower each body
val () = tr12env_poplam0(env)
val () = if ~recq then tr12env_add0_d2varlst(env, d2vs)
val d2cs = if list_consq tqas then list_map(d2vs)(\v. d2cst_make_dvar(tok, v, tqas)) else nil
val () = if list_consq tqas then tr12env_add1_d2cstlst(env, d2cs)
d2ecl(loc, D2Cfundclst(tok, tqas, d2cs, d2fs))
```

**G. datatype** — `trans12_decl00.dats:3117-3168` (see §3.3 for the entity calls).

**Driver** — `trans12.dats:528-556` (mirror in `pyfront.dats`, plan §5.4):
make env → lower decl list → `tr12env_free_top` → `d2parsed_make_args`.

---

## 5. Worked example

Surface:
```python
def double(x: Int) -> Int:
    return x + x
```

Lowering sketch (one non-recursive `def`, one param, typed):
```
// names
val symDouble = symbl_make_name "double"
val d2vDouble = d2var_new2_name(locDouble, symDouble)

// enter function scope, bind the parameter
val () = tr12env_pshlam0(env)
val symX  = symbl_make_name "x"
val d2vX  = d2var_new2_name(locX, symX)
val s2X   = (* lower `Int`; resolve_type looks up the surface name via pyrt *) s2exp_cst(resolve_type "Int")
val f2a   = f2arg(locParams, F2ARGdapp(~1, list_sing(d2pat(locX, D2Pannot(d2pat_var(locX,d2vX), s1none, s2X)))))
val ()    = tr12env_add0_f2arg(env, f2a)

// return type signature
val sres  = S2RESsome(S2EFFnone(), s2exp_cst(resolve_type "Int"))

// body: x + x   →   D2Edapp("+", -1, [x, x])
val d2vXuse = (case tr12env_find_d2itm(env, symX) of ~optn_vt_cons(D2ITMvar v) => v)
val plus    = (case tr12env_find_d2itm(env, symbl_make_name "+") of ~optn_vt_cons(D2ITMcst cs) => d2exp_cst(locPlus, list_head cs))
val body    = d2exp_dapp(locBody, plus, ~1, [ d2exp_var(locX1, d2vXuse), d2exp_var(locX2, d2vXuse) ])

val () = tr12env_poplam0(env)

// non-recursive: bind the function name AFTER the body
val () = tr12env_add0_d2var(env, d2vDouble)

// assemble the d2fundcl + decl
val dfun = d2fundcl_make_args(locDouble, d2vDouble, list_sing(f2a), sres, TEQD2EXPsome(eqtok, body), WTHS2EXPnone())
val decl = d2ecl(locDouble, D2Cfundclst(funTok, (*tqas*)nil, (*d2cs*)nil, list_sing(dfun)))
```

That `decl`, collected into the top-level list and wrapped by
`d2parsed_make_args`, is handed to `d3parsed_of_trans23` — which infers `x: Int`,
checks `x + x : Int` against the `-> Int` signature, and (codegen on) emits the JS
function. A type error (say `-> Bool`) surfaces as a `D3Et2pck` `…errck` node whose
`.lctn()` is `locBody` — i.e. the **Python** `return x + x` line.

---

*See PYTHON-FRONTEND-PLAN.md §10 for how these pieces are sequenced into
milestones, and §11 for the differential-oracle tests that validate each lowering
against the stock ATS3 frontend.*
</content>
