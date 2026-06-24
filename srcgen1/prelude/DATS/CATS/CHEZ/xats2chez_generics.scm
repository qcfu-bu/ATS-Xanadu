;;;====================================================================
;;; xats2chez_generics.scm — the GENERIC-RESOLUTION layer, loaded LAST.
;;;
;;; The intrep0-direct emitter type-ERASES template instances to their base
;;; name (g_eq, g_cmp, char_eq, strn_make_llist, ...).  The JS backend gives
;;; each instance a distinct monomorphized body via trxi0i1; we skip that, so
;;; every prelude file that instantiates a generic emits an UNGUARDED
;;; (define g_cmp ...) for ITS type, and they clobber each other — last-loaded
;;; wins.  e.g. tupl002's g_cmp is the tuple comparator `(g_cmp (vector-ref x0
;;; 0) ...)`, so after it loads, comparing two scalars vector-refs an int and
;;; crashes ("10 is not a vector").
;;;
;;; Fix: this file is concatenated AFTER all compiled units, providing a SINGLE
;;; correct, fully-polymorphic (or arity-dispatching) definition of each
;;; colliding generic.  Being last, it wins.  The value representation is
;;; uniform (numbers / strings / vectors=tuples&datacons), so one structural
;;; definition is correct for every instantiation.
;;;
;;; (This is the runtime analog of monomorphization: instead of N specialized
;;; functions, one polymorphic function that dispatches on the runtime value.)
;;;====================================================================

;;;--------------------------------------------------------------------
;;; Comparison generics.  g_cmp returns a sign -1/0/1 and is STRUCTURAL on
;;; vectors (lexicographic over fields), so it is correct for scalars, strings,
;;; tuples, datacons, and lists alike.  g_eq/g_neq use equal?.  g_lt/g_gt/g_lte/
;;; g_gte derive from g_cmp.
;;;--------------------------------------------------------------------
(define (g_cmp a b)
  (cond
    ((and (number? a) (number? b)) (cond ((< a b) -1) ((> a b) 1) (else 0)))
    ((and (string? a) (string? b)) (cond ((string<? a b) -1) ((string>? a b) 1) (else 0)))
    ((and (vector? a) (vector? b))
     (let ((na (vector-length a)) (nb (vector-length b)))
       (let loop ((i 0))
         (cond ((and (= i na) (= i nb)) 0)
               ((= i na) -1)
               ((= i nb) 1)
               (else (let ((c (g_cmp (vector-ref a i) (vector-ref b i))))
                       (if (= c 0) (loop (+ i 1)) c)))))))
    (else 0)))
(define (g_eq  a b) (equal? a b))
(define (g_neq a b) (not (equal? a b)))
(define (g_lt  a b) (< (g_cmp a b) 0))
(define (g_gt  a b) (> (g_cmp a b) 0))
(define (g_lte a b) (<= (g_cmp a b) 0))
(define (g_gte a b) (>= (g_cmp a b) 0))
(define (g_equal a b) (equal? a b))

;; char comparisons (a char IS its integer code).
(define (char_eq  a b) (= a b))
(define (char_neq a b) (not (= a b)))
(define (char_lt  a b) (< a b))
(define (char_gt  a b) (> a b))
(define (char_lte a b) (<= a b))
(define (char_gte a b) (>= a b))
(define (char_cmp a b) (cond ((< a b) -1) ((> a b) 1) (else 0)))

;;;--------------------------------------------------------------------
;;; strn_make_llist — collides between strn000's 2-arg $fwork instance and the
;;; lexer's 1-arg string-builder.  case-lambda dispatches on arity:
;;;   1-arg (cs)            : build a Scheme string from a char-code list_vt.
;;;   2-arg (cs env$fwork)  : strn000's make-with-env-fwork (iterate work over cs).
;;;--------------------------------------------------------------------
(define strn_make_llist
  (case-lambda
    ((cs)
     (let loop ((cs cs) (acc '()))
       (if (= (vector-ref cs 0) 0)
           (list->string (reverse acc))
           (loop (vector-ref cs 2) (cons (integer->char (vector-ref cs 1)) acc)))))
    ((cs env$fwork)
     (define (fwork cs work)
       (let loop ((cs cs))
         (if (= (vector-ref cs 0) 0) (vector)
             (begin (work (vector-ref cs 1)) (loop (vector-ref cs 2))))))
     (env$fwork cs fwork))))

;;;--------------------------------------------------------------------
;;; gseq_* — generic SEQUENCE ops, polymorphic over the container (string |
;;; list_vt vector).  Type erasure collapses gseq_exists<string> and
;;; gseq_exists<list> onto one name; the list instance (list_exists) wins and
;;; vector-refs a string (e.g. IDSYMq's symseq "%&+...").  Dispatch on the
;;; runtime rep: a string iterates char codes, a #(0)/#(1 h t) vector walks cons.
;;;--------------------------------------------------------------------
(define (gseq_exists xs test)
  (cond
    ((string? xs)
     (let ((n (string-length xs)))
       (let loop ((i 0))
         (cond ((>= i n) #f)
               ((test (char->integer (string-ref xs i))) #t)
               (else (loop (+ i 1)))))))
    ((vector? xs)
     (let loop ((xs xs))
       (cond ((= (vector-ref xs 0) 0) #f)
             ((test (vector-ref xs 1)) #t)
             (else (loop (vector-ref xs 2))))))
    (else #f)))
(define (gseq_forall xs test)
  (cond
    ((string? xs)
     (let ((n (string-length xs)))
       (let loop ((i 0))
         (cond ((>= i n) #t)
               ((test (char->integer (string-ref xs i))) (loop (+ i 1)))
               (else #f)))))
    ((vector? xs)
     (let loop ((xs xs))
       (cond ((= (vector-ref xs 0) 0) #t)
             ((test (vector-ref xs 1)) (loop (vector-ref xs 2)))
             (else #f))))
    (else #t)))
(define (gseq_memberq xs x0)
  (gseq_exists xs (lambda (x1) (g_eq x0 x1))))
;; list_exists is the list instance of the same generic — same polymorphic body.
(define (list_exists xs test) (gseq_exists xs test))

;;;--------------------------------------------------------------------
;;; Option (optn) constructors + a few stream/list reifiers that the COMPILER
;;; source references from the FROZEN prelude (measured floor, not recompiled).
;;; option: none = #(0), some(x) = #(1 x).
;;;--------------------------------------------------------------------
(define (optn_nil) (vector 0))
(define (optn_cons x) (vector 1 x))
;; strm_vt_listize0: force a lazy strm_vt (l1azy -> strmcon_vt nil=#(0)/cons=#(1 h
;; lazytail)) fully into a list_vt (#(0) nil / #(1 h t) cons).
(define (strm_vt_listize0 xs)
  (let loop ((s (XATS000_dl1az xs)))
    (if (= (vector-ref s 0) 0) (vector 0)
        (vector 1 (vector-ref s 1) (loop (XATS000_dl1az (vector-ref s 2)))))))

;;;--------------------------------------------------------------------
;;; FROZEN-PRELUDE FLOOR for the FULL compiler (measured from compiling
;;; srcgen2/DATS/* against this runtime).  Semantics per the ATS prelude /
;;; JS srcgen2_prelude.js contract.  Comparison-based ops use the polymorphic
;;; global g_cmp above (no continuation injection needed); ops with a genuine
;;; per-call closure ($fopr/$work/$test) take it as a trailing arg.
;;;--------------------------------------------------------------------

;; physical-identity casts (linear -> persistent; same vector rep).
(define (list_vt2t xs) xs)
(define (optn_vt2t xs) xs)
(define (stropt_unsome s) s)

;; seq->scheme-list helper (string char-codes | list_vt cons cells).
(define (cz-seq->list s)
  (cond ((string? s) (map char->integer (string->list s)))
        ((vector? s)
         (let loop ((s s) (acc '()))
           (if (= (vector-ref s 0) 0) (reverse acc)
               (loop (vector-ref s 2) (cons (vector-ref s 1) acc)))))
        (else '())))
(define (cz-list->list_vt xs)            ; scheme list -> list_vt (#(0)/#(1 h t))
  (let loop ((xs (reverse xs)) (acc (vector 0)))
    (if (null? xs) acc (loop (cdr xs) (vector 1 (car xs) acc)))))

;; list ops
(define (list_last xs)
  (let loop ((xs xs))
    (let ((t (vector-ref xs 2)))
      (if (= (vector-ref t 0) 0) (vector-ref xs 1) (loop t)))))
(define (list_mergesort xs)
  (cz-list->list_vt (list-sort (lambda (a b) (< (g_cmp a b) 0)) (cz-seq->list xs))))
(define (list_sortedq xs)
  (let loop ((l (cz-seq->list xs)))
    (cond ((null? l) #t) ((null? (cdr l)) #t)
          ((<= (g_cmp (car l) (cadr l)) 0) (loop (cdr l))) (else #f))))
(define (list_rappendx0_vt xs ys)        ; reverse(xs) ++ ys
  (let loop ((xs xs) (acc ys))
    (if (= (vector-ref xs 0) 0) acc
        (loop (vector-ref xs 2) (vector 1 (vector-ref xs 1) acc)))))
(define (list_make_fwork fwork)          ; fwork drives elems into a sink, in order
  (let ((acc (box '())))
    (fwork (lambda (x) (set-box! acc (cons x (unbox acc))) XATSTOP0))
    (cz-list->list_vt (reverse (unbox acc)))))

;; option iteration
(define (optn_foritm xs work)
  (if (= (vector-ref xs 0) 1) (begin (work (vector-ref xs 1)) XATSTOP0) XATSTOP0))

;; string-as-sequence
(define (strn_nilq s) (= 0 (string-length s)))
;; strn_append: the prelude's foritm-based instance is lambda-lifted to a 3-arg
;; ($f1un) form that clobbers the native 2-arg concat; re-assert the native one
;; here (loaded last) — concatenation needs no continuation.
(define (strn_append s t) (string-append s t))
(define (strn_foldl s r0 fwork)          ; left fold: fwork(acc, char-code) -> acc
  (let ((n (string-length s)))
    (let loop ((i 0) (r r0))
      (if (>= i n) r (loop (+ i 1) (fwork r (char->integer (string-ref s i))))))))
;; stropt: none = #f sentinel, some(s) = the string itself (matches JS null/string).
(define (stropt_nilq opt) (not (string? opt)))

;; streams: terminating strm_vt lazy map (cf. infinite strx_vt_map0 above).
(define (strm_vt_map0 xs fopr)
  (XATS000_l1azy
   (lambda (_)
     (let ((c (XATS000_dl1az xs)))
       (if (= (vector-ref c 0) 0) (vector 0)
           (vector 1 (fopr (vector-ref c 1)) (strm_vt_map0 (vector-ref c 2) fopr)))))))

;; gseq generic-sequence ops (container-polymorphic over string | list_vt)
(define (gseq_get$at$opt xs i)
  (let loop ((l (cz-seq->list xs)) (i i))
    (cond ((null? l) (vector 0)) ((= i 0) (vector 1 (car l))) (else (loop (cdr l) (- i 1))))))
(define (gseq_prefixq xs1 xs2)
  (let loop ((a (cz-seq->list xs1)) (b (cz-seq->list xs2)))
    (cond ((null? a) #t) ((null? b) #f)
          ((= (g_cmp (car a) (car b)) 0) (loop (cdr a) (cdr b))) (else #f))))
(define (gseq_z2cmp11 xs ys)
  (let loop ((a (cz-seq->list xs)) (b (cz-seq->list ys)))
    (cond ((and (null? a) (null? b)) 0) ((null? a) -1) ((null? b) 1)
          (else (let ((c (g_cmp (car a) (car b)))) (if (= c 0) (loop (cdr a) (cdr b)) c))))))
;; gseq_group_lstrm_llist(xs, test): lazy stream of runs (consecutive elems where
;; test(x) holds, emitted as a list_vt when test turns false).  test trailing arg.
(define (gseq_group_lstrm_llist xs test)
  (let build ((l (cz-seq->list xs)))
    (XATS000_l1azy
     (lambda (_)
       (if (null? l) (vector 0)
           (let grab ((l l) (run '()))
             (cond ((and (pair? l) (test (car l))) (grab (cdr l) (cons (car l) run)))
                   ((null? run) (grab (cdr l) (list (car l))))   ; always take >=1
                   (else (vector 1 (cz-list->list_vt (reverse run)) (build l))))))))))

;; a0ref — a single mutable box; dt = direct/destructive read/write.
(define (a0ref_dtget r) (unbox r))
(define (a0ref_dtset r x) (set-box! r x) XATSTOP0)
(define (XATS2JS_a0ref_set r x) (set-box! r x) XATSTOP0)

;; a1ptr — pointer array (vector); free is a GC no-op.
(define (a1ptr_free a sz) XATSTOP0)
(define (a1ptr_get$at1 a i) (vector-ref a i))
(define (a1ptr_make_llist xs)
  (let* ((l (cz-seq->list xs)) (v (make-vector (length l))))
    (let loop ((l l) (i 0)) (if (null? l) v (begin (vector-set! v i (car l)) (loop (cdr l) (+ i 1)))))))

;; char / float
(define (char_fprint c out)
  (if (output-port? out) (write-char (integer->char c) out)
      (XATS2JS_strn_print (string (integer->char c)))) XATSTOP0)
(define (gflt_eq$dflt$dflt a b) (fl= a b))

;;;--------------------------------------------------------------------
;;; Variadic gs_* print/max families.  The _nN suffix is a fixed arity and the
;;; _aN suffix is a generated true-variadic; a Scheme variadic accepts any of
;;; them, so one impl per family is aliased to every arity name.
;;;   print -> push onto the print store;  prout -> stdout store;  prerr -> stderr
;;;   ...ln  -> flush + newline;  max -> left-fold g_max (NOT printing).
;;;--------------------------------------------------------------------
(define (gs--prints . args) (for-each gs_print_one args) XATSTOP0)
(define (gs--printlns . args) (for-each gs_print_one args) (console_log (the_print_store_flush)))
(define (gs--prerrs . args) (for-each cats-prerr1 args) XATSTOP0)
(define (gs--prerrlns . args) (for-each cats-prerr1 args) (newline (current-error-port)) XATSTOP0)
(define (gs--maxs . args) (fold-left g_max (car args) (cdr args)))
(define-syntax cz-alias
  (syntax-rules () ((_ tgt n ...) (begin (define n tgt) ...))))
(cz-alias gs--prints
  gs_print_n0 gs_print_n1 gs_print_n2 gs_print_n3 gs_print_n4 gs_print_n5 gs_print_n6
  gs_print_n7 gs_print_n8 gs_print_n9 gs_print_n10 gs_print_n11 gs_print_n12
  gs_print_a0 gs_print_a1 gs_print_a2 gs_print_a3 gs_print_a4 gs_print_a5 gs_print_a6
  gs_print_a7 gs_print_a8 gs_print_a9 gs_print_a10 gs_print_a11 gs_print_a12
  gs_prout_n0 gs_prout_n1 gs_prout_n2 gs_prout_n3 gs_prout_n4 gs_prout_n5 gs_prout_n6
  gs_prout_n7 gs_prout_n8 gs_prout_a0 gs_prout_a1 gs_prout_a2 gs_prout_a3 gs_prout_a4)
(cz-alias gs--printlns
  gs_println_n0 gs_println_n1 gs_println_n2 gs_println_n3 gs_println_n4 gs_println_n5
  gs_println_n6 gs_println_n7 gs_println_n8 gs_println_n9 gs_println_n10 gs_println_n11 gs_println_n12
  gs_println_a0 gs_println_a1 gs_println_a2 gs_println_a3 gs_println_a4 gs_println_a5 gs_println_a6
  gs_proutln_n0 gs_proutln_n1 gs_proutln_n2 gs_proutln_n3 gs_proutln_n4)
(cz-alias gs--prerrs
  gs_prerr_n0 gs_prerr_n1 gs_prerr_n2 gs_prerr_n3 gs_prerr_n4 gs_prerr_n5 gs_prerr_n6
  gs_prerr_n7 gs_prerr_n8 gs_prerr_a0 gs_prerr_a1 gs_prerr_a2 gs_prerr_a3 gs_prerr_a4)
(cz-alias gs--prerrlns
  gs_prerrln_n0 gs_prerrln_n1 gs_prerrln_n2 gs_prerrln_n3 gs_prerrln_n4 gs_prerrln_n5
  gs_prerrln_n6 gs_prerrln_n7 gs_prerrln_n8 gs_prerrln_n9 gs_prerrln_n10
  gs_prerrln_a0 gs_prerrln_a1 gs_prerrln_a2 gs_prerrln_a3 gs_prerrln_a4)
(cz-alias gs--maxs gs_max_n2 gs_max_n3 gs_max_n4 gs_max_n5 gs_max_n6 gs_max_n7 gs_max_n8)

;;;====================================================================
;;; end of [xats2chez_generics.scm]  (the FROZEN prelude floor; grows as the
;;; compiler source references more prelude symbols — measured, not guessed)
;;;====================================================================
