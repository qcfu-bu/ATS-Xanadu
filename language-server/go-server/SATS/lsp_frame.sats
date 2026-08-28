(* ****** ****** *)
(*
lsp_frame.sats — the LSP base-protocol (Content-Length) framing, as a
PURE state machine over a byte buffer.  The driver owns the buffer as a
loop parameter and feeds it chunks from the floor; frame_next never
blocks and never does I/O.
*)
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
//
datatype
fropt =
| FRnone of ()                  (* incomplete: need more input *)
| FRmsg of (string, string)     (* (body, remaining buffer) *)
| FRerr of (string)             (* framing desync: description *)
//
(* extract the next complete message from buf, if any *)
fun
frame_next(buf: string): fropt
//
(* wrap a body for the wire: Content-Length header + CRLFCRLF + body *)
fun
frame_wrap(body: string): string
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_frame.sats] *)
(***********************************************************************)
