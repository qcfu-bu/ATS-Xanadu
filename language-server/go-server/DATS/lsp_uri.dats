(* ****** ****** *)
(*
lsp_uri.dats — file:// URI codec.  See lsp_uri.sats.
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
fun
u_hexval(c0: sint): sint =
if (c0 >= 48)
then
(
if (c0 <= 57) then c0 - 48 else
if (c0 >= 97)
then (if (c0 <= 102) then c0 - 87 else (0 - 1))
else
if (c0 >= 65)
then (if (c0 <= 70) then c0 - 55 else (0 - 1)) else (0 - 1))
else (0 - 1)
//
(* ****** ****** *)
//
#implfun
uri_to_path
(uri) =
if strn_starts_at(uri, 0, "file://")
then
let
val n0 = strn_length(uri)
(* the path begins at the first '/' at or after index 7
   (file:///p -> 7 is it; file://host/p -> after the host) *)
fun
findsl(k0: sint): sint =
if (k0 >= n0) then (0 - 1) else
if (byte_at(uri, k0) = 47) then k0 else findsl(k0+1)
val p0 = findsl(7)
in
if (p0 < 0) then "" else
strn_make_fwork
( lam(emit) =>
  let
  fun
  loop(k0: sint): void =
  if (k0 >= n0) then () else
  let
  val c0 = byte_at(uri, k0)
  in
  if (c0 = 37)
  then
  (
  if (k0+2 < n0)
  then
  let
  val h1 = u_hexval(byte_at(uri, k0+1))
  val h2 = u_hexval(byte_at(uri, k0+2))
  in
  if (h1 < 0)
  then (emit(char_make_sint(c0)); loop(k0+1)) else
  if (h2 < 0)
  then (emit(char_make_sint(c0)); loop(k0+1))
  else (emit(char_make_sint(h1*16 + h2)); loop(k0+3))
  end
  else (emit(char_make_sint(c0)); loop(k0+1)))
  else (emit(char_make_sint(c0)); loop(k0+1))
  end
  in loop(p0) end)
end
else ""
//
(* ****** ****** *)
//
fun
u_unreservedq(c0: sint): bool =
if (c0 >= 97)
then (if (c0 <= 122) then true else (c0 = 126)) else
if (c0 >= 65)
then (if (c0 <= 90) then true else (c0 = 95)) else
if (c0 >= 48)
then (if (c0 <= 57) then true else false) else
if (c0 = 45) then true else
if (c0 = 46) then true else
if (c0 = 47) then true else false
//
#implfun
path_to_uri
(path) =
strn_make_fwork
( lam(emit) =>
  let
  val n0 = strn_length(path)
  fun
  hexd(v0: sint): void =
  if (v0 < 10)
  then emit(char_make_sint(48 + v0))
  else emit(char_make_sint(55 + v0))  (* UPPERCASE *)
  fun
  loop(k0: sint): void =
  if (k0 >= n0) then () else
  let
  val c0 = byte_at(path, k0)
  val () =
  (
  if u_unreservedq(c0)
  then emit(char_make_sint(c0))
  else (emit(char_make_sint(37)); hexd(c0/16); hexd(c0 - (c0/16)*16)))
  in
  loop(k0+1)
  end
  val fsch = "file://"
  fun
  hdr7(k0: sint): void =
  if (k0 >= 7) then () else
  (emit(strn_get$at(fsch, k0)); hdr7(k0+1))
  in
  (hdr7(0); loop(0))
  end)
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_uri.dats] *)
(***********************************************************************)
