# ATS3 (ATS-Xanadu) Compiler Primer — for LSP Implementors

> **Purpose.** Onboarding doc so a human or a subagent can become productive on the
> ATS3 LSP without re-running weeks of code discovery. Everything here was verified
> against the source at `/Users/qcfu/Projects/ATS-Xanadu` (branch `LSP`) and by running
> the prebuilt compiler. File:line citations are hints — they can drift; treat the
> **named functions/datatypes** as the stable anchors and re-grep if a line is off.

---

## 0. TL;DR orientation

- ATS3 = "Applied Type System", v3. A dependently-typed systems language. v3 adds an
  **ML-like (algebraic, quantifier-free) type-checking layer** on top of the older
  dependent layer, so a program can be compiled after passing only the simple layer.
- The compiler is **self-hosted (written in ATS3)** and **transpiles to JavaScript**
  (also to Python and C). It runs on `node`.
- The compiler front-end is a **pipeline of AST translations** `L0 → L1 → L2 → L3`.
  Each translation is paired with a **"proofread" pass** that does *not* fail fast —
  instead it **wraps bad nodes in error constructors inside the AST** and bumps an error
  counter, to be reported later. This non-fail-fast design is exactly what an LSP wants.
- For the LSP we only need the **front-end (parse + typecheck)**, never codegen.
  A front-end-only driver already exists and ships prebuilt as a node script.

### The single most useful fact for each LSP goal
| Goal | Key fact |
|---|---|
| **Diagnostics** | Errors are `…errck` wrapper nodes embedded in the typed AST; every AST node has `.lctn()` giving a `loctn` (file + begin/end position). Harvest by traversal. |
| **Hover** | Every typed expression node `d3exp` carries its type: `d3exp.styp() : s2typ`. Find node under cursor → print its `s2typ`. |
| **Go-to-def** | `d2var`/`d2cst`/`d2con` carry their **binding-site location** as field #1, and the **same entity object** is embedded at every use site. So `useNode.entity.lctn()` *is* the definition location — no symbol-table lookup needed. |

---

## 1. Repository layout (top level)

| Path | What it is | Relevant? |
|---|---|---|
| `srcgen2/` | **The current compiler**, written in ATS3 (the bootstrapped "srcgen2"). **This is where 95% of LSP-relevant code lives.** | ★★★ primary |
| `srcgen1/` | Older ATS3 compiler written in ATS2 (used to bootstrap srcgen2). Mostly ignore, but a few JS FFI shims live only here (e.g. `srcgen1/prelude/DATS/CATS/JS/NODE/xatsopt.cats`). | ★ reference |
| `prelude/` | The ATS3 prelude (standard library core). Compiled into every program. | ★★ |
| `xatslib/` | Extra ATS3 libraries (incl. `githwxi/` user libs, `libcats/` the C/JS-binding layer with `FILR`, IO). | ★★ FFI/IO source |
| `xassets/JS/` | **Prebuilt, ready-to-run JS compilers** (`node`-runnable). `xatsopt/xatsopt_tcheck01_ats2_opt1.js` = the **front-end type-checker**. `xats2js/xats2js_jsemit01_ats2_opt1.js` = the `.dats`→`.js` transpiler. | ★★★ we run these |
| `srcgen2/xats2js/` | The ATS3→JS backend (separate sub-compiler). Has its own `srcgen1`/`srcgen2`. Current = `srcgen2`. | ★★ build/FFI lowering |
| `srcgen2/xats2js/srcgenx/xshared/runtime/` | The **JS runtime pieces** (`srcgen2_precats.js`, `srcgen2_prelude.js`, `srcgen2_prelude_node.js`, `srcgen2_xatslib.js`, …) that get **concatenated** with compiled output to form a runnable program. | ★★★ linking |
| `Makefile_buildjs`, `srcgen2/Makefile_x*` | Build rules. | ★★ |
| `language-server/` | **NEW — our LSP project.** `client/` (VSCode extension, TS) and `server/` (ATS3 LSP server). `docs/` = this primer + the plan. | ★★★ our code |

**File-type conventions:** `.sats` = static/interface (declarations, datatypes, function
signatures — like a `.h`/`.mli`). `.dats` = dynamic/implementation (like a `.c`/`.ml`).
`.hats` = header include fragments. `.cats` = **raw C-or-JS** companion code injected by FFI
directives. `.keeper`/`.00` = scratch/backup, ignore.

---

