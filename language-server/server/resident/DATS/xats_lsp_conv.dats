(* ****** ****** *)
(*
Per-check conversion layer — IMPLEMENTATION (portable ATS3).

friendly (backtick-ident remap via a static typename table), def_in_current (uri
== the current document), and path2uri (reuse xats_lsp_uri's encoder + the
cur-document remap).  The current uri + normalized path live in two cells, set by
conv_set_cur.  Mirrors the Scheme glue's LSP_friendly / LSP_def_in_current /
LSP_path2uri byte-for-byte.  Interface: SATS/xats_lsp_conv.sats.
*)
(* ****** ****** *)
//
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
//
#staload "./../SATS/xats_lsp_conv.sats"
#staload "./../SATS/xats_lsp_uri.sats"        // lsp_path2uri (the file:// encoder)
#staload "./../SATS/xats_lsp_u16.sats"        // lsp_byte2utf16 (the byte->UTF-16 walk)
//
#include "./../HATS/xats_lsp_ref.hats"
//
(* ****** ****** *)
//
#extern fun str_len(s: string): sint = $extnam()
#extern fun str_char_code(s: string, i: sint): sint = $extnam()
#extern fun str_of_code(c: sint): string = $extnam()
#extern fun str_slice(s: string, a: sint, b: sint): string = $extnam()
#extern fun lsp_getenv(name: string): string = $extnam()
#extern fun lsp_fs_read(path: string): string = $extnam()        // file text, "" on error/empty
//
(* ****** ****** *)
//
#typedef ucache = list(@(string, @(sint, string)))     // norm-path -> (ascii?, text)
//
val the_cur_uri: lspcell(string) = cell_make("")       // editor uri of the doc under check
val the_cur_pnorm: lspcell(string) = cell_make("")     // its normalized fs path ("" = none)
val the_cur_text: lspcell(string) = cell_make("")      // source text of the doc under check
val the_cur_ascii: lspcell(sint) = cell_make(1)        // 1 = whole cur text is ASCII
val the_other: lspcell(ucache) = cell_make(list_nil()) // per-check other-file conv cache
//
// UTF-16 conversion on unless ATS3_LSP_UTF16=0 (read once at load).
val the_u16_on: sint =
  (if strn_eq(lsp_getenv("ATS3_LSP_UTF16"), "0") then 0 else 1)
//
(* ****** ****** *)
(* ---- path normalization (collapse ./.. on an abs path; matches glue LSP_norm) ---- *)
//
fun split_slash(s: string, i: sint, n: sint, start: sint, acc: list(string)): list(string) =
  if (i >= n) then list_reverse(list_cons(str_slice(s, start, n), acc))
  else if (str_char_code(s, i) = 47)
       then split_slash(s, i+1, n, i+1, list_cons(str_slice(s, start, i), acc))
       else split_slash(s, i+1, n, start, acc)
fun norm_pop(out: list(string)): list(string) =
  (case+ out of list_nil() => list_nil() | list_cons(_, o) => o)
fun seg_kind(seg: string): sint =                       // 0 drop, 1 pop, 2 keep
  if (if strn_eq(seg, "") then true else strn_eq(seg, ".")) then 0
  else if strn_eq(seg, "..") then 1 else 2
fun norm_collapse(segs: list(string), out: list(string)): list(string) =
  (case+ segs of
   | list_nil() => out
   | list_cons(seg, rest) => let val k = seg_kind(seg) in
       if (k = 0) then norm_collapse(rest, out)
       else if (k = 1) then norm_collapse(rest, norm_pop(out))
       else norm_collapse(rest, list_cons(seg, out)) end)
fun join_segs(rev: list(string)): string = let
  fun go(xs: list(string), acc: string): string =
    (case+ xs of list_nil() => acc | list_cons(x, r) => go(r, strn_append("/", strn_append(x, acc))))
in
  let val s = go(rev, "") in (if strn_eq(s, "") then "/" else s) end
end
fun path_norm(p: string): string =
  if strn_eq(p, "") then ""
  else join_segs(norm_collapse(split_slash(p, 0, str_len(p), 0, list_nil()), list_nil()))
//
(* ****** ****** *)
(* ---- string helpers ---- *)
//
fun startswith(s: string, pre: string): bool = let
  val np = str_len(pre) val ns = str_len(s)
  fun chk(i: sint): bool =
    if (i >= np) then true
    else if (i >= ns) then false
    else if (str_char_code(s, i) = str_char_code(pre, i)) then chk(i+1) else false
