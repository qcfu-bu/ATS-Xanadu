(* ****** ****** *)
(*
WS-1a — LSP diagnostics checker (Stages 2+3).

A "compiler-linking" driver: it #include's the compiler headers and calls
the front-end (d3parsed_of_fil{sats,dats}); built by linking against the
compiled compiler srcgen2/lib/lib2xatsopt.js (see build.sh).

Instead of the stock f3perr0_d3parsed text report, it runs a NEW traversal
(modeled structurally on srcgen2/DATS/f3perr0_dynexp.dats + f3perr0_decl00
+ f2perr0_dynexp) that, at each `…errck` node, READS the wrapped node's
internal 0-based location (loc.pbeg().nrow()/.ncol(), loc.pend()...) and
CLASSIFIES the error into a §4.1 `code` + a human message, then pushes it
to a JS-side accumulator (LSPCHK_diag_push). The JS side (xats_lsp_check.cats)
dedups per Decision D6 and serializes the §4 JSON bundle to --json-out.

Primer anchors: §3 (front-end API), §5 (0-based internal coords via
accessors), §6 (errck nodes / codes / dedup), §9 (traversal template).
*)
(* ****** ****** *)
#include
"./../../../srcgen2/HATS/libxatsopt.hats"
(* ****** ****** *)
#include
"./../../../srcgen2/HATS/xatsopt_sats.hats"
#include
"./../../../srcgen2/HATS/xatsopt_dpre.hats"
(* ****** ****** *)
//
// libxatsopt.hats already #staload's dynexp2/dynexp3/staexp2/statyp2/xsymbol,
// and each of those SATS carries its own `#symload node/lctn/styp/name` — so
// the dot-notation for d2*/d3*/s2cst/symbl is already in scope. We add the
// three SATS that libxatsopt does NOT staload but we need, exactly as the
// stock reporter files (f2perr0_dynexp.dats / dynexp1_print0.dats) do:
//   locinfo  -> postn/loctn accessors (pbeg/pend/ntot/nrow/ncol)
//   lexing0  -> token accessors
//   dynexp1  -> bare D1Eid0 + d1exp.node()
//
#staload "./../../../srcgen2/SATS/locinfo.sats"
#staload "./../../../srcgen2/SATS/lexing0.sats"
#staload "./../../../srcgen2/SATS/dynexp1.sats"
//
// filpath -> fpath_get_fnm1 (the file path inside a LCSRCfpath source). The
// go-to-def path mapping (primer §8) reads lctn.lsrc() -> fpath -> fnm1.
#staload "./../../../srcgen2/SATS/filpath.sats"
//
(* ****** ****** *)
(* ****** ****** *)
//
// ---------------- FFI declarations (impl in the .cats) ----------------
//
#if
defq(_XATS2JS_)
#typedef argv=jsa1sz(strn)
#endif
//
#extern fun
XATSOPT_argv$get((*0*)): argv = $extnam()
//
#extern fun
LSPCHK_argv_count((*0*)): sint = $extnam()
#extern fun
LSPCHK_argv_get(i0: sint): strn = $extnam()
//
// string-buffer FILR (capture a type's printed form, primer §7 leaf printer)
#extern fun
LSPCHK_strbuf_new((*0*)): FILR = $extnam()
#extern fun
LSPCHK_strbuf_get(fb: FILR): strn = $extnam()
//
// push one raw diagnostic (0-based internal coords) into the JS accumulator
#extern fun
LSPCHK_diag_push
( l0: sint, c0: sint
, l1: sint, c1: sint
, code: strn, message: strn): void = $extnam()
//
// push one hover entry (0-based internal coords) into the JS accumulator.
// `typ` = source-syntax type string (the pretty-printer below).
// `kind` = "expr" | "pat".
#extern fun
LSPCHK_hover_push
( l0: sint, c0: sint
, l1: sint, c1: sint
, typ: strn, kind: strn): void = $extnam()
//
// push one definition entry into the JS accumulator. Coords are 0-based.
//   use{l0,c0,l1,c1} = the use-site range (the D3Evar/D3Ecst/D3Econ node)
//   defpath          = entity's def-site fnm1 path (lctn.lsrc() -> fpath fnm1);
//                      "" when the source is not a real file (skip in JS)
//   def{l0,c0,l1,c1} = the binding-site range (entity.lctn())
//   entity           = "var" | "cst" | "con"
//   hastdef          = 1 if a type-def is supplied, else 0
//   tdpath           = type-constant def-site path (s2cst_get_lctn fnm1)
//   td{l0,c0,l1,c1}  = the type-constant's declaration range
#extern fun
LSPCHK_def_push
( ul0: sint, uc0: sint, ul1: sint, uc1: sint
, defpath: strn
, dl0: sint, dc0: sint, dl1: sint, dc1: sint
, entity: strn
, hastdef: sint
, tdpath: strn
, tl0: sint, tc0: sint, tl1: sint, tc1: sint): void = $extnam()
//
// WS-5 document symbol: name + SymbolKind + name-range + container ("" if top).
#extern fun
LSPCHK_symbol_push
( l0: sint, c0: sint, l1: sint, c1: sint
, name: strn, kind: sint, container: strn): void = $extnam()
//
// WS-5 inlay hint: position (end of bound name) + label (": T") + kind.
#extern fun
LSPCHK_inlay_push
(line: sint, col: sint, label: strn, kind: sint): void = $extnam()
//
// WS-6 Stage 3 member: receiver range + record field name + field type.
#extern fun
LSPCHK_member_push
( l0: sint, c0: sint, l1: sint, c1: sint
, name: strn, typ: strn): void = $extnam()
//
// dedup + serialize §4 bundle + write to jsonout
#extern fun
LSPCHK_json_finish
(uri: strn, nerror: sint, jsonout: strn): void = $extnam()
//
(* ****** ****** *)
(* ****** ****** *)
//
fun
fpath_satsq
(fp: strn): bool = let
val n0 = strn_length(fp)
in
if (n0 <= 4) then false else
( if(fp[n0-1]!='s') then (false) else
  if(fp[n0-2]!='t') then (false) else
  if(fp[n0-3]!='a') then (false) else
  if(fp[n0-4]!='s') then (false) else
  if(fp[n0-5]!='.') then (false) else (true))