## 2. The compiler pipeline (front-end)

Source flows through these stages. Each `transNN` produces the next AST level; each
`treadNN`/`pread00`/`fperrNN` is a proofread/report pass. Interfaces in `srcgen2/SATS/`,
impls in `srcgen2/DATS/`.

```
text
 │  lexbuf0 / lexing0           lexing + tokenization
 ▼
L0 AST  (dynexp0/staexp0)       parse  →  pread00 (proofread L0)
 │  trans01                     fixity resolution
 ▼
L1 AST  (dynexp1/staexp1)       →  tread01
 │  trans12                     binding resolution (names → entities)
 ▼
L2 AST  (dynexp2/staexp2)       →  tread12
 │  trans2a (pre-typecheck) + trsym2b (overload resolution)
 │                              →  t2read0 / f2perr0  (L2 error report)
 │  trans23                     SIMPLE TYPE-CHECKING  (the ML-like layer)
 ▼
L3 AST  (dynexp3 + statyp2)     →  tread23
 │  trans3a (+ tread3a / f3perr0)   normalize template args, table top-level templates
 ▼
[front-end ends here for the LSP]
 │  trtmp3b / trtmp3c           template resolution (CODEGEN-ONLY — we don't run this)
 ▼  IR (intrep) → js1emit       JS emission
```

**Levels at a glance**
- **L0**: raw parse tree. `d0exp`, `s0exp`, etc.
- **L1**: fixity resolved (operators grouped). `d1exp`, `s1exp`.
- **L2**: **binding resolved** — identifiers are linked to entities (`d2var`/`d2cst`/`d2con`/`s2cst`). `d2exp`, `s2exp`. This is the first level with real semantic identity.
- **L3**: **type-checked** — every `d3exp` carries its inferred `s2typ`. `d3exp`, types as `s2typ` (`statyp2.sats`).

**Key design property (verified):** errors are **not** thrown. `transNN`/`treadNN` insert
`…errck` nodes and increment a counter. A *later* traversal prints them. This means a file
with errors still produces a (partial) typed AST you can walk — ideal for diagnostics,
hover, and go-to-def even on broken code.

---

## 3. The per-file front-end API (what the LSP calls)

**Public signatures:** `srcgen2/SATS/xatsopt.sats` (impl in `srcgen2/DATS/xatsopt_utils0.dats`):

```
fun d2parsed_of_filsats(fpth: string): d2parsed   // parse+typecheck a .sats through L2
fun d2parsed_of_fildats(fpth: string): d2parsed   // ...a .dats through L2
fun d3parsed_of_filsats(fpth: string): d3parsed   // ...a .sats through L3 (full front-end)
fun d3parsed_of_fildats(fpth: string): d3parsed   // ...a .dats through L3
fun d2parsed_of_trans02(dpar: d0parsed): d2parsed // run L0→L2 on an already-parsed handle
fun d3parsed_of_trans03(dpar: d0parsed): d3parsed // run L0→L3 on an already-parsed handle
```

**The AST handle progression** is a boxed record per level: `d0parsed → d1parsed →
d2parsed → d3parsed`. Each bundles `{ stadyn (0=sats/1=dyn), nerror, source: lcsrc,
…topenv…, parsed: d?eclistopt }`. Accessors you will use constantly:
- `d3parsed_get_nerror(dpar): sint` — total error count (skip work if 0).
- `d3parsed_get_parsed(dpar): d3eclistopt` — the declaration list to traverse.
- `d3parsed_get_source(dpar): lcsrc` — the file identity.
- (same shape for `d2parsed_get_*`).

**In-memory / unsaved buffers:** `d0parsed_from_atext(stadyn, source)`
(`srcgen2/SATS/parsing.sats`) parses **text already in memory** (no file on disk). Pair with
`d3parsed_of_trans03` to typecheck a dirty editor buffer. ⚠️ Note: staloaded *dependencies*
are still resolved from the **filesystem**, so the dirty buffer's imports must exist on disk.

**The driver to copy:** `srcgen2/UTIL/xatsopt_tcheck00.dats` (and `_tcheck01`). Its
`mymain_work(fpath)` dispatches on extension → `d3parsed_of_fil{sats,dats}` → reports errors
with `f3perr0_d3parsed(g_stderr(), dpar)`. **No output file is written.** This is the exact
skeleton for our checker; we replace the text report with structured JSON emission.

