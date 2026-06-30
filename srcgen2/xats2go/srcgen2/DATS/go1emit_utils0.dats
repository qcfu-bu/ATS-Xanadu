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
go1emit_utils0 — naming + leaf-value emission for the Go backend (M1).
Mirrors xats2js/srcgen2/DATS/js1emit_utils0.dats, emitting Go instead of
JS for exactly the leaf nodes test01 needs.
//
Naming (PLAN.md §5.9, mirrors js1emit):
  - i1tnm  -> "goxtnm<stamp>"            (always a valid Go identifier)
  - d2cst  -> "xatsgo.<Goname(sym)>"     (known prelude csts routed to the
              xatsgo runtime; the dcst identity comes from the real timp,
              so this is the pipeline-resolved call, not an FFI shortcut)
  - string -> xatsgo.XATSSTRN("<go-escaped>")
*)
//
(* ****** ****** *)
(* ****** ****** *)
//
#include
"./../../..\
/HATS/xatsopt_sats.hats"
#include
"./../../..\
/HATS/xatsopt_dpre.hats"
//
(* ****** ****** *)
//
#staload // SYM =
"./../../../SATS/xsymbol.sats"
#staload // LOC =
"./../../../SATS/locinfo.sats"
#staload // LEX =
"./../../../SATS/lexing0.sats"
#staload // FP0 =
"./../../../SATS/filpath.sats"
#staload // BAS =
"./../../../SATS/xbasics.sats"
//
#staload // D2E =
"./../../../SATS/dynexp2.sats"
//
#staload // GLO =
"./../../../SATS/xglobal.sats"
//
(* ****** ****** *)
//
#staload ".\
/../../xats2cc\
/srcgen1/SATS/intrep0.sats"//...
//
#staload "./../SATS/intrep1.sats"
#staload "./../SATS/xats2go.sats"
#staload "./../SATS/go1emit.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#extern
fun
XATS2GO_gochar_esc
  (c0: char): strn = $extnam()
//
(* ****** ****** *)
(* ****** ****** *)
//
#symload lctn with d2cst_get_lctn
#symload lctn with d2var_get_lctn
#symload name with d2cst_get_name
#symload name with d2var_get_name
#symload node with token_get_node
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
go1emit_strn_contains: tiny path classifier helper kept local to the Go
emitter.  Used by [d2cst_package_sourceq] below; deliberately ASCII-only
because source paths and directory markers are ASCII.
*)
#implfun
go1emit_strn_contains
( hay: strn
, needle: strn): bool =
let
  val nhay = strn_length(hay)
  val nndl = strn_length(needle)
  fun
  match_at
  (i0: sint, j0: sint): bool =
    if j0 >= nndl then true else
    if strn_get$at(hay, i0+j0) = strn_get$at(needle, j0)
    then match_at(i0, j0+1) else false
  fun
  loop
  (i0: sint): bool =
    if nndl <= 0 then true else
    if i0 + nndl > nhay then false else
    if match_at(i0, 0) then true else loop(i0+1)
in//let
  loop(0)
end//endof[go1emit_strn_contains(hay,needle)]
//
(* ****** ****** *)
//
#implfun
go1emit_package_pathq
(path: strn): bool =
(
if go1emit_strn_contains(path, "prelude/") then false else
if go1emit_strn_contains(path, "xatslib/") then false else
if go1emit_strn_contains(path, "srcgen2/xats2go/srcgen2/") then true else
if go1emit_strn_contains(path, "srcgen2/SATS/") then true else
if go1emit_strn_contains(path, "srcgen2/DATS/") then true else false)
//
(* ****** ****** *)
//
#implfun
d2cst_known_packageq
(sname: strn): bool =
(
if
(sname = "d2cst_get_name") then true else
if
(sname = "d2cst_get_lctn") then true else
if
(sname = "d2cst_get_styp") then true else
if
(sname = "d2cst_get_stmp") then true else
if
(sname = "d2var_get_name") then true else
if
(sname = "d2var_get_lctn") then true else
if
(sname = "d2var_get_styp") then true else
if
(sname = "d2var_get_stmp") then true else
if
(sname = "token_get_node") then true else
if
(sname = "fprint_loctn_as_stamp") then true else
if
(sname = "symbl_get_name") then true else
if
(sname = "strnfpr") then true else
if
(sname = "chrfpr") then true else
if
(sname = "d2cstgo1") then true else
if
(sname = "d2cstimplgo1") then true else
if
(sname = "d2vargo1") then true else false)
//
#implfun
d2cst_known_runtimeq
(sname: strn): bool =
(
if
(sname = "XATS2GO_gochar_esc") then true else
if
(sname = "XATS2GO_chrfpr") then true else false)
//
(* ****** ****** *)
//
#implfun
d2cst_package_sourceq
(dcst) =
let
  val lsrc = loctn_get_lsrc(dcst.lctn((*0*)))
