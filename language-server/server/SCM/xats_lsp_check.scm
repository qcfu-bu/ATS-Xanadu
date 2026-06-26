;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;                                                                  ;;;;
;;;;   WS-1a  LSP diagnostics checker  -  CHEZ-glue companion         ;;;;
;;;;   (the Chez analog of server/CATS/xats_lsp_check.cats)           ;;;;
;;;;                                                                  ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Every `#extern fun NAME(...) = $extnam()` in xats_lsp_check.dats is
;; implemented here by a same-named Scheme definition.  The build links this
;; file BEFORE the cz0emit-compiled driver, after the runtime + frontend
;; fragments.  The design mirrors the JS .cats exactly: the ATS side walks the
;; typed AST and pushes raw rows; ALL mutable state, dedup (Decision D6), JSON
;; serialization and the file write live HERE, so the ATS side stays a pure
;; traversal + classification pass.
;;
;; Reps (faithful to the cz0emit value model): a "FILR" is a Chez port (the
;; runtime's *_fprint prims do put-string/put-char on it); strings are Scheme
;; strings; argv is the Node-style vector #("node" script arg1 ...) the runtime
;; builds from (command-line).
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; ---- argv access (Node-style; the driver's find_flag scans from index 2) ----
(define (LSPCHK_argv_count) (vector-length (XATSOPT_argv$get)))
(define (LSPCHK_argv_get i0) (vector-ref (XATSOPT_argv$get) i0))

;; ---- string-buffer FILR -----------------------------------------------------
;; s2typ_fprint / sort2_fprint emit through the runtime's port-based fprint
;; family (XATS2JS_NODE_strn_fprint = (put-string port s)), so a Chez string
;; output port captures a type's printed form as a Scheme string.
(define (LSPCHK_strbuf_new) (open-output-string))
(define (LSPCHK_strbuf_get fb) (get-output-string fb))

;; ---- int label / xtv stamp -> string (faithful s2typ printer helpers) ------
(define (TYPRINT_int2str n)
  (number->string (if (number? n) (exact (floor n)) 0)))
(define (TYPRINT_stamp2str s)
  (cond ((number? s) (number->string s))
        ((string? s) s)
        (else (let ((p (open-output-string))) (display s p) (get-output-string p)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ---- accumulators (one-shot: one file per process) -------------------- ;;

(define LSPCHK_diags   '())
(define LSPCHK_hovers  '())
(define LSPCHK_defs    '())
(define LSPCHK_symbols '())
(define LSPCHK_inlays  '())
(define LSPCHK_members '())

;; small helpers ---------------------------------------------------------------
(define (->int x) (if (number? x) (exact (floor x)) 0))
(define (->str x) (cond ((string? x) x) ((not x) "") (else
  (let ((p (open-output-string))) (display x p) (get-output-string p)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ---- friendly type-name map (leaf head-name remap in mismatch msgs) --- ;;

(define LSPCHK_TYPENAME
  (let ((h (make-hashtable string-hash string=?)))
    (for-each
     (lambda (kv) (hashtable-set! h (car kv) (cdr kv)))
     '(("gint_type" . "int") ("bool_type" . "bool") ("char_type" . "char")
       ("gflt_type" . "double") ("xats_void_t" . "void") ("string_i0_tx" . "string")
       ("the_s2exp_strn0" . "string") ("the_s2exp_sint0" . "int")
       ("the_s2exp_uint0" . "uint") ("the_s2exp_slint0" . "lint")
       ("the_s2exp_ulint0" . "ulint") ("the_s2exp_sllint0" . "llint")
       ("the_s2exp_ullint0" . "ullint") ("the_s2exp_sflt0" . "float")
       ("the_s2exp_dflt0" . "double") ("the_s2exp_list0" . "list")
       ("the_s2exp_optn0" . "optn") ("the_s2exp_lazy0" . "lazy")
       ("the_s2exp_p1" . "ptr") ("the_s2exp_p2" . "p2tr")
       ("the_s2exp_bool0" . "bool") ("the_s2exp_char0" . "char")
       ("the_s2exp_void" . "void") ("strn" . "string")
       ("xats_sint_t" . "int") ("xats_uint_t" . "uint")
       ("xats_slint_t" . "lint") ("xats_ulint_t" . "ulint")
       ("xats_ssize_t" . "ssize") ("xats_usize_t" . "usize")
       ("xats_sllint_t" . "llint") ("xats_ullint_t" . "ullint")
       ("xats_strn_t" . "string") ("xats_bool_t" . "bool")
       ("xats_char_t" . "char") ("xats_dflt_t" . "double")
       ("p1tr_tbox" . "ptr") ("p2tr_tbox" . "p2tr")
       ("list_t0_i0_tx" . "list") ("list_vt_i0_vx" . "list_vt")
       ("optn_t0_i0_tx" . "optn") ("optn_vt_i0_vx" . "optn_vt")
       ("lazy_t0_tx" . "lazy") ("lazy_vt_vx" . "lazy_vt")))
    h))

(define (LSPCHK-id-char? c)
  (or (char<=? #\A c #\Z) (char<=? #\a c #\z) (char<=? #\0 c #\9)
      (char=? c #\_) (char=? c #\$)))
(define (LSPCHK-id-start? c)
  (or (char<=? #\A c #\Z) (char<=? #\a c #\z) (char=? c #\_)))

;; replace any `name` (backtick-delimited identifier) that has a friendly alias.
(define (LSPCHK_friendly msg)
  (let ((s (->str msg)) (n 0))
    (set! n (string-length s))
    (let ((out (open-output-string)))
      (let loop ((i 0))
        (cond
         ((>= i n) (get-output-string out))
         ((char=? (string-ref s i) #\`)
          ;; scan an identifier between backticks
          (let scan ((j (+ i 1)))
            (cond
             ((and (< j n) (char=? (string-ref s j) #\`) (> j (+ i 1))
                   (LSPCHK-id-start? (string-ref s (+ i 1))))
              (let ((nm (substring s (+ i 1) j)))
                (if (and (LSPCHK-all-id? nm) (hashtable-contains? LSPCHK_TYPENAME nm))
                    (begin (put-char out #\`)
                           (put-string out (hashtable-ref LSPCHK_TYPENAME nm #f))
                           (put-char out #\`) (loop (+ j 1)))
                    (begin (put-char out #\`) (loop (+ i 1))))))
             ((and (< j n) (LSPCHK-id-char? (string-ref s j))) (scan (+ j 1)))
             (else (put-char out #\`) (loop (+ i 1))))))
         (else (put-char out (string-ref s i)) (loop (+ i 1))))))))

(define (LSPCHK-all-id? nm)
  (and (> (string-length nm) 0)
       (let loop ((k 0))
         (cond ((>= k (string-length nm)) #t)
               ((LSPCHK-id-char? (string-ref nm k)) (loop (+ k 1)))
               (else #f)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ---- push primitives -------------------------------------------------- ;;

(define (LSPCHK_diag_push l0 c0 l1 c1 code message)
  (set! LSPCHK_diags
    (cons (vector (->int l0) (->int c0) (->int l1) (->int c1)
                  (->str code) (LSPCHK_friendly message))
          LSPCHK_diags))
  _xunit)

(define (LSPCHK_hover_push l0 c0 l1 c1 typ kind)
  (let ((t (->str typ)))
    (if (string=? t "") _xunit
        (begin
          (set! LSPCHK_hovers
            (cons (vector (->int l0) (->int c0) (->int l1) (->int c1) t (->str kind))
                  LSPCHK_hovers))
          _xunit))))

(define (LSPCHK_def_push ul0 uc0 ul1 uc1 defpath dl0 dc0 dl1 dc1
                         entity hastdef tdpath tl0 tc0 tl1 tc1)
  (let ((defUri (LSPCHK_path2uri defpath)))
    (if (string=? defUri "") _xunit
        (let ((tdUri (if (= (->int hastdef) 1) (LSPCHK_path2uri tdpath) "")))
          (set! LSPCHK_defs
            (cons (vector (->int ul0) (->int uc0) (->int ul1) (->int uc1)
                          defUri (->int dl0) (->int dc0) (->int dl1) (->int dc1)
                          (->str entity) tdUri
                          (->int tl0) (->int tc0) (->int tl1) (->int tc1))
                  LSPCHK_defs))
          _xunit))))

(define (LSPCHK_symbol_push l0 c0 l1 c1 name kind container typ)
  (if (or (< (->int l0) 0) (< (->int c0) 0) (string=? (->str name) "")) _xunit
      (begin
        (set! LSPCHK_symbols
          (cons (vector (->int l0) (->int c0) (->int l1) (->int c1)
                        (->str name) (->int kind) (->str container) (->str typ))
                LSPCHK_symbols))
        _xunit)))

(define (LSPCHK_inlay_push line col label kind)
  (if (or (< (->int line) 0) (< (->int col) 0) (string=? (->str label) "")) _xunit
      (begin
        (set! LSPCHK_inlays
          (cons (vector (->int line) (->int col) (->str label) (->int kind))
                LSPCHK_inlays))
        _xunit)))

(define (LSPCHK_member_push l0 c0 l1 c1 name typ)
  (if (or (< (->int l0) 0) (< (->int c0) 0) (string=? (->str name) "")) _xunit
      (begin
        (set! LSPCHK_members
          (cons (vector (->int l0) (->int c0) (->int l1) (->int c1)
                        (->str name) (->str typ))
                LSPCHK_members))
        _xunit)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ---- path -> file:// URI (encodeURIComponent per segment) ------------- ;;

;; encodeURIComponent: keep A-Za-z0-9 and -_.!~*'() ; percent-encode the rest
;; as UTF-8 bytes.
(define (LSPCHK-uric-unreserved? c)
  (or (char<=? #\A c #\Z) (char<=? #\a c #\z) (char<=? #\0 c #\9)
      (memv c '(#\- #\_ #\. #\! #\~ #\* #\' #\( #\)))))
(define LSPCHK-hexdig "0123456789ABCDEF")
(define (LSPCHK-pct-byte out b)
  (put-char out #\%)
  (put-char out (string-ref LSPCHK-hexdig (fxand (fxsrl b 4) 15)))
  (put-char out (string-ref LSPCHK-hexdig (fxand b 15))))
(define (LSPCHK-encodeURIComponent s)
  (let ((out (open-output-string)))
    (let loop ((i 0))
      (if (>= i (string-length s)) (get-output-string out)
          (let ((c (string-ref s i)))
            (if (LSPCHK-uric-unreserved? c)
                (put-char out c)
                (let ((cp (char->integer c)))
                  ;; UTF-8 encode the codepoint, percent each byte
                  (cond
                   ((< cp #x80) (LSPCHK-pct-byte out cp))
                   ((< cp #x800)
                    (LSPCHK-pct-byte out (fxior #xC0 (fxsrl cp 6)))
                    (LSPCHK-pct-byte out (fxior #x80 (fxand cp #x3F))))
                   ((< cp #x10000)
                    (LSPCHK-pct-byte out (fxior #xE0 (fxsrl cp 12)))
                    (LSPCHK-pct-byte out (fxior #x80 (fxand (fxsrl cp 6) #x3F)))
                    (LSPCHK-pct-byte out (fxior #x80 (fxand cp #x3F))))
                   (else
                    (LSPCHK-pct-byte out (fxior #xF0 (fxsrl cp 18)))
                    (LSPCHK-pct-byte out (fxior #x80 (fxand (fxsrl cp 12) #x3F)))
                    (LSPCHK-pct-byte out (fxior #x80 (fxand (fxsrl cp 6) #x3F)))
                    (LSPCHK-pct-byte out (fxior #x80 (fxand cp #x3F)))))))
            (loop (+ i 1)))))))

(define (LSPCHK-string-split s ch)
  (let ((n (string-length s)))
    (let loop ((i 0) (start 0) (acc '()))
      (cond
       ((>= i n) (reverse (cons (substring s start n) acc)))
       ((char=? (string-ref s i) ch)
        (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
       (else (loop (+ i 1) start acc))))))

(define (LSPCHK_path2uri p)
  (let ((s (->str p)))
    (cond
     ((string=? s "") "")
     ((and (>= (string-length s) 7) (string=? (substring s 0 7) "file://")) s)
     (else
      (let ((abs (if (and (> (string-length s) 0) (char=? (string-ref s 0) #\/))
                     s
                     ;; resolve relative against cwd
                     (string-append (let ((d (current-directory)))
                                      (if (and (> (string-length d) 0)
                                               (char=? (string-ref d (- (string-length d) 1)) #\/))
                                          d (string-append d "/")))
                                    s))))
        (string-append
         "file://"
         (let ((segs (LSPCHK-string-split abs #\/)))
           (let join ((segs segs) (first #t) (out (open-output-string)))
             (cond
              ((null? segs) (get-output-string out))
              (else
               (unless first (put-char out #\/))
               (put-string out (LSPCHK-encodeURIComponent (car segs)))
               (join (cdr segs) #f out)))))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ---- dedup (Decision D6) + sort -------------------------------------- ;;
;; row accessors by index (see push primitives above)

(define (di-l0 d) (vector-ref d 0)) (define (di-c0 d) (vector-ref d 1))
(define (di-l1 d) (vector-ref d 2)) (define (di-c1 d) (vector-ref d 3))
(define (di-code d) (vector-ref d 4)) (define (di-msg d) (vector-ref d 5))

(define (LSPCHK_posLE la ca lb cb) (or (< la lb) (and (= la lb) (<= ca cb))))
(define (LSPCHK_rank code)
  (cond ((string=? code "type-mismatch") 5)
        ((string=? code "unbound-identifier") 5)
        ((string=? code "unresolved-template") 4)
        ((string=? code "pattern-error") 3)
        ((string=? code "unknown") 2)
        ((string=? code "decl-error") 1)
        (else 2)))

(define (LSPCHK_dedup diags)
  (let ((xs (filter (lambda (d) (and (>= (di-l0 d) 0) (>= (di-c0 d) 0))) diags)))
    ;; (a) collapse by begin position
    (let ((best (make-hashtable string-hash string=?)))
      (for-each
       (lambda (d)
         (let* ((key (string-append (number->string (di-l0 d)) ":" (number->string (di-c0 d))))
                (cur (hashtable-ref best key #f)))
           (if (not cur) (hashtable-set! best key d)
               (let ((dEnd (+ (* (di-l1 d) 1000000) (di-c1 d)))
                     (cEnd (+ (* (di-l1 cur) 1000000) (di-c1 cur))))
                 (cond ((< dEnd cEnd) (hashtable-set! best key d))
                       ((and (= dEnd cEnd) (> (LSPCHK_rank (di-code d)) (LSPCHK_rank (di-code cur))))
                        (hashtable-set! best key d)))))))
       xs)
      (let ((ys (vector->list (hashtable-values best))))
        (define (overlap a b)
          (and (LSPCHK_posLE (di-l0 a) (di-c0 a) (di-l1 b) (di-c1 b))
               (LSPCHK_posLE (di-l0 b) (di-c0 b) (di-l1 a) (di-c1 a))))
        (let ((kept
               (filter
                (lambda (d)
                  (let loop ((es ys))
                    (cond
                     ((null? es) #t)
                     ((eq? (car es) d) (loop (cdr es)))
                     (else
                      (let* ((e (car es))
                             (inside (and (LSPCHK_posLE (di-l0 d) (di-c0 d) (di-l0 e) (di-c0 e))
                                          (LSPCHK_posLE (di-l1 e) (di-c1 e) (di-l1 d) (di-c1 d))))
                             (strictly (and inside
                                            (not (and (= (di-l0 e) (di-l0 d)) (= (di-c0 e) (di-c0 d))
                                                      (= (di-l1 e) (di-l1 d)) (= (di-c1 e) (di-c1 d)))))))
                        (cond
                         (strictly #f)
                         ((and (string=? (di-code d) "decl-error")
                               (not (string=? (di-code e) "decl-error"))
                               (overlap d e)
                               (> (LSPCHK_rank (di-code e)) (LSPCHK_rank (di-code d)))) #f)
                         (else (loop (cdr es)))))))))
                ys)))
          (list-sort
           (lambda (a b)
             (cond ((not (= (di-l0 a) (di-l0 b))) (< (di-l0 a) (di-l0 b)))
                   ((not (= (di-c0 a) (di-c0 b))) (< (di-c0 a) (di-c0 b)))
                   ((not (= (di-l1 a) (di-l1 b))) (< (di-l1 a) (di-l1 b)))
                   (else (< (di-c1 a) (di-c1 b)))))
           kept))))))

;; hover row: #(l0 c0 l1 c1 type kind)
(define (LSPCHK_hover_dedup hs)
  (let ((seen (make-hashtable string-hash string=?)) (out '()))
    (for-each
     (lambda (h)
       (let ((l0 (vector-ref h 0)) (c0 (vector-ref h 1))
             (l1 (vector-ref h 2)) (c1 (vector-ref h 3)))
         (when (and (>= l0 0) (>= c0 0)
                    (not (or (< l1 l0) (and (= l1 l0) (< c1 c0)))))
           (let ((key (string-append (number->string l0) ":" (number->string c0) ":"
                        (number->string l1) ":" (number->string c1) ":"
                        (vector-ref h 5) ":" (vector-ref h 4))))
             (unless (hashtable-contains? seen key)
               (hashtable-set! seen key #t) (set! out (cons h out)))))))
     hs)
    (list-sort
     (lambda (a b)
       (cond ((not (= (vector-ref a 0) (vector-ref b 0))) (< (vector-ref a 0) (vector-ref b 0)))
             ((not (= (vector-ref a 1) (vector-ref b 1))) (< (vector-ref a 1) (vector-ref b 1)))
             ((not (= (vector-ref a 2) (vector-ref b 2))) (> (vector-ref a 2) (vector-ref b 2)))
             (else (> (vector-ref a 3) (vector-ref b 3)))))
     (reverse out))))

;; def row: #(ul0 uc0 ul1 uc1 defUri dl0 dc0 dl1 dc1 entity tdUri tl0 tc0 tl1 tc1)
(define (LSPCHK_def_dedup ds)
  (let ((seen (make-hashtable string-hash string=?)) (out '()))
    (for-each
     (lambda (d)
       (let ((ul0 (vector-ref d 0)) (uc0 (vector-ref d 1))
             (dl0 (vector-ref d 5)) (dc0 (vector-ref d 6)))
         (when (and (>= ul0 0) (>= uc0 0) (>= dl0 0) (>= dc0 0))
           (let ((key (string-append
                       (number->string ul0) ":" (number->string uc0) ":"
                       (number->string (vector-ref d 2)) ":" (number->string (vector-ref d 3)) ":"
                       (vector-ref d 4) ":" (number->string dl0) ":" (number->string dc0) ":"
                       (number->string (vector-ref d 7)) ":" (number->string (vector-ref d 8)) ":"
                       (vector-ref d 9))))
             (unless (hashtable-contains? seen key)
               (hashtable-set! seen key #t) (set! out (cons d out)))))))
     ds)
    (list-sort
     (lambda (a b)
       (cond ((not (= (vector-ref a 0) (vector-ref b 0))) (< (vector-ref a 0) (vector-ref b 0)))
             ((not (= (vector-ref a 1) (vector-ref b 1))) (< (vector-ref a 1) (vector-ref b 1)))
             ((not (= (vector-ref a 2) (vector-ref b 2))) (< (vector-ref a 2) (vector-ref b 2)))
             (else (< (vector-ref a 3) (vector-ref b 3)))))
     (reverse out))))

;; symbol row: #(l0 c0 l1 c1 name kind container typ)
(define (LSPCHK_dedup_symbols ss)
  (let ((seen (make-hashtable string-hash string=?)) (out '()))
    (for-each
     (lambda (s)
       (let ((key (string-append
                   (number->string (vector-ref s 0)) ":" (number->string (vector-ref s 1)) ":"
                   (number->string (vector-ref s 2)) ":" (number->string (vector-ref s 3)) ":"
                   (number->string (vector-ref s 5)) ":" (vector-ref s 4) ":" (vector-ref s 6))))
         (unless (hashtable-contains? seen key)
           (hashtable-set! seen key #t) (set! out (cons s out)))))
     ss)
    (list-sort
     (lambda (a b)
       (cond ((not (= (vector-ref a 0) (vector-ref b 0))) (< (vector-ref a 0) (vector-ref b 0)))
             (else (< (vector-ref a 1) (vector-ref b 1)))))
     (reverse out))))

;; inlay row: #(line char label kind)
(define (LSPCHK_dedup_inlays hs)
  (let ((seen (make-hashtable string-hash string=?)) (out '()))
    (for-each
     (lambda (h)
       (let ((key (string-append
                   (number->string (vector-ref h 0)) ":" (number->string (vector-ref h 1)) ":"
                   (vector-ref h 2) ":" (number->string (vector-ref h 3)))))
         (unless (hashtable-contains? seen key)
           (hashtable-set! seen key #t) (set! out (cons h out)))))
     hs)
    (list-sort
     (lambda (a b)
       (cond ((not (= (vector-ref a 0) (vector-ref b 0))) (< (vector-ref a 0) (vector-ref b 0)))
             (else (< (vector-ref a 1) (vector-ref b 1)))))
     (reverse out))))

;; member row: #(l0 c0 l1 c1 name typ)
(define (LSPCHK_dedup_members ms)
  (let ((seen (make-hashtable string-hash string=?)) (out '()))
    (for-each
     (lambda (m)
       (let ((key (string-append
                   (number->string (vector-ref m 0)) ":" (number->string (vector-ref m 1)) ":"
                   (number->string (vector-ref m 2)) ":" (number->string (vector-ref m 3)) ":"
                   (vector-ref m 4))))
         (unless (hashtable-contains? seen key)
           (hashtable-set! seen key #t) (set! out (cons m out)))))
     ms)
    (reverse out)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ---- JSON writer matching JSON.stringify(bundle, null, 2) ------------- ;;
;; json value reps: (str . S) (num . N) (bool . B) (obj (k . v)...) (arr v...)

(define (jstr s) (cons 'str s))
(define (jnum n) (cons 'num n))
(define (jbool b) (cons 'bool b))
(define (jobj kvs) (cons 'obj kvs))      ; kvs : list of (key-string . jval)
(define (jarr vs) (cons 'arr vs))        ; vs  : list of jval

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
            (put-char out (string-ref LSPCHK-hexdig (fxand (fxsrl code 4) 15)))
            (put-char out (string-ref LSPCHK-hexdig (fxand code 15))))
           (else (put-char out c))))
        (loop (+ i 1)))))
  (put-char out #\"))

(define (json-indent out level)
  (let loop ((k (* level 2))) (when (> k 0) (put-char out #\space) (loop (- k 1)))))

(define (json-emit out v level)
  (case (car v)
    ((str) (json-escape out (cdr v)))
    ((num) (put-string out (number->string (cdr v))))
    ((bool) (put-string out (if (cdr v) "true" "false")))
    ((obj)
     (let ((kvs (cdr v)))
       (if (null? kvs) (put-string out "{}")
           (begin
             (put-string out "{\n")
             (let loop ((kvs kvs) (first #t))
               (unless (null? kvs)
                 (unless first (put-string out ",\n"))
                 (json-indent out (+ level 1))
                 (json-escape out (caar kvs))
                 (put-string out ": ")
                 (json-emit out (cdar kvs) (+ level 1))
                 (loop (cdr kvs) #f)))
             (put-char out #\newline) (json-indent out level) (put-char out #\})))))
    ((arr)
     (let ((vs (cdr v)))
       (if (null? vs) (put-string out "[]")
           (begin
             (put-string out "[\n")
             (let loop ((vs vs) (first #t))
               (unless (null? vs)
                 (unless first (put-string out ",\n"))
                 (json-indent out (+ level 1))
                 (json-emit out (car vs) (+ level 1))
                 (loop (cdr vs) #f)))
             (put-char out #\newline) (json-indent out level) (put-char out #\])))))
    (else (error 'json-emit "bad json value" v))))

(define (json-string v)
  (let ((out (open-output-string))) (json-emit out v 0) (get-output-string out)))

(define (jrange l0 c0 l1 c1)
  (jobj (list (cons "start" (jobj (list (cons "line" (jnum l0)) (cons "character" (jnum c0)))))
              (cons "end"   (jobj (list (cons "line" (jnum l1)) (cons "character" (jnum c1))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ---- json_finish: build the §4 bundle and write it to jsonout -------- ;;

(define (LSPCHK-writefile path str)
  (when (file-exists? path) (delete-file path))
  (call-with-output-file path (lambda (p) (put-string p str))))

;; last-resort ok:false bundle (so the server can detect a crash)
(define (LSPCHK-empty-bundle uri)
  (jobj (list (cons "schema" (jnum 1))
              (cons "uri" (jstr (->str uri)))
              (cons "ok" (jbool #f))
              (cons "nerror" (jnum 0))
              (cons "diagnostics" (jarr '()))
              (cons "hovers" (jarr '()))
              (cons "definitions" (jarr '()))
              (cons "symbols" (jarr '()))
              (cons "inlays" (jarr '())))))

(define (LSPCHK_json_finish uri nerror jsonout)
  (let* ((deduped (LSPCHK_dedup (reverse LSPCHK_diags)))
         (diagnostics
          (map (lambda (d)
                 (jobj (list (cons "range" (jrange (di-l0 d) (di-c0 d) (di-l1 d) (di-c1 d)))
                             (cons "severity" (jnum 1))
                             (cons "code" (jstr (di-code d)))
                             (cons "message" (jstr (di-msg d)))
                             (cons "source" (jstr "ats3")))))
               deduped))
         (hovers
          (map (lambda (h)
                 (jobj (list (cons "range" (jrange (vector-ref h 0) (vector-ref h 1)
                                                   (vector-ref h 2) (vector-ref h 3)))
                             (cons "type" (jstr (vector-ref h 4)))
                             (cons "kind" (jstr (vector-ref h 5))))))
               (LSPCHK_hover_dedup (reverse LSPCHK_hovers))))
         (definitions
          (map (lambda (d)
                 (let ((base (list (cons "useRange" (jrange (vector-ref d 0) (vector-ref d 1)
                                                            (vector-ref d 2) (vector-ref d 3)))
                                   (cons "defUri" (jstr (vector-ref d 4)))
                                   (cons "defRange" (jrange (vector-ref d 5) (vector-ref d 6)
                                                            (vector-ref d 7) (vector-ref d 8)))
                                   (cons "entity" (jstr (vector-ref d 9))))))
                   (jobj (if (string=? (vector-ref d 10) "")
                             base
                             (append base
                                     (list (cons "typeDefUri" (jstr (vector-ref d 10)))
                                           (cons "typeDefRange"
                                                 (jrange (vector-ref d 11) (vector-ref d 12)
                                                         (vector-ref d 13) (vector-ref d 14)))))))))
               (LSPCHK_def_dedup (reverse LSPCHK_defs))))
         (symbols
          (map (lambda (s)
                 (jobj (list (cons "name" (jstr (vector-ref s 4)))
                             (cons "kind" (jnum (vector-ref s 5)))
                             (cons "range" (jrange (vector-ref s 0) (vector-ref s 1)
                                                   (vector-ref s 2) (vector-ref s 3)))
                             (cons "selectionRange" (jrange (vector-ref s 0) (vector-ref s 1)
                                                            (vector-ref s 2) (vector-ref s 3)))
                             (cons "container" (jstr (vector-ref s 6)))
                             (cons "type" (jstr (vector-ref s 7))))))
               (LSPCHK_dedup_symbols (reverse LSPCHK_symbols))))
         (inlays
          (map (lambda (h)
                 (jobj (list (cons "position" (jobj (list (cons "line" (jnum (vector-ref h 0)))
                                                          (cons "character" (jnum (vector-ref h 1))))))
                             (cons "label" (jstr (vector-ref h 2)))
                             (cons "kind" (jnum (vector-ref h 3))))))
               (LSPCHK_dedup_inlays (reverse LSPCHK_inlays))))
         (members
          (map (lambda (m)
                 (jobj (list (cons "receiverRange" (jrange (vector-ref m 0) (vector-ref m 1)
                                                           (vector-ref m 2) (vector-ref m 3)))
                             (cons "name" (jstr (vector-ref m 4)))
                             (cons "type" (jstr (vector-ref m 5))))))
               (LSPCHK_dedup_members (reverse LSPCHK_members))))
         (bundle
          (jobj (list (cons "schema" (jnum 1))
                      (cons "uri" (jstr (->str uri)))
                      (cons "ok" (jbool #t))
                      (cons "nerror" (jnum (->int nerror)))
                      (cons "diagnostics" (jarr diagnostics))
                      (cons "hovers" (jarr hovers))
                      (cons "definitions" (jarr definitions))
                      (cons "symbols" (jarr symbols))
                      (cons "inlays" (jarr inlays))
                      (cons "members" (jarr members))))))
    (guard (e (#t (guard (e2 (#t _xunit))
                    (LSPCHK-writefile jsonout (json-string (LSPCHK-empty-bundle uri)))
                    _xunit)))
      (LSPCHK-writefile jsonout (json-string bundle))
      _xunit)))
