////////////////////////////////////////////////////////////////////////.
//   STAGE-0 SCOPING SURFACE SPIKE — JS glue (.cats)
//   companion for frontend/DATS/pyfront_scope_spike.dats
//
//   PYB_log*  -> process.stderr  (progress + per-probe nerror; stdout stays clean)
//   PYB_probe -> probe selector from PROBE env (S1=1, S2=2 ; 0 = run all).
////////////////////////////////////////////////////////////////////////.
//
function PYB_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYB_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
function PYB_probe() {
  var p = (process.env.PROBE || "ALL");
  if (p === "S1") return 1;
  if (p === "S2") return 2;
  return 0;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_scope_spike.cats]
////////////////////////////////////////////////////////////////////////.
