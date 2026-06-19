(* ********************************************************************** *)
(*
   STATUS: ✅ FIXED upstream (githwxi/ATS-Xanadu b362d545f + 813611246,
   2026-06-19) — now type-checks gracefully (exit 0, 2 recoverable
   diagnostics; no abort). Kept as a REGRESSION artifact. See
   ../COMPILER-BUG-unify00-underapplied.md#resolution.

   MINIMAL REPRO — `unify00_s2typ` aborts with XATS000_cfail on an
   UNDER-APPLIED type constructor used as a called function's result type.

   `list0` is the arity-1 boxed list constructor (it needs one type
   argument, e.g. `list0(strn)`). Here it is written UNAPPLIED as the
   result type of `g`, and then `g()` is called — so the front-end tries
   to type-pack (`trans23_d2exp_tpck`) the application's result and unify
   it, reaching a case `unify00_s2typ` does not handle.

   EXPECTED: an ordinary type error ("type constructor applied to too few
             arguments" / under-application), exit 1, no abort.
   ACTUAL  : XATS000_cfail thrown from `unify00_s2typ`, aborting the whole
             file (no diagnostics recoverable).

   RUN (stock, current-generation compiler — no LSP involved):
     XATSHOME=<repo> node --stack-size=8801 \
       xassets/JS/xatsopt/xatsopt_tcheck01_ats3_opt1.js \
       language-server/docs/repro/unify00-cfail-underapplied.dats

   A/B:
     xatsopt_tcheck01_ats2_opt1.js  (old ATS2-built)  -> exit 1, graceful error
     xatsopt_tcheck01_ats3_opt1.js  (current-gen)     -> XATS000_cfail (abort)

   See ../COMPILER-BUG-unify00-underapplied.md for the full analysis.
*)
(* ********************************************************************** *)

#extern fun g((*void*)): list0 = $extnam()  // list0 is UNDER-APPLIED (needs 1 arg)
val x = g()                                  // calling it forces the unify

(* ********************************************************************** *)
(* end of [unify00-cfail-underapplied.dats] *)
(* ********************************************************************** *)
