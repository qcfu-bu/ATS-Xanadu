# intrep0, intrep1, and how template instances are emitted

> Status: VERIFIED 2026-06-25 by reading the backend source and by compiling
> programs through the freshly-bootstrapped compiler and inspecting + running the
> emitted JS. File:line citations are into
> `srcgen2/xats2js/srcgen1/{SATS,DATS}/`. This is the single most important
> document for `xats2cz`: it is the part the previous two attempts got wrong.

The backend is three stages after the frontend produces `d3parsed`:

```
d3parsed --trxd3i0--> intrep0 --trxi0i1--> intrep1 --xats2js/js1emit--> JS text
          (shared)    (expr IR)            (ANF IR)
```

`xats2cz` reuses the frontend + `trxd3i0` verbatim and replaces
`trxi0i1 / intrep1 / js1emit` with chez-adapted equivalents. To do that without
repeating the prior failures, you must understand exactly what each stage does to
**template instances**.

---

## 1. The golden rule: monomorphization is already done

ATS3 templates are resolved by the **frontend**, not the backend. By the time we
reach `d3parsed`, the passes `trans3a` → `trtmp3b` (non-recursive) → `trtmp3c`
(recursive) have:
- decided *which* `#impltmp`/`#implfun` body applies at each call, accounting for
  **lexical scope** (an instance can be shadowed within a scope so the same
  template call compiles to different code in different scopes), and
- produced, for each resolved use, a **template-instance descriptor stamped with a
  unique id** that denotes the resolution.

The backend's job is **NOT to resolve or monomorphize** — it is to *emit* the
already-resolved instances correctly. Both prior attempts wasted effort building
hoisting / lambda-lifting / seeding machinery; the JS backend does none of that.
(`srcgen2/SATS/intrep0.sats:42` literally says `Types are erased!!!`.)

---

## 2. intrep0 — the expression IR (`SATS/intrep0.sats`)

Expression-shaped, type-erased. Abstract boxes: `i0pat`, `i0exp`, `fiarg`,
`i0gua/i0gpt/i0cls`, `i0dcl`, `t0imp`, `i0valdcl/i0vardcl/i0fundcl`, `i0parsed`.

The template-relevant `i0exp_node` ctors (`intrep0.sats:422-571`):

| ctor | meaning |
|------|---------|
| `I0Ecst of d2cst` | reference to a top-level constant (a fun/val/template *name* with no instantiation) |
| `I0Econ of d2con` | data constructor reference |
| `I0Evar of d2var` | dynamic variable |
| **`I0Etimp of (i0exp tapp, t0imp)`** | **a template-instance use**: the (type-erased) application `tapp` paired with the instance descriptor `t0imp` |
| `I0Etapp of i0exp` / `I0Etapq of (i0exp, t2jaglst)` | template application (type args erased / explicit) |
| `I0Edapp of (i0exp fun, i0explst args)` | ordinary dynamic application (function call) |
| `I0Elam0/I0Efix0` | lambda / recursive-lambda |
| `I0Elet0/I0Eift0/I0Ecas0/I0Eseqn/I0Ewhere` | let / if / case / sequence / where |

The instance descriptor (`intrep0.sats:681-711`):

```
datatype t0imp_node =
  | T0IMPall1 of (d2cst, t2jaglst, i0dclopt)   // phase-1 (non-recursive) resolved
  | T0IMPallx of (d2cst, t2jaglst, i0dclopt)   // fully (recursively) resolved
fun t0imp_stmp$get (t0imp): stamp              // the unique instance/scope id
```
So a `t0imp` = `(stamp, ctor(d2cst, t2jaglst, i0dclopt))`:
- **`stamp`** — the unique id of this resolved instance (the "defining-scope" id).
- **`d2cst`** — *which* template constant is being instantiated.
- **`t2jaglst`** — the (erased-but-recorded) type/template arguments.
- **`i0dclopt`** — the **resolved instance body**, as an `I0Dimplmnt0` decl, present
  when materialized at this site (`T0IMPallx` carries the full recursive body).

