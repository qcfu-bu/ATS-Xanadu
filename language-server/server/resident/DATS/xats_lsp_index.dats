(* ****** ****** *)
(*
Per-uri LSP index — IMPLEMENTATION (portable ATS3).

Pure jval + list + sint work behind cells (xats_lsp_ref.hats): five per-check
accumulators (diags/hovers/defs/tokens/inlays), the uri -> snapshot map, the
diag/hover/def/inlay dedups + the semantic-token delta-encoder, and the request
builders.  Mirrors the Scheme glue's LSP_cur_* / LSP_index / LSP_dedup_* /
LSP_encode_tokens / LSP_build_* byte-for-byte.  Interface: SATS/xats_lsp_index.sats.

The six byte->UTF-16 / path->uri / friendly / prelude-classification primitives are
STATEFUL glue leaves (per-check current-document + other-file converters, cur-uri
remap) — they belong to the validate lifecycle (still glue; Step 6), so they remain
external here.  Everything else is backend-agnostic ATS3.
*)
(* ****** ****** *)
//
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
//
#staload "./../SATS/xats_lsp_json.sats"
#staload "./../SATS/xats_lsp_index.sats"
// Stage 6b: the per-check conversion layer (friendly / def_in_current / path2uri)
// is now ATS — call it ATS->ATS instead of via the old glue leaves.
#staload "./../SATS/xats_lsp_conv.sats"
//
#include "./../HATS/xats_lsp_ref.hats"
//
(* ****** ****** *)
//
// leaf primitives.  int2str: sint -> decimal text (shared with the other modules).
// The six conversion leaves are STATEFUL glue functions (named exactly, since
// cz0emit emits the ATS name and ignores $extnam):
//   LSP_cur_b2u   (line, byteCol)        -> UTF-16 col in the CURRENT document
//   LSP_other_b2u (path, line, byteCol)  -> UTF-16 col in another (def-target) file
//   LSP_path2uri  (path)                 -> file:// uri (cur-doc remap applied)
//   LSP_friendly  (message)              -> diagnostic message w/ friendly typenames
//   LSP_def_in_current (uri)             -> is this def-uri the current document?
//   JS_path_is_prelude (path)            -> is this path under the loaded prelude?
//
#extern fun int2str(n: sint): string = $extnam()
#extern fun str_len(s: string): sint = $extnam()
#extern fun str_char_code(s: string, i: sint): sint = $extnam()
#extern fun str_of_code(c: sint): string = $extnam()
#extern fun LSP_cur_b2u(line: int, col: int): int = $extnam()
#extern fun LSP_other_b2u(path: string, line: int, col: int): int = $extnam()
// LSP_path2uri / LSP_friendly / LSP_def_in_current now come from xats_lsp_conv
// (#staload'd above) — ATS->ATS, no longer glue leaves.
#extern fun JS_path_is_prelude(path: string): bool = $extnam()
//
(* ****** ****** *)
//
// a per-uri snapshot: dedup'd hovers, defs, encoded semantic ints, inlays, then
// the WS-5/WS-6 rows: document symbols, scope binders, receiver members.
#typedef idxrec =
  @(list(jval), list(jval), list(sint), list(jval), list(jval), list(jval), list(jval))
// a reference target: (found, defUri, dl0, dc0, dl1, dc1).
#typedef reftgt = @(bool, string, sint, sint, sint, sint)
// a bg-indexed (unopened) file's symbols: (uri, dedup'd symbol rows).
#typedef projrec = @(string, list(jval))
//
#extern fun lsp_getenv(name: string): string = $extnam()
//
(* ****** ****** *)
(* ---- accumulator + index cells (module-owned, init at fragment load) ---- *)
//
val the_diags:   lspcell(list(jval)) = cell_make(list_nil())
val the_hovers:  lspcell(list(jval)) = cell_make(list_nil())
val the_defs:    lspcell(list(jval)) = cell_make(list_nil())
val the_tokens:  lspcell(list(jval)) = cell_make(list_nil())
val the_inlays:  lspcell(list(jval)) = cell_make(list_nil())
val the_syms:    lspcell(list(jval)) = cell_make(list_nil())
val the_scopes:  lspcell(list(jval)) = cell_make(list_nil())
val the_members: lspcell(list(jval)) = cell_make(list_nil())
val the_ndiags:  lspcell(sint) = cell_make(0)
val the_index:   lspcell(list(@(string, idxrec))) = cell_make(list_nil())
// completion caches: prelude pervasives + the staloaded API (jval rows {name,kind,
// typ}) + the seen staloaded-file stamps + the path-keyed bg-indexed symbol cache.
val the_prelude:       lspcell(list(jval)) = cell_make(list_nil())
val the_staload:       lspcell(list(jval)) = cell_make(list_nil())
val the_staload_files: lspcell(list(sint)) = cell_make(list_nil())
val the_proj:          lspcell(list(@(string, projrec))) = cell_make(list_nil())
//
// env-configured once at load (matches the glue defaults).
fun env_is0(name: string): bool = strn_eq(lsp_getenv(name), "0")
fun parse_cap(s: string): sint = let
  val n = str_len(s)
  fun loop(i: sint, acc: sint, any: bool): sint =
    if (i >= n) then (if any then acc else 200)
    else let val c = str_char_code(s, i) in
      if (if (c >= 48) then (c <= 57) else false) then loop(i+1, acc*10 + (c-48), true)
      else 200   // non-numeric -> glue default
    end
in
  if strn_eq(s, "") then 200 else loop(0, 0, false)
end
val the_staload_enabled: bool = (if env_is0("ATS3_LSP_STALOAD_COMPLETE") then false else true)
val the_complete_cap: sint = parse_cap(lsp_getenv("ATS3_LSP_COMPLETE_CAP"))
//
fun push_cell(c: lspcell(list(jval)), row: jval): void =
  cell_set(c, list_cons(row, cell_get(c)))
//
(* ****** ****** *)
(* ---- small helpers ---- *)
//
fun gi(v: jval, k: string): sint = jas_int(jget(v, k), 0)
fun gs(v: jval, k: string): string = jas_str(jget(v, k), "")
//
fun k_int(acc: string, n: sint): string = strn_append(acc, strn_append(int2str(n), ":"))
fun k_str(acc: string, s: string): string = strn_append(acc, strn_append(s, ":"))
//
fun jlen(xs: list(jval)): sint =
  (case+ xs of list_nil() => 0 | list_cons(_, r) => 1 + jlen(r))
fun ilen(xs: list(sint)): sint =
  (case+ xs of list_nil() => 0 | list_cons(_, r) => 1 + ilen(r))
fun jappend(xs: list(jval), ys: list(jval)): list(jval) =
  (case+ xs of list_nil() => ys | list_cons(x, r) => list_cons(x, jappend(r, ys)))
//
fun posLE(la: sint, ca: sint, lb: sint, cb: sint): bool =
  if (la < lb) then true else (if (la = lb) then (ca <= cb) else false)
fun span4(l0: sint, c0: sint, l1: sint, c1: sint): sint =
  (l1 - l0) * 1000000 + (c1 - c0)
//
// jval object/array/position/range constructors.
fun jpr(k: string, v: jval): jpair = @(k, v)
fun mkpos(line: sint, ch: sint): jval =
  JVobj(list_cons(jpr("line", JVint line), list_cons(jpr("character", JVint ch), list_nil())))
fun mkrange(l0: sint, c0: sint, l1: sint, c1: sint): jval =
  JVobj(list_cons(jpr("start", mkpos(l0, c0)), list_cons(jpr("end", mkpos(l1, c1)), list_nil())))
//
(* ****** ****** *)
(* ---- generic dedup/sort over jval rows ---- *)
//
fun seen_has(seen: list(string), k: string): bool =
  (case+ seen of
   | list_nil() => false
   | list_cons(s, rest) => (if strn_eq(s, k) then true else seen_has(rest, k)))
