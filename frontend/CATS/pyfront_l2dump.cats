////////////////////////////////////////////////////////////////////////.
//   L2DUMP — Pythonic-ATS round-trip fidelity harness: driver JS glue (.cats)
//   companion for frontend/DATS/pyfront_l2dump.dats
//
//   PYL2_log       -> process.stderr  (progress; never pollutes the stdout dump)
//   PYL2_readfile  -> read a source file (pyfront mode reads the .pdats/.psats text)
//   PYL2_argv_mode -> process.argv[2]  ("stock" | "pyfront")
//   PYL2_argv_path -> process.argv[3]  (the input file)
//   PYL2_argv_stadyn -> process.argv[4] (0 = static .sats/.psats, 1 = dynamic .dats/.pdats)
////////////////////////////////////////////////////////////////////////.
//
function PYL2_log(s) { process.stderr.write(String(s)); }
//
function PYL2_readfile(path) {
  try { return require("fs").readFileSync(String(path), "utf8"); }
  catch (e) { return ""; }
}
function PYL2_argv_mode() {
  return (process.argv && process.argv.length > 2) ? String(process.argv[2]) : "";
}
function PYL2_argv_path() {
  return (process.argv && process.argv.length > 3) ? String(process.argv[3]) : "";
}
function PYL2_argv_stadyn() {
  var a = process.argv[4];
  if (a === undefined || a === null) return 0;
  var n = parseInt(String(a), 10);
  return (n === 1) ? 1 : 0;
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_l2dump.cats]
////////////////////////////////////////////////////////////////////////.
