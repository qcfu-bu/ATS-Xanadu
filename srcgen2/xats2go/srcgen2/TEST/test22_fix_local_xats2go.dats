(* ****** ****** *)
(*
M2.5: a LOCAL recursive closure via `fix`.  `fix f(x) => if x>0 then x*f(x-1)
else 1` is bound to a local lambda value and applied to 5 => 120.  This is the
surface that lowers to I1INSfix0 (a local named recursive function value needing
Go's `var f F; f = func(...){... f(...) ...}` self-reference idiom).
//
NOTE: the recursion is NON-TAIL (`x * f(x-1)` -- the self-call result is
MULTIPLIED, not returned directly), so the Go side emits a plain recursive
self-call (no `for` loop).  This also keeps the JS oracle usable: the JS
backend's fix0 emission has a pre-existing bug for a TAIL fix self-call (it
emits a bare `continue` with no enclosing loop -> SyntaxError); a non-tail fix
avoids that path, so this test is byte-equal-vs-JS.
//
Prints `fixfac(5)=120`.
*)
(* ****** ****** *)
#staload _ =
"prelude/DATS/gdbg000.dats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_dats.hats"
(* ****** ****** *)
#include
"prelude/HATS/prelude_JS_dats.hats"
(* ****** ****** *)
//
fun
fixfac(n: sint): sint =
(fix f(x: sint): sint =>
   if x > 0 then x * f(x-1) else 1)(n)
//
val () = strn_print("fixfac(5)=")
val () = sint_print(fixfac(5))    // 120
val () = strn_print("\n")
//
val () = the_print_store_log( (*void*) )
//
(* ****** ****** *)
(***********************************************************************)
(* end of [ATS3/XANADU_srcgen2_xats2go_srcgen2_TEST_test22_fix_local.dats] *)
(***********************************************************************)