end
//
(* ****** ****** *)
//
(* ****** ****** *)
//
// ----------------- render a type (s2typ) to a JS string ---------------
// A minimal source-ish renderer for type-mismatch messages: we extract the
// HEAD of the type so the message reads "expected `int`, got `string`"-ish
// rather than the full debug AST. We resolve:
//   T2Pcst(s2c)          -> the constant's name (e.g. gint_type, the_s2exp_strn0)
//   T2Papps(head, _)     -> recurse on the head (so int<...> -> its head name)
//   T2Ptext(name, _)     -> the external name string (e.g. xats_sint_t)
//   T2Ps2exp / others    -> fall back to the compiler's debug printer
// A full source-syntax pretty-printer is WS-2's job (primer §7); this is the
// cheap leaf-printer the task permits.
//
fun
typ_to_strn
(t2p: s2typ): strn = typ_aux(t2p, 4) where {
  // `fuel` bounds recursion through existential-var resolution chains so we
  // never loop on a self-referential / still-unresolved unification var.
  fun
  typ_aux
  (t2p: s2typ, fuel: sint): strn =
  if (fuel <= 0) then typ_to_strn_dbg(t2p) else
  (
  case+ s2typ_get_node(t2p) of
  | T2Pcst(s2c) => symbl_get_name(s2cst_get_name(s2c))
  | T2Papps(head, _) => typ_aux(head, fuel-1)
  | T2Ptext(nm, _) => nm
  | T2Pxtv(xv) => typ_aux(x2t2p_get_styp(xv), fuel-1)
  | _ => typ_to_strn_dbg(t2p)
  )
}
//
and
typ_to_strn_dbg
(t2p: s2typ): strn = let
  val fb = LSPCHK_strbuf_new()
  val () = s2typ_fprint(t2p, fb)
