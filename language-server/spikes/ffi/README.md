# WS-0a — Toolchain & FFI spike

**Status: PASSING.** This spike proves the full **ATS3 → JS → node → npm** path
end-to-end, producing a documented, repeatable build. It de-risks every later LSP
workstream (the server in WS-1b binds `vscode-jsonrpc`/`vscode-languageserver` the
exact same way).

It demonstrates all four required FFI capabilities in one tiny program:

1. **Call JS from ATS3** — bind & call `console.log` via `#extern fun NAME(...) = $extnam()` + a `.cats` body. Prints a greeting.
2. **`require()` a node builtin AND a real npm module** — `require('node:fs')` and `require('vscode-jsonrpc')`; calls something trivial from each and prints evidence.
3. **argv + file read** — reads `process.argv`, reads the file passed as `argv[2]`, prints its byte-length and first line.
4. **ATS→JS callback** — passes an ATS3 closure to a JS function that invokes it (the `$fwork` idiom), incl. registering it as a listener on a real `vscode-jsonrpc` `Emitter`.

---

## Files

| File | Role |
|---|---|
| `ffi_spike.dats` | The ATS3 program. FFI declarations (`#extern fun … = $extnam()`) + the demonstration logic. |
| `ffi_spike.cats` | The raw-JS companion: `require()`s and the bodies of every `#extern` function (same JS name as the ATS name). |
| `build.sh` | Implements the primer §10.3 recipe (transpile + `cat`-link). Produces `app.js`. |
| `package.json` / `package-lock.json` | Pins the npm dep `vscode-jsonrpc@^9.0.0`. |
| `sample.txt` | A sample input file to pass as `argv[2]`. |
| *(generated)* `ffi_spike_dats.js`, `app.js` | Transpiler output and the linked runnable. Git-ignored. |

---

## Exact commands

```sh
cd language-server/spikes/ffi

# one-time: install the npm dependency next to where app.js will live
npm install vscode-jsonrpc

# build (transpile .dats -> .js, then cat-link runtime + glue + output -> app.js)
export XATSHOME=/Users/qcfu/Projects/ATS-Xanadu
bash build.sh

# run, passing a file as the argument (argv[2])
node app.js sample.txt
```

`build.sh` runs the prebuilt JS-emit compiler with `--stack-size=8801` (required
**when compiling** — the compiler is deeply recursive; the produced program needs no
such flag) and sends the heavy debug trace to **stderr**, so stdout is clean JS.

---

## Real captured output

`bash build.sh` (stderr — the per-prelude-file `d0parsed_from_fpath:` trace — omitted):

```
>> [1/3] transpile ffi_spike.dats -> ffi_spike_dats.js
   transpiled 5002 lines
>> [2/3] link (concatenate) runtime + glue + compiled output -> app.js
   linked 8516 lines into app.js
>> [3/3] done.  Run:  node app.js <somefile>
```

`node app.js sample.txt`:

```
[1] Hello from ATS3 via console.log (JS FFI)!
[2] node:fs.readFileSync is a function
[2] vscode-jsonrpc loaded: 64 exports; CancellationTokenSource isCancellationRequested false -> true
[3] process.argv length = 3
[3] argv[2] = sample.txt
[3] file byte-length = 53
[3] file first line = first line of the sample file
[4] callback fired with payload: first-callback-invocation
[4] callback fired with payload: second-callback-invocation
[4] vscode-jsonrpc Emitter -> ATS3 closure: event-via-vscode-jsonrpc-Emitter
[done] all 4 FFI capabilities exercised.
```

Mapping output → capability:
- `[1]` → **(1)** console.log called from ATS3.
- `[2]` → **(2)** `node:fs` resolved (its `readFileSync` is a function) and `vscode-jsonrpc` resolved (64 exports); a `CancellationTokenSource` was constructed and `cancel()`ed, flipping `isCancellationRequested` `false → true` — real library behaviour, not just a load.
- `[3]` → **(3)** `process.argv` read (length 3), `argv[2]` file read (53 bytes, first line echoed).
- `[4]` → **(4)** an ATS3 closure invoked from JS twice, and the same closure-passing idiom driven through a real `vscode-jsonrpc` `Emitter`.

Running with **no** file argument is also total (guarded):

```
[3] process.argv length = 2
[3] (no file argument; run `node app.js <somefile>`)
```

---

## Deviations from the primer §10.3 recipe (for the architect)

These are precise; the primer should be corrected from them.

1. **`srcgen2_xatslib_node.js` does not exist — drop it from the link list.**
   Primer §10.3 lists six runtime files ending in
   `… srcgen2_xatslib.js srcgen2_xatslib_node.js`. In
   `srcgen2/xats2js/srcgenx/xshared/runtime/` there is **no `srcgen2_xatslib_node.js`**
   (only a 387-byte header stub `srcgen2_xatslib_node_hd`). `cat`-ing it errors
   (`No such file or directory`). `build.sh` links **five** runtime files:
   `xats2js_js1emit.js`, `srcgen2_precats.js`, `srcgen2_prelude.js`,
   `srcgen2_prelude_node.js`, `srcgen2_xatslib.js`.

