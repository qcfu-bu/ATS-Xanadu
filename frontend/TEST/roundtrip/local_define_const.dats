(* Regression: local #define constants must print as dynamic value bindings. *)

#extern
fun
local_define_const_sta
( (*void*) ): sint

#extern
fun
local_define_const_dyn
( (*void*) ): sint

local
#define STA 0
#define DYN 1
in

#implfun
local_define_const_sta
  ( (*void*) ) = STA

#implfun
local_define_const_dyn
  ( (*void*) ) = DYN

end
