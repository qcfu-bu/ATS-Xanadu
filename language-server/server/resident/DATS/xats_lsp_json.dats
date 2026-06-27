(* ****** ****** *)
(*
JSON value + parse/serialize — IMPLEMENTATION (portable ATS3).

Pure recursion over `jval` + sint char-code arithmetic + list building.  The only
backend dependency is four trivial LEAF primitives (string length / char-code-at /
string-of-code / int-to-text) — every backend has them (charCodeAt, fromCharCode,
String, length).  All PARSER LOGIC (the state machine, recursion, jval
construction) is portable ATS3.  Interface: SATS/xats_lsp_json.sats.

Working in char codes (sint) instead of the dialect's length-indexed `strn`/`cgtz`
keeps the parser on fully-portable types (sint, string, list) — plain `string`
indexes as static-length-0, which fails strn's bounds proof.
*)
(* ****** ****** *)
//
// portable: PRELUDE only (template impls for strn_append/list/sint), NOT the compiler.
#staload _ = "prelude/DATS/gdbg000.dats"
#include "prelude/HATS/prelude_dats.hats"
#include "prelude/HATS/prelude_JS_dats.hats"
//
#staload "./../SATS/xats_lsp_json.sats"
//
// leaf primitives (backend-provided; trivial one-liners on every runtime).
#extern fun int2str(n: sint): string = $extnam()       // sint -> decimal text
#extern fun str_len(s: string): sint = $extnam()       // # of code units
#extern fun str_char_code(s: string, i: sint): sint = $extnam() // code unit at i (caller bounds-checks)
#extern fun str_of_code(c: sint): string = $extnam()   // 1-char string from a code
//
// string BUILDER (O(1) amortized append) — the parse/serialize hot paths build
// big strings (didOpen/didChange file text, semanticTokens arrays); char-by-char
// `strn_append` re-materializes the whole accumulator each call => O(n^2).  A
// backend buffer (Chez output-string-port; JS array+join; native byte-buffer)
// keeps them O(n).  (`sbuf` abstype is declared in the .sats — abstype decls
// aren't allowed in a .dats.)
#extern fun sb_new((*void*)): sbuf = $extnam()
#extern fun sb_str(b: sbuf, s: string): void = $extnam()   // append a whole string
#extern fun sb_code(b: sbuf, c: sint): void = $extnam()    // append one char by code
#extern fun sb_get(b: sbuf): string = $extnam()            // materialize (once)
//
(* ****** ****** *)
//
// ASCII code legend (avoids the dialect's `char` literal type entirely):
//   34 "   92 \   47 /   123 {   125 }   91 [   93 ]   44 ,   58 :
//   32 sp  9 tab   10 nl  13 cr  48 '0'  57 '9'  45 -   43 +   46 .
//   101 e  69 E   97 a  102 f  122 z  65 A  70 F
//   116 t  110 n  117 u  114 r
//
fun json_isws(c: sint): bool =
  if (c = 32) then true else if (c = 9) then true else if (c = 10) then true else (c = 13)
fun json_isdigit(c: sint): bool = if (c >= 48) then (c <= 57) else false
fun json_ishexlo(c: sint): bool = if (c >= 97) then (c <= 102) else false
fun json_ishexhi(c: sint): bool = if (c >= 65) then (c <= 70) else false
fun json_isnumtail(c: sint): bool =
  if (c = 46) then true else if (c = 101) then true else if (c = 69) then true
  else if (c = 43) then true else if (c = 45) then true else json_isdigit(c)
//
(* ****** ****** *)
(* ---- serialize ---- *)
//
// escape one char into the buffer (extracted so json_esc_into's loop stays flat).
fun
json_esc_char(b: sbuf, c: sint): void =
  if (c = 34) then sb_str(b, "\\\"")
  else if (c = 92) then sb_str(b, "\\\\")
  else if (c = 10) then sb_str(b, "\\n")
  else if (c = 13) then sb_str(b, "\\r")
  else if (c = 9) then sb_str(b, "\\t")
  else sb_code(b, c)
// write a JSON-quoted, escaped string into the buffer (O(n)).
fun
json_esc_into(b: sbuf, s: string): void = let
  val n = str_len(s)
  fun loop(i: sint): void =
    if (i >= n) then () else (json_esc_char(b, str_char_code(s, i)); loop(i+1))
