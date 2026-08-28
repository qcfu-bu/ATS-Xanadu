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
(***********************************************************************)
(* end of [lsp_floor.sats] *)
(***********************************************************************)
