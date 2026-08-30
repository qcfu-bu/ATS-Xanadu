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
fun
report_dep_s2
(out0: FILR, fopt: fpathopt, sopt2: s2taloadopt): void =
case+ sopt2 of
| S2TALOADdpar(shrq2, depd2p) =>
  (
  if (shrq2 = 0)
  then
  (
  if dep_wantq(fopt)
  then
  (
  f2perr0_d2parsed(out0, d2parsed_of_tread12(depd2p));
  report_dep2_opt(out0, d2parsed_get_parsed(depd2p)))
  else ())
  else ())
| _(*none/fenv*) => ()
//
and
report_dep2_1
(out0: FILR, dpcl2: d2ecl): void =
case+ d2ecl_get_node(dpcl2) of
| D2Cstaload
  (_(*knd*), _(*tknd*), _(*gsrc*), fopt2, sopt2) =>
  report_dep_s2(out0, fopt2, sopt2)
| D2Cinclude
  (_(*knd*), _(*tknd*), _(*gsrc*), _(*fopt*), dopt2) =>
  report_dep2_opt(out0, dopt2)
| _(*else*) => ()
//
and
report_dep2_lst
(out0: FILR, dcls: d2eclist): void =
case+ dcls of
| list_nil() => ()
| list_cons(d1, ds1) =>
  (report_dep2_1(out0, d1); report_dep2_lst(out0, ds1))
//
and
report_dep2_opt
(out0: FILR, dopt: d2eclistopt): void =
case+ dopt of
| optn_nil() => ()
| optn_cons(dcls) => report_dep2_lst(out0, dcls)
//
fun
report_dep1
(out0: FILR, dpcl: d3ecl): void =
case+ d3ecl_get_node(dpcl) of
| D3Cstaload
  (_(*knd*), _(*tknd*), _(*gsrc*), fopt, sopt) =>
  (
  case+ sopt of
  | S3TALOADdpar(shrq, depdpar) =>
    (
    if (shrq = 0)
    then
    (
    if dep_wantq(fopt)
    then
    (
    report_dep_l2(out0, fopt);
    f3perr0_d3parsed(out0, depdpar);
    report_dep_opt(out0, d3parsed_get_parsed(depdpar)))
    else ())
    else ())
  | S3TALOADnone(sopt2) => report_dep_s2(out0, fopt, sopt2))
| D3Cinclude
  (_(*knd*), _(*tknd*), _(*gsrc*), _(*fopt*), dopt) =>
  report_dep_opt(out0, dopt)
| _(*else*) => ()
//
and
report_dep_lst
(out0: FILR, dcls: d3eclist): void =
case+ dcls of
| list_nil() => ()
| list_cons(d1, ds1) =>
  (report_dep1(out0, d1); report_dep_lst(out0, ds1))
//
and
report_dep_opt
(out0: FILR, dopt: d3eclistopt): void =
case+ dopt of
| optn_nil() => ()
| optn_cons(dcls) => report_dep_lst(out0, dcls)
//
fun
report_deps
(out0: FILR, dpar: d3parsed): void =
report_dep_opt(out0, d3parsed_get_parsed(dpar))
//
(* ****** ****** *)
//
(*
EVICTION (M6): after the reports (which MUTATE cached dep d2parsed via
tread12 — the mutation is discarded by this very eviction) remove the
checked file and every freshly-loaded (shr = 0) non-stdlib dependency
from the four per-file caches.  Keys are the fnm2 stamps, exactly as
xsymmap_topmap keys its mydict.  STDLIB deps stay cached (immutable
like the pvsloaded prelude — same warm-check win, same assumption).
The delete leaf treats the topmap by its runtime rep (jshmap); an
absent key is a no-op, so evicting the (never-cached) target is
belt-and-braces.
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
fun
evict_fopt(fopt: fpathopt): void =
case+ fopt of
| optn_nil() => ()
| optn_cons(fpx) => evict_fnm2(fpath_get_fnm2(fpx))
//
fun
evict_dep_s2
(fopt: fpathopt, sopt2: s2taloadopt): void =
case+ sopt2 of
| S2TALOADdpar(shrq2, depd2p) =>
  (
  if (shrq2 = 0)
  then
  (
  if dep_wantq(fopt)
  then
  (
  evict_fopt(fopt);
  evict_dep2_opt(d2parsed_get_parsed(depd2p)))
  else ())
  else ())
| _(*none/fenv*) => ()
//
and
evict_dep2_1
(dpcl2: d2ecl): void =
case+ d2ecl_get_node(dpcl2) of
| D2Cstaload
  (_(*knd*), _(*tknd*), _(*gsrc*), fopt2, sopt2) =>
  evict_dep_s2(fopt2, sopt2)
| D2Cinclude
  (_(*knd*), _(*tknd*), _(*gsrc*), _(*fopt*), dopt2) =>
  evict_dep2_opt(dopt2)
| _(*else*) => ()
//
and
evict_dep2_lst
(dcls: d2eclist): void =
case+ dcls of
| list_nil() => ()
| list_cons(d1, ds1) =>
  (evict_dep2_1(d1); evict_dep2_lst(ds1))
//
and
evict_dep2_opt
(dopt: d2eclistopt): void =
case+ dopt of
| optn_nil() => ()
| optn_cons(dcls) => evict_dep2_lst(dcls)
//
fun
evict_dep1
(dpcl: d3ecl): void =
case+ d3ecl_get_node(dpcl) of
| D3Cstaload
  (_(*knd*), _(*tknd*), _(*gsrc*), fopt, sopt) =>
  (
  case+ sopt of
  | S3TALOADdpar(shrq, depdpar) =>
    (
    if (shrq = 0)
    then
    (
    if dep_wantq(fopt)
    then
    (
    evict_fopt(fopt);
    evict_dep_opt(d3parsed_get_parsed(depdpar)))
    else ())
    else ())
  | S3TALOADnone(sopt2) => evict_dep_s2(fopt, sopt2))
| D3Cinclude
  (_(*knd*), _(*tknd*), _(*gsrc*), _(*fopt*), dopt) =>
  evict_dep_opt(dopt)
| _(*else*) => ()
//
and
evict_dep_lst
(dcls: d3eclist): void =
case+ dcls of
| list_nil() => ()
| list_cons(d1, ds1) =>
  (evict_dep1(d1); evict_dep_lst(ds1))
//
and
evict_dep_opt
(dopt: d3eclistopt): void =
case+ dopt of
| optn_nil() => ()
| optn_cons(dcls) => evict_dep_lst(dcls)
//
fun
evict_deps
(fpth: strn, dpar: d3parsed): void =
(
evict_dep_opt(d3parsed_get_parsed(dpar));
evict_fnm2(fpath_get_fnm2(fpath_make_absolute(fpth))))
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
;
(*
LAST: the per-check eviction (M6) — after every report and the index
emission, since the walks and lspidx read the cached structures.
*)
evict_deps(fpth, dpar)
//
end where
{
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
