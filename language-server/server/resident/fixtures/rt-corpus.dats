(*
Round-trip corpus: a spread of real ATS3 types as #typedefs. The harness checks
this file, recovers each typedef's post-typecheck s2typ (via D2Csexpdef +
s2cst_get_styp), prints it with the faithful printer (Exact mode), wraps the
printed text as a fresh #typedef, re-checks, and unifies original vs round-tripped.
*)
//
// --- primitive leaves + width-distinct ints ---
#typedef c_int    = int
#typedef c_uint   = uint
#typedef c_lint   = lint
#typedef c_bool   = bool
#typedef c_char   = char
#typedef c_dbl    = double
#typedef c_ptr    = p0tr
//
// --- applications ---
#typedef c_list   = list(int)
#typedef c_listb  = list(bool)
#typedef c_optn   = optn(int)
//
// --- function types ---
#typedef c_fun1   = (int) -> int
#typedef c_fun2   = (int, int) -> int
#typedef c_fun3   = (int, bool, char) -> int
#typedef c_funhi  = (int) -> ((int) -> int)        // arg-position arrow (right-nested)
#typedef c_funarg = ((int) -> int) -> int          // left arm IS a function -> parens
#typedef c_funlst = (list(int)) -> int
//
// --- arg modifiers (call-by-value lval `!`, by-ref `&`) ---
#typedef c_arg    = (!int) -> int
#typedef c_argr   = (&int) -> int
//
// --- tuples (flat) ---
#typedef c_tup2   = @(int, bool)
#typedef c_tup3   = @(int, bool, char)
//
// --- records (flat) ---
#typedef c_rcd    = @{ fst= int, snd= bool }
//
// --- quantifiers ---
#typedef c_uni    = {a:t0} (a) -> a
#typedef c_exi    = [a:t0] (a)
#typedef c_uni2   = {a:t0}{b:t0} (a, b) -> a
//
// --- closures ---
#typedef c_cloref  = (int) -<cloref> int
#typedef c_cloptr  = (int) -<cloptr> int
#typedef c_clo2    = (int, bool) -<cloref> int
//
// --- nested / mixed ---
#typedef c_listfun = list((int) -> int)
#typedef c_funtup  = (@(int, bool)) -> int
#typedef c_optfun  = optn((int) -> bool)
#typedef c_listtup = list(@(int, bool))
#typedef c_optrcd  = optn(@{x= int, y= int})
#typedef c_fun4    = (int, int, int, int) -> bool
#typedef c_funclo  = (int) -> ((bool) -<cloref> char)
//
// --- constrained / indexed quantifiers (constraints dropped: lossy) ---
#typedef c_exidx   = [n:int] list(int, n)
#typedef c_unicon  = {n:int | n >= 0} (int) -> int
//
// --- proof-arg bar (npf) + arg transition (>>) ---
#typedef c_pf1     = (int | int) -> int
#typedef c_pf0     = (| int) -> int
#typedef c_atx     = (int >> bool) -> int
#typedef c_atxbang = (!int >> bool) -> int
//
(* end of corpus *)
