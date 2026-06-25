////////////////////////////////////////////////////////////////////////.
//   M5b.4/.5 sexpdef + S2Etrcd GATING SPIKE — JS glue (.cats)
//   companion for frontend/DATS/pyfront_m5b45_spike.dats
//
//   PYB_log*  -> process.stderr  (progress + per-probe nerror; stdout stays clean)
////////////////////////////////////////////////////////////////////////.
//
function PYB_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYB_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
// probe selector from the environment (PROBE=A|B|Bp|C|C2). Each probe runs in its
// OWN node process so a hard XATS000_cfail crash in one is ISOLATED, not masking
// the others. Returns a small int code: A=1 B=2 Bp=3 C2=4 C=5 (0 = run all).
function PYB_probe() {
  var p = (process.env.PROBE || "ALL");
  if (p === "A")  return 1;
  if (p === "B")  return 2;
  if (p === "Bp") return 3;
  if (p === "C2") return 4;
  if (p === "C")  return 5;
  if (p === "C3") return 6;
  if (p === "C4") return 7;
  return 0;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_m5b45_spike.cats]
////////////////////////////////////////////////////////////////////////.
