(* ****** ****** *)
(*
lsp_frame.dats — Content-Length framing.  See lsp_frame.sats.
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
(*
the Content-Length value found in the header block [0, he), or -1.
Header-name matching is exact ("Content-Length:") — the canonical
spelling every LSP client sends.
*)
fun
fr_clen
(buf: string, he: sint): sint =
let
val p0 = strn_index_of(buf, 0, "Content-Length:")
in
if (p0 < 0) then (0 - 1) else
if (p0 >= he) then (0 - 1) else
let
fun
skipsp(k0: sint): sint =
if (k0 >= he) then k0 else
(if (byte_at(buf, k0) = 32) then skipsp(k0+1) else k0)
fun
dig(k0: sint, v0: sint): sint =
if (k0 >= he) then v0 else
let
val c0 = byte_at(buf, k0)
in
if (c0 < 48) then v0 else
if (c0 > 57) then v0 else dig(k0+1, v0*10 + (c0 - 48))
end
val d0 = skipsp(p0 + 15)
in
if (d0 >= he) then (0 - 1) else
if (byte_at(buf, d0) < 48) then (0 - 1) else
if (byte_at(buf, d0) > 57) then (0 - 1) else dig(d0, 0)
end
end//endof[fr_clen]
//
(* ****** ****** *)
//
#implfun
frame_next
(buf) =
let
val n0 = strn_length(buf)
val he = strn_index_of(buf, 0, "\r\n\r\n")
in
if (he < 0) then FRnone() else
let
val body0 = he + 4
val cl = fr_clen(buf, he)
in
if (cl < 0)
then FRerr("missing or malformed Content-Length header") else
if (n0 < body0 + cl)
then FRnone()
else
FRmsg
( strn_slice(buf, body0, body0 + cl)
, strn_slice(buf, body0 + cl, n0))
end
end//endof[frame_next]
//
(* ****** ****** *)
//
#implfun
frame_wrap
(body) =
strn_append
( strn_append("Content-Length: ", itoa(strn_length(body)))
, strn_append("\r\n\r\n", body))
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_frame.dats] *)
(***********************************************************************)
