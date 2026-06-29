# xats2go — the typed‑intrep1 redesign (2nd attempt at the IR)

> Status: DESIGN, grounded in source facts verified 2026‑06‑29 against
> `srcgen2/xats2go/...`, `srcgen2/xats2js/srcgen1/...`, and
> `srcgen2/xats2go/xats2cc/srcgen1/...`. This doc is the xats2go analog of
> `srcgen2/xats2cz/docs/03-ir-and-templates.md` — it exists so the IR mistake
> the first attempt made is not repeated. Every file:line claim below was read,
> not recalled.

## 0. The one‑paragraph summary

The first xats2go attempt emitted Go from an intrep1 **copied verbatim from
`xats2js`** — an ANF IR that is **type‑erased** because its target (JavaScript)
is dynamically typed. To recover the static types Go needs, the attempt bolted a
**process‑global side‑table** (`go1emit_tytab0`, milestone M2.6a) onto the
lowering: it stashed each temp's source `i0typ` keyed by stamp and the emitter
consulted it as a backstop. That is the wrong shape: a typed target wants a
**typed IR**, not an untyped IR plus a side‑channel. This redesign builds a
**new intrep1 whose temps and values carry a `gotyp`** (a native‑Go type as
data) and a **new `trxi0i1` that computes that `gotyp` from the source
expression's type at each lowering site**, so the emitter reads types directly
off the IR. The type source is the **xats2cc `intrep0`**, which — unlike the
JS/Chez `intrep0` — preserves a per‑expression `ityp : i0typ`.

---

## 1. Why the basis is `xats2cc`, not `xats2js` (the type‑preservation argument)

The D3→intrep0 stage (`trxd3i0`) exists in two flavors in this tree, and the
difference is decisive for a **statically‑typed** target:

| | `xats2js` / `xats2cz` intrep0 (the JS/Chez path) | `xats2cc` intrep0 |
|---|---|---|
| `i0exp` constructor | `i0exp_make_node(loc, node)` — **no type** (`srcgen2/xats2js/srcgen1/SATS/intrep0.sats:600`) | `i0exp_make_ityp$node(loc, ityp, node)` (`xats2cc/srcgen1/SATS/intrep0.sats:860`) |
| per‑expression type | **erased** — `srcgen2/SATS/intrep0.sats:42` says *"Types are erased!!!"* | `i0exp_ityp$get(iexp): i0typ` (`xats2cc/srcgen1/SATS/intrep0.sats:820`) |
| per‑var type | none | `i0var_ityp$get(ivar): i0typ` (`:806`) |
| layout in the type | only via the constructor split (`I0Etup0` vs `I0Etup1(token)`) | **also** in the type: `I0Ttrcd(trcdknd, npf, fields)` (`:367`), `I0Ttcon(d2con, args)` (`:366`) |

The JS and Chez backends are *correct* to erase types: their value
representation is uniform and dynamically dispatched, so a type annotation on
every node would be dead weight. **Go is the opposite** — it needs the concrete
type of every binding to emit `var x T`, struct field types, type assertions,
`func(...)…` signatures, and value‑vs‑pointer layout. The `xats2cc` `intrep0`
is the only one that carries that information.

So the original xats2go decision to staload `xats2cc/srcgen1/SATS/intrep0.sats`
(see `srcgen2/SATS/intrep1.sats:56`) was **right for the basis**. What was wrong
was *what got built on top of it* (§2). The reversal in the directives
("use the proven JS/Chez one" → "use xats2cc after all") is resolved by exactly
this fact: the proven JS/Chez `intrep0` is type‑erased, and a typed Go IR cannot
be derived from erased types.

> Note on "incompleteness": `xats2cc` is an incomplete ATS3→**C** backend. We do
> **not** consume its C emitter — only its **typed `intrep0` + `trxd3i0` +
> `tryd3i0`** (the D3→intrep0 stage). The incompleteness lives in the part we
> never touch.

---

## 2. What was actually wrong (the type‑erased intrep1 + the side‑table)

