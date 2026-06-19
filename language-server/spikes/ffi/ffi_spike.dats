(* ****** ****** *)
(*
WS-0a: Toolchain & FFI spike (P0, critical path)
//
Proves the full ATS3 -> JS -> node -> npm path end-to-end:
  (1) call JS from ATS3 (console.log greeting)
  (2) require() a node builtin (node:fs) AND a real npm module
      (vscode-jsonrpc) and call something from each
  (3) read process.argv and a file passed as an argument
  (4) pass an ATS3 closure to a JS function that invokes it
      (the $fwork callback idiom)
//
Mimics the include headers of the verified-minimal example
  prelude/TEST/CATS/JS/test00_prelude.dats
and the FFI idioms of
  prelude/DATS/CATS/JS/NODE/node000.{dats,cats}
  xatslib/githwxi/DATS/CATS/JS/NODE/myfil00.{dats,cats}
  xatslib/libcats/DATS/CATS/JS/NODE/gbas000.{dats,cats}
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
(* ****** ****** *)
//
// FFI bindings.  Each `#extern fun NAME(...) : T = $extnam()` says
// "this ATS3 function IS the same-named JS global", supplied by
// ffi_spike.cats.  (primer S10.1)
//
(* (1) call JS from ATS3 *)
#extern
fun
FFISPIKE_console_log(x0: strn): void = $extnam()
//
(* (2) evidence the node builtin + npm module loaded *)
#extern
fun
FFISPIKE_fs_probe((*0*)): strn = $extnam()
#extern
fun
FFISPIKE_jsonrpc_probe((*0*)): strn = $extnam()
//
(* (3) argv + file read, kept scalar to avoid array marshalling *)
#extern
fun
FFISPIKE_argv_count((*0*)): sint = $extnam()
#extern
fun
FFISPIKE_argv_count_str((*0*)): strn = $extnam()
#extern
fun
FFISPIKE_argv_get(i0: sint): strn = $extnam()
#extern
fun
FFISPIKE_file_length_str(fpath: strn): strn = $extnam()
#extern
fun
FFISPIKE_file_firstline(fpath: strn): strn = $extnam()
//
(* (4) ATS3 -> JS callback (the $fwork idiom) *)
#extern
fun
FFISPIKE_run_callback(work: (strn) -> void): void = $extnam()
#extern
fun
FFISPIKE_jsonrpc_emit(work: (strn) -> void): void = $extnam()
//
(* ****** ****** *)
(* ****** ****** *)
//
(* ---- (1) call JS from ATS3 ---- *)
//
val () =
FFISPIKE_console_log
("[1] Hello from ATS3 via console.log (JS FFI)!")
//
(* ****** ****** *)
//
(* ---- (2) require() node builtin + npm module ---- *)
//
val () =
FFISPIKE_console_log("[2] " + FFISPIKE_fs_probe())
val () =
FFISPIKE_console_log("[2] " + FFISPIKE_jsonrpc_probe())
//
(* ****** ****** *)
//
(* ---- (3) argv + file read ---- *)
//
val argc =
FFISPIKE_argv_count()
val () =
FFISPIKE_console_log
("[3] process.argv length = " + FFISPIKE_argv_count_str())
//
// argv[2] is the first user arg: `node app.js <file>`.
// Guard so the program is total even with no file argument.
//
val () =
if
(argc >= 3)
then let
  val fpath = FFISPIKE_argv_get(2)
  val nbyte = FFISPIKE_file_length_str(fpath)
  val line0 = FFISPIKE_file_firstline(fpath)
in
  FFISPIKE_console_log("[3] argv[2] = " + fpath);
  FFISPIKE_console_log
  ("[3] file byte-length = " + nbyte);
  FFISPIKE_console_log("[3] file first line = " + line0)
end // then
else
  FFISPIKE_console_log
  ("[3] (no file argument; run `node app.js <somefile>`)")
//
(* ****** ****** *)
//
(* ---- (4) ATS3 -> JS callback ($fwork idiom) ---- *)
//
// The ATS3 closure `cb` closes over a local prefix string, then JS
// invokes it.  Proves event-handler registration (JSON-RPC) will work.
//
val () =
let
  val prefix = "[4] callback fired with payload: "
  val cb = lam(s: strn): void =>
    FFISPIKE_console_log(prefix + s)
in
  FFISPIKE_run_callback(cb)
end
//
// Same closure idiom, but through a real npm-module event API
// (vscode-jsonrpc Emitter), proving ATS3 closures survive into the
// actual library family the server will use.
//
val () =
let
  val cb2 = lam(s: strn): void =>
    FFISPIKE_console_log("[4] vscode-jsonrpc Emitter -> ATS3 closure: " + s)
in
  FFISPIKE_jsonrpc_emit(cb2)
end
//
val () =
FFISPIKE_console_log("[done] all 4 FFI capabilities exercised.")
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [language-server/spikes/ffi/ffi_spike.dats] *)
(***********************************************************************)