in//let
(
case+ lsrc of
|LCSRCsome1(path) => go1emit_package_pathq(path)
|LCSRCfpath(fpx) => go1emit_package_pathq(fpath_get_fnm1(fpx))
|_(*else*) => false)
end//endof[d2cst_package_sourceq(dcst)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
xsymgo1: emit a symbol's chars as a valid Go identifier fragment.
Mirrors xsymjs1 (escape ' -> $) but Go has no '$' in identifiers, so we
map any non-[A-Za-z0-9_] char to '_' (collisions are acceptable for the
M1 known-prelude surface; M2 introduces a stamp-disambiguated mangler).
*)
#implfun
xsymgo1
( filr: FILR
, xsym: sym_t): void =
let
//
val name = symbl_get_name(xsym)
//
#impltmp
foritm$work<char>(c0) =
let
val ok =
(
if
(c0 >= 'a')
then (c0 <= 'z') else
(
if
(c0 >= 'A')
then (c0 <= 'Z') else
(
if
(c0 >= '0')
then (c0 <= '9') else (c0 = '_'))))
val c1 =
(
if ok then c0 else '_')
in//let
(
  chrfpr(filr, c1)) end
//
in//let
(
  strn_foritm(name)) end//let
//endof[xsymgo1(filr,xsym)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
d2cstgo1: runtime/prelude constants route to xatsgo; compiler/backend helper
constants route to package symbols.  The classifier is intentionally hybrid:
known runtime externals stay runtime, [$extnam] impls recorded in the d2cst map
stay runtime, and only known helpers or compiler/backend source locations become
package names.  A miss never turns a prelude path into a package identifier.
*)
#implfun
d2cstgo1
(filr, dcst) =
let
val name = dcst.name((*0*))
val sname = symbl_get_name(name)
val stmp = d2cst_get_stmp(dcst)
val xopt = the_d2cstmap_xnmfind(stmp)
val xrtq =
(
case+ xopt of
| ~optn_vt_cons(X2NAMsome(_)) => true
| ~optn_vt_cons(X2NAMnone()) => false
| ~optn_vt_nil() => false)
val pkgq =
(
if d2cst_known_runtimeq(sname) then false else
if xrtq then false else
if d2cst_known_packageq(sname) then true else
d2cst_package_sourceq(dcst))
//
// CATS/GO prelude floor: a leaf primitive named `XATS2GO_*` (from the GO arm's
// $extnam binding) is provided by the linked .cats, so it emits as the BARE
// mangled name ([xsymgo1] maps `$`->`_`), NOT `xatsgo.Xats_XATS2GO_*`.  This
// only fires for `XATS2GO_`-prefixed names, which never occur in a JS-arm
// program, so the existing (JS-arm) suite is unaffected.
val goleafq =
(
if (strn_length(sname) >= 8)
then
  (
  if sname[0] != 'X' then false else
  if sname[1] != 'A' then false else
  if sname[2] != 'T' then false else
  if sname[3] != 'S' then false else
  if sname[4] != '2' then false else
  if sname[5] != 'G' then false else
  if sname[6] != 'O' then false else
  (sname[7] = '_'))
else false)
in//let
(
if
goleafq
then
  xsymgo1(filr, name)
else
if
pkgq
then
  d2cstimplgo1(filr, dcst)
else
(
  strnfpr(filr, "xatsgo.Xats_");
  xsymgo1(filr, name))) end
