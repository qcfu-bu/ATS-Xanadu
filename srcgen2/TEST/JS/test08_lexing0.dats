(* ****** ****** *)
#include
"./../..\
/HATS/xatsopt_sats.hats"
#include
"./../..\
/HATS/xatsopt_dats.hats"
(* ****** ****** *)
#staload
"./../../SATS/locinfo.sats"
#staload
"./../../SATS/lexbuf0.sats"
(* ****** ****** *)
#include
"./../../DATS/locinfo.dats"
#include
"./../../DATS/locinfo_print0.dats"
#include
"./../../DATS/lexbuf0.dats"
#include
"./../../DATS/lexbuf0_cstrx1.dats"
#include
"./../../DATS/lexbuf0_cstrx2.dats"
(* ****** ****** *)
#include
"./../../DATS/lexing0.dats"
#include
"./../../DATS/lexing0_print0.dats"
#include
"./../../DATS/lexing0_utils0.dats"
(* ****** ****** *)
//
val
csrc1 =
strx_vt_map0
(
strn_strxize
("H e l l o, w o r l d !")) where
{
#impltmp
map0$fopr
<char><sint>(cc) =
let
val ci = char_code(cc)
in//let
  if ci > 0 then ci else -1
end
} (*where*) // end of [strx_map0]
//
(* ****** ****** *)

val buf1 = lxbf1_make_cstrx(csrc1)

(* ****** ****** *)

val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))
val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))
val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))
val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))
val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))
val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))
val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))
val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))
val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))
val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))
val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))
val (  ) =
prerrln
("lexing(buf1) = ", lxbf1_lexing_tnode(buf1))

(* ****** ****** *)

val (  ) = prerrln("ALNUMq('a') = ", ALNUMq('a'))
val (  ) = prerrln("ALNUMq('z') = ", ALNUMq('z'))
val (  ) = prerrln("ALNUMq('0') = ", ALNUMq('0'))
val (  ) = prerrln("ALNUMq('9') = ", ALNUMq('9'))
val (  ) = prerrln("ALNUMq('_') = ", ALNUMq('_'))
val (  ) = prerrln("ALNUM_q('a') = ", ALNUM_q('a'))
val (  ) = prerrln("ALNUM_q('z') = ", ALNUM_q('z'))
val (  ) = prerrln("ALNUM_q('0') = ", ALNUM_q('0'))
val (  ) = prerrln("ALNUM_q('9') = ", ALNUM_q('9'))
val (  ) = prerrln("ALNUM_q('_') = ", ALNUM_q('_'))
val (  ) = prerrln("ALNUM_q('.') = ", ALNUM_q('.'))
val (  ) = prerrln("XDIGITq('0') = ", XDIGITq('0'))
val (  ) = prerrln("XDIGITq('a') = ", XDIGITq('a'))
val (  ) = prerrln("XDIGITq('f') = ", XDIGITq('f'))
val (  ) = prerrln("XDIGITq('g') = ", XDIGITq('g'))
val (  ) = prerrln("XDIGITq('A') = ", XDIGITq('A'))
val (  ) = prerrln("XDIGITq('F') = ", XDIGITq('F'))
val (  ) = prerrln("XDIGITq('G') = ", XDIGITq('G'))

(* ****** ****** *)

val (  ) = prerrln("IDFSTq('z') = ", IDFSTq( 'z' ))
val (  ) = prerrln("IDFSTq('X') = ", IDFSTq( 'X' ))
val (  ) = prerrln("IDFSTq('_') = ", IDFSTq( '_' ))
val (  ) = prerrln("IDFSTq('%') = ", IDFSTq( '%' ))
val (  ) = prerrln("IDSYMq('%') = ", IDSYMq( '%' ))
val (  ) = prerrln("IDSYMq(':') = ", IDSYMq( ':' ))
val (  ) = prerrln("IDSYMq('@') = ", IDSYMq( '@' ))
val (  ) = prerrln("IDSYMq('#') = ", IDSYMq( '#' ))
val (  ) = prerrln("IDSYMq('$') = ", IDSYMq( '$' ))
val (  ) = prerrln("IDFSTq('\'') = ", IDFSTq( '\'' ))
val (  ) = prerrln("IDRSTq('\'') = ", IDRSTq( '\'' ))

(* ****** ****** *)
//
val
csrc2 =
strx_vt_map0
(
strn_strxize
(
"(lexing(buf1) = , $LXBF.lxbf1_lexing_tnode(buf1))"
)
) where
{
#impltmp
map0$fopr
<char><sint>(cc) =
let
val ci = char_code(cc) in if ci > 0 then ci else -1
end
} (*where*) // end of [strx_map0]
//
val buf2 = lxbf1_make_cstrx(csrc2)
//
val (  ) =
prerrln("lexing(buf2) = ", lxbf1_lexing_tnodelst(buf2))
//
(* ****** ****** *)
//
val
csrc2 =
strx_vt_map0
(
strn_strxize
(
":<abcde>\"Hello, world!\"'\\000''\\a'bcd012"
)
) where
{
#impltmp
map0$fopr
<char><sint>(cc) =
let
val ci = char_code(cc) in if ci > 0 then ci else -1
end
} (*where*) // end of [strx_map0]
//
val buf2 = lxbf1_make_cstrx(csrc2)
//
val (  ) =
prerrln("lexing(buf2) = ", lxbf1_lexing_tnodelst(buf2))
//
(* ****** ****** *)

(* end of [ATS3/XATSOPT_TEST_JS_test08_lexing0.dats] *)
