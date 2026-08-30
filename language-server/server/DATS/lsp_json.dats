(* ****** ****** *)
(*
lsp_json.dats — JSON parse/serialize in pure ATS3.  See lsp_json.sats.

Conventions:
- all indices are BYTE indices; byte_at yields 0..255 codes;
- parser functions return @(jval, sint) = (value-or-JVerr, next index);
- string building goes through strn_make_fwork ONCE per built string
  (O(n)); the serializer emits the whole document in ONE pass;
- helpers are defined BEFORE their users (top-level funs do not
  forward-reference in this dialect).
*)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
#include
"prelude/HATS/prelude_dats.hats"
#include
"prelude/HATS/prelude_GO_dats.hats"
(* ****** ****** *)
#include
"./../HATS/lspserver_sats.hats"
(* ****** ****** *)
(* parsing: small pure scanners *)
(* ****** ****** *)
//
fun
p_ws
(s0: string, i0: sint, n0: sint): sint =
if (i0 >= n0) then i0 else
let
val c0 = byte_at(s0, i0)
in
if (c0 = 32) then p_ws(s0, i0+1, n0) else
if (c0 = 9) then p_ws(s0, i0+1, n0) else
if (c0 = 10) then p_ws(s0, i0+1, n0) else
if (c0 = 13) then p_ws(s0, i0+1, n0) else i0
end//endof[p_ws]
//
(* index of the closing quote, scanning from i0; -1 if unterminated *)
fun
p_str_end
(s0: string, i0: sint, n0: sint): sint =
if (i0 >= n0) then (0 - 1) else
let
val c0 = byte_at(s0, i0)
in
if (c0 = 34) then i0 else
if (c0 = 92)
then
(if (i0+1 >= n0) then (0 - 1) else p_str_end(s0, i0+2, n0))
else p_str_end(s0, i0+1, n0)
end//endof[p_str_end]
//
fun
hexval(c0: sint): sint =
if (c0 >= 48)
then
(
if (c0 <= 57) then c0 - 48 else
if (c0 >= 97)
then (if (c0 <= 102) then c0 - 87 else (0 - 1))
else
if (c0 >= 65)
then (if (c0 <= 70) then c0 - 55 else (0 - 1)) else (0 - 1))
else (0 - 1)
//
(* value of the 4 hex digits at k0 (caller ensured k0+4 <= bound); -1 if bad *)
fun
hex4
(s0: string, k0: sint): sint =
let
val h1 = hexval(byte_at(s0, k0))
val h2 = hexval(byte_at(s0, k0+1))
val h3 = hexval(byte_at(s0, k0+2))
val h4 = hexval(byte_at(s0, k0+3))
in
if (h1 < 0) then (0 - 1) else
if (h2 < 0) then (0 - 1) else
if (h3 < 0) then (0 - 1) else
if (h4 < 0) then (0 - 1) else
h1*4096 + h2*256 + h3*16 + h4
end//endof[hex4]
//
(* UTF-8-encode the codepoint cp into the emit sink *)
fun
emit_u8
(emit: cgtz -> void, cp: sint): void =
if (cp < 128) then emit(char_make_sint(cp)) else
if (cp < 2048)
then
let
val () = emit(char_make_sint(192 + cp/64))
in
emit(char_make_sint(128 + (cp - (cp/64)*64)))
end
else
if (cp < 65536)
then
let
val () = emit(char_make_sint(224 + cp/4096))
val m1 = cp - (cp/4096)*4096
val () = emit(char_make_sint(128 + m1/64))
in
emit(char_make_sint(128 + (m1 - (m1/64)*64)))
end
else
let
val () = emit(char_make_sint(240 + cp/262144))
val m1 = cp - (cp/262144)*262144
val () = emit(char_make_sint(128 + m1/4096))
val m2 = m1 - (m1/4096)*4096
val () = emit(char_make_sint(128 + m2/64))
in
emit(char_make_sint(128 + (m2 - (m2/64)*64)))
end
//
(*
decode the escaped payload bytes [i0, j0) of s0 (j0 = the closing
quote's index) into the emit sink.  Unknown escapes pass through
literally; malformed \u emits U+FFFD.
*)
fun
p_str_emit
(s0: string, i0: sint, j0: sint, emit: cgtz -> void): void =
if (i0 >= j0) then () else
let
val c0 = byte_at(s0, i0)
in
if (c0 = 92)
then
(
if (i0+1 >= j0) then () else
let
val e0 = byte_at(s0, i0+1)
in
if (e0 = 110) then (emit(char_make_sint(10)); p_str_emit(s0, i0+2, j0, emit)) else
if (e0 = 116) then (emit(char_make_sint(9)); p_str_emit(s0, i0+2, j0, emit)) else
if (e0 = 114) then (emit(char_make_sint(13)); p_str_emit(s0, i0+2, j0, emit)) else
if (e0 = 98) then (emit(char_make_sint(8)); p_str_emit(s0, i0+2, j0, emit)) else
if (e0 = 102) then (emit(char_make_sint(12)); p_str_emit(s0, i0+2, j0, emit)) else
if (e0 = 117) then p_str_emit_u(s0, i0, j0, emit)
else (emit(char_make_sint(e0)); p_str_emit(s0, i0+2, j0, emit))
end)
else (emit(char_make_sint(c0)); p_str_emit(s0, i0+1, j0, emit))
end//endof[p_str_emit]
//
(* the \uXXXX (and surrogate-pair) case; i0 is at the backslash *)
and
p_str_emit_u
(s0: string, i0: sint, j0: sint, emit: cgtz -> void): void =
if (i0+6 > j0)
then (emit_u8(emit, 65533)) else
let
val h0 = hex4(s0, i0+2)
in
if (h0 < 0) then (emit_u8(emit, 65533); p_str_emit(s0, i0+6, j0, emit)) else
if (h0 < 55296) then (emit_u8(emit, h0); p_str_emit(s0, i0+6, j0, emit)) else
if (h0 >= 56320)
then
(
if (h0 < 57344)
then (emit_u8(emit, 65533); p_str_emit(s0, i0+6, j0, emit))
else (emit_u8(emit, h0); p_str_emit(s0, i0+6, j0, emit)))
else
(* high surrogate: expect \uXXXX low next *)
(
if (i0+12 > j0)
then (emit_u8(emit, 65533); p_str_emit(s0, i0+6, j0, emit))
else
if (byte_at(s0, i0+6) = 92)
then
(
if (byte_at(s0, i0+7) = 117)
then
let
val h1 = hex4(s0, i0+8)
in
if (h1 < 56320)
then (emit_u8(emit, 65533); p_str_emit(s0, i0+6, j0, emit))
else
if (h1 >= 57344)
then (emit_u8(emit, 65533); p_str_emit(s0, i0+6, j0, emit))
else
(
emit_u8
(emit, 65536 + (h0 - 55296)*1024 + (h1 - 56320))
; p_str_emit(s0, i0+12, j0, emit))
end
else (emit_u8(emit, 65533); p_str_emit(s0, i0+6, j0, emit)))
else (emit_u8(emit, 65533); p_str_emit(s0, i0+6, j0, emit)))
end//endof[p_str_emit_u]
//
(* decode the payload [i0, j0) into a fresh string *)
fun
p_str_decode
(s0: string, i0: sint, j0: sint): string =
strn_make_fwork(lam(emit) => p_str_emit(s0, i0, j0, emit))
//
(* ****** ****** *)
(* parsing: the value grammar *)
(* ****** ****** *)
//
fun
p_val
(s0: string, i0: sint, n0: sint): @(jval, sint) =
let
val i1 = p_ws(s0, i0, n0)
in
if (i1 >= n0) then @(JVerr(), i1) else
let
val c0 = byte_at(s0, i1)
in
if (c0 = 123) then p_obj(s0, i1+1, n0) else
if (c0 = 91) then p_arr(s0, i1+1, n0) else
if (c0 = 34) then p_qstr(s0, i1+1, n0) else
if strn_starts_at(s0, i1, "true") then @(JVtrue(), i1+4) else
if strn_starts_at(s0, i1, "false") then @(JVfalse(), i1+5) else
if strn_starts_at(s0, i1, "null") then @(JVnull(), i1+4) else
p_num(s0, i1, n0)
end
end//endof[p_val]
//
(* i0 is just past the opening quote *)
and
p_qstr
(s0: string, i0: sint, n0: sint): @(jval, sint) =
let
val j0 = p_str_end(s0, i0, n0)
in
if (j0 < 0)
then @(JVerr(), n0)
else @(JVstr(p_str_decode(s0, i0, j0)), j0+1)
end//endof[p_qstr]
//
and
p_num
(s0: string, i0: sint, n0: sint): @(jval, sint) =
let
fun
digs(k0: sint): sint =
if (k0 >= n0) then k0 else
let
val c0 = byte_at(s0, k0)
in
if (c0 < 48) then k0 else if (c0 > 57) then k0 else digs(k0+1)
end
fun
numtail(k0: sint): sint =
if (k0 >= n0) then k0 else
let
val c0 = byte_at(s0, k0)
in
if (c0 >= 48)
then (if (c0 <= 57) then numtail(k0+1) else k0)
else
if (c0 = 46) then numtail(k0+1) else
if (c0 = 101) then numtail(k0+1) else
if (c0 = 69) then numtail(k0+1) else
if (c0 = 43) then numtail(k0+1) else
if (c0 = 45) then numtail(k0+1) else k0
end
val neg = (byte_at(s0, i0) = 45)
val a0 = (if neg then i0+1 else i0): sint
val a1 = digs(a0)
in
if (a1 = a0) then @(JVerr(), i0) else
let
val z0 = numtail(a1)
fun
acc(k0: sint, v0: sint): sint =
if (k0 >= a1) then v0 else acc(k0+1, v0*10 + (byte_at(s0, k0) - 48))
in
if (z0 = a1)
then
(
if neg
then @(JVint(0 - acc(a0, 0)), a1)
else @(JVint(acc(a0, 0)), a1))
else @(JVnum(strn_slice(s0, i0, z0)), z0)
end
end//endof[p_num]
//
(* i0 is just past the '[' *)
and
p_arr
(s0: string, i0: sint, n0: sint): @(jval, sint) =
let
val i1 = p_ws(s0, i0, n0)
in
if (i1 >= n0) then @(JVerr(), i1) else
if (byte_at(s0, i1) = 93)
then @(JVarr(JVLnil()), i1+1)
else p_arr_items(s0, i1, n0)
end//endof[p_arr]
//
and
p_arr_items
(s0: string, i0: sint, n0: sint): @(jval, sint) =
let
val r0 = p_val(s0, i0, n0)
in
case+ r0.0 of
| JVerr() => @(JVerr(), r0.1)
| _(*value*) => p_arr_tail(s0, r0.0, r0.1, n0)
end//endof[p_arr_items]
//
and
p_arr_tail
(s0: string, v0: jval, i0: sint, n0: sint): @(jval, sint) =
let
val i1 = p_ws(s0, i0, n0)
in
if (i1 >= n0) then @(JVerr(), i1) else
if (byte_at(s0, i1) = 44)
then
let
val r1 = p_arr_items(s0, i1+1, n0)
in
case+ r1.0 of
| JVarr(xs) => @(JVarr(JVLcons(v0, xs)), r1.1)
| _(*err*) => @(JVerr(), r1.1)
end
else
if (byte_at(s0, i1) = 93)
then @(JVarr(JVLcons(v0, JVLnil())), i1+1)
else @(JVerr(), i1)
end//endof[p_arr_tail]
//
(* i0 is just past the '{' *)
and
p_obj
(s0: string, i0: sint, n0: sint): @(jval, sint) =
let
val i1 = p_ws(s0, i0, n0)
in
if (i1 >= n0) then @(JVerr(), i1) else
if (byte_at(s0, i1) = 125)
then @(JVobj(JKVnil()), i1+1)
else p_obj_items(s0, i1, n0)
end//endof[p_obj]
//
and
p_obj_items
(s0: string, i0: sint, n0: sint): @(jval, sint) =
let
val i1 = p_ws(s0, i0, n0)
in
if (i1 >= n0) then @(JVerr(), i1) else
if (byte_at(s0, i1) = 34)
then
let
val rk = p_qstr(s0, i1+1, n0)
in
case+ rk.0 of
| JVstr(k0) => p_obj_colon(s0, k0, rk.1, n0)
| _(*err*) => @(JVerr(), rk.1)
end
else @(JVerr(), i1)
end//endof[p_obj_items]
//
and
p_obj_colon
(s0: string, k0: string, i0: sint, n0: sint): @(jval, sint) =
let
val i1 = p_ws(s0, i0, n0)
in
if (i1 >= n0) then @(JVerr(), i1) else
if (byte_at(s0, i1) = 58)
then
let
val rv = p_val(s0, i1+1, n0)
in
case+ rv.0 of
| JVerr() => @(JVerr(), rv.1)
| _(*value*) => p_obj_tail(s0, k0, rv.0, rv.1, n0)
end
else @(JVerr(), i1)
end//endof[p_obj_colon]
//
and
p_obj_tail
(s0: string, k0: string, v0: jval, i0: sint, n0: sint): @(jval, sint) =
let
val i1 = p_ws(s0, i0, n0)
in
if (i1 >= n0) then @(JVerr(), i1) else
if (byte_at(s0, i1) = 44)
then
let
val rr = p_obj_items(s0, i1+1, n0)
in
case+ rr.0 of
| JVobj(kvs) => @(JVobj(JKVcons(k0, v0, kvs)), rr.1)
| _(*err*) => @(JVerr(), rr.1)
end
else
if (byte_at(s0, i1) = 125)
then @(JVobj(JKVcons(k0, v0, JKVnil())), i1+1)
else @(JVerr(), i1)
end//endof[p_obj_tail]
//
(* ****** ****** *)
//
#implfun
json_parse
(s0) =
let
val r0 = p_val(s0, 0, strn_length(s0))
in
r0.0
end//endof[json_parse]
//
(* ****** ****** *)
(* serialization: ONE emit pass over the tree *)
(* ****** ****** *)
//
fun
jser_raw
(t0: string, emit: cgtz -> void): void =
let
val n0 = strn_length(t0)
fun
loop(k0: sint): void =
if (k0 >= n0) then () else
(emit(strn_get$at(t0, k0)); loop(k0+1))
in
loop(0)
end//endof[jser_raw]
//
fun
jser_hexd
(v0: sint, emit: cgtz -> void): void =
if (v0 < 10)
then emit(char_make_sint(48 + v0))
else emit(char_make_sint(87 + v0))
//
(* a JSON string literal: quotes + minimal escaping; UTF-8 passes through *)
fun
jser_qstr
(t0: string, emit: cgtz -> void): void =
let
val n0 = strn_length(t0)
fun
loop(k0: sint): void =
if (k0 >= n0) then () else
let
val c0 = byte_at(t0, k0)
val () =
(
if (c0 = 34) then (emit(char_make_sint(92)); emit(char_make_sint(34))) else
if (c0 = 92) then (emit(char_make_sint(92)); emit(char_make_sint(92))) else
if (c0 = 10) then (emit(char_make_sint(92)); emit(char_make_sint(110))) else
if (c0 = 13) then (emit(char_make_sint(92)); emit(char_make_sint(114))) else
if (c0 = 9) then (emit(char_make_sint(92)); emit(char_make_sint(116))) else
if (c0 < 32)
then
(
emit(char_make_sint(92)); emit(char_make_sint(117));
emit(char_make_sint(48)); emit(char_make_sint(48));
jser_hexd(c0/16, emit); jser_hexd(c0 - (c0/16)*16, emit))
else emit(char_make_sint(c0)))
in
loop(k0+1)
end
in
emit(char_make_sint(34)); loop(0); emit(char_make_sint(34))
end//endof[jser_qstr]
//
fun
jser_int
(x0: sint, emit: cgtz -> void): void =
let
fun
digits(v0: sint): void =
if (v0 <= 0) then () else
let
val () = digits(v0 / 10)
in
emit(char_make_sint(48 + (v0 - (v0/10)*10)))
end
in
if (x0 = 0) then emit('0') else
if (x0 < 0)
then (emit('-'); digits(0 - x0))
else digits(x0)
end//endof[jser_int]
//
fun
jser_val
(jv0: jval, emit: cgtz -> void): void =
case+ jv0 of
| JVerr() => jser_raw("null", emit)
| JVnull() => jser_raw("null", emit)
| JVtrue() => jser_raw("true", emit)
| JVfalse() => jser_raw("false", emit)
| JVint(x0) => jser_int(x0, emit)
| JVnum(t0) => jser_raw(t0, emit)
| JVstr(t0) => jser_qstr(t0, emit)
| JVarr(xs) =>
  (emit(char_make_sint(91)); jser_lst(xs, 0, emit); emit(char_make_sint(93)))
| JVobj(kvs) =>
  (emit(char_make_sint(123)); jser_kvs(kvs, 0, emit); emit(char_make_sint(125)))
//
and
jser_lst
(xs: jvlst, k0: sint, emit: cgtz -> void): void =
case+ xs of
| JVLnil() => ()
| JVLcons(x0, r0) =>
  let
  val () = (if (k0 > 0) then emit(char_make_sint(44)) else ())
  val () = jser_val(x0, emit)
  in
  jser_lst(r0, k0+1, emit)
  end
//
and
jser_kvs
(kvs: jkvlst, k0: sint, emit: cgtz -> void): void =
case+ kvs of
| JKVnil() => ()
| JKVcons(k1, v1, r0) =>
  let
  val () = (if (k0 > 0) then emit(char_make_sint(44)) else ())
  val () = jser_qstr(k1, emit)
  val () = emit(char_make_sint(58))
  val () = jser_val(v1, emit)
  in
  jser_kvs(r0, k0+1, emit)
  end
//
(* ****** ****** *)
//
#implfun
json_ser
(jv0) = strn_make_fwork(lam(emit) => jser_val(jv0, emit))
//
(* ****** ****** *)
(* accessors *)
(* ****** ****** *)
//
fun
jkv_find
(kvs: jkvlst, k0: string): jval =
case+ kvs of
| JKVnil() => JVerr()
| JKVcons(k1, v1, r0) =>
  (if streq(k1, k0) then v1 else jkv_find(r0, k0))
//
#implfun
jis_err
(jv0) =
(
case+ jv0 of JVerr() => true | _(*else*) => false)
//
#implfun
jobj_get
(jv0, k0) =
(
case+ jv0 of
| JVobj(kvs) => jkv_find(kvs, k0) | _(*else*) => JVerr())
//
#implfun
jget_str
(jv0, dflt) =
(
case+ jv0 of JVstr(t0) => t0 | _(*else*) => dflt)
//
#implfun
jget_int
(jv0, dflt) =
(
case+ jv0 of JVint(x0) => x0 | _(*else*) => dflt)
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_json.dats] *)
(***********************************************************************)
