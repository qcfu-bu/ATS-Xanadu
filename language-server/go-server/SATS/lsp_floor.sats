(* ****** ****** *)
(*
lsp_floor.sats — the extern-floor INTERFACE of the ATS3 LSP server.

This is the ONLY module through which the server touches the outside
world.  The floor is deliberately tiny (see the plan): raw stdio byte
read/write + a monotonic clock.  Everything else — framing, JSON, the
dispatch loop — is pure ATS3.

The Go bodies live in CATS/GO/lsp_floor.cats (spliced into the emitted
module by tools/build.sh, $->_ mangled), reached through the
XATS2GO_LSP_* externs declared in DATS/lsp_floor.dats.
*)
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
//
(*
lsp_read_chunk: BLOCKING read of some bytes from stdin.
Returns "" exactly at EOF (never on a merely-empty read).
*)
fun
lsp_read_chunk((*void*)): string
//
(* lsp_write_out: write bytes to stdout (the protocol channel). *)
fun
lsp_write_out(s0: string): void
//
(* lsp_write_log: write bytes to stderr (the log channel). *)
fun
lsp_write_log(s0: string): void
//
(* lsp_now_ms: monotonic milliseconds since process start. *)
fun
lsp_now_ms((*void*)): sint
//
(* ****** ****** *)
(* M2 additions: stdin polling + check-process spawn/reap *)
(* ****** ****** *)
//
(*
lsp_poll_stdin: wait up to ms milliseconds (ms < 0 = forever) for stdin
input.  1 = data available (a following lsp_read_chunk will not block);
0 = timeout; 2 = EOF.
*)
fun
lsp_poll_stdin(ms: sint): sint
//
(*
M6 (in-process compiler): checks call the LINKED compiler through the
wire-generated glue shim.  M6.1 makes them ASYNC — one single-flight
goroutine per check, so the event loop keeps answering hover/completion
during a mid-file check; the compiler globals stay single-threaded
(the goroutine ordering gives the happens-before edges).
*)
//
(* set an environment variable (XATSHOME before the prelude loads) *)
fun
lsp_setenv(name: string, value: string): void
//
(*
run the closure under a panic guard: 1 = completed, 0 = recovered (a
frontend abort fails one call, never the server).
*)
fun
lsp_guard(f0: (sint) -> void): sint
//
(*
start the in-process check of path (txt = the live buffer when
stdinq > 0) on the check goroutine.  Returns the check id, or -1 if a
check is already in flight (the caller gates on CKnone, so that is
belt-and-braces).
*)
fun
lsp_check_start
(path: string, txt: string, stdinq: sint): sint
//
(* 1 = finished, 0 = still running, -1 = unknown id *)
fun
lsp_check_done(id: sint): sint
//
(* the captured report text; call only after lsp_check_done = 1 *)
fun
lsp_check_rep(id: sint): string
//
(* the --index records; call only after lsp_check_done = 1 *)
fun
lsp_check_idx(id: sint): string
//
(* 1 = the check completed, 0 = it was cut short by a recovered panic *)
fun
lsp_check_ok(id: sint): sint
//
(*
forget the check.  BLOCKS until the goroutine finishes when it is
still running (a live compiler goroutine is never abandoned) — this
doubles as the drain before a prelude reload.
*)
fun
lsp_check_drop(id: sint): void
//
(* terminate the server process with the given exit code *)
fun
lsp_exit(code: sint): void
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_floor.sats] *)
(***********************************************************************)
