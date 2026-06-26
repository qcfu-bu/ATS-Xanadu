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
(define (str_slice s a b) (substring s a b))   ; O(len) codepoint-indexed substring (doc range edits)
(define (cell_make x) (vector x))
(define (cell_get c) (vector-ref c 0))
(define (cell_set c x) (vector-set! c 0 x) _xunit)
(define (lsp_getenv n) (or (getenv n) ""))   ; for the ATS index module's env-configured caches
;; the startup prelude-index metric line (the ATS index module owns the count now).
(define (lsp_log_prelude_index n)
  (put-string (current-error-port) (string-append "[xats-lsp-resident] prelude-index: " (number->string n) " name(s) [env]\n"))
  (flush-output-port (current-error-port)) _xunit)
(define LSP-hexdig "0123456789ABCDEF")
;; stderr log line (the server's diagnostics go to stderr; stdout is the LSP wire)
(define (LSP-stderr s) (put-string (current-error-port) s) (flush-output-port (current-error-port)) _xunit)

;; ---- string utilities -------------------------------------------------------
(define (LSP-string-index s ch start)
  (let ((n (string-length s)))
    (let loop ((i start)) (cond ((>= i n) -1) ((char=? (string-ref s i) ch) i) (else (loop (+ i 1)))))))
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
(define (jbool b) (cons 'bool b))
(define jnull 'jnull)
(define (jobj kvs) (cons 'obj kvs))
(define (jarr vs) (cons 'arr vs))
;; a pre-serialized JSON string spliced verbatim into the wire (the ATS index
;; builders return serialized jval; the glue wraps it so json-emit emits it raw).
(define (jraw s) (cons 'raw s))

(define (json-escape out s)
  (put-char out #\")
  (let ((n (string-length s)))
    (let loop ((i 0))
      (when (< i n)
        (let* ((c (string-ref s i)) (code (char->integer c)))
          (cond
           ((char=? c #\") (put-string out "\\\""))
           ((char=? c #\\) (put-string out "\\\\"))
           ((char=? c #\backspace) (put-string out "\\b"))
           ((char=? c #\page) (put-string out "\\f"))
           ((char=? c #\newline) (put-string out "\\n"))
           ((char=? c #\return) (put-string out "\\r"))
           ((char=? c #\tab) (put-string out "\\t"))
           ((< code #x20)
            (put-string out "\\u00")
            (put-char out (string-ref LSP-hexdig (fxand (fxsrl code 4) 15)))
            (put-char out (string-ref LSP-hexdig (fxand code 15))))
           (else (put-char out c))))
        (loop (+ i 1)))))
  (put-char out #\"))

;; compact encoder (no pretty indent — LSP messages are wire format)
(define (json-emit out v)
  (cond
   ((eq? v 'jnull) (put-string out "null"))
   ((pair? v)
    (case (car v)
      ((str) (json-escape out (cdr v)))
      ((num) (let ((n (cdr v))) (put-string out (if (and (number? n) (integer? n) (exact? n))
                                                     (number->string n)
                                                     (number->string (LSP->int n))))))
      ((bool) (put-string out (if (cdr v) "true" "false")))
      ((raw) (put-string out (cdr v)))
      ((obj)
       (put-char out #\{)
       (let loop ((kvs (cdr v)) (first #t))
         (unless (null? kvs)
           (unless first (put-char out #\,))
           (json-escape out (caar kvs)) (put-char out #\:) (json-emit out (cdar kvs))
           (loop (cdr kvs) #f)))
       (put-char out #\}))
      ((arr)
       (put-char out #\[)
       (let loop ((vs (cdr v)) (first #t))
         (unless (null? vs)
           (unless first (put-char out #\,))
           (json-emit out (car vs)) (loop (cdr vs) #f)))
       (put-char out #\]))
      (else (error 'json-emit "bad json value" v))))
   (else (error 'json-emit "bad json value" v))))

(define (json-string v) (let ((o (open-output-string))) (json-emit o v) (get-output-string o)))

;; ---- JSON parser: string -> a Scheme value.  Objects -> hashtable (string-keyed,
;; equal?), arrays -> vector, strings -> string, numbers -> number, true/false ->
;; #t/#f, null -> the symbol 'null.  Accessors below read this shape.
(define (json-parse s)
  (let ((n (string-length s)) (i 0))
    (define (peek) (if (< i n) (string-ref s i) #\nul))
    (define (adv) (set! i (+ i 1)))
    (define (skip-ws) (let loop () (when (and (< i n) (memv (string-ref s i) '(#\space #\tab #\newline #\return))) (adv) (loop))))
    (define (parse-value)
      (skip-ws)
      (let ((c (peek)))
        (cond
         ((char=? c #\{) (parse-object))
         ((char=? c #\[) (parse-array))
         ((char=? c #\") (parse-string))
         ((or (char=? c #\-) (char<=? #\0 c #\9)) (parse-number))
         ((char=? c #\t) (set! i (+ i 4)) #t)
         ((char=? c #\f) (set! i (+ i 5)) #f)
         ((char=? c #\n) (set! i (+ i 4)) 'null)
         (else (error 'json-parse "unexpected char" c i)))))
    (define (parse-object)
      (adv) (skip-ws)
      (let ((h (make-hashtable string-hash string=?)))
        (if (char=? (peek) #\}) (begin (adv) h)
            (let loop ()
              (skip-ws)
              (let ((k (parse-string)))
                (skip-ws) (adv)                      ; consume ':'
                (let ((v (parse-value)))
                  (hashtable-set! h k v)
                  (skip-ws)
                  (cond ((char=? (peek) #\,) (adv) (loop))
                        (else (adv) h))))))))         ; consume '}'
    (define (parse-array)
      (adv) (skip-ws)
      (if (char=? (peek) #\]) (begin (adv) (vector))
          (let loop ((acc '()))
            (let ((v (parse-value)))
              (skip-ws)
              (cond ((char=? (peek) #\,) (adv) (loop (cons v acc)))
                    (else (adv) (list->vector (reverse (cons v acc)))))))))
    (define (parse-string)
      (skip-ws) (adv)                                  ; consume opening quote
      (let ((out (open-output-string)))
        (let loop ()
          (let ((c (peek)))
            (cond
             ((char=? c #\") (adv) (get-output-string out))
             ((char=? c #\\)
              (adv)
              (let ((e (peek)))
                (adv)
                (case e
                  ((#\") (put-char out #\")) ((#\\) (put-char out #\\)) ((#\/) (put-char out #\/))
                  ((#\b) (put-char out #\backspace)) ((#\f) (put-char out #\page))
                  ((#\n) (put-char out #\newline)) ((#\r) (put-char out #\return)) ((#\t) (put-char out #\tab))
                  ((#\u)
                   (let ((cp (string->number (substring s i (+ i 4)) 16)))
                     (set! i (+ i 4))
                     ;; surrogate pair?
                     (if (and (>= cp #xD800) (<= cp #xDBFF) (< (+ i 6) (+ n 1))
                              (char=? (string-ref s i) #\\) (char=? (string-ref s (+ i 1)) #\u))
                         (let ((lo (string->number (substring s (+ i 2) (+ i 6)) 16)))
                           (set! i (+ i 6))
                           (put-char out (integer->char (+ #x10000 (* (- cp #xD800) #x400) (- lo #xDC00)))))
                         (put-char out (integer->char cp)))))
                  (else (put-char out e)))
                (loop)))
             (else (put-char out c) (adv) (loop)))))))
    (define (parse-number)
      (let ((start i))
        (when (char=? (peek) #\-) (adv))
        (let loop () (when (and (< i n) (let ((c (peek))) (or (char<=? #\0 c #\9) (memv c '(#\. #\e #\E #\+ #\-))))) (adv) (loop)))
        (string->number (substring s start i))))
    (parse-value)))

;; accessors over the parsed shape (objects = hashtable, arrays = vector)
(define (jget o k . default)
  (if (hashtable? o) (hashtable-ref o k (if (null? default) 'null (car default)))
      (if (null? default) 'null (car default))))
(define (jget* o . path)                         ; nested: (jget* m "params" "textDocument" "uri")
  (let loop ((o o) (p path))
    (cond ((null? p) o)
          ((eq? o 'null) 'null)
          ((not (hashtable? o)) 'null)
          (else (loop (hashtable-ref o (car p) 'null) (cdr p))))))
(define (jnum->int x) (if (number? x) (exact (floor x)) 0))
(define (jstr-or x d) (if (string? x) x d))

;; ====================================================================== ;;
;; depset + depgraph: now implemented in ATS (xats_lsp_resident.dats) over the   ;;
;; portable cell (xats_lsp_ref.hats).  The glue only OWNS the two top-level graph ;;
;; OBJECTS (created here, passed OPAQUE to the ATS validator/pruner, reset on a   ;;
;; prelude reload) — it never inspects them.  An empty graph is a cell holding    ;;
;; the ATS empty list: list_nil() emits as (vector 0), so an empty depgraph is    ;;
;; (cell_make (vector 0)).  JS_depset_*/JS_depgraph_* are GONE (ATS owns them).   ;;
;; ====================================================================== ;;

;; ATS empty list = (vector 0); an empty depset/depgraph = a cell holding it.
(define (LSP_empty_graph) (cell_make (vector 0)))

;; the reverse depgraph (dependents) + the R2a forward graph (staloads).
(define LSP_dependencies (LSP_empty_graph))
(define LSP_fwd (LSP_empty_graph))
(define (JS_fwd_graph) LSP_fwd)

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
;; The LOADED prelude/compiler tree (the files the_tr12env_pvsl00d parses at
;; startup) lives ONLY under these $XATSHOME subdirs — NOT the whole repo.  Using
;; the bare $XATSHOME prefix wrongly classified user files that merely live inside
;; the repo (e.g. language-server/, frontend/) as immutable, disabling
;; live-on-change for them and forcing a full prelude reload on every save.  A
;; file is "immutable prelude" iff it is under one of these roots.
(define LSP_prelude_roots
  (if (string=? LSP_xatshome "") '()
      (let ((h (substring LSP_xatshome 0 (- (string-length LSP_xatshome) 1))))   ; strip trailing /
        (map (lambda (d) (string-append h "/" d "/")) '("prelude" "srcgen1" "srcgen2" "xassets")))))
(define (LSP-any pred lst) (and (pair? lst) (or (pred (car lst)) (LSP-any pred (cdr lst)))))
(define (JS_path_is_prelude path)
  (if (null? LSP_prelude_roots) #f
      (let ((s (LSP_norm path)))
        (and (not (string=? s ""))
             (let ((sp (string-append s "/"))) (LSP-any (lambda (r) (LSP-starts-with? sp r)) LSP_prelude_roots))))))

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

;; ====================================================================== ;;
;; friendly type-name map (leaf head-name remap in mismatch messages)      ;;
;; ====================================================================== ;;
(define LSP_TYPENAME
  (let ((h (make-hashtable string-hash string=?)))
    (for-each (lambda (kv) (hashtable-set! h (car kv) (cdr kv)))
     '(("gint_type" . "int") ("bool_type" . "bool") ("char_type" . "char")
       ("gflt_type" . "double") ("xats_void_t" . "void") ("string_i0_tx" . "string")
       ("the_s2exp_strn0" . "string") ("the_s2exp_sint0" . "int") ("the_s2exp_uint0" . "uint")
       ("the_s2exp_slint0" . "lint") ("the_s2exp_ulint0" . "ulint") ("the_s2exp_sllint0" . "llint")
       ("the_s2exp_ullint0" . "ullint") ("the_s2exp_sflt0" . "float") ("the_s2exp_dflt0" . "double")
       ("the_s2exp_list0" . "list") ("the_s2exp_optn0" . "optn") ("the_s2exp_lazy0" . "lazy")
       ("the_s2exp_p1" . "ptr") ("the_s2exp_p2" . "p2tr") ("the_s2exp_bool0" . "bool")
       ("the_s2exp_char0" . "char") ("the_s2exp_void" . "void") ("strn" . "string")
       ("xats_sint_t" . "int") ("xats_uint_t" . "uint") ("xats_slint_t" . "lint") ("xats_ulint_t" . "ulint")
       ("xats_ssize_t" . "ssize") ("xats_usize_t" . "usize") ("xats_sllint_t" . "llint") ("xats_ullint_t" . "ullint")
       ("xats_strn_t" . "string") ("xats_bool_t" . "bool") ("xats_char_t" . "char") ("xats_dflt_t" . "double")
       ("p1tr_tbox" . "ptr") ("p2tr_tbox" . "p2tr") ("list_t0_i0_tx" . "list") ("list_vt_i0_vx" . "list_vt")
       ("optn_t0_i0_tx" . "optn") ("optn_vt_i0_vx" . "optn_vt") ("lazy_t0_tx" . "lazy") ("lazy_vt_vx" . "lazy_vt")))
    h))
(define (LSP-id-char? c) (or (char<=? #\A c #\Z) (char<=? #\a c #\z) (char<=? #\0 c #\9) (char=? c #\_) (char=? c #\$)))
(define (LSP-id-start? c) (or (char<=? #\A c #\Z) (char<=? #\a c #\z) (char=? c #\_)))
(define (LSP-all-id? nm)
  (and (> (string-length nm) 0)
       (let loop ((k 0)) (cond ((>= k (string-length nm)) #t) ((LSP-id-char? (string-ref nm k)) (loop (+ k 1))) (else #f)))))
;; replace any `name` (backtick-delimited identifier) that has a friendly alias.
(define (LSP_friendly msg)
  (let* ((s (LSP->str msg)) (n (string-length s)) (out (open-output-string)))
    (let loop ((i 0))
      (cond
       ((>= i n) (get-output-string out))
       ((char=? (string-ref s i) #\`)
        (let scan ((j (+ i 1)))
          (cond
           ((and (< j n) (char=? (string-ref s j) #\`) (> j (+ i 1)) (LSP-id-start? (string-ref s (+ i 1))))
            (let ((nm (substring s (+ i 1) j)))
              (if (and (LSP-all-id? nm) (hashtable-contains? LSP_TYPENAME nm))
                  (begin (put-char out #\`) (put-string out (hashtable-ref LSP_TYPENAME nm #f)) (put-char out #\`) (loop (+ j 1)))
                  (begin (put-char out #\`) (loop (+ i 1))))))
           ((and (< j n) (LSP-id-char? (string-ref s j))) (scan (+ j 1)))
           (else (put-char out #\`) (loop (+ i 1))))))
       (else (put-char out (string-ref s i)) (loop (+ i 1)))))))

;; ====================================================================== ;;
;; URL <-> path (percent decode/encode) + file:// builders                 ;;
;; ====================================================================== ;;
(define (LSP-uric-unreserved? c)
  (or (char<=? #\A c #\Z) (char<=? #\a c #\z) (char<=? #\0 c #\9) (memv c '(#\- #\_ #\. #\! #\~ #\* #\' #\( #\)))))
(define (LSP-hexval c) (cond ((char<=? #\0 c #\9) (- (char->integer c) 48)) ((char<=? #\a c #\f) (+ 10 (- (char->integer c) 97))) ((char<=? #\A c #\F) (+ 10 (- (char->integer c) 65))) (else 0)))
(define (LSP-pct-byte out b)
  (put-char out #\%) (put-char out (string-ref LSP-hexdig (fxand (fxsrl b 4) 15))) (put-char out (string-ref LSP-hexdig (fxand b 15))))
(define (LSP-encodeURIComponent s)
  (let ((out (open-output-string)) (bytes (string->utf8 s)))
    (let loop ((i 0))
      (if (>= i (bytevector-length bytes)) (get-output-string out)
          (let ((b (bytevector-u8-ref bytes i)))
            (if (and (< b 128) (LSP-uric-unreserved? (integer->char b))) (put-char out (integer->char b)) (LSP-pct-byte out b))
            (loop (+ i 1)))))))
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
;; path -> file:// uri (per-segment encode); remap the file under check to the doc uri.
(define LSP_cur_path #f)
(define LSP_cur_uri #f)
(define (LSP_path2uri p)
  (let ((s (LSP->str p)))
    (cond
     ((string=? s "") "")
     ((LSP-starts-with? s "file://") s)
     (else
      (let ((abs (if (and (> (string-length s) 0) (char=? (string-ref s 0) #\/)) s (LSP_norm s))))
        (if (and LSP_cur_path LSP_cur_uri (string=? (LSP_norm abs) (LSP_norm LSP_cur_path))) LSP_cur_uri
            (string-append "file://"
              (let ((segs (LSP-string-split abs #\/)))
                (let join ((segs segs) (first #t) (o (open-output-string)))
                  (cond ((null? segs) (get-output-string o))
                        (else (unless first (put-char o #\/)) (put-string o (LSP-encodeURIComponent (car segs))) (join (cdr segs) #f o))))))))))))
(define (LSP_file_uri n) (string-append "file://" (let ((segs (LSP-string-split (LSP->str n) #\/))) (let join ((segs segs) (first #t) (o (open-output-string))) (cond ((null? segs) (get-output-string o)) (else (unless first (put-char o #\/)) (put-string o (LSP-encodeURIComponent (car segs))) (join (cdr segs) #f o)))))))

;; ====================================================================== ;;
;; TYPRINT helpers + string-buffer FILR (= a Chez output-string port)      ;;
;; ====================================================================== ;;
(define (TYPRINT_int2str n) (number->string (if (number? n) (exact (floor n)) 0)))
(define (TYPRINT_stamp2str s) (cond ((number? s) (number->string s)) ((string? s) s) (else (let ((p (open-output-string))) (display s p) (get-output-string p)))))
(define (LSP_strbuf_new) (open-output-string))
(define (LSP_strbuf_get fb) (get-output-string fb))

;; ====================================================================== ;;
;; UTF-16 column conversion (byte ncol -> UTF-16 code-unit column)         ;;
;; ====================================================================== ;;
;; Build a converter over one source text: per-line byte->utf16 prefix, lazily,
;; only for lines containing a non-ASCII byte (ASCII lines: byteCol == utf16Col).
(define LSP_u16_enabled (not (equal? (getenv "ATS3_LSP_UTF16") "0")))
;; byte->utf16 prefix for line bytes [s,e): pref[k] = utf16 code units in [s,s+k).
(define (LSP-u16-prefix bytes s e)
  (let* ((len (- e s)) (pref (make-vector (+ len 1) 0)))
    (let loop ((i s) (k 0) (units 0))
      (if (>= i e)
          (begin (vector-set! pref (min k len) units)
                 (let fill ((j (+ k 1))) (when (<= j len) (vector-set! pref j units) (fill (+ j 1))))
                 pref)
          (let* ((b (bytevector-u8-ref bytes i))
                 (sq (cond ((< b #x80) 1) ((< b #xE0) 2) ((< b #xF0) 3) (else 4)))
                 (cp0 (cond ((< b #x80) b) ((< b #xE0) (fxand b #x1f)) ((< b #xF0) (fxand b #x0f)) (else (fxand b #x07)))))
            (let asm ((j 1) (cp cp0) (ok (<= (+ i sq) e)))
              (if (and ok (< j sq))
                  (let ((cb (bytevector-u8-ref bytes (+ i j))))
                    (if (not (= (fxand cb #xc0) #x80)) (asm sq cp #f) (asm (+ j 1) (fxior (fxsll cp 6) (fxand cb #x3f)) ok)))
                  (let* ((sq2 (if ok sq 1)) (cp2 (if ok cp b)) (u (if (>= cp2 #x10000) 2 1)))
                    (let fillp ((j 0)) (when (and (< j sq2) (<= (+ k j) len)) (vector-set! pref (+ k j) units) (fillp (+ j 1))))
                    (loop (+ i sq2) (+ k sq2) (+ units u))))))))))
;; line info: #(ascii len #f) or #(wide len prefix-vector)
(define (LSP-u16-lineinfo bytes starts nb line)
  (if (>= line (vector-length starts)) (vector 'ascii 0 #f)
      (let* ((s (vector-ref starts line))
             (e (if (< (+ line 1) (vector-length starts)) (- (vector-ref starts (+ line 1)) 1) nb)))
        (let scan ((i s))
          (cond ((>= i e) (vector 'ascii (- e s) #f))
                ((>= (bytevector-u8-ref bytes i) #x80) (vector 'wide (- e s) (LSP-u16-prefix bytes s e)))
                (else (scan (+ i 1))))))))
(define (LSP_u16_make text)
  (let* ((bytes (string->utf8 (LSP->str text))) (nb (bytevector-length bytes))
         (starts (let loop ((i 0) (acc '(0)))
                   (cond ((>= i nb) (list->vector (reverse acc)))
                         ((= (bytevector-u8-ref bytes i) 10) (loop (+ i 1) (cons (+ i 1) acc)))
                         (else (loop (+ i 1) acc)))))
         (cache (make-hashtable equal-hash equal?)))
    (define (line-info line)
      (or (hashtable-ref cache line #f)
          (let ((info (LSP-u16-lineinfo bytes starts nb line))) (hashtable-set! cache line info) info)))
    (lambda (line byteCol)
      (let ((c (LSP->int byteCol)))
        (if (<= c 0) 0
            (let ((info (line-info (LSP->int line))))
              (if (eq? (vector-ref info 0) 'ascii) c
                  (let ((pref (vector-ref info 2)))
                    (if (>= c (vector-length pref)) (vector-ref pref (- (vector-length pref) 1)) (vector-ref pref c))))))))))
(define LSP_cur_u16 #f)
(define LSP_cur_path_norm #f)
(define (LSP_cur_b2u line byteCol) (if (and LSP_u16_enabled LSP_cur_u16) (LSP_cur_u16 line byteCol) (LSP->int byteCol)))
(define LSP_other_u16 (make-hashtable equal-hash equal?))
(define (LSP_other_b2u path line byteCol)
  (let ((c (LSP->int byteCol)))
    (cond ((not LSP_u16_enabled) c)
          ((<= c 0) 0)
          (else (let ((n (LSP_norm path)))
                  (if (string=? n "") c
                      (let ((conv (if (hashtable-contains? LSP_other_u16 n) (hashtable-ref LSP_other_u16 n #f)
                                      (let ((cv (guard (e (#t #f)) (LSP_u16_make (LSP-read-file n))))) (hashtable-set! LSP_other_u16 n cv) cv))))
                        (if conv (conv line byteCol) c))))))))
(define (LSP-read-file path)
  (let* ((p (open-file-input-port path)) (bs (get-bytevector-all p)))
    (close-port p) (if (eof-object? bs) "" (utf8->string bs))))
;; FFI floor leaf: read a file's text, "" on error/missing (the ATS conv module's
;; LSP_other_b2u reads def-target files for cross-file UTF-16 column conversion).
(define (lsp_fs_read path) (guard (e (#t "")) (LSP-read-file path)))

;; ====================================================================== ;;
;; harvest accumulators (per-check) + the per-uri index                    ;;
;; ====================================================================== ;;
(define LSP_cur_diags '())   (define LSP_cur_hovers '())  (define LSP_cur_defs '())
(define LSP_cur_tokens '())  (define LSP_cur_symbols '()) (define LSP_cur_inlays '())
(define LSP_cur_scopes '())  (define LSP_cur_members '())
;; uri -> #(hovers defs semtokens symbols inlays scopes members)
(define LSP_index (make-hashtable equal-hash equal?))
(define (LSP-idx-get uri) (hashtable-ref LSP_index uri #f))
(define (idx-hovers r) (vector-ref r 0)) (define (idx-defs r) (vector-ref r 1))
(define (idx-sem r) (vector-ref r 2)) (define (idx-syms r) (vector-ref r 3))
(define (idx-inlays r) (vector-ref r 4)) (define (idx-scopes r) (vector-ref r 5))
(define (idx-members r) (vector-ref r 6))

;; semantic token legend (indices/bits must match the DATS TT_*/TM_* constants)
(define LSP_TOKEN_TYPES (list "namespace" "type" "typeParameter" "parameter" "variable" "property" "function" "enumMember" "keyword" "string" "number" "operator" "comment"))
(define LSP_TOKEN_MODS  (list "declaration" "definition" "readonly" "static" "defaultLibrary"))
(define LSP_TOKEN_MOD_DEFAULTLIB (fxsll 1 4))   ; index of 'defaultLibrary'

(define (jrange l0 c0 l1 c1)
  (jobj (list (cons "start" (jobj (list (cons "line" (jnum l0)) (cons "character" (jnum c0)))))
              (cons "end"   (jobj (list (cons "line" (jnum l1)) (cons "character" (jnum c1))))))))

(define (LSP_def_in_current defUri) (and LSP_cur_uri (string=? defUri LSP_cur_uri)))

;; ---- push sinks (byte cols -> UTF-16 here; rows stored UTF-16) ----
(define (LSP_diag_push l0 c0 l1 c1 code message)
  (set! LSP_cur_diags
    (cons (vector (LSP->int l0) (LSP_cur_b2u l0 c0) (LSP->int l1) (LSP_cur_b2u l1 c1)
                  (LSP->str code) (LSP_friendly message)) LSP_cur_diags)) _xunit)
(define (LSP_hover_push l0 c0 l1 c1 typ kind)
  (let ((t (LSP->str typ)))
    (if (string=? t "") _xunit
        (begin (set! LSP_cur_hovers
                 (cons (vector (LSP->int l0) (LSP_cur_b2u l0 c0) (LSP->int l1) (LSP_cur_b2u l1 c1) t (LSP->str kind)) LSP_cur_hovers)) _xunit))))
(define (LSP_def_push ul0 uc0 ul1 uc1 defpath dl0 dc0 dl1 dc1 entity hastdef tdpath tl0 tc0 tl1 tc1)
  (let ((defUri (LSP_path2uri defpath)))
    (if (string=? defUri "") _xunit
        (let-values (((dc0u dc1u) (if (LSP_def_in_current defUri)
                                      (values (LSP_cur_b2u dl0 dc0) (LSP_cur_b2u dl1 dc1))
                                      (values (LSP_other_b2u defpath dl0 dc0) (LSP_other_b2u defpath dl1 dc1)))))
          (let ((tdUri "") (tl0v 0) (tc0v 0) (tl1v 0) (tc1v 0))
            (when (= (LSP->int hastdef) 1)
              (let ((u (LSP_path2uri tdpath)))
                (unless (string=? u "")
                  (set! tdUri u) (set! tl0v (LSP->int tl0)) (set! tl1v (LSP->int tl1))
                  (if (LSP_def_in_current u)
                      (begin (set! tc0v (LSP_cur_b2u tl0 tc0)) (set! tc1v (LSP_cur_b2u tl1 tc1)))
                      (begin (set! tc0v (LSP_other_b2u tdpath tl0 tc0)) (set! tc1v (LSP_other_b2u tdpath tl1 tc1)))))))
            (set! LSP_cur_defs
              (cons (vector (LSP->int ul0) (LSP_cur_b2u ul0 uc0) (LSP->int ul1) (LSP_cur_b2u ul1 uc1)
                            defUri (LSP->int dl0) dc0u (LSP->int dl1) dc1u (LSP->str entity)
                            tdUri tl0v tc0v tl1v tc1v) LSP_cur_defs))
            _xunit)))))
(define (LSP_token_push l0 c0 l1 c1 ttype tmods defpath)
  (if (or (< (LSP->int l0) 0) (< (LSP->int c0) 0) (not (= (LSP->int l0) (LSP->int l1)))) _xunit
      (let* ((cu0 (LSP_cur_b2u l0 c0)) (cu1 (LSP_cur_b2u l1 c1)) (len (- cu1 cu0)))
        (if (<= len 0) _xunit
            (let ((mods (LSP->int tmods)))
              (when (and (string? defpath) (not (string=? defpath "")) (JS_path_is_prelude defpath))
                (set! mods (fxior mods LSP_TOKEN_MOD_DEFAULTLIB)))
              (set! LSP_cur_tokens (cons (vector (LSP->int l0) cu0 len (LSP->int ttype) mods) LSP_cur_tokens))
              _xunit)))))
(define (LSP_symbol_push l0 c0 l1 c1 name kind container typ)
  (if (or (< (LSP->int l0) 0) (< (LSP->int c0) 0) (string=? (LSP->str name) "")) _xunit
      (begin (set! LSP_cur_symbols
               (cons (vector (LSP->int l0) (LSP_cur_b2u l0 c0) (LSP->int l1) (LSP_cur_b2u l1 c1)
                             (LSP->str name) (LSP->int kind) (LSP->str container) (LSP->str typ)) LSP_cur_symbols)) _xunit)))
(define (LSP_inlay_push line col label kind)
  (if (or (< (LSP->int line) 0) (< (LSP->int col) 0) (string=? (LSP->str label) "")) _xunit
      (begin (set! LSP_cur_inlays (cons (vector (LSP->int line) (LSP_cur_b2u line col) (LSP->str label) (LSP->int kind)) LSP_cur_inlays)) _xunit)))
(define (LSP_scope_push l0 c0 l1 c1 name typ)
  (if (or (< (LSP->int l0) 0) (< (LSP->int c0) 0) (string=? (LSP->str name) "")) _xunit
      (begin (set! LSP_cur_scopes (cons (vector (LSP->int l0) (LSP_cur_b2u l0 c0) (LSP->int l1) (LSP_cur_b2u l1 c1) (LSP->str name) (LSP->str typ)) LSP_cur_scopes)) _xunit)))
(define (LSP_member_push l0 c0 l1 c1 name typ)
  (if (or (< (LSP->int l0) 0) (< (LSP->int c0) 0) (string=? (LSP->str name) "")) _xunit
      (begin (set! LSP_cur_members (cons (vector (LSP->int l0) (LSP_cur_b2u l0 c0) (LSP->int l1) (LSP_cur_b2u l1 c1) (LSP->str name) (LSP->str typ)) LSP_cur_members)) _xunit)))

;; ---- dedups (mirror the checker glue; reverse-then-sort for stable order) ----
(define (LSP-num-cat . xs) (let ((o (open-output-string))) (for-each (lambda (x) (if (number? x) (put-string o (number->string x)) (put-string o x)) (put-char o #\:)) xs) (get-output-string o)))
(define (vr v i) (vector-ref v i))
(define (LSP_posLE la ca lb cb) (or (< la lb) (and (= la lb) (<= ca cb))))
(define (LSP_rank code)
  (cond ((string=? code "type-mismatch") 5) ((string=? code "unbound-identifier") 5)
        ((string=? code "unresolved-template") 4) ((string=? code "pattern-error") 3)
        ((string=? code "unknown") 2) ((string=? code "decl-error") 1) (else 2)))
(define (LSP_dedup_diags diags)
  (let ((xs (filter (lambda (d) (and (>= (vr d 0) 0) (>= (vr d 1) 0))) diags)) (best (make-hashtable string-hash string=?)))
    (for-each (lambda (d)
                (let* ((key (LSP-num-cat (vr d 0) (vr d 1))) (cur (hashtable-ref best key #f)))
                  (if (not cur) (hashtable-set! best key d)
                      (let ((de (+ (* (vr d 2) 1000000) (vr d 3))) (ce (+ (* (vr cur 2) 1000000) (vr cur 3))))
                        (cond ((< de ce) (hashtable-set! best key d))
                              ((and (= de ce) (> (LSP_rank (vr d 4)) (LSP_rank (vr cur 4)))) (hashtable-set! best key d)))))))
              xs)
    (let ((ys (vector->list (hashtable-values best))))
      (define (overlap a b) (and (LSP_posLE (vr a 0) (vr a 1) (vr b 2) (vr b 3)) (LSP_posLE (vr b 0) (vr b 1) (vr a 2) (vr a 3))))
      (let ((kept (filter (lambda (d)
                            (let loop ((es ys))
                              (cond ((null? es) #t) ((eq? (car es) d) (loop (cdr es)))
                                    (else (let* ((e (car es))
                                                 (inside (and (LSP_posLE (vr d 0) (vr d 1) (vr e 0) (vr e 1)) (LSP_posLE (vr e 2) (vr e 3) (vr d 2) (vr d 3))))
                                                 (strictly (and inside (not (and (= (vr e 0) (vr d 0)) (= (vr e 1) (vr d 1)) (= (vr e 2) (vr d 2)) (= (vr e 3) (vr d 3)))))))
                                            (cond (strictly #f)
                                                  ((and (string=? (vr d 4) "decl-error") (not (string=? (vr e 4) "decl-error")) (overlap d e) (> (LSP_rank (vr e 4)) (LSP_rank (vr d 4)))) #f)
                                                  (else (loop (cdr es)))))))))
                          ys)))
        (list-sort (lambda (a b) (cond ((not (= (vr a 0) (vr b 0))) (< (vr a 0) (vr b 0))) ((not (= (vr a 1) (vr b 1))) (< (vr a 1) (vr b 1)))
                                       ((not (= (vr a 2) (vr b 2))) (< (vr a 2) (vr b 2))) (else (< (vr a 3) (vr b 3))))) kept)))))
(define (LSP_dedup_hovers hs)
  (let ((seen (make-hashtable string-hash string=?)) (out '()))
    (for-each (lambda (h)
                (when (and (>= (vr h 0) 0) (>= (vr h 1) 0) (not (or (< (vr h 2) (vr h 0)) (and (= (vr h 2) (vr h 0)) (< (vr h 3) (vr h 1))))))
                  (let ((k (LSP-num-cat (vr h 0) (vr h 1) (vr h 2) (vr h 3) (vr h 5) (vr h 4))))
                    (unless (hashtable-contains? seen k) (hashtable-set! seen k #t) (set! out (cons h out)))))) hs)
    (list-sort (lambda (a b) (cond ((not (= (vr a 0) (vr b 0))) (< (vr a 0) (vr b 0))) ((not (= (vr a 1) (vr b 1))) (< (vr a 1) (vr b 1)))
                                   ((not (= (vr a 2) (vr b 2))) (> (vr a 2) (vr b 2))) (else (> (vr a 3) (vr b 3))))) (reverse out))))
(define (LSP_dedup_defs ds)
  (let ((seen (make-hashtable string-hash string=?)) (out '()))
    (for-each (lambda (d)
                (when (and (>= (vr d 0) 0) (>= (vr d 1) 0) (>= (vr d 5) 0) (>= (vr d 6) 0))
                  (let ((k (LSP-num-cat (vr d 0) (vr d 1) (vr d 2) (vr d 3) (vr d 4) (vr d 5) (vr d 6) (vr d 7) (vr d 8) (vr d 9))))
                    (unless (hashtable-contains? seen k) (hashtable-set! seen k #t) (set! out (cons d out)))))) ds)
    (list-sort (lambda (a b) (cond ((not (= (vr a 0) (vr b 0))) (< (vr a 0) (vr b 0))) ((not (= (vr a 1) (vr b 1))) (< (vr a 1) (vr b 1)))
                                   ((not (= (vr a 2) (vr b 2))) (< (vr a 2) (vr b 2))) (else (< (vr a 3) (vr b 3))))) (reverse out))))
(define (LSP_dedup_symbols ss)
  (let ((seen (make-hashtable string-hash string=?)) (out '()))
    (for-each (lambda (s) (when (and (>= (vr s 0) 0) (>= (vr s 1) 0))
                            (let ((k (LSP-num-cat (vr s 0) (vr s 1) (vr s 2) (vr s 3) (vr s 5) (vr s 4) (vr s 6))))
                              (unless (hashtable-contains? seen k) (hashtable-set! seen k #t) (set! out (cons s out)))))) ss)
    (list-sort (lambda (a b) (cond ((not (= (vr a 0) (vr b 0))) (< (vr a 0) (vr b 0))) (else (< (vr a 1) (vr b 1))))) (reverse out))))
(define (LSP_dedup_inlays hs)
  (let ((seen (make-hashtable string-hash string=?)) (out '()))
    (for-each (lambda (h) (when (and (>= (vr h 0) 0) (>= (vr h 1) 0))
                            (let ((k (LSP-num-cat (vr h 0) (vr h 1) (vr h 2) (vr h 3))))
                              (unless (hashtable-contains? seen k) (hashtable-set! seen k #t) (set! out (cons h out)))))) hs)
    (list-sort (lambda (a b) (cond ((not (= (vr a 0) (vr b 0))) (< (vr a 0) (vr b 0))) (else (< (vr a 1) (vr b 1))))) (reverse out))))
(define (LSP_dedup_scopes ss)
  (let ((seen (make-hashtable string-hash string=?)) (out '()))
    (for-each (lambda (s) (when (and (>= (vr s 0) 0) (>= (vr s 1) 0))
                            (let ((k (LSP-num-cat (vr s 0) (vr s 1) (vr s 2) (vr s 3) (vr s 4) (vr s 5))))
                              (unless (hashtable-contains? seen k) (hashtable-set! seen k #t) (set! out (cons s out)))))) ss)
    (reverse out)))
(define (LSP_dedup_members ms)
  (let ((seen (make-hashtable string-hash string=?)) (out '()))
    (for-each (lambda (m) (when (and (>= (vr m 0) 0) (>= (vr m 1) 0))
                            (let ((k (LSP-num-cat (vr m 0) (vr m 1) (vr m 2) (vr m 3) (vr m 4))))
                              (unless (hashtable-contains? seen k) (hashtable-set! seen k #t) (set! out (cons m out)))))) ms)
    (reverse out)))
;; delta-encode tokens -> flat list of ints (5-tuples), collapse same-start (keep shortest)
(define (LSP_encode_tokens toks)
  (let ((byStart (make-hashtable string-hash string=?)))
    (for-each (lambda (t) (when (and (>= (vr t 0) 0) (>= (vr t 1) 0) (> (vr t 2) 0))
                            (let* ((k (LSP-num-cat (vr t 0) (vr t 1))) (cur (hashtable-ref byStart k #f)))
                              (when (or (not cur) (< (vr t 2) (vr cur 2))) (hashtable-set! byStart k t))))) toks)
    (let ((xs (list-sort (lambda (a b) (cond ((not (= (vr a 0) (vr b 0))) (< (vr a 0) (vr b 0))) (else (< (vr a 1) (vr b 1)))))
                         (vector->list (hashtable-values byStart)))))
      (let loop ((xs xs) (pl 0) (pc 0) (acc '()))
        (if (null? xs) (reverse acc)
            (let* ((t (car xs)) (dl (- (vr t 0) pl)) (dc (if (= dl 0) (- (vr t 1) pc) (vr t 1))))
              (loop (cdr xs) (vr t 0) (vr t 1) (cons (vr t 4) (cons (vr t 3) (cons (vr t 2) (cons dc (cons dl acc))))))))))))

;; ====================================================================== ;;
;; request builders (read the per-uri index -> LSP JSON values)            ;;
;; ====================================================================== ;;
(define (LSP-span l0 c0 l1 c1) (+ (* (- l1 l0) 1000000) (- c1 c0)))
(define (LSP-innermost-by rows ri pl pc)        ; ri = base index of a 4-int range
  (let loop ((rs rows) (best #f) (bestspan #f))
    (if (null? rs) best
        (let* ((r (car rs)) (l0 (vr r ri)) (c0 (vr r (+ ri 1))) (l1 (vr r (+ ri 2))) (c1 (vr r (+ ri 3))))
          (if (and (LSP_posLE l0 c0 pl pc) (LSP_posLE pl pc l1 c1))
              (let ((sp (LSP-span l0 c0 l1 c1)))
                (if (or (not bestspan) (< sp bestspan)) (loop (cdr rs) r sp) (loop (cdr rs) best bestspan)))
              (loop (cdr rs) best bestspan))))))

(define (LSP_build_hover uri line char)
  (let ((r (LSP-idx-get uri)))
    (if (not r) jnull
        (let ((h (LSP-innermost-by (idx-hovers r) 0 line char)))
          (if (not h) jnull
              (jobj (list (cons "contents" (jobj (list (cons "kind" (jstr "markdown"))
                                                       (cons "value" (jstr (string-append "```ats\n" (vr h 4) "\n```"))))))
                          (cons "range" (jrange (vr h 0) (vr h 1) (vr h 2) (vr h 3))))))))))
(define (LSP_build_definition uri line char)
  (let ((r (LSP-idx-get uri)))
    (if (not r) jnull
        (let ((d (LSP-innermost-by (idx-defs r) 0 line char)))
          (if (or (not d) (string=? (vr d 4) "")) jnull
              (jobj (list (cons "uri" (jstr (vr d 4))) (cons "range" (jrange (vr d 5) (vr d 6) (vr d 7) (vr d 8))))))))))
(define (LSP_build_type_definition uri line char)
  (let ((r (LSP-idx-get uri)))
    (if (not r) jnull
        (let ((d (LSP-innermost-by (idx-defs r) 0 line char)))
          (if (or (not d) (string=? (vr d 10) "")) jnull
              (jobj (list (cons "uri" (jstr (vr d 10))) (cons "range" (jrange (vr d 11) (vr d 12) (vr d 13) (vr d 14))))))))))
(define (LSP_build_semantic_tokens uri)
  (let ((r (LSP-idx-get uri)))
    (jobj (list (cons "data" (jarr (map jnum (if r (idx-sem r) '()))))))))
(define (LSP_build_document_symbols uri)
  (let ((r (LSP-idx-get uri)))
    (if (not r) jnull
        (jarr (map (lambda (s)
                     (jobj (list (cons "name" (jstr (vr s 4))) (cons "kind" (jnum (vr s 5)))
                                 (cons "detail" (jstr (vr s 7)))
                                 (cons "range" (jrange (vr s 0) (vr s 1) (vr s 2) (vr s 3)))
                                 (cons "selectionRange" (jrange (vr s 0) (vr s 1) (vr s 2) (vr s 3)))
                                 (cons "children" (jarr '())))))
                   (idx-syms r))))))
;; references / documentHighlight: the def-group the cursor resolves to.
(define (LSP_defkey uri l0 c0 l1 c1) (LSP-num-cat uri l0 c0 l1 c1))
(define (LSP_find_ref_target uri line char)
  (let ((r (LSP-idx-get uri)))
    (if (not r) #f
        (let ((d (LSP-innermost-by (idx-defs r) 0 line char)))
          (if d (vector (vr d 4) (vr d 5) (vr d 6) (vr d 7) (vr d 8))
              (let loop ((ds (idx-defs r)))
                (cond ((null? ds) #f)
                      ((and (string=? (vr (car ds) 4) uri)
                            (LSP_posLE (vr (car ds) 5) (vr (car ds) 6) line char)
                            (LSP_posLE line char (vr (car ds) 7) (vr (car ds) 8)))
                       (vector (vr (car ds) 4) (vr (car ds) 5) (vr (car ds) 6) (vr (car ds) 7) (vr (car ds) 8)))
                      (else (loop (cdr ds))))))))))
(define (LSP_group_use_ranges uri target)
  (let ((r (LSP-idx-get uri)))
    (if (not r) '()
        (let ((key (LSP_defkey (vr target 0) (vr target 1) (vr target 2) (vr target 3) (vr target 4)))
              (seen (make-hashtable string-hash string=?)) (out '()))
          (for-each (lambda (d)
                      (when (string=? (LSP_defkey (vr d 4) (vr d 5) (vr d 6) (vr d 7) (vr d 8)) key)
                        (let ((k (LSP-num-cat (vr d 0) (vr d 1) (vr d 2) (vr d 3))))
                          (unless (hashtable-contains? seen k) (hashtable-set! seen k #t)
                                  (set! out (cons (jrange (vr d 0) (vr d 1) (vr d 2) (vr d 3)) out))))))
                    (idx-defs r))
          (reverse out)))))
(define (LSP_build_references uri line char includeDecl)
  (let ((t (LSP_find_ref_target uri line char)))
    (if (not t) jnull
        (let ((locs (map (lambda (rng) (jobj (list (cons "uri" (jstr uri)) (cons "range" rng)))) (LSP_group_use_ranges uri t))))
          (when (and includeDecl (not (string=? (vr t 0) "")))
            (set! locs (append locs (list (jobj (list (cons "uri" (jstr (vr t 0))) (cons "range" (jrange (vr t 1) (vr t 2) (vr t 3) (vr t 4)))))))))
          (jarr locs)))))
(define (LSP_build_highlights uri line char)
  (let ((t (LSP_find_ref_target uri line char)))
    (if (not t) jnull
        (let ((hl (map (lambda (rng) (jobj (list (cons "range" rng) (cons "kind" (jnum 2))))) (LSP_group_use_ranges uri t))))
          (when (string=? (vr t 0) uri)
            (set! hl (append hl (list (jobj (list (cons "range" (jrange (vr t 1) (vr t 2) (vr t 3) (vr t 4))) (cons "kind" (jnum 3))))))))
          (jarr hl)))))
(define (LSP_build_inlays uri rng)               ; rng = #f or (vector l0 c0 l1 c1)
  (let ((r (LSP-idx-get uri)))
    (if (not r) (jarr '())
        (jarr (let loop ((ins (idx-inlays r)) (acc '()))
                (cond ((null? ins) (reverse acc))
                      (else (let ((h (car ins)))
                              (if (and rng (not (and (LSP_posLE (vr rng 0) (vr rng 1) (vr h 0) (vr h 1)) (LSP_posLE (vr h 0) (vr h 1) (vr rng 2) (vr rng 3)))))
                                  (loop (cdr ins) acc)
                                  (loop (cdr ins) (cons (jobj (list (cons "position" (jobj (list (cons "line" (jnum (vr h 0))) (cons "character" (jnum (vr h 1))))))
                                                                    (cons "label" (jstr (vr h 2))) (cons "kind" (jnum (vr h 3)))
                                                                    (cons "paddingLeft" (jbool #f)) (cons "paddingRight" (jbool #f)))) acc)))))))))))
(define (LSP_current_lsp_diagnostics)
  (jarr (map (lambda (d) (jobj (list (cons "range" (jrange (vr d 0) (vr d 1) (vr d 2) (vr d 3)))
                                     (cons "severity" (jnum 1)) (cons "code" (jstr (vr d 4)))
                                     (cons "message" (jstr (vr d 5))) (cons "source" (jstr "ats3")))))
             (LSP_dedup_diags (reverse LSP_cur_diags)))))

;; ====================================================================== ;;
;; prelude/global symbol index (filled by the ATS pass) + keywords         ;;
;; ====================================================================== ;;
(define LSP_prelude_symbols '())   ; list of #(name kind typ)
(define LSP_prelude_seen (make-hashtable string-hash string=?))
(define (LSP_prelude_sym_reset) (set! LSP_prelude_symbols '()) (set! LSP_prelude_seen (make-hashtable string-hash string=?)) _xunit)
(define (LSP_prelude_sym_push name kind typ)
  (let ((nm (LSP->str name)))
    (if (or (string=? nm "") (hashtable-contains? LSP_prelude_seen nm)) _xunit
        (begin (hashtable-set! LSP_prelude_seen nm #t) (set! LSP_prelude_symbols (cons (vector nm (LSP->int kind) (LSP->str typ)) LSP_prelude_symbols)) _xunit))))
(define (LSP_prelude_sym_done)
  (LSP-stderr (string-append "[xats-lsp-resident] prelude-index: " (number->string (length LSP_prelude_symbols)) " name(s) [env]\n")) _xunit)
(define LSP_KEYWORDS
  '("val" "valpar" "val-" "var" "fun" "fn" "fnx" "prval" "prfun" "prfn" "praxi" "castfn" "let" "in" "end"
    "local" "where" "begin" "case" "case+" "case-" "of" "if" "then" "else" "sif" "scase" "while" "for"
    "lam" "llam" "fix" "when" "and" "rec" "datatype" "datavtype" "dataprop" "typedef" "abstype" "abstbox"
    "stacst" "sortdef" "sexpdef" "exception" "implement" "extern" "staload" "include" "dynload" "addr" "view" "true" "false"))
(define (LSP_sk_to_cik k)
  (case (LSP->int k)
    ((12) 3) ((14) 21) ((13) 6) ((10) 13) ((11) 8) ((5) 7) ((26) 25) ((22) 20) ((9) 4) (else 6)))

;; ====================================================================== ;;
;; staload-aware completion index (the staloaded API a file pulls in)       ;;
;; ====================================================================== ;;
;; The ATS harvest descends each file's staload closure ONCE per session
;; (deduped by staloaded-file STAMP via LSP_staload_seen/mark) and pushes each
;; staloaded declaration's (name,kind,type) here.  Kill-switch:
;; ATS3_LSP_STALOAD_COMPLETE=0 makes seen return #t for everything -> no descent.
(define LSP_staload_enabled (not (equal? (getenv "ATS3_LSP_STALOAD_COMPLETE") "0")))
(define LSP_complete_cap (let ((v (getenv "ATS3_LSP_COMPLETE_CAP"))) (if v (or (string->number v) 200) 200)))
(define LSP_staload_symbols '())                      ; list of #(name kind typ)
(define LSP_staload_seen_names (make-hashtable string-hash string=?))
(define LSP_staload_seen_files (make-hashtable equal-hash equal?))   ; stamp -> #t
(define (LSP_staload_seen stamp) (or (not LSP_staload_enabled) (hashtable-contains? LSP_staload_seen_files stamp)))
(define (LSP_staload_mark stamp) (hashtable-set! LSP_staload_seen_files stamp #t) _xunit)
(define (LSP_staload_sym_push name kind typ)
  (let ((nm (LSP->str name)))
    (if (or (string=? nm "") (hashtable-contains? LSP_staload_seen_names nm)) _xunit
        (begin (hashtable-set! LSP_staload_seen_names nm #t)
               (set! LSP_staload_symbols (cons (vector nm (LSP->int kind) (LSP->str typ)) LSP_staload_symbols)) _xunit))))
(define (LSP-staload-reset)
  (set! LSP_staload_symbols '())
  (set! LSP_staload_seen_names (make-hashtable string-hash string=?))
  (set! LSP_staload_seen_files (make-hashtable equal-hash equal?)))

;; ====================================================================== ;;
;; R2c project staload index (path-keyed forward/reverse graphs)            ;;
;; ====================================================================== ;;
(define LSP_proj_fwd (make-hashtable equal-hash equal?))    ; path -> hashtable(path->#t)
(define LSP_proj_rev (make-hashtable equal-hash equal?))
(define LSP_proj_indexed (make-hashtable equal-hash equal?))
(define LSP_proj_symbols (make-hashtable equal-hash equal?))  ; normpath -> (cons uri symbols-list)
(define LSP_PROJ_SCAN_CAP (let ((v (getenv "ATS3_PROJ_SCAN_CAP"))) (if v (or (string->number v) 4000) 4000)))
(define (LSP-src-file? name)
  (let ((n (string-length name)))
    (or (and (>= n 5) (string=? (substring name (- n 5) n) ".sats"))
        (and (>= n 5) (string=? (substring name (- n 5) n) ".hats"))
        (and (>= n 5) (string=? (substring name (- n 5) n) ".dats")))))
;; parse #staload/#include/#dynload "PATH" directives -> normalized abs paths.
(define (LSP_parse_staloads filePath text)
  (let ((dir (LSP-dirname filePath)) (out '()) (n (string-length text)))
    (define (kw-at? i) (or (LSP-substr-at? text i "#staload") (LSP-substr-at? text i "#include") (LSP-substr-at? text i "#dynload")))
    (let loop ((i 0))
      (cond ((>= i n) (reverse out))
            ((and (char=? (string-ref text i) #\#) (kw-at? i))
             ;; find the first quote on this directive (before newline)
             (let scan ((j (+ i 8)))
               (cond ((or (>= j n) (char=? (string-ref text j) #\newline)) (loop (+ i 1)))
                     ((char=? (string-ref text j) #\")
                      (let ((e (LSP-string-index text #\" (+ j 1))))
                        (if (< e 0) (loop (+ i 1))
                            (let* ((ref (substring text (+ j 1) e))
                                   (abs (if (and (> (string-length ref) 0) (char=? (string-ref ref 0) #\/)) ref (LSP_norm (string-append dir "/" ref))))
                                   (nn (LSP_norm abs)))
                              (unless (or (string=? nn "") (JS_path_is_prelude nn)) (set! out (cons nn out)))
                              (loop (+ e 1))))))
                     (else (scan (+ j 1))))))
            (else (loop (+ i 1)))))))
(define (LSP-substr-at? s i sub)
  (let ((ns (string-length s)) (nsub (string-length sub)))
    (and (<= (+ i nsub) ns) (string=? (substring s i (+ i nsub)) sub))))
(define (LSP-dirname path)
  (let ((i (let loop ((k (- (string-length path) 1))) (cond ((< k 0) -1) ((char=? (string-ref path k) #\/) k) (else (loop (- k 1)))))))
    (if (< i 0) "." (if (= i 0) "/" (substring path 0 i)))))
(define (LSP_proj_unlink from)
  (let ((olds (hashtable-ref LSP_proj_fwd from #f)))
    (when olds (vector-for-each (lambda (to) (let ((back (hashtable-ref LSP_proj_rev to #f)))
                                               (when back (hashtable-delete! back from) (when (= (hashtable-size back) 0) (hashtable-delete! LSP_proj_rev to)))))
                                (hashtable-keys olds)))
    (hashtable-delete! LSP_proj_fwd from)))
;; Stage 5: the forward/reverse staload graph + the #staload/#include/#dynload
;; scanner + the reverse closure now live in ATS (xats_lsp_proj).  The glue keeps
;; LSP_proj_indexed (bg-index worklist) + LSP_proj_symbols (completion symbol
;; cache).  These vars hold the ATS closures, set in vscode_initialize.
(define LSP-ats-proj-index #f)        ; (path text) -> normpath | ""
(define LSP-ats-proj-remove #f)       ; (path) -> void
(define LSP-ats-proj-revclosure #f)   ; (path) -> "p1\np2..." (dependents)
(define LSP-ats-proj-fwdcount #f)     ; () -> int
(define LSP-ats-proj-revcount #f)     ; () -> int
(define (LSP_proj_index_file filePath text0)
  (let ((text (or text0 (guard (e (#t #f)) (LSP-read-file (LSP_norm filePath))))))
    (if (not text) ""
        (let ((n (LSP-ats-proj-index filePath text)))
          (unless (string=? n "") (hashtable-set! LSP_proj_indexed n #t))
          n))))
(define (LSP_proj_remove_file filePath)
  (let ((n (LSP_norm filePath)))
    (unless (string=? n "") (LSP-ats-proj-remove filePath) (hashtable-delete! LSP_proj_indexed n))))
(define (LSP_proj_rev_closure path)
  (let ((s (LSP-ats-proj-revclosure path)) (out (make-hashtable equal-hash equal?)))
    (unless (string=? s "")
      (for-each (lambda (p) (unless (string=? p "") (hashtable-set! out p #t))) (LSP-string-split s #\newline)))
    out))
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
(define (LSP_workspace_roots params)
  (let ((roots '()) (seen (make-hashtable equal-hash equal?)))
    (define (add-uri u) (when (string? u) (let ((p (LSP_norm (vscode_url_to_path u)))) (when (and (not (string=? p "")) (not (hashtable-contains? seen p))) (hashtable-set! seen p #t) (set! roots (cons p roots))))))
    (let ((wf (jget params "workspaceFolders")))
      (when (vector? wf) (vector-for-each (lambda (x) (when (hashtable? x) (add-uri (jget x "uri")))) wf)))
    (when (null? roots)
      (let ((ru (jget params "rootUri")) (rp (jget params "rootPath")))
        (cond ((string? ru) (add-uri ru))
              ((string? rp) (let ((p (LSP_norm rp))) (when (and (not (string=? p "")) (not (hashtable-contains? seen p))) (set! roots (cons p roots))))))))
    (reverse roots)))
;; workspace/symbol fuzzy (case-insensitive subsequence)
(define (LSP-downcase s) (list->string (map char-downcase (string->list s))))
(define (LSP_ws_fuzzy q name)
  (if (string=? q "") #t
      (let ((ql (LSP-downcase q)) (nl (LSP-downcase name)))
        (let loop ((i 0) (j 0))
          (cond ((>= i (string-length ql)) #t) ((>= j (string-length nl)) #f)
                ((char=? (string-ref nl j) (string-ref ql i)) (loop (+ i 1) (+ j 1)))
                (else (loop i (+ j 1))))))))
(define (LSP_build_workspace_symbols query)
  (let ((out '()) (cap 1000) (seenUri (make-hashtable equal-hash equal?)) (cnt 0))
    (call/cc (lambda (ret)
      (let-values (((uris recs) (hashtable-entries LSP_index)))
        (vector-for-each (lambda (uri rec)
                           (hashtable-set! seenUri uri #t)
                           (for-each (lambda (s) (when (LSP_ws_fuzzy query (vr s 4))
                                                   (set! out (cons (jobj (list (cons "name" (jstr (vr s 4))) (cons "kind" (jnum (vr s 5)))
                                                                               (cons "location" (jobj (list (cons "uri" (jstr uri)) (cons "range" (jrange (vr s 0) (vr s 1) (vr s 2) (vr s 3))))))
                                                                               (cons "containerName" (jstr (vr s 6))))) out))
                                                   (set! cnt (+ cnt 1)) (when (>= cnt cap) (ret #t))))
                                     (idx-syms rec)))
                         uris recs))
      (let-values (((ps prs) (hashtable-entries LSP_proj_symbols)))
        (vector-for-each (lambda (np rec)
                           (unless (or (not rec) (hashtable-contains? seenUri (car rec)))
                             (for-each (lambda (s) (when (LSP_ws_fuzzy query (vr s 4))
                                                     (set! out (cons (jobj (list (cons "name" (jstr (vr s 4))) (cons "kind" (jnum (vr s 5)))
                                                                                 (cons "location" (jobj (list (cons "uri" (jstr (car rec))) (cons "range" (jrange (vr s 0) (vr s 1) (vr s 2) (vr s 3))))))
                                                                                 (cons "containerName" (jstr (vr s 6))))) out))
                                                     (set! cnt (+ cnt 1)) (when (>= cnt cap) (ret #t))))
                                       (cdr rec))))
                         ps prs))))
    (jarr (reverse out))))

;; test-only introspection: per-uri index sizes + max harvested line (Bug-1
;; include-leak check).  Mirrors the JS xats/indexStats.
(define (LSP_build_index_stats uri)
  (let ((r (LSP-idx-get uri)))
    (if (not r) (jobj (list (cons "found" (jbool #f))))
        (let* ((hs (idx-hovers r)) (ds (idx-defs r)) (tk (idx-sem r))
               (maxH (fold-left (lambda (a h) (max a (vr h 2))) -1 hs))
               (maxD (fold-left (lambda (a d) (max a (vr d 2))) -1 ds))
               (maxT (let loop ((xs tk) (line 0) (mx -1))
                       (if (< (length xs) 5) mx (let ((nl (+ line (car xs)))) (loop (list-tail xs 5) nl (max mx nl)))))))
          (jobj (list (cons "found" (jbool #t)) (cons "hovers" (jnum (length hs))) (cons "defs" (jnum (length ds)))
                      (cons "tokens" (jnum (quotient (length tk) 5)))
                      (cons "maxHoverLine" (jnum maxH)) (cons "maxDefUseLine" (jnum maxD)) (cons "maxTokenLine" (jnum maxT))))))))

;; ====================================================================== ;;
;; vscode_* helpers (mostly vestigial in the resident; must link)          ;;
;; ====================================================================== ;;
(define (vscode_severity_error$make) 1)
(define (vscode_position_make line offs) (jobj (list (cons "line" (jnum (LSP->int line))) (cons "character" (jnum (LSP->int offs))))))
(define (vscode_range_make pbeg pend) (jobj (list (cons "start" pbeg) (cons "end" pend))))
(define (vscode_diagnostic_make severity range message source)
  (jobj (list (cons "severity" (jnum (LSP->int severity))) (cons "range" range) (cons "message" (jstr (LSP->str message))) (cons "source" (jstr (LSP->str source))))))
(define LSP-side-diags '())                  ; collector if the ATS path is ever used
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
;; TextDocuments store (open buffers; incremental sync; offset<->position)  ;;
;; ====================================================================== ;;
;; doc = (vector uri text version line-starts).  Positions treat each Scheme char
;; as 1 UTF-16 unit (exact for BMP; astral chars only affect sync math).
;; line-starts is a lazily-built vector of per-line char offsets so (line,char)<->
;; offset is O(1)/O(log) instead of an O(file) walk on every keystroke.
;; Stage 6a: the document store lives in ATS (xats_lsp_doc).  These top-level
;; wrappers forward to the closures bound in vscode_initialize (#f until then; the
;; wrappers run only at request/check time, after binding).  LSP-doc-get returns
;; the URI itself as an opaque "doc handle" (or #f) so the existing call sites
;; `(let ((doc (LSP-doc-get uri))) (when doc (... (LSP-doc-text doc))))` are
;; unchanged — `doc` IS the uri, and LSP-doc-text takes the uri.
(define LSP-ats-doc-set #f)     ; (uri text version) -> void
(define LSP-ats-doc-has #f)     ; (uri) -> bool
(define LSP-ats-doc-text #f)    ; (uri) -> text
(define LSP-ats-doc-del #f)     ; (uri) -> void
(define LSP-ats-doc-uris #f)    ; () -> "uri\n...\n"
(define LSP-ats-doc-apply #f)   ; (text sl sc el ec newtext) -> newtext
(define LSP-ats-doc-ctx #f)     ; (uri line char) -> "word\nisMember\ndotCol\nwcol"
(define (LSP-doc-get uri) (if (LSP-ats-doc-has uri) uri #f))
(define (LSP-doc-text uri) (LSP-ats-doc-text uri))   ; `uri` is the doc handle now
(define (LSP-doc-set uri text version) (LSP-ats-doc-set uri text version))
(define (LSP-doc-del uri) (LSP-ats-doc-del uri))
(define (LSP-doc-uris)
  (filter (lambda (s) (not (string=? s ""))) (LSP-string-split (LSP-ats-doc-uris) #\newline)))
;; apply one incremental contentChange (range+text, or whole-doc text) to `text`.
(define (LSP-apply-change text change)
  (let ((rng (jget change "range")))
    (if (not (hashtable? rng)) (jstr-or (jget change "text") text)
        (LSP-ats-doc-apply text
          (jnum->int (jget* rng "start" "line")) (jnum->int (jget* rng "start" "character"))
          (jnum->int (jget* rng "end" "line")) (jnum->int (jget* rng "end" "character"))
          (jstr-or (jget change "text") "")))))

;; ---- completion builder (needs the doc store) ----
;; Stage 6a: completion is built in ATS (idx_completion), and the DOC-STORE-derived
;; partial word + member-mode detection is now in ATS too (xats_lsp_doc's
;; doc_complete_ctx).  This shim splits its "word\nisMember\ndotCol\nwcol" reply and
;; hands the pieces to the ATS completion builder.
(define (LSP_build_completion uri line char idxComplete)
  (if (not (LSP-ats-doc-has uri))
      (jobj (list (cons "isIncomplete" (jbool #f)) (cons "items" (jarr '()))))
      (let* ((parts (LSP-string-split (LSP-ats-doc-ctx uri line char) #\newline))
             (word (car parts)) (member? (string=? (cadr parts) "1"))
             (dotCol (or (string->number (caddr parts)) 0)) (wcol (or (string->number (cadddr parts)) 0)))
        (jraw (idxComplete uri line char word (if member? 1 0) line dotCol wcol)))))
;; allocation-free case-insensitive prefix test against a PRE-LOWERCASED query
;; (downcases only the candidate's first wlen chars, on the fly, exiting early on
;; the first mismatch — no per-candidate string allocation).
(define (LSP-ci-prefix-lc? name wlow wlen)
  (or (= wlen 0)
      (and (>= (string-length name) wlen)
           (let loop ((i 0))
             (cond ((>= i wlen) #t)
                   ((char=? (char-downcase (string-ref name i)) (string-ref wlow i)) (loop (+ i 1)))
                   (else #f))))))
(define (LSP-completion-member uri word rng dotpos)
  (let* ((r (LSP-idx-get uri)) (items '()) (seen (make-hashtable string-hash string=?))
         (wlow (LSP-downcase word)) (wlen (string-length wlow)))
    (when r
      (for-each (lambda (m)
                  (when (and (= (vr m 2) (car dotpos)) (= (vr m 3) (cdr dotpos)) (not (hashtable-contains? seen (vr m 4))) (LSP-ci-prefix-lc? (vr m 4) wlow wlen))
                    (hashtable-set! seen (vr m 4) #t)
                    (set! items (cons (jobj (list (cons "label" (jstr (vr m 4))) (cons "kind" (jnum 5))
                                                  (cons "detail" (jstr (if (string=? (vr m 5) "") "field" (string-append ": " (vr m 5)))))
                                                  (cons "sortText" (jstr (string-append "0" (vr m 4))))
                                                  (cons "textEdit" (jobj (list (cons "range" rng) (cons "newText" (jstr (vr m 4)))))))) items))))
                (idx-members r)))
    (jobj (list (cons "isIncomplete" (jbool #t)) (cons "items" (jarr (reverse items)))))))
(define (LSP-completion-general uri word rng line char)
  (let* ((items '()) (seen (make-hashtable string-hash string=?)) (cap LSP_complete_cap) (cnt 0)
         (wlow (LSP-downcase word)) (wlen (string-length wlow)))
    (define (cand-detail s src) (if (not (string=? (vr s 2) "")) (vr s 2) (if (= (vr s 1) 12) "overloaded" src)))
    ;; cnt-cap checked FIRST so candidates past the cap short-circuit without the
    ;; prefix test; then dedup; then the (now cheap) prefix test.
    (define (add name symKind src detail)
      (when (and (< cnt cap) (not (string=? name "")) (not (hashtable-contains? seen name)) (LSP-ci-prefix-lc? name wlow wlen))
        (hashtable-set! seen name #t) (set! cnt (+ cnt 1))
        (set! items (cons (jobj (list (cons "label" (jstr name)) (cons "kind" (jnum (if (string=? src "5") 14 (LSP_sk_to_cik symKind))))
                                      (cons "detail" (jstr detail)) (cons "sortText" (jstr (string-append src name)))
                                      (cons "textEdit" (jobj (list (cons "range" rng) (cons "newText" (jstr name))))))) items))))
    ;; iterate a list of symbols (#(name kind ... typ)), stopping at the cap.
    (define (add-syms lst src detail-src)
      (let loop ((xs lst))
        (when (and (pair? xs) (< cnt cap))
          (let ((s (car xs))) (add (vr s 0) (vr s 1) src (cand-detail s detail-src)))
          (loop (cdr xs)))))
    ;; iterate a document-symbol list (#(l0 c0 l1 c1 name kind container typ)) at the cap.
    (define (add-docsyms lst src detail-src)
      (let loop ((xs lst))
        (when (and (pair? xs) (< cnt cap))
          (let ((s (car xs))) (add (vr s 4) (vr s 5) src (cand-detail (vector (vr s 4) (vr s 5) (vr s 7)) detail-src)))
          (loop (cdr xs)))))
    (let ((r (LSP-idx-get uri)))
      (when r
        ;; 0: in-scope locals (position-filtered)
        (for-each (lambda (s) (when (and (< cnt cap) (LSP_posLE (vr s 0) (vr s 1) line char) (LSP_posLE line char (vr s 2) (vr s 3)))
                                (add (vr s 4) 13 "0" (if (string=? (vr s 5) "") "local" (vr s 5))))) (idx-scopes r))
        ;; 1: current-file symbols
        (add-docsyms (idx-syms r) "1" "this file")))
    ;; 2: project symbols (other open buffers + bg-indexed)
    (when (< cnt cap)
      (let-values (((uris recs) (hashtable-entries LSP_index)))
        (vector-for-each (lambda (u2 rec) (when (and (< cnt cap) (not (string=? u2 uri))) (add-docsyms (idx-syms rec) "2" "project"))) uris recs)))
    (when (< cnt cap)
      (let-values (((ps prs) (hashtable-entries LSP_proj_symbols)))
        (vector-for-each (lambda (np rec) (when (and (< cnt cap) rec (not (string=? (car rec) uri)) (not (hashtable-contains? LSP_index (car rec)))) (add-docsyms (cdr rec) "2" "project"))) ps prs)))
    ;; 3: prelude/global  4: staloaded API  5: keywords  (all early-exit at the cap)
    (add-syms LSP_prelude_symbols "3" "prelude")
    (add-syms LSP_staload_symbols "4" "staload")
    (let loop ((xs LSP_KEYWORDS)) (when (and (pair? xs) (< cnt cap)) (add (car xs) 0 "5" "keyword") (loop (cdr xs))))
    (jobj (list (cons "isIncomplete" (jbool #t)) (cons "items" (jarr (reverse items)))))))

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
(define (LSP-write-message obj)
  (let* ((body (string->utf8 (json-string obj)))
         (hdr (string->utf8 (string-append "Content-Length: " (number->string (bytevector-length body)) "\r\n\r\n"))))
    (put-bytevector LSP-out hdr) (put-bytevector LSP-out body) (flush-output-port LSP-out)))
(define (LSP-id->jval id) (cond ((number? id) (jnum id)) ((string? id) (jstr id)) (else jnull)))
(define (LSP-respond id result) (LSP-write-message (jobj (list (cons "jsonrpc" (jstr "2.0")) (cons "id" (LSP-id->jval id)) (cons "result" result)))))
(define (LSP-send-notification method params) (LSP-write-message (jobj (list (cons "jsonrpc" (jstr "2.0")) (cons "method" (jstr method)) (cons "params" params)))))
(define LSP-srv-reqid 100000)
(define (LSP-send-request method params)
  (set! LSP-srv-reqid (+ LSP-srv-reqid 1))
  (LSP-write-message (jobj (list (cons "jsonrpc" (jstr "2.0")) (cons "id" (jnum LSP-srv-reqid)) (cons "method" (jstr method)) (cons "params" params)))))

;; ====================================================================== ;;
;; vscode_initialize: the connection loop + all handlers                   ;;
;; ====================================================================== ;;
(define LSP_hasSemanticRefresh #f)
(define LSP_pending_roots '())
(define LSP_BG_CAP (let ((v (getenv "ATS3_BG_INDEX_CAP"))) (if v (or (string->number v) 400) 400)))
;; debounce + reader-thread queue (replaces the JS async event loop / setTimeout)
(define LSP-qmtx (make-mutex))
(define LSP-qcond (make-condition))
(define LSP-queue '())
(define LSP-qeof #f)
(define LSP-DEBOUNCE-MS (let ((v (getenv "ATS3_LSP_DEBOUNCE_MS"))) (if v (or (string->number v) 150) 150)))

;; read a workspace `.xats-lsp` file: one compiler flag per non-blank, non-`#`
;; line (bare names get a `--` prefix), set each via the ATS addFlag callback so
;; `#if defq(...)` blocks resolve the way the project's real build does.
(define (LSP-load-project-flags root addFlag)
  (let ((cfg (string-append root "/.xats-lsp")))
    (when (file-exists? cfg)
      (let ((text (guard (e (#t "")) (LSP-read-file cfg))))
        (for-each
         (lambda (line)
           (let ((s (LSP-trim line)))
             (unless (or (string=? s "") (char=? (string-ref s 0) #\#))
               (let ((flag (if (LSP-starts-with? s "--") s (string-append "--" s))))
                 (guard (e (#t #f)) (addFlag flag))
                 (LSP-stderr (string-append "[xats-lsp-resident] .xats-lsp flag: " flag "\n"))))))
         (LSP-string-split text #\newline))))))

(define (vscode_initialize validator liveValidator pruner reloadPreludeFn evictStampFn addFlag
                           LSP-idx-reset LSP-idx-commit LSP-idx-evict LSP-idx-clear
                           LSP-idx-diags LSP-idx-ndiags LSP-idx-count LSP-idx-query
                           projIndex projRemove projRevClosure projFwdCount projRevCount
                           LSP-idx-workspace LSP-idx-completion LSP-idx-proj-store LSP-idx-proj-delete
                           docSet docHas docText docDel docUris docApply docCtx
                           convSetCur)

  ;; The ATS xats_lsp_index module API (passed as eight closures via initialize):
  ;; the diag/hover/def/token/inlay accumulators + their dedups + the per-uri
  ;; snapshot + the request builders all live in ATS now; the glue drives them by
  ;; uri string.  (symbols/scopes/members + completion/workspace stay glue-side,
  ;; reading LSP_index's 3 trailing fields.)
  ;;   LSP-idx-reset  : () -> clear accumulators
  ;;   LSP-idx-commit : (uri) -> dedup + store snapshot
  ;;   LSP-idx-evict  : (uri) -> drop a uri          LSP-idx-clear : () -> drop all
  ;;   LSP-idx-diags  : () -> published Diagnostic[] (JSON string)
  ;;   LSP-idx-ndiags : () -> its length             LSP-idx-count : (uri,which)->int
  ;;   LSP-idx-query  : (uri, kind, a,b,c,d) -> serialized JSON value

  ;; shared driver: per-check context + accumulators -> snapshot index + publish.
  (define (runValidation uri sourceText mode runCheck)
    (let ((t0 (real-time)))
      (LSP-idx-reset)
      (set! LSP_cur_symbols '()) (set! LSP_cur_scopes '()) (set! LSP_cur_members '())
      (set! LSP_cur_uri uri) (set! LSP_cur_path (vscode_url_to_path uri)) (set! LSP_cur_path_norm (LSP_norm LSP_cur_path))
      (convSetCur LSP_cur_uri LSP_cur_path sourceText)   ; ATS conv layer: friendly/def_in_current/path2uri/cur_b2u state
      (set! LSP_cur_u16 (LSP_u16_make sourceText)) (set! LSP_other_u16 (make-hashtable equal-hash equal?))
      (guard (e (#t #f)) (LSP_proj_index_file LSP_cur_path sourceText))
      (let ((validatorError (guard (e (#t e)) (runCheck) #f)))
        ;; diag/hover/def/token/inlay snapshot is ATS-owned (idx_commit); the glue
        ;; LSP_index keeps only the 3 trailing fields it still reads (symbols/scopes/
        ;; members for documentSymbol/workspace/completion).  Slots 0-2/4 are unused.
        ;; the per-uri snapshot (incl. symbols/scopes/members) is ATS-owned now;
        ;; LSP_index is just the glue's set of indexed (open/checked) uris.
        (LSP-idx-commit uri)
        (hashtable-set! LSP_index uri #t)
        (LSP-idx-proj-delete LSP_cur_path_norm)
        (let ((lspDiags (if validatorError
                            (jarr (list (vscode_diagnostic_make 2 (vscode_range_make (vscode_position_make 0 0) (vscode_position_make 0 1))
                                          "ats3: could not analyze this file (the compiler aborted). This usually means the file staloads the ATS3 compiler itself; ordinary ATS3 files are unaffected." "ats3")))
                            (jraw (LSP-idx-diags)))))
          (LSP-send-notification "textDocument/publishDiagnostics" (jobj (list (cons "uri" (jstr uri)) (cons "diagnostics" lspDiags))))
          (when LSP_hasSemanticRefresh (guard (e (#t #f)) (LSP-send-request "workspace/semanticTokens/refresh" jnull)))
          (LSP-stderr (string-append "[xats-lsp-metric] check uri=" uri " mode=" mode " ms=" (number->string (- (real-time) t0))
                                     " diags=" (number->string (if validatorError 1 (LSP-idx-ndiags)))
                                     " hovers=" (number->string (LSP-idx-count uri 0)) " defs=" (number->string (LSP-idx-count uri 1))
                                     " tokens=" (number->string (LSP-idx-count uri 2)) " stats=" (number->string (LSP_stat_count_reset)) " staloadsyms=" (number->string (length LSP_staload_symbols)) " staloadfiles=" (number->string (hashtable-size LSP_staload_seen_files)) "\n"))
          (set! LSP_cur_uri #f) (set! LSP_cur_path #f) (set! LSP_cur_path_norm #f) (set! LSP_cur_u16 #f) (convSetCur "" "" "")))))

  (define (textValidator uri text) (runValidation uri text "disk" (lambda () (validator LSP_dependencies #f uri))))
  (define (liveValidate uri text) (runValidation uri text "live" (lambda () (liveValidator LSP_dependencies #f uri text))))

  ;; background project indexer (symbols-only; no publish).  Bounded + synchronous.
  (define (LSP-bg-index)
    (when (> LSP_BG_CAP 0)
      (let ((done 0))
        (call/cc (lambda (stop)
          (vector-for-each
           (lambda (n)
             (when (>= done LSP_BG_CAP) (stop #t))
             (let ((uri (LSP_file_uri n)))
               (unless (or (hashtable-contains? LSP_index uri) (JS_path_is_prelude n))
                 (let ((text (guard (e (#t #f)) (LSP-read-file n))))
                   (when text
                     (LSP-idx-reset)   ; symbols-only pass: accumulate -> proj cache (no commit)
                     (set! LSP_cur_uri uri) (set! LSP_cur_path n) (set! LSP_cur_path_norm n)
                     (convSetCur uri n text)
                     (set! LSP_cur_u16 (LSP_u16_make text)) (set! LSP_other_u16 (make-hashtable equal-hash equal?))
                     (guard (e (#t #f)) (validator LSP_dependencies #f uri))
                     (LSP-idx-proj-store n uri)
                     (set! done (+ done 1))
                     (set! LSP_cur_uri #f) (set! LSP_cur_path #f) (set! LSP_cur_u16 #f) (convSetCur "" "" ""))))))
           (hashtable-keys LSP_proj_indexed))))
        (LSP-stderr (string-append "[xats-lsp-resident] bg-index: " (number->string done) " file(s) indexed\n")))))

  ;; prelude reload (a $XATSHOME file was saved).
  (define (reloadPreludeAndRevalidate savedUri)
    (LSP-stderr (string-append "[xats-lsp-resident] reload_prelude: " savedUri "\n"))
    (guard (e (#t (LSP-stderr "reload_prelude threw\n")))
      (reloadPreludeFn)
      (LSP-idx-clear)
      (set! LSP_index (make-hashtable equal-hash equal?))
      (set! LSP_dependencies (LSP_empty_graph))   ; ATS-owned depgraph rep
      (set! LSP_fwd (LSP_empty_graph))
      (set! LSP_signatures (make-hashtable equal-hash equal?))
      (set! LSP_path2stamp (make-hashtable equal-hash equal?))
      ;; staloaded-API index is stamp-keyed -> stale after a reload (new stamps).
      (LSP-staload-reset)
      (for-each (lambda (uri) (let ((doc (LSP-doc-get uri))) (when doc (textValidator uri (LSP-doc-text doc))))) (LSP-doc-uris))))

  ;; watched files (Created=1 Changed=2 Deleted=3): keep project index current,
  ;; evict affected files by stamp, re-validate affected open docs.
  (define (handleWatchedFileChange uri changeType)
    (let ((npath (LSP_norm (vscode_url_to_path uri))))
      (unless (or (string=? npath "") (JS_path_is_prelude npath))
        (if (= changeType 3) (LSP_proj_remove_file npath) (LSP_proj_index_file npath #f))
        (let ((affected (LSP_proj_rev_closure npath)) (evicted 0))
          (hashtable-set! affected npath #t)
          (vector-for-each (lambda (p) (let ((st (hashtable-ref LSP_path2stamp p #f))) (when st (guard (e (#t #f)) (evictStampFn st) (set! evicted (+ evicted 1)))))) (hashtable-keys affected))
          (let ((st (hashtable-ref LSP_path2stamp npath #f))) (when st (hashtable-delete! LSP_signatures st) (when (= changeType 3) (hashtable-delete! LSP_path2stamp npath))))
          ;; which OPEN docs are affected -> compute first so the metric line (incl.
          ;; revalidated count) is emitted to stderr BEFORE the re-validation
          ;; publishes their diagnostics (a smoke greps the line right after the publish).
          (let ((to-reval (filter (lambda (uri2) (let ((dp (LSP_norm (vscode_url_to_path uri2)))) (and (not (string=? dp "")) (hashtable-contains? affected dp))))
                                  (LSP-doc-uris))))
            (LSP-stderr (string-append "[xats-lsp-resident] watched "
                                       (cond ((= changeType 1) "create") ((= changeType 3) "delete") (else "change"))
                                       " " npath " -> affected=" (number->string (hashtable-size affected))
                                       " evicted=" (number->string evicted) " revalidated=" (number->string (length to-reval)) "\n"))
            (for-each (lambda (uri2) (let ((doc (LSP-doc-get uri2))) (when doc (textValidator uri2 (LSP-doc-text doc))))) to-reval))))))

  ;; ---- capabilities ----
  (define (capabilities)
    (let ((caps
           (jobj (list
                  (cons "textDocumentSync" (jobj (list (cons "openClose" (jbool #t)) (cons "change" (jnum 2)) (cons "save" (jobj (list (cons "includeText" (jbool #f))))))))
                  (cons "hoverProvider" (jbool #t))
                  (cons "definitionProvider" (jbool #t))
                  (cons "typeDefinitionProvider" (jbool #t))
                  (cons "documentSymbolProvider" (jbool #t))
                  (cons "referencesProvider" (jbool #t))
                  (cons "documentHighlightProvider" (jbool #t))
                  (cons "inlayHintProvider" (jbool #t))
                  (cons "workspaceSymbolProvider" (jbool #t))
                  (cons "completionProvider" (jobj (list (cons "triggerCharacters" (jarr (list (jstr ".")))) (cons "resolveProvider" (jbool #f)))))
                  (cons "semanticTokensProvider"
                        (jobj (list (cons "legend" (jobj (list (cons "tokenTypes" (jarr (map jstr LSP_TOKEN_TYPES)))
                                                               (cons "tokenModifiers" (jarr (map jstr LSP_TOKEN_MODS))))))
                                    (cons "full" (jbool #t))
                                    (cons "range" (jbool #f)))))))))
      (jobj (list (cons "capabilities" caps)
                  (cons "serverInfo" (jobj (list (cons "name" (jstr "xats-lsp-resident")) (cons "version" (jstr "0.1.0")))))))))

  ;; ---- request param helpers ----
  (define (p-uri m) (jstr-or (jget* m "params" "textDocument" "uri") ""))
  (define (p-line m) (jnum->int (jget* m "params" "position" "line")))
  (define (p-char m) (jnum->int (jget* m "params" "position" "character")))

  ;; ---- dispatch ----
  (define (LSP-handle-request id method m)
    (guard (e (#t (LSP-respond id jnull)))
      (cond
       ((string=? method "initialize")
        (let ((params (jget m "params")))
          (let ((wcap (jget* params "capabilities" "workspace")))
            (set! LSP_hasSemanticRefresh (and (hashtable? wcap) (hashtable? (jget wcap "semanticTokens")) (not (eq? (jget* wcap "semanticTokens" "refreshSupport") 'null)))))
          (set! LSP_pending_roots (LSP_workspace_roots params))
          ;; apply project `.xats-lsp` compiler flags BEFORE any file is checked.
          (for-each (lambda (root) (guard (e (#t #f)) (LSP-load-project-flags root addFlag))) LSP_pending_roots)
          (LSP-respond id (capabilities))))
       ((string=? method "shutdown") (LSP-respond id jnull))
       ((string=? method "textDocument/hover") (LSP-respond id (jraw (LSP-idx-query (p-uri m) 0 (p-line m) (p-char m) 0 0))))
       ((string=? method "textDocument/definition") (LSP-respond id (jraw (LSP-idx-query (p-uri m) 1 (p-line m) (p-char m) 0 0))))
       ((string=? method "textDocument/typeDefinition") (LSP-respond id (jraw (LSP-idx-query (p-uri m) 2 (p-line m) (p-char m) 0 0))))
       ((string=? method "textDocument/references")
        (LSP-respond id (jraw (LSP-idx-query (p-uri m) 3 (p-line m) (p-char m) (if (eq? (jget* m "params" "context" "includeDeclaration") #t) 1 0) 0))))
       ((string=? method "textDocument/documentHighlight") (LSP-respond id (jraw (LSP-idx-query (p-uri m) 4 (p-line m) (p-char m) 0 0))))
       ((string=? method "textDocument/documentSymbol") (LSP-respond id (jraw (LSP-idx-query (p-uri m) 9 0 0 0 0))))
       ((string=? method "textDocument/inlayHint")
        (let ((rng (jget* m "params" "range")))
          (if (hashtable? rng)
              (LSP-respond id (jraw (LSP-idx-query (p-uri m) 6 (jnum->int (jget* rng "start" "line")) (jnum->int (jget* rng "start" "character")) (jnum->int (jget* rng "end" "line")) (jnum->int (jget* rng "end" "character")))))
              (LSP-respond id (jraw (LSP-idx-query (p-uri m) 5 0 0 0 0))))))
       ((string=? method "workspace/symbol") (LSP-respond id (jraw (LSP-idx-workspace (jstr-or (jget* m "params" "query") "")))))
       ((string=? method "textDocument/completion") (LSP-respond id (LSP_build_completion (p-uri m) (p-line m) (p-char m) LSP-idx-completion)))
       ((string=? method "textDocument/semanticTokens/full") (LSP-respond id (jraw (LSP-idx-query (p-uri m) 7 0 0 0 0))))
       ((string=? method "xats/indexStats")
        (LSP-respond id (jraw (LSP-idx-query (jstr-or (jget* m "params" "uri") (jstr-or (jget* m "params" "textDocument" "uri") "")) 8 0 0 0 0))))
       (else (LSP-respond id jnull)))))

  (define (LSP-handle-notification method m)
    (guard (e (#t #f))
      (cond
       ((string=? method "initialized")
        (when (pair? LSP_pending_roots)
          (let ((roots LSP_pending_roots)) (set! LSP_pending_roots '())
            (guard (e (#t #f)) (LSP_proj_scan_workspace roots))
            (guard (e (#t #f)) (LSP-bg-index)))))
       ((string=? method "exit") (flush-output-port LSP-out) (exit 0))
       ((string=? method "textDocument/didOpen")
        (let ((uri (jstr-or (jget* m "params" "textDocument" "uri") "")) (text (jstr-or (jget* m "params" "textDocument" "text") "")) (ver (jnum->int (jget* m "params" "textDocument" "version"))))
          (LSP-doc-set uri text ver) (textValidator uri text)))
       ((string=? method "textDocument/didChange")
        (let* ((uri (jstr-or (jget* m "params" "textDocument" "uri") "")) (doc (LSP-doc-get uri)))
          (when doc
            (let ((text (LSP-doc-text doc)) (changes (jget* m "params" "contentChanges")))
              (when (vector? changes) (vector-for-each (lambda (ch) (set! text (LSP-apply-change text ch))) changes))
              (LSP-doc-set uri text (jnum->int (jget* m "params" "textDocument" "version")))
              (guard (e (#t #f)) (pruner LSP_dependencies uri))
              (unless (JS_path_is_prelude (vscode_url_to_path uri)) (liveValidate uri text))))))
       ((string=? method "textDocument/didSave")
        (let* ((uri (jstr-or (jget* m "params" "textDocument" "uri") "")) (fpath (vscode_url_to_path uri)))
          (if (JS_path_is_prelude fpath) (reloadPreludeAndRevalidate uri)
              (let ((doc (LSP-doc-get uri))) (when doc (textValidator uri (LSP-doc-text doc)))))))
       ((string=? method "textDocument/didClose")
        (let ((uri (jstr-or (jget* m "params" "textDocument" "uri") "")))
          (LSP-doc-del uri) (hashtable-delete! LSP_index uri) (LSP-idx-evict uri)
          (LSP-send-notification "textDocument/publishDiagnostics" (jobj (list (cons "uri" (jstr uri)) (cons "diagnostics" (jarr '())))))))
       ((string=? method "workspace/didChangeWatchedFiles")
        (let ((changes (jget* m "params" "changes")))
          (when (vector? changes) (vector-for-each (lambda (c) (handleWatchedFileChange (jstr-or (jget c "uri") "") (jnum->int (jget c "type")))) changes))))
       (else #f))))

  (define (LSP-dispatch m)
    (let ((id (jget m "id")) (method (jget m "method")))
      (cond
       ((not (string? method)) #f)                         ; a response to our request -> ignore
       ((not (eq? id 'null)) (LSP-handle-request id method m))
       (else (LSP-handle-notification method m)))))

  ;; didChange: apply edits + prune the cache IMMEDIATELY; the VALIDATE is debounced
  ;; (set as `pending`), so a quick following save cancels it — matching the JS
  ;; debounce.  Returns (cons uri newtext) or #f.
  (define (apply-didChange m)
    (let* ((uri (jstr-or (jget* m "params" "textDocument" "uri") "")) (doc (LSP-doc-get uri)))
      (if (not doc) #f
          (let ((text (LSP-doc-text doc)) (changes (jget* m "params" "contentChanges")))
            (when (vector? changes) (vector-for-each (lambda (ch) (set! text (LSP-apply-change text ch))) changes))
            (LSP-doc-set uri text (jnum->int (jget* m "params" "textDocument" "version")))
            (guard (e (#t #f)) (pruner LSP_dependencies uri))
            (cons uri text)))))
  (define (msg-method m) (and (hashtable? m) (jget m "method")))
  (define (msg-uri m) (jstr-or (jget* m "params" "textDocument" "uri") ""))

  ;; bind the ATS project-graph closures into the top-level wrappers (also reached
  ;; from scan_dir, a top-level fn outside this scope).  Placed here (after the
  ;; internal defines) so it is in expression context.
  (set! LSP-ats-proj-index projIndex) (set! LSP-ats-proj-remove projRemove)
  (set! LSP-ats-proj-revclosure projRevClosure)
  (set! LSP-ats-proj-fwdcount projFwdCount) (set! LSP-ats-proj-revcount projRevCount)
  ;; bind the ATS document-store closures (xats_lsp_doc) into the top-level wrappers.
  (set! LSP-ats-doc-set docSet) (set! LSP-ats-doc-has docHas) (set! LSP-ats-doc-text docText)
  (set! LSP-ats-doc-del docDel) (set! LSP-ats-doc-uris docUris)
  (set! LSP-ats-doc-apply docApply) (set! LSP-ats-doc-ctx docCtx)

  ;; reader thread: read framed messages -> parse -> enqueue + signal.  Only this
  ;; thread touches stdin + json-parse (pure); the main thread runs the compiler.
  (fork-thread (lambda ()
    (let rloop ()
      (let ((s (LSP-read-message LSP-in)))
        (with-mutex LSP-qmtx
          (if (eof-object? s) (set! LSP-qeof #t) (set! LSP-queue (append LSP-queue (list (json-parse s)))))
          (condition-signal LSP-qcond))
        (unless (eof-object? s) (rloop))))))

  (LSP-stderr "[xats-lsp-resident] listening on stdio (resident, in-process)\n")
  (let ((pending #f))                             ; (cons uri text) of a debounced live check
    (let loop ()
      (let ((item (with-mutex LSP-qmtx
                    (let w ()
                      (cond ((pair? LSP-queue) (let ((m (car LSP-queue))) (set! LSP-queue (cdr LSP-queue)) m))
                            (LSP-qeof 'eof)
                            (pending (if (condition-wait LSP-qcond LSP-qmtx (make-time 'time-duration (* LSP-DEBOUNCE-MS 1000000) 0)) (w) 'timeout))
                            (else (condition-wait LSP-qcond LSP-qmtx) (w)))))))
        (cond
         ((eq? item 'eof) _xunit)
         ((eq? item 'timeout)
          (when pending (let ((u (car pending)) (tx (cdr pending))) (set! pending #f)
                          (unless (JS_path_is_prelude (vscode_url_to_path u)) (guard (e (#t #f)) (liveValidate u tx)))))
          (loop))
         (else
          (let ((method (msg-method item)))
            (cond
             ((equal? method "textDocument/didChange") (let ((p (guard (e (#t #f)) (apply-didChange item)))) (when p (set! pending p))) (loop))
             ((equal? method "textDocument/didSave") (when (and pending (equal? (car pending) (msg-uri item))) (set! pending #f))
              (guard (e (#t (LSP-stderr "[xats-lsp-resident] dispatch error\n"))) (LSP-dispatch item)) (loop))
             ((equal? method "textDocument/didClose") (when (and pending (equal? (car pending) (msg-uri item))) (set! pending #f))
              (guard (e (#t #f)) (LSP-dispatch item)) (loop))
             (else (guard (e (#t (LSP-stderr "[xats-lsp-resident] dispatch error\n"))) (LSP-dispatch item)) (loop)))))))))
  _xunit)
