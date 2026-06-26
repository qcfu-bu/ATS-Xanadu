(* ****** ****** *)
(*
Project staload graph — IMPLEMENTATION (portable ATS3).

Pure string + list + sint work behind cells: a path normalizer (split on '/',
drop ''/'.', '..' pops, leading '/'), a directory helper, the #staload/#include/
#dynload scanner (char codes, no regex), and the forward/reverse path graphs as
assoc-lists of (path -> path-set).  Mirrors the Scheme glue's LSP_norm /
LSP_parse_staloads / LSP_proj_* byte-for-byte.  Interface: SATS/xats_lsp_proj.sats.
*)
(* ****** ****** *)
//
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
//
#staload "./../SATS/xats_lsp_proj.sats"
//
#include "./../HATS/xats_lsp_ref.hats"
//
(* ****** ****** *)
//
// leaves: int->text + the 3 string primitives + the prelude classifier (glue).
#extern fun int2str(n: sint): string = $extnam()
#extern fun str_len(s: string): sint = $extnam()
#extern fun str_char_code(s: string, i: sint): sint = $extnam()
#extern fun str_of_code(c: sint): string = $extnam()
#extern fun JS_path_is_prelude(path: string): bool = $extnam()
//
(* ****** ****** *)
//
#typedef pset = list(string)                       // a set of paths (deduped list)
#typedef pmap = list(@(string, pset))              // path -> path-set
//
val the_fwd: lspcell(pmap) = cell_make(list_nil())     // path -> its staload targets
val the_rev: lspcell(pmap) = cell_make(list_nil())     // path -> its dependents
val the_indexed: lspcell(pset) = cell_make(list_nil())
//
(* ****** ****** *)
(* ---- string + set + map helpers ---- *)
//
fun str_eq_at(s: string, i: sint, sub: string): bool = let
  val ns = str_len(s) val nb = str_len(sub)
  fun loop(k: sint): bool =
    if (k >= nb) then true
    else if (str_char_code(s, i+k) = str_char_code(sub, k)) then loop(k+1) else false
in
  if (i + nb > ns) then false else loop(0)
end
//
fun set_has(s: pset, x: string): bool =
  (case+ s of list_nil() => false | list_cons(y, r) => (if strn_eq(y, x) then true else set_has(r, x)))
fun set_add(s: pset, x: string): pset = (if set_has(s, x) then s else list_cons(x, s))
fun set_del(s: pset, x: string): pset =
  (case+ s of list_nil() => list_nil() | list_cons(y, r) => (if strn_eq(y, x) then set_del(r, x) else list_cons(y, set_del(r, x))))
//
fun map_get(m: pmap, k: string): pset =
  (case+ m of list_nil() => list_nil() | list_cons(kv, r) => (if strn_eq(kv.0, k) then kv.1 else map_get(r, k)))
fun map_has(m: pmap, k: string): bool =
  (case+ m of list_nil() => false | list_cons(kv, r) => (if strn_eq(kv.0, k) then true else map_has(r, k)))
fun map_put(m: pmap, k: string, v: pset): pmap =
  (case+ m of
   | list_nil() => list_cons(@(k, v), list_nil())
   | list_cons(kv, r) => (if strn_eq(kv.0, k) then list_cons(@(k, v), r) else list_cons(kv, map_put(r, k, v))))
fun map_del(m: pmap, k: string): pmap =
  (case+ m of
   | list_nil() => list_nil()
   | list_cons(kv, r) => (if strn_eq(kv.0, k) then r else list_cons(kv, map_del(r, k))))
fun map_size(m: pmap): sint = (case+ m of list_nil() => 0 | list_cons(_, r) => 1 + map_size(r))
//
(* ****** ****** *)
(* ---- path normalization (matches glue LSP_norm on an absolute path) ---- *)
//
// build s[a, b) one code at a time (paths are short).
fun str_slice(s: string, a: sint, b: sint, acc: string): string =
  if (a >= b) then acc else str_slice(s, a+1, b, strn_append(acc, str_of_code(str_char_code(s, a))))
//
// split a path on '/' (code 47) into segments (in order).
fun split_slash(s: string, i: sint, n: sint, start: sint, acc: list(string)): list(string) =
  if (i >= n) then list_reverse(list_cons(str_slice(s, start, n, ""), acc))
  else if (str_char_code(s, i) = 47)
       then split_slash(s, i+1, n, i+1, list_cons(str_slice(s, start, i, ""), acc))
       else split_slash(s, i+1, n, start, acc)
