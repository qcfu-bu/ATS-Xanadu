package reprbench

import "testing"

// POLYMORPHIC payload (the compiler's dominant case: 51% of field accesses
// are on fields whose type is unrecoverable, so they stay `any` in EVERY
// representation).  Isolates the CONTAINER win from the unboxing win.
type consAp struct { ConA }
func mkConsAp(x any, xs *ConA) *ConA { c := &bufA{}; c.Tag = 1; c.buf[0], c.buf[1] = x, xs; c.Args = c.buf[:2]; return &c.ConA }
func sumAp(v *ConA) int { s := 0; for v.Tag == 1 { s += v.Args[0].(int); v = v.Args[1].(*ConA) }; return s }

type consCp struct { F0 any; F1 ListC }
func (*consCp) isListC() {}
func sumCp(v ListC) int { s := 0; for { c, ok := v.(*consCp); if !ok { return s }; s += c.F0.(int); v = c.F1 } }

// box the payload ONCE outside the loop so we measure the container, not convT64
var boxed [1000]any
func init() { for i := range boxed { boxed[i] = i } }

func buildAp() *ConA { v := nilA; for i := N; i > 0; i-- { v = mkConsAp(boxed[i%1000], v) }; return v }
func buildCp() ListC { v := nilC; for i := N; i > 0; i-- { v = &consCp{boxed[i%1000], v} }; return v }

func BenchmarkBuildA_poly(b *testing.B) { for i := 0; i < b.N; i++ { buildAp() } }
func BenchmarkBuildC_poly(b *testing.B) { for i := 0; i < b.N; i++ { buildCp() } }
func BenchmarkSumA_poly(b *testing.B) { v := buildAp(); b.ResetTimer(); for i := 0; i < b.N; i++ { sumAp(v) } }
func BenchmarkSumC_poly(b *testing.B) { v := buildCp(); b.ResetTimer(); for i := 0; i < b.N; i++ { sumCp(v) } }
