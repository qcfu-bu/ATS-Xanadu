package reprbench

import ("testing"; "unsafe")

// ---- A: TODAY — one universal con, []any fields, inline buf -------------
type ConA struct { Tag int; Args []any; Name string }
type bufA struct { ConA; buf [3]any }
func mkConsA(x int, xs *ConA) *ConA { c := &bufA{}; c.Tag = 1; c.buf[0], c.buf[1] = x, xs; c.Args = c.buf[:2]; return &c.ConA }
var nilA = &ConA{Tag: 0}
func sumA(v *ConA) int {
	s := 0
	for v.Tag == 1 { s += v.Args[0].(int); v = v.Args[1].(*ConA) }
	return s
}

// ---- B: header embed + unsafe cast --------------------------------------
type HdrB struct{ Tag int }
type consB struct { HdrB; F0 int; F1 *HdrB }
type nilBt struct{ HdrB }
func mkConsB(x int, xs *HdrB) *HdrB { c := &consB{HdrB{1}, x, xs}; return &c.HdrB }
var nilB = func() *HdrB { c := &nilBt{HdrB{0}}; return &c.HdrB }()
func sumB(v *HdrB) int {
	s := 0
	for v.Tag == 1 { c := (*consB)(unsafe.Pointer(v)); s += c.F0; v = c.F1 }
	return s
}

// ---- C: per-datatype interface + type switch ----------------------------
type ListC interface{ isListC() }
type consC struct { F0 int; F1 ListC }
type nilCt struct{}
func (*consC) isListC() {}
func (*nilCt) isListC() {}
var nilC ListC = &nilCt{}
func sumC(v ListC) int {
	s := 0
	for { c, ok := v.(*consC); if !ok { return s }; s += c.F0; v = c.F1 }
}

const N = 300000

func buildA() *ConA { v := nilA; for i := N; i > 0; i-- { v = mkConsA(i, v) }; return v }
func buildB() *HdrB { v := nilB; for i := N; i > 0; i-- { v = mkConsB(i, v) }; return v }
func buildC() ListC { v := nilC; for i := N; i > 0; i-- { v = &consC{i, v} }; return v }

func BenchmarkBuildA(b *testing.B) { for i := 0; i < b.N; i++ { buildA() } }
func BenchmarkBuildB(b *testing.B) { for i := 0; i < b.N; i++ { buildB() } }
func BenchmarkBuildC(b *testing.B) { for i := 0; i < b.N; i++ { buildC() } }

func BenchmarkSumA(b *testing.B) { v := buildA(); b.ResetTimer(); for i := 0; i < b.N; i++ { sumA(v) } }
func BenchmarkSumB(b *testing.B) { v := buildB(); b.ResetTimer(); for i := 0; i < b.N; i++ { sumB(v) } }
func BenchmarkSumC(b *testing.B) { v := buildC(); b.ResetTimer(); for i := 0; i < b.N; i++ { sumC(v) } }
