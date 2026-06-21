(* a block comment at the top of the file *)
def f(x):
    (* nested (* inner block *) still a comment *)
    let y = x + 1  (* trailing block comment after code *)
    # a hash line comment too
    y
