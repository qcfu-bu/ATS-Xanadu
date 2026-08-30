(* ****** ****** *)
(*
lsp_util.dats — byte-level string helpers.  See lsp_util.sats.
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
//
#implfun
strn_slice
(s0, i0, j0) =
strn_make_fwork
( lam(emit) =>
  let
  fun
  loop(k0: sint): void =
  if (k0 >= j0) then () else
  let val () = emit(strn_get$at(s0, k0)) in loop(k0+1) end
  in loop(i0) end)
//
(* ****** ****** *)
//
#implfun
streq
(s1, s2) = (strn_cmp(s1, s2) = 0)
//
(* ****** ****** *)
//
#implfun
itoa(x0) =
strn_make_fwork
( lam(emit) =>
  let
  fun
  digits(v0: sint): void =
  if (v0 <= 0) then () else
  let
  val () = digits(v0 / 10)
  in emit(char_make_sint(48 + (v0 - (v0/10)*10))) end
  in
  if (x0 = 0) then emit('0') else
  if (x0 < 0) then let val () = emit('-') in digits(0 - x0) end
  else digits(x0)
  end)
//
(* ****** ****** *)
//
#implfun
byte_at
(s0, i0) = sint_make_char(strn_get$at(s0, i0))
//
(* ****** ****** *)
//
#implfun
strn_starts_at
(hay, i0, ndl) =
let
val nh = strn_length(hay)
val nn = strn_length(ndl)
fun
loop(k0: sint): bool =
if (k0 >= nn) then true else
if (strn_get$at(hay, i0+k0) = strn_get$at(ndl, k0))
then loop(k0+1) else false
in//let
if (i0 < 0) then false else
if (i0 + nn > nh) then false else loop(0)
end//endof[strn_starts_at]
//
(* ****** ****** *)
//
#implfun
strn_index_of
(hay, i0, ndl) =
let
val nh = strn_length(hay)
val nn = strn_length(ndl)
fun
loop(k0: sint): sint =
if (k0 + nn > nh) then (0 - 1) else
if strn_starts_at(hay, k0, ndl) then k0 else loop(k0+1)
in//let
if (i0 < 0) then loop(0) else loop(i0)
end//endof[strn_index_of]
//
(* ****** ****** *)
//
#implfun
atoi_at
(s0, i0) =
let
val n0 = strn_length(s0)
fun
loop(k0: sint, v0: sint): @(sint, sint) =
if (k0 >= n0) then @(v0, k0) else
let
val c0 = byte_at(s0, k0)
in
if (c0 < 48) then @(v0, k0) else
if (c0 > 57) then @(v0, k0) else loop(k0+1, v0*10 + (c0 - 48))
end
in//let
loop(i0, 0)
end//endof[atoi_at]
//
(* ****** ****** *)
//
#implfun
u16_units
(s0, i0, j0) =
let
fun
loop(k0: sint, acc: sint): sint =
if (k0 >= j0) then acc else
let
val c0 = byte_at(s0, k0)
in
if (c0 < 128) then loop(k0+1, acc+1) else
if (c0 < 192) then loop(k0+1, acc) (* stray continuation byte *) else
if (c0 < 224) then loop(k0+2, acc+1) else
if (c0 < 240) then loop(k0+3, acc+1)
else loop(k0+4, acc+2) (* astral: a surrogate pair *)
end
in//let
loop(i0, 0)
end//endof[u16_units]
//
(* ****** ****** *)
(***********************************************************************)
(* end of [lsp_util.dats] *)
(***********************************************************************)
