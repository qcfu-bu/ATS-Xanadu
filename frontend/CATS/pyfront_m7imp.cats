////////////////////////////////////////////////////////////////////////.
//   M7-import (task #34) — multi-file `import` driver JS glue (.cats)
//   companion for frontend/DATS/pyfront_m7imp.dats
//
//   PYI_log*    -> process.stderr  (progress + the f3perr0 diagnostics; never pollutes stdout)
//   PYI_readfile / PYI_argv : file + indexed-argv access (two input files in one process)
////////////////////////////////////////////////////////////////////////.
//
function PYI_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYI_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
//
function PYI_readfile(path) {
  try { return require("fs").readFileSync(String(path), "utf8"); }
  catch (e) { return ""; }
}
function PYI_argv(i) {
  var n = (i | 0);
  return (process.argv && process.argv.length > n) ? String(process.argv[n]) : "";
}
function PYI_dump() { return (process.env && process.env.PYI_DUMP) ? 1 : 0; }
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_m7imp.cats]
////////////////////////////////////////////////////////////////////////.
