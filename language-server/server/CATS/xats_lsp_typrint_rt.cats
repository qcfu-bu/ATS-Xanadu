////////////////////////////////////////////////////////////////////////.
// xats_lsp_typrint_rt.cats — JS glue for the round-trip harness driver.
////////////////////////////////////////////////////////////////////////.
//
const RT_fs = require('node:fs');
//
function RT_argv_get(i0)        { return process.argv[i0]; }
function RT_println(s)          { process.stdout.write(String(s) + "\n"); }
function RT_writefile(path, s)  { RT_fs.writeFileSync(String(path), String(s)); }
// a printed form containing a bare `_` is an erased index (documented-lossy).
function strn_has_underscore(s) {
  return /(^|[^A-Za-z0-9_])_([^A-Za-z0-9_]|$)/.test(String(s));
}
//
// string-buffer FILR (capture s2typ_fprint debug output as a JS string).
function LSP_strbuf_new()       { return { buf: "", write: function (s) { this.buf += s; } }; }
function LSP_strbuf_get(fb)     { return fb.buf; }
//
// int label / xtv stamp -> string (faithful printer helpers).
function TYPRINT_int2str(n)     { return String(n|0); }
function TYPRINT_stamp2str(s)   { return String(s); }
//
////////////////////////////////////////////////////////////////////////.
// end of [xats_lsp_typrint_rt.cats]
////////////////////////////////////////////////////////////////////////.
