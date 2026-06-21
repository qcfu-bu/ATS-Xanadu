////////////////////////////////////////////////////////////////////////.
//   M6a — Python-surface frontend: TYPECHECK-ONLY LSP glue (.cats)
//   companion for frontend/DATS/pyfront_lsp.dats
//
//   PYLSP_readfile : synchronous file read (the didOpen/didSave path has only the
//   URI/path, not the buffer text). Returns "" on any error (a missing/unreadable
//   file then lexes to an empty module — no crash). Same idiom as M1's PYL_readfile
//   / M3's PYM_readfile, kept separate so the LSP link does not pull M3's stdout
//   sentinels or argv glue.
////////////////////////////////////////////////////////////////////////.
//
function PYLSP_readfile(path) {
  try { return require("fs").readFileSync(String(path), "utf8"); }
  catch (e) { return ""; }
}
//
////////////////////////////////////////////////////////////////////////.
// end of [frontend/CATS/pyfront_lsp.cats]
////////////////////////////////////////////////////////////////////////.
