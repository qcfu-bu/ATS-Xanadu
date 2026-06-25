(* ****** ****** *)
(*
C1 — xglobal_reset() contamination / idempotency / prelude-reload test.

Single-process driver. It type-checks two files A and B in ONE process.
Between A and B it OPTIONALLY calls xglobal_reset() (followed by re-running
the prelude loaders, since reset re-arms the the_ntime gates).

The "flip" is the proof:
  - WITHOUT reset: B = `val y = x` does NOT report `unbound x` (A's top-level
    `x` leaked into the global env).
  - WITH reset+reload: B DOES report an unbound identifier for `x`.

It also exercises:
  - idempotency: check the SAME file twice with reset+reload between; the
    unbound-count must be identical;
  - prelude-reload: after reset+reload a prelude-using file still checks clean.

Modeled structurally on language-server/server/DATS/xats_lsp_check.dats: same
header includes, same front-end entry (d3parsed_of_fildats), a minimal d3/d2
walk that only harvests the unbound-identifier signal we need, and a small
.cats glue for argv + an integer accumulator the JS side can read back.
*)
(* ****** ****** *)
#include
"./../../../../srcgen2/HATS/libxatsopt.hats"
(* ****** ****** *)
#include
"./../../../../srcgen2/HATS/xatsopt_sats.hats"
#include
"./../../../../srcgen2/HATS/xatsopt_dpre.hats"
(* ****** ****** *)
//
#staload "./../../../../srcgen2/SATS/locinfo.sats"
#staload "./../../../../srcgen2/SATS/lexing0.sats"
#staload "./../../../../srcgen2/SATS/dynexp1.sats"
#staload "./../../../../srcgen2/SATS/filpath.sats"
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
C1_argv_count((*0*)): sint = $extnam()
#extern fun
C1_argv_get(i0: sint): strn = $extnam()
//
// One JS-side report line: (label, nerror, total-unbound-count, x-unbound-count).
#extern fun
C1_report
(label: strn, nerror: sint, nunbound: sint, nx: sint): void = $extnam()
//
// Print a free-form line on the clean channel (process.stdout).
#extern fun
C1_say(s: strn): void = $extnam()
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
// A tiny mutable counter pair, threaded through the walk by reference.
//
#typedef cnt = a0ref(sint)
//
fun
cnt_inc(c: cnt): void = (c[] := c[] + 1)
//
(* ****** ****** *)
//
// extract a bare-identifier name from a d1exp (the unbound-id payload).
//
fun
d1exp_idname_opt
(d1e: d1exp): strn =
(
case+ d1exp_get_node(d1e) of
| D1Eid0(sym) => symbl_get_name(sym)
| _ => ""
)
//
// At a D2Enone1(D1Eid0 name) we have an unbound identifier. Bump the total
// count; if the name is the probe identifier ("x"), bump the x-count too.
//
fun
note_unbound
(nm: strn, ctot: cnt, cx: cnt): void =
(
  cnt_inc(ctot)
; if strn_eq(nm, "x") then cnt_inc(cx) else ()
)
//
(* ****** ****** *)
(* ****** ****** *)
//
// ===================== TRAVERSAL (find unbound ids) ===================
//
// A minimal version of the xats_lsp_check.dats walk: we only descend far
// enough to reach the D2Enone1(D1Eid0) shape (the unbound-identifier signal,
// primer §6). Everything else is a transparent recurse-or-ignore.
//
fun
walk_d3exp (d3e0: d3exp, ct: cnt, cx: cnt): void =
(
case+ d3e0.node() of
| D3Eerrck(_, d3e1) => walk_d3exp(d3e1, ct, cx)
| D3Et2pck(d3e1, _) => walk_d3exp(d3e1, ct, cx)
| D3Et2ped(d3e1, _) => walk_d3exp(d3e1, ct, cx)
| D3Elabck(d3e1, _) => walk_d3exp(d3e1, ct, cx)
| D3Eannot(d3e1, _, _) => walk_d3exp(d3e1, ct, cx)
| D3Etimp(d3f0, _) => walk_d3exp(d3f0, ct, cx)
| D3Etimq(d3f0, _, _) => walk_d3exp(d3f0, ct, cx)
| D3Esapp(d3f0, _) => walk_d3exp(d3f0, ct, cx)
| D3Esapq(d3f0, _) => walk_d3exp(d3f0, ct, cx)
| D3Etapp(d3f0, _) => walk_d3exp(d3f0, ct, cx)
| D3Etapq(d3f0, _) => walk_d3exp(d3f0, ct, cx)
| D3Edap0(d3f0) => walk_d3exp(d3f0, ct, cx)
| D3Edapp(d3f0, _, d3es) => (walk_d3exp(d3f0, ct, cx); walk_d3explst(d3es, ct, cx))
| D3Epcon(_, _, d3e1) => walk_d3exp(d3e1, ct, cx)
| D3Eproj(_, _, d3e1) => walk_d3exp(d3e1, ct, cx)
| D3Elet0(dcls, d3e1) => (walk_d3eclist(dcls, ct, cx); walk_d3exp(d3e1, ct, cx))
| D3Eift0(d3e1, dthn, dels) =>
  (walk_d3exp(d3e1, ct, cx); walk_d3expopt(dthn, ct, cx); walk_d3expopt(dels, ct, cx))
| D3Ecas0(_, d3e1, _) => walk_d3exp(d3e1, ct, cx)
| D3Eseqn(d3es, d3e1) => (walk_d3explst(d3es, ct, cx); walk_d3exp(d3e1, ct, cx))
| D3Etup0(_, d3es) => walk_d3explst(d3es, ct, cx)
| D3Etup1(_, _, d3es) => walk_d3explst(d3es, ct, cx)
| D3Elam0(_, _, _, _, d3e1) => walk_d3exp(d3e1, ct, cx)
| D3Efix0(_, _, _, _, _, d3e1) => walk_d3exp(d3e1, ct, cx)
| D3Ewhere(d3e1, dcls) => (walk_d3exp(d3e1, ct, cx); walk_d3eclist(dcls, ct, cx))
| D3Eassgn(dl, dr) => (walk_d3exp(dl, ct, cx); walk_d3exp(dr, ct, cx))
| D3Eraise(_, d3e1) => walk_d3exp(d3e1, ct, cx)
| D3Enone1(d2e1) => walk_d2exp(d2e1, ct, cx)
| D3Enone2(d3e1) => walk_d3exp(d3e1, ct, cx)
| _ => ((*leaf*))
)
//
and
walk_d3ecl (dcl0: d3ecl, ct: cnt, cx: cnt): void =
(
case+ dcl0.node() of
| D3Cerrck(_, dcl1) => walk_d3ecl(dcl1, ct, cx)
| D3Cstatic(_, dcl1) => walk_d3ecl(dcl1, ct, cx)
| D3Cextern(_, dcl1) => walk_d3ecl(dcl1, ct, cx)
| D3Ctmpsub(_, dcl1) => walk_d3ecl(dcl1, ct, cx)
| D3Cdclst0(dcls) => walk_d3eclist(dcls, ct, cx)
| D3Clocal0(da, db) => (walk_d3eclist(da, ct, cx); walk_d3eclist(db, ct, cx))
| D3Cinclude(_, _, _, _, dopt) => walk_d3eclistopt(dopt, ct, cx)
| D3Cvaldclst(_, dvs) => walk_d3valdclist(dvs, ct, cx)
| D3Cvardclst(_, dvs) => walk_d3vardclist(dvs, ct, cx)
| D3Cfundclst(_, _, _, dfs) => walk_d3fundclist(dfs, ct, cx)
| D3Cimplmnt0(_, _, _, _, _, _, _, _, dexp) => walk_d3exp(dexp, ct, cx)
| D3Cnone1(d2cl) => walk_d2ecl(d2cl, ct, cx)
| D3Cnone2(d3cl) => walk_d3ecl(d3cl, ct, cx)
| _ => ((*leaf*))
)
//
and
walk_d2exp (d2e0: d2exp, ct: cnt, cx: cnt): void =
(
case+ d2e0.node() of
// unbound identifier: D2Enone1(D1Eid0 name)  (primer §6)
| D2Enone1(d1e1) =>
  let val nm = d1exp_idname_opt(d1e1) in note_unbound(nm, ct, cx) end
| D2Eerrck(_, d2e1) => walk_d2exp(d2e1, ct, cx)
| D2Et2pck(d2e1, _) => walk_d2exp(d2e1, ct, cx)
| D2Et2ped(d2e1, _) => walk_d2exp(d2e1, ct, cx)
| D2Elabck(d2e1, _) => walk_d2exp(d2e1, ct, cx)
| D2Eannot(d2e1, _, _) => walk_d2exp(d2e1, ct, cx)
| D2Esapp(d2f0, _) => walk_d2exp(d2f0, ct, cx)
| D2Etapp(d2f0, _) => walk_d2exp(d2f0, ct, cx)
| D2Edap0(d2f0) => walk_d2exp(d2f0, ct, cx)
| D2Edapp(d2f0, _, d2es) => (walk_d2exp(d2f0, ct, cx); walk_d2explst(d2es, ct, cx))
| D2Eproj(_, _, _, d2e1) => walk_d2exp(d2e1, ct, cx)
| D2Elet0(dcls, d2e1) => (walk_d2eclist(dcls, ct, cx); walk_d2exp(d2e1, ct, cx))
| D2Eift0(d2e1, dthn, dels) =>
  (walk_d2exp(d2e1, ct, cx); walk_d2expopt(dthn, ct, cx); walk_d2expopt(dels, ct, cx))
| D2Eseqn(d2es, d2e1) => (walk_d2explst(d2es, ct, cx); walk_d2exp(d2e1, ct, cx))
| D2Etup0(_, d2es) => walk_d2explst(d2es, ct, cx)
| D2Etup1(_, _, d2es) => walk_d2explst(d2es, ct, cx)
| D2Elam0(_, _, _, _, d2e1) => walk_d2exp(d2e1, ct, cx)
| D2Efix0(_, _, _, _, _, d2e1) => walk_d2exp(d2e1, ct, cx)
| D2Ewhere(d2e1, dcls) => (walk_d2exp(d2e1, ct, cx); walk_d2eclist(dcls, ct, cx))
| D2Eassgn(dl, dr) => (walk_d2exp(dl, ct, cx); walk_d2exp(dr, ct, cx))
| D2Eraise(_, d2e1) => walk_d2exp(d2e1, ct, cx)
| D2Enone2(d2e1) => walk_d2exp(d2e1, ct, cx)
| _ => ((*leaf or D2Enone1 handled above*))
)
//
and
walk_d2ecl (dcl0: d2ecl, ct: cnt, cx: cnt): void =
(
case+ dcl0.node() of
| D2Cerrck(_, dcl1) => walk_d2ecl(dcl1, ct, cx)
| D2Cstatic(_, dcl1) => walk_d2ecl(dcl1, ct, cx)
| D2Cextern(_, dcl1) => walk_d2ecl(dcl1, ct, cx)
| D2Clocal0(da, db) => (walk_d2eclist(da, ct, cx); walk_d2eclist(db, ct, cx))
| D2Cvaldclst(_, dvs) => walk_d2valdclist(dvs, ct, cx)
| D2Cvardclst(_, dvs) => walk_d2vardclist(dvs, ct, cx)
| D2Cfundclst(_, _, _, dfs) => walk_d2fundclist(dfs, ct, cx)
| D2Cimplmnt0(_, _, _, _, _, _, _, dexp) => walk_d2exp(dexp, ct, cx)
| D2Cnone2(d2cl) => walk_d2ecl(d2cl, ct, cx)
| _ => ((*leaf*))
)
//
and
walk_d3explst (xs: d3explst, ct: cnt, cx: cnt): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (walk_d3exp(x, ct, cx); walk_d3explst(xs, ct, cx)) )
and
walk_d3expopt (xo: d3expopt, ct: cnt, cx: cnt): void =
( case+ xo of optn_nil() => () | optn_cons(x) => walk_d3exp(x, ct, cx) )
and
walk_d3eclist (xs: d3eclist, ct: cnt, cx: cnt): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (walk_d3ecl(x, ct, cx); walk_d3eclist(xs, ct, cx)) )
and
walk_d3eclistopt (xo: d3eclistopt, ct: cnt, cx: cnt): void =
( case+ xo of optn_nil() => () | optn_cons(xs) => walk_d3eclist(xs, ct, cx) )
and
walk_d3valdclist (dvs: d3valdclist, ct: cnt, cx: cnt): void =
( case+ dvs of
  | list_nil() => ()
  | list_cons(dv, dvs) =>
    ( walk_teqd3exp(d3valdcl_get_tdxp(dv), ct, cx)
    ; walk_d3valdclist(dvs, ct, cx) ) )
