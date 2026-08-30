////////////////////////////////////////////////////////////////////////.
//
// CATS/GO/lsp_floor.cats — the Go extern floor of the ATS3 LSP server.
// Spliced into the assembled package by tools/build.sh ($->_ mangled).
// Surface: stdio bytes + monotonic clock + (M6) the in-process check
// floor — setenv, a panic guard, and the runtime capture/buffer-FILR
// wrappers.  Types are belief-consistent with DATS/lsp_floor.dats:
// string <-> Go string, sint <-> int, void -> any.  The ATS side is
// single-threaded; the goroutines here only pump I/O into buffers.
//
// Needs `import ("os"; "time"; "xatsgo")`.
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
// wait up to ms (ms < 0 = forever) for input: 1 data, 0 timeout, 2 EOF,
// 3 = the in-flight check finished (wakes the loop to reap immediately
// instead of waiting out the poll tick).
func XATS2GO_LSP_poll_stdin(ms int) int {
	xats2goLspStdinEnsure()
	if len(xats2goLspStdinPend) > 0 {
		return 1
	}
	if xats2goLspStdinEOF {
		return 2
	}
	var chkdone chan struct{}
	if xats2goLspCur != nil {
		chkdone = xats2goLspCur.done
	}
	if ms < 0 {
		select {
		case b, ok := <-xats2goLspStdinCh:
			if !ok {
				xats2goLspStdinEOF = true
				return 2
			}
			xats2goLspStdinPend = b
			return 1
		case <-chkdone: // nil channel when no check: never fires
			return 3
		}
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
	case <-chkdone:
		return 3
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
// ---- M6: the IN-PROCESS check floor -----------------------------------
// The compiler is linked into this binary (wire-server.sh); checks run
// in-process via tchk_check (UTIL/xats2go_tchecklib).  The old
// spawn/reap process floor is gone with it.
//
// set an environment variable (XATSHOME before the prelude loads; the
// compiler reads it via its getenv leaf).
func XATS2GO_LSP_setenv(name string, value string) any {
	os.Setenv(name, value)
	return nil
}
//
// run the closure with a panic guard: 1 = completed, 0 = recovered.
// A frontend abort (the compiler's exit-worthy errors surface as
// panics in the GO arm) fails ONE check, never the server.  Closure
// convention per CATS/GO/strn000.cats: `(sint)->void` emits as
// `func(int) any`.
func XATS2GO_LSP_guard(f0 func(int) any) int {
	ok := 1
	func() {
		defer func() {
			if r := recover(); r != nil {
				os.Stderr.WriteString("ats3-lsp: check aborted (recovered panic)\n")
				ok = 0
			}
		}()
		f0(0)
	}()
	return ok
}
//
// ---- the ASYNC in-process check (one goroutine, single-flight) --------
// The check runs OFF the event loop so hover/completion stay responsive
// during a mid-file check.  Exactly ONE check goroutine exists at a time
// (the compiler globals are single-threaded); the go statement orders it
// after everything the loop did before (prelude load included), and the
// done-channel close orders its writes before the loop's collection.
// The goroutine calls the wire-generated shim XATS2GO_LSP_tchk_check
// (same package) under its own recover, then drains the runtime stash
// into the per-check record — the loop never touches the stash.
type xats2goLspInproc struct {
	done chan struct{}
	rep  string // the captured report text
	idx  string // the --index records
	ok   int    // 1 completed, 0 recovered panic
}
//
var xats2goLspInprocs = map[int]*xats2goLspInproc{}
var xats2goLspInprocN int
var xats2goLspInflight bool
var xats2goLspCur *xats2goLspInproc // the in-flight check (poll wakes on its done)
//
// start the PRELUDE WARM-UP on the check goroutine (M7.1): initialize
// answers in ~3ms and the ~250ms pvsload happens concurrently in the
// gap before the user's first edit.  Occupies the single-flight slot
// (the first real check queues behind it); the loop reaps it like a
// check with an empty uri (no publish).
func XATS2GO_LSP_warmup_start() int {
	if xats2goLspInflight {
		return -1
	}
	c := &xats2goLspInproc{done: make(chan struct{})}
	id := xats2goLspInprocN
	xats2goLspInprocN++
	xats2goLspInprocs[id] = c
	xats2goLspInflight = true
	xats2goLspCur = c
	go func() {
		c.ok = 1
		func() {
			defer func() {
				if r := recover(); r != nil {
					os.Stderr.WriteString("ats3-lsp: prelude load aborted (recovered panic)\n")
					c.ok = 0
				}
			}()
			XATS2GO_LSP_tchk_prelude_load()
		}()
		close(c.done)
	}()
	return id
}
//
// start the check; returns the check id, or -1 if one is already in
// flight (the caller gates on that, this is belt-and-braces).
func XATS2GO_LSP_check_start(path string, txt string, stdinq int) int {
	if xats2goLspInflight {
		return -1
	}
	c := &xats2goLspInproc{done: make(chan struct{})}
	id := xats2goLspInprocN
	xats2goLspInprocN++
	xats2goLspInprocs[id] = c
	xats2goLspInflight = true
	xats2goLspCur = c
	go func() {
		c.ok = 1
		func() {
			defer func() {
				if r := recover(); r != nil {
					os.Stderr.WriteString("ats3-lsp: check aborted (recovered panic)\n")
					c.ok = 0
				}
			}()
			XATS2GO_LSP_tchk_check(path, txt, stdinq)
		}()
		c.rep = xatsgo.Xats_XATS2GO_lsp_take_rep()
		c.idx = xatsgo.Xats_XATS2GO_lsp_take_idx()
		close(c.done)
	}()
	return id
}
//
// 1 = finished, 0 = still running, -1 = unknown id
func XATS2GO_LSP_check_done(id int) int {
	c := xats2goLspInprocs[id]
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
func XATS2GO_LSP_check_rep(id int) string {
	c := xats2goLspInprocs[id]
	if c == nil {
		return ""
	}
	return c.rep
}
//
func XATS2GO_LSP_check_idx(id int) string {
	c := xats2goLspInprocs[id]
	if c == nil {
		return ""
	}
	return c.idx
}
//
func XATS2GO_LSP_check_ok(id int) int {
	c := xats2goLspInprocs[id]
	if c == nil {
		return 0
	}
	return c.ok
}
//
// forget the check.  BLOCKS until the goroutine finishes if it is still
// running — a live compiler goroutine is never abandoned (the compiler
// globals are single-threaded), which makes this double as the
// prelude-reload drain.  The normal collection path calls it only after
// check_done = 1, so it never blocks there.
func XATS2GO_LSP_check_drop(id int) any {
	c := xats2goLspInprocs[id]
	if c != nil {
		<-c.done
		delete(xats2goLspInprocs, id)
		xats2goLspInflight = false
		if xats2goLspCur == c {
			xats2goLspCur = nil
		}
	}
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
