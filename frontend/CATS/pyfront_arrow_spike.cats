////////////////////////////////////////////////////////////////////////.
//   ARROW-EFFECTS STAGE-0 SPIKE — JS glue (.cats)
//   companion for frontend/DATS/pyfront_arrow_spike.dats
//
//   PYB_log*  -> process.stderr  (progress + per-probe nerror; stdout stays clean)
//   PYB_probe -> probe selector from PROBE env
//     (AR-CLOREF=1, AR-CLOREFC=2, AR-CLO0=3, AR-CLO1=4, AR-DIST=5 ; 0 = run all).
////////////////////////////////////////////////////////////////////////.
//
function PYB_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYB_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
function PYB_probe() {
  var p = (process.env.PROBE || "ALL");
  if (p === "AR-CLOREF")  return 1;
  if (p === "AR-CLOREFC") return 2;
  if (p === "AR-CLO0")    return 3;
  if (p === "AR-CLO1")    return 4;
  if (p === "AR-DIST")    return 5;
  return 0;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_arrow_spike.cats]
////////////////////////////////////////////////////////////////////////.
