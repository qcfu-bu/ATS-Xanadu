(* ****** ****** *)
(*
Dedup + position-sort for harvested LSP items — IMPLEMENTATION (portable ATS3).

Pure list + jval work: a growing seen-list for dedup (item counts are per-file
small, so O(n^2) membership is fine), a stable insertion sort driven by a field
spec (no higher-order fn needed — the comparator reads field names).  Interface:
SATS/xats_lsp_dedup.sats.
*)
(* ****** ****** *)
//
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
//
#staload "./../SATS/xats_lsp_json.sats"
#staload "./../SATS/xats_lsp_dedup.sats"
//
#extern fun int2str(n: sint): string = $extnam()
//
(* ****** ****** *)
//
// a field's value rendered for a dedup key: int -> decimal, string as-is.
fun
jfield_str(v: jval, f: string): string =
(
case+ jget(v, f) of
| JVint(n) => int2str(n)
| JVstr(s) => s
| JVbool(b) => (if b then "true" else "false")
| _ => ""
)
//
// dedup key = join of the key fields, ':'-separated (mirrors LSP-num-cat).
fun
jkey(v: jval, fields: list(string)): string =
(
case+ fields of
| list_nil() => ""
| list_cons(f, rest) => strn_append(jfield_str(v, f), strn_append(":", jkey(v, rest)))
)
//
// is `k` already in the seen list?
fun
seen_has(seen: list(string), k: string): bool =
(
case+ seen of
| list_nil() => false
| list_cons(s, rest) => (if strn_eq(s, k) then true else seen_has(rest, k))
)
//
// keep first occurrence per key, preserving original order.
fun
dedup_first(items: list(jval), fields: list(string), seen: list(string)): list(jval) =
(
case+ items of
| list_nil() => list_nil()
| list_cons(x, rest) => let
    val k = jkey(x, fields)
  in
    if seen_has(seen, k) then dedup_first(rest, fields, seen)
    else list_cons(x, dedup_first(rest, fields, list_cons(k, seen)))
  end
)
//
// keep items whose start position is non-negative (l0>=0, c0>=0).
fun
filter_valid(items: list(jval)): list(jval) =
(
case+ items of
| list_nil() => list_nil()
| list_cons(x, rest) =>
  if (if (jas_int(jget(x, "l0"), (0 - 1)) >= 0) then (jas_int(jget(x, "c0"), (0 - 1)) >= 0) else false)
  then list_cons(x, filter_valid(rest))
  else filter_valid(rest)
)
//
(* ****** ****** *)
(* ---- stable sort by field spec ---- *)
//
// compare a,b by the spec: returns true iff a strictly precedes b.
fun
jbefore(a: jval, b: jval, spec: sortspec): bool =
(
case+ spec of
| list_nil() => false
| list_cons(fd, rest) => let
    val va = jas_int(jget(a, fd.0), 0)
    val vb = jas_int(jget(b, fd.0), 0)
  in
    if (va = vb) then jbefore(a, b, rest)
    else if fd.1 then (va < vb) else (va > vb)   (* fd.1 = ascending? *)
  end
)
//
// insert x into an already-sorted list, after equal elements (stable).
fun
sort_insert(x: jval, sorted: list(jval), spec: sortspec): list(jval) =
(
case+ sorted of
| list_nil() => list_cons(x, list_nil())
| list_cons(y, rest) =>
  if jbefore(x, y, spec) then list_cons(x, sorted)
  else list_cons(y, sort_insert(x, rest, spec))
)
//
fun
jsort(items: list(jval), spec: sortspec): list(jval) =
(
case+ items of
| list_nil() => list_nil()
| list_cons(x, rest) => sort_insert(x, jsort(rest, spec), spec)
)
//
(* ****** ****** *)
//
#implfun jdedup_sort(items, keyfields, spec) =
  jsort(dedup_first(filter_valid(items), keyfields, list_nil()), spec)
//
(* ****** ****** *)
(*
end of [language-server/server/resident/DATS/xats_lsp_dedup.dats]
*)