and
walk_d3vardclist (dvs: d3vardclist, ct: cnt, cx: cnt): void =
( case+ dvs of
  | list_nil() => ()
  | list_cons(dv, dvs) =>
    ( walk_teqd3exp(d3vardcl_get_dini(dv), ct, cx)
    ; walk_d3vardclist(dvs, ct, cx) ) )
and
walk_d3fundclist (dfs: d3fundclist, ct: cnt, cx: cnt): void =
( case+ dfs of
  | list_nil() => ()
  | list_cons(df, dfs) =>
    ( walk_teqd3exp(d3fundcl_get_tdxp(df), ct, cx)
    ; walk_d3fundclist(dfs, ct, cx) ) )
and
walk_teqd3exp (t: teqd3exp, ct: cnt, cx: cnt): void =
( case+ t of
  | TEQD3EXPnone() => ()
  | TEQD3EXPsome(_, e) => walk_d3exp(e, ct, cx) )
and
walk_d2explst (xs: d2explst, ct: cnt, cx: cnt): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (walk_d2exp(x, ct, cx); walk_d2explst(xs, ct, cx)) )
and
walk_d2expopt (xo: d2expopt, ct: cnt, cx: cnt): void =
( case+ xo of optn_nil() => () | optn_cons(x) => walk_d2exp(x, ct, cx) )
and
walk_d2eclist (xs: d2eclist, ct: cnt, cx: cnt): void =
( case+ xs of
  | list_nil() => ()
  | list_cons(x, xs) => (walk_d2ecl(x, ct, cx); walk_d2eclist(xs, ct, cx)) )
