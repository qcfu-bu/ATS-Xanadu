(* Regression: inline source parentheses must preserve infix grouping. *)

#extern
fun
paren_infix_grouping
(r0: sint, bas: sint, c0: char): sint

#implfun
paren_infix_grouping
(r0, bas, c0) =
(
r0*bas+(c0-'0')) where
{
#symload - with sub_char_char of 1001
}
