(* ****** ****** *)
(*
lsp_json.sats — JSON values, parsing, and serialization, in pure ATS3.

Strings are UTF-8 BYTE strings end to end: json_parse decodes \uXXXX
escapes to UTF-8 bytes; json_ser emits UTF-8 bytes verbatim and escapes
only what JSON requires.  Numbers: integral syntax parses to JVint;
any other numeric syntax is preserved textually as JVnum (lossless
round-trip; LSP traffic is integer-only in practice).

Parse failure is the JVerr value (total functions, no exceptions);
jobj_get on a missing key is JVerr too, which doubles as the
request-vs-notification test on "id".
*)
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
//
datatype
jval =
| JVerr of ()
| JVnull of ()
| JVtrue of ()
| JVfalse of ()
| JVint of (sint)
| JVnum of (string)
| JVstr of (string)
| JVarr of (jvlst)
| JVobj of (jkvlst)
and
jvlst =
| JVLnil of ()
| JVLcons of (jval, jvlst)
and
jkvlst =
| JKVnil of ()
| JKVcons of (string, jval, jkvlst)
//
(* ****** ****** *)
//
(* parse one JSON document (leading/trailing whitespace tolerated) *)
fun
json_parse(s0: string): jval
//
(* serialize (deterministic: object fields in list order) *)
fun
json_ser(jv0: jval): string
//
(* ****** ****** *)
//
fun
jis_err(jv0: jval): bool
//
(* field k0 of an object, or JVerr *)
fun
jobj_get(jv0: jval, k0: string): jval
//
(* the string payload, or dflt *)
fun
jget_str(jv0: jval, dflt: string): string
//
(* the integer payload, or dflt *)
fun
jget_int(jv0: jval, dflt: sint): sint
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_json.sats] *)
(***********************************************************************)
