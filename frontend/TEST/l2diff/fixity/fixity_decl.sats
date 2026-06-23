//
// FIXITY round-trip fixture (Cluster B): operator-precedence declarations.
//
// Stock builds the L1 fixity ENV (trans01_decl00.dats f0_fixity/f0_nonfix) and
// preserves the raw d0ecl through both levels, lowering each to
//   D2Cd1ecl(D1Cd0ecl(D0Cfixity/D0Cnonfix(...)))
// The pythonic frontend keeps the ATS fixity keywords VERBATIM (infixl/infixr/
// prefix/postfix/nonfix) and lowers to the SAME L2.
//
#infixl + of 50
#infixl * of 60
#infixr ** of 61
#prefix ~ of 51
#nonfix foo