2. **`srcgen2_prelude_node.js` is REQUIRED, not optional.**
   The §10.3 snippet includes it, but it is easy to read the prelude-only
   `Makefile_jsemit01` `test00` target (which omits it) as the canonical minimum.
   It is **mandatory** for anything touching node (console/fs/argv) — i.e. any real
   program, including the LSP server. (The authoritative Makefile only adds it for the
   node-using targets `test05`/`test99`.)

3. **Your own `.cats` must be `cat`-linked into `app.js`; it is NOT auto-included.**
   The primer shows the FFI `.cats` idiom but the §10.3 `cat` line lists only the
   *runtime* `.cats` (already baked into `srcgen2_*.js`) plus your compiled `.dats.js`.
   For a standalone program your hand-written glue (`ffi_spike.cats`) must be appended
   too — **before** the compiled output, because it contains
   `const X = require(...)` (not hoisted) that the compiled top-level `val`s use on
   load. (The prelude’s own glue is injected via `#extcode file` directives inside
   `prelude/HATS/prelude_JS_cats.hats`; plain `cat` is the simpler equivalent for a
   one-off and is what the test Makefiles do.)

4. **npm resolution rule — precise.** `require('vscode-jsonrpc')` resolves relative to
   **`app.js`'s own directory** (node walks up from there for `node_modules`),
   **independent of the current working directory**. Verified:
   - `app.js` in (or under) a dir with `node_modules/vscode-jsonrpc` → works from *any* cwd (even `/tmp` with an absolute path to `app.js`).
   - `app.js` copied to a dir with no `node_modules` up the tree → `Error: Cannot find module 'vscode-jsonrpc'`.
   - Rescue in that case: `NODE_PATH=<abs>/node_modules node app.js …` (verified working).

   **Implication for WS-1b:** build/ship the server's `.js` next to its `node_modules`
   (or set `NODE_PATH`). No `package.json`/bundler integration is needed at runtime —
   linking is literally `cat`, and `require` does the rest.

5. **Transpiler choice.** The primer §10.3 names the prebuilt
   `xassets/JS/xats2js/xats2js_jsemit01_ats2_opt1.js` — used here and it works. (The
   in-tree Makefiles instead call `srcgen2/xats2js/srcgenx/UTIL/xats2js_jsemit01_ats3.js`
   with `--stack-size=8192`; the prebuilt asset at `--stack-size=8801` is fine.)

6. **Exit-code / error detection while building.** Transpile exit code is **0 even on a
   clean build**; success is the **absence** of `F2PERR0-ERROR` / `F3PERR0-ERROR` lines
   in stderr (the bare `F3PERR0_D3PARSED:` header always prints). A build wrapper should
   grep stderr for `PERR0-ERROR`, not trust `$?`.

---

## Idioms / precedents mimicked (primer anchors)

- **Include headers** copied verbatim from the verified-minimal example
  `prelude/TEST/CATS/JS/test00_prelude.dats`:
  `#staload _ = "prelude/DATS/gdbg000.dats"`, then
  `#include "prelude/HATS/prelude_dats.hats"` and
  `#include "prelude/HATS/prelude_JS_dats.hats"`.
- **`#extern fun NAME(...) = $extnam()` + same-named JS body** — from
  `prelude/DATS/CATS/JS/NODE/node000.{dats,cats}` (`XATS2JS_NODE_g_print`) and
  `xatslib/libcats/DATS/CATS/JS/NODE/gbas000.{dats,cats}` (argv, fprint).
- **`require('node:fs')` in a `.cats`** — from `node000.cats`
  (`const XATS2JS_NODE_fs = require('node:fs')`).
- **`$fwork` callback** (ATS closure invoked from JS: `work(<string>)`) — from
  `xatslib/githwxi/DATS/CATS/JS/NODE/myfil00.{dats,cats}`
  (`XATS2JS_NODE_myfil00$fpath_readall$fwork`).
- **`cat`-link recipe** — from `prelude/TEST/CATS/JS/Makefile_jsemit01` (`test00`,
  `test05`, `test99` targets) and primer §10.3.

### Note on a deliberate simplification
The compiler's argv binding returns `a1sz(strn)` / `jsa1sz(strn)` (an ATS array; see
`gbas000.dats` `process_argv`, `xatsopt_tcheck00.dats`). This spike deliberately keeps
the ATS3 side **scalar** — the `.cats` returns argv count/element and file length as
plain `sint`/`strn` — to avoid the dependent/linear array-marshalling machinery and
keep the spike maximally robust. WS-1b can adopt the `a1sz` binding if it wants the
whole array on the ATS3 side; this spike shows the scalar path is sufficient and
simplest. Likewise, `sint → strn` formatting is done **in JS** (`String(n)`), because
the prelude exposes no `tostring`/`sint→strn` helper that's trivially callable here.
