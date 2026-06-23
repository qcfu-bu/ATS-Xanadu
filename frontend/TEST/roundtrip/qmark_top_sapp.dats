(* Regression: the `?` static operator (#sexpdef ? = top0_vt_t0) round-trips as a
   static-application head `?[A]` and resolves to the top-view (S2Etop0) of A.
   The stock parser lexes `?` as T_IDSYM("?"); pyprint emits `@sapp[?[A]]`; the
   Pythonic frontend re-lexes `?` to PT_QMARK, parses `?[A]` as PyTcon("?",[A]),
   and lowers the head `?` against the prelude sexpdef back to S2Eapps([?, A]). *)

#extern
fun
qmark_top_fnp
{a:t0}
( x0: a ): void

#extern
fun
qmark_set_fnp
{a:t0}
( x0: (a) ): void

#implfun
qmark_top_fnp
{a:t0}
( x0 ) =
(
  qmark_set_fnp{?a}(x0)
)