The instance *definition* form (`i0dcl_node`, `intrep0.sats:788-792`):
```
| I0Dimplmnt0 of (token knd, stamp, dimpl, fiarglst, i0exp body)
```
`stamp` = defining-scope id; `dimpl` = the level-2 implementation descriptor
(`$D2E.dimpl`); `fiarglst` = formal args; `body` = the implementation.

Entry: `i0parsed_of_trxd3i0(d3parsed): i0parsed` (`SATS/trxd3i0.sats:63`).
`trxd3i0_timpl(env, timpl): t0imp` (`trxd3i0.sats:127`) builds the `t0imp` from the
level-3 `timpl`.

> **`xats2cz` reuses this stage as-is.** intrep0 already carries everything the chez
> backend needs: expression shape + the stamped, body-bearing template instances +
> (in `t2jaglst`/the level-2 types) the typing metadata.

---

## 3. intrep1 — the A-Normal-Form IR (`SATS/intrep1.sats`)

`trxi0i1` exists for one reason: **flatten the expression tree into A-Normal Form
for an imperative target**. This is the layer `xats2cz` replaces.

The core shapes (`intrep1.sats:209-461`):
```
i1cmp = I1CMPcons of (i1letlst, i1val)         // a computation = lets ; then a value
i1let = I1LETnew0 of (i1ins)                   // run an instruction, discard result
      | I1LETnew1 of (i1tnm, i1ins)            // bind instruction result to fresh temp
i1ins = effectful / compound ops:
        I1INSopr | I1INSdapp(call) | I1INStimp(template instance!) |
        I1INSpcon/pflt/proj | I1INSlet0 | I1INSift0 | I1INScas0 |
        I1INStup0/1/rcd2 | I1INSlam0/fix0 | I1INStry0 | I1INSflat | I1INSfold |
        I1INSfree | I1INSdl0az/dl1az | I1INSl0azy/l1azy | I1INSdp2tr |
        I1INSraise | I1INSassgn
i1val = atomic operands:
        I1Vint/.../I1Vi00/... | I1Vtnm(temp ref) | I1Vcon/cst/var |
        I1Vp0rj/p1cn/p1rj/p2rj(projections) | I1Vlpft/lpbx/lpcn(flat/boxed/consed
        left-values — the layout distinction the Go backend exploits) | I1Vextnam
```
- `i1tnm` is the **fresh temp name** minted for each named sub-computation
  (`i1tnm_new0`, `i1tnm_stmp$get`). **This is exactly the `jsxtnm` that the
  per-file namespacing rewrites to `jsxNNNtnm`** (then `js1/js2/js3` at link).
- ANF is constructed by an **ilet-stack in `envi0i1`** (`SATS/trxi0i1.sats:56-117`):
  `iltstk_pshblk0/pshlam0/pshlet0` open a scope, `iltstk_ilet$insert` appends a
  let, `pop*` returns the accumulated `i1letlst`. Lowering an `i0exp` *to a value*
  (`trxi0i1_i0exp → i1val`, `trxi0i1.sats:278`) side-effects lets into the current
  scope; `trxi0i1_i0blk → i1cmp` (`:286`) opens a fresh scope and returns a
  self-contained computation; `trxi0i1_i0lft → i1val` (`:282`) handles left-values.

**The template instance survives the lowering intact** (`intrep1.sats:225-237,
658-703`):
```
i1ins   ::= ... | I1INStimp of (i0exp tapp, t1imp)      // NOTE: keeps the raw i0exp!
t1imp_node = T1IMPall1 of (d2cst, t2jaglst, i1dclopt)
           | T1IMPallx of (d2cst, t2jaglst, i1dclopt)
fun t1imp_stmp$get(t1imp): stamp     fun t1imp_dcst$get(t1imp): d2cst
fun t1imp_i1cmpq(t1imp): i1cmpopt    fun t1imp_i1dclq(t1imp): i1dclopt
| I1Dimplmnt0 of (token knd, stamp, dimpl, fjarglst, i1cmp body)
```
`trxi0i1_t0imp(env, t0imp): t1imp` (`DATS/trxi0i1_dynexp.dats:3342-3399`) reads
`t0imp_stmp$get`, recurses the body decl with `trxi0i1_i0dcl`, and rebuilds with
`t1imp_make_node(stmp, node)` — **the stamp is carried through unchanged; nothing
is renamed or monomorphized**. (Confirms the prior-attempt finding.)