**Dependency model.** `#staload "x.sats"` is typechecked **on demand, depth-first, once**,
the first time it's encountered, and cached **process-globally** by canonical filename in
append-only tables (`the_d1parenv`/`the_d2parenv`/`the_d3parenv`/`the_d3tmpenv` in
`srcgen2/DATS/xglobal.dats`). So checking file X transitively parses+typechecks all its
staloads on a cold cache. There is **no cache invalidation** and **no dependents-recheck**.

---

## 4. ⚠️ Re-entrancy: the compiler is ONE-SHOT (critical architectural constraint)

**The compiler cannot correctly type-check a second unrelated file in the same process.**
There is **no reset/clear/init API** anywhere in the tree. Global mutable state that leaks
between runs:
- **Stamp counters** (`stamper_getinc`, `xstamp0.dats`) — monotonic unique-id generators per
  entity kind; never reset.
- **Symbol intern tables** (`_MYMAP_` name→symbol, `the_xsymbls` stamp→symbol) — append-only.
- **Global envs** (`xglobal.dats`: `the_fxtyenv`, `the_sexpenv`, `the_d2cstmap`, the four
  `the_d?parenv` file caches) — accumulate, no delete.
- **Prelude loaders are load-once** (gated by `the_ntime` counters): after file #1, file #1's
  top-level defs stay merged into the global envs, so file #2 would see them as if prelude.

**Consequence for architecture:** run each type-check in a **fresh `node` process that exits
after one file** (process-per-check, optionally pooled). Do **not** try to keep a resident
in-process compiler. See the plan doc; this is decided.

---

## 5. Location model (`srcgen2/SATS/locinfo.sats`) — read carefully

```
postn = POSTN of (sint ntot, sint nrow, sint ncol)   // a point
loctn = LOCTN of (lcsrc lsrc, postn pbeg, postn pend) // a half-open [pbeg,pend) range
lcsrc = LCSRCnone0 | LCSRCsome1 of strn | LCSRCfpath of fpath   // the source
```
Accessors (symloaded): `loc.lsrc()`, `loc.pbeg()`, `loc.pend()`; `pos.ntot()`, `pos.nrow()`,
`pos.ncol()`. Every AST node: `node.lctn(): loctn`.

### Indexing — VERIFIED, and there is a display trap
**Internal values are 0-based.** The lexer starts at `POSTN(0,0,0)`; each byte does
`ntot+=1; ncol+=1`; a newline does `ntot+=1; nrow+=1; ncol:=0`.
- `nrow`: **0-based line.**
- `ncol`: **0-based column, counted in BYTES (UTF-8), not codepoints/UTF-16.**
- `ntot`: **0-based byte offset.**
- `loctn_dummy()` = `POSTN(-1,-1,-1)` — treat negative as "no location".

**⚠️ The display trap.** `loctn_fprint`/`postn_fprint` print **1-based** values (they add +1).
Running the stock checker on `val x: int = "hello"` prints the `"hello"` literal as
`@(14(line=1,offs=14)--21(line=1,offs=21))`, but the **internal** position is
`ntot=13,nrow=0,ncol=13 .. ntot=20,nrow=0,ncol=20`. **Use the internal accessors; never parse
the printed text.** (This is one more reason to emit our own structured output.)

### Converting `loctn` → LSP `Range`
LSP wants 0-based line + 0-based **UTF-16** character.
- **line** = `nrow` directly (both 0-based). ✅ no adjustment.
- **character** = `ncol` directly **iff the line is ASCII**. For non-ASCII content, `ncol` is a
  byte offset and must be converted to a UTF-16 offset by re-reading the line's bytes. (Plan:
  ship ASCII-correct v1, add UTF-16 conversion as a hardening task.)
- **uri** from `lsrc`: `LCSRCfpath(fp)` → `fpath_get_fnm1/fnm2` (`filpath.sats`) → `file://` URI.

---

## 6. Diagnostics subsystem (LSP goal #1)

**No error datatype, no global error list.** Errors are **wrapper constructors in the AST**,
each `(sint lvl, wrapped_node)`:
- L1: `D1Perrck`/`D1Eerrck`/`D1Cerrck`, `S1Eerrck`, `G1Eerrck` (`dynexp1.sats`/`staexp1.sats`)
- L2: `D2Perrck`/`D2Eerrck`/`D2Cerrck` (`dynexp2.sats`), `S2Eerrck` (`staexp2.sats`)
- L3: `D3Perrck`/`D3Eerrck`/`D3Cerrck` (`dynexp3.sats`)

