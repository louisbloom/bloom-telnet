;; tests/tintin-speedwalk.lisp - Tests for speedwalk expansion
(load "tests/test-loader.lisp")

;; Ensure speedwalk is enabled for tests
(set! *tintin-speedwalk-enabled* #t)
(set! *tintin-speedwalk-diagonals* #f)

;; ============================================================================
;; Basic expansion
;; ============================================================================
(assert-equal (tintin-expand-speedwalk "3n2e") "n;n;n;e;e"
 "speedwalk 3n2e")
(assert-equal (tintin-expand-speedwalk "n") "n"
 "speedwalk single direction")
(assert-equal (tintin-expand-speedwalk "nsew") "n;s;e;w"
 "speedwalk four directions")
(assert-equal (tintin-expand-speedwalk "2u3d") "u;u;d;d;d"
 "speedwalk up and down")

;; ============================================================================
;; Invalid input returns original
;; ============================================================================
(assert-equal (tintin-expand-speedwalk "hello") "hello"
 "speedwalk invalid returns original")
(assert-equal (tintin-expand-speedwalk "kill orc") "kill orc"
 "speedwalk non-speedwalk returns original")

;; ============================================================================
;; Disabled speedwalk returns original
;; ============================================================================
(set! *tintin-speedwalk-enabled* #f)
(assert-equal (tintin-expand-speedwalk "3n") "3n"
 "speedwalk disabled returns original")
(set! *tintin-speedwalk-enabled* #t)

;; ============================================================================
;; Diagonal directions
;; ============================================================================
(set! *tintin-speedwalk-diagonals* #t)
(assert-equal (tintin-expand-speedwalk "2ne") "ne;ne"
 "speedwalk diagonals 2ne")
(assert-equal (tintin-expand-speedwalk "nesw") "ne;sw"
 "speedwalk diagonals nesw")
(set! *tintin-speedwalk-diagonals* #f)