The xats2go intrep1 is a copy of the xats2js ANF IR. Its carriers hold **no
type**:

- `i1val = lctn + i1val_node` — `srcgen2/SATS/intrep1.sats:551‑583`. No type.
- `i1tnm = stamp` only — `srcgen2/DATS/intrep1.dats:290‑312` (`I1TNM(stmp)`).
- `i1ins` results — untyped.

Because the temps are untyped, the emitter has to **reconstruct** the Go type
at every use. M2.6a's fix was the side‑table:

- `go1emit_tytab0.sats` — a process‑global `stamp → i0typ` map, *populated during
  lowering* (`trxi0i1_dynexp.dats`, at the `i0exp_trxi0i1` chokepoint) and *read
  by the emitter* (`go1emit_styp0.dats:1302 gotype_of_tnm_from_tytab`).
- It is explicitly a backstop: recorded "best‑effort and conservative … the
  emitter falls back to `any`" (its own header comment).

This works but is the wrong architecture for a typed target:

1. **Type lives off to the side of the value it describes** — two structures to
   keep in sync, with `any`‑fallbacks papering over every gap.
2. **The emitter re‑derives types** (`gotype_of_styp`, `gotype_of_i0typ`,
   `gotype_of_ival`, `gotype_of_cmp` — ~2700 lines in `go1emit_styp0.dats`)
   instead of reading them.
3. **It is a global mutable map**, sound only because the driver fully runs
   lowering before emission in one process — a fragile invariant.

The redesign deletes the side‑table by **moving the type onto the IR**.

---

## 3. The new typed intrep1

### 3.1 `gotyp` — native Go types as data

A new module `SATS/gotyp.sats` defines `gotyp`, the **Go type language** the IR
carries. It is the structured form of what `go1emit_styp0.dats` currently
produces as strings:

```
datatype gotyp =
| GOTint    | GOTflt   | GOTbool | GOTrune | GOTstr   // concrete scalars
| GOTany                                              // any (interface{}) — faithful for I0Tvar
| GOTunit                                             // the unit result (no Go value)
| GOTptr    of (gotyp)            // *T          (boxed layout / by‑ref param / var cell)
| GOTslice  of (gotyp)            // []T
| GOTstruct of (labgotyplst)      // struct{F<l> T; …}   (flat tuple/record, value)
| GOTfunc   of (gotyplst, gotyp)  // func(args) res      (proof args already dropped)
| GOTcon    of (sym_t)            // a datatype value (today: *xatsgo.XatsCon; name = datatype)
| GOText    of (strn)             // a runtime/external Go type name, verbatim
```

`gotyp` is a plain (non‑abstract) recursive datatype — exactly the style
`intrep1.sats` uses for `i1val_node`/`i1ins` — so it needs no allocator
boilerplate. One render function `gotyp_emit(gotyp): strn` replaces the head of
the string‑producing tangle in `go1emit_styp0.dats`.

### 3.2 Typed temps and typed values

The IR change is small and local:

- **`i1tnm` gains a `gotyp`.** `i1tnm_new0()` (`intrep1.dats:307`) becomes
  `i1tnm_new1(gty: gotyp)`; `i1tnm_gotyp$get(i1tnm): gotyp` is added. Because
  intrep1 is ANF/SSA — every non‑atomic computation is named by exactly one
  `I1LETnew1(tnm, ins)` — **typing the temp types the whole dataflow.**
- **`i1val_gotyp(ival): gotyp`** is the one query the emitter calls. It is total:
  - `I1Vtnm(tnm)` → `tnm.gotyp()` (the stored type — the common case);
  - literals `I1Vint/flt/btf/chr/str` and evaluated `I1Vi00/f00/…` → the matching
    scalar `GOT*`;
  - `I1Vcst/Vcon/Vfenv` → from the `d2cst`/`d2con` signature (§4);
  - projections/lvalues carry their own field `gotyp` (computed at lowering).

No global state, no stamp lookups, no `any`‑backstop in the emitter.

### 3.3 What the emitter becomes