//
fun jfilter(rows: list(jval), keep: jval -> bool): list(jval) =
  (case+ rows of
   | list_nil() => list_nil()
   | list_cons(x, rest) =>
     if keep(x) then list_cons(x, jfilter(rest, keep)) else jfilter(rest, keep))
//
fun jdedup1(rows: list(jval), keyf: jval -> string, seen: list(string)): list(jval) =
  (case+ rows of
   | list_nil() => list_nil()
   | list_cons(x, rest) => let val k = keyf(x) in
       if seen_has(seen, k) then jdedup1(rest, keyf, seen)
       else list_cons(x, jdedup1(rest, keyf, list_cons(k, seen)))
     end)
//
// stable insertion sort (forward fold; equal keys keep input order).
fun sins(x: jval, sorted: list(jval), before: (jval, jval) -> bool): list(jval) =
  (case+ sorted of
   | list_nil() => list_cons(x, list_nil())
   | list_cons(y, rest) =>
     if before(x, y) then list_cons(x, sorted)
     else list_cons(y, sins(x, rest, before)))
fun jssort_go(rows: list(jval), acc: list(jval), before: (jval, jval) -> bool): list(jval) =
  (case+ rows of
   | list_nil() => acc
   | list_cons(x, rest) => jssort_go(rest, sins(x, acc, before), before))
fun jstable_sort(rows: list(jval), before: (jval, jval) -> bool): list(jval) =
  jssort_go(rows, list_nil(), before)
//
// comparators (true iff a strictly precedes b).
fun pos4_before(a: jval, b: jval): bool = // (l0,c0,l1,c1) all ascending
  let val a0 = gi(a,"l0") val b0 = gi(b,"l0") in
    if (a0 = b0) then let val a1 = gi(a,"c0") val b1 = gi(b,"c0") in
      if (a1 = b1) then let val a2 = gi(a,"l1") val b2 = gi(b,"l1") in
        if (a2 = b2) then (gi(a,"c1") < gi(b,"c1")) else (a2 < b2)
      end else (a1 < b1)
    end else (a0 < b0)
  end
fun hov_before(a: jval, b: jval): bool = // l0 asc, c0 asc, l1 DESC, c1 DESC
  let val a0 = gi(a,"l0") val b0 = gi(b,"l0") in
    if (a0 = b0) then let val a1 = gi(a,"c0") val b1 = gi(b,"c0") in
      if (a1 = b1) then let val a2 = gi(a,"l1") val b2 = gi(b,"l1") in
        if (a2 = b2) then (gi(a,"c1") > gi(b,"c1")) else (a2 > b2)
      end else (a1 < b1)
    end else (a0 < b0)
  end
fun line_col_before(a: jval, b: jval): bool = // (line,col) ascending (inlays)
  let val a0 = gi(a,"line") val b0 = gi(b,"line") in
    if (a0 = b0) then (gi(a,"col") < gi(b,"col")) else (a0 < b0)
  end
fun tok_before(a: jval, b: jval): bool = // (l0,c0) ascending (tokens)
  let val a0 = gi(a,"l0") val b0 = gi(b,"l0") in
    if (a0 = b0) then (gi(a,"c0") < gi(b,"c0")) else (a0 < b0)
  end
//
(* ****** ****** *)
(* ---- hover dedup ---- *)
//
fun hov_keep(r: jval): bool = let
  val l0 = gi(r,"l0") val c0 = gi(r,"c0") val l1 = gi(r,"l1") val c1 = gi(r,"c1")
in
  if (if (l0 >= 0) then (c0 >= 0) else false) then
    (if (l1 < l0) then false else (if (if (l1 = l0) then (c1 < c0) else false) then false else true))
  else false
end
fun hov_key(r: jval): string =
  k_str(k_str(k_int(k_int(k_int(k_int("", gi(r,"l0")), gi(r,"c0")), gi(r,"l1")), gi(r,"c1")), gs(r,"kind")), gs(r,"typ"))
fun dedup_hovers(rows: list(jval)): list(jval) =
  jstable_sort(jdedup1(jfilter(rows, hov_keep), hov_key, list_nil()), hov_before)
//
(* ****** ****** *)
(* ---- def dedup ---- *)
//
fun def_keep(r: jval): bool =
  if (if (gi(r,"l0") >= 0) then (gi(r,"c0") >= 0) else false) then
    (if (gi(r,"dl0") >= 0) then (gi(r,"dc0") >= 0) else false)
  else false
fun def_key(r: jval): string =
  k_str(k_int(k_int(k_int(k_int(k_str(k_int(k_int(k_int(k_int("",
    gi(r,"l0")), gi(r,"c0")), gi(r,"l1")), gi(r,"c1")), gs(r,"du")),
    gi(r,"dl0")), gi(r,"dc0")), gi(r,"dl1")), gi(r,"dc1")), gs(r,"entity"))
fun dedup_defs(rows: list(jval)): list(jval) =
  jstable_sort(jdedup1(jfilter(rows, def_keep), def_key, list_nil()), pos4_before)
//
(* ****** ****** *)
(* ---- inlay dedup ---- *)
//
fun inl_keep(r: jval): bool =
  if (gi(r,"line") >= 0) then (gi(r,"col") >= 0) else false
fun inl_key(r: jval): string =
  k_str(k_int(k_int(k_int("", gi(r,"line")), gi(r,"col")), gi(r,"kind")) , gs(r,"label"))
fun dedup_inlays(rows: list(jval)): list(jval) =
  jstable_sort(jdedup1(jfilter(rows, inl_keep), inl_key, list_nil()), line_col_before)
//
(* ****** ****** *)
(* ---- symbol / scope / member dedup ---- *)
//
fun pos2_keep(r: jval): bool = (if (gi(r,"l0") >= 0) then (gi(r,"c0") >= 0) else false)
// document symbols: key l0:c0:l1:c1:kind:name:container ; sort by (l0,c0) asc.
fun sym_key(r: jval): string =
  k_str(k_str(k_int(k_int(k_int(k_int(k_int("",
    gi(r,"l0")), gi(r,"c0")), gi(r,"l1")), gi(r,"c1")), gi(r,"kind")), gs(r,"name")), gs(r,"container"))
fun line_col2_before(a: jval, b: jval): bool = // (l0,c0) ascending (symbols)
  let val a0 = gi(a,"l0") val b0 = gi(b,"l0") in
    if (a0 = b0) then (gi(a,"c0") < gi(b,"c0")) else (a0 < b0)
  end
fun dedup_symbols(rows: list(jval)): list(jval) =
  jstable_sort(jdedup1(jfilter(rows, pos2_keep), sym_key, list_nil()), line_col2_before)
// scopes: key l0:c0:l1:c1:name:typ ; NO sort (push order preserved, as the glue).
fun scope_key(r: jval): string =
  k_str(k_str(k_int(k_int(k_int(k_int("",
    gi(r,"l0")), gi(r,"c0")), gi(r,"l1")), gi(r,"c1")), gs(r,"name")), gs(r,"typ"))
fun dedup_scopes(rows: list(jval)): list(jval) =
  jdedup1(jfilter(rows, pos2_keep), scope_key, list_nil())
// members: key l0:c0:l1:c1:name ; NO sort.
fun member_key(r: jval): string =
  k_str(k_int(k_int(k_int(k_int("",
    gi(r,"l0")), gi(r,"c0")), gi(r,"l1")), gi(r,"c1")), gs(r,"name"))
fun dedup_members(rows: list(jval)): list(jval) =
  jdedup1(jfilter(rows, pos2_keep), member_key, list_nil())
//
(* ****** ****** *)
(* ---- diagnostics dedup (overlap suppression + severity rank) ---- *)
//
fun diag_rank(code: string): sint =
  if strn_eq(code, "type-mismatch") then 5
  else if strn_eq(code, "unbound-identifier") then 5
  else if strn_eq(code, "unresolved-template") then 4
  else if strn_eq(code, "pattern-error") then 3
  else if strn_eq(code, "unknown") then 2
  else if strn_eq(code, "decl-error") then 1
  else 2