//
// collapse: drop ""/".", ".." pops the previous kept segment.  `out` is reversed.
fun norm_pop(out: list(string)): list(string) =
  (case+ out of list_nil() => list_nil() | list_cons(_, o) => o)
fun seg_kind(seg: string): sint =   // 0 = drop, 1 = pop, 2 = keep
  if (if strn_eq(seg, "") then true else strn_eq(seg, ".")) then 0
  else if strn_eq(seg, "..") then 1 else 2
fun norm_collapse(segs: list(string), out: list(string)): list(string) =
  (case+ segs of
   | list_nil() => out
   | list_cons(seg, rest) => let
       val k = seg_kind(seg)
     in
       if (k = 0) then norm_collapse(rest, out)
       else if (k = 1) then norm_collapse(rest, norm_pop(out))
       else norm_collapse(rest, list_cons(seg, out))
     end)
//
// join kept segments (given reversed) as "/a/b/c".
fun join_segs(rev: list(string)): string = let
  fun go(xs: list(string), acc: string): string =
    (case+ xs of list_nil() => acc | list_cons(x, r) => go(r, strn_append("/", strn_append(x, acc))))
in
  let val s = go(rev, "") in (if strn_eq(s, "") then "/" else s) end
end
//
fun path_norm(p: string): string =
  if strn_eq(p, "") then ""
  else join_segs(norm_collapse(split_slash(p, 0, str_len(p), 0, list_nil()), list_nil()))
//
// dirname: prefix up to the last '/' ("." if none, "/" if at index 0).
fun last_slash(s: string, i: sint, found: sint): sint =
  if (i < 0) then found
  else if (str_char_code(s, i) = 47) then i else last_slash(s, i-1, found)
fun path_dirname(p: string): string = let
  val i = last_slash(p, str_len(p) - 1, (0 - 1))
in
  if (i < 0) then "." else if (i = 0) then "/" else str_slice(p, 0, i, "")
end
//
(* ****** ****** *)
(* ---- staload/include/dynload scanner ---- *)
//
fun is_directive(text: string, i: sint): bool =
  if str_eq_at(text, i, "#staload") then true
  else if str_eq_at(text, i, "#include") then true
  else str_eq_at(text, i, "#dynload")
//
// resolve a quoted ref against dir, normalize, drop prelude; cons onto acc.
fun resolve_ref(dir: string, ref: string, acc: pset): pset = let
  val abs =
    if (if (str_len(ref) > 0) then (str_char_code(ref, 0) = 47) else false) then ref
    else strn_append(dir, strn_append("/", ref))
  val nn = path_norm(abs)
in
  if (if strn_eq(nn, "") then true else JS_path_is_prelude(nn)) then acc
  else list_cons(nn, acc)
end
//
// find the closing quote (code 34) from j; -1 if none before end.
fun find_quote(text: string, j: sint, n: sint): sint =
  if (j >= n) then (0 - 1)
  else if (str_char_code(text, j) = 34) then j else find_quote(text, j+1, n)
//
// from a directive at i: scan to the first quote before a newline.  Returns the
// next scan index (after the closing quote, or i+1 if no usable quote).
fun scan_directive(text: string, n: sint, dir: string, i: sint, j: sint, acc: pset): @(sint, pset) =
  if (if (j >= n) then true else (str_char_code(text, j) = 10)) then @(i+1, acc)
  else if (str_char_code(text, j) = 34) then let
    val e = find_quote(text, j+1, n)
  in
    if (e < 0) then @(i+1, acc)
    else @(e+1, resolve_ref(dir, str_slice(text, j+1, e, ""), acc))
  end
  else scan_directive(text, n, dir, i, j+1, acc)
//
fun parse_loop(text: string, n: sint, dir: string, i: sint, acc: pset): pset =
  if (i >= n) then list_reverse(acc)
  else if (if (str_char_code(text, i) = 35) then is_directive(text, i) else false) then let
    val r = scan_directive(text, n, dir, i, i+8, acc)
  in
    parse_loop(text, n, dir, r.0, r.1)
  end
  else parse_loop(text, n, dir, i+1, acc)
