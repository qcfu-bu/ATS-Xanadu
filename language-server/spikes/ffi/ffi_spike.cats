////////////////////////////////////////////////////////////////////////.
//                                                                    //.
//                  WS-0a  Toolchain & FFI spike                      //.
//                  JS-glue companion for ffi_spike.dats              //.
//                                                                    //.
////////////////////////////////////////////////////////////////////////.
//
// HX-LSP-WS0a:
// This file is the ".cats" (raw-JS companion) half of the FFI idiom
// documented in ATS3-COMPILER-PRIMER.md S10.1.  Every ATS3 function
// declared with `#extern fun NAME(...) : T = $extnam()` is implemented
// here by a same-named JS function (the `$` in the name survives into
// JS verbatim, and is a legal JS identifier char).
//
// It is NOT pulled in by `#extcode file` from the .dats; instead it is
// `cat`-concatenated into the final app.js by build.sh, exactly the way
// the prelude's own *.cats are linked (see prelude/HATS/prelude_JS_cats.hats
// uses `#extcode file`, but for a standalone spike the simplest, most
// robust route proven by the Makefile recipe is plain concatenation).
//
////////////////////////////////////////////////////////////////////////.
//
// (1) require() a node builtin AND a real npm module.
//     Precedent: prelude/DATS/CATS/JS/NODE/node000.cats does
//       const XATS2JS_NODE_fs = require('node:fs')
//     We add the npm module vscode-jsonrpc (the real JSON-RPC library
//     family the LSP server will use).
//
const FFISPIKE_fs = require('node:fs')
const FFISPIKE_jsonrpc = require('vscode-jsonrpc')
//
////////////////////////////////////////////////////////////////////////.
//
// (1a) Call JS from ATS3: a plain console.log greeting.
//
function
FFISPIKE_console_log(x0)
{
  console.log(x0.toString());
  return; // FFISPIKE_console_log
}
//
////////////////////////////////////////////////////////////////////////.
//
// (2a) Evidence that the node builtin `node:fs` is live: report its type.
//
function
FFISPIKE_fs_probe()
{
  return ("node:fs.readFileSync is a "
          + (typeof FFISPIKE_fs.readFileSync));
}
//
// (2b) Evidence that the npm module `vscode-jsonrpc` is live and usable:
//      construct a CancellationTokenSource, flip it, and report the
//      transition  false -> true.  Also report how many symbols the
//      module exports (proves the whole module object resolved).
//
function
FFISPIKE_jsonrpc_probe()
{
  const cts = new FFISPIKE_jsonrpc.CancellationTokenSource();
  const before = cts.token.isCancellationRequested;
  cts.cancel();
  const after = cts.token.isCancellationRequested;
  const nexport = Object.keys(FFISPIKE_jsonrpc).length;
  return ("vscode-jsonrpc loaded: "
          + nexport + " exports; "
          + "CancellationTokenSource isCancellationRequested "
          + before + " -> " + after);
}
//
////////////////////////////////////////////////////////////////////////.
//
// (3a) argv access.  process.argv is a JS string array; argv[2] is the
//      first user-supplied argument (node app.js <file>  =>  argv[2]).
//      We return the COUNT as a number (maps to ATS3 `sint`) and the
//      element at an index as a string (maps to ATS3 `strn`), keeping
//      the ATS3 side free of array-marshalling.
//      Precedent: gbas000.cats XATS2JS_NODE_process_argv returns
//      process.argv as a1sz(strn); we deliberately stay scalar here.
//
function
FFISPIKE_argv_count()
{
  return process.argv.length;
}
// returns the count as a string, so the ATS3 side never has to do
// numeric->string formatting (keeps the .dats simple + total).
function
FFISPIKE_argv_count_str()
{
  return String(process.argv.length);
}
function
FFISPIKE_argv_get(i0)
{
  return process.argv[i0];
}
//
// (3b) read a whole file and report its byte length + first line.
//      Synchronous read, same as myfil00.cats and the compiler's own
//      fpath reader.  On error returns a sentinel string so the ATS3
//      side stays total.
//
function
FFISPIKE_file_length(fpath)
{
  try {
    return FFISPIKE_fs.readFileSync(fpath).length;
  } catch (error) {
    return (-1);
  }
}
// string form, same reason as FFISPIKE_argv_count_str.
function
FFISPIKE_file_length_str(fpath)
{
  try {
    return String(FFISPIKE_fs.readFileSync(fpath).length);
  } catch (error) {
    return ("-1 (could not read)");
  }
}
function
FFISPIKE_file_firstline(fpath)
{
  try {
    const txt = FFISPIKE_fs.readFileSync(fpath).toString();
    const nl  = txt.indexOf("\n");
    return (nl < 0 ? txt : txt.slice(0, nl));
  } catch (error) {
    return ("<<could not read: " + fpath + ">>");
  }
}
//
////////////////////////////////////////////////////////////////////////.
//
// (4) ATS->JS callback (the `$fwork` idiom, primer S10.1).  JS calls the
//     ATS3 closure that was handed to it.  This is exactly the shape of
//     a JSON-RPC handler registration: a library function that stores /
//     invokes a callback we provide from ATS3.
//     Precedent: myfil00.cats XATS2JS_NODE_myfil00$fpath_readall$fwork
//     does `work(<string>)`.
//
function
FFISPIKE_run_callback(work)
{
  // invoke the ATS3-supplied closure twice, with two different strings,
  // to prove it is a genuine callable carrying ATS3 behaviour.
  work("first-callback-invocation");
  work("second-callback-invocation");
  return; // FFISPIKE_run_callback
}
//
// A callback that mimics an event emitter: vscode-jsonrpc ships an
// Emitter; we register the ATS3 closure as its listener and fire one
// event, proving ATS3 closures survive into a real npm event API.
//
function
FFISPIKE_jsonrpc_emit(work)
{
  const emitter = new FFISPIKE_jsonrpc.Emitter();
  emitter.event(function (payload) { work(payload); });
  emitter.fire("event-via-vscode-jsonrpc-Emitter");
  emitter.dispose();
  return; // FFISPIKE_jsonrpc_emit
}
//
////////////////////////////////////////////////////////////////////////.
////////////////////////////////////////////////////////////////////////.
// end of [language-server/spikes/ffi/ffi_spike.cats]
////////////////////////////////////////////////////////////////////////.
////////////////////////////////////////////////////////////////////////.