fun diag_valid(r: jval): bool =
  if (gi(r,"l0") >= 0) then (gi(r,"c0") >= 0) else false
fun same_key01(a: jval, b: jval): bool =
  if (gi(a,"l0") = gi(b,"l0")) then (gi(a,"c0") = gi(b,"c0")) else false
// pick the winner between a same-(l0,c0) pair: smaller (l1,c1) end wins, ties by rank.
fun diag_pick(e: jval, d: jval): jval = let
  val de = gi(d,"l1") * 1000000 + gi(d,"c1")
  val ce = gi(e,"l1") * 1000000 + gi(e,"c1")
in
  if (de < ce) then d
  else if (de = ce) then (if (diag_rank(gs(d,"code")) > diag_rank(gs(e,"code"))) then d else e)
  else e
end
fun diag_ins(acc: list(jval), d: jval): list(jval) =
  (case+ acc of
   | list_nil() => list_cons(d, list_nil())
   | list_cons(e, rest) =>
     if same_key01(e, d) then list_cons(diag_pick(e, d), rest)
     else list_cons(e, diag_ins(rest, d)))
fun diag_best_go(rows: list(jval), acc: list(jval)): list(jval) =
  (case+ rows of
   | list_nil() => acc
   | list_cons(d, rest) => diag_best_go(rest, diag_ins(acc, d)))
//
fun overlap(a: jval, b: jval): bool =
  if posLE(gi(a,"l0"),gi(a,"c0"), gi(b,"l1"),gi(b,"c1"))
  then posLE(gi(b,"l0"),gi(b,"c0"), gi(a,"l1"),gi(a,"c1")) else false
fun coords_eq(a: jval, b: jval): bool =
  if (gi(a,"l0") = gi(b,"l0")) then
    (if (gi(a,"c0") = gi(b,"c0")) then
      (if (gi(a,"l1") = gi(b,"l1")) then (gi(a,"c1") = gi(b,"c1")) else false)
     else false)
  else false
// keep d unless some e strictly-contains d, or d is a decl-error dominated by an
// overlapping higher-rank diagnostic.
fun diag_keep1(d: jval, ys: list(jval)): bool =
  (case+ ys of
   | list_nil() => true
   | list_cons(e, rest) =>
     if same_key01(e, d) then diag_keep1(d, rest)  // e is self (keys unique)
     else let
       val inside =
         if posLE(gi(d,"l0"),gi(d,"c0"), gi(e,"l0"),gi(e,"c0"))
         then posLE(gi(e,"l1"),gi(e,"c1"), gi(d,"l1"),gi(d,"c1")) else false
       val strictly = if inside then (if coords_eq(e, d) then false else true) else false
       val decldom =
         if strn_eq(gs(d,"code"), "decl-error") then
           (if (if strn_eq(gs(e,"code"), "decl-error") then false else true) then
              (if overlap(d, e) then (diag_rank(gs(e,"code")) > diag_rank(gs(d,"code"))) else false)
            else false)
         else false
     in
       if strictly then false
       else if decldom then false
       else diag_keep1(d, rest)
     end)
fun diag_filter(ys_all: list(jval), ys: list(jval)): list(jval) =
  (case+ ys of
   | list_nil() => list_nil()
   | list_cons(d, rest) =>
     if diag_keep1(d, ys_all) then list_cons(d, diag_filter(ys_all, rest))
     else diag_filter(ys_all, rest))
fun dedup_diags(rows: list(jval)): list(jval) = let
  val xs = jfilter(rows, diag_valid)
  val ys = diag_best_go(xs, list_nil())
  val kept = diag_filter(ys, ys)
in
  jstable_sort(kept, pos4_before)
end
//
(* ****** ****** *)
(* ---- semantic-token encode (collapse same-start, keep shortest, delta) ---- *)
//
fun tok_valid(r: jval): bool =
  if (if (gi(r,"l0") >= 0) then (gi(r,"c0") >= 0) else false) then (gi(r,"len") > 0) else false
fun tok_ins(acc: list(jval), t: jval): list(jval) =
  (case+ acc of
   | list_nil() => list_cons(t, list_nil())
   | list_cons(e, rest) =>
     if same_key01(e, t) then
       (if (gi(t,"len") < gi(e,"len")) then list_cons(t, rest) else list_cons(e, rest))
     else list_cons(e, tok_ins(rest, t)))
fun tok_bystart(rows: list(jval), acc: list(jval)): list(jval) =
  (case+ rows of
   | list_nil() => acc
   | list_cons(t, rest) => tok_bystart(rest, tok_ins(acc, t)))
fun tok_delta(xs: list(jval), pl: sint, pc: sint): list(sint) =
  (case+ xs of
   | list_nil() => list_nil()
   | list_cons(t, rest) => let
       val l0 = gi(t,"l0") val c0 = gi(t,"c0")
       val dl = l0 - pl
       val dc = if (dl = 0) then (c0 - pc) else c0
     in
       list_cons(dl, list_cons(dc, list_cons(gi(t,"len"),
         list_cons(gi(t,"tt"), list_cons(gi(t,"mods"), tok_delta(rest, l0, c0))))))
     end)
fun encode_tokens(rows: list(jval)): list(sint) =
  tok_delta(jstable_sort(tok_bystart(jfilter(rows, tok_valid), list_nil()), tok_before), 0, 0)
//
(* ****** ****** *)
(* ---- innermost-by-position over a jval row list ---- *)
//
fun innermost_go
  (rows: list(jval), line: sint, ch: sint, haveb: bool, best: jval, bspan: sint): @(bool, jval) =
  (case+ rows of
   | list_nil() => @(haveb, best)
   | list_cons(r, rest) => let
       val l0 = gi(r,"l0") val c0 = gi(r,"c0") val l1 = gi(r,"l1") val c1 = gi(r,"c1")
     in
       if (if posLE(l0,c0,line,ch) then posLE(line,ch,l1,c1) else false) then let
         val sp = span4(l0,c0,l1,c1)
       in
         if (if haveb then (sp < bspan) else true)
         then innermost_go(rest, line, ch, true, r, sp)
         else innermost_go(rest, line, ch, haveb, best, bspan)
       end
       else innermost_go(rest, line, ch, haveb, best, bspan)
     end)
fun innermost(rows: list(jval), line: sint, ch: sint): @(bool, jval) =
  innermost_go(rows, line, ch, false, JVnull(), 0)
//
(* ****** ****** *)
(* ---- the index map: lookup / put / delete ---- *)
//
fun idx_lookup_go(lst: list(@(string, idxrec)), uri: string): @(bool, idxrec) =
  (case+ lst of
   | list_nil() => @(false, @(list_nil(), list_nil(), list_nil(), list_nil(), list_nil(), list_nil(), list_nil()))
   | list_cons(kv, rest) => if strn_eq(kv.0, uri) then @(true, kv.1) else idx_lookup_go(rest, uri))
fun idx_lookup(uri: string): @(bool, idxrec) = idx_lookup_go(cell_get(the_index), uri)
//
fun idx_put(lst: list(@(string, idxrec)), uri: string, rec: idxrec): list(@(string, idxrec)) =
  (case+ lst of
   | list_nil() => list_cons(@(uri, rec), list_nil())
   | list_cons(kv, rest) =>
     if strn_eq(kv.0, uri) then list_cons(@(uri, rec), rest)
     else list_cons(kv, idx_put(rest, uri, rec)))
fun idx_del(lst: list(@(string, idxrec)), uri: string): list(@(string, idxrec)) =
  (case+ lst of
   | list_nil() => list_nil()
   | list_cons(kv, rest) => if strn_eq(kv.0, uri) then rest else list_cons(kv, idx_del(rest, uri)))
