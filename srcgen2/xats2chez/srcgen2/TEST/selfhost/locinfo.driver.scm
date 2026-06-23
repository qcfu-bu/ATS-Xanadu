;; self-host validation for locinfo (source positions).
(define p1 (postn_make_int3 10 1 5))
(define p2 (postn_make_int3 20 2 3))
(display (postn_get_ntot p1)) (display " ")
(display (postn_get_nrow p1)) (display " ")
(display (postn_get_ncol p1)) (newline)
(display (postn_cmp p1 p2)) (display " ")
(display (postn_cmp p2 p1)) (display " ")
(display (postn_cmp p1 p1)) (newline)
