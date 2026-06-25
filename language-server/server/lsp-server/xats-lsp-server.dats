(* ****** ****** *)
(*
WS-1b: the LSP server core (P1).

A standalone ATS3 -> JS node program: a working Language Server over stdio
that, on document open/change, runs the (one-shot) checker and publishes
diagnostics. It owns the JSON-RPC connection lifecycle, TextDocument sync,
the debounce decision, a per-(uri,version) cache of the parsed checker
bundle (so WS-2/WS-3 can answer hover/def from it later), and the
spawn -> read-json -> map -> publish pipeline.

Architecture: LSP-ARCHITECTURE-AND-PLAN.md S2 (process model), S3 (D1-D9),
S4 (the FROZEN JSON contract this consumes), S6 WS-1b.
Build/FFI: ATS3-COMPILER-PRIMER.md S10 (FFI + the VERIFIED build recipe S10.3).

ATS3 / .cats split (the ".cats holds substantial JS" idiom; the compiler's own
IO is thin ATS3 over .cats):
  * ATS3 (this file) drives ALL control flow / lifecycle:
      - main: configure checker, create connection, register handlers, listen
      - the open/change callbacks: the DEBOUNCE decision (schedule a per-uri
        timer); on fire, the check pipeline
      - the check pipeline: write-temp -> spawn -> read-json -> CACHE -> publish
      - the close callback: clear diagnostics + drop cache entry
  * .cats (xats-lsp-server.cats) is the FFI marshalling layer: it require()s the
    npm libs and node builtins and exposes same-named JS bodies for each
    `#extern fun NAME(...) = $extnam()`. It hands ATS3 only scalars (strn/sint/
    bool) and opaque handles -- zero marshalling on the ATS3 side. The
    per-(uri,version) bundle cache is a JS Map in the .cats, but EVERY put/get/
    drop is decided and invoked from ATS3 here (ATS3 owns when to cache, when to
    look up, when to evict). The LSP Diagnostic[] array for a given uri+version
    is shaped in the .cats from the parsed bundle (kept as an opaque handle),
    per the brief's "shape the LSP diagnostics in .cats and hand ATS3 opaque
    handles" option -- keeping the .dats free of JSON/array marshalling.

Idioms / build are copied from the VERIFIED WS-0a spike
  language-server/spikes/ffi/{ffi_spike.dats,ffi_spike.cats,build.sh}.
*)
(* ****** ****** *)
//
#staload _ =
"prelude/DATS/gdbg000.dats"
//
(* ****** ****** *)
//
#include
"prelude/HATS/prelude_dats.hats"
//
#include
"prelude/HATS/prelude_JS_dats.hats"
//
(* ****** ****** *)
//
// ---- FFI bindings (S10.1: `#extern fun NAME(...) = $extnam()` says
//      "this ATS3 function IS the same-named JS global", supplied by
//      xats-lsp-server.cats). All args/results are scalars or opaque
//      handles, so the ATS3 side never marshals arrays/objects. ----
//
(* ****** ****** *)
//
// (a) logging to stderr (stdout is the JSON-RPC channel; NEVER write there).
//
#extern
fun
XLSP_log(msg: strn): void = $extnam()
//
// (b) configuration: the checker command is configurable via the env var
//     ATS3_LSP_CHECKER (default: the real xats-lsp-check.js path). Reading the
//     env + node-exe path is trivial JS; we expose them as accessors so the
//     ATS3 main can log them.
//
#extern
fun
XLSP_checker_path((*0*)): strn = $extnam()
#extern
fun
XLSP_debounce_ms((*0*)): sint = $extnam()
//
// (c) connection lifecycle. createConnection over stdio (handles the
//     --stdio/--node-ipc/--socket flags, falling back to explicit stdin/stdout
//     streams when launched bare, exactly like the WS-0b stub). The handles are
//     module-global in the .cats, so we model the connection/documents as
//     unit-returning setup calls rather than threading opaque handles around --
//     simplest and matches the single-connection reality of a stdio server.
//
#extern
fun
XLSP_connection_make((*0*)): void = $extnam()
//
// onInitialize: advertise capabilities. We register a NULLARY ATS3 callback so
// ATS3 owns the "we are initializing" moment (logging); the actual capability
// object (textDocumentSync incremental, hoverProvider, definitionProvider) is
// returned from JS where the library enums live.
//
#extern
fun
XLSP_on_initialize(cb: () -> void): void = $extnam()
//
// document events. The TextDocuments manager (full/incremental sync handled by
// the library) calls back into ATS3 with SCALARS: uri, version, and the full
// current text. ATS3 then makes the debounce decision.
//
#extern
fun
XLSP_on_open(cb: (strn, sint, strn) -> void): void = $extnam()
#extern
fun
XLSP_on_change(cb: (strn, sint, strn) -> void): void = $extnam()
#extern
fun
XLSP_on_close(cb: (strn) -> void): void = $extnam()
//
// hover / definition / type-definition (WS-2 / WS-3, server side).
//
// These are answered PURELY from the per-(uri,version) cache -- NO recompile,
// NO checker spawn. The library hands the request `params` to JS, which
// extracts the SCALARS (uri, line, character) and forwards them to the ATS3
// callback. ATS3 OWNS the lookup decision: it calls a thin `.cats` search
// primitive that does the Map access + innermost-range-contains scan and
// returns the chosen entry INDEX (or -1 = none); ATS3 inspects that index and
// returns it (>= 0 to build a result, -1 for null). The `.cats` wrapper then
// shapes the LSP Hover / Location object from (uri, index) -- keeping the .dats
// free of any JSON/array marshalling, consistent with the diagnostics split.
//
// (b1) hover: cb(uri, line, char) -> chosen hover index (or -1). The .cats
//      builds `{ contents:{kind:"markdown", value:"```ats\n"+type+"\n```"},
//      range:<hover.range> }` from that index, else returns null.
//
#extern
fun
XLSP_on_hover(cb: (strn, sint, sint) -> sint): void = $extnam()
//
// (b2) definition: cb(uri, line, char) -> chosen definition index (or -1). The
//      .cats builds the LSP Location `{ uri:defUri, range:defRange }`.
//
#extern
fun
XLSP_on_definition(cb: (strn, sint, sint) -> sint): void = $extnam()
//
// (b3) type-definition: same use-site innermost-contains scan over the SAME
//      `definitions` array, but the .cats builds `{ uri:typeDefUri,
//      range:typeDefRange }` and returns null when those optional fields are
//      absent. ATS3 returns the chosen definition index (or -1).
//
#extern
fun
XLSP_on_type_definition(cb: (strn, sint, sint) -> sint): void = $extnam()
//
// the innermost-range search primitives (the contains/innermost helper lives in
// the .cats, but ATS3 INVOKES it and decides what to do with the result):
//
//   XLSP_hover_find(uri, line, char): among the latest cached bundle's
//   `hovers`, return the index of the INNERMOST (smallest-span) entry whose
//   `range` contains the position, or -1 if no bundle / no containing entry.
//
#extern
fun
XLSP_hover_find(uri: strn, line: sint, char: sint): sint = $extnam()
//
//   XLSP_definition_find(uri, line, char): same, over `definitions`, scanning
//   each entry's `useRange`. Returns the chosen index or -1.
//
#extern
fun
XLSP_definition_find(uri: strn, line: sint, char: sint): sint = $extnam()
//
// listen: documents.listen(connection); connection.listen().
//
#extern
fun
XLSP_listen((*0*)): void = $extnam()
//
(* ****** ****** *)
//
// (d) debounce: per-uri coalescing timer. XLSP_debounce_schedule(uri, cb)
//     (re)arms a setTimeout for `uri` of XLSP_debounce_ms(); a prior pending
//     timer for the same uri is cleared first (coalescing didChange bursts).
//     On fire it invokes the ATS3 closure `cb`. The ATS3 side decides WHEN to
//     schedule (every open/change) -- the .cats just owns the timer table.
//
#extern
fun
XLSP_debounce_schedule(uri: strn, cb: () -> void): void = $extnam()
#extern
fun
XLSP_debounce_cancel(uri: strn): void = $extnam()
//
(* ****** ****** *)
//
// (e) the check pipeline primitives (each a thin scalar/handle FFI call):
//
//   write the current buffer to a temp file, PRESERVING the .dats/.sats
//   extension (the checker dispatches on it), returning the temp path.
//
#extern
fun
XLSP_tmp_write(uri: strn, text: strn): strn = $extnam()
//
//   spawnSync the checker:  node <checkerJs> <tmpSrc> --uri <uri>
//                                --json-out <tmpJson>
//   (one check at a time; we debounce). Returns the --json-out path that was
//   used (so ATS3 can hand it to the reader). stdout of the checker is IGNORED
//   (debug noise, Decision D3) -- only --json-out is read.
//
#extern
fun
XLSP_run_checker(tmpSrc: strn, uri: strn): strn = $extnam()
//
//   read + JSON.parse the bundle file into an OPAQUE handle stored under
//   (uri, version) in the cache, and report success (true) / failure (false,
//   e.g. unreadable / unparsable -> we publish empty + log). Parsing the JSON
//   and shaping LSP Diagnostic[] stays in JS; ATS3 holds only the cache key.
//
#extern
fun
XLSP_cache_put_from_json
  (uri: strn, version: sint, jsonPath: strn): bool = $extnam()