in
  (sb_code(b, 34); loop(0); sb_code(b, 34))
end
//
// serialize INTO the buffer (one buffer threaded through the whole tree => O(n)).
fun
json_ser_into(b: sbuf, v: jval): void =
(
case+ v of
| JVnull() => sb_str(b, "null")
| JVbool(t) => sb_str(b, (if t then "true" else "false"))
| JVint(n) => sb_str(b, int2str(n))
| JVstr(s) => json_esc_into(b, s)
| JVarr(xs) => (sb_code(b, 91); json_ser_arr(b, xs, 0); sb_code(b, 93))      (* [ ] *)
| JVobj(kvs) => (sb_code(b, 123); json_ser_obj(b, kvs, 0); sb_code(b, 125))  (* { } *)
)
and
json_ser_arr(b: sbuf, xs: list(jval), i: sint): void =
(
case+ xs of
| list_nil() => ()
| list_cons(x, rest) =>
  ((if (i > 0) then sb_code(b, 44) else ()); json_ser_into(b, x); json_ser_arr(b, rest, i+1))
)
and
json_ser_obj(b: sbuf, kvs: list(jpair), i: sint): void =
(
case+ kvs of
| list_nil() => ()
| list_cons(kv, rest) =>
  ((if (i > 0) then sb_code(b, 44) else ());
   json_esc_into(b, kv.0); sb_code(b, 58); json_ser_into(b, kv.1); json_ser_obj(b, rest, i+1))
)
//
(* ****** ****** *)
(* ---- parse (functional position threading over char codes) ---- *)
//
fun
json_skipws(s: string, n: sint, i: sint): sint =
  if (i < n) then (if json_isws(str_char_code(s, i)) then json_skipws(s, n, i+1) else i) else i
//
fun
json_hv(c: sint): sint =
  if json_isdigit(c) then (c - 48)
  else if json_ishexlo(c) then (c - 97 + 10)
  else if json_ishexhi(c) then (c - 65 + 10)
  else 0
fun
json_u4(s: string, i: sint): sint =
  (json_hv(str_char_code(s, i)) * 4096) + (json_hv(str_char_code(s, i+1)) * 256)
    + (json_hv(str_char_code(s, i+2)) * 16) + json_hv(str_char_code(s, i+3))