`go1emit_styp0.dats` shrinks from "recover a Go type from `s2typ`/`i0typ`/the
side‑table" to "**render the `gotyp` already on the node**." The `~2700`‑line
`gotype_of_*` family collapses into `gotyp_emit` plus the lowering‑time
`gotyp_of_i0typ` (§4). `go1emit_tytab0.{sats,dats}` and the
`#staload go1emit_tytab0` lines are deleted.

---

## 4. The new `trxi0i1` — `ityp` → `gotyp` at the mint site

`gotyp_of_i0typ(ityp): gotyp` is the heart of the new lowering. It mirrors the
existing `gotype_of_i0typ` (`go1emit_styp0.dats:1194`) but returns structured
`gotyp` and runs **once, where the typed `i0exp` is in scope**, not lazily in the
emitter:

| `i0typ_node` (`xats2cc/.../intrep0.sats`) | `gotyp` |
|---|---|
| `I0Tcst(s2cst)` — scalar abstype | by s2cst name: `…sint…`→`GOTint`, `gflt`/`dflt`→`GOTflt`, `bool`→`GOTbool`, `char`→`GOTrune`, `string`→`GOTstr`; a datatype cst → `GOTcon(name)` |
| `I0Tvar(s2var)` | `GOTany` — **faithful**: ATS represents a type var uniformly/boxed; `any` is not a defect |
| `I0Ttrcd(knd, npf, fields)` | drop `npf` proof fields → `GOTstruct(per‑field gotyp_of_i0typ)`; if `trcdknd_fltq(knd)` false (boxed) wrap in `GOTptr` |
| `I0Ttcon(d2con, args)` | `GOTcon(parent‑datatype name)` (today boxed `*xatsgo.XatsCon`; typed struct later) |
| `I0Tapps(hd, args)` | `gint_type(KIND,_)`→width(`GOTint`), `gflt_type(KIND)`→`GOTflt`, parametrized datatype→`GOTcon`; else chase `hd` |
| `I0Ttext(name, args)` | `gotyp_of_textnm(name)` (the `xats_*_t` KIND → scalar map) |
| `I0Tlft(t)` | chase the inner `i0typ` (matches the proven emitter; the by‑ref/lvalue `GOTptr` is an S4/byref refinement) |
| `I0Ttop0/1`, `I0Texi0/uni0`, `I0Tlam1` | chase the inner `i0typ` |
| `I0Tnone1(t2p)` | `gotyp_of_styp(t2p)` (reuse the `s2typ` arm) |
| else (datatype/poly/unknown) | `GOTany` |

At each site in `trxi0i1_dynexp.dats` that currently calls `i1tnm_new0()`, the
new code calls `i1tnm_new1(gotyp_of_i0typ(iexp.ityp()))` using the `i0exp` already
in hand. Concretely:

- **`i0exp_trxi0i1` chokepoint** — the same place M2.6a hooked the side‑table;
  the temp minted for a computed result gets the result expression's `gotyp`.
- **call results** — `I1INSdapp` result temp ← the `i0exp`'s `ityp` (the call's
  result type, already substituted by the frontend's monomorphization).
- **projections** — `I1INSpflt/proj/pcon` result temp ← the projected field's
  `gotyp` (the `I0Ttrcd`/`I0Ttcon` field type).
- **if / case / let** — result temp ← the node's own `ityp` (the branch‑join
  type the frontend already computed); no ad‑hoc branch unification needed.
- **fun params** — each `fjarg` binder's `i1tnm` ← `i0var_ityp$get` of its
  `d2var` → `gotyp`. Result type ← the function `i0typ`.

Because the frontend has **already monomorphized** (template instances arrive as
`I0Etimp`/`t0imp` with concrete `t2jaglst`, and the substituted `ityp` is on
every node), `gotyp_of_i0typ` sees concrete types at the use site — no inference,
no unification in the backend.

---

## 5. Template instances are unchanged