//
//   look up whether a bundle is cached for (uri, version) -- used to skip a
//   redundant recheck if the version is unchanged (and by later phases).
//
#extern
fun
XLSP_cache_has(uri: strn, version: sint): bool = $extnam()
//
//   drop the cached bundle for a uri (all versions) -- on close.
//
#extern
fun
XLSP_cache_drop(uri: strn): void = $extnam()
//
//   publish: shape the cached bundle's diagnostics into an LSP Diagnostic[] and
//   connection.sendDiagnostics({uri, diagnostics}). The bundle range is ALREADY
//   0-based LSP shape (contract S4), so the mapping is near-identity. If no
//   bundle is cached for (uri, version) -> publishes an EMPTY array (clears).
//
#extern
fun
XLSP_publish(uri: strn, version: sint): void = $extnam()
//
//   publish an explicit empty diagnostics array (clear) for a uri.
//
#extern
fun
XLSP_publish_empty(uri: strn): void = $extnam()
//
(* ****** ****** *)
(* ****** ****** *)
//
// ---- orchestration (ATS3 owns the lifecycle) ----
//
(* ****** ****** *)
//
// run_check uri version: the debounced pipeline body.
//   write-temp -> spawn checker -> read+parse json into cache -> publish.
// All steps are ATS3-sequenced; each primitive is a single FFI call.
//
fun
run_check
  (uri: strn, version: sint, text: strn): void = let
