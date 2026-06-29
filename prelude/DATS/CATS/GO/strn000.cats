////////////////////////////////////////////////////////////////////////.
//
// CATS/GO/strn000.cats — typed Go primitive floor for [strn] (strings).
// Mirrors CATS/JS/strn000.cats for the SCALAR-returning primitives
// (length / cmp / print / get_at).  The higher-order string-CONSTRUCTION
// primitives (strn_make_fwork / strn_fmake_env$fwork / strn_fset$at$raw) are
// DEFERRED (arm-bound, bodiless) until the go-arm higher-order calling
// convention is settled.  ASCII surface (len = bytes = JS .length; cs[i] is a
// byte -> rune).
//
// Needs `import "strconv"` is NOT required here; the print store + `strings`
// live in xtop000.cats.
//
////////////////////////////////////////////////////////////////////////.
//
// NOTE: the string params are `any` (asserted to string), matching the
// emitter's `any`-boundary convention -- an ATS `strn` param's static type is
// an existential that the current param-type recovery resolves to `any` (unlike
// `sint`'s `gint_type` path).  XATSSTRN is identity on a Go string, so the
// asserted value is always a real string.  (Tightening to typed `string` params
// is gated on the emitter's existential-chase / typed-temp param path.)
func xats2goStr(x any) string {
	if s, ok := x.(string); ok {
		return s
	}
	return ""
}
//
func XATS2GO_strn_length(cs any) int { return len(xats2goStr(cs)) }
//
// strn_cmp: the ATS contract is the char-difference (== JS charCodeAt diff),
// NOT strings.Compare's -1/0/1.  Replicate it so ordering magnitude matches.
func XATS2GO_strn_cmp(x1 any, x2 any) int {
	s1 := xats2goStr(x1)
	s2 := xats2goStr(x2)
	n1 := len(s1)
	n2 := len(s2)
	n0 := n1
	if n2 < n1 {
		n0 = n2
	}
	for i0 := 0; i0 < n0; i0++ {
		df := int(s1[i0]) - int(s2[i0])
		if df != 0 {
			return df
		}
	}
	return n1 - n2
}
//
func XATS2GO_strn_get_at_raw(cs any, i0 int) rune { return rune(xats2goStr(cs)[i0]) }
//
// void-as-value (returns any/nil), like the other prelude prints.
func XATS2GO_strn_print(cs any) any {
	XATS2GO_the_print_store = append(XATS2GO_the_print_store, xats2goStr(cs))
	return nil
}
//
////////////////////////////////////////////////////////////////////////.
// end of [ATS3_XANADU_prelude_DATS_CATS_GO_strn000.cats]
////////////////////////////////////////////////////////////////////////.
