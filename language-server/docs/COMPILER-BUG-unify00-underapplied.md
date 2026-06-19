# Compiler bug: `unify00_s2typ` aborts (`XATS000_cfail`) on an under-applied type constructor

**Status:** minimal repro in hand; reproducible with **stock** current-generation
tooling (no LSP, no local compiler patches involved). Fix is compiler-side and
belongs to Hongwei.

---

## One-line summary

When a function's declared **result type is an under-applied (arity-deficient)
type constructor** — e.g. `list0` written without its one type argument — and
that function is **called**, the front-end's static-type unifier `unify00_s2typ`
hits a **non-exhaustive case** and throws `XATS000_cfail`, aborting the entire
file instead of reporting an ordinary "type constructor under-applied" error.

## Minimal repro (2 lines)

`language-server/docs/repro/unify00-cfail-underapplied.dats`:

```ats
#extern fun g((*void*)): list0 = $extnam()   // list0 needs 1 arg; written unapplied
val x = g()                                   // the call forces the type-pack + unify
```

Properly applying the constructor (`list0(strn)`) type-checks cleanly — the
abort is specifically about the **under-application**.

## How to reproduce (stock tooling only)

```sh
XATSHOME=<repo> node --stack-size=8801 \
  xassets/JS/xatsopt/xatsopt_tcheck01_ats3_opt1.js \
  language-server/docs/repro/unify00-cfail-underapplied.dats
# -> throws XATS000_cfail from unify00_s2typ, exit 1
```

## A/B — it is a regression in the *current* front-end

Identical input, three compilers:

| compiler artifact | built by | result |
|---|---|---|
| `xassets/JS/xatsopt/xatsopt_tcheck01_ats2_opt1.js` | old **ATS2** compiler (prebuilt) | exit 1, **graceful error**, no abort |
| `xassets/JS/xatsopt/xatsopt_tcheck01_ats3_opt1.js` | **current ATS3 / Xanadu** | exit 1, **`XATS000_cfail`** |
| `language-server/server/BUILD/xats-lsp-check.js`   | current `srcgen2` (`lib2xatsopt.js`) | exit 1, **`XATS000_cfail`** |

The older `_ats2_`-generation compiler reports an ordinary type error here; the
**current** generation aborts. So this is a regression (or newly-exposed gap) in
the present `unify00_s2typ`, *not* anything specific to the LSP build — the stock
`_ats3_` compiler reproduces it on its own.

> Note for context: this is **unrelated to the local `xglobal_reset` (C1)
> experiment**. C1 touched only `xglobal.{dats,sats}` and the static-singleton
> initializers; `unify00_s2typ` lives in `srcgen2/DATS/statyp2_tmplib.dats`
> (with helpers in `trans2a_utils0.dats` / `trans23_utils0.dats`) and is
> untouched. Two independent confirmations:
> 1. The stock `_ats3_` compiler artifact (committed 2026-02-06, four months
>    before C1, containing zero `xglobal_reset` symbols) aborts identically.
> 2. Reverting all six C1 files to their pre-C1 state and rebuilding
>    `lib2xatsopt.js` from that source produces a checker that **still aborts
>    identically** (`XATS000_cfail` at `unify00_s2typ`, same stack). C1 cannot
>    introduce a bug that a pre-C1 compiler already has.

## Abort site (readable build, `xats-lsp-check.js`)

```
throw new Error("XATS000_cfail")
  at XATS000_cfail
  at unify00_s2typ          (statyp2_tmplib.dats)   <-- non-exhaustive case
  at unify23_s2typ
  at trans23_d2exp_tpck                              <-- type-packing the application
  at f0_t2pck
  at trans23_d2exp
```

(The same gap is also reachable through the `trans2a_d2exp_tpck` / `unify2a_s2typ`
path — e.g. the original LSP driver below — so it is `unify00_s2typ` itself, not a
single caller.)

## Observed scope of the trigger

Empirically, which **unapplied** constructor is used matters — so the missing
case is keyed to the constructor's **sort/shape**, not "any under-application":

| unapplied ctor as result type, then called | aborts? |
|---|---|
| `list0` | **yes** |
| `list1` | **yes** |
| `list0(strn)` (properly applied) | no (clean) |
| `jsa1sz` | no |
| `option0` | no |

`list0` / `list1` (boxed list constructors) reach the unhandled case; `jsa1sz`
(JS array) and `option0` do not. That contrast is probably the quickest way to
localize the missing pattern in `unify00_s2typ`.

## How the LSP server hit this in real code

The LSP's own compiler-linking driver files
(`server/DATS/xats_lsp_check.dats`, `server/resident/DATS/xats_lsp_resident.dats`)
contain — copied from the stock driver template `srcgen2/UTIL/xatsopt_tcheck01.dats` —

```ats
#if defq(_XATS2JS_)
#typedef argv = jsa1sz(strn)
#endif
#extern fun XATSOPT_argv$get((*0*)): argv = $extnam()
...
val argv = XATSOPT_argv$get()
```

When the front-end type-checks one of these files **as a target**, `_XATS2JS_`
is not defined in that nested check, so the guarded `#typedef argv` is skipped;
`argv` is then left in an under-applied/ill-formed state, and the
`XATSOPT_argv$get()` call drives the same `unify00_s2typ` abort. (Removing the
`#if` guard so the typedef is always active makes the file check cleanly — but
the guard is correct for the real build; the proper fix is in the compiler.)

This is why the LSP cannot analyze its *own* compiler-linking source files
(`could not analyze … (compiler aborted: XATS000_cfail)`), while all ordinary
ATS3 code — the entire `srcgen2/`, the prelude, user programs — checks fine.

## Suggested fix direction (for Hongwei)

`unify00_s2typ` should not `cfail` on an under-applied / arity-deficient type
constructor: either

1. add the missing case so it emits a proper **under-application type error**
   (matching the `_ats2_`-generation behavior), or
2. have `trans23_d2exp_tpck` / `trans2a_d2exp_tpck` reject an under-applied
   constructor type **before** it reaches `unify00_s2typ`.

Option (1) restores the older, graceful behavior and is presumably the smaller
change.

## Impact / interim handling on the LSP side

Narrow: only files that place an under-applied constructor in a called position
trip it — in practice the handful of compiler-linking driver files in this
server. The resident server already **catches** the abort and publishes a single
informational diagnostic (`could not analyze … ; other files unaffected`) so one
bad file never takes down analysis of the rest. No LSP change is required; this
report exists so the underlying compiler gap can be fixed at the source.
