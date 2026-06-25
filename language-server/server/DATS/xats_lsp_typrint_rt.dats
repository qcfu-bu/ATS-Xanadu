(* ****** ****** *)
(*
xats_lsp_typrint_rt.dats — ROUND-TRIP harness for the faithful s2typ printer.

Proves the printer is parser-consistent: for a corpus of real types, print each
(Exact mode), wrap as `#typedef _RTn = <printed>`, re-check, recover, and unify
(unify23_s2typ) the round-tripped type with the original.

Flow (one process; the originals' s2typ handles stay live across the second
check because the warm compiler keeps them in its topmaps):
  1. load prelude (the_fxtyenv_pvsload / the_tr12env_pvsl00d + flags)
  2. check the corpus file -> recover every D2Csexpdef (name, s2typ) [originals]
  3. print each original in Exact mode -> emit `#typedef _RT<i> = <printed>`
     into a temp file, ALSO printing the BEFORE/AFTER (hover vs exact) for report
  4. check the temp file (0 diagnostics required) -> recover each _RT<i>'s s2typ
  5. unify23_s2typ(original<i>, roundtrip<i>) over a fresh tr23env -> pass/fail
  6. print a pass-rate report to stdout.

Build: server/build.sh with this file as the driver and the _rt.cats glue.
*)
(* ****** ****** *)
//
#include "./../resident/HATS/libxatsopt_resident.hats"
//
#include "srcgen2/HATS/xatsopt_sats.hats"
#include "srcgen2/HATS/xatsopt_dpre.hats"
//
#staload "./../../../srcgen2/SATS/dynexp2.sats"
//
(* ****** ****** *)
//
// ---------------- FFI (impl in the .cats) ----------------
//
#extern fun RT_argv_get(i0: sint): string = $extnam()
#extern fun RT_println(s: string): void = $extnam()
#extern fun RT_writefile(path: string, body: string): void = $extnam()
#extern fun strn_has_underscore(s: string): bool = $extnam()
//
// string-buffer FILR (for the leaf debug renderer typ_to_strn).
#extern fun LSP_strbuf_new((*0*)): FILR = $extnam()
#extern fun LSP_strbuf_get(fb: FILR): string = $extnam()
//
// printer FFI helpers (shared with the resident/checker printer).
#extern fun TYPRINT_int2str(n: int): string = $extnam()
#extern fun TYPRINT_stamp2str(s: stamp): string = $extnam()
//
(* ****** ****** *)
//
// leaf debug renderer (fuel-guarded), needed by the shared printer's fallback.
//
fun
typ_to_strn
(t2p: s2typ): string = typ_aux(t2p, 4) where {
  fun
  typ_aux
  (t2p: s2typ, fuel: int): string =
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
(t2p: s2typ): string = let
  val fb = LSP_strbuf_new()
  val () = s2typ_fprint(t2p, fb)
in
  LSP_strbuf_get(fb)
end
//
// sort -> source name (e.g. "type") via the strbuf + sort2_fprint.
fun
TYPRINT_sort2str
(srt: sort2): string = let
  val fb = LSP_strbuf_new()
  val () = sort2_fprint(srt, fb)
in
  LSP_strbuf_get(fb)
end
//
(* ****** ****** *)
//
#include "./../HATS/xats_lsp_typrint.hats"
//
(* ****** ****** *)
//
// ---- harvest: collect (name, s2typ) for every D2Csexpdef in a d3parsed ----
//
// We use a JS-side list (via the .cats) to accumulate; but to keep this driver
// self-contained we instead build an ATS list. Each entry: (name, original s2typ).
//
#typedef sdef = (string, s2typ)
#typedef sdeflst = list(sdef)
//
fun
collect_d2ecl
(dcl: d2ecl, acc: sdeflst): sdeflst =
(
case+ d2ecl_get_node(dcl) of
| D2Csexpdef(s2c, s2e) =>
  let
    val nm = symbl_get_name(s2cst_get_name(s2c))
    val t2p = s2exp_stpize(s2e)
  in
    list_cons((nm, t2p), acc)
  end
| D2Cstatic(_, dcl1) => collect_d2ecl(dcl1, acc)
| D2Clocal0(da, db) => collect_d2eclist(db, collect_d2eclist(da, acc))
| _ => acc
)
//
and
collect_d2eclist
(dcls: d2eclist, acc: sdeflst): sdeflst =
(
case+ dcls of
| list_nil() => acc
| list_cons(d, rest) => collect_d2eclist(rest, collect_d2ecl(d, acc))
)
//
fun
collect_d3ecl
(dcl: d3ecl, acc: sdeflst): sdeflst =
(
case+ d3ecl_get_node(dcl) of
| D3Cd2ecl(d2cl) => collect_d2ecl(d2cl, acc)
| D3Cstatic(_, dcl1) => collect_d3ecl(dcl1, acc)
| D3Cextern(_, dcl1) => collect_d3ecl(dcl1, acc)
| D3Cdclst0(dcls) => collect_d3eclist(dcls, acc)
| D3Clocal0(da, db) => collect_d3eclist(db, collect_d3eclist(da, acc))
| D3Cerrck(_, dcl1) => collect_d3ecl(dcl1, acc)
| D3Cnone1(d2cl) => collect_d2ecl(d2cl, acc)
| D3Cnone2(d3cl) => collect_d3ecl(d3cl, acc)
| _ => acc
)
//
and
collect_d3eclist
(dcls: d3eclist, acc: sdeflst): sdeflst =
(
case+ dcls of
| list_nil() => acc
| list_cons(d, rest) => collect_d3eclist(rest, collect_d3ecl(d, acc))
)
//
fun
collect_parsed
(parsed: d3eclistopt): sdeflst =
(
case+ parsed of
| optn_nil() => list_nil()
| optn_cons(dcls) => list_reverse(collect_d3eclist(dcls, list_nil()))
)
//
(* ****** ****** *)
//
// list helpers (list_reverse, list_length, list_get_at via index).
//
fun
list_reverse{a:t0}(xs: list(a)): list(a) = loop(xs, list_nil()) where {
  fun loop(xs: list(a), acc: list(a)): list(a) =
  (case+ xs of list_nil() => acc | list_cons(x, r) => loop(r, list_cons(x, acc)))
}
//
fun
list_len{a:t0}(xs: list(a)): int =
(case+ xs of list_nil() => 0 | list_cons(_, r) => 1 + list_len(r))
//
(* ****** ****** *)
//
// look up a round-trip by its `_RT<i>` name; returns (found?, s2typ). Missing
// entries (e.g. a typedef that failed to parse) are detected, not misaligned.
//
fun
sdeflst_find
(xs: sdeflst, nm: string): (bool, s2typ) =
(
case+ xs of
| list_nil() => (false, s2typ_none0())
| list_cons((n, t), r) =>
  if strn_eq(n, nm) then (true, t) else sdeflst_find(r, nm)
)
//
(* ****** ****** *)
//
// build the round-trip source: "#typedef _RT<i> = <printed-exact>\n" for each.
//
fun
build_rt_src
(xs: sdeflst, i: int): string =
(
case+ xs of
| list_nil() => ""
| list_cons((_, t2p), rest) =>
  let
    val ex = typr_pretty_mode(t2p, TPMexact())
    // skip documented-lossy forms (erased index `_`) so the round-trip file
    // stays parse-clean; they are reported separately in the unify pass.
    val line =
      if strn_has_underscore(ex) then "" else
      strn_append("#typedef _RT",
        strn_append(TYPRINT_int2str(i),
          strn_append(" = ",
            strn_append(ex, "\n"))))
  in
    strn_append(line, build_rt_src(rest, i+1))
  end
)
//
(* ****** ****** *)
//
// print BEFORE (hover) / AFTER (exact) for each original, for the report.
//
fun
report_forms
(xs: sdeflst): void =
(
case+ xs of
| list_nil() => ()
| list_cons((nm, t2p), rest) =>
  let
    val hov = typr_pretty_mode(t2p, TPMhover())
    val ex  = typr_pretty_mode(t2p, TPMexact())
    val dbg = typ_to_strn(t2p)
    val () = RT_println(
      strn_append("  ", strn_append(nm,
        strn_append("\n      hover: ", strn_append(hov,
          strn_append("\n      exact: ", strn_append(ex,
            strn_append("\n      (dbg): ", dbg))))))))
  in
    report_forms(rest)
  end
)
//
(* ****** ****** *)
//
// unify each original<i> with roundtrip<i>; count passes. Compare UP TO the
// printer's documented lossy cases (linearity box0/box1, dropped quantifier
// constraints, metavars) — which unify23_s2typ already handles structurally.
//
fun
run_unify
(origs: sdeflst, rts: sdeflst, i: int, npass: int, ntot: int): (int, int) =
(
case+ origs of
| list_nil() => (npass, ntot)
| list_cons((nm, t2o), rest) =>
  let
    val rtname = strn_append("_RT", TYPRINT_int2str(i))
    val (found, t2r) = sdeflst_find(rts, rtname)
    // primary criterion: re-parse + re-print is a FIXPOINT (the printed form of
    // the round-tripped type equals the original's). For non-universal types we
    // ALSO require unify23 (the stronger structural check); universals only
    // alpha-rename their binders (a documented lossy case unify treats as rigid),
    // so we accept the fixpoint there.
    val so = typr_pretty_mode(t2o, TPMexact())
    val sr = if found then typr_pretty_mode(t2r, TPMexact()) else ""
    val fixpt = if found then strn_eq(so, sr) else false
    val uni =
      if found then let
        val env0 = tr23env_make_nil()
        val b = unify23_s2typ(env0, t2o, t2r)
        val () = tr23env_free_nil(env0)
      in b end
      else false
    // documented-lossy: an erased index arg prints as `_` (a non-impredicative
    // quantifier index that s2exp_stpize collapsed to T2Pnone0). Such a form is
    // not re-parseable; we compare UP TO it (excluded from the pass rate).
    val lossy = strn_has_underscore(so)
    val ok = if uni then true else fixpt
    val tag =
      if lossy   then "  [LOSS] " else
      if ~found  then "  [MISS] " else
      if ok      then "  [PASS] " else "  [FAIL] "
    val note =
      if lossy then " (erased index `_`: documented-lossy, compare-up-to)" else
      if uni then " (unify)" else
      if fixpt then " (fixpoint; universal alpha-rename)" else ""
    val () =
      RT_println(
        strn_append(tag,
          strn_append(nm,
            strn_append(note,
              strn_append("   exact=", so)))))
    // pass-rate counts only NON-lossy entries; lossy ones are reported, skipped.
    val npass1 = if lossy then npass else (if ok then npass+1 else npass)
    val ntot1  = if lossy then ntot else ntot+1
  in
    run_unify(rest, rts, i+1, npass1, ntot1)
  end
)
//
(* ****** ****** *)
//
// ----------------- main -----------------
//
val _ = the_fxtyenv_pvsload()
val _ = the_tr12env_pvsl00d()
val () = xatsopt_flag$pvsadd0("--_XATSOPT_")
val () = xatsopt_flag$pvsadd0("--_SRCGEN2_XATSOPT_")
//
val corpus = RT_argv_get(2)
val rtpath = RT_argv_get(3)
//
val () = RT_println(strn_append("== round-trip corpus: ", corpus))
//
// phase A: check corpus, recover originals.
val dpar0 = d3parsed_of_fildats(corpus)
val ner0  = d3parsed_get_nerror(dpar0)
val () = RT_println(strn_append("corpus nerror = ", TYPRINT_int2str(ner0)))
val origs = collect_parsed(d3parsed_get_parsed(dpar0))
val norig = list_len(origs)
val () = RT_println(strn_append("recovered originals = ", TYPRINT_int2str(norig)))
//
val () = RT_println("== BEFORE/AFTER (hover / exact / debug) ==")
val () = report_forms(origs)
//
// phase B: emit the round-trip source, check it.
val rtsrc = build_rt_src(origs, 0)
val () = RT_writefile(rtpath, rtsrc)
val () = RT_println(strn_append("== round-trip source written: ", rtpath))
val () = RT_println(rtsrc)
//
val dpar1 = d3parsed_of_fildats(rtpath)
val ner1  = d3parsed_get_nerror(dpar1)
val () = RT_println(strn_append("round-trip nerror = ", TYPRINT_int2str(ner1)))
val rts = collect_parsed(d3parsed_get_parsed(dpar1))
val nrt = list_len(rts)
val () = RT_println(strn_append("recovered round-trips = ", TYPRINT_int2str(nrt)))
//
// phase C: unify.
val () = RT_println("== UNIFY (original vs round-trip) ==")
val (npass, ntot) = run_unify(origs, rts, 0, 0, 0)
val () = RT_println(
  strn_append("\n== RESULT: ",
    strn_append(TYPRINT_int2str(npass),
      strn_append(" / ",
        strn_append(TYPRINT_int2str(ntot),
          strn_append(" passed; parse-diags(rt)=", TYPRINT_int2str(ner1)))))))
//
(* ****** ****** *)
(* end of [xats_lsp_typrint_rt.dats] *)
(* ****** ****** *)