//
(* ****** ****** *)
(* ---- row constructors (jval objects) ---- *)
//
fun mkdiag(l0: sint, c0: sint, l1: sint, c1: sint, code: string, message: string): jval =
  JVobj(list_cons(jpr("l0", JVint l0), list_cons(jpr("c0", JVint c0),
        list_cons(jpr("l1", JVint l1), list_cons(jpr("c1", JVint c1),
        list_cons(jpr("code", JVstr code), list_cons(jpr("message", JVstr message), list_nil())))))))
fun mkhover(l0: sint, c0: sint, l1: sint, c1: sint, typ: string, kind: string): jval =
  JVobj(list_cons(jpr("l0", JVint l0), list_cons(jpr("c0", JVint c0),
        list_cons(jpr("l1", JVint l1), list_cons(jpr("c1", JVint c1),
        list_cons(jpr("typ", JVstr typ), list_cons(jpr("kind", JVstr kind), list_nil())))))))
fun mktoken(l0: sint, c0: sint, len: sint, tt: sint, mods: sint): jval =
  JVobj(list_cons(jpr("l0", JVint l0), list_cons(jpr("c0", JVint c0),
        list_cons(jpr("len", JVint len), list_cons(jpr("tt", JVint tt),
        list_cons(jpr("mods", JVint mods), list_nil()))))))
fun mkinlay(line: sint, col: sint, label: string, kind: sint): jval =
  JVobj(list_cons(jpr("line", JVint line), list_cons(jpr("col", JVint col),
        list_cons(jpr("label", JVstr label), list_cons(jpr("kind", JVint kind), list_nil())))))
fun mkdef
  ( l0: sint, c0: sint, l1: sint, c1: sint, du: string
  , dl0: sint, dc0: sint, dl1: sint, dc1: sint, entity: string
  , tdu: string, tl0: sint, tc0: sint, tl1: sint, tc1: sint) : jval =
  JVobj(
    list_cons(jpr("l0", JVint l0), list_cons(jpr("c0", JVint c0),
    list_cons(jpr("l1", JVint l1), list_cons(jpr("c1", JVint c1),
    list_cons(jpr("du", JVstr du),
    list_cons(jpr("dl0", JVint dl0), list_cons(jpr("dc0", JVint dc0),
    list_cons(jpr("dl1", JVint dl1), list_cons(jpr("dc1", JVint dc1),
    list_cons(jpr("entity", JVstr entity),
    list_cons(jpr("tdu", JVstr tdu),
    list_cons(jpr("tl0", JVint tl0), list_cons(jpr("tc0", JVint tc0),
    list_cons(jpr("tl1", JVint tl1), list_cons(jpr("tc1", JVint tc1),
    list_nil()))))))))))))))))
fun mksym(l0: sint, c0: sint, l1: sint, c1: sint, name: string, kind: sint, container: string, typ: string): jval =
  JVobj(list_cons(jpr("l0", JVint l0), list_cons(jpr("c0", JVint c0),
        list_cons(jpr("l1", JVint l1), list_cons(jpr("c1", JVint c1),
        list_cons(jpr("name", JVstr name), list_cons(jpr("kind", JVint kind),
        list_cons(jpr("container", JVstr container), list_cons(jpr("typ", JVstr typ), list_nil())))))))))
fun mksm2(l0: sint, c0: sint, l1: sint, c1: sint, name: string, typ: string): jval =
  JVobj(list_cons(jpr("l0", JVint l0), list_cons(jpr("c0", JVint c0),
        list_cons(jpr("l1", JVint l1), list_cons(jpr("c1", JVint c1),
        list_cons(jpr("name", JVstr name), list_cons(jpr("typ", JVstr typ), list_nil()))))))) // scope/member row
fun mknk(name: string, kind: sint, typ: string): jval =   // prelude/staload cache row
  JVobj(list_cons(jpr("name", JVstr name), list_cons(jpr("kind", JVint kind),
        list_cons(jpr("typ", JVstr typ), list_nil()))))
//
(* ****** ****** *)
(* ---- bit4 (defaultLibrary) modifier ---- *)
//
fun bit4_set(m: sint): bool = let val q = m / 16 in ((q - (q / 2) * 2) = 1) end
fun mods_deflib(m: sint): sint = if bit4_set(m) then m else (m + 16)
//
(* ****** ****** *)
(* ---- sinks ---- *)
//
#implfun idx_diag_push(l0, c0, l1, c1, code, message) =
  push_cell(the_diags,
    mkdiag(l0, LSP_cur_b2u(l0, c0), l1, LSP_cur_b2u(l1, c1), code, LSP_friendly(message)))
//
#implfun idx_hover_push(l0, c0, l1, c1, typ, kind) =
  if strn_eq(typ, "") then ()
  else push_cell(the_hovers, mkhover(l0, LSP_cur_b2u(l0, c0), l1, LSP_cur_b2u(l1, c1), typ, kind))
//
#implfun idx_def_push(ul0, uc0, ul1, uc1, defpath, dl0, dc0, dl1, dc1, entity, hastdef, tdpath, tl0, tc0, tl1, tc1) = let
  val defUri = LSP_path2uri(defpath)
in
  if strn_eq(defUri, "") then ()
  else let
    val inCur = LSP_def_in_current(defUri)
    val dc0u = if inCur then LSP_cur_b2u(dl0, dc0) else LSP_other_b2u(defpath, dl0, dc0)
    val dc1u = if inCur then LSP_cur_b2u(dl1, dc1) else LSP_other_b2u(defpath, dl1, dc1)
    val td = (
      if (hastdef = 1) then let
        val u = LSP_path2uri(tdpath)
      in
        if strn_eq(u, "") then @("", 0, 0, 0, 0)
        else let
          val inCurT = LSP_def_in_current(u)
          val tc0v = if inCurT then LSP_cur_b2u(tl0, tc0) else LSP_other_b2u(tdpath, tl0, tc0)
          val tc1v = if inCurT then LSP_cur_b2u(tl1, tc1) else LSP_other_b2u(tdpath, tl1, tc1)
        in @(u, tl0, tc0v, tl1, tc1v) end
      end
      else @("", 0, 0, 0, 0)
    ) : @(string, sint, sint, sint, sint)
  in
    push_cell(the_defs,
      mkdef(ul0, LSP_cur_b2u(ul0, uc0), ul1, LSP_cur_b2u(ul1, uc1), defUri,
            dl0, dc0u, dl1, dc1u, entity, td.0, td.1, td.2, td.3, td.4))
  end
end
//
#implfun idx_token_push(l0, c0, l1, c1, ttype, tmods, defpath) =
  if (if (l0 < 0) then true else (if (c0 < 0) then true else (if (l0 = l1) then false else true)))
  then ()
  else let
    val cu0 = LSP_cur_b2u(l0, c0)
    val cu1 = LSP_cur_b2u(l1, c1)
    val len = cu1 - cu0
  in
    if (len <= 0) then ()
    else let
      val mods =
        if (if strn_eq(defpath, "") then false else JS_path_is_prelude(defpath))
        then mods_deflib(tmods) else tmods
    in push_cell(the_tokens, mktoken(l0, cu0, len, ttype, mods)) end
  end
//
#implfun idx_inlay_push(line, col, label, kind) =
  if (if (line < 0) then true else (if (col < 0) then true else strn_eq(label, "")))
  then ()
  else push_cell(the_inlays, mkinlay(line, LSP_cur_b2u(line, col), label, kind))
//
#implfun idx_symbol_push(l0, c0, l1, c1, name, kind, container, typ) =
  if (if (l0 < 0) then true else (if (c0 < 0) then true else strn_eq(name, "")))
  then ()
  else push_cell(the_syms, mksym(l0, LSP_cur_b2u(l0, c0), l1, LSP_cur_b2u(l1, c1), name, kind, container, typ))