(~13 constructors total: pattern/expr/decl per level.) The wrapper has **no location of its
own** and **no message string**; location comes from `wrapped.lctn()`, and the "message" in the
stock reporter is just the **pretty-printed offending node**.

- `lvl` is **error-nesting depth, NOT severity.** A root error is `lvl=1`; each enclosing
  wrapper is `+1`. Reporters suppress `lvl >= 3` to throttle cascade duplicates
  (`FPEMSG_ERRLVL = 3`). There are **no warnings** — everything is an error.
- The count rides on the handle: `d3parsed_get_nerror`.

**Reporters (print-only today):** `f3perr0_d3parsed(out: FILR, dpar)` and `f2perr0_d2parsed`
(richer family — handles template-instantiation errors `D3Etimp`/`D3Etimq` and can print
expected/actual `s2exp` via `f2perr0_s2exp`). Plus an older `*_fpemsg` family. Both **print to
a FILR**; neither returns a structured list.

### What real errors look like (empirical)
Running the stock checker on a file with a type error and an unbound name shows:
- **Type mismatch** → `D3Eerrck(1; D3Et2pck(<expr>; <actualType s2typ>; <expectedType s2typ>))`.
  e.g. `D3Et2pck(D3Estr("hello"); T2Pcst(the_s2exp_strn0); T2Papps(T2Pcst(gint_type);…))`.
  **`D3Et2pck` = the type-coercion node carrying (expr, actual, expected)** — this is the hook
  for a real *"expected int, got string"* message.
- **Unbound identifier** → `D2Eerrck(1; D2Enone1(D1Eid0(nonexistent_var)))`.
- **Redundancy:** the same root error appears multiple times — at L2 (`F2PERR0`/`D2Eerrck`) and
  again at L3 (`F3PERR0`/`D3Cerrck` wrapping it via `D3Cnone1`), and as inner expr + outer decl
  wrappers. **The harvester MUST dedup**, preferring the innermost (smallest-range) node and
  collapsing by begin-position.
- Exit code is **0 even with errors** — do not rely on exit status; use `nerror`/parse output.

### Recommended diagnostics hook
Write a **new traversal** modeled structurally on `f3perr0_d3exp`/`auxmain`
(`srcgen2/DATS/f3perr0_dynexp.dats`) that, at each `…errck` case, instead of printing, **pushes
`(loctn, severity, code, message)` to an accumulator**. Keep the `lvl < 3` filter; dedup by
begin-position. Synthesize messages per constructor (`D3Et2pck`→type mismatch with both
`s2typ`s; `D2Enone1(D1Eid0 x)`→"unbound identifier `x`"; `D3Etimp/timq`→"unresolved template").
Emit as JSON (see plan §contract).

---

## 7. Type model (LSP goal #2: hover)

**Every typed node carries its type.** `srcgen2/SATS/dynexp3.sats`:
```
fun d3exp_get_styp(d3e: d3exp): s2typ     // d3e.styp()
fun d3exp_get_node(d3e: d3exp): d3exp_node
fun d3exp_get_lctn(d3e: d3exp): loc_t      // d3e.lctn()
```
(`d3pat` likewise has `.styp()`.) So **hover = position→node search + print the node's
`s2typ`.**

**The type representation is `s2typ`** (`srcgen2/SATS/statyp2.sats`), not `s2exp`. Key
constructors of `s2typ_node`:
```
T2Pcst  of s2cst                              // type constant: int, bool, …
T2Pvar  of s2var                              // type variable
T2Pxtv  of x2t2p                              // existential / unification var
T2Papps of (s2typ, s2typlst)                  // application  F<args>
T2Pfun1 of (s2typ, sint npf, s2typlst, s2typ) // function type
T2Pexi0 of (s2varlst, s2typ)                  // ∃-quantified
T2Puni0 of (s2varlst, s2typ)                  // ∀-quantified
T2Ptrcd of (trcdknd, sint, l2t2plst)          // tuple/record
T2Ps2exp of s2exp …                           // lifted static expr
T2Perrck of (int, s2typ)                      // type-error marker
```

