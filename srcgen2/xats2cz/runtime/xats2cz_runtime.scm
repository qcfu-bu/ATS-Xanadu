;;; xats2cz_runtime.scm — Chez runtime for emitted ATS3 programs.
;;;
;;; M1: minimal & clean.  Grows per milestone — each primitive faithful to the
;;; authoritative JS contract (srcgen2_prelude.js / prelude .cats), NOT inherited
;;; from the prior attempt's CATS/CHEZ.
;;;
;;; Value rep (honored by cz0emit):
;;;   datacon = #(tag field ...) ; tuple = #(field ...) ; char = integer code.
;;; unit = the _xunit value below.

(define _xunit (if #f #f))                 ; the ATS unit value (Chez "void")
(define XATSTOP0 _xunit)                    ; `_` value placeholder, never demanded

;;; match failure (falling off the end of a case with no matching clause).
(define (XATS000_cfail) (error 'xats2cz "match (case) failure"))
;;; an unresolved template instance reached emission (upstream resolution bug);
;;; a clean compile never emits this — make it a loud trap, not unbound-var.
(define (XATS_undef) (error 'xats2cz "XATS_undef: unresolved template instance"))

;;; ---- datatypes: datacon = #(ctag field ...) ; tuple/record = #(field ...) ----
(define (XATS000_ctgeq v t) (= (vector-ref v 0) t))   ; tag test (slot 0)
(define (XATSPCON con i) (vector-ref con (+ i 1)))      ; datacon field i (skip ctag)

;;; ---- records: symbol-keyed, the Chez analog of a JS object {x:..,y:..}.
;;; Built from alternating  key val  args; projected/mutated by SYMBOL (the
;;; field type is erased in intrep0, so position is NOT recoverable). ----
(define (XATS_rcd2 . kvs)
  (let ((h (make-eq-hashtable)))
    (let loop ((kvs kvs))
      (if (null? kvs) h
          (begin (hashtable-set! h (car kvs) (cadr kvs)) (loop (cddr kvs)))))))
(define (XATS_rsel r k) (hashtable-ref r k #f))            ; field read
(define (XATS_rset r k v) (hashtable-set! r k v) _xunit)   ; field write

;;; ---- mutable left-values: a var is a Chez box; a field-address is
;;; #(container key) — key is an int (tuple/vector slot) or a symbol (record
;;; field).  XATS_lvget/lvset dispatch on box?, then on (symbol? key). ----
(define (XATS_lvget x)
  (cond ((box? x) (unbox x))
        (else (let ((c (vector-ref x 0)) (k (vector-ref x 1)))
                (if (symbol? k) (hashtable-ref c k #f) (vector-ref c k))))))
(define (XATS_lvset x v)
  (cond ((box? x) (set-box! x v))
        (else (let ((c (vector-ref x 0)) (k (vector-ref x 1)))
                (if (symbol? k) (hashtable-set! c k v) (vector-set! c k v))))))
(define (p2tr_get p) (XATS_lvget p))
(define (p2tr_set p v) (XATS_lvset p v))

;;; ---- lazy: l0azy MEMOIZES (#(forced? thunk/value)); l1azy is call-by-name. ----
(define (XATS000_l0azy thunk) (vector 0 thunk))
(define (XATS000_dl0az lz)
  (if (> (vector-ref lz 0) 0)
      (vector-ref lz 1)
      (let ((res ((vector-ref lz 1))))
        (vector-set! lz 0 1) (vector-set! lz 1 res) res)))
(define (XATS000_l1azy thunk) thunk)
(define (XATS000_dl1az lz) (lz 1))

;;; ---- print store (mirrors XATS2JS_the_print_store in srcgen2_prelude.js) ----
;;; A list of pushed strings, kept in reverse; flush joins in order and clears.
(define XATS2JS_the_print_store '())

(define (XATS2JS_sint_print i)
  (set! XATS2JS_the_print_store
        (cons (number->string i) XATS2JS_the_print_store))
  _xunit)

(define (XATS2JS_strn_print s)
  (set! XATS2JS_the_print_store (cons s XATS2JS_the_print_store))
  _xunit)

(define (XATS2JS_the_print_store_clear)
  (set! XATS2JS_the_print_store '())
  _xunit)

(define (XATS2JS_the_print_store_flush)
  (let ((cs (apply string-append (reverse XATS2JS_the_print_store))))
    (set! XATS2JS_the_print_store '())
    cs))

;;; prout = general output, prerr = error reporting (xtop000.cats).  Same shape
;;; as the print store; only flush is defined for these (no clear, no producers).
(define XATS2JS_the_prout_store '())
(define XATS2JS_the_prerr_store '())
(define (XATS2JS_the_prout_store_flush)
  (let ((cs (apply string-append (reverse XATS2JS_the_prout_store))))
    (set! XATS2JS_the_prout_store '()) cs))
(define (XATS2JS_the_prerr_store_flush)
  (let ((cs (apply string-append (reverse XATS2JS_the_prerr_store))))
    (set! XATS2JS_the_prerr_store '()) cs))

;;; console.log(s): writes s then a newline (matches Node console.log).
(define (XATS2JS_console_log s)
  (display s) (newline)
  _xunit)

;;; ---- NODE prelude: print DIRECTLY to stdout (process.stdout.write x.toString()),
;;; not via the print store.  Match JS x.toString() formatting. ----
(define (XATS2JS_NODE_g_print x)    (display x) _xunit)
(define (XATS2JS_NODE_sint_print i) (display i) _xunit)
(define (XATS2JS_NODE_uint_print u) (display u) _xunit)
(define (XATS2JS_NODE_strn_print s) (display s) _xunit)
(define (XATS2JS_NODE_bool_print b) (display (if b "true" "false")) _xunit)
(define (XATS2JS_NODE_char_print c) (display (string (integer->char c))) _xunit)
(define (XATS2JS_NODE_dflt_print f) (display (xats_dflt_tostring f)) _xunit)

;;; ---- sint arithmetic (mirrors srcgen2_prelude.js:314-346) ----
;;; div = Math.trunc(i1/i2) -> quotient (truncates toward zero in Chez);
;;; mod = JS % (sign of dividend) -> remainder (sign of dividend in Chez).
(define (XATS2JS_sint_neg i1) (- i1))
(define (XATS2JS_sint_add$sint i1 i2) (+ i1 i2))
(define (XATS2JS_sint_sub$sint i1 i2) (- i1 i2))
(define (XATS2JS_sint_mul$sint i1 i2) (* i1 i2))
(define (XATS2JS_sint_div$sint i1 i2) (quotient i1 i2))
(define (XATS2JS_sint_mod$sint i1 i2) (remainder i1 i2))

;;; ---- strings (value rep = Scheme string) ----
(define (XATS2JS_strn_length cs) (string-length cs))
(define (XATS2JS_strn_get$at$raw cs i) (char->integer (string-ref cs i)))
(define (XATS2JS_strn_get$at cs i) (char->integer (string-ref cs i)))
;; lexicographic by char code; first nonzero code diff, else (n1 - n2) (matches JS).
(define (XATS2JS_strn_cmp x1 x2)
  (let* ((n1 (string-length x1)) (n2 (string-length x2)) (n0 (min n1 n2)))
    (let loop ((i 0))
      (if (< i n0)
          (let ((df (- (char->integer (string-ref x1 i)) (char->integer (string-ref x2 i)))))
            (if (not (= df 0)) df (loop (+ i 1))))
          (- n1 n2)))))
(define (XATS2JS_strn_eq x1 x2) (string=? x1 x2))
(define (XATS2JS_strn_neq x1 x2) (not (string=? x1 x2)))
;; build a string by collecting char codes pushed through a work callback
;; (JS: cs=[]; fwork(ch=>cs.push(ch)); String.fromCharCode(...cs)).
(define (XATS2JS_strn_make_fwork fwork)
  (let ((cs '()))
    (fwork (lambda (ch) (set! cs (cons ch cs)) _xunit))
    (list->string (map integer->char (reverse cs)))))
(define (XATS2JS_strn_fmake_env$fwork env fwork)
  (let ((cs '()))
    (fwork env (lambda (ch) (set! cs (cons ch cs)) _xunit))
    (list->string (map integer->char (reverse cs)))))
(define XATS2JS_strn_fmake1_env$fwork XATS2JS_strn_fmake_env$fwork)
;; XATS000_* generic aliases (some prelude paths use the generic name).
(define XATS000_strn_length XATS2JS_strn_length)
(define XATS000_strn_get$at$raw XATS2JS_strn_get$at$raw)
(define XATS000_strn_cmp XATS2JS_strn_cmp)
(define (XATS000_strn_print s) (XATS2JS_strn_print s))
(define XATS000_strn_make_fwork XATS2JS_strn_make_fwork)
(define XATS000_strn_fmake_env$fwork XATS2JS_strn_fmake_env$fwork)
(define XATS000_strn_fmake1_env$fwork XATS2JS_strn_fmake1_env$fwork)

;;; ---- sint comparisons (return Scheme booleans = the ATS bool rep) ----
(define (XATS2JS_sint_lt$sint  i1 i2) (< i1 i2))
(define (XATS2JS_sint_gt$sint  i1 i2) (> i1 i2))
(define (XATS2JS_sint_lte$sint i1 i2) (<= i1 i2))
(define (XATS2JS_sint_gte$sint i1 i2) (>= i1 i2))
(define (XATS2JS_sint_eq$sint  i1 i2) (= i1 i2))
(define (XATS2JS_sint_neq$sint i1 i2) (not (= i1 i2)))

;;; ---- uint + int<->uint conversions (gint000.cats) ----
(define (XATS2JS_uint_print u0)
  (set! XATS2JS_the_print_store (cons (number->string u0) XATS2JS_the_print_store))
  _xunit)
(define (XATS2JS_sint_to$uint i0)
  (if (>= i0 0) i0 (error 'xats2cz "sint_to$uint: negative" i0)))
(define (XATS2JS_uint_to$sint u0)
  (if (>= u0 0) u0 (error 'xats2cz "uint_to$sint: negative" u0)))

;;; ---- bool ---- (JS orders bools as 1/0, so compare via the int image)
(define (xats_b2i b) (if b 1 0))
(define (XATS2JS_bool_lt  b1 b2) (< (xats_b2i b1) (xats_b2i b2)))
(define (XATS2JS_bool_gt  b1 b2) (> (xats_b2i b1) (xats_b2i b2)))
(define (XATS2JS_bool_lte b1 b2) (<= (xats_b2i b1) (xats_b2i b2)))
(define (XATS2JS_bool_gte b1 b2) (>= (xats_b2i b1) (xats_b2i b2)))
(define (XATS2JS_bool_eq  b1 b2) (eq? b1 b2))
(define (XATS2JS_bool_neq b1 b2) (not (eq? b1 b2)))

;;; ---- char (value rep = integer code) ----
;;; XATSCHR0: a 1-char source string -> its integer code (char literal emission).
(define (XATSCHR0 s) (char->integer (string-ref s 0)))
(define (XATS2JS_char_lt  c1 c2) (< c1 c2))
(define (XATS2JS_char_lte c1 c2) (<= c1 c2))
(define (XATS2JS_char_gt  c1 c2) (> c1 c2))
(define (XATS2JS_char_gte c1 c2) (>= c1 c2))
(define (XATS2JS_char_eq  c1 c2) (= c1 c2))
(define (XATS2JS_char_neq c1 c2) (not (= c1 c2)))
(define (XATS2JS_char_add$sint c1 i2) (remainder (+ c1 i2) 256))  ; JS (c1+i2)%256
(define (XATS2JS_char_sub$char c1 c2) (- c1 c2))
(define (XATS2JS_char_make_sint i0) i0)   ; char rep IS the int code (identity)
(define (XATS2JS_sint_make_char ch) ch)
(define (XATS2JS_char_print c0)
  (set! XATS2JS_the_print_store
        (cons (string (integer->char c0)) XATS2JS_the_print_store))
  _xunit)

;;; ---- dflt (float; value rep = Chez flonum) — faithful to gflt000.cats ----
(define (XATS2JS_dflt_neg  df) (- df))
(define (XATS2JS_dflt_abs  df) (if (>= df 0.0) df (- df)))
(define (XATS2JS_dflt_sqrt df) (if (< df 0.0) +nan.0 (sqrt df)))   ; JS Math.sqrt(neg)=NaN
(define (XATS2JS_dflt_cbrt df)                                      ; sign-aware cube root
  (if (< df 0.0) (- (expt (- df) (/ 1.0 3.0))) (expt df (/ 1.0 3.0))))
(define (XATS2JS_dflt_add$dflt f1 f2) (+ f1 f2))
(define (XATS2JS_dflt_sub$dflt f1 f2) (- f1 f2))
(define (XATS2JS_dflt_mul$dflt f1 f2) (* f1 f2))
(define (XATS2JS_dflt_div$dflt f1 f2) (/ f1 f2))
(define (XATS2JS_dflt_mod$dflt f1 f2) (- f1 (* f2 (truncate (/ f1 f2)))))  ; JS % (sign of f1)
(define (XATS2JS_dflt_lt$dflt  f1 f2) (< f1 f2))
(define (XATS2JS_dflt_gt$dflt  f1 f2) (> f1 f2))
(define (XATS2JS_dflt_lte$dflt f1 f2) (<= f1 f2))
(define (XATS2JS_dflt_gte$dflt f1 f2) (>= f1 f2))
(define (XATS2JS_dflt_eq$dflt  f1 f2) (= f1 f2))
(define (XATS2JS_dflt_neq$dflt f1 f2) (not (= f1 f2)))
(define (XATS2JS_dflt_cmp$dflt f1 f2) (cond ((< f1 f2) -1) ((> f1 f2) 1) (else 0)))
(define (XATS2JS_dflt_ceil  df) (ceiling df))
(define (XATS2JS_dflt_floor df) (floor df))
(define (XATS2JS_dflt_round df) (floor (+ df 0.5)))    ; JS Math.round = floor(x+0.5)
(define (XATS2JS_dflt_trunc df) (truncate df))

;;; JS Number.toString(): an integer-valued float prints WITHOUT ".0" (10.0 -> "10").
(define (xats_dflt_tostring f)
  (if (and (not (nan? f)) (not (infinite? f)) (= f (floor f)))
      (number->string (exact (floor f)))
      (number->string f)))
(define (XATS2JS_dflt_print f0)
  (set! XATS2JS_the_print_store
        (cons (xats_dflt_tostring f0) XATS2JS_the_print_store))
  _xunit)

;;; ====================================================================
;;; Arrays & maps.  JS arrays -> Chez vectors; JS Map -> Chez hashtable.
;;; (Mostly exercised by the compiler itself; validated at self-hosting.)
;;; ====================================================================

;;; ---- axrf (CATS): refcells + flat arrays.  a0rf = a 1-vector (JS [x]). ----
(define (XATS2JS_a0rf_lget A0) (vector-ref A0 0))
(define (XATS2JS_a0rf_lset A0 x1) (vector-set! A0 0 x1) _xunit)
(define (XATS2JS_a0rf_make_1val x0) (vector x0))
(define (XATS2JS_a1rf_lget$at A0 i0) (vector-ref A0 i0))
(define (XATS2JS_a1rf_lset$at A0 i0 x1) (vector-set! A0 i0 x1) _xunit)
(define (XATS2JS_a1rf_make_ncpy n0 x0) (make-vector n0 x0))
(define (XATS2JS_a1rf_make_nfun n0 fopr)
  (let ((A0 (make-vector n0 0)))
    (do ((i 0 (+ i 1))) ((= i n0) A0) (vector-set! A0 i (fopr i)))))

;;; ---- axsz (CATS): sized arrays.  make_none -> length-n vector (0-filled). ----
(define (XATS2JS_a1sz_length A0) (vector-length A0))
(define (XATS2JS_a1sz_lget$at A0 i0) (vector-ref A0 i0))
(define (XATS2JS_a1sz_lset$at A0 i0 x1) (vector-set! A0 i0 x1) _xunit)
(define (XATS2JS_a1sz_make_none n0) (make-vector n0 0))
(define (XATS2JS_a1sz_make_ncpy n0 x0) (make-vector n0 x0))
(define (XATS2JS_a1sz_make_nfun n0 fopr)
  (let ((A0 (make-vector n0 0)))
    (do ((i 0 (+ i 1))) ((= i n0) A0) (vector-set! A0 i (fopr i)))))
(define (XATS2JS_a1sz_make_fwork fwork)
  (let ((lst '()))
    (fwork (lambda (x0) (set! lst (cons x0 lst)) _xunit))
    (list->vector (reverse lst))))

;;; ---- jsdasz (xatslib native): JS dynamic array -> Chez vector.  Growth only
;;; happens in the build prims (make_fwork pushes), so a plain vector suffices. ----
(define (XATS2JS_jsdasz_length A) (vector-length A))
(define (XATS2JS_jsdasz_get$at A i) (vector-ref A i))
(define (XATS2JS_jsdasz_set$at A i x) (vector-set! A i x) x)   ; JS (A[i]=x) -> x
(define (XATS2JS_jsdasz_make_ncpy n x) (make-vector n x))
(define (XATS2JS_jsdasz_make_nfun n f)
  (let ((A (make-vector n 0)))
    (do ((i 0 (+ i 1))) ((= i n) A) (vector-set! A i (f i)))))
(define (XATS2JS_jsdasz_make_1val x1) (vector x1))
(define (XATS2JS_jsdasz_make_2val x1 x2) (vector x1 x2))
(define (XATS2JS_jsdasz_make_3val x1 x2 x3) (vector x1 x2 x3))
(define (XATS2JS_jsdasz_make_fwork fwork)
  (let ((lst '()))
    (fwork (lambda (x) (set! lst (cons x lst)) _xunit))
    (list->vector (reverse lst))))
(define (XATS2JS_jsdasz_forall$f1un A test)
  (let ((n (vector-length A)))
    (let loop ((i 0))
      (cond ((= i n) #t)
            ((test (vector-ref A i)) (loop (+ i 1)))
            (else #f)))))
(define (XATS2JS_jsdasz_rforall$f1un A test)
  (let ((n (vector-length A)))
    (let loop ((i 0))
      (cond ((= i n) #t)
            ((test (vector-ref A (- n 1 i))) (loop (+ i 1)))
            (else #f)))))
(define (XATS2JS_jsdasz_mapref$f1un A fopr)
  (let ((n (vector-length A)))
    (do ((i 0 (+ i 1))) ((= i n) _xunit) (vector-set! A i (fopr (vector-ref A i))))))
(define (XATS2JS_jsdasz_sortref$f2un A cmpr)
  (vector-sort! (lambda (a b) (< (cmpr a b) 0)) A) _xunit)   ; in-place; JS cmpr sign
(define (XATS2JS_jsdasz_iforall$f2un A test)
  (let ((n (vector-length A)))
    (let loop ((i 0))
      (cond ((= i n) #t)
            ((test i (vector-ref A i)) (loop (+ i 1)))
            (else #f)))))
;; iterator = (vector A idxbox); next$work yields (index, elem).
(define (XATS2JS_jsdasz$iter_make A) (cons A (box 0)))
(define (XATS2JS_jsdasz$iter_next$work iter work)
  (let ((A (car iter)) (ib (cdr iter)))
    (let ((i (unbox ib)))
      (if (< i (vector-length A))
          (begin (set-box! ib (+ i 1)) (work i (vector-ref A i)) #t)
          #f))))

;;; ---- jshmap (xatslib native): JS Map -> Chez equal-hashtable.  NOTE: Chez
;;; hashtable iteration order is unspecified (JS Map = insertion order); revisit
;;; if self-hosting needs ordered traversal. ----
(define (XATS2JS_jshmap_size map) (hashtable-size map))
(define (XATS2JS_jshmap_make_nil) (make-hashtable equal-hash equal?))
(define (XATS2JS_jshmap_keyq map key) (hashtable-contains? map key))
(define (XATS2JS_jshmap_search$tst map key) (hashtable-contains? map key))
(define (XATS2JS_jshmap_get$at$raw map key) (hashtable-ref map key #f))
(define (XATS2JS_jshmap_set$at$raw map key itm) (hashtable-set! map key itm) _xunit)
(define (XATS2JS_jshmap_insert$raw map key itm) (hashtable-set! map key itm) _xunit)
(define (XATS2JS_jshmap_forall$f2un map test)
  (let-values (((ks vs) (hashtable-entries map)))
    (let ((n (vector-length ks)))
      (let loop ((i 0))
        (cond ((= i n) #t)
              ((test (vector-ref ks i) (vector-ref vs i)) (loop (+ i 1)))
              (else #f))))))
(define (XATS2JS_jshmap$iter_make map)
  (let-values (((ks vs) (hashtable-entries map))) (vector ks vs (box 0))))
(define (XATS2JS_jshmap$iter_next$work iter work)
  (let ((ks (vector-ref iter 0)) (vs (vector-ref iter 1)) (ib (vector-ref iter 2)))
    (let ((i (unbox ib)))
      (if (< i (vector-length ks))
          (begin (set-box! ib (+ i 1)) (work (vector-ref ks i) (vector-ref vs i)) #t)
          #f))))

;;; ---- gbas: generic to-string + leading-prefix number parsing ----
(define (XATS2JS_g_tostr obj)
  (cond ((string? obj) obj)
        ((boolean? obj) (if obj "true" "false"))
        ((and (number? obj) (inexact? obj)) (xats_dflt_tostring obj))
        ((number? obj) (number->string obj))
        (else (let ((p (open-output-string))) (display obj p) (get-output-string p)))))
;; mimic JS parseInt(rep,10): skip ws, optional sign, leading digits; #f if none.
(define (xats_str_parse_int rep)
  (let ((n (string-length rep)))
    (let skip ((i 0))
      (cond
        ((and (< i n) (char-whitespace? (string-ref rep i))) (skip (+ i 1)))
        (else
         (let* ((neg (and (< i n) (char=? (string-ref rep i) #\-)))
                (j0 (if (and (< i n) (or neg (char=? (string-ref rep i) #\+))) (+ i 1) i)))
           (let dig ((j j0) (acc 0) (any #f))
             (if (and (< j n) (char<=? #\0 (string-ref rep j) #\9))
                 (dig (+ j 1) (+ (* acc 10) (- (char->integer (string-ref rep j)) 48)) #t)
                 (and any (if neg (- acc) acc))))))))))
(define (XATS2JS_strn_sint$parse$fwork rep0 work)
  (let ((i0 (xats_str_parse_int rep0))) (when i0 (work i0))) _xunit)
(define (XATS2JS_strn_dflt$parse$fwork rep0 work)
  (let ((f0 (string->number rep0)))
    (when (and f0 (real? f0)) (work (exact->inexact f0))))
  _xunit)
