////////////////////////////////////////////////////////////////////////.
//
// CATS/GO/axrf000.cats — typed Go primitive floor for [a0rf] (single-cell
// mutable reference).  An a0rf is a SHARED, mutable box; the JS arm uses a
// singleton array `[x0]`, and the faithful Go analog is a length-1 `[]any`
// slice (slices share their backing array, so a copy of the handle still
// mutates the same cell -- exactly the reference semantics the prelude wants).
//
// a0rf erases to Go `any` (no GOTptr/GOTslice mapping for the abstract type),
// so the handle is carried as `any` and asserted to `[]any` at get/set.
//
////////////////////////////////////////////////////////////////////////.
//
func XATS2GO_a0rf_make_1val(x0 any) any { return []any{x0} }
//
func XATS2GO_a0rf_get(A any) any { return A.([]any)[0] }
//
// void-as-value (returns any/nil): mutate the shared cell through the slice.
func XATS2GO_a0rf_set(A any, x any) any {
	A.([]any)[0] = x
	return nil
}
//
////////////////////////////////////////////////////////////////////////.
// end of [ATS3_XANADU_prelude_DATS_CATS_GO_axrf000.cats]
////////////////////////////////////////////////////////////////////////.