in chk(0) end
//
fun is_id_start(c: sint): bool =                        // A-Z a-z _
  if (if (c >= 65) then (c <= 90) else false) then true
  else if (if (c >= 97) then (c <= 122) else false) then true
  else if (c = 95) then true else false
fun is_id_char(c: sint): bool =                         // + 0-9 $
  if is_id_start(c) then true
  else if (if (c >= 48) then (c <= 57) else false) then true
  else if (c = 36) then true else false
//
(* ****** ****** *)
(* ---- friendly typename table (matches glue LSP_TYPENAME) ---- *)
//
#typedef tnmap = list(@(string, string))
fun tn(k: string, v: string, r: tnmap): tnmap = list_cons(@(k, v), r)
fun mk_typenames(): tnmap =
  tn("gint_type","int", tn("bool_type","bool", tn("char_type","char",
  tn("gflt_type","double", tn("xats_void_t","void", tn("string_i0_tx","string",
  tn("the_s2exp_strn0","string", tn("the_s2exp_sint0","int", tn("the_s2exp_uint0","uint",
  tn("the_s2exp_slint0","lint", tn("the_s2exp_ulint0","ulint", tn("the_s2exp_sllint0","llint",
  tn("the_s2exp_ullint0","ullint", tn("the_s2exp_sflt0","float", tn("the_s2exp_dflt0","double",
  tn("the_s2exp_list0","list", tn("the_s2exp_optn0","optn", tn("the_s2exp_lazy0","lazy",
  tn("the_s2exp_p1","ptr", tn("the_s2exp_p2","p2tr", tn("the_s2exp_bool0","bool",
  tn("the_s2exp_char0","char", tn("the_s2exp_void","void", tn("strn","string",
  tn("xats_sint_t","int", tn("xats_uint_t","uint", tn("xats_slint_t","lint", tn("xats_ulint_t","ulint",
  tn("xats_ssize_t","ssize", tn("xats_usize_t","usize", tn("xats_sllint_t","llint", tn("xats_ullint_t","ullint",
  tn("xats_strn_t","string", tn("xats_bool_t","bool", tn("xats_char_t","char", tn("xats_dflt_t","double",
  tn("p1tr_tbox","ptr", tn("p2tr_tbox","p2tr", tn("list_t0_i0_tx","list", tn("list_vt_i0_vx","list_vt",
  tn("optn_t0_i0_tx","optn", tn("optn_vt_i0_vx","optn_vt", tn("lazy_t0_tx","lazy", tn("lazy_vt_vx","lazy_vt",
  list_nil()))))))))))))))))))))))))))))))))))))))))))))
val the_typenames: tnmap = mk_typenames()
//
// lookup: @(found, friendly-name)
fun tn_lookup(m: tnmap, k: string): @(bool, string) =
  (case+ m of
   | list_nil() => @(false, "")
   | list_cons(kv, r) => (if strn_eq(kv.0, k) then @(true, kv.1) else tn_lookup(r, k)))
//
(* ****** ****** *)
//
// whole-text ASCII test (every codepoint < 128).
fun text_is_ascii(s: string): bool = let
  val n = str_len(s)
  fun loop(i: sint): bool =
    if (i >= n) then true
    else if (str_char_code(s, i) >= 128) then false else loop(i+1)
in loop(0) end
//
// byte col -> UTF-16 col given the text + its ascii flag (1=ascii => identity).
fun b2u_conv(text: string, ascii: sint, line: sint, col: sint): sint =
  if (ascii = 1) then col else lsp_byte2utf16(text, line, col)
//
// other-file cache lookup: @(found, ascii, text).
fun ucache_get(c: ucache, k: string): @(bool, sint, string) =
  (case+ c of
   | list_nil() => @(false, 1, "")
   | list_cons(kv, r) => (if strn_eq(kv.0, k) then @(true, (kv.1).0, (kv.1).1) else ucache_get(r, k)))
//
#implfun conv_set_cur(uri, path, text) = let
  val () = cell_set(the_cur_uri, uri)
  val () = cell_set(the_cur_pnorm, (if strn_eq(path, "") then "" else path_norm(path)))
  val () = cell_set(the_cur_text, text)
  val () = cell_set(the_cur_ascii, (if text_is_ascii(text) then 1 else 0))
