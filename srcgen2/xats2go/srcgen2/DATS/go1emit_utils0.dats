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
#staload // BAS =
"./../../../SATS/xbasics.sats"
//
#staload // D2E =
"./../../../SATS/dynexp2.sats"
//
(* ****** ****** *)
//
#staload ".\
/../../../xats2cc\
/srcgen1/SATS/intrep0.sats"//...
//
#staload "./../SATS/intrep1.sats"
#staload "./../SATS/xats2go.sats"
#staload "./../SATS/go1emit.sats"
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
xsymgo1: emit a symbol's chars as a valid Go identifier fragment.
Mirrors xsymjs1 (escape ' -> $) but Go has no '$' in identifiers, so we
map any non-[A-Za-z0-9_] char to '_' (collisions are acceptable for the
M1 known-prelude surface; M2 introduces a stamp-disambiguated mangler).
*)
fun
xsymgo1
( filr: FILR
, xsym: symbl): void =
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
  char_fprint(c1, filr)) end
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
d2cstgo1: route a prelude constant to its xatsgo runtime entry point.
The dcst identity is whatever the pipeline-resolved I1INStimp produced;
we emit  xatsgo.Xats_<sym>  and capitalize via the explicit "Xats_"
prefix so the result is an exported Go identifier regardless of the ATS
symbol's case. The xatsgo runtime provides Xats_strn_print /
Xats_the_print_store_log etc. as first-class function values.
*)
#implfun
d2cstgo1
(filr, dcst) =
let
val name = dcst.name((*0*))
in//let
(
strnfpr(filr, "xatsgo.Xats_");
xsymgo1(filr, name)) end
//endof[d2cstgo1(filr,dcst)]
//
(* ****** ****** *)
//
(*
d2vargo1: a local/global dynamic variable -> "<sym>_<gostamp>".
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
| '\n' => strn_fprint("\\n", filr)
| '\t' => strn_fprint("\\t", filr)
| '\r' => strn_fprint("\\r", filr)
| '\"' => strn_fprint("\\\"", filr)
| '\\' => strn_fprint("\\\\", filr)
| _(*else*) => char_fprint(c0, filr))
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
f0_gostr(filr, s00);
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
(*
The token's [rep1] holds the RAW SOURCE chars, so any backslash escape
(e.g. \n) is already present as the two literal chars '\' 'n' -- which is
exactly the form a Go double-quoted string literal wants. So we copy
verbatim, mirroring i0strjs1 (which likewise does NOT re-escape '\').
A raw newline byte cannot appear in a single-line source string, so no
special case is needed for it here.
*)
(
char_fprint(c0, filr); loop1(i0+1))
end//let//end-of-[loop1(i0)]
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
  // \n \t \r \b \f \v \\ \' so the source rep is Go-compatible verbatim.
  strnfpr(filr, rep)
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
case+ c0 of
| '\n' => strn_fprint("\\n", filr)
| '\t' => strn_fprint("\\t", filr)
| '\r' => strn_fprint("\\r", filr)
| '\b' => strn_fprint("\\b", filr)
| '\f' => strn_fprint("\\f", filr)
| '\v' => strn_fprint("\\v", filr)
| '\'' => strn_fprint("\\'", filr)
| '\\' => strn_fprint("\\\\", filr)
| _(*else*) => char_fprint(c0, filr)
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