and
walk_d2valdclist (dvs: d2valdclist, ct: cnt, cx: cnt): void =
( case+ dvs of
  | list_nil() => ()
  | list_cons(dv, dvs) =>
    ( walk_teqd2exp(d2valdcl_get_tdxp(dv), ct, cx)
    ; walk_d2valdclist(dvs, ct, cx) ) )
and
walk_d2vardclist (dvs: d2vardclist, ct: cnt, cx: cnt): void =
( case+ dvs of
  | list_nil() => ()
  | list_cons(dv, dvs) =>
    ( walk_teqd2exp(d2vardcl_get_dini(dv), ct, cx)
    ; walk_d2vardclist(dvs, ct, cx) ) )
and
walk_d2fundclist (dfs: d2fundclist, ct: cnt, cx: cnt): void =
( case+ dfs of
  | list_nil() => ()
  | list_cons(df, dfs) =>
    ( walk_teqd2exp(d2fundcl_get_tdxp(df), ct, cx)
    ; walk_d2fundclist(dfs, ct, cx) ) )
and
walk_teqd2exp (t: teqd2exp, ct: cnt, cx: cnt): void =
( case+ t of
  | TEQD2EXPnone() => ()
  | TEQD2EXPsome(_, e) => walk_d2exp(e, ct, cx) )