At a use-site, `I0Etimp(i0e1, timp)` is lowered by `f0_timp`
(`trxi0i1_dynexp.dats:1772-1792`) → `i1val_timp` (`:213-232`): mint a fresh
`i1tnm`, wrap as `I1INStimp(i0e1, t1imp)`, bind `I1LETnew1(itnm, ins)`, insert into
the env, and return `I1Vtnm(itnm)` as the operand. So **"use a template instance"
becomes "let jsxtnmN = <the instance>; … use jsxtnmN"**.

---

## 4. THE TEMPLATE-INSTANCE EMISSION (the crux)

### 4.1 The strategy in one sentence
**Each template-instance use is emitted as a fresh local closure inlined at that
use site; instances used *inside* a body are inlined as *nested* closures; template
implementations are NEVER emitted as shared top-level definitions.** Lexical nesting
of the emitted closures reproduces ATS3's lexical template scoping for free — which
is *also* what makes "swap an instance in a scope to change behavior" work.

### 4.2 The use-site dispatcher — `I1INStimp` (`DATS/js1emit_dynexp.dats:2105-2156`)
```
| I1INStimp(i0f1, timp) =>
    iopt = t1imp_i1cmpq(timp)
    case iopt of
    | optn_nil()      => emit  "let <itnm> = " ; f0_t1imp(env0, timp)   // inline closure
    | optn_cons(icmp) => f0_i1tnmcmp(env0, itnm, icmp)                  // value-like body
```
`t1imp_i1cmpq` (`DATS/intrep1_utils0.dats:121-182`) returns a body **only when the
instance is an `I1Dimplmnt0` with empty `fjas`** (a nullary/value-like instance);
otherwise `optn_nil` → the inline-closure path (the common case).

### 4.3 The inline emitter — `f0_t1imp` (`DATS/js1emit_dynexp.dats:1478-1590`)
Reads `t1imp_dcst$get` + `t1imp_i1dclq`, then:
- **no body** (`optn_nil`) → `XATS000_undef() // timp: <dcst>` (an undefined
  instance reference — a real, observable failure mode).
- **`I1Dfundclst(_,_,d2cs,i1fs)`** (a mutually-recursive function group) →
  ```
  function () {
    <emit all fundcls in the group>
    return <the i1fundcl whose dpid matches this instance's dcst>
  } () // endtimp(<dcst>)
  ```
  (an IIFE that defines the recursive group and returns the requested member;
  `dcst2varfpr` at `:1522-1552` picks the member by matching `dcst`.)
- **`I1Dimplmnt0(_,stmp,dimp,fjas,icmp)`** (the common single-function instance) →
  ```
  function <fjas-args> { // timp: <dcst>
    <destructure fjarglst> <body cmp> return <result>
  } // endtimp(<dcst>)
  ```

### 4.4 The top-level instance split — `f0_implmnt0` (`DATS/js1emit_decl00.dats:586-692`)
For a top-level `I1Dimplmnt0`, `dimpl_tempq(dimp)` decides:
- **template** → emit ONLY a comment `// I1Dimplmnt0(...):timp`, **no code**. The
  instance is materialized later, inline, at each use site (§4.3).
- **non-template** (a concrete `#implfun` of a *non-template* SATS-declared fun) →
  emit a real top-level definition
  `let <dicstjs1(dimp)> = function <args> { ... } // endfun(impl)`
  (or `} () // endnfn(impl)` when nullary/non-fun).

### 4.5 Name mangling (`DATS/js1emit_utils0.dats`)
- `d2cstjs1` (`:173-241`): no external name → **`xsymjs1(name) + "_" +
  fprint_loctn_as_stamp(lctn)`**; `$extnam`/`$extern` → bare `name` (links to the
  runtime primitive). `d2varjs1` (`:245-262`) and `d2conjs1` (`:151-169`) use the
  same `name_<location-stamp>` scheme.
