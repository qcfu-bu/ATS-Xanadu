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

;;;====================================================================
;;; end of [xats2chez_generics.scm]  (the FROZEN prelude floor; grows as the
;;; compiler source references more prelude symbols — measured, not guessed)
;;;====================================================================
