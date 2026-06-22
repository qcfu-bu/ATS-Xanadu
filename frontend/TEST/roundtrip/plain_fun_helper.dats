(* Regression: ordinary top-level fun declarations must bind as plain Pythonic defs. *)

#extern
fun
plain_fun_helper_check
( x0: sint ): sint

fun
plain_fun_helper_id
( x0: sint ): sint = x0

#implfun
plain_fun_helper_check
( x0 ) =
plain_fun_helper_id(x0)
