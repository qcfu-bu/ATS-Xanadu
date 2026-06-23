;; self-host validation driver for xstamp0 (the stamp counter library).
;; Exercises stamper_new / stamper_getinc / stamp_cmp compiled to Scheme.
(define s (stamper_new))
(display (stamp_get_uint (stamper_getinc s))) (display " ")
(display (stamp_get_uint (stamper_getinc s))) (display " ")
(display (stamp_get_uint (stamper_getinc s))) (newline)
(display (stamp_cmp (stamper_getinc s) (stamper_getinc s))) (newline)
