////////////////////////////////////////////////////////////////////////.
//
// CATS/GO/lsp_floor.cats — the Go extern floor of the ATS3 LSP server.
// Spliced into the assembled package by tools/build.sh ($->_ mangled).
// Surface (the pre-authorized set, nothing more): stdio bytes +
// monotonic clock + check-process spawn/reap.  Types are
// belief-consistent with DATS/lsp_floor.dats: string <-> Go string,
// sint <-> int, void -> any.  The ATS side is single-threaded; the
// goroutines here only pump I/O into buffers.
//
// Needs `import ("bytes"; "os"; "os/exec"; "time")`.
//
////////////////////////////////////////////////////////////////////////.
//
// ---- stdin: one pump goroutine feeds a channel; poll+read share it ----
var xats2goLspStdinCh chan []byte
var xats2goLspStdinPend []byte
var xats2goLspStdinEOF bool
//
func xats2goLspStdinEnsure() {
	if xats2goLspStdinCh != nil {
		return
	}
	ch := make(chan []byte, 64)
	xats2goLspStdinCh = ch
	go func() {
		for {
			buf := make([]byte, 65536)
			n, err := os.Stdin.Read(buf)
			if n > 0 {
				ch <- buf[:n]
			}
			if err != nil {
				close(ch)
				return
			}
		}
	}()
}
//
// BLOCKING read of some bytes from stdin; "" exactly at EOF.
func XATS2GO_LSP_read_chunk() string {
	xats2goLspStdinEnsure()
	if len(xats2goLspStdinPend) > 0 {
		s := string(xats2goLspStdinPend)
		xats2goLspStdinPend = nil
		return s
	}
	if xats2goLspStdinEOF {
		return ""
	}
	b, ok := <-xats2goLspStdinCh
	if !ok {
		xats2goLspStdinEOF = true
		return ""
	}
	return string(b)
}
//
// wait up to ms (ms < 0 = forever) for input: 1 data, 0 timeout, 2 EOF.
func XATS2GO_LSP_poll_stdin(ms int) int {
	xats2goLspStdinEnsure()
	if len(xats2goLspStdinPend) > 0 {
		return 1
	}
	if xats2goLspStdinEOF {
		return 2
	}
	if ms < 0 {
		b, ok := <-xats2goLspStdinCh
		if !ok {
			xats2goLspStdinEOF = true
			return 2
		}
		xats2goLspStdinPend = b
		return 1
	}
	t := time.NewTimer(time.Duration(ms) * time.Millisecond)
	defer t.Stop()
	select {
	case b, ok := <-xats2goLspStdinCh:
		if !ok {
			xats2goLspStdinEOF = true
			return 2
		}
		xats2goLspStdinPend = b
		return 1
	case <-t.C:
		return 0
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
// ---- checks: spawn a checker process, reap it, read its output --------
type xats2goLspCheck struct {
	cmd  *exec.Cmd
	out  *bytes.Buffer // stderr: the diagnostic report
	sout *bytes.Buffer // stdout: the --index records
	done chan struct{}
}
//
var xats2goLspChecks = map[int]*xats2goLspCheck{}
var xats2goLspCheckN int
//
// start `prog arg1 [arg2] [arg3]` ("" args omitted) with XATSHOME=xhome;
// input is piped to the child's stdin (then closed); stderr AND stdout
// captured (exec's copiers finish before Wait returns, so reading after
// done is race-free).  Returns the check id, or -1 on spawn failure.
func XATS2GO_LSP_spawn_check(prog string, arg1 string, arg2 string, arg3 string, xhome string, input string) int {
	args := []string{arg1}
	if arg2 != "" {
		args = append(args, arg2)
	}
	if arg3 != "" {
		args = append(args, arg3)
	}
	cmd := exec.Command(prog, args...)
	cmd.Env = append(os.Environ(), "XATSHOME="+xhome)
	cmd.Stdin = strings.NewReader(input)
	var out bytes.Buffer
	var sout bytes.Buffer
	cmd.Stderr = &out
	cmd.Stdout = &sout
	if err := cmd.Start(); err != nil {
		return -1
	}
	c := &xats2goLspCheck{cmd: cmd, out: &out, sout: &sout, done: make(chan struct{})}
	id := xats2goLspCheckN
	xats2goLspCheckN++
	xats2goLspChecks[id] = c
	go func() {
		cmd.Wait()
		close(c.done)
	}()
	return id
}
//
func XATS2GO_LSP_check_done(id int) int {
	c := xats2goLspChecks[id]
	if c == nil {
		return -1
	}
	select {
	case <-c.done:
		return 1
	default:
		return 0
	}
}
//
func XATS2GO_LSP_check_output(id int) string {
	c := xats2goLspChecks[id]
	if c == nil {
		return ""
	}
	return c.out.String()
}
//
func XATS2GO_LSP_check_stdout(id int) string {
	c := xats2goLspChecks[id]
	if c == nil {
		return ""
	}
	return c.sout.String()
}
//
func XATS2GO_LSP_check_drop(id int) any {
	c := xats2goLspChecks[id]
	if c == nil {
		return nil
	}
	select {
	case <-c.done:
	default:
		c.cmd.Process.Kill()
	}
	delete(xats2goLspChecks, id)
	return nil
}
//
// terminate the server process (LSP: exit 0 after shutdown, 1 without).
func XATS2GO_LSP_exit(code int) any {
	os.Exit(code)
	return nil
}
//
////////////////////////////////////////////////////////////////////////.
// end of [lsp_floor.cats]
////////////////////////////////////////////////////////////////////////.