//
fun parse_staloads(filePath: string, text: string): pset =
  parse_loop(text, str_len(text), path_dirname(filePath), 0, list_nil())
//
(* ****** ****** *)
(* ---- graph maintenance ---- *)
//
// remove all of `from`'s forward edges (and the matching back-edges).
fun unlink_one(rev: pmap, from: string, targets: pset): pmap =
  (case+ targets of
   | list_nil() => rev
   | list_cons(to, rest) => let
       val back = set_del(map_get(rev, to), from)
       val rev1 = (if (case+ back of list_nil() => true | _ => false) then map_del(rev, to) else map_put(rev, to, back))
     in unlink_one(rev1, from, rest) end)
fun proj_unlink(from: string): void = let
  val olds = map_get(cell_get(the_fwd), from)
  val () = cell_set(the_rev, unlink_one(cell_get(the_rev), from, olds))
in
  cell_set(the_fwd, map_del(cell_get(the_fwd), from))
end
//
// add `from -> each target` back-edges into rev.
fun link_back(rev: pmap, from: string, targets: pset): pmap =
  (case+ targets of
   | list_nil() => rev
   | list_cons(to, rest) => link_back(map_put(rev, to, set_add(map_get(rev, to), from)), from, rest))
//
// dedup a path list into a set (preserving first occurrence).
fun to_set(xs: pset, seen: pset): pset =
  (case+ xs of
   | list_nil() => list_nil()
   | list_cons(x, r) => (if set_has(seen, x) then to_set(r, seen) else list_cons(x, to_set(r, list_cons(x, seen)))))
//
#implfun proj_index_file(path, text) = let
  val n = path_norm(path)
in
  if (if strn_eq(n, "") then true else JS_path_is_prelude(n)) then ""
  else let
    val () = proj_unlink(n)
    val targets = to_set(parse_staloads(n, text), list_nil())
    val () =
      (case+ targets of
       | list_nil() => ()
       | _ => let
           val () = cell_set(the_rev, link_back(cell_get(the_rev), n, targets))
         in cell_set(the_fwd, map_put(cell_get(the_fwd), n, targets)) end)
    val () = cell_set(the_indexed, set_add(cell_get(the_indexed), n))
  in n end
end
//
#implfun proj_remove_file(path) = let
  val n = path_norm(path)
in
  if strn_eq(n, "") then ()
  else let
    val () = proj_unlink(n)
  in cell_set(the_indexed, set_del(cell_get(the_indexed), n)) end
end
//
(* ****** ****** *)
(* ---- reverse closure (BFS over the dependents graph) ---- *)
//
fun add_new(deps: pset, seen: pset, out: pset, fresh: pset): @(pset, pset, pset) =
  (case+ deps of
   | list_nil() => @(seen, out, fresh)
   | list_cons(d, rest) =>
     if set_has(seen, d) then add_new(rest, seen, out, fresh)
     else add_new(rest, list_cons(d, seen), list_cons(d, out), list_cons(d, fresh)))
fun bfs(rev: pmap, stack: pset, seen: pset, out: pset): pset =
  (case+ stack of
   | list_nil() => out
   | list_cons(cur, rest) => let
       val r = add_new(map_get(rev, cur), seen, out, list_nil())
       // r.0 = seen', r.1 = out', r.2 = freshly-found -> push before rest
       fun app(a: pset, b: pset): pset = (case+ a of list_nil() => b | list_cons(x, t) => list_cons(x, app(t, b)))
     in bfs(rev, app(r.2, rest), r.0, r.1) end)
fun join_nl(xs: pset, first: bool, acc: string): string =
  (case+ xs of
   | list_nil() => acc
   | list_cons(x, r) => join_nl(r, false, (if first then x else strn_append(acc, strn_append("\n", x)))))
//
#implfun proj_rev_closure(path) = let
  val start = path_norm(path)
in
  if strn_eq(start, "") then ""
  else let
    val out = bfs(cell_get(the_rev), list_cons(start, list_nil()), list_cons(start, list_nil()), list_nil())
  in join_nl(list_reverse(out), true, "") end
end
//
#implfun proj_fwd_count() = map_size(cell_get(the_fwd))
#implfun proj_rev_count() = map_size(cell_get(the_rev))
//
(* ****** ****** *)
(*
end of [language-server/server/resident/DATS/xats_lsp_proj.dats]
*)
