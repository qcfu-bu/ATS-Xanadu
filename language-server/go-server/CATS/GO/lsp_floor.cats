////////////////////////////////////////////////////////////////////////.
//
// CATS/GO/lsp_floor.cats — the Go extern floor of the ATS3 LSP server.
// Spliced into the assembled package by tools/build.sh ($->_ mangled).
// KEEP THIS A ONE-PAGER: stdio bytes + monotonic clock (process spawn
// arrives with the M2 checker).  Types are belief-consistent with
// DATS/lsp_floor.dats: string <-> Go string, sint <-> int, void -> any.
//
// Needs `import ("os"; "time")`.
//
////////////////////////////////////////////////////////////////////////.
//
// BLOCKING read of some bytes from stdin; "" exactly at EOF.
func XATS2GO_LSP_read_chunk() string {
	buf := make([]byte, 65536)
	for {
		n, err := os.Stdin.Read(buf)
		if n > 0 {
			return string(buf[:n])
		}
		if err != nil {
			return ""
		}
	}
}
//
func XATS2GO_LSP_write_out(s string) any {
	os.Stdout.WriteString(s)
	return nil
}
//
func XATS2GO_LSP_write_log(s string) any {
	os.Stderr.WriteString(s)
	return nil
}
//
var xats2goLspEpoch = time.Now()
//
func XATS2GO_LSP_now_ms() int {
	return int(time.Since(xats2goLspEpoch).Milliseconds())
}
//
////////////////////////////////////////////////////////////////////////.
// end of [lsp_floor.cats]
////////////////////////////////////////////////////////////////////////.
