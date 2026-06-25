# #13a — dotted overloaded selectors: the missing `tread12` pass (and why it can't be added yet)

> **RE-DIAGNOSIS 2026-06-23 (current `tread12`-included pipeline).** Everything below this banner is
> the ORIGINAL investigation, written BEFORE `d2parsed_of_tread12` was committed to the M3 driver
> (`pyfront_m3.dats:144`, commit d7253f16b). `tread12` IS NOW in the pipeline in stock order
> (`tread12 → trans2a → trsym2b → t2read0 → trans23`). It did **not** close `staexp0`/`staexp2` as
> Stage 3 predicted. The precise residual is now characterized in the new section
> **"## RE-DIAGNOSIS: the residual is an overload-bucket unify under `#absimpl` (compiler's job)"**
> at the BOTTOM of this file. TL;DR of the re-diagnosis: the dotted-selector failure is NOT a
> pretty-print/desugar fidelity gap — our L2 is faithful (a direct call, an untyped-param receiver,
> and the no-`#absimpl` case all resolve; only the staloaded-con-binder + local-`#absimpl`-candidate
> intersection fails, inside the compiler's own `match2a_d2cst` overload unify). A scope-bounding
> "fix" (bounding the `private:` capture-rest body at the next sibling private) DOES close `staexp0`
> but **regresses 5 green files** (`dynexp1/2/3`, `statyp2`, `locinfo`) by scoping the GLOBAL
> `#absimpl` transparency those files legitimately rely on — so it is a workaround, reverted. Gate
> held at **163/163**, tree clean, files left uncovered (compiler's job).

Investigation of the residual **#13a overload-resolution** failure that blocks five bootstrap
compiler files from reaching `m3_nerror=0` on the M3 Pythonic round-trip.

- Working dir / `XATSHOME`: `/Users/qcfu/Projects/ATS-Xanadu`
- Probe recipe: `cd frontend && bash build-pp-corpus.sh --stadyn auto --reuse-bundle --out-dir BUILD/_p13 <file>`,
  then `node --stack-size=8801 BUILD/pyfront-m3.js <emitted>.pp.pdats` (grep `F2PERR0`/`F3PERR0`).
- Baseline (and final): `make -j8 pp-corpus-auto PP_STRICT=1` → **166 / 166**, total `# TODO(pp): 0`,
  zero `m3_nerror>0` rows in `BUILD/pp-corpus-make-auto/summary.tsv`. Tree clean (report-only).

## TL;DR

The dotted selector `x.NAME()` lowers (faithfully) to `D2Edapp(D2Esym0(NAME, dpis), [x])` — a
**full overload bucket `dpis`**, exactly what the stock parser emits (verified from the L2 dump,
see below). The frontend does **not** produce a dead unbound id; it produces the real overload
symbol, and the M3 driver already runs stock `trans2a → trsym2b → t2read0` to resolve it.

The bug is that the M3 driver is **missing one stock pass**: stock `trans03_from_fpath`
(`srcgen2/DATS/trans23.dats:87`) runs **`d2parsed_of_tread12`** *before* trans2a, and the M3
spike (`pyfront_m3.dats:135-143`) never ran it. `tread12` is not just an unbound-name checker:
`tread12_d2con` (`tread12_dynexp.dats:1050-1062`) `s2exp_stpize`s each constructor's sexp and
`d2con_set_styp`s it, establishing the **instantiated `xtyp`** that trans2a's pattern check
(`f0_dapp`) and trsym2b's `match2a_d2cst` read to learn a receiver's type and to match a
dotted-selector overload against it. Adding `d2parsed_of_tread12` in the stock order **does
resolve abstract-receiver selectors** that previously failed (proven: `trans12_decl00` 4 → 2,
two `.node()/.name()` selectors on `#abstbox` receivers now resolve).

**But `tread12` cannot be added wholesale**: it is the full L1→L2 read/check and is **stricter
than the M3 reduced pipeline about viewtypes / linearity** constructs the frontend lowers loosely.
Adding it **regressed 8 previously-green corpus files** (`xatsopt_tmplib` +60 errors,
`trtmp3c_myenv0` +14, `nmspace` +7 on `list_vt`/`_vt_free` linear functions, …). The 166 gate is
absolute, so the change was reverted. The fix is therefore **gated on making the frontend lowering
faithful enough that `tread12` accepts the 166 green files** — a frontend-lowering-fidelity task,
not an overload-resolution task.

## The mechanism (verified)

A dotted call `x.NAME()` is ATS sugar for the overloaded selector `NAME(x)` where `NAME` is
`#symload`'d across many types. `pl_selector_app` (`pylower_dynexp.dats:1365`, commit 40f8c8357)
lowers it to a first-arg application `D2Edapp(D2Edtsel(lab=NAME, dpis), [x])` when `NAME`'s bucket
`dpis` has > 1 candidate. The M3 driver then runs the stock post-passes, which resolve a dotted
selector **type-directed**:

1. trans2a `f0_dapp_dtsel` (`trans2a_dynexp.dats:2234`) rewrites
   `D2Edapp(D2Edtsel, [x])` → `D2Edapp(D2Esym0(NAME, dpis), [x])`, calls `f0_dapp_elses`.
2. `f0_dapp_elses` (`:2302`) builds `tfun = T2Pfun1([typeof(x)], tres)` from the receiver's
   trans2a'd type and unifies it into the `D2Esym0` node's `styp`.
3. trsym2b `f0_sym0` (`trsym2b_dynexp.dats:1090`) reads `t2p1 = sym.styp() = T2Pfun1([typeof(x)],_)`
   and runs `match2a_d2ptmlst(dpis, t2p1)`; per candidate, `match2a_d2cst` (`trsym2b_utils0.dats:147`)
   unifies the candidate's arg type against **`typeof(x)`**. The unique survivor is written into the
   `D2Esym0`'s `d2rxp` (`d2rxp_set_dexp`).
4. If the bucket narrows to **empty**, the `d2rxp` keeps `D2Enone0`; t2read0 `f0_sym0`
   (`t2read0_dynexp.dats:1631`) then `err := err+1` — the graceful `D2Eerrck` we observe.

The bucket IS present and full in the emitted L2 (refuting "the frontend produced a dead unbound
id"). The receiver `D2Evar(id0)` is the argument, the con-pattern binder is correctly bound, and
the 27-candidate `lctn` bucket is attached:

```
D2Esym0(D2RXP(D2Eerrck(...; D2Esym0(D2RXP(D2Enone0()); D1Eid0(lctn); $list())));   # drxp: failed-resolution result
        D1Eid0(lctn);
        $list( D2PTMsome(0; D2ITMcst($list(d0typ_get_lctn))), ... ,
               D2PTMsome(0; D2ITMcst($list(i0dnt_get_lctn))), ... ,
               D2PTMsome(0; D2ITMcst($list(token_get_lctn))) ))                      # full 27-candidate bucket
```

### Why some receivers resolve and some don't — and why `tread12` matters

`staexp0.dats:676` `S0QIDsome(tok, id0) => tok.lctn() + id0.lctn()` errcks on **`id0.lctn()`
only** (offs 26), never on **`tok.lctn()`** (offs 13). Both are con-pattern binders in one
expression; the only difference is the receiver type's head:

| binder | type | typedef | head | resolves? |
|---|---|---|---|---|
| `tok` | `token` | concrete | `T2Pcst(token)` | **yes** |
| `id0` | `i0dnt` | `#abstbox i0dnt_tbox` | `T2Pbas(i0dnt_tbox)` | **no (in M3); yes once con xtyp is stpized**|

The green corpus files using the same selectors (`trans12_dynexp.dats` alone has 188 uses) are
green because they select on receivers whose type is concrete *or* whose constructor's `xtyp` was
properly stpized by `tread12` in the full pipeline. **The M3 driver skipped `tread12`, so a
con-pattern field binder whose type is an abstract `#abstbox` is left with an un-stpized con `xtyp`;
the receiver type that flows into the selector match is then malformed for abstract heads, the
bucket fails to narrow, and t2read0 errcks.** This is the genuine #13a root — a **missing stock
pass in the M3 driver**, not a frontend resolution gap and not the armless-`T2Pbas`-unify of
CFAIL cluster C2.

> Earlier drafts mis-attributed the failure to the commented-out `T2Pbas` arm of `unify00_s2typ`.
> That arm is real, but it is **not** what blocks these selectors: adding `tread12` resolves
> abstract-`#abstbox` receivers (e.g. `d1tst`/`s2var` `.node()/.name()`) without touching any
> stock unify arm. The blocker is the un-stpized con `xtyp`, which `tread12` fixes.

### Proof that `tread12` is the right pass

Adding one line to the M3 driver — `val dpar = d2parsed_of_tread12(dpar)` immediately before
`d2parsed_of_trans2a`, mirroring `trans03_from_fpath:87` exactly — and rebuilding (`M3: PASS`):

- `trans12_decl00.dats`: **4 → 2** (`.node()/.name()` on `#abstbox` `d1tst`/`s2var` receivers
  resolved; the residual 2 are non-selector: an unbound `s2td`, the `neg` operator, an unbound
  `tr12env_add1_d2cs`).
- The other four files were unchanged at the selector sites that depend on the *additional*
  fidelity issues below.

So `tread12` is faithful (it is literally the stock pass, in stock order) and it makes real
progress. It is the correct direction.

## Why `tread12` can't be merged yet — the 8-file regression

`d2parsed_of_tread12` (`tread12.dats:73`) runs `tread12_d2eclistopt` with its own `nerror`, and if
`nerror≠0` returns a **new** d2parsed carrying that count (`:98-103`). Because `tread12` is the
**full L1→L2 read/check**, it enforces invariants the M3 reduced pipeline was silently tolerating —
chiefly around **viewtypes / linearity** (`list_vt`, `!`-borrows, `_vt_free`), which the frontend
lowers loosely (cf. `lexing0_utils1`'s `!Obj`/`T2Pvar` issue below). Running the full
`make -j8 pp-corpus-auto PP_STRICT=1` with `tread12` added **regressed 8 previously-green files**:

```
xatsopt_tmplib   +60      trtmp3c_myenv0  +14      t3read0_dynexp  +8
staexp2_utils2   +8       parsing_tokbuf  +7       nmspace         +7   (list_vt / _vt_free linear fns)
trtmp3b_myenv0   +9       t3read0_decl00  +2
```

The 166 gate is absolute, so the change was reverted (tree left clean). **The fix is gated on
frontend-lowering fidelity, not on overload logic.**

## Per-file breakdown (with `tread12` reverted; current behavior)

Four of five are genuine #13a (abstract-receiver selector → missing-`tread12`). **`lexing0_utils1`
is a different root** and should not be grouped with #13a.

| file | nerror | root |
|---|---|---|
| `staexp0` | 6 | #13a: 4× `id0.lctn()` (con-pattern `i0dnt`) + `s0qid`/`d0qid` twins + 1 param `s0e1.lctn()` (`s0exp`). |
| `staexp2` | 5 | #13a: `s2v0.sort()`/`s2c0.sort()` (param `s2var`/`s2cst`), `s2c1.sort()`/`s2c1.sexp()` (con-pattern), `s2f0.node()` (annotated `S2exp`). |
| `trans23_dynexp` | 5 | #13a: `d3f0.styp()` (let, `d3pat`), `darg.styp(targ)` (let, `d3exp`, **setter** — `styp` bucket has `d3exp_get_styp` *and* `d3exp_set_styp`; needs arity disambiguation) **+ 1 non-selector**: `list_ziprev` element-type mismatch (`list[(a,b)]` vs `list[s2var_tbox,none]`). |
| `trans12_decl00` | 4 (→2 with tread12) | #13a: `.node()` selectors on `#abstbox` receivers (`tread12`-fixable) + residual non-selector unbound names. |
| `lexing0_utils1` | 5 | **NOT #13a**: all five are `D3Et2pck(D3Evar(buf); T2Pvar(_); T2Pnone0())` — the linear/viewtype param `buf:!Obj` passed to `lexing_CMNT*`; pyprint drops the `!Obj` annotation so `unify(T2Pvar, T2Pnone0)` errcks. Same viewtype-fidelity family that `tread12` is strict about. |

## Precise plan for a faithful fix (gate-protected)

The fix is to run `tread12` (and thus inherit stock's selector resolution) **without regressing the
166**. That requires closing the lowering-fidelity gaps that make `tread12` reject green files —
purely additive frontend work, no `srcgen2/` edits, no frontend overload logic.

### Stage 1 — characterize the `tread12` rejections (diagnostic, no risk)
Add `d2parsed_of_tread12` behind a build flag (or a scratch bundle), run the full corpus, and for
each of the 8 regressors capture the exact `tread12_*` errck site (it has commented `prerrsln`s).
Bucket them; the dominant family is viewtype/linearity (`list_vt`, `!`-borrow, `_vt_free`). This is
the same root as `lexing0_utils1`'s `!Obj`/`T2Pvar`, so Stage 2 likely fixes both.

### Stage 2 — make the frontend lower viewtypes/linearity faithfully (the real work)
For each rejected construct, lower it the way stock `trans02`/`trans12` does so `tread12` accepts
it. Candidates (verify against the captured sites):
- **`!Obj`/borrow param annotations**: pyprint drops them, so `buf` lowers untyped (`T2Pnone0`).
  Lower a borrow-annotated param to the proper viewtype binder (or have pyprint emit the annotation
  AND the frontend lower it to the `T2Pvar`/borrow the callee expects).
- **`list_vt` / linear `_vt_free`**: ensure the linear value's consumption/freeing lowers to the L2
  shape `tread12` checks (it tracks linear resource use).
Each construct lands independently; after each, the FULL `make -j8 pp-corpus-auto PP_STRICT=1`
must stay 166/166 (these are green files — the change must not alter their accepted output).

### Stage 3 — add `tread12` and close the selector files
Once Stage 2 makes all 166 green under `tread12`, add `val dpar = d2parsed_of_tread12(dpar)` before
`trans2a` (stock order). Expected to close the #13a selector residue in `staexp0`, `staexp2`,
`trans12_decl00` (and the two selectors in `trans23_dynexp`). Residual non-selector errors
(`trans23_dynexp`'s `list_ziprev`; `trans12_decl00`'s `s2td`/`neg`) are separate and tracked apart.

### Gate protocol
After each stage: `bash build-m3.sh` (`M3: PASS`), then `make -j8 pp-corpus-auto PP_STRICT=1` →
166/166, total `# TODO(pp): 0`, zero `m3_nerror>0` rows. Add any newly-closed file to **both**
`CORPUS/pp-default-auto.files` and `CORPUS/pp-default-dynamic.files`.

> **Do NOT** "fix" #13a by adding/extending the frontend OVERLOAD FAST PATHS or hand-resolving a
> selector to a concrete `d2cst`. The bucket is already faithful; the compiler's own
> trans2a/trsym2b resolve it once `tread12` has stpized the con `xtyp`. The whole task is to run
> the stock pass and make the frontend lowering faithful enough for it.

## Bottom line

- **Mechanism (verified):** dotted overloaded selectors lower to a faithful `D2Esym0` overload
  bucket; stock trans2a/trsym2b resolve it type-directed. The M3 driver was **missing the stock
  `d2parsed_of_tread12` pass** (run before trans2a in `trans03_from_fpath`), which `s2exp_stpize`s
  + `d2con_set_styp`s each constructor — establishing the receiver type the selector match needs.
  Without it, con-pattern field binders of abstract `#abstbox` type leave the bucket un-narrowable.
- **`tread12` is the right pass, proven** (`trans12_decl00` 4 → 2; abstract-`#abstbox` `.node()`
  selectors resolve), but **adding it wholesale regresses 8 green files** because it is the strict
  full L1→L2 read/check and the frontend lowers viewtypes/linearity loosely. Reverted to hold the gate.
- **Files (re-categorized):** 4 of 5 are #13a (`staexp0`, `staexp2`, `trans23_dynexp` (+a separate
  list-mismatch), `trans12_decl00`); `lexing0_utils1` is **not** #13a (the viewtype-`!Obj`/`T2Pvar`
  family — the *same* fidelity gap that makes `tread12` reject green files, so Stage 2 fixes both).
- **Closed this session:** none (report-only). The path is: make the frontend lower
  viewtypes/linearity faithfully (Stage 2), then add `tread12` (Stage 3).
- **Audit:** `166 / 166`, total `# TODO(pp): 0`, zero `m3_nerror>0` — unchanged, tree clean.

(* ============================================================================ *)

## RE-DIAGNOSIS: the residual is an overload-bucket unify under `#absimpl` (compiler's job)

**Pipeline NOW (verified `pyfront_m3.dats:143-149`):**
`tread12 → trans2a → trsym2b → t2read0 → trans23`, exact stock `trans03_from_fpath` order.
`d2parsed_of_tread12` IS committed. Probing `staexp0` under it: **still 6** (`tread12` did NOT
close it — Stage 3's prediction was wrong). Re-probe recipe unchanged
(`bash build-pp-corpus.sh --stadyn auto --reuse-bundle --out-dir BUILD/_sel srcgen2/DATS/staexp0.dats`).

### The 6 `staexp0` errors are all the SAME shape
All six are a dotted `id0.lctn()` (or `s0t2.lctn()`) where the **receiver is a con-pattern field
binder bound by a STALOADED constructor** — `S0QIDnone(id0)`/`S0QIDsome(tok,id0)`/the `d0qid` twins
(`id0 : i0dnt`), and `s0exp_annotopt`'s `s0t2` from `optn_cons(s0t2)`. `tok.lctn()` (offs 13 of
`tok.lctn()+id0.lctn()`) RESOLVES; `id0.lctn()` (offs 26) does not. `staexp2`'s residual is the same
family (`s2v0.sort()`/`s2c0.sort()` on `s2var`/`s2cst`; `s2c1.sort()`/`.sexp()` con-binders) — after
this re-diagnosis it is **5 → 1** under the scope hack, the last being a separate `list_map`/template
issue, NOT a selector. `trans23_dynexp` is unrelated (a setter-arity `darg.styp(targ)` + a `where:`/
`list_ziprev` element-type mismatch).

### Minimal repro bisection (the decisive evidence)
Building tiny `.pdats` that staload the same SATS header and add ONE function:

| repro | construct | result |
|---|---|---|
| 1 | `s0qid_get_lctn` with `id0.lctn()`, **no** `#absimpl` in file | **nerror=0** |
| 4/5 | + local `datatype i0dnt_` and `#absimpl i0dnt_tbox = i0dnt_` (the `private:` block) | **FAILS** |
| 6 | the `enum`/datatype WITHOUT the `#absimpl` | **nerror=0** |
| 7 | the selector placed **before** the `#absimpl` (capture-rest scope excludes it) | **nerror=0** |
| 8 | `#absimpl` present, but a **direct call** `i0dnt_get_lctn(id0)` (no overload bucket) | **nerror=0** |
| 9 | `#absimpl` present, dotted `id0.lctn()` on an **untyped param** (no con binder) | **nerror=0** |

So the failure needs the **intersection** of (a) an `#absimpl` that makes the *local* overload
candidate `i0dnt_get_lctn`'s `xtyp` stpize TRANSPARENT (`i0dnt_tbox → i0dnt_`, via trans2a
`f0_absimpl`'s `s2abs_set_styp`, `trans2a_decl00.dats:404`), (b) a receiver whose `xtyp` is the
STALOADED constructor's FROZEN-OPAQUE arg type (`S0QIDnone`'s `xtyp` was stpized at SATS-load when
`i0dnt_tbox` had no styp, and `tread12_d2con`/`tread12_d2conlst` only re-stpizes constructors
DECLARED IN THIS FILE — `tread12_decl00.dats:1281`, the `D2Cdatatype` arm — never a staloaded con),
and (c) the OVERLOAD-BUCKET path (`match2a_d2cst` / `trsym2b_dynexp f0_sym0`), which reads
`d2cst_get_xtyp(candidate)` = `i0dnt_` and unifies it against the receiver `i0dnt_tbox`.

A **direct call** (repro 8), an **untyped param** receiver (repro 9, a fresh tyvar that unifies
either way), and the **no-`#absimpl`** case (repro 1/6) all resolve. Only the bucket-match of an
opaque-vs-transparent abstract pair fails. That unify is the compiler's own `match2a_*`
(`trsym2b_utils0.dats:147`) — identical code to stock, run in stock order on a byte-faithful bucket.

### Faithful-vs-fidelity verdict: COMPILER'S JOB
Our L2 emission is faithful: the dotted selector lowers to the standard `D2Esym0` overload bucket
(prior investigation verified byte-identity), the con-pattern binds correctly, and the SAME construct
resolves the moment the bucket is bypassed (direct call) or the abstract pair is consistent (param /
no-absimpl). The residual is the compiler reconciling a frozen-opaque staloaded-con arg type against
a stpized-transparent local-candidate `xtyp` **inside overload resolution** — not a pretty-print or
desugar divergence.

### Why the scope hack is NOT a faithful fix (reverted)
Bounding the `private:` capture-rest body at the next sibling `private:` (so an `#absimpl`'s
transparency does not "leak" past the original `local…end`) reorders enough to keep the candidate
`xtyp` opaque, and it **closes `staexp0` (6→0)** and trims `staexp2` (5→1). BUT it is WRONG: an
`#absimpl` is a **GLOBAL** mutation of the public abstract `s2cst` (the whole point — it gives the
opaque type its representation everywhere after). `locinfo.dats` relies on exactly that: `local
datatype postn … #absimpl postn_tbox = postn end` then a SIBLING `local datatype loctn = LOCTN of
(lcsrc, postn, postn) … end` — the second block references `postn` (= the public `postn_tbox`)
transparently. Scoping the absimpl breaks `dynexp1/2/3`, `statyp2`, `locinfo` (`159/164` on the
gate). Reverted. The capture-rest nesting IS a structural divergence from stock's sibling
`D2Clocal0`s, but it is NOT what blocks these selectors, and "fixing" it costs more green files than
it buys.

### Audit (re-diagnosis): `163 / 163`, total `# TODO(pp): 0`, zero `m3_nerror>0` — tree clean, files
left uncovered (`staexp0`, `staexp2`, `trans23_dynexp` stay out of the default gate). Report-only.
