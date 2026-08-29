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
xats2go_tcheck01 — the CHECK-ONLY driver (for the ATS3 LSP server).
//
CLAUDE-2026-08-28: [xats2go_goemit01.dats] with the backend REMOVED: the
pipeline stops after the diagnostics reports —
//
  d0parsed_from_fpath -> pread00 report (PREAD00-ERROR, parse level)
    -> d3parsed_of_trans03
    -> tread3a / trtmp3b / trtmp3c / t3read0
    -> f3perr0_d3parsed report (F3PERR0-ERROR)
//
No trxd3i0/tryd3i0/trxi0i1, no Go emission, nothing on stdout.  The
diagnostic surface (stderr) is BYTE-COMPATIBLE with xats2go_goemit01 on
the same input: the LSP server parses these stderr reports.  Built by
selfhost-build/wire-tcheck.sh into src/tcheck/ over the SAME assembled
frontend packages as the CLI driver.
*)
//
(* ****** ****** *)
(* ****** ****** *)
#include
"./../../..\
/HATS/xatsopt_sats.hats"
(*
#include
"./../../..\
/HATS/xatsopt_dats.hats"
*)
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
[pread00] is not in libxatsopt.hats; the driver needs it for
[d0parsed_of_pread00] and [d0parsed_fpemsg] (see xats2go_goemit01).
[lexbuf0] is not there either; the [--stdin] mode needs
[lxbf1_make_strn].  Both are driver-local staloads (only this module's
stamps move).
*)
#staload "./../../../SATS/pread00.sats"
#staload "./../../../SATS/lexbuf0.sats"
#staload "./../../../SATS/filpath.sats"
#staload "./../../../SATS/f2perr0.sats"
//
(* the --index hover/def emitter (built alongside by wire-tcheck.sh) *)
#staload "./xats2go_lspidx.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#if
defq(_XATS2JS_)
#typedef argv=jsa1sz(strn)
#endif//#if(defq(_XATS2JS_))
//
#if
defq(_XATS2PY_)
#typedef argv=pya1sz(strn)
#endif//#if(defq(_XATS2PY_))
//
#extern
fun
XATSOPT_argv$get
  ((*0*)): argv = $extnam()
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
the diagnostics window must bracket BOTH the parse phase and the
f3perr0 report (see xats2go_goemit01): the srcgen2 resolver does not
apply the reporters' local `g_print$out<>() = out` hooks, so the
runtime default channel is flipped to stderr for the duration.
*)
#extern
fun
XATS2GO_report_begin((*void*)): void = $extnam()
#extern
fun
XATS2GO_report_end((*void*)): void = $extnam()
//
(* the whole stdin as one string (the --stdin buffer payload) *)
#extern
fun
XATS2GO_tcheck_stdin_readall((*void*)): strn = $extnam()
//
(* ****** ****** *)
//
(* ASCII string helpers (the driver's own flags/extensions) *)
fun
my_streq
(s1: strn, s2: strn): bool =
let
val n1 = strn_length(s1)
val n2 = strn_length(s2)
fun
loop(i0: sint): bool =
if i0 >= n1 then true else
if strn_get$at(s1, i0) = strn_get$at(s2, i0)
then loop(i0+1) else false
in//let
if n1 = n2 then loop(0) else false
end//endof[my_streq]
//
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
(* ****** ****** *)
//
(*
[--stdin]: parse TEXT (the editor's unsaved buffer, read from stdin)
ATTRIBUTED to the real path — replicates [trans00_from_fpath]
(DATS/parsing.dats) except the lexbuf comes from the text: the token
locations AND the d0parsed source carry LCSRCsome1(fpth), so
diagnostics name the file and relative staloads resolve exactly as in
the on-disk mode.
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
dependency errors: a staloaded file's errck nodes live in ITS
d3parsed and NOTHING reports them — the target's f3perr0 walks only
the target's decl list, and its D3Cstaload arm deliberately does not
descend.  But the staload node CARRIES the dependency:
S3TALOADdpar(shr, d3parsed).  Walk the target's decls (descending
through includes), and for every FRESHLY-CHECKED (shr = 0) dependency
report its errors with f3perr0 — the lines print the dependency's own
path, and the LSP filters by ITS workspace root (the driver stays
policy-free: a clean dependency prints nothing, so the toolchain
files cost only the walk) — recursing for transitive deps (shr = 0
fires exactly once per file per run, so the walk terminates).
//
(An earlier attempt enumerated the_d3parenv via topmap_strmize and
appeared to be erased — LATER DIAGNOSED (2026-08-29): the erasure came
from an unrelated errck (a missing staload) poisoning the decl, and a
separate probe artifact came from RELATIVE-path invocation degrading
d2cst_package_sourceq's substring test.  topmap_strmize works fine
from a driver when the input path is ABSOLUTE, as wire-tcheck passes
it.  This AST walk is kept anyway: the staload nodes carry the
dependency directly, which is the better source here.)
//
The dependency pipeline (s3taload_from_fpath) SKIPS the tread12
proofread, so its binding/static errors are never wrapped in errck
decls and f3perr0 alone finds nothing — run tread12 on the dep's
CACHED d2parsed and report with f2perr0 (F2PERR0-ERROR lines), plus
f3perr0 on its d3parsed for the L3 expression errcks.  Mutating the
shared cache is fine: the process is one-shot and this runs last.
//
STDLIB deps are excluded by path ($XATSHOME/prelude/ + /xatslib/):
tread12 over the prelude's own DATS floods thousands of recoverable
template reports.  Anything else — including workspaces that live
INSIDE the repo — is reported.
*)
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
a SATS staload's payload is a d2parsed (S2TALOADdpar) — report it at
level 2 and recurse through ITS staloads with a parallel L2 walk.
*)
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
fun
mymain_work
(fpth: string, stdinq: sint, idxq: sint): void =
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
out0 = g_stderr((*0*))
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
the hover/def index (--index): machine records on STDOUT — the
channel is otherwise unused by this driver.
*)
if (idxq > 0)
then lspidx_emit(g_stdout<>((*0*)), dpar) else ()
//
end where
{
//
(*
the PARSE-level (PREAD00) report between the halves of
[d3parsed_of_fildats] — see the long note in xats2go_goemit01.dats.
stadyn follows the EXTENSION (.sats = 0, else 1); the text comes from
the file, or from stdin under [--stdin].
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
my_d0parsed_from_text
(stadyn, XATS2GO_tcheck_stdin_readall(), fpth)
else d0parsed_from_fpath(stadyn, fpth)): d0parsed
//
val
d0par =
d0parsed_of_pread00(d0par0)
//
val ( ) =
d0parsed_fpemsg(g_stderr((*0*)), d0par)
//
val
dpar = d3parsed_of_trans03(d0par)
//
val ( ) = XATS2GO_report_end()
//
}(*where*)//end-of-[mymain_work(fpth,stdinq,idxq)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
the driver's OWN flags ([--stdin]; [--index] reserved for the M3 query
mode) are consumed here, not fed to the compiler flag store.
*)
fun
my_ownflagq(arg0: strn): bool =
if my_streq(arg0, "--stdin") then true else
if my_streq(arg0, "--index") then true else false
//
fun
argv$hasflag
(argv: argv, name: strn): sint =
(
  loop(3)) where
{
//
val n0 = length(argv)
//
fun
loop(i0: sint): sint =
if
(i0 < n0)
then
(if my_streq(argv[i0], name) then 1 else loop(i0+1))
else 0
}(*where*)//end-of-[argv$hasflag(argv,name)]
//
fun
argv$loop
(argv: argv): void =
(
  loop(3)) where
{
//
val n0 = length(argv)
//
fun
loop(i0: sint): void =
if
(i0 < n0)
then
(
  loop(i0+1)) where
{
val () =
if my_ownflagq(argv[i0])
then ((*consumed*))
else xatsopt_flag$pvsadd0(argv[i0])
}
}(*where*)//end-of-[argv$loop(argv)]
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
mymain_main(): void =
let
//
val alen = length(argv)
//
val (  ) =
if
(
alen >= 3)
then
let // let
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
(
argv$loop(argv);
mymain_work
( argv[2]
, argv$hasflag(argv, "--stdin")
, argv$hasflag(argv, "--index")))
endlet // let // if(length(argv) >= 3)
//
val (  ) =
if
(
alen<=2)
then
let//let
val (  ) =
(
prerrsln
("ERROR: no source is given: ", argv))
endlet // let // if(length(argv) <= 2)
//
endlet where
{
//
val (  ) =
prerrsln("\
// Welcome from ATS3/Xanadu! (xats2go tcheck01)")
val (  ) =
prerrsln("\
// XATSHOME = ", the_XATSHOME())
//
val argv = XATSOPT_argv$get((*0*))
//
}(*where*)//end-of-[mymain_main(...)]
//
(* ****** ****** *)
(* ****** ****** *)
val ((*the_entry_point*)) = mymain_main((*void*))
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_UTIL_xats2go_tcheck01.dats] *)
(***********************************************************************)
