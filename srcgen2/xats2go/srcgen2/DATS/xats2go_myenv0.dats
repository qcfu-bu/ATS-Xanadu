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
xats2go — minimal [envx2go] implementation for milestone M0.
Mirrors xats2js/srcgen2/DATS/xats2js_myenv0.dats.
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
(* ****** ****** *)
(* ****** ****** *)
//
#staload ".\
/../../xats2cc\
/srcgen1/SATS/intrep0.sats"//...
//
#staload // STMP =
"./../../../SATS/xstamp0.sats"
//
#staload "./../SATS/intrep1.sats"
#staload "./../SATS/trxi0i1.sats"
#staload "./../SATS/xats2go.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
#extern
fun
XATS2GO_chrfpr
  (filr: FILR, c0: char): void = $extnam()
//
(* ****** ****** *)
(* ****** ****** *)
//
(* ****** ****** *)
// local
(* ****** ****** *)
//
datavwtp
envx2go =
ENVX2GO of
( FILR(*output*)
, sint(*level0*)
, sint(*indent*))
//
#absimpl envx2go_vtbx = envx2go
//
(* ****** ****** *)
// in//local
(* ****** ****** *)
//
#implfun
envx2go_filr$get
  ( env0 ) =
let
val+
ENVX2GO
(filr
,lvl0, nind) = env0 in filr end
//
#implfun
envx2go_lvl0$get
  ( env0 ) =
let
val+
ENVX2GO
(filr
,lvl0, nind) = env0 in lvl0 end
//
#implfun
envx2go_nind$get
  ( env0 ) =
let
val+
ENVX2GO
(filr
,lvl0, nind) = env0 in nind end
//
(* ****** ****** *)
//
#implfun
envx2go_make_out
  ( filr ) = ENVX2GO(filr, 0, 0)
//
(* ****** ****** *)
//
#implfun
envx2go_free_nil
  (  env0  ) =
(
case+ env0 of
| ~
ENVX2GO
(filr, lvl0, nind) => ((*void*)))
(*case+*)//end-of-(envx2go_free_nil(env0))
//
(* ****** ****** *)
//
(*
CLAUDE-2026-08 (zztic stage B): the shared-instance emission memo (see
xats2go.sats).  Frames parallel the emitted Go block structure: incnind
opens a scope, decnind closes it (dropping its entries), so [find] only
ever returns a temp that is lexically visible at the alias site.
*)
datatype
zzime =
ZZIME of (stamp(*instance*), stamp(*bound temp*))
//
#typedef zzimelst = list(zzime)
//
local
//
val
zzimemo =
a0ref_make_1val
<list(zzimelst)>(list_nil())
//
in//local
//
fun
zzime_scopepush((*void*)): void =
a0ref_set<list(zzimelst)>
( zzimemo
, list_cons
  (list_nil(), a0ref_get<list(zzimelst)>(zzimemo)))
//
fun
zzime_scopepop((*void*)): void =
(
case+
a0ref_get<list(zzimelst)>(zzimemo) of
|list_nil() => ((*void*))
|list_cons(_, rest) =>
a0ref_set<list(zzimelst)>(zzimemo, rest))
//
#implfun
go1emit_instmemo_add
(istmp, tstmp) =
(
case+
a0ref_get<list(zzimelst)>(zzimemo) of
|list_nil() => ((*no open scope: drop*))
|list_cons(top, rest) =>
a0ref_set<list(zzimelst)>
( zzimemo
, list_cons(list_cons(ZZIME(istmp, tstmp), top), rest)))
//
#implfun
go1emit_instmemo_find
(  istmp  ) = let
//
fun
scan1(ents: zzimelst): optn(stamp) =
(
case+ ents of
|list_nil() => optn_nil()
|list_cons(ZZIME(is1, ts1), ents) =>
 if
 (stamp_cmp(is1, istmp) = 0)
 then optn_cons(ts1) else scan1(ents))
