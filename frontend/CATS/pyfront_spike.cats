////////////////////////////////////////////////////////////////////////.
//                                                                    //.
//   M2.5 STEP-0 flow-spike: JS glue (.cats)                          //.
//   companion for frontend/DATS/pyfront_spike.dats                   //.
//                                                                    //.
////////////////////////////////////////////////////////////////////////.
//
//   PYS_log*       -> process.stderr (progress; never pollutes the emitted JS)
//   PYS_mark       -> process.stdout (the //==PYS-JS-{BEGIN,END}== sentinels that
//                     bracket the emitted flow-spike JS so the build script can
//                     extract exactly the emitted text)
//   PYS_argv_path  -> process.argv[2] (the flow_spike.dats path to compile)
//
////////////////////////////////////////////////////////////////////////.
//
function PYS_log(s)          { process.stderr.write(String(s) + "\n"); }
function PYS_log_int(s, n)   { process.stderr.write(String(s) + " " + String(n) + "\n"); }
function PYS_mark(s)         { process.stdout.write(String(s) + "\n"); }
function PYS_argv_path()     { return (process.argv && process.argv.length > 2) ? String(process.argv[2]) : ""; }
//
// The flow_spike program's own print FFI (PYRT_pstr/PYRT_pint). The spike's
// emitted JS calls these; defining them here makes the emitted program runnable
// with ONLY the bare runtime (no dependence on the prelude `prints` channel).
//
function PYRT_pstr(s)        { process.stdout.write(String(s)); }
function PYRT_pint(n)        { process.stdout.write(String(n)); }
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_spike.cats]
////////////////////////////////////////////////////////////////////////.