//
#implfun idx_scope_push(l0, c0, l1, c1, name, typ) =
  if (if (l0 < 0) then true else (if (c0 < 0) then true else strn_eq(name, "")))
  then ()
  else push_cell(the_scopes, mksm2(l0, LSP_cur_b2u(l0, c0), l1, LSP_cur_b2u(l1, c1), name, typ))
//
#implfun idx_member_push(l0, c0, l1, c1, name, typ) =
  if (if (l0 < 0) then true else (if (c0 < 0) then true else strn_eq(name, "")))
  then ()
  else push_cell(the_members, mksm2(l0, LSP_cur_b2u(l0, c0), l1, LSP_cur_b2u(l1, c1), name, typ))
//
(* ---- completion symbol caches (name-dedup deferred to query time) ---- *)
//
fun ilist_has(xs: list(sint), x: sint): bool =
  (case+ xs of list_nil() => false | list_cons(y, r) => (if (y = x) then true else ilist_has(r, x)))
//
#implfun idx_prelude_reset() = cell_set(the_prelude, list_nil())
#implfun idx_prelude_push(name, kind, typ) =
  if strn_eq(name, "") then () else cell_set(the_prelude, list_cons(mknk(name, kind, typ), cell_get(the_prelude)))
#implfun idx_prelude_done() = ()
#implfun idx_prelude_count() = jlen(cell_get(the_prelude))
//
#implfun idx_staload_seen(stamp) =
  if (if the_staload_enabled then false else true) then true
  else ilist_has(cell_get(the_staload_files), stamp)
#implfun idx_staload_mark(stamp) = cell_set(the_staload_files, list_cons(stamp, cell_get(the_staload_files)))
#implfun idx_staload_push(name, kind, typ) =
  if strn_eq(name, "") then () else cell_set(the_staload, list_cons(mknk(name, kind, typ), cell_get(the_staload)))
#implfun idx_staload_reset() = let
  val _ = cell_set(the_staload, list_nil())
  val _ = cell_set(the_staload_files, list_nil())
in () end
//
// snapshot the CURRENT symbol accumulator (deduped) under `path`/`uri`.
fun proj_put(lst: list(@(string, projrec)), path: string, rec: projrec): list(@(string, projrec)) =
  (case+ lst of
   | list_nil() => list_cons(@(path, rec), list_nil())
   | list_cons(kv, r) =>
     if strn_eq(kv.0, path) then list_cons(@(path, rec), r) else list_cons(kv, proj_put(r, path, rec)))
fun proj_rm(lst: list(@(string, projrec)), path: string): list(@(string, projrec)) =
  (case+ lst of
   | list_nil() => list_nil()
   | list_cons(kv, r) => if strn_eq(kv.0, path) then r else list_cons(kv, proj_rm(r, path)))
#implfun idx_proj_store(path, uri) = let
  val sym = dedup_symbols(list_reverse(cell_get(the_syms)))
  val rec = @(uri, sym) : projrec
in cell_set(the_proj, proj_put(cell_get(the_proj), path, rec)) end
#implfun idx_proj_delete(path) = cell_set(the_proj, proj_rm(cell_get(the_proj), path))
//
(* ****** ****** *)
(* ---- lifecycle ---- *)
//
#implfun idx_reset() = let
  val _ = cell_set(the_diags, list_nil())
  val _ = cell_set(the_hovers, list_nil())
  val _ = cell_set(the_defs, list_nil())
  val _ = cell_set(the_tokens, list_nil())
  val _ = cell_set(the_inlays, list_nil())
  val _ = cell_set(the_syms, list_nil())
  val _ = cell_set(the_scopes, list_nil())
  val _ = cell_set(the_members, list_nil())
in () end
//
#implfun idx_commit(uri) = let
  val hov = dedup_hovers(list_reverse(cell_get(the_hovers)))
  val def = dedup_defs(list_reverse(cell_get(the_defs)))
  val sem = encode_tokens(list_reverse(cell_get(the_tokens)))
  val inl = dedup_inlays(list_reverse(cell_get(the_inlays)))
  val sym = dedup_symbols(list_reverse(cell_get(the_syms)))
  val scp = dedup_scopes(list_reverse(cell_get(the_scopes)))
  val mem = dedup_members(list_reverse(cell_get(the_members)))
  val rec = @(hov, def, sem, inl, sym, scp, mem) : idxrec
in
  cell_set(the_index, idx_put(cell_get(the_index), uri, rec))
end
//
#implfun idx_evict(uri) = cell_set(the_index, idx_del(cell_get(the_index), uri))
#implfun idx_clear() = cell_set(the_index, list_nil())
//
(* ****** ****** *)
(* ---- diagnostics (published array) ---- *)
//
fun diag_to_lsp(ds: list(jval)): list(jval) =
  (case+ ds of
   | list_nil() => list_nil()
   | list_cons(d, rest) =>
     list_cons(
       JVobj(list_cons(jpr("range", mkrange(gi(d,"l0"), gi(d,"c0"), gi(d,"l1"), gi(d,"c1"))),
             list_cons(jpr("severity", JVint 1),
             list_cons(jpr("code", JVstr (gs(d,"code"))),
             list_cons(jpr("message", JVstr (gs(d,"message"))),
             list_cons(jpr("source", JVstr "ats3"), list_nil())))))),
       diag_to_lsp(rest)))
#implfun idx_diagnostics() = let
  val ds = dedup_diags(list_reverse(cell_get(the_diags)))
  val _ = cell_set(the_ndiags, jlen(ds))
in
  json_serialize(JVarr(diag_to_lsp(ds)))
end
#implfun idx_ndiags() = cell_get(the_ndiags)
//
#implfun idx_count(uri, which) = let
  val lk = idx_lookup(uri)
in
  if lk.0 then let val rec = lk.1 in
    if (which = 0) then jlen(rec.0)
    else if (which = 1) then jlen(rec.1)
    else if (which = 2) then (ilen(rec.2) / 5)
    else 0
  end else 0
end
//
(* ****** ****** *)
(* ---- request builders ---- *)
//
fun build_hover(hovers: list(jval), line: sint, ch: sint): string = let
  val m = innermost(hovers, line, ch)
in
  if m.0 then let
    val h = m.1
    val value = strn_append("```ats\n", strn_append(gs(h,"typ"), "\n```"))
    val contents = JVobj(list_cons(jpr("kind", JVstr "markdown"), list_cons(jpr("value", JVstr value), list_nil())))
    val obj = JVobj(list_cons(jpr("contents", contents),
                    list_cons(jpr("range", mkrange(gi(h,"l0"), gi(h,"c0"), gi(h,"l1"), gi(h,"c1"))), list_nil())))
  in json_serialize(obj) end
  else "null"
end
//
fun build_def(defs: list(jval), line: sint, ch: sint): string = let
  val m = innermost(defs, line, ch)
in
  if m.0 then let val d = m.1 in
    if strn_eq(gs(d,"du"), "") then "null"
    else json_serialize(JVobj(list_cons(jpr("uri", JVstr (gs(d,"du"))),
           list_cons(jpr("range", mkrange(gi(d,"dl0"), gi(d,"dc0"), gi(d,"dl1"), gi(d,"dc1"))), list_nil()))))
  end else "null"
end
//
fun build_typedef(defs: list(jval), line: sint, ch: sint): string = let
  val m = innermost(defs, line, ch)
in
  if m.0 then let val d = m.1 in
    if strn_eq(gs(d,"tdu"), "") then "null"
    else json_serialize(JVobj(list_cons(jpr("uri", JVstr (gs(d,"tdu"))),
           list_cons(jpr("range", mkrange(gi(d,"tl0"), gi(d,"tc0"), gi(d,"tl1"), gi(d,"tc1"))), list_nil()))))
  end else "null"
