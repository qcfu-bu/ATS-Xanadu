(* ****** ****** *)
(*
test73_strescape — GAP-2 (self-hosting): Go string-literal ESCAPING.
//
Exercises every escape path the string-literal emitter (i0strgo1 -> f0_strn)
must normalize from the ATS source rep to a valid Go double-quoted literal:
  - a SOURCE LINE-CONTINUATION  `"\<NL>foo"`  (the bug that broke test70:
    a backslash followed by a real newline -> DROP both),
  - the standard backslash escapes `\n` `\t` `\"` `\\` (already two source
    chars -> pass through unchanged, valid in Go too).
Output is deterministic + byte-equal-vs-JS (the differential oracle).
*)
(* ****** ****** *)
//
#include
"prelude/HATS/prelude_dats.hats"
//
#include
"prelude/HATS/prelude_JS_dats.hats"
//
(* ****** ****** *)
(* ****** ****** *)
//
// a line-continuation: the `\<NL>` is DROPPED, so this prints `ab\n`.
val () =
strn_print("a\
b\n")
//
// a literal tab + escaped quote + backslash.
val () =
strn_print("tab[\t]quote[\"]slash[\\]\n")
//
// newline escape only.
val () =
strn_print("line1\nline2\n")
//
(* ****** ****** *)
(* ****** ****** *)
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(* ****** ****** *)
//
(***********************************************************************)
(* end of [test73_strescape_xats2go.dats] *)
(***********************************************************************)