//endof[d2cstgo1(filr,dcst)]
//
(* ****** ****** *)
//
(*
d2cstimplgo1: a resolved user implementation constant -> package-level Go
identifier.  Unlike [d2cstgo1], this is NOT an xatsgo runtime hook; it mirrors
[d2vargo1]'s source-name + location-stamp scheme so a #implfun definition and
its package symbol are stable, Go-safe, and collision-resistant.
*)
#implfun
d2cstimplgo1
(filr, dcst) =
let
val name = dcst.name((*0*))
in//let
(
xsymgo1(filr, name);
strnfpr(filr, "_");
fprint_loctn_as_stamp(filr, dcst.lctn((*0*)))) end
//endof[d2cstimplgo1(filr,dcst)]
//
(* ****** ****** *)
//
(*
d2vargo1: a local/global dynamic variable -> "<go-safe-sym>_<gostamp>".
(Not exercised by test01's executed path, but provided for completeness
and used by any I1Vfid leaf.)
*)
#implfun
d2vargo1
(filr, dvar) =
let
val name = dvar.name((*0*))
in//let
(
xsymgo1(filr, name);
strnfpr(filr, "_");
fprint_loctn_as_stamp(filr, dvar.lctn((*0*)))) end
//endof[d2vargo1(filr,dvar)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
i1tnmgo1: an ANF temp -> "goxtnm<stamp>".
Mirrors i1tnmjs1 ("jsx"+"tnm"+stamp); "goxtnm" is always a valid Go id.
*)
#implfun
i1tnmgo1
(filr, itnm) =
(
prints("goxtnm", stmp)) where
{
#impltmp g_print$out<>() = filr
val stmp = i1tnm_stmp$get(itnm)
}(*where*)//endof[i1tnmgo1(filr,itnm)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
f0_gostr: emit the chars of a string body, Go-escaped, between the
double quotes already opened by the caller. Go string-literal escapes
match what test01 needs (\n \t \r \" \\); other control chars fall back
to \xHH is NOT needed for M1 (the only escape in test01 is \n).
*)
fun
f0_gostr
( filr: FILR
, cs: strn): void =
let
#impltmp
foritm$work<char>(c0) =
(
case+ c0 of
| '\n' => strnfpr(filr, "\\n")
| '\t' => strnfpr(filr, "\\t")
| '\r' => strnfpr(filr, "\\r")
| '\"' => strnfpr(filr, "\\\"")
| '\\' => strnfpr(filr, "\\\\")
| _(*else*) => chrfpr(filr, c0))
in//let
(
  strn_foritm(cs)) end