end
//
fun find_ref_fallback(defs: list(jval), uri: string, line: sint, ch: sint): reftgt =
  (case+ defs of
   | list_nil() => @(false, "", 0, 0, 0, 0)
   | list_cons(d, rest) =>
     if (if strn_eq(gs(d,"du"), uri) then
           (if posLE(gi(d,"dl0"),gi(d,"dc0"),line,ch) then posLE(line,ch,gi(d,"dl1"),gi(d,"dc1")) else false)
         else false)
     then @(true, gs(d,"du"), gi(d,"dl0"), gi(d,"dc0"), gi(d,"dl1"), gi(d,"dc1"))
     else find_ref_fallback(rest, uri, line, ch))
fun find_ref_target(defs: list(jval), uri: string, line: sint, ch: sint): reftgt = let
  val m = innermost(defs, line, ch)
in
  if m.0 then let val d = m.1 in
    @(true, gs(d,"du"), gi(d,"dl0"), gi(d,"dc0"), gi(d,"dl1"), gi(d,"dc1"))
  end else find_ref_fallback(defs, uri, line, ch)
end
//
fun def_groupkey(du: string, l0: sint, c0: sint, l1: sint, c1: sint): string =
  k_int(k_int(k_int(k_int(k_str("", du), l0), c0), l1), c1)
fun use_groupkey(l0: sint, c0: sint, l1: sint, c1: sint): string =
  k_int(k_int(k_int(k_int("", l0), c0), l1), c1)
// collect the USE ranges of every def row matching the target's def identity.
fun group_use_go(defs: list(jval), key: string, seen: list(string), acc: list(jval)): list(jval) =
  (case+ defs of
   | list_nil() => list_reverse(acc)
   | list_cons(d, rest) =>
     if strn_eq(def_groupkey(gs(d,"du"), gi(d,"dl0"), gi(d,"dc0"), gi(d,"dl1"), gi(d,"dc1")), key) then let
       val uk = use_groupkey(gi(d,"l0"), gi(d,"c0"), gi(d,"l1"), gi(d,"c1"))
     in
       if seen_has(seen, uk) then group_use_go(rest, key, seen, acc)
       else group_use_go(rest, key, list_cons(uk, seen),
              list_cons(mkrange(gi(d,"l0"), gi(d,"c0"), gi(d,"l1"), gi(d,"c1")), acc))
     end
     else group_use_go(rest, key, seen, acc))
fun group_use_ranges(defs: list(jval), t: reftgt): list(jval) =
  group_use_go(defs, def_groupkey(t.1, t.2, t.3, t.4, t.5), list_nil(), list_nil())
//
fun ref_locs(uri: string, ranges: list(jval)): list(jval) =
  (case+ ranges of
   | list_nil() => list_nil()
   | list_cons(rng, rest) =>
     list_cons(JVobj(list_cons(jpr("uri", JVstr uri), list_cons(jpr("range", rng), list_nil()))),
       ref_locs(uri, rest)))
fun build_references(defs: list(jval), uri: string, line: sint, ch: sint, includeDecl: sint): string = let
  val t = find_ref_target(defs, uri, line, ch)
in
  if (if t.0 then false else true) then "null"
  else let
    val locs0 = ref_locs(uri, group_use_ranges(defs, t))
    val locs =
      if (if (includeDecl = 1) then (if strn_eq(t.1, "") then false else true) else false)
      then jappend(locs0, list_cons(
             JVobj(list_cons(jpr("uri", JVstr (t.1)), list_cons(jpr("range", mkrange(t.2, t.3, t.4, t.5)), list_nil()))),
             list_nil()))
      else locs0
  in json_serialize(JVarr(locs)) end
end
//
fun hl_items(ranges: list(jval)): list(jval) =
  (case+ ranges of
   | list_nil() => list_nil()
   | list_cons(rng, rest) =>
     list_cons(JVobj(list_cons(jpr("range", rng), list_cons(jpr("kind", JVint 2), list_nil()))),
       hl_items(rest)))
fun build_highlights(defs: list(jval), uri: string, line: sint, ch: sint): string = let
  val t = find_ref_target(defs, uri, line, ch)
in
  if (if t.0 then false else true) then "null"
  else let
    val hl0 = hl_items(group_use_ranges(defs, t))
    val hl =
      if strn_eq(t.1, uri)
      then jappend(hl0, list_cons(
             JVobj(list_cons(jpr("range", mkrange(t.2, t.3, t.4, t.5)), list_cons(jpr("kind", JVint 3), list_nil()))),
             list_nil()))
      else hl0
  in json_serialize(JVarr(hl)) end
end
//
fun inlay_item(h: jval): jval =
  JVobj(list_cons(jpr("position", mkpos(gi(h,"line"), gi(h,"col"))),
        list_cons(jpr("label", JVstr (gs(h,"label"))),
        list_cons(jpr("kind", JVint (gi(h,"kind"))),
        list_cons(jpr("paddingLeft", JVbool false),
        list_cons(jpr("paddingRight", JVbool false), list_nil()))))))
fun inlay_go(inlays: list(jval), hasrng: bool, rl0: sint, rc0: sint, rl1: sint, rc1: sint): list(jval) =
  (case+ inlays of
   | list_nil() => list_nil()
   | list_cons(h, rest) => let
       val keep =
         if hasrng then
           (if posLE(rl0, rc0, gi(h,"line"), gi(h,"col"))
            then posLE(gi(h,"line"), gi(h,"col"), rl1, rc1) else false)
         else true
     in
       if keep then list_cons(inlay_item(h), inlay_go(rest, hasrng, rl0, rc0, rl1, rc1))
       else inlay_go(rest, hasrng, rl0, rc0, rl1, rc1)
     end)
fun build_inlays(inlays: list(jval), hasrng: bool, rl0: sint, rc0: sint, rl1: sint, rc1: sint): string =
  json_serialize(JVarr(inlay_go(inlays, hasrng, rl0, rc0, rl1, rc1)))
//
fun ints_to_jarr(xs: list(sint)): list(jval) =
  (case+ xs of list_nil() => list_nil() | list_cons(x, r) => list_cons(JVint x, ints_to_jarr(r)))
fun build_semantic(sem: list(sint)): string =
  json_serialize(JVobj(list_cons(jpr("data", JVarr(ints_to_jarr(sem))), list_nil())))
//
fun max_field(rows: list(jval), k: string, acc: sint): sint =
  (case+ rows of
   | list_nil() => acc
   | list_cons(r, rest) => let val v = gi(r, k) in max_field(rest, k, (if (v > acc) then v else acc)) end)
// max absolute line decoded from the delta-encoded semantic flat ints.
fun max_token_line(xs: list(sint), line: sint, mx: sint): sint =
  (case+ xs of
   | list_cons(dl, list_cons(_, list_cons(_, list_cons(_, list_cons(_, rest))))) => let
       val nl = line + dl
     in max_token_line(rest, nl, (if (nl > mx) then nl else mx)) end
   | _ => mx)
fun build_index_stats(found: bool, rec: idxrec): string =
  if (if found then false else true)
  then json_serialize(JVobj(list_cons(jpr("found", JVbool false), list_nil())))
  else let
    val hs = rec.0 val ds = rec.1 val tk = rec.2
    val maxH = max_field(hs, "l1", (0 - 1))
    val maxD = max_field(ds, "l1", (0 - 1))
    val maxT = max_token_line(tk, 0, (0 - 1))
  in
    json_serialize(JVobj(
      list_cons(jpr("found", JVbool true),
      list_cons(jpr("hovers", JVint (jlen(hs))),
      list_cons(jpr("defs", JVint (jlen(ds))),
      list_cons(jpr("tokens", JVint (ilen(tk) / 5)),
      list_cons(jpr("maxHoverLine", JVint maxH),
      list_cons(jpr("maxDefUseLine", JVint maxD),
      list_cons(jpr("maxTokenLine", JVint maxT), list_nil())))))))))
  end