The redesign touches **only the type carriers**, not the template machinery. The
xats2cz rule still holds verbatim (`srcgen2/xats2cz/docs/03-ir-and-templates.md`
§4): `I1INStimp(i0exp, t1imp)` is emitted inline as a nested local construct at
its use site; nothing is hoisted/lifted/monomorphized in the backend; a
top‑level *template* `I1Dimplmnt0` emits nothing while a *non‑template*
`#implfun` emits a top‑level definition. The instance body now simply lowers with
typed temps like any other code.

---

## 6. Staging (gated by the differential‑vs‑JS oracle)

The existing `build-go.sh <src>` harness compiles a source through **both**
backends and asserts byte‑equal stdout; it gates every step.

- **S0 — `gotyp` foundation. ✅ DONE.** `SATS/gotyp.sats` (the type language) +
  `DATS/gotyp.dats` (`gotyp_fprint`/predicates) + this doc. Additive.
- **S1 — typed temps. ✅ DONE (transpile‑verified).** `i1tnm` carries the Go
  type; `i1tnm_new1`/`i1tnm_gotyp$get`/`i1tnm_gotyp$set`/`i1val_gotyp`.
  `i1tnm_new0` kept as `i1tnm_new1(GOTany)` so unconverted sites still build.
  The type is a settable cell (`a0ref(gotyp)`) so it can be finalized at the
  lowering chokepoint without threading every mint site.
- **S2 — the translation engine + temp‑type finalization. ✅ DONE
  (transpile‑verified).** `SATS/DATS/gotyp_of_styp` = the faithful structured
  port of `go1emit_styp0`'s `gotype_of_styp`/`gotype_of_i0typ` (→ `gotyp`),
  layered below `trxi0i1` (no intrep1/go1emit dep). Wired at the
  `i0exp_trxi0i1` chokepoint: `i1tnm_gotyp$set(itnm, gotyp_of_i0typ(iexp.ityp()))`
  finalizes each producing temp's type. The side‑table is kept in parallel
  (the emitter still reads it), so emitted Go is unchanged and the suite stays
  green; this lands the typed‑type computation ready for S3. *Verification
  note:* each touched file transpiles through the jsemit00 seed with 0
  parse/typecheck errors; full byte‑equal‑vs‑JS validation arrives with S3
  (the emitter switchover is what changes output, so it must be oracle‑gated).
- **S3 — emitter reads `gotyp` (oracle‑gated).** Replace the emitter's
  `gotype_of_*` recovery with `i1val_gotyp` + a `gotyp_emit` renderer (added in
  the emitter layer, byte‑identical to today's strings); delete
  `go1emit_tytab0` and the side‑table population. Re‑green each construct
  against the JS oracle (`build-go.sh`).
- **S4 — idiomatic layout.** `GOTstruct`/`GOTptr` from `I0Ttrcd` drive value
  struct vs pointer; `I0Tlft`/by‑ref → `GOTptr`; `GOTcon` graduates from
  `*xatsgo.XatsCon` to typed tagged structs.

Each S‑step is independently testable and reversible; none rebuilds the 171 MB
frontend lib. S0–S2 are additive (the emitter still uses the side‑table), so the
existing green suite is preserved; S3 is the first step that changes emitted
output and is therefore gated by the differential‑vs‑JS oracle.

---

## 7. Invariants (the discipline this preserves)

1. **One type, on the value.** A computed value's Go type is a field of its temp,
   never a lookup. `any` appears **only** for `I0Tvar` (genuinely polymorphic) —
   and there it is faithful to ATS's own uniform representation, not a gap.
2. **No backend inference.** The frontend monomorphized; `gotyp_of_i0typ` is a
   total structural map over an already‑concrete `i0typ`.
3. **Layout from the type, not a guess.** flat/boxed comes from
   `I0Ttrcd`'s `trcdknd` (and the constructor split), so value‑struct‑vs‑pointer
   is decided by data the frontend recorded.
4. **The oracle still gates.** Byte‑equal‑vs‑JS per construct; a wrong `gotyp`
   surfaces as a `go build` error or an output mismatch.
```
