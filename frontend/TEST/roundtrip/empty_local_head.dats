(* Regression: an empty ATS local-head must not print as an empty `private:` block. *)

#extern
fun
empty_local_head_check
( x0: sint ): sint

local
in

#implfun
empty_local_head_check
  ( x0 ) = x0 + 1

end
