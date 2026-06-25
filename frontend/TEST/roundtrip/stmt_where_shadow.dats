(* Regression: val () statement-level where blocks must preserve shadowing decls. *)

#staload "./../../../srcgen2/SATS/filpath.sats"

#extern
fun
stmt_where_shadow
( name: strn ): void

#implfun
stmt_where_shadow
  ( name ) =
let
val dir1 = fpath_dpart(name)
val () =
the_drpth_push(dir1) where
{
val dir1 = drpth_make_name(dir1)
}
in
  ()
end
