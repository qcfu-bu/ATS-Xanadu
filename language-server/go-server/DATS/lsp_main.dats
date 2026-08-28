(* ****** ****** *)
(*
lsp_main.dats — the driver: a single-threaded, TAIL-RECURSIVE resident
dispatch loop (the Go backend's TCO makes [serve] an O(1)-stack
for-loop).  M1 surface: initialize / initialized / shutdown / exit;
unknown requests get -32601; unknown notifications are ignored.

The loop owns all state as parameters (the input buffer); there is no
module-level mutable state in M1.
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
init_result((*void*)): jval =
let
val sync =
JVobj
( JKVcons("openClose", JVtrue()
, JKVcons("change", JVint(1), JKVnil())))
val caps =
JVobj(JKVcons("textDocumentSync", sync, JKVnil()))
val info =
JVobj
( JKVcons("name", JVstr("ats3-lsp")
, JKVcons("version", JVstr("0.1.0"), JKVnil())))
in
JVobj
( JKVcons("capabilities", caps
, JKVcons("serverInfo", info, JKVnil())))
end//endof[init_result]
//
(* ****** ****** *)
//
fun
send_msg(jv0: jval): void =
lsp_write_out(frame_wrap(json_ser(jv0)))
//
fun
respond
(idv: jval, res: jval): void =
send_msg
(JVobj
( JKVcons("jsonrpc", JVstr("2.0")
, JKVcons("id", idv
, JKVcons("result", res, JKVnil())))))
//
fun
respond_err
(idv: jval, code: sint, msg: string): void =
send_msg
(JVobj
( JKVcons("jsonrpc", JVstr("2.0")
, JKVcons("id", idv
, JKVcons("error"
, JVobj
  ( JKVcons("code", JVint(code)
  , JKVcons("message", JVstr(msg), JKVnil())))
, JKVnil())))))
//
(* ****** ****** *)
//
(* handle one message body; 0 = continue serving, 1 = exit *)
fun
on_msg(body: string): sint =
let
val jv0 = json_parse(body)
in
if jis_err(jv0)
then (respond_err(JVnull(), 0 - 32700, "parse error"); 0)
else
let
val mth = jget_str(jobj_get(jv0, "method"), "")
val idv = jobj_get(jv0, "id")
in
if streq(mth, "initialize")
then (respond(idv, init_result()); 0) else
if streq(mth, "initialized") then 0 else
if streq(mth, "shutdown")
then (respond(idv, JVnull()); 0) else
if streq(mth, "exit") then 1 else
if jis_err(idv) then 0 (* unknown notification: ignore *)
else
(
respond_err
(idv, 0 - 32601, strn_append("method not found: ", mth)); 0)
end
end//endof[on_msg]
//
(* ****** ****** *)
//
fun
serve(buf: string): void =
case+ frame_next(buf) of
| FRmsg(body, rest) =>
  (
  if (on_msg(body) = 0)
  then serve(rest)
  else lsp_write_log("ats3-lsp: exit\n"))
| FRnone() =>
  let
  val c0 = lsp_read_chunk()
  in
  if (strn_length(c0) <= 0)
  then lsp_write_log("ats3-lsp: stdin closed\n")
  else serve(strn_append(buf, c0))
  end
| FRerr(msg) =>
  lsp_write_log
  (strn_append("ats3-lsp: framing error: ", strn_append(msg, "\n")))
//
(* ****** ****** *)
//
fun
server_main((*void*)): void =
let
val () = lsp_write_log("ats3-lsp: server started\n")
in
serve("")
end//endof[server_main]
//
(* ****** ****** *)
val ((*the_entry_point*)) = server_main((*void*))
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_main.dats] *)
(***********************************************************************)