//
  val () =
    XLSP_log("run_check: uri=" + uri + " (debounced fire)")
//
  // 1) write the current buffer to a temp file (keeps the .dats/.sats ext).
  val tmpSrc = XLSP_tmp_write(uri, text)
//
  // 2) spawn the one-shot checker; it writes the bundle to its --json-out.
  //    stdout is ignored (D3); we get back the json path.
  val jsonPath = XLSP_run_checker(tmpSrc, uri)
//
  // 3) read+parse the bundle into the per-(uri,version) cache.
  val ok = XLSP_cache_put_from_json(uri, version, jsonPath)
//
in
//
  if ok then
    let
      val () = XLSP_log("run_check: cached bundle, publishing")
    in
      // 4) publish from the cache (near-identity 0-based mapping in .cats).
      XLSP_publish(uri, version)
    end // end-of-[then]
  else
    let
      val () =
        XLSP_log("run_check: checker produced no readable bundle; clearing")
    in
      XLSP_publish_empty(uri)
    end // end-of-[else]
//
end // end-of-[run_check]
//
(* ****** ****** *)
//
// on_doc uri version text: the shared open/change handler. We make the
// DEBOUNCE decision here in ATS3: (re)arm a per-uri timer that, when it fires,
// runs the check pipeline for THIS version+text. Bursts of didChange for the
// same uri coalesce because XLSP_debounce_schedule clears any prior pending
// timer for that uri first.
//
fun
on_doc
  (uri: strn, version: sint, text: strn): void = let
//
  val () =
    XLSP_log
    ("on_doc: uri=" + uri + " scheduling debounced check")
//
  // The closure captures (uri, version, text) for the deferred run. It is the
  // $fwork callback idiom (S10.1): an ATS3 lambda handed to JS setTimeout.
  val work =
    lam((*void*)): void => run_check(uri, version, text)
//
in
  XLSP_debounce_schedule(uri, work)
end // end-of-[on_doc]
//
(* ****** ****** *)
//
// on_close uri: cancel any pending debounce, drop the cache for the uri, and
// clear its diagnostics in the editor.
//
fun
on_close(uri: strn): void = let
  val () = XLSP_log("on_close: uri=" + uri)
  val () = XLSP_debounce_cancel(uri)
  val () = XLSP_cache_drop(uri)