- `xsymjs1` (`:121-146`): copies the symbol char-by-char, **only escaping `'` → `$`**.
- `fprint_loctn_as_stamp` (`SATS/locinfo.sats:157`): turns a *source location* into
  the numeric suffix. **The uniquifier in emitted names is the source LOCATION** —
  distinct definitions live at distinct locations, so their mangled names never
  collide in a whole-program image. (This, not the `t0imp` stamp, is what makes the
  whole-program JS collision-free.)
- `i1tnmjs1` (`:267-279`): temp names emit as `jsxtnm<stmp>` → namespaced per file.
- `XATS000_*` is the fixed runtime-primitive namespace (`XATS000_inteq`,
  `XATS000_raise`, `XATS000_l0azy`, `XATS000_fold`, `XATS000_patck`,
  `XATS000_undef`, `XATS000_cfail`, …) defined in the hand-written JS runtime.

### 4.6 Worked example — verified emitted JS
Source: `fun run0() = list_length<sint>(list_reverse<sint>(mk()))` (test79).
The freshly-bootstrapped compiler emits (abridged, real output):
```js
// T1IMPallx(list_length(1428); LCSRCsome1(.../list000.dats)@(...));  <metadata comment>
let jsxtnm22 = function (arg1) {            // timp: list_length(1428)
  ...
  let jsxtnm16 = function (arg1, arg2) {    // timp: sint_add$sint(1178)   <-- NESTED instance
    ...
  } // endtimp(sint_add$sint(1178))
  ...
} // endtimp(list_length(1428))
let jsxtnm42 = function (arg1) {            // timp: list_reverse(1436)
  let jsxtnm39 = function (arg1) {          // timp: list_reverse_vt(1437) <-- NESTED
    let jsxtnm36 = function (arg1, arg2) {  // timp: list_rappendx0_vt(1440) <-- NESTED deeper
      ...
    } // endtimp(list_rappendx0_vt(1440))
  } // endtimp(list_reverse_vt(1437))
} // endtimp(list_reverse(1436))
let jsxtnm44 = XATSDAPP(jsxtnm42(jsxtnm43)); // call the reverse instance
let jsxtnm45 = XATSDAPP(jsxtnm22(jsxtnm44)); // call the length instance
```
Runs and prints `3`. The `// timp: name(stamp)` shows the `d2cst` + its stamp; the
preceding `// T1IMPallx(...)` comment dumps the full instance metadata (d2cst,
source location, the `t2jaglst` erased type `<...gint_type...>`, and the
`I1Dtmpsub(...; I1Dimplmnt0(...))` body). The instance tree of the *program* becomes
a tree of *nested closures* in the output.

### 4.7 Why this is the whole ballgame for continuations
Higher-order templates use hooks (`map$fopr`, `foritm$work`, `forall$test`, …). The
frontend resolves a hook to a body defined in the *caller's* scope. Because the JS
backend **inlines the instance body where it is used**, the hook reference lands
*inside* the caller's lexical scope in the emitted JS and resolves as an ordinary
closed-over variable — no hoisting, no lambda-lifting, no global seed map. The 2nd
attempt's long detour through hoist/lift/seed was the consequence of *not* inlining;
its eventual fix ("JS-style INLINE + alpha-renaming") was a re-derivation of this.

---

## 5. What this means for `xats2cz` (chez intrep1)

Scheme is an **expression language with first-class lexical closures and native
proper tail calls**. The xats2js template strategy — *inline each instance as a
nested local closure* — maps onto Scheme **more** directly than onto JS:

| xats2js (JS) | xats2cz (Chez) |
|--------------|----------------|
| ANF: `let jsxtnmN = function(a){…}; … jsxtnmN(x)` | `(let ((tN (lambda (a) …))) … (tN x))` — or inline the `(lambda …)` directly |
| `function(){ <recgroup>; return member } ()` (IIFE for `I1Dfundclst`) | `(letrec ((f …) (g …)) f)` |
| statements + explicit `return` (`f0_i1cmpret`) | the body expression *is* the result (tail position natural) |
| `XATS000_*` JS runtime primitives | a Chez runtime providing the same primitive floor |
| name `_<location-stamp>`, `'`→`$` | same `_<location-stamp>` scheme; pick a Scheme-legal escape |