in
  LSPCHK_strbuf_get(fb)
end
//
(* ****** ****** *)
//
// =============== SOURCE-SYNTAX s2typ PRETTY-PRINTER (hover) =============
//
// The FAITHFUL printer is the SHARED include xats_lsp_typrint.hats (single
// source of truth; the inverse of p1_s0exp). It needs three leaf/FFI helpers:
//   TYPRINT_int2str / TYPRINT_stamp2str  (.cats) — int label / xtv stamp
//   TYPRINT_sort2str                     (here)  — sort -> surface name (Exact)
// Hover uses TPMhover (friendly, readable); round-trip uses TPMexact.
//
#extern fun
TYPRINT_int2str(n: sint): strn = $extnam()
#extern fun
TYPRINT_stamp2str(s: stamp): strn = $extnam()
//
fun
TYPRINT_sort2str
(srt: sort2): strn = let
  val fb = LSPCHK_strbuf_new()
  val () = sort2_fprint(srt, fb)
in
  LSPCHK_strbuf_get(fb)
end
//
#include "./../HATS/xats_lsp_typrint.hats"
//
(* ****** ****** *)
(* ====================================================================== *)
(*   EMIT SINKS for the SHARED harvest (HATS/xats_lsp_harvest.hats).       *)
(*   The shared walk calls diag_push/hover_push/def_push/token_push; we    *)
(*   bind diag/hover/def to the checker's LSPCHK_* JS accumulators (which  *)
(*   dedup + serialize the §4 JSON bundle), and token_push to a NO-OP —    *)
(*   the checker has no semantic tokens, so it DROPS every token row the   *)
(*   shared walk emits. The JSON bundle stays diagnostics+hovers+defs.     *)
(* ====================================================================== *)
//
fun
diag_push
( l0: int, c0: int, l1: int, c1: int
, code: string, message: string): void =
  LSPCHK_diag_push(l0, c0, l1, c1, code, message)
//
fun
hover_push
( l0: int, c0: int, l1: int, c1: int
, typ: string, kind: string): void =
  LSPCHK_hover_push(l0, c0, l1, c1, typ, kind)
//
fun
def_push
( ul0: int, uc0: int, ul1: int, uc1: int
, defpath: string
, dl0: int, dc0: int, dl1: int, dc1: int
, entity: string
, hastdef: int
, tdpath: string
, tl0: int, tc0: int, tl1: int, tc1: int): void =
  LSPCHK_def_push
  ( ul0, uc0, ul1, uc1, defpath
  , dl0, dc0, dl1, dc1, entity, hastdef, tdpath
  , tl0, tc0, tl1, tc1 )
//
// WS-5: document symbols + inlay hints -> the checker's LSPCHK_* accumulators.
fun
symbol_push
( l0: int, c0: int, l1: int, c1: int
, name: string, kind: int, container: string): void =
  LSPCHK_symbol_push(l0, c0, l1, c1, name, kind, container)
//
fun
inlay_push
(line: int, col: int, label: string, kind: int): void =
  LSPCHK_inlay_push(line, col, label, kind)
//
fun
member_push
( l0: int, c0: int, l1: int, c1: int
, name: string, typ: string): void =
  LSPCHK_member_push(l0, c0, l1, c1, name, typ)
