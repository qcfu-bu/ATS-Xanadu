(* ****** ****** *)
(*
lsp_uri.sats — file:// URI <-> filesystem path, in pure ATS3.
Byte-level %-codec (UTF-8 passes through as bytes); encoding uses
UPPERCASE hex (the VSCode convention).
*)
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
//
(* the decoded path of a file:// uri, or "" if not one *)
fun
uri_to_path(uri: string): string
//
(* file:// uri for an absolute path *)
fun
path_to_uri(path: string): string
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_uri.sats] *)
(***********************************************************************)
