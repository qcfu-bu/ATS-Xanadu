# WS-1a — LSP diagnostics checker (`xats-lsp-check.js`)

The one-shot **checker** the LSP server spawns per document version. It runs the
ATS3 compiler **front-end** on one source file and writes the §4 JSON bundle
(diagnostics populated; `hovers`/`definitions` empty in this phase) to
`--json-out`.

```
node --stack-size=8801 --max-old-space-size=8192 \
     BUILD/xats-lsp-check.js <src.dats|sats> --uri <uri> --json-out <path.json>
```

## Files

| File | Role |
|---|---|
| `DATS/xats_lsp_check.dats` | The checker. Runs `d3parsed_of_fil{sats,dats}`, then a **new traversal** (modeled on `srcgen2/DATS/f3perr0_dynexp.dats` + `f3perr0_decl00.dats` + `f2perr0_dynexp.dats`) that finds every `…errck` node, reads its wrapped node's **internal 0-based** location, classifies it into a §4.1 `code` + message, and pushes it to the JS accumulator. |
| `CATS/xats_lsp_check.cats` | JS glue: argv access, a string-buffer FILR (to print a type via the compiler's own `s2typ_fprint`), the diagnostics accumulator, **dedup (Decision D6)**, friendly type-name mapping, JSON serialization, `fs.writeFileSync`. |
| `HATS/xats_lsp_harvest.hats` | The **shared** harvest traversal (diagnostics + hover + go-to-def + semantic tokens), `#include`d by both the CLI checker and the resident server. Each consumer binds the abstract `diag_push`/`hover_push`/`def_push`/`token_push` sinks. |
| `build-lib2xatsopt.sh` | **One-time** (~6–9 min): compiles the whole front-end to `srcgen2/lib/lib2xatsopt.js` (the compiler-as-a-library). |
| `build.sh` | Transpiles the driver and **cat-links** runtime + `lib2xatsopt.js` + glue + driver → `BUILD/xats-lsp-check.js`. |

## Build (the "compiler-linking build")

This is **distinct from the WS-0a FFI-spike build**: the driver calls the
compiler front-end, so it must be linked together with the whole compiler.

```sh
export XATSHOME=/Users/qcfu/Projects/ATS-Xanadu
bash build-lib2xatsopt.sh    # one-time: builds srcgen2/lib/lib2xatsopt.js (~171 MB)
bash build.sh                # builds BUILD/xats-lsp-check.js
```

### Key facts (deviations from primer §10.3 — for the architect)

1. **Transpiler = `jsemit00`, NOT `jsemit01`.** Use
   `xassets/JS/xats2js/xats2js_jsemit00_ats2_opt1.js`. The `jsemit01_*_opt1`
   asset (fine for the FFI spike) **mis-emits ~23 closure templates** in
   `trans01_staexp.dats` (e.g. `list_map$e1nv_vt`) as an unresolved
   `XATSDAPP(...debug AST...)` blob containing `//` from locations — invalid JS
   (parsed as a regex at load). `jsemit00` resolves all templates.

2. **Runtime link list differs from the spike.** The compiler headers staload
   `srcgen1/prelude`, so we link the **srcgen1** runtime, not srcgen2_prelude*:
   ```
   srcgen2/.../xats2js_js1emit.js
   srcgen2/.../srcgen2_precats.js
   srcgen1/.../srcgen1_prelude.js
   srcgen1/.../srcgen1_prelude_node.js   (provides XATSOPT_argv$get etc.)
   srcgen1/.../srcgen1_xatslib_node.js
   ```
   then `sed -E 's/jsx(...)tnm/js1\1tnm/g' lib2xatsopt.js`, then your `.cats`,
   then the transpiled driver. (Order matters; the `.cats` `require()`s are not
   hoisted, so they precede the driver.)

3. **`lib2xatsopt.js` is built per-file** with `jsxtnm → jsx<N>tnm` namespacing
   (matching `srcgen2/Makefile_xjsemit`), then the link-time `js1\1` transform.
   The driver's own templates stay `jsxtnm`, disjoint from the library's.

4. **Driver `#include`s** the same compiler headers as `tcheck00.dats`
   (`libxatsopt.hats`, `xatsopt_sats.hats`, `xatsopt_dpre.hats`), with paths
   reaching back into `srcgen2/`. It additionally `#staload`s
   `locinfo.sats` / `lexing0.sats` / `dynexp1.sats` (the SATS that
   `libxatsopt.hats` does not, but the traversal needs).

5. **Memory.** The non-minified `lib2xatsopt.js` is ~171 MB; run with
   `--max-old-space-size=8192`. Normal files run fine; the heaviest staload
   closures can still OOM — but those crash the **stock** compiler too
   (`xatsopt_tcheck01_ats2_opt1.js`), so it is a compiler limit, not a checker
   bug. (Minifying the lib with closure-compiler — the stock `*_opt1` path —
   would shrink it; left as a follow-up.)

## What it classifies

| `code` | from | message |
|---|---|---|
| `type-mismatch` | `D3Et2pck(expr, expected)` under `…errck`; actual = `expr.styp()` | `` expected `X`, got `Y` `` (head-of-type names; common ones mapped to `int`/`string`/`bool`/…) |
| `unbound-identifier` | `D2Enone1(D1Eid0 name)` | `` unbound identifier `name` `` |
| `unresolved-template` | `D3Etimp` / `D3Etimq` | `unresolved template instantiation` |
| `pattern-error` | `D?Perrck` not otherwise classified | `pattern error` |
| `decl-error` | `D?Cerrck` wrapper | `declaration error` (usually deduped away) |
| `unknown` | fallback | `type error` |

**Dedup (D6):** collapse by begin-position keeping the smallest range; drop
outer wrappers that strictly contain a more specific diagnostic; drop
`decl-error`s overlapped by a precise diagnostic.

**Coordinates (D5):** `line = nrow`, `character = ncol` — internal **0-based**
values read via `loc.pbeg()/.pend()` and `pos.nrow()/.ncol()`. Byte columns
(ASCII-correct v1; UTF-16 conversion is WS-4).