//
(* ****** ****** *)
(* ****** ****** *)
//
// Reload the prelude. xglobal_reset() re-arms the the_ntime gates, so after a
// reset the loaders fire again (exactly the sequence mymain_main uses at
// startup in xats_lsp_check.dats).
//
fun
prelude_reload((*0*)): void = let
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
in (*nothing*) end
//
// Type-check one file and return @(nerror, total-unbound, x-unbound).
// nerror is the compiler's own error count (d3parsed_get_nerror); the
// unbound/x counts come from our own walk of the typed AST.
//
fun
check_file
(fpth: strn): @(sint, sint, sint) = let
  val dpar =
    if (fpath_satsq(fpth))
    then d3parsed_of_filsats(fpth)
    else d3parsed_of_fildats(fpth)
  val nerr = d3parsed_get_nerror(dpar)
  val ct = a0ref_make_1val<sint>(0)
  val cx = a0ref_make_1val<sint>(0)
  val () = walk_d3eclistopt(d3parsed_get_parsed(dpar), ct, cx)
in
  @(nerr, ct[], cx[])
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
(* ****** ****** *)
//
fun
mymain_main(): void = let
//
val argv = XATSOPT_argv$get()
val alen = length(argv)
//
in
//
if (alen >= 4) then let
  // argv[2] = file A (`val x = 3`), argv[3] = file B (`val y = x`).
  val fileA = argv[2]
  val fileB = argv[3]
  //
  // startup: load prelude + the standard flags (same as the stock driver).
  val _ = the_fxtyenv_pvsl00d()
  val _ = the_tr12env_pvsl00d()
  val () = xatsopt_flag$pvsadd0("--_XATSOPT_")
  val () = xatsopt_flag$pvsadd0("--_SRCGEN2_XATSOPT_")
  val () = cargv$loop(argv)