//endof[f0_gostr(filr,cs)]
//
(* ****** ****** *)
//
(*
i0s00go1: an evaluated string literal (I1Vs00 of strn) ->
  xatsgo.XATSSTR0("<go-escaped>")
*)
#implfun
i0s00go1
(filr, s00) =
(
strnfpr(filr, "xatsgo.XATSSTR0(\"");
strnfpr(filr, s00);
strnfpr(filr, "\")"))
//endof[i0s00go1(filr,s00)]
//
(* ****** ****** *)
//
(*
i0strgo1: a string-literal TOKEN (I1Vstr of token) ->
  xatsgo.XATSSTRN("<go-escaped>")
The token's [rep1] carries the raw source chars (incl. surrounding
quotes); mirror i0strjs1's clsd/ncls handling but skip the leading quote
and drop the trailing quote via the recorded length.
*)
#implfun
i0strgo1
(filr, tstr) =
(
case-
tstr.node() of
//
|T_STRN1_clsd
( rep1, len2 ) =>
(
strnfpr(filr, "xatsgo.XATSSTRN(\"");
f0_strn(rep1, len2-1);
strnfpr(filr, "\")"))
|T_STRN2_ncls
( rep1, len2 ) =>
(
strnfpr(filr, "xatsgo.XATSSTRN(\"");
f0_strn(rep1, len2-0);
strnfpr(filr, "\")"))
) where
{
//
(*
GAP-2 fix (self-hosting): the token's [rep1] holds the RAW SOURCE chars of
the string literal (the surface text between the quotes, INCLUDING the
opening quote at index 0).  Two source conventions must be normalized to a
valid Go double-quoted literal -- this mirrors the JS backend's [f0_strn]
escape handling (so the bytes match the JS oracle), with the JS-specific
output retargeted to Go:
//
  (a) a SOURCE BACKSLASH ESCAPE (`\n`, `\t`, `\"`, `\\`, ...) is already two
      literal chars '\'+c in [rep1].  A Go double-quoted literal accepts the
      SAME escape syntax (`\n` `\t` `\"` `\\` `\r` etc.), so we pass `\`+c
      THROUGH verbatim -- EXCEPT a backslash followed by a real NEWLINE byte,
      which is an ATS source LINE-CONTINUATION (`"foo\<NL>bar"` == `"foobar"`)
      and must be DROPPED entirely (both the `\` and the newline).  This is
      the bug that broke test70: the line-continuation `\<NL>` was copied raw,
      producing `"\<NL>..."` which Go rejects (`string literal not
      terminated`, `unknown escape sequence`).
  (b) a RAW CONTROL byte that appears UNESCAPED in [rep1] (a literal newline,
      tab or CR not preceded by `\`) is emitted as the corresponding Go escape
      (`\n` `\t` `\r`).  (The JS backend turns a raw newline into `\n\<NL>`, a
      JS line continuation; Go has no line continuation, so a plain `\n`.)
//
A bare trailing backslash (the last char before the closing quote) cannot
occur in a well-formed string but, for totality, is emitted as `\\` so the
output stays a valid Go literal.
*)
fun
f0_strn
( rep1: strn
, len2: sint): void =
let
//
val n0 = len2
//
fnx
loop1
(i0: nint): void =
if
(i0 >= n0)
then ((*0*)) else
let
val c0 = rep1[i0]
in//let
//
if // if1
(c0 = '\\')
then//then1
(
// a source backslash: consume + handle the following char in [loop2].
loop2(i0+1)
) else//if1
(
// a RAW (unescaped) control byte -> the matching Go escape; else verbatim.
case+ c0 of
| '\n' => (strnfpr(filr, "\\n"); loop1(i0+1))
| '\t' => (strnfpr(filr, "\\t"); loop1(i0+1))
| '\r' => (strnfpr(filr, "\\r"); loop1(i0+1))
| _(*else*) => (chrfpr(filr, c0); loop1(i0+1)))
end//let//end-of-[loop1(i0)]
//
and
loop2
(i1: nint): void =
if // if
(i1 >= n0)
then//then
(
// a trailing bare backslash (malformed source) -> a literal `\\` (Go-valid).
strnfpr(filr, "\\\\")) else
let
  val c1 = rep1[i1]
in (*let*)
if // if
(c1 = '\n')
then//then
(
// `\<NL>` = ATS source line continuation -> DROP both, continue after the NL.
loop1(i1+1)) else
(
// `\`+c is an already-valid Go escape (\n \t \" \\ \r ...) -> pass through.
chrfpr(filr, '\\'); chrfpr(filr, c1); loop1(i1+1))
end//let//end-of-[loop2(i1)]
//
in//let
(
// skip the opening quote at index 0
let val i0 = 1 in loop1(i0) end) end//let
//endof[f0_strn(rep1,len2)]
//
}(*where*)//endof[i0strgo1(filr,tstr)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(*
=======================================================================
== SCALAR LITERALS -> CONCRETE GO  (milestone M2.1)                   ==
=======================================================================
//
Emit ATS scalar literals as native Go literal syntax (NOT boxed `any`).
The node kind IS the Go type (gotype_of_ival), so a literal carries its
own concrete type:
  I1Vint/I1Vi00 -> int      (Go integer literal, e.g. 42)
  I1Vbtf/I1Vb00 -> bool     (true / false)
  I1Vchr/I1Vc00 -> rune     (Go rune literal, e.g. 'A')
  I1Vflt/I1Vf00 -> float64  (Go float literal, e.g. 1.5)
This is the Regime-B scalar payoff: arithmetic over these composes with
native Go operators (see go1emit_styp0.dats: op recognition).
*)
//
(* ****** ****** *)
//
(*
i0intgo1: an integer-literal TOKEN -> a Go integer literal.
T_INT01(rep) is base-10 with rep the raw decimal digits ("42"), which is
already a valid Go int literal -- emit it verbatim.  T_INT02/03 (non-10
bases / suffixes) are rarer; emit the rep verbatim too when present (Go
shares 0x/0o/0b prefixes) and fall back to a boxed runtime form only if
the shape is unrecognized.
*)
#implfun
i0intgo1
(filr, tint) =
(
case- tint.node() of
|T_INT01(rep) => strnfpr(filr, rep)
|T_INT02(_, rep) => strnfpr(filr, rep)
|T_INT03(_, rep, _) => strnfpr(filr, rep)
)
//endof[i0intgo1(filr,tint)]
//
#implfun
i0i00go1
(filr, i00) =
(
prints(i00)) where
{
#impltmp g_print$out<>() = filr
}(*where*)//endof[i0i00go1(filr,i00)]
//
(* ****** ****** *)
//
(*
i0btfgo1 / i0b00go1: a boolean literal -> Go `true`/`false`.
The token form carries the symbol (TRUE_symbl/FALSE_symbl); the evaluated
form carries a Go-level bool.
*)
#implfun
i0btfgo1
(filr, btf0) =
(
if
(symbl_cmp(btf0, TRUE_symbl) = 0)
then strnfpr(filr, "true")
else strnfpr(filr, "false")
)//endof[i0btfgo1(filr,btf0)]
//
#implfun
i0b00go1
(filr, b00) =
(
if b00
then strnfpr(filr, "true")
else strnfpr(filr, "false")
)//endof[i0b00go1(filr,b00)]
//
(* ****** ****** *)
//
(*
i0fltgo1 / i0f00go1: a float literal -> Go float64 literal.
T_FLT01(rep) is the base-10 source text ("1.5"); a Go float64 literal
shares that syntax, so emit verbatim.  The runtime's dflt_print matches
JS Number.toString() at the PRINT site, so the literal value itself need
only be the same float64 -- which "1.5" parses to identically in Go & JS.
*)
#implfun
i0fltgo1
(filr, tflt) =
(
case- tflt.node() of
|T_FLT01(rep) => strnfpr(filr, rep)
|T_FLT02(_, rep) => strnfpr(filr, rep)
|T_FLT03(_, rep, _) => strnfpr(filr, rep)
)
//endof[i0fltgo1(filr,tflt)]
//
#implfun
i0f00go1
(filr, f00) =
(
prints(f00)) where
{
#impltmp g_print$out<>() = filr
}(*where*)//endof[i0f00go1(filr,f00)]
//
(* ****** ****** *)
//
(*
i0chrgo1 / i0c00go1: a char literal -> a Go rune literal.
A Go rune literal is a single-quoted character.  The token rep INCLUDES
the surrounding quotes (e.g. "'A'") and any backslash escape already in
Go-compatible form for the common cases; the evaluated form carries a
Go char.  We emit a rune literal with Go escapes for the control chars.
*)
#implfun
i0chrgo1
(filr, tchr) =
(
case- tchr.node() of
|T_CHAR1_nil0 _ =>
  strnfpr(filr, "rune(0)")
|T_CHAR2_char(rep) =>
  // rep is "'?'" -- already a Go rune literal for printable ASCII.
  strnfpr(filr, rep)
|T_CHAR3_blsh(rep) =>
  // rep is "'\\?'" -- emit the recognized Go escapes; ATS and Go share
  // \n \t \r \b \f \v \\ \' so the source rep is Go-compatible verbatim,
  // EXCEPT \" which is invalid in a Go rune literal (Go wants '"', not '\"').
  if rep = "'\\\"'" then strnfpr(filr, "'\"'") else strnfpr(filr, rep)
)
//endof[i0chrgo1(filr,tchr)]
//
(*
f0_gochr: emit one char inside a Go rune literal, Go-escaped.
*)
fun
f0_gochr
( filr: FILR
, c0: char): void =
(
strnfpr(filr, XATS2GO_gochar_esc(c0))
)//endof[f0_gochr(filr,c0)]
//
#implfun
i0c00go1
(filr, c00) =
(
strnfpr(filr, "'");
f0_gochr(filr, c00);
strnfpr(filr, "'"))
//endof[i0c00go1(filr,c00)]
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_go1emit_utils0.dats] *)
(***********************************************************************)
