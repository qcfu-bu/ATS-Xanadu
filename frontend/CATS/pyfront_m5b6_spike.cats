////////////////////////////////////////////////////////////////////////.
//   M5b.6 linear/flat MODE GATING SPIKE — JS glue (.cats)
//   companion for frontend/DATS/pyfront_m5b6_spike.dats
//
//   PYB_log*  -> process.stderr  (progress + per-probe nerror; stdout stays clean)
////////////////////////////////////////////////////////////////////////.
//
function PYB_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYB_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
// probe selector from the environment (PROBE=L1|L2|L3|L4|L5). Each probe runs in
// its OWN node process so a hard XATS000_cfail / linearity-error in one is ISOLATED,
// not masking the others. Returns a small int code: L1=1 L2=2 L3=3 L4=4 L5=5
// (0 = run all in one process).
function PYB_probe() {
  var p = (process.env.PROBE || "ALL");
  if (p === "L1") return 1;
  if (p === "L2") return 2;
  if (p === "L3") return 3;
  if (p === "L4") return 4;
  if (p === "L5") return 5;
  return 0;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_m5b6_spike.cats]
////////////////////////////////////////////////////////////////////////.
