////////////////////////////////////////////////////////////////////////.
//
// CATS/GO/unsfx00.cats — typed Go primitive floor for the UNSAFE p2tr
// (pointer) deref leaves.  Needs `import "reflect"`.
//
// The pointer [p0] arrives as `any` holding a REAL Go pointer (e.g. a `*int`
// from `$addr(i0)` flowing through an `any`-erased generic p2tr_get<ni>
// instance).  Go cannot `*` an `any`, so we deref BY REFLECTION:
// reflect.ValueOf(p).Elem() is the pointed-to cell (settable, since it is
// reached through a pointer).  This lets a real typed pointer be read / written
// generically, which is exactly what the gseq stack counter needs.
//
////////////////////////////////////////////////////////////////////////.
//
func XATS2GO_p2tr_get(p0 any) any {
	return reflect.ValueOf(p0).Elem().Interface()
}
//
// void-as-value (returns any/nil), like the other void prelude prims.
func XATS2GO_p2tr_set(p0 any, x0 any) any {
	reflect.ValueOf(p0).Elem().Set(reflect.ValueOf(x0))
	return nil
}
//
////////////////////////////////////////////////////////////////////////.
// end of [ATS3_XANADU_prelude_DATS_CATS_GO_unsfx00.cats]
////////////////////////////////////////////////////////////////////////.
