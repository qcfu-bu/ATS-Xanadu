(* ****** ****** *)
(*
lsp_main.dats — the driver: a single-threaded, TAIL-RECURSIVE resident
event loop (the Go backend's TCO makes [serve] an O(1)-stack for-loop).

M2 surface: the M1 lifecycle + textDocument/didOpen|didChange|didSave|
didClose with publishDiagnostics via the check-only compiler driver
(spawned per check; the compiler is one-shot).  Checks run on the
ON-DISK file and are triggered by didOpen/didSave; didChange only
updates the in-memory store (live-buffer checking is the pending
architect decision — see PLAN.md).  All state is loop-carried; there
is no module-level mutable state.

Configuration arrives in initialize.params.initializationOptions:
  { "checker":  "<abs path to xats2go-tcheck>",
    "xatshome": "<abs path to the ATS3 repo>" }
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
(* server state (loop-carried) *)
(* ****** ****** *)
//
datatype
doclst =
| DOCnil of ()
| DOCcons of (string(*uri*), sint(*version*), string(*text*), doclst)
//
datatype
pendlst =
| PNDnil of ()
| PNDcons of (string(*uri*), sint(*deadline ms*), pendlst)
//
datatype
chkst =
| CKnone of ()
| CKrun of (sint(*check id*), string(*uri*), sint(*version*))
//
(* (checker path, xatshome, docs, pending checks, the in-flight check) *)
datatype
srvst =
| SRV of (string, string, doclst, pendlst, chkst)
//
(* ****** ****** *)
(* document store helpers *)
(* ****** ****** *)
//
fun
docs_put
(dl: doclst, uri: string, ver: sint, txt: string): doclst =
case+ dl of
| DOCnil() => DOCcons(uri, ver, txt, DOCnil())
| DOCcons(u0, v0, t0, r0) =>
  (
  if streq(u0, uri)
  then DOCcons(uri, ver, txt, r0)
  else DOCcons(u0, v0, t0, docs_put(r0, uri, ver, txt)))
//
fun
docs_del
(dl: doclst, uri: string): doclst =
case+ dl of
| DOCnil() => DOCnil()
| DOCcons(u0, v0, t0, r0) =>
  (
  if streq(u0, uri)
  then r0
  else DOCcons(u0, v0, t0, docs_del(r0, uri)))
//
fun
docs_version
(dl: doclst, uri: string): sint =
case+ dl of
| DOCnil() => (0 - 1)
| DOCcons(u0, v0, _, r0) =>
  (if streq(u0, uri) then v0 else docs_version(r0, uri))
//
fun
docs_text
(dl: doclst, uri: string): string =
case+ dl of
| DOCnil() => ""
| DOCcons(u0, _, t0, r0) =>
  (if streq(u0, uri) then t0 else docs_text(r0, uri))
//
(* ****** ****** *)
(* pending-check helpers *)
(* ****** ****** *)
//
(* schedule (replacing any earlier deadline for the same uri) *)
fun
pend_put
(pl: pendlst, uri: string, ddl: sint): pendlst =
case+ pl of
| PNDnil() => PNDcons(uri, ddl, PNDnil())
| PNDcons(u0, d0, r0) =>
  (
  if streq(u0, uri)
  then PNDcons(uri, ddl, r0)
  else PNDcons(u0, d0, pend_put(r0, uri, ddl)))
//
(* the first due entry: @(uri-or-"", remaining list) *)
fun
pend_take_due
(pl: pendlst, now: sint): @(string, pendlst) =
case+ pl of
| PNDnil() => @("", PNDnil())
| PNDcons(u0, d0, r0) =>
  (
  if (d0 <= now)
  then @(u0, r0)
  else
  let
  val rr = pend_take_due(r0, now)
  in
  @(rr.0, PNDcons(u0, d0, rr.1))
  end)
//
fun
pend_del
(pl: pendlst, uri: string): pendlst =
case+ pl of
| PNDnil() => PNDnil()
| PNDcons(u0, d0, r0) =>
  (
  if streq(u0, uri)
  then r0
  else PNDcons(u0, d0, pend_del(r0, uri)))
//
fun
pend_emptyq(pl: pendlst): bool =
case+ pl of PNDnil() => true | PNDcons(_, _, _) => false
//
(* ****** ****** *)
(* outgoing messages *)
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
(* publishDiagnostics; ver < 0 omits the version field *)
fun
publish
(uri: string, ver: sint, diags: jval): void =
let
val prms =
(
if (ver < 0)
then
JVobj
( JKVcons("uri", JVstr(uri)
, JKVcons("diagnostics", diags, JKVnil())))
else
JVobj
( JKVcons("uri", JVstr(uri)
, JKVcons("version", JVint(ver)
, JKVcons("diagnostics", diags, JKVnil()))))): jval
in
send_msg
(JVobj
( JKVcons("jsonrpc", JVstr("2.0")
, JKVcons("method", JVstr("textDocument/publishDiagnostics")
, JKVcons("params", prms, JKVnil())))))
end//endof[publish]
//
(* ****** ****** *)
(* handlers *)
(* ****** ****** *)
//
fun
init_result((*void*)): jval =
let
val sync =
JVobj
( JKVcons("openClose", JVtrue()
, JKVcons("change", JVint(1)
, JKVcons("save", JVtrue(), JKVnil()))))
val caps =
JVobj(JKVcons("textDocumentSync", sync, JKVnil()))
val info =
JVobj
( JKVcons("name", JVstr("ats3-lsp")
, JKVcons("version", JVstr("0.2.0"), JKVnil())))
in
JVobj
( JKVcons("capabilities", caps
, JKVcons("serverInfo", info, JKVnil())))
end//endof[init_result]
//
fun
h_initialize
(jv0: jval, idv: jval, st: srvst): srvst =
let
val opts =
jobj_get(jobj_get(jv0, "params"), "initializationOptions")
val chk = jget_str(jobj_get(opts, "checker"), "")
val xh = jget_str(jobj_get(opts, "xatshome"), "")
val () = respond(idv, init_result())
in
case+ st of
| SRV(c0, x0, dl, pl, ck) =>
  SRV
  ( (if (strn_length(chk) > 0) then chk else c0): string
  , (if (strn_length(xh) > 0) then xh else x0): string
  , dl, pl, ck)
end//endof[h_initialize]
//
fun
h_didopen
(jv0: jval, st: srvst): srvst =
let
val td =
jobj_get(jobj_get(jv0, "params"), "textDocument")
val uri = jget_str(jobj_get(td, "uri"), "")
val ver = jget_int(jobj_get(td, "version"), 0 - 1)
val txt = jget_str(jobj_get(td, "text"), "")
in
if (strn_length(uri) <= 0) then st else
case+ st of
| SRV(c0, x0, dl, pl, ck) =>
  SRV
  ( c0, x0
  , docs_put(dl, uri, ver, txt)
  , pend_put(pl, uri, lsp_now_ms())
  , ck)
end//endof[h_didopen]
//
fun
h_didchange
(jv0: jval, st: srvst): srvst =
let
val prms = jobj_get(jv0, "params")
val td = jobj_get(prms, "textDocument")
val uri = jget_str(jobj_get(td, "uri"), "")
val ver = jget_int(jobj_get(td, "version"), 0 - 1)
val ccs = jobj_get(prms, "contentChanges")
(* full sync: the last change's text is the new content *)
fun
lastxt(xs: jvlst, cur: jval): jval =
case+ xs of
| JVLnil() => cur
| JVLcons(x0, r0) => lastxt(r0, jobj_get(x0, "text"))
val tjv =
(
case+ ccs of
| JVarr(xs) => lastxt(xs, JVerr()) | _(*else*) => JVerr()): jval
in
if (strn_length(uri) <= 0) then st else
case+ st of
| SRV(c0, x0, dl, pl, ck) =>
  let
  val txt =
  (
  if jis_err(tjv)
  then docs_text(dl, uri) else jget_str(tjv, "")): string
  in
  SRV(c0, x0, docs_put(dl, uri, ver, txt), pl, ck)
  end
end//endof[h_didchange]
//
fun
h_didsave
(jv0: jval, st: srvst): srvst =
let
val td =
jobj_get(jobj_get(jv0, "params"), "textDocument")
val uri = jget_str(jobj_get(td, "uri"), "")
in
if (strn_length(uri) <= 0) then st else
case+ st of
| SRV(c0, x0, dl, pl, ck) =>
  SRV(c0, x0, dl, pend_put(pl, uri, lsp_now_ms()), ck)
end//endof[h_didsave]
//
fun
h_didclose
(jv0: jval, st: srvst): srvst =
let
val td =
jobj_get(jobj_get(jv0, "params"), "textDocument")
val uri = jget_str(jobj_get(td, "uri"), "")
val () =
if (strn_length(uri) > 0)
then publish(uri, 0 - 1, JVarr(JVLnil()))
in
if (strn_length(uri) <= 0) then st else
case+ st of
| SRV(c0, x0, dl, pl, ck) =>
  SRV(c0, x0, docs_del(dl, uri), pend_del(pl, uri), ck)
end//endof[h_didclose]
//
(* ****** ****** *)
//
(* handle one message body: @(new state, 0 = continue | 1 = exit) *)
fun
on_msg
(body: string, st: srvst): @(srvst, sint) =
let
val jv0 = json_parse(body)
in
if jis_err(jv0)
then (respond_err(JVnull(), 0 - 32700, "parse error"); @(st, 0))
else
let
val mth = jget_str(jobj_get(jv0, "method"), "")
val idv = jobj_get(jv0, "id")
in
if streq(mth, "initialize")
then @(h_initialize(jv0, idv, st), 0) else
if streq(mth, "initialized") then @(st, 0) else
if streq(mth, "textDocument/didOpen")
then @(h_didopen(jv0, st), 0) else
if streq(mth, "textDocument/didChange")
then @(h_didchange(jv0, st), 0) else
if streq(mth, "textDocument/didSave")
then @(h_didsave(jv0, st), 0) else
if streq(mth, "textDocument/didClose")
then @(h_didclose(jv0, st), 0) else
if streq(mth, "shutdown")
then (respond(idv, JVnull()); @(st, 0)) else
if streq(mth, "exit") then @(st, 1) else
if jis_err(idv) then @(st, 0) (* unknown notification: ignore *)
else
(
respond_err
(idv, 0 - 32601, strn_append("method not found: ", mth)); @(st, 0))
end
end//endof[on_msg]
//
(* ****** ****** *)
(* the check pump *)
(* ****** ****** *)
//
(* reap a finished check and publish its diagnostics *)
fun
chk_step(st: srvst): srvst =
case+ st of
| SRV(c0, x0, dl, pl, ck) =>
  (
  case+ ck of
  | CKnone() => st
  | CKrun(id, uri, ver) =>
    (
    if (lsp_check_done(id) = 1)
    then
    let
    val rep = lsp_check_output(id)
    val () = lsp_check_drop(id)
    val path = uri_to_path(uri)
    val () = publish(uri, ver, diag_array(path, rep))
    in
    SRV(c0, x0, dl, pl, CKnone())
    end
    else st))
//
(* start the next due check when idle *)
fun
pend_step(st: srvst): srvst =
case+ st of
| SRV(c0, x0, dl, pl, ck) =>
  (
  case+ ck of
  | CKrun(_, _, _) => st
  | CKnone() =>
    let
    val r0 = pend_take_due(pl, lsp_now_ms())
    val uri = r0.0
    in
    if (strn_length(uri) <= 0) then st else
    if (strn_length(c0) <= 0)
    then
    (
    lsp_write_log("ats3-lsp: no checker configured; skipping check\n");
    SRV(c0, x0, dl, r0.1, CKnone()))
    else
    let
    val path = uri_to_path(uri)
    in
    if (strn_length(path) <= 0)
    then SRV(c0, x0, dl, r0.1, CKnone())
    else
    let
    val id = lsp_spawn_check(c0, path, x0)
    in
    if (id < 0)
    then
    (
    lsp_write_log("ats3-lsp: checker spawn failed\n");
    SRV(c0, x0, dl, r0.1, CKnone()))
    else SRV(c0, x0, dl, r0.1, CKrun(id, uri, docs_version(dl, uri)))
    end
    end
    end)
//
(* how long the poll may block: -1 = forever (nothing in flight) *)
fun
wait_ms(st: srvst): sint =
case+ st of
| SRV(_, _, _, pl, ck) =>
  (
  case+ ck of
  | CKrun(_, _, _) => 25
  | CKnone() => (if pend_emptyq(pl) then (0 - 1) else 25))
//
(* ****** ****** *)
//
fun
serve(buf: string, st: srvst): void =
case+ frame_next(buf) of
| FRmsg(body, rest) =>
  let
  val r0 = on_msg(body, st)
  in
  if (r0.1 = 0)
  then serve(rest, r0.0)
  else lsp_write_log("ats3-lsp: exit\n")
  end
| FRnone() =>
  let
  val st1 = pend_step(chk_step(st))
  val ev = lsp_poll_stdin(wait_ms(st1))
  in
  if (ev = 1)
  then serve(strn_append(buf, lsp_read_chunk()), st1) else
  if (ev = 0)
  then serve(buf, st1)
  else lsp_write_log("ats3-lsp: stdin closed\n")
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
serve("", SRV("", "", DOCnil(), PNDnil(), CKnone()))
end//endof[server_main]
//
(* ****** ****** *)
val ((*the_entry_point*)) = server_main((*void*))
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_main.dats] *)
(***********************************************************************)
