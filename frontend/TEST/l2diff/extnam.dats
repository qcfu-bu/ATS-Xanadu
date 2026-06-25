//
// FFI round-trip fixture: the `$extnam` foreign-name binding on an `#extern fun`.
//
// This is the dominant prelude FFI construct (665 uses). Stock lowers each of these to
//   D2Cextern(D2Cfundclst(D2FUNDCL(foo; ...; TEQD2EXPsome(=, D2Eextnam(T_DLR_EXTNAM; G1Nlist(...))))))
// and registers the foreign name on the d2cst stamp (the_d2cstmap_xnmadd0). The Pythonic
// frontend round-trips it as `@extern def foo(...) -> T = extnam(["cname"])` and lowers to the
// SAME L2. The nullary/void forms below round-trip with ZERO structural diff (EXACT mode); the
// int-param forms additionally carry the pre-existing M5a `int`<->`the_s2exp_sint0` type-name
// alias (a separate, non-extnam concern), so use --triage for those.
//
// empty `$extnam()` — the foreign name defaults to the fun's own name (the 665x dominant form).
#extern fun foo(): void = $extnam()
//
// named `$extnam("cname")` — an explicit foreign C name.
#extern fun bar(): void = $extnam("bar_c_impl")
