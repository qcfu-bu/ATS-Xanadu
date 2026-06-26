(* ****** ****** *)
(*
path <-> file:// URI — INTERFACE (portable ATS3).

Percent-encode/decode with full UTF-8 handling done as pure sint arithmetic
(codepoint <-> UTF-8 bytes via /,*,- ; no bitwise, no list-FFI), so it ports to any
backend with the same three leaf primitives the JSON module uses.  Implementation
in DATS/xats_lsp_uri.dats.

`lsp_path2uri` assumes a normalized absolute path (the caller normalizes + applies
any current-doc URI remap — that's stateful server concern, not encoding).
*)
(* ****** ****** *)
//
#include "prelude/HATS/prelude_dats.hats"
//
(* ****** ****** *)
//
fun lsp_path2uri(path: string): string   // "/a/b c"      -> "file:///a/b%20c"
fun lsp_uri2path(uri: string): string    // "file:///a/b%20c" -> "/a/b c"
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_uri.sats]
*)
