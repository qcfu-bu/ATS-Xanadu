(* ****** ****** *)
(*
Mutable ref cell — FFI floor (portable ATS3), included not staloaded.

A single irreducible primitive: a 0-dimensional mutable cell (a 1-vector at
runtime).  The prelude's `a0rf` get/set go through a proof-carrying `owed`
pattern that cz0emit cannot lower (it binds the value but drops the proof var),
so the LSP server carries its own 3-op cell.  Each op is a universally-
quantified leaf extern (`{a:t0}` = one type-erased name) mapped in the backend
glue (Chez: `(vector x)` / `(vector-ref c 0)` / `(vector-set! c 0 x)`).

This is a `.hats` (textually #included, NOT #staloaded) on purpose: an extern
declared in scope at the call site emits by its PLAIN name (`cell_make`), so the
backend defines exactly three stable functions — whereas a cross-module
#staload would mangle them with a per-file stamp.  The abstype is a static
declaration (emits nothing), so #including it in several modules is safe; keep
`lspcell` values module-internal (expose domain ops like depset_add, never a raw
cell) so the abstract type's identity never has to cross a module boundary.
*)
(* ****** ****** *)
//
#abstbox lspcell_tx(a:vt)
#typedef lspcell(a:vt) = lspcell_tx(a)
//
#extern fun cell_make {a:t0}(x: a): lspcell(a) = $extnam()
#extern fun cell_get  {a:t0}(c: lspcell(a)): a  = $extnam()
#extern fun cell_set  {a:t0}(c: lspcell(a), x: a): void = $extnam()
//
(* ****** ****** *)
(*
end of [language-server/server/resident/HATS/xats_lsp_ref.hats]
*)
