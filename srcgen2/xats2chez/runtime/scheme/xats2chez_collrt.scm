;;;====================================================================
;;; xats2chez_collrt.scm — collection runtime floor: the linear list / lazy
;;; stream low-level constructors + accessors (analog of the JS precats), plus
;;; the higher-order ops that the JS backend gets via trxi0i1 instance
;;; materialization (which the intrep0-direct chez emitter skips).
;;; Reps (match the JS contract): nil=#(0), cons=#(1 h t); a lazy stream is an
;;; l0azy thunk forcing to a strmcon.  Higher-order ops take their continuation
;;; as a trailing arg (injected by lambda-lifting + global-map seeding).
;;;====================================================================

;; strmcon_vt (a FORCED stream cell) + list_vt (a linear list): nil/cons/tests.
(define (strmcon_vt_nil) (vector 1))
(define (strmcon_vt_cons h t) (vector 0 h t))          ; t : lazy strm_vt
(define (strmcon_vt_sing x) (vector 0 x (XATS000_l1azy (lambda (_) (vector 1)))))
(define (strmcon_vt_nilq1 s) (= (vector-ref s 0) 1))
(define (strmcon_vt_consq1 s) (= (vector-ref s 0) 0))
(define (list_vt_nilq1 xs) (= (vector-ref xs 0) 0))
(define (list_vt_consq1 xs) (= (vector-ref xs 0) 1))
(define (list_vt_head$raw1 xs) (vector-ref xs 1))
(define (list_vt_tail$raw0 xs) (vector-ref xs 2))
(define (strm_vt_nil) (XATS000_l1azy (lambda (_) (vector 1))))
