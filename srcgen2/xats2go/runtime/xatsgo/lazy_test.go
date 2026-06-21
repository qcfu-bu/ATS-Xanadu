package xatsgo

import "testing"

// TestL0azyMemoizes proves Xats_l0azy/Xats_dl0az force the thunk EXACTLY ONCE
// (memoization): the side-effect counter increments once even when forced twice,
// and both forces return the same cached result. This is the Go image of the JS
// XATS000_l0azy/dl0az [0,lfun] memo cell.
func TestL0azyMemoizes(t *testing.T) {
	forced := 0
	lz := Xats_l0azy(func() any { forced++; return 21 + 21 })
	if forced != 0 {
		t.Fatalf("thunk ran before force: forced=%d", forced)
	}
	r1 := Xats_dl0az(lz)
	r2 := Xats_dl0az(lz)
	if forced != 1 {
		t.Fatalf("l0azy not memoized: forced=%d (want 1)", forced)
	}
	if r1 != 42 || r2 != 42 {
		t.Fatalf("cached result wrong: r1=%v r2=%v", r1, r2)
	}
}

// TestL1azyCallByName proves Xats_l1azy/Xats_dl1az are CALL-BY-NAME (NOT memoized):
// the thunk re-runs on every force. Go image of XATS000_l1azy=identity / dl1az=call.
func TestL1azyCallByName(t *testing.T) {
	ran := 0
	th := Xats_l1azy(func() any { ran++; return ran })
	r1 := Xats_dl1az(th)
	r2 := Xats_dl1az(th)
	if ran != 2 {
		t.Fatalf("l1azy unexpectedly memoized: ran=%d (want 2)", ran)
	}
	if r1 != 1 || r2 != 2 {
		t.Fatalf("call-by-name results wrong: r1=%v r2=%v", r1, r2)
	}
}

// TestFoldFree: fold yields its arg; free is a GC no-op returning nil.
func TestFoldFree(t *testing.T) {
	if Xats_fold(7) != 7 {
		t.Fatalf("fold should yield its arg")
	}
	if Xats_free(7) != nil {
		t.Fatalf("free should be a no-op returning nil")
	}
}

// TestEmitterShapeAnyBoxed reproduces the EXACT Go the emitter emits when an
// I1INSl0azy result temp (a Go `any`) is forced by I1INSdl0az:
//
//	cell := any(Xats_l0azy(func() any { ... }))     // l0azy result is any-typed
//	r := Xats_dl0az(cell.(*XatsLazy))                // dl0az asserts the lazy type
//
// and for l1azy/dl1az the analogous `cell.(func() any)` assertion. This proves
// the emitted type-assertion strings (".(*xatsgo.XatsLazy)" / ".(func() any)")
// compile + behave once the value flows through an `any` slot (the regime-A
// representation the emitter uses everywhere).
func TestEmitterShapeAnyBoxed(t *testing.T) {
	forced := 0
	var cell any = Xats_l0azy(func() any { forced++; return 100 })
	r1 := Xats_dl0az(cell.(*XatsLazy))
	r2 := Xats_dl0az(cell.(*XatsLazy))
	if forced != 1 || r1 != 100 || r2 != 100 {
		t.Fatalf("any-boxed l0azy/dl0az wrong: forced=%d r1=%v r2=%v", forced, r1, r2)
	}
	ran := 0
	var th any = Xats_l1azy(func() any { ran++; return ran })
	s1 := Xats_dl1az(th.(func() any))
	s2 := Xats_dl1az(th.(func() any))
	if ran != 2 || s1 != 1 || s2 != 2 {
		t.Fatalf("any-boxed l1azy/dl1az wrong: ran=%d s1=%v s2=%v", ran, s1, s2)
	}
}