**⚠️ The only existing printer (`s2typ_fprint`) emits DEBUG form**, e.g. a function type prints
as `T2Pfun1(…;…;…;…)` and an application as `T2Papps(tfun; args)` — unreadable for hover.
The leaf printers are clean (`s2cst_fprint` prints the bare name). **Hover therefore needs a
new ~70-line source-syntax pretty-printer over `s2typ_node`** (mechanical; the type is already
attached, so there's no semantic difficulty). This is the main hover cost.

**Hover feasibility: EASY–MEDIUM.** Biggest obstacle = the pretty-printer. Secondary = the
byte→UTF-16 column conversion for non-ASCII.

---

## 8. Symbol / definition model (LSP goal #3: go-to-def)

**The decisive fact:** level-2 entities carry their binding-site location as **field #1**, and
trans12 embeds the **same entity object** at every use site (shared identity), so a use node's
entity already knows where it was defined.

`srcgen2/DATS/dynexp2.dats` (getters in `srcgen2/SATS/dynexp2.sats`):
```
d2var = D2VAR of (loc_t lctn, sym_t name, …, s2exp sexp, s2typ styp, stamp, …)
d2cst = D2CST of (loc_t lctn, sym_t name, …, s2exp sexp, stamp, s2typ styp, …)
d2con = D2CON of (loc_t lctn, …)            // data constructor
```
Getters: `d2var_get_lctn`, `d2cst_get_lctn`, `d2con_get_lctn`; types via `_get_sexp`/`_get_styp`.
Static-side: `s2cst_get_lctn` (`staexp2.sats`) — type constants carry their def location too.
(`s2var` has **no** location — type variables are positionless.)

**Use sites** carry the entity at both levels:
- L2 `d2exp_node`: `D2Evar of d2var`, `D2Ecst of d2cst`, `D2Econ of d2con`, plus overload sets
  `D2Econs of d2conlst` / `D2Ecsts of d2cstlst`.
- L3 `d3exp_node`: `D3Evar of d2var`, `D3Econ of d2con`, `D3Ecst of d2cst`.

**Binding resolution** (`srcgen2/SATS/trans12.sats`): a name → `d2itm` via
`tr12env_find_d2itm(env, key): d2itmopt_vt` (qualified: `tr12env_qfind_d2itm`), where
```
d2itm = D2ITMvar of d2var | D2ITMcon of d2conlst | D2ITMcst of d2cstlst | D2ITMsym of …
```
The `d2var` is **created once at its binding site** (`d2var_new2_name(loc0, sym1)`,
`loc0 = dpid.lctn()`) and that object is reused at every use.

**Go-to-def algorithm:** position→node search → extract `d2var`/`d2cst`/`d2con` → return
`entity.lctn()` → map to LSP `Location` (file from `lctn.lsrc()`, range from `pbeg`/`pend`).

**Navigation variants:**
| Request | Target | Feasible at front-end? |
|---|---|---|
| Definition | `entity.lctn()` (binding/declaration site) | ✅ yes |
| Type-definition | `d3e.styp()` → head `T2Pcst(s2c)` → `s2cst_get_lctn(s2c)` | ✅ yes (type *vars* not navigable) |
| Implementation | resolved template/overload instance | ⚠️ partial: single consts ✅; overloaded/template need `trtmp3b/3c` output |

**Caveat:** `d2cst` exposes only its **declaration** location (no `d2cst_get_def`). Go-to the
*implementation body* of a constant needs a **separately-built stamp-keyed index** over
`implement` decls. Go-to-declaration works out of the box.

**Go-to-def feasibility: EASY.** Position→node search is shared with hover.

---

## 9. Position → node search (shared infra for hover + go-to-def)

**Does not exist yet — must be written.** Best template to copy: `f3perr0_d3exp` + its `auxmain`
helper (`srcgen2/DATS/f3perr0_dynexp.dats`) — the cleanest full mutually-recursive walk over the
whole `d3exp` family (`d3exp`/`d3pat`/`f3arg`/`d3gua`/`d3cls`/`d3ecl`), already reading `.lctn()`
per node, dispatching `case+ d3e.node() of` with one arm per constructor. Reusable list/option
fan-out helpers exist (`f3perr0_d3explst`/`d3expopt`, generic `list_f3perr0_fnp`).

**Algorithm:** outermost-first recursion; at each node test
`P.ntot ∈ [loc.pbeg().ntot(), loc.pend().ntot())` (single-scalar `ntot` test avoids row/col edge
cases — convert the LSP position to a byte offset once up front, or carry nrow/ncol and compare
lexicographically). Recurse into children; the **deepest** containing node wins (children are
strictly inside parents). Cross-check against `d3exp_fprint` (`dynexp3_print0.dats`) as the
authoritative checklist that all ~70 constructors are handled.

---

## 10. JS FFI, build, and run (foundation for the ATS3 server)

### 10.1 FFI mechanism (identity name-mapping)
ATS3 binds external JS by declaring a function whose **emitted JS name is identical** to the ATS
name, then supplying that JS function via a `.cats` file:
```
#extern fun XATS2JS_NODE_g_print(x0: strn): void = $extnam()   // ATS decl
```
```js
function XATS2JS_NODE_g_print (x0) { process.stdout.write(x0.toString()); return; }  // .cats body
```
- `= $extnam()` ⇒ "this ATS function IS the same-named global JS function". `$` is legal in JS
  identifiers and survives verbatim.
- **`#extcode file "path.cats"`** inlines a raw JS file into the emitted output (link-time JS
  injection). Inline `#extcode` with a JS string literal also exists.
- The idiomatic wrapper pairs a typed `#impltmp foo<> = JSNAME where { #extern fun JSNAME(...) =
  $extnam() }` with a `.cats` body. Values map natively: `sint`↔number, `strn`↔string,
  `bool`↔boolean, ATS closure↔JS function, `a1sz`↔array. Wrap opaque JS objects (a Connection,
  an fs module) as `#abstype` handles — zero marshalling.
- **Callbacks** (needed for JSON-RPC handlers) use the `$fwork` idiom: pass an ATS lambda where
  JS expects a function; it becomes a JS function. Precedent:
  `myfil00$fpath_readall$fwork(fpath, lam(cs) => …)` in `xatslib/githwxi/DATS/myfil00.dats`.
- **`require('npm-mod')`** is just JS inside a `.cats`: `const M = require('vscode-languageserver/node')`.
  Precedent: `srcgen2_prelude_node.js` does `const XATS2JS_NODE_fs = require('node:fs')`.

### 10.2 IO precedents to copy
- File handle type `FILR` (= `FILEref`): `xatslib/libcats/DATS/gbas000.dats`. `g_stdin/stdout/stderr`
  → `process.stdin/stdout/stderr`. `*_fprint(obj, out)` → `out.write(...)`.
- Read a file: `fs.readFileSync(path).toString()` — see
  `xatslib/githwxi/DATS/CATS/JS/NODE/myfil00.cats` and the compiler's own
  `XATSOPT_fpath_full$read`. Existence: `fs.accessSync(p, R_OK)`.
- `process.argv` → `XATSOPT_argv$get()` (compiler) / `process_argv()` (lib). `argv[2]` is the
  first user arg.

### 10.3 Build + run recipe (a `.dats` → runnable node program)
> ✅ **VERIFIED end-to-end by WS-0a** (`language-server/spikes/ffi/`), including
> `require('vscode-jsonrpc')` and ATS↔JS callbacks. The recipe below incorporates its
> corrections (the original draft had two wrong runtime entries).
```sh
export XATSHOME=/Users/qcfu/Projects/ATS-Xanadu
# 1) transpile .dats → .js using the prebuilt JS-emit compiler
node --stack-size=8801 \
  $XATSHOME/xassets/JS/xats2js/xats2js_jsemit01_ats2_opt1.js  myprog.dats  > myprog_dats.js
# 2) "link" = concatenate runtime pieces + YOUR .cats glue + your compiled output.
#    NOTE: exactly these 5 runtime files, IN THIS ORDER. Your hand-written .cats must be
#    cat'd in YOURSELF and must come BEFORE myprog_dats.js (its `const X=require(...)`
#    lines are not hoisted). srcgen2_prelude_node.js is REQUIRED for any node IO.
R=$XATSHOME/srcgen2/xats2js/srcgenx/xshared/runtime
cat $R/xats2js_js1emit.js $R/srcgen2_precats.js $R/srcgen2_prelude.js \
    $R/srcgen2_prelude_node.js $R/srcgen2_xatslib.js \
    myprog.cats  myprog_dats.js  > app.js
# 3) run (top-level vals/main execute on load). Run where any npm deps resolve.
node app.js
```
- ⚠️ **`srcgen2_xatslib_node.js` does NOT exist** in the runtime dir (only a `_hd` stub) — do
  not `cat` it. The link list is **5** runtime files, not 6.
- ⚠️ **Build-error detection:** the transpile step exits **0 even on success AND on type
  errors**. Detect a *bad transpile* by grepping the transpiler's **stderr** for `PERR0-ERROR`
  (the header `F3PERR0_D3PARSED:` always prints and is not an error). Do **not** trust `$?`.
- `--stack-size=8801` is needed **when compiling** (the compiler is deeply recursive); the
  produced program has no such requirement.
- There is **no linker / no package.json integration** — linking is literally `cat`. To pull in
  npm modules, `require()` them from a `.cats`; **`require` resolves relative to `app.js`'s own
  directory** (independent of cwd), so ship `app.js` next to its `node_modules` (or set
  `NODE_PATH=<abs>/node_modules`).
- Working minimal examples: `prelude/TEST/CATS/JS/test00_prelude.dats` (in-tree) and
  **`language-server/spikes/ffi/`** (our verified spike — the best reference for FFI + npm).
- ⚠️ **Entry-point convention (VERIFIED by WS-1b):** the srcgen2/JS prelude has **no
  `implement main`** — that ATS2/C-backend form fails to parse (`D2Enone1(D1Eid0(implement))`).
  Define an ordinary `fun myprog_main(): void = let … end` and invoke it with a **top-level
  `val () = myprog_main()`** (top-level `val`s run on load). This is exactly what
  `srcgen2/UTIL/xatsopt_tcheck00.dats` does. Two working LSP programs follow it:
  `language-server/server/lsp-server/` (the server) and the spike.

### 10.4 Prebuilt compilers we run directly (no build needed)
- **Front-end type-checker:** `xassets/JS/xatsopt/xatsopt_tcheck01_ats2_opt1.js`
  → `node --stack-size=8801 <that> file.dats`. Verified working: clean file → just a header;
  bad file → `F2PERR0-ERROR`/`F3PERR0-ERROR` lines with locations. **Heavy debug tracing is
  printed** (`d0parsed_from_fpath: source = …` for every prelude file) — so a machine consumer
  must isolate real output on a clean channel (temp file / sentinel), not scrape raw stdout.
- **JS transpiler:** `xassets/JS/xats2js/xats2js_jsemit01_ats2_opt1.js`.

**FFI feasibility for the LSP server: HIGH.** The compiler itself is already a node program that
`require`s `fs`, reads argv, reads files, and writes streams — the exact shape of an LSP server.
Binding `vscode-languageserver/node` is a mechanical application of `#extern … = $extnam()` +
a `.cats` glue file + the `cat`-link step.

---

### 10.5 Compiler-linking build — the checker (VERIFIED by WS-1a)
The §10.3 recipe builds a *standalone* program. The **checker** is different: it must link the
**whole compiler front-end** (it calls `d3parsed_of_fil…`). Authoritative scripts:
`language-server/server/build-lib2xatsopt.sh` + `build.sh`. The hard-won facts:
- **Two steps:** (1) build the compiler-as-a-library `srcgen2/lib/lib2xatsopt.js` (~171 MB,
  162 `.dats`, one-time ~6–9 min; per-file transpile with `jsxtnm→jsx<N>tnm` namespacing from
  `srcgen2/Makefile_xjsemit`); (2) transpile the driver and `cat`-link it against the lib.
- ⚠️ **Use the `jsemit00` transpiler, NOT `jsemit01`.** `xats2js_jsemit00_ats2_opt1.js` resolves
  all templates; the `jsemit01_*_opt1` asset **mis-emits ~23 closure templates** in
  `trans01_staexp.dats` (e.g. `list_map$e1nv_vt`) as an invalid blob that crashes at load.
  (The FFI spike §10.3 happened to dodge this; the compiler-linking build does not.)
- **Runtime link list differs from §10.3** (compiler headers staload `srcgen1/prelude`):
  `srcgen2/.../{xats2js_js1emit,srcgen2_precats}.js` + `srcgen1/.../{srcgen1_prelude,
  srcgen1_prelude_node,srcgen1_xatslib_node}.js` (the last provides `XATSOPT_argv$get`), then
  the namespaced `lib2xatsopt.js`, then the `.cats`, then the driver. **Not** the
  `srcgen2_prelude*.js` set.
- **Driver staloads:** the `tcheck00` headers (`libxatsopt.hats`, `xatsopt_sats.hats`,
  `xatsopt_dpre.hats`) **plus** `locinfo.sats`, `lexing0.sats`, `dynexp1.sats` (which
  `libxatsopt` omits but a diagnostics/position traversal needs). Don't re-`#symload` accessors.
- ⚠️ **Run flags are REQUIRED:** `node --stack-size=8801 --max-old-space-size=8192 …`. Without
  `--stack-size` the checker **stack-overflows in the lexer** (`lxbf1_take_clst`/`f0_IDFST`);
  the 171 MB unminified lib wants the larger heap. The **server passes these flags when spawning
  the checker** (`xats-lsp-server.cats`, overridable via `ATS3_LSP_CHECKER_NODE_ARGS`).
- **Artifact:** `language-server/server/BUILD/xats-lsp-check.js`; the server probes
  `../BUILD/xats-lsp-check.js` (or `$ATS3_LSP_CHECKER`). Verified end-to-end: server → real
  checker → diagnostics at exact contract coordinates, ~1.9 s for a 2-file handshake.
- **ATS3 syntax gotchas (WS-1a):** mutual recursion must be top-level `fun … and …` (not
  `extern fun`+`implement` in `where`); `D2Eflat`/`D2Cimplmnt0` differ in arity from their L3
  counterparts.
- ✅ **Minification (Closure SIMPLE) — DONE and default.** `build.sh` runs
  `npx google-closure-compiler --compilation_level SIMPLE` on the linked checker (mirrors the
  repo's own `*_opt1` rule, e.g. `srcgen2/UTIL/Makefile_xjsemit:70`). **Measured: 173 MB → 4.0 MB
  (~43×), cold start 0.63 s → 0.39 s, max RSS ~1032 MB → ~230 MB, and `--max-old-space-size` is no
  longer needed** (so the earlier OOM-on-pathological-files caveat is moot for the minified
  build). Output is `BUILD/xats-lsp-check.opt1.js`; **the server prefers it** (`XLSP_pick_checker`
  probes `.opt1.js` before the raw `.js`). Set `MINIFY=0` to skip the ~25 s closure pass during
  fast dev iteration (the server then falls back to the raw bundle). **Use SIMPLE only** —
  ADVANCED would rename `$extnam`/`require` FFI names and break the build.

## 11. Quick file index (grep anchors)

| Concern | SATS (interface) | DATS (impl) |
|---|---|---|
| Locations | `locinfo.sats`, `filpath.sats` | `locinfo.dats`, `lexing0_utils2.dats` (pos advance) |
| Errors/report | `f2perr0.sats`, `f3perr0.sats`, `tread23.sats` | `f3perr0_dynexp.dats` (★ traversal template), `tread23_*.dats` |
| L2 AST/entities | `dynexp2.sats`, `staexp2.sats` | `dynexp2.dats`, `trans12_dynexp.dats` (binding) |
| L3 AST/types | `dynexp3.sats`, `statyp2.sats` | `dynexp3.dats`, `trans23.dats` (typecheck), `statyp2_print0.dats` (type printer) |
| Symbols/stamps | `xsymbol.sats`, `xstamp0.sats`, `xsymenv.sats` | `xsymbol.dats`, `xglobal.dats` (global state ★) |
| Driver / per-file API | `xatsopt.sats`, `parsing.sats` | `xatsopt_utils0.dats`, `UTIL/xatsopt_tcheck00.dats` (★ driver to copy) |
| FFI / IO | — | `prelude/DATS/CATS/JS/**`, `xatslib/libcats/DATS/**`, `xatslib/githwxi/DATS/CATS/JS/NODE/myfil00.{dats,cats}` |
| Runtime/link | — | `srcgen2/xats2js/srcgenx/xshared/runtime/*.js` |

---

## 12. Known risks / open questions (carry into the plan)

1. **One-shot compiler** → process-per-check architecture (decided; see plan §3).
2. **No dependency-cache invalidation / no dependents-recheck** → each edit re-checks the whole
   staload closure from cold; rely on debounce. Cross-file "edit A, see error in B" is out of
   scope for v1.
3. **Debug tracing on stdout** → emit structured output to a temp file or sentinel-delimited
   block; investigate whether the trace prints can be cheaply silenced in our own driver.
4. **No message strings / no severity** → we author per-constructor messages; everything maps to
   `DiagnosticSeverity.Error` for v1.
5. **Type printer is debug-form** → write a source-syntax `s2typ` pretty-printer for hover.
6. **byte vs UTF-16 columns** → ASCII-correct v1; add UTF-16 conversion as hardening.
7. **Cold-start cost** → typechecking one file loads the whole prelude every time; measure, and
   if too slow consider caching the position/hover/def indices per document version so only a
   *content change* re-runs the compiler (see plan: "compile once per version, serve from cache").
