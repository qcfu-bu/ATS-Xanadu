////////////////////////////////////////////////////////////////////////.
//   M3 — Python-surface frontend: pipeline-driver JS glue (.cats)
//   companion for frontend/DATS/pyfront_m3.dats
//
//   PYM_log*    -> process.stderr  (progress + the f3perr0 banner; never pollutes JS)
//   PYM_mark    -> process.stdout  (the sentinel lines delimiting the emitted JS)
//   PYM_readfile / PYM_argv_path : file + argv access (same idiom as M1 pylexing.cats)
////////////////////////////////////////////////////////////////////////.
//
function PYM_log(s)        { process.stderr.write(String(s) + "\n"); }
function PYM_log_int(s, n) { process.stderr.write(String(s) + " " + String(n) + "\n"); }
function PYM_mark(s)       { process.stdout.write(String(s) + "\n"); }
//
function PYM_readfile(path) {
  try { return require("fs").readFileSync(String(path), "utf8"); }
  catch (e) { return ""; }
}
function PYM_argv_path() {
  return (process.argv && process.argv.length > 2) ? String(process.argv[2]) : "";
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_m3.cats]
////////////////////////////////////////////////////////////////////////.
