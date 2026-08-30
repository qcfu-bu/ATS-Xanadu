(* ****** ****** *)
(*
lsp_main.dats — the driver: a single-threaded, TAIL-RECURSIVE resident
event loop (the Go backend's TCO makes [serve] an O(1)-stack for-loop).

M6.1 surface: the M1 lifecycle + textDocument/didOpen|didChange|
didSave|didClose with publishDiagnostics via the IN-PROCESS compiler
(the architect's 2026-08-29 ruling): the frontend is LINKED into this
binary (wire-server.sh), the prelude loads ONCE at initialize, and
every check runs tchk_check (UTIL/xats2go_tchecklib) on the floor's
single-flight check GOROUTINE — the loop keeps answering requests
while a check runs; per-check EVICTION inside tchk_check reproduces
process-per-check semantics (the compiler is one-shot).  A check of a
stored document passes the CURRENT BUFFER TEXT (the --stdin path);
didChange re-checks after a 250 ms debounce; a due check for a busy
loop stays queued and fires on reap (newest text wins — the queued
re-check reads the current buffer).  A didSave under $XATSHOME's
prelude trees drains the in-flight check, xglobal_reset()s + reloads
the prelude, and revalidates every open document.  All state is
loop-carried; there is no module-level mutable state.  Exit codes
follow LSP: 0 after shutdown, 1 without.

Configuration arrives in initialize.params.initializationOptions:
  { "xatshome": "<abs path to the ATS3 repo>" }
("checker" is accepted and ignored — pre-M6 clients still work.)
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
(*
the in-process check bridge (M6).  The compiler lives in a DIFFERENT
prelude world (srcgen1) than the server modules (repo-root GO prelude),
so the server cannot staload the compiler SATS — mixing the two
preludes detonates template resolution.  The bridge is at the GO
symbol level instead: UTIL/xats2go_lspglue (compiler world) exports
the check entry points as stamped Z_ functions; wire-server.sh
generates a shim forwarding these plain externs to them; the report
and index texts come back as strings via the runtime stash
(take_rep/take_idx, CATS/GO/lsp_floor.cats).
*)
#extern
fun
XATS2GO_LSP_tchk_prelude_load((*void*)): void = $extnam()
#extern
fun
XATS2GO_LSP_tchk_prelude_reload((*void*)): void = $extnam()
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
(* the per-uri hover/def/token/candidate index cache (latest wins) *)
datatype
idxlst =
| IXnil of ()
| IXcons of
  ( string(*uri*), sint(*version*)
  , hovlst, deflst, toklst, candlst, loclst, memlst, symlst, idxlst)
//
(* (checker path, xatshome, workspace root, docs, pending checks,
   in-flight check, shutdown-seen, index cache) *)
datatype
srvst =
| SRV of (string, string, string, doclst, pendlst, chkst, sint, idxlst)
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
fun
docs_has
(dl: doclst, uri: string): bool =
case+ dl of
| DOCnil() => false
| DOCcons(u0, _, _, r0) =>
  (if streq(u0, uri) then true else docs_has(r0, uri))
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
(* index-cache helpers *)
(* ****** ****** *)
//
fun
ix_put
( ix: idxlst, uri: string, ver: sint
, hl: hovlst, df: deflst, tk: toklst
, cd: candlst, lc: loclst, mm: memlst, sy: symlst): idxlst =
case+ ix of
| IXnil() => IXcons(uri, ver, hl, df, tk, cd, lc, mm, sy, IXnil())
| IXcons(u0, v0, h0, d0, t0, c0, l0, m0, s0, r0) =>
  (
  if streq(u0, uri)
  then IXcons(uri, ver, hl, df, tk, cd, lc, mm, sy, r0)
  else
  IXcons
  ( u0, v0, h0, d0, t0, c0, l0, m0, s0
  , ix_put(r0, uri, ver, hl, df, tk, cd, lc, mm, sy)))
//
fun
ix_del
(ix: idxlst, uri: string): idxlst =
case+ ix of
| IXnil() => IXnil()
| IXcons(u0, v0, h0, d0, t0, c0, l0, m0, s0, r0) =>
  (
  if streq(u0, uri)
  then r0
  else IXcons(u0, v0, h0, d0, t0, c0, l0, m0, s0, ix_del(r0, uri)))
//
fun
ix_hov
(ix: idxlst, uri: string): hovlst =
case+ ix of
| IXnil() => HVnil()
| IXcons(u0, _, h0, _, _, _, _, _, _, r0) =>
  (if streq(u0, uri) then h0 else ix_hov(r0, uri))
//
fun
ix_dfs
(ix: idxlst, uri: string): deflst =
case+ ix of
| IXnil() => DFnil()
| IXcons(u0, _, _, d0, _, _, _, _, _, r0) =>
  (if streq(u0, uri) then d0 else ix_dfs(r0, uri))
//
fun
ix_tks
(ix: idxlst, uri: string): toklst =
case+ ix of
| IXnil() => TKnil()
| IXcons(u0, _, _, _, t0, _, _, _, _, r0) =>
  (if streq(u0, uri) then t0 else ix_tks(r0, uri))
//
fun
ix_cds
(ix: idxlst, uri: string): candlst =
case+ ix of
| IXnil() => CDnil()
| IXcons(u0, _, _, _, _, c0, _, _, _, r0) =>
  (if streq(u0, uri) then c0 else ix_cds(r0, uri))
//
fun
ix_lcs
(ix: idxlst, uri: string): loclst =
case+ ix of
| IXnil() => LCnil()
| IXcons(u0, _, _, _, _, _, l0, _, _, r0) =>
  (if streq(u0, uri) then l0 else ix_lcs(r0, uri))
//
fun
ix_mms
(ix: idxlst, uri: string): memlst =
case+ ix of
| IXnil() => MMnil()
| IXcons(u0, _, _, _, _, _, _, m0, _, r0) =>
  (if streq(u0, uri) then m0 else ix_mms(r0, uri))
//
fun
ix_sys
(ix: idxlst, uri: string): symlst =
case+ ix of
| IXnil() => SYnil()
| IXcons(u0, _, _, _, _, _, _, _, s0, r0) =>
  (if streq(u0, uri) then s0 else ix_sys(r0, uri))
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
(*
workspace/semanticTokens/refresh: tell the client to re-pull tokens
now that a fresh index landed (without it, VSCode's post-edit pull
races the check, keeps the stale pre-edit tokens forever, and the
highlighting appears disabled).  A server->client REQUEST: the id is
derived from the (monotonic) check id so it is unique; the client's
response is ignored by on_msg.
*)
fun
send_tokrefresh(chkid: sint): void =
send_msg
(JVobj
( JKVcons("jsonrpc", JVstr("2.0")
, JKVcons("id", JVint(1000000 + chkid)
, JKVcons("method"
  , JVstr("workspace/semanticTokens/refresh"), JKVnil())))))
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
(* the semantic-token legend: kinds indexed by the driver's T records *)
val legend =
JVobj
( JKVcons("tokenTypes"
, JVarr
  ( JVLcons(JVstr("variable")
  , JVLcons(JVstr("function")
  , JVLcons(JVstr("enumMember"), JVLnil()))))
, JKVcons("tokenModifiers", JVarr(JVLnil()), JKVnil())))
val semtok =
JVobj
( JKVcons("legend", legend
, JKVcons("full", JVtrue(), JKVnil())))
val caps =
JVobj
( JKVcons("textDocumentSync", sync
, JKVcons("hoverProvider", JVtrue()
, JKVcons("definitionProvider", JVtrue()
, JKVcons("referencesProvider", JVtrue()
, JKVcons("documentHighlightProvider", JVtrue()
, JKVcons("documentSymbolProvider", JVtrue()
, JKVcons("semanticTokensProvider", semtok
, JKVcons("completionProvider"
  , JVobj
    ( JKVcons("triggerCharacters"
    , JVarr(JVLcons(JVstr("."), JVLnil())), JKVnil()))
  , JKVnil())))))))))
val info =
JVobj
( JKVcons("name", JVstr("ats3-lsp")
, JKVcons("version", JVstr("0.6.0"), JKVnil())))
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
val prms = jobj_get(jv0, "params")
val opts = jobj_get(prms, "initializationOptions")
val chk = jget_str(jobj_get(opts, "checker"), "")
val xh = jget_str(jobj_get(opts, "xatshome"), "")
(* the workspace root gates cross-file diagnostic summaries:
   rootUri, else workspaceFolders[0].uri *)
val wsr0 = uri_to_path(jget_str(jobj_get(prms, "rootUri"), ""))
val wsr =
(
if (strn_length(wsr0) > 0) then wsr0 else
case+ jobj_get(prms, "workspaceFolders") of
| JVarr(JVLcons(f0, _)) =>
  uri_to_path(jget_str(jobj_get(f0, "uri"), ""))
| _(*else*) => ""): string
val () = respond(idv, init_result())
(*
M6: the in-process prelude load, ONCE (the pvsl gates make a repeat
call a no-op).  XATSHOME must be in the environment BEFORE the load —
the compiler reads it via its getenv leaf.  ~290 ms, after the
initialize response so the client is never kept waiting on it.
*)
val () =
(
if (strn_length(xh) > 0)
then lsp_setenv("XATSHOME", xh) else ())
val ldok =
lsp_guard(lam(_) => XATS2GO_LSP_tchk_prelude_load())
val () =
(
if (ldok = 0)
then lsp_write_log("ats3-lsp: prelude load FAILED\n") else ())
in
case+ st of
| SRV(c0, x0, ws, dl, pl, ck, sd, ix) =>
  SRV
  ( (if (strn_length(chk) > 0) then chk else c0): string
  , (if (strn_length(xh) > 0) then xh else x0): string
  , (if (strn_length(wsr) > 0) then wsr else ws): string
  , dl, pl, ck, sd, ix)
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
| SRV(c0, x0, ws, dl, pl, ck, sd, ix) =>
  SRV
  ( c0, x0, ws
  , docs_put(dl, uri, ver, txt)
  , pend_put(pl, uri, lsp_now_ms())
  , ck, sd, ix)
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
| SRV(c0, x0, ws, dl, pl, ck, sd, ix) =>
  let
  val txt =
  (
  if jis_err(tjv)
  then docs_text(dl, uri) else jget_str(tjv, "")): string
  in
  SRV
  ( c0, x0, ws
  , docs_put(dl, uri, ver, txt)
  (* live checking: re-check the buffer after a quiet 250 ms *)
  , pend_put(pl, uri, lsp_now_ms() + 250)
  , ck, sd, ix)
  end
end//endof[h_didchange]
//
(* does s0 start with pfx0? (byte-wise) *)
fun
str_prefixq
(s0: string, pfx0: string): bool =
let
val n0 = strn_length(s0)
val n1 = strn_length(pfx0)
fun
loop(i0: sint): bool =
if i0 >= n1 then true else
if strn_get$at(s0, i0) = strn_get$at(pfx0, i0)
then loop(i0+1) else false
in//let
if n1 <= n0 then loop(0) else false
end//endof[str_prefixq]
//
(*
is path a PRELUDE file under xhome?  (The trees the in-process
compiler's pvsloaded prelude comes from; a save there invalidates the
warm prelude.)
*)
fun
prelude_pathq
(path: string, xhome: string): bool =
if (strn_length(xhome) <= 0) then false else
if str_prefixq(path, strn_append(xhome, "/prelude/")) then true else
if str_prefixq(path, strn_append(xhome, "/srcgen1/prelude/")) then true else
str_prefixq(path, strn_append(xhome, "/srcgen2/prelude/"))
//
(* queue a re-check of every OPEN document (post-reload revalidation) *)
fun
pend_all_docs
(dl: doclst, pl: pendlst, now: sint): pendlst =
case+ dl of
| DOCnil() => pl
| DOCcons(u0, _, _, r0) =>
  pend_all_docs(r0, pend_put(pl, u0, now), now)
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
| SRV(c0, x0, ws, dl, pl, ck, sd, ix) =>
  (
  if prelude_pathq(uri_to_path(uri), x0)
  then
  (*
  M6.1 PRELUDE RELOAD: drain any in-flight check (lsp_check_drop
  BLOCKS until its goroutine finishes; the results are stale under
  the new prelude and discarded), reset + reload the compiler under
  the guard, then queue a re-check of every open document.
  *)
  let
  val () =
  (
  case+ ck of
  | CKnone() => ()
  | CKrun(id, _, _) => lsp_check_drop(id))
  val () =
  lsp_write_log("ats3-lsp: prelude file saved; reloading prelude\n")
  val rok =
  lsp_guard(lam(_) => XATS2GO_LSP_tchk_prelude_reload())
  val () =
  (
  if (rok = 0)
  then lsp_write_log("ats3-lsp: prelude reload FAILED (state may be stale; restart recommended)\n")
  else lsp_write_log("ats3-lsp: prelude reloaded\n"))
  in
  SRV(c0, x0, ws, dl, pend_all_docs(dl, pl, lsp_now_ms()), CKnone(), sd, ix)
  end
  else SRV(c0, x0, ws, dl, pend_put(pl, uri, lsp_now_ms()), ck, sd, ix))
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
| SRV(c0, x0, ws, dl, pl, ck, sd, ix) =>
  SRV(c0, x0, ws, docs_del(dl, uri), pend_del(pl, uri), ck, sd, ix_del(ix, uri))
end//endof[h_didclose]
//
(* the (uri, line, character) of a positional request *)
fun
req_pos(jv0: jval): @(string, sint, sint) =
let
val prms = jobj_get(jv0, "params")
val uri =
jget_str(jobj_get(jobj_get(prms, "textDocument"), "uri"), "")
val pos = jobj_get(prms, "position")
in
@( uri
 , jget_int(jobj_get(pos, "line"), 0 - 1)
 , jget_int(jobj_get(pos, "character"), 0 - 1))
end//endof[req_pos]
//
fun
h_hover
(jv0: jval, idv: jval, st: srvst): void =
let
val rp = req_pos(jv0)
in
case+ st of
| SRV(_, _, _, _, _, _, _, ix) =>
  let
  val res = idx_hover(ix_hov(ix, rp.0), rp.1, rp.2)
  in
  if jis_err(res)
  then respond(idv, JVnull()) else respond(idv, res)
  end
end//endof[h_hover]
//
fun
h_definition
(jv0: jval, idv: jval, st: srvst): void =
let
val rp = req_pos(jv0)
in
case+ st of
| SRV(_, _, _, _, _, _, _, ix) =>
  let
  val res = idx_def(ix_dfs(ix, rp.0), rp.1, rp.2)
  in
  if (strn_length(res.0) <= 0)
  then respond(idv, JVnull())
  else
  respond
  ( idv
  , JVobj
    ( JKVcons("uri", JVstr(path_to_uri(res.0))
    , JKVcons("range", res.1, JKVnil()))))
  end
end//endof[h_definition]
//
fun
h_completion
(jv0: jval, idv: jval, st: srvst): void =
let
val rp = req_pos(jv0)
in
case+ st of
| SRV(_, _, _, dl, _, _, _, ix) =>
  respond
  ( idv
  , idx_complete
    ( ix_cds(ix, rp.0), ix_lcs(ix, rp.0), ix_mms(ix, rp.0)
    , docs_text(dl, rp.0), rp.1, rp.2))
end//endof[h_completion]
//
fun
h_semtoks
(jv0: jval, idv: jval, st: srvst): void =
let
val uri =
jget_str
( jobj_get
  (jobj_get(jobj_get(jv0, "params"), "textDocument"), "uri"), "")
in
case+ st of
| SRV(_, _, _, _, _, _, _, ix) =>
  respond
  ( idv
  , JVobj
    (JKVcons("data", idx_toks_data(ix_tks(ix, uri)), JKVnil())))
end//endof[h_semtoks]
//
(*
M7: references.  Resolve the target definition at the position (from
THIS uri's index), then collect matching use-sites across EVERY cached
uri; includeDeclaration appends the definition site itself.
*)
fun
refs_all
( ix: idxlst
, dpath: string, d0: sint, d1: sint, d2: sint, d3: sint
, acc: jvlst): jvlst =
case+ ix of
| IXnil() => acc
| IXcons(u0, _, _, df0, _, _, _, _, _, r0) =>
  refs_all
  ( r0, dpath, d0, d1, d2, d3
  , idx_ref_locs(df0, u0, dpath, d0, d1, d2, d3, acc))
//
fun
h_references
(jv0: jval, idv: jval, st: srvst): void =
let
val rp = req_pos(jv0)
val incl =
(
case+
jobj_get
(jobj_get(jobj_get(jv0, "params"), "context"), "includeDeclaration")
of JVtrue() => 1 | _(*else*) => 0): sint
in
case+ st of
| SRV(_, _, _, _, _, _, _, ix) =>
  let
  val tg =
  idx_ref_target(ix_dfs(ix, rp.0), uri_to_path(rp.0), rp.1, rp.2)
  in
  if (tg.0 = 0)
  then respond(idv, JVarr(JVLnil()))
  else
  let
  val locs =
  refs_all(ix, tg.1, tg.2, tg.3, tg.4, tg.5, JVLnil())
  val locs =
  (
  if (incl > 0)
  then
  JVLcons
  ( JVobj
    ( JKVcons("uri", JVstr(path_to_uri(tg.1))
    , JKVcons
      ("range", idx_range_jv(tg.2, tg.3, tg.4, tg.5), JKVnil())))
  , locs)
  else locs): jvlst
  in
  respond(idv, JVarr(locs))
  end
  end
end//endof[h_references]
//
fun
h_dochl
(jv0: jval, idv: jval, st: srvst): void =
let
val rp = req_pos(jv0)
in
case+ st of
| SRV(_, _, _, _, _, _, _, ix) =>
  let
  val path = uri_to_path(rp.0)
  val tg = idx_ref_target(ix_dfs(ix, rp.0), path, rp.1, rp.2)
  in
  if (tg.0 = 0)
  then respond(idv, JVarr(JVLnil()))
  else
  let
  val hls =
  idx_ref_hls(ix_dfs(ix, rp.0), tg.1, tg.2, tg.3, tg.4, tg.5)
  in
  (*
  when the definition lives in THIS file, highlight it too (the
  editor convention: def + uses light up together)
  *)
  case+ hls of
  | JVarr(xs) =>
    (
    if streq(tg.1, path)
    then
    respond
    ( idv
    , JVarr
      ( JVLcons
        ( JVobj
          ( JKVcons("range", idx_range_jv(tg.2, tg.3, tg.4, tg.5)
          , JKVcons("kind", JVint(1), JKVnil())))
        , xs)))
    else respond(idv, hls))
  | _(*else*) => respond(idv, hls)
  end
  end
end//endof[h_dochl]
//
fun
h_docsym
(jv0: jval, idv: jval, st: srvst): void =
let
val uri =
jget_str
( jobj_get
  (jobj_get(jobj_get(jv0, "params"), "textDocument"), "uri"), "")
in
case+ st of
| SRV(_, _, _, _, _, _, _, ix) =>
  respond(idv, idx_symbols(ix_sys(ix, uri)))
end//endof[h_docsym]
//
fun
st_shutdown(st: srvst): srvst =
case+ st of
| SRV(c0, x0, ws, dl, pl, ck, _, ix) => SRV(c0, x0, ws, dl, pl, ck, 1, ix)
//
fun
exit_code(st: srvst): sint =
case+ st of
| SRV(_, _, _, _, _, _, sd, _) => (if (sd > 0) then 0 else 1)
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
if streq(mth, "textDocument/hover")
then (h_hover(jv0, idv, st); @(st, 0)) else
if streq(mth, "textDocument/definition")
then (h_definition(jv0, idv, st); @(st, 0)) else
if streq(mth, "textDocument/references")
then (h_references(jv0, idv, st); @(st, 0)) else
if streq(mth, "textDocument/documentHighlight")
then (h_dochl(jv0, idv, st); @(st, 0)) else
if streq(mth, "textDocument/documentSymbol")
then (h_docsym(jv0, idv, st); @(st, 0)) else
if streq(mth, "textDocument/semanticTokens/full")
then (h_semtoks(jv0, idv, st); @(st, 0)) else
if streq(mth, "textDocument/completion")
then (h_completion(jv0, idv, st); @(st, 0)) else
if streq(mth, "shutdown")
then (respond(idv, JVnull()); @(st_shutdown(st), 0)) else
if streq(mth, "exit") then @(st, 1) else
(* a message with no method = the client's RESPONSE to one of our
   requests (e.g. the token refresh): ignore *)
if streq(mth, "") then @(st, 0) else
if jis_err(idv) then @(st, 0) (* unknown notification: ignore *)
else
(
respond_err
(idv, 0 - 32601, strn_append("method not found: ", mth)); @(st, 0))
end
end//endof[on_msg]
//
(* ****** ****** *)
(* the check pump (M6.1: ASYNC in-process — one check goroutine) *)
(* ****** ****** *)
//
(*
reap a finished check and publish.  The check ran OFF the loop (the
floor's single-flight goroutine): the capture window collected the
report text (byte-identical to the old checker's stderr), a buffer
FILR collected the --index records, tchk_check evicted its workspace
closure, and the goroutine's recover turned a frontend abort into one
failed check.
*)
fun
chk_step(st: srvst): srvst =
case+ st of
| SRV(c0, x0, ws, dl, pl, ck, sd, ix) =>
  (
  case+ ck of
  | CKnone() => st
  | CKrun(id, uri, ver) =>
    (
    if (lsp_check_done(id) = 1)
    then
    let
    val rep = lsp_check_rep(id)
    val idxtxt = lsp_check_idx(id)
    val okg = lsp_check_ok(id)
    val () = lsp_check_drop(id)
    val path = uri_to_path(uri)
    val () =
    (
    if (okg = 0)
    then lsp_write_log("ats3-lsp: in-process check aborted\n") else ())
    val () =
    publish(uri, ver, diag_build(path, ws, docs_text(dl, uri), rep))
    val hvdf = idx_parse(idxtxt)
    val ix1 =
    ix_put
    ( ix, uri, ver
    , hvdf.0, hvdf.1, hvdf.2, hvdf.3, hvdf.4, hvdf.5, hvdf.6)
    val () = send_tokrefresh(ver)
    in
    SRV(c0, x0, ws, dl, pl, CKnone(), sd, ix1)
    end
    else st))
//
(* start the check goroutine for uri (the state's chk must be CKnone) *)
fun
start_check(st: srvst, uri: string): srvst =
case+ st of
| SRV(c0, x0, ws, dl, pl, _, sd, ix) =>
  let
  val path = uri_to_path(uri)
  in
  if (strn_length(path) <= 0)
  then SRV(c0, x0, ws, dl, pl, CKnone(), sd, ix)
  else
  let
  (* a stored document is checked LIVE (the --stdin path);
     every check also produces the hover/def index *)
  val hasdoc = docs_has(dl, uri)
  val txt = (if hasdoc then docs_text(dl, uri) else ""): string
  val stdinq = (if hasdoc then 1 else 0): sint
  val id = lsp_check_start(path, txt, stdinq)
  in
  if (id < 0)
  then
  (
  lsp_write_log("ats3-lsp: check already in flight; requeueing\n");
  SRV(c0, x0, ws, dl, pend_put(pl, uri, lsp_now_ms()), CKnone(), sd, ix))
  else SRV(c0, x0, ws, dl, pl, CKrun(id, uri, docs_version(dl, uri)), sd, ix)
  end
  end
//
(*
start the next due check.  While one is in flight, the due entry stays
queued (r0.1 is discarded, st keeps the original list) and fires as
soon as the running check is reaped — one check at a time, newest text
wins because the queued re-check reads the CURRENT buffer.
*)
fun
pend_step(st: srvst): srvst =
case+ st of
| SRV(c0, x0, ws, dl, pl, ck, sd, ix) =>
  let
  val r0 = pend_take_due(pl, lsp_now_ms())
  val uri = r0.0
  in
  if (strn_length(uri) <= 0) then st else
  case+ ck of
  | CKnone() =>
    start_check(SRV(c0, x0, ws, dl, r0.1, CKnone(), sd, ix), uri)
  | CKrun(_, _, _) => st (* busy: the due entry stays queued *)
  end//endof[pend_step]
//
(*
how long the poll may block: -1 = forever (nothing pending).  With a
check in flight the poll ALSO wakes on its done channel (ev = 3), so
the tick is only a fallback.
*)
fun
wait_ms(st: srvst): sint =
case+ st of
| SRV(_, _, _, _, pl, ck, _, _) =>
  (
  case+ ck of
  | CKrun(_, _, _) => 1000
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
  else
  let
  val () = lsp_write_log("ats3-lsp: exit\n")
  in
  lsp_exit(exit_code(r0.0))
  end
  end
| FRnone() =>
  let
  val st1 = pend_step(chk_step(st))
  val ev = lsp_poll_stdin(wait_ms(st1))
  in
  if (ev = 1)
  then serve(strn_append(buf, lsp_read_chunk()), st1) else
  if (ev = 0)
  then serve(buf, st1) else
  if (ev = 3) (* the in-flight check finished: loop to reap it now *)
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
serve("", SRV("", "", "", DOCnil(), PNDnil(), CKnone(), 0, IXnil()))
end//endof[server_main]
//
(* ****** ****** *)
val ((*the_entry_point*)) = server_main((*void*))
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_main.dats] *)
(***********************************************************************)