//
(* ****** ****** *)
(* ---- documentSymbol ---- *)
//
fun docsym_items(syms: list(jval)): list(jval) =
  (case+ syms of
   | list_nil() => list_nil()
   | list_cons(s, r) => let
       val rng = mkrange(gi(s,"l0"), gi(s,"c0"), gi(s,"l1"), gi(s,"c1"))
     in
       list_cons(JVobj(
         list_cons(jpr("name", JVstr (gs(s,"name"))), list_cons(jpr("kind", JVint (gi(s,"kind"))),
         list_cons(jpr("detail", JVstr (gs(s,"typ"))),
         list_cons(jpr("range", rng), list_cons(jpr("selectionRange", rng),
         list_cons(jpr("children", JVarr(list_nil())), list_nil()))))))),
         docsym_items(r))
     end)
fun build_docsym(found: bool, syms: list(jval)): string =
  if (if found then false else true) then "null" else json_serialize(JVarr(docsym_items(syms)))
//
(* ****** ****** *)
(* ---- string helpers for completion / workspace ---- *)
//
fun downcase_char(c: sint): sint = if (if (c >= 65) then (c <= 90) else false) then (c + 32) else c
fun downcase_str(s: string): string = let
  val n = str_len(s)
  fun loop(i: sint, acc: string): string =
    if (i >= n) then acc else loop(i+1, strn_append(acc, str_of_code(downcase_char(str_char_code(s, i)))))
in loop(0, "") end
// case-insensitive prefix: wlow is the pre-downcased query, wlen its length.
fun ci_prefix(name: string, wlow: string, wlen: sint): bool =
  if (wlen = 0) then true
  else if (str_len(name) >= wlen) then let
    fun loop(i: sint): bool =
      if (i >= wlen) then true
      else if (downcase_char(str_char_code(name, i)) = str_char_code(wlow, i)) then loop(i+1) else false
  in loop(0) end
  else false
// SymbolKind -> CompletionItemKind (mirrors the glue LSP_sk_to_cik table).
fun sk_to_cik(k: sint): sint =
  if (k = 12) then 3 else if (k = 14) then 21 else if (k = 13) then 6
  else if (k = 10) then 13 else if (k = 11) then 8 else if (k = 5) then 7
  else if (k = 26) then 25 else if (k = 22) then 20 else if (k = 9) then 4 else 6
fun cand_detail(kind: sint, typ: string, src: string): string =
  if (if strn_eq(typ, "") then false else true) then typ
  else if (kind = 12) then "overloaded" else src
// case-insensitive subsequence (workspace fuzzy); qlow pre-downcased.
fun subseq(q: string, qi: sint, ql: sint, n: string, ni: sint, nl: sint): bool =
  if (qi >= ql) then true
  else if (ni >= nl) then false
  else if (str_char_code(q, qi) = str_char_code(n, ni)) then subseq(q, qi+1, ql, n, ni+1, nl)
  else subseq(q, qi, ql, n, ni+1, nl)
fun ws_fuzzy(qlow: string, name: string): bool =
  if strn_eq(qlow, "") then true
  else let val nlow = downcase_str(name) in subseq(qlow, 0, str_len(qlow), nlow, 0, str_len(nlow)) end
//
(* ****** ****** *)
(* ---- completion (4-tier; the doc-store word is supplied by the glue) ---- *)
//
// completion state: (items reversed, seen names, count).
#typedef cst = @(list(jval), list(string), sint)
fun cst_empty((*void*)): cst = @(list_nil(), list_nil(), 0)
//
val the_keywords: list(string) =
  list_cons("val", list_cons("valpar", list_cons("val-", list_cons("var", list_cons("fun",
  list_cons("fn", list_cons("fnx", list_cons("prval", list_cons("prfun", list_cons("prfn",
  list_cons("praxi", list_cons("castfn", list_cons("let", list_cons("in", list_cons("end",
  list_cons("local", list_cons("where", list_cons("begin", list_cons("case", list_cons("case+",
  list_cons("case-", list_cons("of", list_cons("if", list_cons("then", list_cons("else",
  list_cons("sif", list_cons("scase", list_cons("while", list_cons("for", list_cons("lam",
  list_cons("llam", list_cons("fix", list_cons("when", list_cons("and", list_cons("rec",
  list_cons("datatype", list_cons("datavtype", list_cons("dataprop", list_cons("typedef", list_cons("abstype",
  list_cons("abstbox", list_cons("stacst", list_cons("sortdef", list_cons("sexpdef", list_cons("exception",
  list_cons("implement", list_cons("extern", list_cons("staload", list_cons("include", list_cons("dynload",
  list_cons("addr", list_cons("view", list_cons("true", list_cons("false",
  list_nil()))))))))))))))))))))))))))))))))))))))))))))))))))))))
//
fun comp_add(name: string, symKind: sint, src: string, detail: string,
             rng: jval, wlow: string, wlen: sint, cap: sint, st: cst): cst = let
  val items = st.0 val seen = st.1 val cnt = st.2
in
  if (if (cnt < cap) then
        (if (if strn_eq(name, "") then false else true) then
           (if seen_has(seen, name) then false else ci_prefix(name, wlow, wlen))
         else false)
      else false)
  then let
    val cik = if strn_eq(src, "5") then 14 else sk_to_cik(symKind)
    val te = JVobj(list_cons(jpr("range", rng), list_cons(jpr("newText", JVstr name), list_nil())))
    val item = JVobj(
      list_cons(jpr("label", JVstr name), list_cons(jpr("kind", JVint cik),
      list_cons(jpr("detail", JVstr detail), list_cons(jpr("sortText", JVstr (strn_append(src, name))),
      list_cons(jpr("textEdit", te), list_nil()))))))
  in @(list_cons(item, items), list_cons(name, seen), cnt+1) end
  else st
end
// add a row list (#{name,kind,typ}) under a sortText tier.
fun add_rows(rows: list(jval), src: string, dsrc: string,
             rng: jval, wlow: string, wlen: sint, cap: sint, st: cst): cst =
  (case+ rows of
   | list_nil() => st
   | list_cons(s, r) =>
     if (st.2 < cap) then let
       val det = cand_detail(gi(s,"kind"), gs(s,"typ"), dsrc)
       val st1 = comp_add(gs(s,"name"), gi(s,"kind"), src, det, rng, wlow, wlen, cap, st)
     in add_rows(r, src, dsrc, rng, wlow, wlen, cap, st1) end
     else st)
// tier 0: in-scope locals (position-filtered).
fun add_scopes(scopes: list(jval), line: sint, ch: sint,
               rng: jval, wlow: string, wlen: sint, cap: sint, st: cst): cst =
  (case+ scopes of
   | list_nil() => st
   | list_cons(s, r) => let
       val inrange =
         if posLE(gi(s,"l0"),gi(s,"c0"),line,ch) then posLE(line,ch,gi(s,"l1"),gi(s,"c1")) else false
       val st1 =
         if inrange then let
           val det = if strn_eq(gs(s,"typ"), "") then "local" else gs(s,"typ")
         in comp_add(gs(s,"name"), 13, "0", det, rng, wlow, wlen, cap, st) end
         else st
     in add_scopes(r, line, ch, rng, wlow, wlen, cap, st1) end)
fun index_has(lst: list(@(string, idxrec)), uri: string): bool =
  (case+ lst of list_nil() => false | list_cons(kv, r) => (if strn_eq(kv.0, uri) then true else index_has(r, uri)))
// tier 2a: other open buffers' symbols.
fun add_other(idxlist: list(@(string, idxrec)), uri: string,
              rng: jval, wlow: string, wlen: sint, cap: sint, st: cst): cst =
  (case+ idxlist of
   | list_nil() => st
   | list_cons(kv, r) =>
     if (st.2 < cap) then let
       val st1 = if (if strn_eq(kv.0, uri) then false else true)
                 then add_rows((kv.1).4, "2", "project", rng, wlow, wlen, cap, st) else st
     in add_other(r, uri, rng, wlow, wlen, cap, st1) end
     else st)
