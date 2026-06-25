(* Regression: chained expression-level where blocks should flatten into one Pythonic where. *)

#extern
fun
nested_where_chain_check
( x0: sint ): sint

#implfun
nested_where_chain_check
  ( x0 ) =
aux0(x0) where
{
fun
aux0(x1: sint): sint = aux1(x1)
}
where
{
fun
aux1(x1: sint): sint = x1 + 1
}