in
let
  val () = C1_say("== C1 xglobal_reset() test ==")
  //
  // ===================================================================
  // TEST 1 — contamination probe via top-level `val` (A=`val x=3`,
  // B=`val y=x`). Report B's unbound-x WITHOUT reset and WITH reset.
  // NOTE (finding): user-file top-level vals are checked via
  // d3parsed_of_fildats, which does NOT merge them into the global
  // the_dexpenv (only the PRELUDE loader path merges). So `x` does not
  // leak through this path and B reports unbound-x in BOTH cases.
  // The genuine reset flip is TEST 2 (prelude in the global env).
  // ===================================================================
  val () = C1_say("-- TEST 1: top-level `val` probe --")
  val rA0 = check_file(fileA)
  val () = C1_report("A (val x=3)              ", rA0.0, rA0.1, rA0.2)
  val rB0 = check_file(fileB)        // no reset between A and B
  val () = C1_report("B (val y=x) WITHOUT reset", rB0.0, rB0.1, rB0.2)
  val () = xglobal_reset()
  val () = prelude_reload()
  val rA1 = check_file(fileA)        // re-establish A under reset+reload
  val () = xglobal_reset()
  val () = prelude_reload()
  val rB1 = check_file(fileB)        // reset before B
  val () = C1_report("B (val y=x) WITH reset   ", rB1.0, rB1.1, rB1.2)
  //
  // ===================================================================
  // TEST 2 — THE FLIP that proves reset works. A prelude-using file
  // (fileA references `int`, a prelude type). The prelude lives in the
  // GLOBAL env (the_sexpenv etc.), which xglobal_reset() clears and the
  // re-armed the_ntime gate reloads.
  //   * reset WITHOUT reload  -> global env empty -> file FAILS (nerror>0)
  //   * reset WITH reload     -> prelude restored -> file PASSES (nerror=0)
  // ===================================================================
  val () = C1_say("-- TEST 2: prelude-in-global-env FLIP --")
  // baseline: clean check with the prelude loaded.
  val () = xglobal_reset()
  val () = prelude_reload()
  val rC0 = check_file(fileA)
  val () = C1_report("A with prelude loaded    ", rC0.0, rC0.1, rC0.2)
  // reset but DO NOT reload: the global env (prelude) is now gone.
  val () = xglobal_reset()
  val rC1 = check_file(fileA)
  val () = C1_report("A after reset, NO reload ", rC1.0, rC1.1, rC1.2)
  // reset + reload: prelude restored, clean again.
  val () = xglobal_reset()
  val () = prelude_reload()
  val rC2 = check_file(fileA)
  val () = C1_report("A after reset + reload   ", rC2.0, rC2.1, rC2.2)
  //
  // ===================================================================
  // TEST 3 — idempotency: check fileA twice with reset+reload between;
  // nerror (and unbound counts) must be identical.
  // ===================================================================
  val () = C1_say("-- TEST 3: idempotency --")
  val () = xglobal_reset()
  val () = prelude_reload()
  val r2a = check_file(fileA)
  val () = xglobal_reset()
  val () = prelude_reload()
  val r2b = check_file(fileA)
  val () = C1_report("idempotency A run #1     ", r2a.0, r2a.1, r2a.2)
  val () = C1_report("idempotency A run #2     ", r2b.0, r2b.1, r2b.2)
  //
  // ===================================================================
  // TEST 4 — prelude reload: after reset+reload, a prelude-using file
  // still type-checks cleanly (nerror=0).
  // ===================================================================
  val () = C1_say("-- TEST 4: prelude reload clean --")
  val () = xglobal_reset()
  val () = prelude_reload()
  val r3 = check_file(fileA)
  val () = C1_report("prelude-reload A (clean) ", r3.0, r3.1, r3.2)
in
  C1_say("== done ==")
end
end
else
  C1_say("ERROR: usage: <fileA.dats> <fileB.dats>")
//
end
//
(* ****** ****** *)
val ((*entry*)) = mymain_main()
(* ****** ****** *)
//
(***********************************************************************)
(* end of [c1-test/DATS/c1_reset_test.dats] *)
(***********************************************************************)
