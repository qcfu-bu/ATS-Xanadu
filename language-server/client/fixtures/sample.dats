(***********************************************************************)
(*  A sample ATS3 .dats file exercising the TextMate grammar.          *)
(*  Block comments (* nest *) like this in ATS.                        *)
(***********************************************************************)

//
#define ATS_PACKNAME "sample-pkg"
#include "./../HATS/header.hats"
#staload "./../SATS/xbasics.sats"
#staload UN = "prelude/SATS/unsafe.sats"
//
#typedef b0 = bool
#stacst0 the_answer: int
//

datatype mylist (a:t@ype) =
  | mylist_nil  (a) of ()
  | mylist_cons (a) of (a, mylist a)

fun
length {n:nat} (xs: mylist a): int =
(
case+ xs of
| mylist_nil () => 0
| mylist_cons (_, rest) => 1 + length (rest)
)

fn
square (x: int): int = x * x

val pi: double = 3.14159
val hex: uint = 0xDEADBEEF
val oct: int = 0755
val flt: double = 6.022e23
val ch: char = '\n'
val str: string = "hello\tworld\n"

#impltmp
g_print<bool> (b0) =
  if b0 then $showtype("true") else pstrn("false")

#impltmp
make_pair<a> (x, y) = $tup (x, y)

prfun
lemma {n:int} (): [n >= 0] void = ()

#typedef cmp (a:t@ype) = (a, a) -> int

val yes = true and no = false

//// everything below here is commented out to end of file
this is not real code and should all be comment-colored
val ignored = "still a comment"
