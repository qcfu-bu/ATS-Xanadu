;;; ====================================================================== ;;;
;;; xats_lsp_resident.scm — the FLOOR (Stage 6 cutover).
;;; The ATS driver (resident/DATS/xats_lsp_resident.dats) owns the LSP message
;;; loop, dispatch, validation and all request/notification handlers.  This file
;;; provides ONLY the irreducible backend primitives it calls as leaves: the FFI
;;; string/cell ops, framed stdio (reader thread + debounce timeout), a catch-all
;;; guard, fs/time, the compiler-stamp signature map, the FS workspace scan, and
;;; the compiler-touching leaves (topmap eviction, typrint, diagnostic builders).
;;; Auto-reduced from the pre-cutover glue to its live transitive closure (94 of
;;; 250 forms); the dispatch/dedup/builder/doc/json code now lives in ATS.
;;; ====================================================================== ;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;                                                                  ;;;;
;;;;   RESIDENT LSP server  -  CHEZ-glue companion  (workstream R1)    ;;;;
;;;;   Chez analog of server/resident/CATS/xats_lsp_resident.cats      ;;;;
;;;;                                                                  ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Replaces the vscode-languageserver Node library (no Chez equivalent) with a
;; hand-written LSP JSON-RPC transport: Content-Length-framed JSON over
;; stdin/stdout, a JSON parser + serializer, and a synchronous request-dispatch
;; loop (Chez has no async event loop; warm checks are ~ms, so processing one
;; message fully before reading the next is correct + simplest).
;;
;; It provides every `#extern fun NAME(...) = $extnam()` the cz0emit-compiled
;; xats_lsp_resident.dats references: the depset/depgraph/sig data structures, the
;; cache-eviction primitive (JS_map_reset = delete env[stamp] -> hashtable-delete!
;; on the compiler's per-file topmaps), the LSP_* harvest accumulators feeding a
;; per-uri index, the vscode_* helpers, and the big vscode_initialize loop.
;;
;; The ATS side passes its validators (text/live/prune/reload/evict) into
;; vscode_initialize as Scheme procedures; the loop calls them, and they call back
;; into the glue (depgraph_add, env_reset, the LSP_*_push sinks).  Mutual
;; recursion across the FFI boundary, exactly like the JS .cats.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ====================================================================== ;;
;; small helpers (shared with the checker glue's conventions)             ;;
;; ====================================================================== ;;

(define (LSP->int x) (if (number? x) (exact (floor x)) 0))


(define (LSP->str x) (cond ((string? x) x) ((not x) "")
                          (else (let ((p (open-output-string))) (display x p) (get-output-string p)))))



;; ---- FFI floor leaves for the portable ATS3 modules -------------------------
;; The 4 codepoint-normalized string leaves (xats_lsp_{json,uri,u16,dedup}) +
;; the 3-op mutable cell (xats_lsp_ref.hats).  Chez strings are codepoint-indexed,
;; so string-ref/string-length already give code POINTS (matching the modules'
;; contract); a cell is a 1-vector.
(define (int2str n) (number->string n))


(define (str_len s) (string-length s))


(define (str_char_code s i) (char->integer (string-ref s i)))


(define (str_of_code c) (string (integer->char c)))


(define (str_slice s a b) (substring s a b))

   ; O(len) codepoint-indexed substring (doc range edits)
(define (cell_make x) (vector x))


(define (cell_get c) (vector-ref c 0))


(define (cell_set c x) (vector-set! c 0 x) _xunit)


(define (lsp_getenv n) (or (getenv n) ""))

   ; for the ATS index module's env-configured caches
;; the startup prelude-index metric line (the ATS index module owns the count now).
(define (lsp_log_prelude_index n)
  (put-string (current-error-port) (string-append "[xats-lsp-resident] prelude-index: " (number->string n) " name(s) [env]\n"))
  (flush-output-port (current-error-port)) _xunit)


;; stderr log line (the server's diagnostics go to stderr; stdout is the LSP wire)
(define (LSP-stderr s) (put-string (current-error-port) s) (flush-output-port (current-error-port)) _xunit)


(define (LSP-string-split s ch)
  (let ((n (string-length s)))
    (let loop ((i 0) (start 0) (acc '()))
      (cond ((>= i n) (reverse (cons (substring s start n) acc)))
            ((char=? (string-ref s i) ch) (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
            (else (loop (+ i 1) start acc))))))


(define (LSP-starts-with? s pre)
  (let ((ns (string-length s)) (np (string-length pre)))
    (and (>= ns np) (string=? (substring s 0 np) pre))))


(define (LSP-string-contains? s sub)            ; naive substring search
  (let ((ns (string-length s)) (nsub (string-length sub)))
    (if (= nsub 0) 0
        (let loop ((i 0))
          (cond ((> (+ i nsub) ns) -1)
                ((string=? (substring s i (+ i nsub)) sub) i)
                (else (loop (+ i 1))))))))



;; ====================================================================== ;;
;; JSON encoder (matches the checker glue) + parser (NEW)                  ;;
;; ====================================================================== ;;
;; json value reps: (str . S) (num . N) (bool . B) null=(quote jnull)
;;                  (obj (k . v)...) (arr v...)
(define (jstr s) (cons 'str s))


(define (jnum n) (cons 'num n))


(define (jobj kvs) (cons 'obj kvs))



;; ====================================================================== ;;
;; THE cache-eviction primitive: delete env[stamp] from a topmap            ;;
;; ====================================================================== ;;
;; the_d{1,2,3}parenv are jshmaps (equal-hashtables) keyed by the file's stamp
;; number (topmap_insert: g0u2s(uint(stmp)) = uint2sint(stamp_get_uint(stmp)) =
;; the number).  The ATS hands us key.stmp() (the same number) -> delete it.
(define (JS_map_reset env key)
  (when (hashtable-contains? env key) (hashtable-delete! env key)) _xunit)



;; ====================================================================== ;;
;; $XATSHOME prelude detection + path normalization                        ;;
;; ====================================================================== ;;
;; LSP_norm: make absolute (vs cwd) + collapse '.'/'..' (no symlink resolution;
;; consistency across the server is what matters, not canonical realpath).
(define (LSP_norm p)
  (let ((s (LSP->str p)))
    (if (string=? s "") ""
        (let ((abs (if (and (> (string-length s) 0) (char=? (string-ref s 0) #\/))
                       s
                       (let ((d (current-directory)))
                         (string-append (if (LSP-starts-with? (string-append d "/") "/") d d) "/" s)))))
          (let ((segs (LSP-string-split abs #\/)) (out '()))
            (for-each
             (lambda (seg)
               (cond ((or (string=? seg "") (string=? seg ".")) #f)
                     ((string=? seg "..") (when (pair? out) (set! out (cdr out))))
                     (else (set! out (cons seg out)))))
             segs)
            (string-append "/" (let join ((xs (reverse out)) (first #t) (o (open-output-string)))
                                  (cond ((null? xs) (get-output-string o))
                                        (else (unless first (put-char o #\/)) (put-string o (car xs))
                                              (join (cdr xs) #f o))))))))))



(define LSP_xatshome
  (let ((h (or (getenv "XATSHOME") "")))
    (if (string=? h "") "" (let ((n (LSP_norm h))) (if (string=? n "") "" (string-append n "/"))))))


;; Stage 6d: prelude-root classification now lives in ATS (xats_lsp_conv).  This is
;; a thin wrapper forwarding to that closure (bound in vscode_initialize); kept as a
;; top-level name because top-level fns (LSP_immutable, scan_dir) call it too.
;; (LSP_xatshome / LSP_prelude_roots / LSP-any above are now dead — cleanup later.)
(define LSP-ats-pip #f)


(define (JS_path_is_prelude path) (LSP-ats-pip path))



;; ---- prelude snapshot (R2a secondary guard): stamps cached at startup ----
(define LSP_prelude_stamps (make-hashtable equal-hash equal?))


(define LSP_prelude_frozen #f)


(define (JS_prelude_snapshot env)
  (vector-for-each (lambda (k) (hashtable-set! LSP_prelude_stamps k #t)) (hashtable-keys env)) _xunit)


(define (JS_prelude_snapshot_reset) (set! LSP_prelude_stamps (make-hashtable equal-hash equal?)) (set! LSP_prelude_frozen #f) _xunit)


(define (JS_prelude_freeze)
  (set! LSP_prelude_frozen #t)
  (LSP-stderr (string-append "[xats-lsp-resident] prelude immutable: XATSHOME="
                             (if (string=? LSP_xatshome "") "(unset)" LSP_xatshome) " + "
                             (number->string (hashtable-size LSP_prelude_stamps)) " snapshot stamp(s)\n"))
  _xunit)


(define (LSP_immutable stamp path)
  (or (hashtable-contains? LSP_prelude_stamps stamp) (JS_path_is_prelude path)))



;; ====================================================================== ;;
;; R2a signature map (stamp -> #(path mtime size)) + path->stamp index      ;;
;; ====================================================================== ;;
(define LSP_signatures (make-hashtable equal-hash equal?))


(define LSP_path2stamp (make-hashtable equal-hash equal?))


(define LSP_stat_count 0)


(define (LSP_stat_count_reset) (let ((n LSP_stat_count)) (set! LSP_stat_count 0) n))


;; {mtime,size} or #f if gone/unreadable.
(define (LSP_stat_sig path)
  (guard (e (#t #f))
    (if (file-exists? path)
        (begin (set! LSP_stat_count (+ LSP_stat_count 1))
               (cons (file-modification-time path) (LSP-file-size path)))
        #f)))


(define (LSP-file-size path)
  (guard (e (#t 0)) (let* ((p (open-file-input-port path)) (n (let loop ((k 0)) (let ((b (get-bytevector-n p 65536))) (if (eof-object? b) k (loop (+ k (bytevector-length b)))))))) (close-port p) n)))


(define (JS_sig_record stamp path)
  (let ((p (LSP->str path)))
    (cond ((string=? p "") _xunit)
          ((LSP_immutable stamp p) _xunit)
          (else (let ((sig (LSP_stat_sig p)))
                  (if (not sig) _xunit
                      (begin (hashtable-set! LSP_signatures stamp (vector p (car sig) (cdr sig)))
                             (let ((n (LSP_norm p))) (unless (string=? n "") (hashtable-set! LSP_path2stamp n stamp)))
                             _xunit)))))))


(define (JS_sig_refresh stamp)
  (let ((rec (hashtable-ref LSP_signatures stamp #f)))
    (if (not rec) _xunit
        (let ((sig (LSP_stat_sig (vector-ref rec 0))))
          (if (not sig) _xunit (begin (vector-set! rec 1 (car sig)) (vector-set! rec 2 (cdr sig)) _xunit)))))
  _xunit)


(define (JS_sig_changed stamp)
  (let ((rec (hashtable-ref LSP_signatures stamp #f)))
    (if (not rec) #f
        (let ((sig (LSP_stat_sig (vector-ref rec 0))))
          (cond ((not sig) #t)
                ((or (not (equal? (car sig) (vector-ref rec 1))) (not (= (cdr sig) (vector-ref rec 2)))) #t)
                (else #f))))))


(define (JS_path2stamp_lookup path)
  (let ((n (LSP_norm path))) (if (string=? n "") #f (hashtable-ref LSP_path2stamp n #f))))


(define (LSP-hexval c) (cond ((char<=? #\0 c #\9) (- (char->integer c) 48)) ((char<=? #\a c #\f) (+ 10 (- (char->integer c) 97))) ((char<=? #\A c #\F) (+ 10 (- (char->integer c) 65))) (else 0)))


;; percent-DECODE a uri path into a filesystem path (utf-8).
(define (LSP-decodeURI s)
  (let ((n (string-length s)) (acc '()))
    (let loop ((i 0))
      (cond ((>= i n) (utf8->string (u8-list->bytevector (reverse acc))))
            ((and (char=? (string-ref s i) #\%) (< (+ i 2) n))
             (set! acc (cons (+ (* 16 (LSP-hexval (string-ref s (+ i 1)))) (LSP-hexval (string-ref s (+ i 2)))) acc))
             (loop (+ i 3)))
            (else (let ((bs (string->utf8 (string (string-ref s i)))))
                    (let bl ((k 0)) (when (< k (bytevector-length bs)) (set! acc (cons (bytevector-u8-ref bs k) acc)) (bl (+ k 1)))))
                  (loop (+ i 1)))))))


(define (vscode_url_to_path uri)
  (let ((s (LSP->str uri)))
    (cond ((LSP-starts-with? s "file://") (LSP-decodeURI (substring s 7 (string-length s))))
          (else s))))



;; ====================================================================== ;;
;; TYPRINT helpers + string-buffer FILR (= a Chez output-string port)      ;;
;; ====================================================================== ;;
(define (TYPRINT_int2str n) (number->string (if (number? n) (exact (floor n)) 0)))


(define (TYPRINT_stamp2str s) (cond ((number? s) (number->string s)) ((string? s) s) (else (let ((p (open-output-string))) (display s p) (get-output-string p)))))


(define (LSP_strbuf_new) (open-output-string))


(define (LSP_strbuf_get fb) (get-output-string fb))


(define (LSP-read-file path)
  (let* ((p (open-file-input-port path)) (bs (get-bytevector-all p)))
    (close-port p) (if (eof-object? bs) "" (utf8->string bs))))


;; FFI floor leaf: read a file's text, "" on error/missing (the ATS conv module's
;; LSP_other_b2u reads def-target files for cross-file UTF-16 column conversion).
(define (lsp_fs_read path) (guard (e (#t "")) (LSP-read-file path)))


(define LSP_proj_indexed (make-hashtable equal-hash equal?))

  ; normpath -> (cons uri symbols-list)
(define LSP_PROJ_SCAN_CAP (let ((v (getenv "ATS3_PROJ_SCAN_CAP"))) (if v (or (string->number v) 4000) 4000)))


(define (LSP-src-file? name)
  (let ((n (string-length name)))
    (or (and (>= n 5) (string=? (substring name (- n 5) n) ".sats"))
        (and (>= n 5) (string=? (substring name (- n 5) n) ".hats"))
        (and (>= n 5) (string=? (substring name (- n 5) n) ".dats")))))


;; Stage 5: the forward/reverse staload graph + the #staload/#include/#dynload
;; scanner + the reverse closure now live in ATS (xats_lsp_proj).  The glue keeps
;; LSP_proj_indexed (bg-index worklist) + LSP_proj_symbols (completion symbol
;; cache).  These vars hold the ATS closures, set in vscode_initialize.
(define LSP-ats-proj-index #f)

   ; (path) -> "p1\np2..." (dependents)
(define LSP-ats-proj-fwdcount #f)

     ; () -> int
(define LSP-ats-proj-revcount #f)

     ; () -> int
(define (LSP_proj_index_file filePath text0)
  (let ((text (or text0 (guard (e (#t #f)) (LSP-read-file (LSP_norm filePath))))))
    (if (not text) ""
        (let ((n (LSP-ats-proj-index filePath text)))
          (unless (string=? n "") (hashtable-set! LSP_proj_indexed n #t))
          n))))


(define (LSP_proj_scan_dir root)
  (let ((count 0) (capped #f))
    (let loop ((stack (list (LSP_norm root))))
      (cond ((or (null? stack) (>= count LSP_PROJ_SCAN_CAP)) (when (>= count LSP_PROJ_SCAN_CAP) (set! capped #t)))
            (else (let ((dir (car stack)))
                    (set! stack (cdr stack))
                    (unless (or (string=? dir "") (JS_path_is_prelude dir))
                      (guard (e (#t #f))
                        (for-each (lambda (name)
                                    (unless (or (LSP-starts-with? name ".") (string=? name "node_modules"))
                                      (let ((full (string-append dir "/" name)))
                                        (cond ((file-directory? full) (unless (JS_path_is_prelude full) (set! stack (cons full stack))))
                                              ((and (LSP-src-file? name) (< count LSP_PROJ_SCAN_CAP))
                                               (unless (string=? (LSP_proj_index_file full #f) "") (set! count (+ count 1))))))))
                                  (directory-list dir))))
                    (loop stack)))))
    (cons count capped)))


(define (LSP_proj_scan_workspace roots)
  (let ((total 0) (capped #f))
    (for-each (lambda (r) (when (and r (not (string=? r ""))) (let ((res (LSP_proj_scan_dir r))) (set! total (+ total (car res))) (set! capped (or capped (cdr res)))))) roots)
    (LSP-stderr (string-append "[xats-lsp-resident] project-index: files=" (number->string total) " fwd=" (number->string (LSP-ats-proj-fwdcount)) " rev=" (number->string (LSP-ats-proj-revcount)) (if capped " capped=1" "") "\n"))
    _xunit))


;; workspace/symbol fuzzy (case-insensitive subsequence)
(define (LSP-downcase s) (list->string (map char-downcase (string->list s))))



;; ====================================================================== ;;
;; vscode_* helpers (mostly vestigial in the resident; must link)          ;;
;; ====================================================================== ;;
(define (vscode_severity_error$make) 1)


(define (vscode_position_make line offs) (jobj (list (cons "line" (jnum (LSP->int line))) (cons "character" (jnum (LSP->int offs))))))


(define (vscode_range_make pbeg pend) (jobj (list (cons "start" pbeg) (cons "end" pend))))


(define (vscode_diagnostic_make severity range message source)
  (jobj (list (cons "severity" (jnum (LSP->int severity))) (cons "range" range) (cons "message" (jstr (LSP->str message))) (cons "source" (jstr (LSP->str source))))))


(define LSP-side-diags '())

                  ; collector if the ATS path is ever used
(define (vscode_diagnostics_push ds d) (set! LSP-side-diags (cons d LSP-side-diags)) _xunit)


;; regex (only the ".*[.]EXT$" suffix patterns are used by the resident)
(define (LSP-ends-with? s suf) (let ((ns (string-length s)) (nf (string-length suf))) (and (>= ns nf) (string=? (substring s (- ns nf) ns) suf))))


(define (vscode_regex_make pat) (LSP->str pat))


(define (vscode_regex_test re input)
  (let ((p (LSP->str re)) (s (LSP->str input)))
    (let ((i (LSP-string-contains? p "[.]")))
      (if (< i 0) #f
          (let* ((rest (substring p (+ i 3) (string-length p)))
                 (ext (if (and (> (string-length rest) 0) (char=? (string-ref rest (- (string-length rest) 1)) #\$)) (substring rest 0 (- (string-length rest) 1)) rest)))
            (LSP-ends-with? s (string-append "." ext)))))))



;; ====================================================================== ;;
;; transport: Content-Length framed JSON over stdin/stdout                 ;;
;; ====================================================================== ;;
(define LSP-in (standard-input-port))


(define LSP-out (standard-output-port))


(define (LSP-read-line inp)
  (let ((acc '()))
    (let loop ()
      (let ((b (get-u8 inp)))
        (cond ((eof-object? b) (if (null? acc) (eof-object) (list->string (reverse acc))))
              ((= b 13) (get-u8 inp) (list->string (reverse acc)))   ; \r then \n
              ((= b 10) (list->string (reverse acc)))
              (else (set! acc (cons (integer->char b) acc)) (loop)))))))


(define (LSP-trim s)
  (let* ((n (string-length s)) (a (let loop ((i 0)) (if (and (< i n) (memv (string-ref s i) '(#\space #\tab))) (loop (+ i 1)) i)))
         (b (let loop ((i (- n 1))) (if (and (>= i a) (memv (string-ref s i) '(#\space #\tab #\return))) (loop (- i 1)) (+ i 1)))))
    (substring s a b)))


(define (LSP-read-message inp)
  (let loop ((clen #f))
    (let ((line (LSP-read-line inp)))
      (cond ((eof-object? line) (eof-object))
            ((string=? line "") (if clen (let ((body (get-bytevector-n inp clen))) (if (eof-object? body) (eof-object) (utf8->string body))) (loop #f)))
            (else (let ((i (LSP-string-contains? (LSP-downcase line) "content-length:")))
                    (if (>= i 0) (loop (string->number (LSP-trim (substring line (+ i 15) (string-length line))))) (loop clen))))))))


;; debounce + reader-thread queue (replaces the JS async event loop / setTimeout)
(define LSP-qmtx (make-mutex))


(define LSP-qcond (make-condition))


(define LSP-queue '())


(define LSP-qeof #f)



;; ====================================================================== ;;
;; Stage 6 cutover: the FLOOR.  The ATS driver now owns the message loop +  ;;
;; dispatch + validation; this glue provides only the irreducible backend    ;;
;; primitives it calls: framed stdio (reader thread + debounce timeout),     ;;
;; a guard, fs/time, the compiler-stamp signature map, and the FS workspace  ;;
;; scan (which calls the ATS proj-index closure bound via lsp_boot).         ;;
;; ====================================================================== ;;

;; frame a pre-serialized JSON string (the driver builds the JSON) and write it.
(define (LSP-write-raw str)
  (let* ((body (string->utf8 str))
         (hdr (string->utf8 (string-append "Content-Length: " (number->string (bytevector-length body)) "\r\n\r\n"))))
    (put-bytevector LSP-out hdr) (put-bytevector LSP-out body) (flush-output-port LSP-out)))



;; reader thread (lazy-started on the first read): reads framed messages -> a
;; queue of RAW body strings.  The driver parses them with its own JSON module.
(define LSP-reader-started #f)


(define (lsp-ensure-reader)
  (unless LSP-reader-started
    (set! LSP-reader-started #t)
    (fork-thread (lambda ()
      (let rloop ()
        (let ((s (LSP-read-message LSP-in)))
          (with-mutex LSP-qmtx
            (if (eof-object? s) (set! LSP-qeof #t) (set! LSP-queue (append LSP-queue (list s))))
            (condition-signal LSP-qcond))
          (unless (eof-object? s) (rloop))))))))



;; lsp_msg_read(timeout_ms) -> (vector kind body): kind 0=message 1=timeout 2=EOF.
;; timeout_ms < 0 blocks until a message or EOF (the driver's debounce uses the
;; positive timeout to coalesce a pending live-check).
(define (lsp_msg_read timeout_ms)
  (lsp-ensure-reader)
  (with-mutex LSP-qmtx
    (let w ()
      (cond ((pair? LSP-queue) (let ((s (car LSP-queue))) (set! LSP-queue (cdr LSP-queue)) (vector 0 s)))
            (LSP-qeof (vector 2 ""))
            ((< timeout_ms 0) (condition-wait LSP-qcond LSP-qmtx) (w))
            (else (if (condition-wait LSP-qcond LSP-qmtx (make-time 'time-duration (* timeout_ms 1000000) 0)) (w) (vector 1 "")))))))



(define (lsp_msg_write s) (LSP-write-raw s))


(define (lsp_log s) (LSP-stderr s))


(define (lsp_now_ms) (real-time))


(define (lsp_exit) (flush-output-port LSP-out) (exit 0))


;; run a thunk under a catch-all guard (the compiler can abort on self-staloading
;; files); 1 if it threw, else 0.  Replaces the per-handler guards the glue had.
(define (lsp_guard thunk) (guard (e (#t 1)) (thunk) 0))


(define (lsp_fs_exists path) (file-exists? path))



;; boot: bind the two ATS closures the FS scan still needs (the project-index
;; rewire + the prelude classifier).  Called once by the driver before the loop.
(define (lsp_boot projIndex projFwd projRev pathIsPrelude)
  (set! LSP-ats-proj-index projIndex)
  (set! LSP-ats-proj-fwdcount projFwd)
  (set! LSP-ats-proj-revcount projRev)
  (set! LSP-ats-pip pathIsPrelude)
  _xunit)



;; ---- compiler-stamp signature map (kept here; stamp-keyed = backend-specific) --
;; path -> stamp lookup for the watched-files eviction cascade: (vector found stamp).
(define (JS_path2stamp path)
  (let ((st (JS_path2stamp_lookup path))) (if st (vector 1 st) (vector 0 0))))


;; forget a path's signature (+ its path->stamp entry on delete).
(define (JS_sig_forget npath isDelete)
  (let ((st (hashtable-ref LSP_path2stamp npath #f)))
    (when st (hashtable-delete! LSP_signatures st) (when (= isDelete 1) (hashtable-delete! LSP_path2stamp npath))))
  _xunit)


(define (JS_sig_reset) (set! LSP_signatures (make-hashtable equal-hash equal?)) (set! LSP_path2stamp (make-hashtable equal-hash equal?)) _xunit)


(define (JS_stat_count) (LSP_stat_count_reset))



;; ---- FS workspace scan (dirlist is backend-specific) -> the bg-index worklist --
(define (JS_proj_scan rootsJoined)
  (let ((roots (filter (lambda (s) (not (string=? s ""))) (LSP-string-split rootsJoined #\newline))))
    (LSP_proj_scan_workspace roots)))


(define (JS_proj_worklist)
  (let ((out (open-output-string)))
    (vector-for-each (lambda (k) (put-string out k) (put-char out #\newline)) (hashtable-keys LSP_proj_indexed))
    (get-output-string out)))