//
// parse a string literal: `i` at the opening quote (34); returns (text, pos-after).
fun
json_pstr(s: string, n: sint, i: sint): @(string, sint) = let
  val b = sb_new()
  // decode a backslash escape at `j` (s[j]=92) into `b`; return the next position.
  fun esc(j: sint): sint =
    if (j+1 >= n) then n
    else let val e = str_char_code(s, j+1) in
      if (e = 110) then (sb_code(b, 10); j+2)        (* \n *)
      else if (e = 116) then (sb_code(b, 9); j+2)    (* \t *)
      else if (e = 114) then (sb_code(b, 13); j+2)   (* \r *)
      else if (e = 34) then (sb_code(b, 34); j+2)    (* \" *)
      else if (e = 92) then (sb_code(b, 92); j+2)    (* \\ *)
      else if (e = 47) then (sb_code(b, 47); j+2)    (* \/ *)
      else if (e = 117) then (if (j+5 < n) then (sb_code(b, json_u4(s, j+2)); j+6) else n)  (* \uXXXX *)
      else (sb_code(b, e); j+2)
    end
  // scan to the closing quote, writing decoded content into `b`; return pos-after.
  fun loop(j: sint): sint =
    if (j >= n) then j
    else let val c = str_char_code(s, j) in
      if (c = 34) then j+1
      else if (c = 92) then loop(esc(j))
      else (sb_code(b, c); loop(j+1))
    end
  val endpos = loop(i+1)
in
  @(sb_get(b), endpos)
end
//
// parse a number at `i`: integer magnitude as sint; sign honored; a
// fractional/exponent tail is consumed but its value discarded (LSP fields are integers).
fun
json_pnum(s: string, n: sint, i: sint): @(jval, sint) = let
  val neg = (if (i < n) then (str_char_code(s, i) = 45) else false)
  val i0 = (if neg then i+1 else i)
  fun
  digits(j: sint, acc: sint): @(sint, sint) =
    if (if (j < n) then json_isdigit(str_char_code(s, j)) else false)
    then digits(j+1, (acc * 10) + (str_char_code(s, j) - 48)) else @(acc, j)
  val mj = digits(i0, 0)
  val mag = mj.0
  fun
  skiptail(j: sint): sint =
    if (if (j < n) then json_isnumtail(str_char_code(s, j)) else false) then skiptail(j+1) else j
  val j1 = skiptail(mj.1)
in
  @(JVint(if neg then (0 - mag) else mag), j1)
end
//
fun
json_pval(s: string, n: sint, i0: sint): @(jval, sint) = let
  val i = json_skipws(s, n, i0)
in
  if (i >= n) then @(JVnull(), i) else let val c = str_char_code(s, i) in
    if (c = 123) then json_pobj(s, n, i)            (* { *)
    else if (c = 91) then json_parr(s, n, i)        (* [ *)
    else if (c = 34) then let val tj = json_pstr(s, n, i) in @(JVstr(tj.0), tj.1) end  (* " *)
    else if (c = 116) then @(JVbool(true), i+4)     (* t *)
    else if (c = 102) then @(JVbool(false), i+5)    (* f *)
    else if (c = 110) then @(JVnull(), i+4)         (* n *)
    else if (if (c = 45) then true else json_isdigit(c)) then json_pnum(s, n, i)
    else @(JVnull(), i+1)
  end
end
and
json_parr(s: string, n: sint, i: sint): @(jval, sint) = let
  fun
  loop(j0: sint, acc: list(jval)): @(jval, sint) = let
    val j = json_skipws(s, n, j0)
  in
    if (j >= n) then @(JVarr(list_reverse(acc)), j)
    else let val c = str_char_code(s, j) in
      if (c = 93) then @(JVarr(list_reverse(acc)), j+1)        (* ] *)
      else if (c = 44) then loop(j+1, acc)                     (* , *)
      else let val vk = json_pval(s, n, j) in loop(vk.1, list_cons(vk.0, acc)) end
    end
  end
in
  loop(i+1, list_nil())
end
and
json_pobj(s: string, n: sint, i: sint): @(jval, sint) = let
  fun
  loop(j0: sint, acc: list(jpair)): @(jval, sint) = let
    val j = json_skipws(s, n, j0)
  in
    if (j >= n) then @(JVobj(list_reverse(acc)), j)
    else let val c = str_char_code(s, j) in
      if (c = 125) then @(JVobj(list_reverse(acc)), j+1)       (* } *)
      else if (c = 44) then loop(j+1, acc)                     (* , *)
      else if (c = 34) then let                                (* " : start of a key *)
        val kk = json_pstr(s, n, j)
        val k1 = json_skipws(s, n, kk.1)
        val k2 = (if (if (k1 < n) then (str_char_code(s, k1) = 58) else false) then k1+1 else k1)
        val vk = json_pval(s, n, k2)
      in
        loop(vk.1, list_cons(@(kk.0, vk.0), acc))
      end
      else loop(j+1, acc)
    end
  end
in
  loop(i+1, list_nil())
end
//
(* ****** ****** *)
(* ---- public implementations ---- *)
//
#implfun json_serialize(v) = let val b = sb_new() val () = json_ser_into(b, v) in sb_get(b) end
#implfun json_parse(s) = (json_pval(s, str_len(s), 0)).0
//
#implfun jget(v, key) =
(
case+ v of
| JVobj(kvs) => let
    fun loop(xs: list(jpair)): jval =
      case+ xs of list_nil() => JVnull() | list_cons(kv, rest) => (if strn_eq(kv.0, key) then kv.1 else loop(rest))
  in loop(kvs) end
| _ => JVnull()
)
#implfun jget2(v, k1, k2) = jget(jget(v, k1), k2)
#implfun jget3(v, k1, k2, k3) = jget(jget(jget(v, k1), k2), k3)
#implfun jas_str(v, dflt) = (case+ v of JVstr(s) => s | _ => dflt)
#implfun jas_int(v, dflt) = (case+ v of JVint(n) => n | _ => dflt)
#implfun jas_bool(v) = (case+ v of JVbool(b) => b | _ => false)
#implfun jas_arr(v) = (case+ v of JVarr(xs) => xs | _ => list_nil())
#implfun jis_obj(v) = (case+ v of JVobj(_) => true | _ => false)
//
(* ****** ****** *)
(*
end of [language-server/server/resident/DATS/xats_lsp_json.dats]
*)