### DECISION (2026-06-25, user): NO `intrep1cz` — emit Scheme directly from intrep0
There is **no** chez intrep1 datatype and **no** `trxi0i1cz`/ANF stage. The
pipeline is **two stages** after the frontend:
```
d3parsed --trxd3i0--> intrep0 --cz0emit--> Scheme text
          (reused)    (expr IR)            (the only new emitter)
```
Rationale (the survey makes this the principled choice): intrep0 is *already*
expression-shaped, *already* type-erased, and *already* carries the stamped,
body-bearing template instances (`I0Etimp`/`t0imp` with its `i0dclopt` body and
`stamp`). The xats2js `intrep1` exists only to ANF-flatten for an imperative
target; Chez is an expression language with native closures + proper tail calls,
so that flattening is pure overhead. Emitting straight from intrep0 removes a
whole IR + lowering pass with nothing lost.

> **d3→intrep0 PROVIDER (user-corrected 2026-06-25): use xats2js, NOT xats2cc.**
> `xats2cc` is an *incomplete* ATS3→C backend; consuming its `intrep0`/`trxd3i0`/
> `tryd3i0` (as `xats2chez` did) inherits that incompleteness. `xats2cz` consumes
> the **complete, self-hosting xats2js backend**: the js2 layer is `lib2xats2js.js`
> (built from scratch + verified to self-compile), the driver `#staload`s
> `srcgen2/xats2js/srcgen1/SATS/{intrep0,trxd3i0}.sats`, the pipeline is just
> `i0parsed_of_trxd3i0` (NO `tryd3i0` — that is xats2cc-only). `cz0emit` is written
> against **xats2js's `intrep0.sats` node set** (5-field `I0Dimplmnt0`, no
> `I0Ddclenv`); it is NOT a copy of `xats2chez/chez0emit.dats`, which targets
> xats2cc's divergent intrep0. The Chez runtime / value-rep contract is independent
> of this and may be reused.

Design consequences:
1. **`cz0emit` is a single mutually-recursive walk over intrep0** (`i0exp`, `i0pat`,
   `i0dcl`, `t0imp`, clauses), emitting Scheme expressions — the chez analog of the
   *combined* `xats2js`+`js1emit` walk, but with no `i1*` layer beneath it.
2. **The template rule is unchanged and applies at intrep0 directly.** `I0Etimp(tapp,
   t0imp)` → emit the instance body (from the `t0imp`'s `i0dclopt`) **inline as a
   nested lambda** at the use site, exactly mirroring §4.3/§4.6; nested instances
   nest. Do **not** hoist, lift, seed, or monomorphize. Top-level *template*
   `I0Dimplmnt0` emits **nothing** (it is materialized at each use site); a
   *non-template* `#implfun` emits a top-level `(define …)`.
3. **Types erased initially**, like JS. The `t2jaglst`/level-2 type metadata stays
   available in intrep0 if we later want typed primitives or boxed/unboxed layout,
   but the first correct backend ignores it.
4. **Reuse the name-mangling scheme** (`name_<location-stamp>`, Scheme-legal escape)
   so def/use names agree and a whole-program image stays collision-free.
5. The Chez compiler only runs the *emitted Scheme*; the emitter itself is ATS3
   source transpiled to JS by the seed and run on Node (same as every other
   backend). Self-hosting = compile the whole frontend + `trxd3i0` + `cz0emit`
   source to Scheme + provide the `XATS000_*`/prelude primitive floor in Scheme +
   a driver, then run on Chez.

> This is the same intrep0-direct shape the 2nd attempt (`xats2chez`) used; its
> emitter `chez0emit.dats` reportedly reached near-complete intrep0→Scheme node
> coverage. The difference for `xats2cz` is to get the **template emission right
> from the start** — faithful inline nested closures per §4, not the
> hoist/lift/seed detour — and to build on the verified bootstrap/runtime facts in
> `01`/`02`.

See `docs/02-dependencies.md` for the scattered runtime/prelude/xatslib inventory,
and `docs/01-bootstrap.md` for the build pipeline.
