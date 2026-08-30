(* ****** ****** *)
(*
lsp_floor.dats — the extern floor: thin #implfun wrappers over the
XATS2GO_LSP_* leaves.  The Go bodies are CATS/GO/lsp_floor.cats; the
types here are BELIEF-CONSISTENT with those bodies (string params/
returns are Go strings; sint is Go int; void returns any/nil).
*)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_GO_dats.hats"
(* ****** ****** *)
#include
"./../HATS/lspserver_sats.hats"
(* ****** ****** *)
//
#extern
fun
XATS2GO_LSP_read_chunk((*void*)): string = $extnam()
#extern
fun
XATS2GO_LSP_write_out(s0: string): void = $extnam()
#extern
fun
XATS2GO_LSP_write_log(s0: string): void = $extnam()
#extern
fun
XATS2GO_LSP_now_ms((*void*)): sint = $extnam()
#extern
fun
XATS2GO_LSP_poll_stdin(ms: sint): sint = $extnam()
#extern
fun
XATS2GO_LSP_exit(code: sint): void = $extnam()
#extern
fun
XATS2GO_LSP_setenv
(name: string, value: string): void = $extnam()
#extern
fun
XATS2GO_LSP_guard(f0: (sint) -> void): sint = $extnam()
//
(* ****** ****** *)
//
#implfun
lsp_read_chunk() = XATS2GO_LSP_read_chunk()
//
#implfun
lsp_write_out(s0) = XATS2GO_LSP_write_out(s0)
//
#implfun
lsp_write_log(s0) = XATS2GO_LSP_write_log(s0)
//
#implfun
lsp_now_ms() = XATS2GO_LSP_now_ms()
//
#implfun
lsp_poll_stdin(ms) = XATS2GO_LSP_poll_stdin(ms)
//
#implfun
lsp_exit(code) = XATS2GO_LSP_exit(code)
//
#implfun
lsp_setenv(name, value) = XATS2GO_LSP_setenv(name, value)
//
#implfun
lsp_guard(f0) = XATS2GO_LSP_guard(f0)
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_floor.dats] *)
(***********************************************************************)