in
  cell_set(the_other, list_nil())                       // per-check other-file cache reset
end
//
#implfun LSP_cur_b2u(line, col) =
  if (the_u16_on = 0) then col
  else if (col <= 0) then 0
  else b2u_conv(cell_get(the_cur_text), cell_get(the_cur_ascii), line, col)
//
#implfun LSP_other_b2u(path, line, col) =
  if (the_u16_on = 0) then col
  else if (col <= 0) then 0
  else let
    val n = path_norm(path)
  in
    if strn_eq(n, "") then col
    else let
      val hit = ucache_get(cell_get(the_other), n)
    in
      if hit.0 then b2u_conv(hit.2, hit.1, line, col)
      else let
        val text = lsp_fs_read(n)
        val asc = (if text_is_ascii(text) then 1 else 0)
        val () = cell_set(the_other, list_cons(@(n, @(asc, text)), cell_get(the_other)))
      in
        b2u_conv(text, asc, line, col)
      end
    end
  end
//
#implfun LSP_def_in_current(uri) = let
  val cu = cell_get(the_cur_uri)
in
  (if strn_eq(cu, "") then false else strn_eq(uri, cu))
end
//
#implfun LSP_path2uri(p) =
  if strn_eq(p, "") then ""
  else if startswith(p, "file://") then p
  else let
    val abs = (if (str_char_code(p, 0) = 47) then p else path_norm(p))
    val cu = cell_get(the_cur_uri)
    val cpn = cell_get(the_cur_pnorm)
  in
    if (if strn_eq(cu, "") then false else strn_eq(path_norm(abs), cpn)) then cu
    else lsp_path2uri(abs)
  end
//
(* ****** ****** *)
//
#implfun LSP_friendly(msg) = let
  val s = msg
  val n = str_len(s)
  val bt = str_of_code(96)                               // a single backtick "`"
  // advance from j over id-chars; returns the index of the first non-id char.
  fun scan_id(j: sint): sint =
    if (j >= n) then j
    else if is_id_char(str_char_code(s, j)) then scan_id(j+1) else j
  fun loop(i: sint, acc: string): string =
    if (i >= n) then acc
    else if (str_char_code(s, i) = 96) then
      (if (if (i+1 < n) then is_id_start(str_char_code(s, i+1)) else false) then let
         val j = scan_id(i+1)
       in
         if (if (j < n) then (str_char_code(s, j) = 96) else false) then let
           val look = tn_lookup(the_typenames, str_slice(s, i+1, j))
         in
           if look.0
             then loop(j+1, strn_append(acc, strn_append(bt, strn_append(look.1, bt))))
             else loop(i+1, strn_append(acc, bt))
         end
         else loop(i+1, strn_append(acc, bt))
       end
       else loop(i+1, strn_append(acc, bt)))
    else loop(i+1, strn_append(acc, str_of_code(str_char_code(s, i))))
in
  loop(0, "")
end
//
(* ****** ****** *)
(* ---- prelude-root classification (matches glue JS_path_is_prelude) ---- *)
//
// The loaded prelude/compiler tree lives ONLY under these $XATSHOME subdirs (NOT
// the whole repo) — so files merely living inside the repo (language-server/,
// frontend/) are NOT immutable.  Roots computed once at module load.
val the_xatshome: string =
  let val h = lsp_getenv("XATSHOME") in (if strn_eq(h, "") then "" else path_norm(h)) end
fun mk_roots(h: string): list(string) =
  if strn_eq(h, "") then list_nil()
  else list_cons(strn_append(h, "/prelude/"),
       list_cons(strn_append(h, "/srcgen1/"),
       list_cons(strn_append(h, "/srcgen2/"),
       list_cons(strn_append(h, "/xassets/"), list_nil()))))
val the_roots: list(string) = mk_roots(the_xatshome)
fun any_prefix(roots: list(string), sp: string): bool =
  (case+ roots of
   | list_nil() => false
   | list_cons(r, rr) => (if startswith(sp, r) then true else any_prefix(rr, sp)))
//
#implfun JS_path_is_prelude(path) =
  (case+ the_roots of
   | list_nil() => false
   | list_cons(_, _) => let val s = path_norm(path) in
       (if strn_eq(s, "") then false else any_prefix(the_roots, strn_append(s, "/"))) end)
//
(* ****** ****** *)
(*
end of [language-server/server/resident/DATS/xats_lsp_conv.dats]
*)
