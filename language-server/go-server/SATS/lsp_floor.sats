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
lsp_spawn_check: start `prog arg1 [arg2]` (arg2 = "" for none) with
XATSHOME=xhome in its environment; input is written to the child's
stdin (then closed; "" closes immediately); stderr is captured.
Returns a nonnegative check id, or -1 if the spawn failed.
*)
fun
lsp_spawn_check
( prog: string, arg1: string, arg2: string
, xhome: string, input: string): sint
//
(* 1 = finished, 0 = still running, -1 = unknown id *)
fun
lsp_check_done(id: sint): sint
//
(* the captured stderr; call only after lsp_check_done = 1 *)
fun
lsp_check_output(id: sint): string
//
(* forget the check (kill it first if still running) *)
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
