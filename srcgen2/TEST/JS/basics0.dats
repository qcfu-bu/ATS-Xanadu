(* ****** ****** *)
(*
Thu Jul 14 12:57:48 EDT 2022
*)
(* ****** ****** *)

val x1 = 10
val x2 = 20
and x3 = $lam($10 + $20)

(* ****** ****** *)

val id = lam(x) => x
val id = fix f(x) => x

(* ****** ****** *)

val x4 = if b0 > 0 then 1 else 0

(* ****** ****** *)

(* end of [ATS3/XANADU_prelude_basics0.dats] *)