in
  XLSP_publish_empty(uri)
end // end-of-[on_close]
//
(* ****** ****** *)
//
// ---- hover / definition / type-definition lookup (WS-2 / WS-3) ----
//
// These run on an interactive request, answered PURELY from the cache (NO
// recompile, NO checker spawn). Each is a TINY ATS3 decision over the result of
// a `.cats` innermost-range search:
//
//   1) call the search primitive (Map access + innermost-contains in the .cats)
//      with the request SCALARS (uri, line, char) -> an entry index, or -1.
//   2) ATS3 decides: a non-negative index means "found, build a result"; -1
//      means "no bundle / nothing contains the position" -> the .cats returns a
//      JSON-RPC null. We hand the index straight back.
//
// Keeping the index round-trip THROUGH ATS3 (rather than letting JS both search
// and shape) is what makes the ATS3 layer drive the lookup decision -- exactly
// as the diagnostics pipeline has ATS3 drive every cache put/get/publish.
//
fun
on_hover
  (uri: strn, line: sint, char: sint): sint = let
  val idx = XLSP_hover_find(uri, line, char)
  val () =
    if (idx >= 0)
      then XLSP_log("on_hover: found a containing hover")
      else XLSP_log("on_hover: no containing hover -> null")
in
  idx (* >= 0: build from hovers[idx];  -1: null *)
end // end-of-[on_hover]
//
fun
on_definition
  (uri: strn, line: sint, char: sint): sint = let
  val idx = XLSP_definition_find(uri, line, char)
  val () =
    if (idx >= 0)
      then XLSP_log("on_definition: found a containing use")
      else XLSP_log("on_definition: no containing use -> null")
in
  idx (* >= 0: build Location from definitions[idx];  -1: null *)
end // end-of-[on_definition]
//
fun
on_type_definition
  (uri: strn, line: sint, char: sint): sint = let
  // same use-site scan; the .cats builds from typeDefUri/typeDefRange and
  // returns null if those optional fields are absent at the chosen index.
  val idx = XLSP_definition_find(uri, line, char)
  val () =
    if (idx >= 0)
      then XLSP_log("on_type_definition: found a containing use")
      else XLSP_log("on_type_definition: no containing use -> null")
in
  idx
end // end-of-[on_type_definition]
//
(* ****** ****** *)
(* ****** ****** *)
//
// the entry point. There is no `implement main` in this (srcgen2 JS) prelude:
// the convention (see srcgen2/UTIL/xatsopt_tcheck00.dats) is a `fun ...(): void`
// invoked by a top-level `val () = ...`, which runs on load (WS-0a spike).
//
fun
server_main((*void*)): void = let
//
  val () =
    XLSP_log("xats-lsp-server (ATS3->JS, WS-1b) starting")
  val () =
    XLSP_log("checker = " + XLSP_checker_path())
//
  // 1) create the JSON-RPC connection over stdio.
  val () = XLSP_connection_make()
//
  // 2) register the lifecycle handlers as ATS3 closures.
  val () =
    XLSP_on_initialize
    (lam() => XLSP_log("onInitialize: advertising capabilities"))
//
  val () = XLSP_on_open(lam(u, v, t) => on_doc(u, v, t))
  val () = XLSP_on_change(lam(u, v, t) => on_doc(u, v, t))
  val () = XLSP_on_close(lam(u) => on_close(u))
//
  // 3) wire hover / definition / type-definition (WS-2 / WS-3). Each handler
  //    answers from the cached bundle via an innermost-range lookup; ATS3 owns
  //    the decision and hands back the chosen entry index (or -1 for null).
  val () =
    XLSP_on_hover(lam(u, l, c) => on_hover(u, l, c))
  val () =
    XLSP_on_definition(lam(u, l, c) => on_definition(u, l, c))
  val () =
    XLSP_on_type_definition(lam(u, l, c) => on_type_definition(u, l, c))
//
in
//
  // 4) start listening (documents.listen(connection); connection.listen()).
  XLSP_listen()
//
end // end-of-[server_main]
//
(* ****** ****** *)
(* ****** ****** *)
//
// run the server on load (top-level vals execute when xats-lsp-server.js is
// loaded by node; the connection then keeps the process alive on stdio).
//
val ((*the_entry_point*)) = server_main((*void*))
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [language-server/server/lsp-server/xats-lsp-server.dats] *)
(***********************************************************************)
