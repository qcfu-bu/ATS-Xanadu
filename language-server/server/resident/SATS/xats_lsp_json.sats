(* ****** ****** *)
(*
JSON value + parse/serialize — INTERFACE (portable ATS3, no backend FFI).

The LSP wire is JSON-RPC; `jval` is the in-memory JSON tree shared by the
transport, dispatch, and request builders.  Implementation in
DATS/xats_lsp_json.dats.  Numbers are sint (LSP ids/coordinates/kinds are
integers; a fractional part is parsed and discarded).  Objects keep insertion
order (an assoc list) so a serialized reply matches the field order we build.
*)
(* ****** ****** *)
//
// portable: depends only on the PRELUDE (strings, lists, datatypes), NOT the
// compiler (libxatsopt) — so this module ports to any backend unchanged.
#include "prelude/HATS/prelude_dats.hats"
//
(* ****** ****** *)
//
datatype jval =
  | JVnull of ()
  | JVbool of bool
  | JVint of sint
  | JVstr of string
  | JVarr of list(jval)
  | JVobj of list(@(string, jval))
//
#typedef jpair = @(string, jval)
//
(* ****** ****** *)
//
fun json_parse(text: string): jval
fun json_serialize(v: jval): string
//
// accessors the dispatch + builders read parsed messages through.
fun jget(v: jval, key: string): jval                       // object field, or JVnull
fun jget2(v: jval, k1: string, k2: string): jval           // nested
fun jget3(v: jval, k1: string, k2: string, k3: string): jval
fun jas_str(v: jval, dflt: string): string
fun jas_int(v: jval, dflt: sint): sint
fun jas_bool(v: jval): bool
fun jas_arr(v: jval): list(jval)
fun jis_obj(v: jval): bool
//
(* ****** ****** *)
(*
end of [language-server/server/resident/SATS/xats_lsp_json.sats]
*)
