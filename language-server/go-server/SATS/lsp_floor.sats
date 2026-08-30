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
M6 (in-process compiler): the spawn/reap process floor is REPLACED by
two leaves — the check itself is a direct call into the linked
compiler (tchk_check, UTIL/xats2go_tchecklib; its FILR-typed capture
externs are declared in lsp_main.dats, the one module that staloads
the compiler SATS).
*)
//
(* set an environment variable (XATSHOME before the prelude loads) *)
fun
lsp_setenv(name: string, value: string): void
//
(*
run the closure under a panic guard: 1 = completed, 0 = recovered (a
frontend abort fails one check, never the server).
*)
fun
lsp_guard(f0: (sint) -> void): sint
//
(* terminate the server process with the given exit code *)
fun
lsp_exit(code: sint): void
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_floor.sats] *)
(***********************************************************************)
