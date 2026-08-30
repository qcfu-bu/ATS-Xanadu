(***********************************************************************)
(*                                                                     *)
(*                         Applied Type System                         *)
(*                                                                     *)
(***********************************************************************)

(*
** ATS/Xanadu - Unleashing the Potential of Types!
** Copyright (C) 2026 Hongwei Xi, ATS Trustful Software, Inc.
** All rights reserved
*)

(* ****** ****** *)
(* ****** ****** *)
//
(*
xats2go_tchecklib — the CALLABLE check core (see the .sats header).
CLAUDE-2026-08-29 (M6): extracted VERBATIM from xats2go_tcheck01 (the
helpers, the --stdin lexbuf path, the dependency reporters, and the
mymain_work pipeline), parameterized by (text, errout, idxout), plus
the per-check EVICTION walk that makes in-process re-checks equivalent
to process-per-check.  The CLI driver and the resident server both
staload this; the CLI's stderr/stdout stay byte-identical to pre-M6.
*)
//
(* ****** ****** *)
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../..\
/HATS/xatsopt_dpre.hats"
(* ****** ****** *)
(* ****** ****** *)
#include
"./../HATS/libxatsopt.hats"
(* ****** ****** *)
#include
"./../HATS/mytmplib00.hats"
(* ****** ****** *)
(* ****** ****** *)
//
(*
[pread00]/[lexbuf0]/[filpath]/[f2perr0] are not in libxatsopt.hats —
library-local staloads (only this module's stamps move; see the same
note in xats2go_tcheck01).
*)
#staload "./../../../SATS/pread00.sats"
#staload "./../../../SATS/lexbuf0.sats"
#staload "./../../../SATS/filpath.sats"
#staload "./../../../SATS/f2perr0.sats"
//
#staload "./xats2go_lspidx.sats"
#staload "./xats2go_tchecklib.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
the diagnostics window must bracket BOTH the parse phase and the
f3perr0 report (see xats2go_goemit01): the srcgen2 resolver does not
apply the reporters' local `g_print$out<>() = out` hooks, so the
runtime default channel is flipped to stderr for the duration.  Under
the resident server's capture window these same brackets route the
text into the captured string instead.
*)
#extern
fun
XATS2GO_report_begin((*void*)): void = $extnam()
#extern
fun
XATS2GO_report_end((*void*)): void = $extnam()
//
(*
M7.2 warm-dep leaves (runtime/xatsgo/xatsgo.go): capture-slice marks
(a dep's report bytes = the capture buffer between two marks — FILR
writes AND report-window prints, in order) and the dep registry
(visited/cached/replay/note/edge/stale).
*)
#extern
fun
XATS2GO_capture_mark((*void*)): sint = $extnam()
#extern
fun
XATS2GO_capture_since(mk: sint): strn = $extnam()
#extern
fun
XATS2GO_lsp_depvisitq(key: sint): sint = $extnam()
#extern
fun
XATS2GO_lsp_depcachedq(key: sint): sint = $extnam()
#extern
fun
XATS2GO_lsp_depreplay(key: sint): strn = $extnam()
#extern
fun
XATS2GO_lsp_depnote
(key: sint, path: strn, rpt: strn): void = $extnam()
#extern
fun
XATS2GO_lsp_depedge(par: sint, chd: sint): void = $extnam()
#extern
fun
XATS2GO_lsp_depstale
( m1: topmap(d1parsed), m2: topmap(d2parsed)
, m3: topmap(d3parsed), m4: topmap(d3parsed)): void = $extnam()
#extern
fun
XATS2GO_strn_fprint:
(strn, FILR) -> void = $extnam()
//
fun
dw_pr(out: FILR, s0: strn): void = XATS2GO_strn_fprint(s0, out)
//
(* ****** ****** *)
//
(* ASCII string helpers (extensions/prefixes; the library's own) *)
fun
my_endswith
(s0: strn, sfx: strn): bool =
let
val n0 = strn_length(s0)
val n1 = strn_length(sfx)
fun
loop(i0: sint): bool =
if i0 >= n1 then true else
if strn_get$at(s0, n0-n1+i0) = strn_get$at(sfx, i0)
then loop(i0+1) else false
in//let
if n1 <= n0 then loop(0) else false
end//endof[my_endswith]
//
fun
my_startsw
(s0: strn, off: sint, part: strn): bool =
let
val n0 = strn_length(s0)
val n1 = strn_length(part)
fun
loop(i0: sint): bool =
if i0 >= n1 then true else
if strn_get$at(s0, off+i0) = strn_get$at(part, i0)
then loop(i0+1) else false
in//let
if off < 0 then false else
if off + n1 > n0 then false else loop(0)
end//endof[my_startsw]
//
(* ****** ****** *)
//
(*
[--stdin]: parse TEXT (the editor's unsaved buffer) ATTRIBUTED to the
real path — replicates [trans00_from_fpath] (DATS/parsing.dats) except
the lexbuf comes from the text: token locations AND the d0parsed
source carry LCSRCsome1(fpth), so diagnostics name the file and
relative staloads resolve exactly as in the on-disk mode.
*)
fun
my_d0parsed_from_text
(stadyn: sint, txt: strn, fpth: strn): d0parsed =
let
//
val tks =
lexing_preping_all
(
lexing_lctnize_all
( LCSRCsome1(fpth)
, lxbf1_lexing_tnodelst(lxbf1_make_strn(txt))))
//
val buf =
tokbuf_make_llist(tks)
//
var err: sint = 0(*init*)
//
val res =
optn_cons
(fp_d0eclsq1(stadyn,buf,err))
//
val ( ) = tokbuf_free(buf)
//
in//let
//HX: nerror=-1: unknown of errors
d0parsed(stadyn,(-1),LCSRCsome1(fpth),res)
end//endof[my_d0parsed_from_text]
//
(* ****** ****** *)
//
(*
dependency reporting: see the long note in xats2go_tcheck01 (kept
there for history).  Summary: a freshly-checked (shr = 0) staload
dependency's errors are reported here because the target's f3perr0
does not descend into staloads; the dependency pipeline SKIPS the
tread12 proofread, so run tread12 on the dep's cached d2parsed and
report with f2perr0 first, then f3perr0 on its d3parsed; recurse for
transitive deps.  STDLIB deps ($XATSHOME/prelude/ + /xatslib/) are
excluded — reporting over the prelude's own DATS floods thousands of
recoverable template reports.
*)
fun
dep_skipq(fpx: fpath): bool =
let
val path = fpath_get_fnm1(fpx)
val xhome = the_XATSHOME()
val nx = strn_length(xhome)
in//let
if my_startsw(path, 0, xhome)
then
(
if my_startsw(path, nx, "/prelude/") then true else
my_startsw(path, nx, "/xatslib/"))
else false
end//endof[dep_skipq]
//
fun
dep_wantq(fopt: fpathopt): bool =
case+ fopt of
| optn_nil() => true
| optn_cons(fpx) => (if dep_skipq(fpx) then false else true)
//
fun
report_dep_l2
(out0: FILR, fopt: fpathopt): void =
case+ fopt of
| optn_nil() => ()
| optn_cons(fpx) =>
  (
  case+ the_d2parenv_pvsfind(fpath_get_fnm2(fpx)) of
  | ~
  optn_vt_nil() => ()
  | ~
  optn_vt_cons(d2p) =>
    f2perr0_d2parsed(out0, d2parsed_of_tread12(d2p)))
//
(*
the WARM-DEP report walk (M7.2): visit-once per check via the runtime
visited set — the shr flags inside CACHED ASTs are frozen from their
own elaboration time, so they cannot gate re-visits.  A dep already
in the registry REPLAYS its recorded report bytes (cross-file
diagnostics stay byte-identical across warm checks); a fresh dep
reports (the tread12 mutation happens exactly once, while fresh),
its bytes are sliced from the capture buffer and recorded together
with its staload edges.  Both arms recurse for transitive deps;
edges from a parent dep to its children feed depstale's reverse
closure.  parent < 0 = the target file (no edge).
*)
fun
dep_key(fpx: fpath): sint =
g0u2s(uint(fpath_get_fnm2(fpx).stmp()))
//
fun
dw_dep2
(out0: FILR, parent: sint, fopt: fpathopt, depd2p: d2parsed): void =
case+ fopt of
| optn_nil() => ()
| optn_cons(fpx) =>
  (
  if dep_wantq(fopt)
  then
  let
  val key = dep_key(fpx)
  val () =
  (if (parent >= 0) then XATS2GO_lsp_depedge(parent, key) else ())
  in
  if (XATS2GO_lsp_depvisitq(key) = 0) then () else
  if (XATS2GO_lsp_depcachedq(key) > 0)
  then
  (
  dw_pr(out0, XATS2GO_lsp_depreplay(key));
  dw_decl2_opt(out0, key, d2parsed_get_parsed(depd2p)))
  else
  let
  val mk = XATS2GO_capture_mark()
  val () =
  f2perr0_d2parsed(out0, d2parsed_of_tread12(depd2p))
  val () =
  XATS2GO_lsp_depnote
  (key, fpath_get_fnm1(fpx), XATS2GO_capture_since(mk))
  in
  dw_decl2_opt(out0, key, d2parsed_get_parsed(depd2p))
  end
  end
  else ())
//
and
dw_sopt2
(out0: FILR, parent: sint, fopt2: fpathopt, sopt2: s2taloadopt): void =
case+ sopt2 of
| S2TALOADdpar(_(*shr: frozen*), depd2p) =>
  dw_dep2(out0, parent, fopt2, depd2p)
| _(*none/fenv*) => ()
//
and
dw_decl2
(out0: FILR, parent: sint, dpcl2: d2ecl): void =
case+ d2ecl_get_node(dpcl2) of
| D2Cstaload
  (_(*knd*), _(*tknd*), _(*gsrc*), fopt2, sopt2) =>
  dw_sopt2(out0, parent, fopt2, sopt2)
| D2Cinclude
  (_(*knd*), _(*tknd*), _(*gsrc*), _(*fopt*), dopt2) =>
  dw_decl2_opt(out0, parent, dopt2)
| _(*else*) => ()
//
and
dw_decl2_lst
(out0: FILR, parent: sint, dcls: d2eclist): void =
case+ dcls of
| list_nil() => ()
| list_cons(d1, ds1) =>
  (dw_decl2(out0, parent, d1); dw_decl2_lst(out0, parent, ds1))
//
and
dw_decl2_opt
(out0: FILR, parent: sint, dopt: d2eclistopt): void =
case+ dopt of
| optn_nil() => ()
| optn_cons(dcls) => dw_decl2_lst(out0, parent, dcls)
//
fun
dw_dep3
(out0: FILR, parent: sint, fopt: fpathopt, depdpar: d3parsed): void =
case+ fopt of
| optn_nil() => ()
| optn_cons(fpx) =>
  (
  if dep_wantq(fopt)
  then
  let
  val key = dep_key(fpx)
  val () =
  (if (parent >= 0) then XATS2GO_lsp_depedge(parent, key) else ())
  in
  if (XATS2GO_lsp_depvisitq(key) = 0) then () else
  if (XATS2GO_lsp_depcachedq(key) > 0)
  then
  (
  dw_pr(out0, XATS2GO_lsp_depreplay(key));
  dw_decl3_opt(out0, key, d3parsed_get_parsed(depdpar)))
  else
  let
  val mk = XATS2GO_capture_mark()
  val () = report_dep_l2(out0, fopt)
  val () = f3perr0_d3parsed(out0, depdpar)
  val () =
  XATS2GO_lsp_depnote
  (key, fpath_get_fnm1(fpx), XATS2GO_capture_since(mk))
  in
  dw_decl3_opt(out0, key, d3parsed_get_parsed(depdpar))
  end
  end
  else ())
//
and
dw_decl3
(out0: FILR, parent: sint, dpcl: d3ecl): void =
case+ d3ecl_get_node(dpcl) of
| D3Cstaload
  (_(*knd*), _(*tknd*), _(*gsrc*), fopt, sopt) =>
  (
  case+ sopt of
  | S3TALOADdpar(_(*shr: frozen*), depdpar) =>
    dw_dep3(out0, parent, fopt, depdpar)
  | S3TALOADnone(sopt2) => dw_sopt2(out0, parent, fopt, sopt2))
| D3Cinclude
  (_(*knd*), _(*tknd*), _(*gsrc*), _(*fopt*), dopt) =>
  dw_decl3_opt(out0, parent, dopt)
| _(*else*) => ()
//
and
dw_decl3_lst
(out0: FILR, parent: sint, dcls: d3eclist): void =
case+ dcls of
| list_nil() => ()
| list_cons(d1, ds1) =>
  (dw_decl3(out0, parent, d1); dw_decl3_lst(out0, parent, ds1))
//
and
dw_decl3_opt
(out0: FILR, parent: sint, dopt: d3eclistopt): void =
case+ dopt of
| optn_nil() => ()
| optn_cons(dcls) => dw_decl3_lst(out0, parent, dcls)
//
fun
report_deps
(out0: FILR, dpar: d3parsed): void =
dw_decl3_opt(out0, 0 - 1, d3parsed_get_parsed(dpar))
//

(* ****** ****** *)
//
(*
EVICTION (M7.2, warm deps): workspace deps now STAY CACHED across
checks; freshness is depstale's job at every check start (mtime +
reverse-closure over the recorded staload edges).  Only the TARGET
file is evicted unconditionally (its text arrives live).  Keys are
the fnm2 stamps, exactly as xsymmap_topmap keys its mydict; the
delete leaf treats the topmap by its runtime rep (jshmap); an absent
key is a no-op.  The tread12 mutation of a cached dep d2parsed
happens exactly once, while the dep is FRESH — warm checks replay its
recorded report instead of re-running the reporters.
*)
fun
evict_d1(key: sint): void =
let
#extern
fun
XATS2GO_lsp_evict
(map: topmap(d1parsed), key: sint): void = $extnam()
in
XATS2GO_lsp_evict(the_d1parenv_pvstmap(), key)
end
//
fun
evict_d2(key: sint): void =
let
#extern
fun
XATS2GO_lsp_evict
(map: topmap(d2parsed), key: sint): void = $extnam()
in
XATS2GO_lsp_evict(the_d2parenv_pvstmap(), key)
end
//
fun
evict_d3(key: sint): void =
let
#extern
fun
XATS2GO_lsp_evict
(map: topmap(d3parsed), key: sint): void = $extnam()
in
XATS2GO_lsp_evict(the_d3parenv_pvstmap(), key)
end
//
fun
evict_d3t(key: sint): void =
let
#extern
fun
XATS2GO_lsp_evict
(map: topmap(d3parsed), key: sint): void = $extnam()
in
XATS2GO_lsp_evict(the_d3tmpenv_pvstmap(), key)
end
//
fun
evict_fnm2(fnm2: sym_t): void =
let
val key = g0u2s(uint(fnm2.stmp()))
in
(evict_d1(key); evict_d2(key); evict_d3(key); evict_d3t(key))
end
//

(* ****** ****** *)
(* ****** ****** *)
//
#implfun
tchk_prelude_load
  ((*void*)) =
let
//
val ret1 =
the_fxtyenv_pvsl00d((*0*))
val (  ) =
if // if
(ret1 > 0)
then
prerrsln("\
// The fixity-defs loaded!")
val ret2 =
the_tr12env_pvsl01d((*nil*))
val (  ) =
if // if
(ret2 > 0)
then prerrsln("\
// The trans12-defs loaded!")
//
(*
the SAME flag set as xats2go_goemit01: the flags select which CATS
files xatsopt_dpre includes, and the diagnostic surface must match
the CLI driver byte-for-byte on the same input.
*)
val (  ) =
xatsopt_flag$pvsadd0("--_XATS2JS_")
val (  ) =
xatsopt_flag$pvsadd0("--_SRCGEN2_XATS2JS_")
val (  ) =
xatsopt_flag$pvsadd0("--_XATS2GO_")
//
in//let
((*void*))
end//endof[tchk_prelude_load]
//
(* ****** ****** *)
//
#implfun
tchk_check
(fpth, txt, stdinq, idxq, errout, idxout) =
let
//
val dpar =
d3parsed_of_tread3a(dpar)
//
val dpar =
d3parsed_of_trtmp3b(dpar)
val dpar =
d3parsed_of_trtmp3c(dpar)
//
val dpar =
d3parsed_of_t3read0(dpar)
//
in//let
//
let
val
out0 = errout
in//let
prerrsln
("F3PERR0_D3PARSED:");
XATS2GO_report_begin();
f3perr0_d3parsed(out0,dpar);
report_deps(out0, dpar);
XATS2GO_report_end()
end//let
;
(*
the hover/def index (--index): machine records on the index channel
(stdout for the CLI; a buffer-FILR for the resident server).
*)
(if (idxq > 0)
then lspidx_emit(idxout, dpar) else ())
//
end where
{
//
(*
FIRST (M7.2): evict STALE warm deps (mtime + reverse closure) and the
target itself, before anything is parsed or elaborated.
*)
val ( ) =
XATS2GO_lsp_depstale
( the_d1parenv_pvstmap(), the_d2parenv_pvstmap()
, the_d3parenv_pvstmap(), the_d3tmpenv_pvstmap())
val ( ) =
evict_fnm2(fpath_get_fnm2(fpath_make_absolute(fpth)))
//
(*
the PARSE-level (PREAD00) report between the halves of
[d3parsed_of_fildats] — see the long note in xats2go_goemit01.dats.
stadyn follows the EXTENSION (.sats = 0, else 1); the text comes from
the file, or from the [txt] argument under [--stdin].
*)
val ( ) = XATS2GO_report_begin()
//
val stadyn =
(
if my_endswith(fpth, ".sats") then 0 else 1): sint
//
val d0par0 =
(
if (stdinq > 0)
then
my_d0parsed_from_text(stadyn, txt, fpth)
else d0parsed_from_fpath(stadyn, fpth)): d0parsed
//
val
d0par =
d0parsed_of_pread00(d0par0)
//
val ( ) =
d0parsed_fpemsg(errout, d0par)
//
val
dpar = d3parsed_of_trans03(d0par)
//
val ( ) = XATS2GO_report_end()
//
}(*where*)//end-of-[tchk_check(...)]
//
(* ****** ****** *)
(* ****** ****** *)

(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_UTIL_xats2go_tchecklib.dats] *)
(***********************************************************************)