//
// NO-OP token sink: the checker emits no semantic tokens (its bundle is
// diagnostics+hovers+defs only). The shared walk still calls token_push at
// every identifier node; we drop the row here so the contract is unchanged.
fun
token_push
( l0: int, c0: int, l1: int, c1: int
, ttype: int, tmods: int, defpath: string): void = ()
//
// NO-OP scope sink: scope-aware locals (WS-6 Stage 2) are a completion-only
// feature; the CLI checker drops them.
fun
scope_push
( l0: int, c0: int, l1: int, c1: int
, name: string, typ: string): void = ()
//
(* ****** ****** *)
//
// the SHARED harvest: source-filter (loc_fpath/lcsrc_fpath/loc_in_topfile/
// the_top_path), classifiers, hover/def/token emission, the d2/d3 walk, and
// harvest_d3parsed (set top-path; walk; reset). Single source of truth — the
// include-leak source filter now lives here, shared with the resident server.
//
#include "./../HATS/xats_lsp_harvest.hats"
//
(* ****** ****** *)
(* ****** ****** *)
//
// ----------------------- driver: run + emit ---------------------------
//
fun
run_check
(fpth: strn, uri: strn, jsonout: strn): void = let
//
val dpar =
  if (fpath_satsq(fpth))
  then d3parsed_of_filsats(fpth)
  else d3parsed_of_fildats(fpth)
//
val nerror = d3parsed_get_nerror(dpar)
//
// ALWAYS harvest via the SHARED harvest_d3parsed: it sets the top-file SOURCE
// FILTER from d3parsed_get_source (so #include'd/#staload'd nodes no longer leak
// phantom hovers/defs attributed to this uri — the include-leak fix), runs the
// one walk (diagnostics from errck nodes, hovers for every typed d3exp/d3pat,
// definitions for D3Evar/Ecst/Econ use sites; token rows are dropped by the
// no-op token sink above), then resets the filter. Even error-free files need
// the hover/def indices (LSP #2/#3).
val () = harvest_d3parsed(dpar)
//
in
  LSPCHK_json_finish(uri, nerror, jsonout)
end
//
(* ****** ****** *)
//
// argv parsing: positional source, then --uri <u>, --json-out <p>.
// argv[2] is the first user arg (node app.js argv[2] ...).
//
fun
find_flag
(flag: strn): strn = let
  val n = LSPCHK_argv_count()
  fun loop(i: sint): strn =
    if (i+1 < n)
    then ( if strn_eq(LSPCHK_argv_get(i), flag)
           then LSPCHK_argv_get(i+1)
           else loop(i+1) )
    else ""
in
  loop(2)
end
//
(* ****** ****** *)
//
fun
mymain_work
(fpth: strn): void = let
  val uri0 = find_flag("--uri")
  val uri = if strn_nilq(uri0) then strn_append("file://", fpth) else uri0
  val jout0 = find_flag("--json-out")
  val jout = if strn_nilq(jout0) then "lsp-check.json" else jout0
in
  run_check(fpth, uri, jout)
end
//
(* ****** ****** *)
//
// flag-loading + argv plumbing copied from the stock tcheck driver.
//
#typedef cargv = jsa1sz(strn)
//
fun
cargv$loop
(argv: cargv): void = (loop(3)) where {
  val n0 = length(argv)
  fun loop(i0: sint): void =
    if (i0 < n0) then (loop(i0+1)) where {
      val () = xatsopt_flag$pvsadd0(argv[i0])
    }
}
//
fun
mymain_main(): void = let
//
val argv = XATSOPT_argv$get()
val alen = length(argv)
//
in
//
if (alen >= 3) then let
  val ret1 = the_fxtyenv_pvsl00d()
  val ret2 = the_tr12env_pvsl00d()
  val () = xatsopt_flag$pvsadd0("--_XATSOPT_")
  val () = xatsopt_flag$pvsadd0("--_SRCGEN2_XATSOPT_")
in
  cargv$loop(argv); mymain_work(argv[2])
end
else
  prerrsln("ERROR: usage: <src.dats|sats> --uri <uri> --json-out <path>")
//
end
//
(* ****** ****** *)
val ((*entry*)) = mymain_main()
(* ****** ****** *)
//
(***********************************************************************)
(* end of [language-server/server/DATS/xats_lsp_check.dats] *)
(***********************************************************************)
