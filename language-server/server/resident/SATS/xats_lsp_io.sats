(* ****** ****** *)
(*
The IRREDUCIBLE per-backend FFI floor for the ATS3 LSP server.

Everything else — the JSON parser/serializer, the per-uri index, all dedup/sort,
every request builder (hover/def/refs/symbols/semantic/inlay/completion), the
dispatch, the depgraph, UTF-16 conversion, path utilities, the project index — is
PORTABLE ATS3.  A new backend (Chez, JS, native, …) re-implements ONLY the
functions below (plus env_reset/evict_stamp from xats_lsp_resident.sats, which
delete from the compiler's own per-file topmap caches).

The boundary sits at the MESSAGE level: framing (Content-Length) and the
debounce concurrency (a reader thread on Chez, the event loop on JS) are
genuinely backend-specific, so the floor hands ATS whole messages.
*)
(* ****** ****** *)
//
#include "./../HATS/libxatsopt_resident.hats"
//
(* ****** ****** *)
//
// ---- message-level stdio (framing + debounce concurrency live in the backend) --
//
// read the next Content-Length-framed JSON-RPC message, waiting up to
// `timeout_ms` (0 = block until a message or EOF).  Returns @(kind, text):
//   kind=0 : a message, its body in `text`
//   kind=1 : the timeout elapsed with no message ready (`text`="")  [debounce]
//   kind=2 : EOF — the peer closed stdin (`text`="")
//
fun lsp_msg_read(timeout_ms: sint): @(sint, string)
//
// frame `text` (Content-Length) and write it to stdout, flushed.
fun lsp_msg_write(text: string): void
//
// write `text` to stderr (the server's diagnostic log; stdout is the LSP wire).
fun lsp_log(text: string): void
//
(* ****** ****** *)
//
// ---- filesystem ----
//
fun lsp_fs_exists(path: string): bool
fun lsp_fs_read(path: string): string          // file contents; "" on error
fun lsp_fs_mtime(path: string): double         // mtime in ms; ~1.0 (negative) on error
fun lsp_fs_size(path: string): sint            // size in bytes; ~1 on error
fun lsp_fs_dirlist(path: string): list(string)   // entry names (no "."/"..","node_modules" kept); empty on error
fun lsp_fs_isdir(path: string): bool
fun lsp_fs_realpath(path: string): string      // normalized absolute path ("" on error)
//
(* ****** ****** *)
//
// ---- env + time ----
//
fun lsp_getenv(name: string): string           // "" if unset
fun lsp_now_ms(): double                        // monotonic-ish ms (metrics + debounce timing)
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_io.sats]
*)