//
fun
scans(frms: list(zzimelst)): optn(stamp) =
(
case+ frms of
|list_nil() => optn_nil()
|list_cons(frm1, frms) =>
(
case+ scan1(frm1) of
|optn_cons(ts1) => optn_cons(ts1)
|optn_nil() => scans(frms)))
//
in//let
(
  scans(a0ref_get<list(zzimelst)>(zzimemo)) )
end//let//end-of-[go1emit_instmemo_find(istmp)]
//
end(*local*)//end-of-[local(zzimemo)]
//
(* ****** ****** *)
//
(*
CLAUDE-2026-08 (zztic v2b): the LIFTED-instance set.  The PASS-0
pre-pass lifts every shared instance occurring >=2 times in the module
to a package-level `var goxtmpl<stamp> = func...`; a SITE then emits
that name instead of a literal/alias.  [emitting] guards the pre-pass
emission itself: while instance X's own body is being emitted, the
liftedq test answers false for X (so it emits its body, not its name);
nested OTHER lifted instances inside still reference their names.
*)
local
//
val
zzlifted =
a0ref_make_1val
<list(stamp)>(list_nil())
//
val
zzemitting =
a0ref_make_1val<stamp>(the_stamp_nil)
//
in//local
//
#implfun
go1emit_instlift_add
(   istmp   ) =
a0ref_set<list(stamp)>
( zzlifted
, list_cons(istmp, a0ref_get<list(stamp)>(zzlifted)))
//
#implfun
go1emit_instlift_emitting
(   istmp   ) =
a0ref_set<stamp>(zzemitting, istmp)
//
#implfun
go1emit_instliftq
(   istmp   ) = let
//
fun
scan(xs: list(stamp)): bool =
(
case+ xs of
|list_nil() => false
|list_cons(x1, xs) =>
 if
 (stamp_cmp(x1, istmp) = 0)
 then true else scan(xs))
//
in//let
if
(stamp_cmp(a0ref_get<stamp>(zzemitting), istmp) = 0)
then false
else scan(a0ref_get<list(stamp)>(zzlifted))
end//let//end-of-[go1emit_instliftq(istmp)]
//
end(*local*)//end-of-[local(zzlifted)]
//
(* ****** ****** *)
//
#implfun
envx2go_incnind
(  env0, ninc  ) = let
//
val+
@ENVX2GO
(filr, lvl0, !nind) = env0
//
val () = zzime_scopepush((*void*))
//
in//let
//
(
nind := nind + ninc; $fold(env0))
//
end (*let*)//end-of-(envx2go_incnind(env0))
//
#implfun
envx2go_decnind
(  env0, ndec  ) = let
//
val+
@ENVX2GO
(filr, lvl0, !nind) = env0
//
val () = zzime_scopepop((*void*))
//
in//let
//
(
nind := nind - ndec; $fold(env0))
//
end (*let*)//end-of-(envx2go_decnind(env0))
//
(* ****** ****** *)
(* ****** ****** *)
//
#implfun
strnfpr(
filr, strn) =
(
strn_fprint(strn, filr))
//
#implfun
chrfpr(
filr, c0) =
(
XATS2GO_chrfpr(filr, c0))
//
#implfun
nindfpr(
filr, nind) =
// emit one TAB per indent level so emitted Go is gofmt-clean (Go is
// whitespace-insensitive, so this is cosmetic, but it keeps `gofmt -l`
// quiet and makes review diffs match canonical Go).
if nind > 0 then
(
strn_fprint
("\t", filr); nindfpr(filr, nind-1))
//
#implfun
nindstrnfpr
(filr
,nind, strn) =
(
nindfpr(filr, nind);strnfpr(filr, strn))
//
(* ****** ****** *)
(* ****** ****** *)
// end (*local*) // end of [local(envx2go_vtbx)]
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_DATS_xats2go_myenv0.dats] *)
(***********************************************************************)