// tier 2b: bg-indexed (unopened) files' symbols.
fun add_projc(projlist: list(@(string, projrec)), uri: string, idxlist: list(@(string, idxrec)),
              rng: jval, wlow: string, wlen: sint, cap: sint, st: cst): cst =
  (case+ projlist of
   | list_nil() => st
   | list_cons(kv, r) =>
     if (st.2 < cap) then let
       val u = (kv.1).0
       val skip = if strn_eq(u, uri) then true else index_has(idxlist, u)
       val st1 = if skip then st else add_rows((kv.1).1, "2", "project", rng, wlow, wlen, cap, st)
     in add_projc(r, uri, idxlist, rng, wlow, wlen, cap, st1) end
     else st)
// tier 5: keywords.
fun add_keywords(kws: list(string), rng: jval, wlow: string, wlen: sint, cap: sint, st: cst): cst =
  (case+ kws of
   | list_nil() => st
   | list_cons(kw, r) =>
     if (st.2 < cap) then let val st1 = comp_add(kw, 0, "5", "keyword", rng, wlow, wlen, cap, st)
                          in add_keywords(r, rng, wlow, wlen, cap, st1) end
     else st)
// member mode (recv.field): members whose END == the dot position.
fun mem_match(m: jval, dotLine: sint, dotCol: sint, seen: list(string), wlow: string, wlen: sint): bool =
  if (gi(m,"l1") = dotLine) then
    (if (gi(m,"c1") = dotCol) then
       (if seen_has(seen, gs(m,"name")) then false else ci_prefix(gs(m,"name"), wlow, wlen))
     else false)
  else false
fun mem_item(m: jval, rng: jval): jval = let
  val nm = gs(m,"name")
  val det = if strn_eq(gs(m,"typ"), "") then "field" else strn_append(": ", gs(m,"typ"))
  val te = JVobj(list_cons(jpr("range", rng), list_cons(jpr("newText", JVstr nm), list_nil())))
in
  JVobj(
    list_cons(jpr("label", JVstr nm), list_cons(jpr("kind", JVint 5),
    list_cons(jpr("detail", JVstr det), list_cons(jpr("sortText", JVstr (strn_append("0", nm))),
    list_cons(jpr("textEdit", te), list_nil()))))))
end
fun add_members(members: list(jval), dotLine: sint, dotCol: sint,
                rng: jval, wlow: string, wlen: sint, st: cst): cst =
  (case+ members of
   | list_nil() => st
   | list_cons(m, r) => let
       val st1 = if mem_match(m, dotLine, dotCol, st.1, wlow, wlen)
                 then @(list_cons(mem_item(m, rng), st.0), list_cons(gs(m,"name"), st.1), st.2)
                 else st
     in add_members(r, dotLine, dotCol, rng, wlow, wlen, st1) end)
//
(* ****** ****** *)
(* ---- workspace/symbol ---- *)
//
#typedef wst = @(list(jval), sint)
fun wst_empty((*void*)): wst = @(list_nil(), 0)
fun ws_item(s: jval, uri: string): jval = let
  val loc = JVobj(list_cons(jpr("uri", JVstr uri),
              list_cons(jpr("range", mkrange(gi(s,"l0"), gi(s,"c0"), gi(s,"l1"), gi(s,"c1"))), list_nil())))
in
  JVobj(
    list_cons(jpr("name", JVstr (gs(s,"name"))), list_cons(jpr("kind", JVint (gi(s,"kind"))),
    list_cons(jpr("location", loc), list_cons(jpr("containerName", JVstr (gs(s,"container"))), list_nil())))))
end
fun ws_items(syms: list(jval), uri: string, qlow: string, cap: sint, st: wst): wst =
  (case+ syms of
   | list_nil() => st
   | list_cons(s, r) =>
     if (st.1 >= cap) then st
     else let
       val st1 = if ws_fuzzy(qlow, gs(s,"name")) then @(list_cons(ws_item(s, uri), st.0), st.1+1) else st
     in ws_items(r, uri, qlow, cap, st1) end)
fun ws_index(idxlist: list(@(string, idxrec)), qlow: string, cap: sint, st: wst): wst =
  (case+ idxlist of
   | list_nil() => st
   | list_cons(kv, r) =>
     if (st.1 >= cap) then st
     else let val st1 = ws_items((kv.1).4, kv.0, qlow, cap, st) in ws_index(r, qlow, cap, st1) end)
fun ws_proj(projlist: list(@(string, projrec)), idxlist: list(@(string, idxrec)), qlow: string, cap: sint, st: wst): wst =
  (case+ projlist of
   | list_nil() => st
   | list_cons(kv, r) =>
     if (st.1 >= cap) then st
     else let
       val u = (kv.1).0
       val st1 = if index_has(idxlist, u) then st else ws_items((kv.1).1, u, qlow, cap, st)
     in ws_proj(r, idxlist, qlow, cap, st1) end)
//
(* ****** ****** *)
//
#implfun idx_query(uri, kind, a, b, c, d) = let
  val lk = idx_lookup(uri)
  val found = lk.0
  val rec = lk.1
in
  if (kind = 0) then build_hover(rec.0, a, b)
  else if (kind = 1) then build_def(rec.1, a, b)
  else if (kind = 2) then build_typedef(rec.1, a, b)
  else if (kind = 3) then build_references(rec.1, uri, a, b, c)
  else if (kind = 4) then build_highlights(rec.1, uri, a, b)
  else if (kind = 5) then build_inlays(rec.3, false, 0, 0, 0, 0)
  else if (kind = 6) then build_inlays(rec.3, true, a, b, c, d)
  else if (kind = 7) then build_semantic(rec.2)
  else if (kind = 8) then build_index_stats(found, rec)
  else if (kind = 9) then build_docsym(found, rec.4)
  else "null"
end
//
#implfun idx_workspace(query) = let
  val qlow = downcase_str(query)
  val s1 = ws_index(cell_get(the_index), qlow, 1000, wst_empty())
  val s2 = ws_proj(cell_get(the_proj), cell_get(the_index), qlow, 1000, s1)
in json_serialize(JVarr(list_reverse(s2.0))) end
//
#implfun idx_completion(uri, line, ch, word, isMember, dotLine, dotCol, wcol) = let
  val lk = idx_lookup(uri)
  val rec = lk.1
  val rng = JVobj(list_cons(jpr("start", mkpos(line, wcol)), list_cons(jpr("end", mkpos(line, ch)), list_nil())))
  val wlow = downcase_str(word)
  val wlen = str_len(wlow)
  val cap = the_complete_cap
  val items =
    if (isMember = 1) then let val mr = add_members(rec.6, dotLine, dotCol, rng, wlow, wlen, cst_empty()) in mr.0 end
    else let
      val s0 = add_scopes(rec.5, line, ch, rng, wlow, wlen, cap, cst_empty())
      val s1 = add_rows(rec.4, "1", "this file", rng, wlow, wlen, cap, s0)
      val s2 = add_other(cell_get(the_index), uri, rng, wlow, wlen, cap, s1)
      val s3 = add_projc(cell_get(the_proj), uri, cell_get(the_index), rng, wlow, wlen, cap, s2)
      val s4 = add_rows(cell_get(the_prelude), "3", "prelude", rng, wlow, wlen, cap, s3)
      val s5 = add_rows(cell_get(the_staload), "4", "staload", rng, wlow, wlen, cap, s4)
      val s6 = add_keywords(the_keywords, rng, wlow, wlen, cap, s5)
    in s6.0 end
in
  json_serialize(JVobj(list_cons(jpr("isIncomplete", JVbool true),
    list_cons(jpr("items", JVarr(list_reverse(items))), list_nil()))))
end
//
(* ****** ****** *)
(*
end of [language-server/server/resident/DATS/xats_lsp_index.dats]
*)
