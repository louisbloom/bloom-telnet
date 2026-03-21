;; tests/tintin-colors.lisp - Tests for color parsing system
(load "tests/test-loader.lisp")

;; ============================================================================
;; tintin-expand-rgb
;; ============================================================================
(assert-equal (tintin-expand-rgb "fff") '(255 255 255) "expand-rgb 3-char fff")
(assert-equal (tintin-expand-rgb "000") '(0 0 0) "expand-rgb 3-char 000")
(assert-equal (tintin-expand-rgb "abc")
 '(170 187 204) "expand-rgb 3-char abc")
(assert-equal (tintin-expand-rgb "FF0000") '(255 0 0) "expand-rgb 6-char red")
(assert-equal (tintin-expand-rgb "00ff00")
 '(0 255 0) "expand-rgb 6-char green")
(assert-equal (tintin-expand-rgb "0000FF")
 '(0 0 255) "expand-rgb 6-char blue")
;; Invalid length returns black
(assert-equal (tintin-expand-rgb "ab") '(0 0 0) "expand-rgb invalid length")

;; ============================================================================
;; tintin-parse-color-spec - named colors
;; ============================================================================
(assert-equal (tintin-parse-color-spec "red") '("31" nil) "parse-color-spec red")
(assert-equal (tintin-parse-color-spec "green")
 '("32" nil) "parse-color-spec green")
(assert-equal (tintin-parse-color-spec "blue")
 '("34" nil) "parse-color-spec blue")

;; ============================================================================
;; tintin-parse-color-spec - light/bright colors
;; ============================================================================
(assert-equal (tintin-parse-color-spec "light red")
 '("91" nil) "parse-color-spec light red")
(assert-equal (tintin-parse-color-spec "light green")
 '("92" nil) "parse-color-spec light green")

;; ============================================================================
;; tintin-parse-color-spec - RGB formats
;; ============================================================================
(assert-equal (tintin-parse-color-spec "<fff>")
 '("38;2;255;255;255" nil) "parse-color-spec <fff>")
(assert-equal (tintin-parse-color-spec "<F00ff00>")
 '("38;2;0;255;0" nil) "parse-color-spec <F00ff00>")

;; ============================================================================
;; tintin-parse-color-spec - attributes
;; ============================================================================
(assert-equal (tintin-parse-color-spec "bold red")
 '("1;31" nil) "parse-color-spec bold red")

;; ============================================================================
;; tintin-parse-color-spec - fg:bg
;; ============================================================================
(assert-equal (tintin-parse-color-spec "red:blue")
 '("31" "44") "parse-color-spec red:blue")

;; ============================================================================
;; tintin-parse-color-spec - empty/nil
;; ============================================================================
(assert-equal (tintin-parse-color-spec "") '(nil nil) "parse-color-spec empty")

;; ============================================================================
;; tintin-build-ansi-code
;; ============================================================================
(assert-equal (tintin-build-ansi-code "31" nil)
 "\033[31m" "build-ansi-code fg only")
(assert-equal (tintin-build-ansi-code nil "44")
 "\033[44m" "build-ansi-code bg only")
(assert-equal (tintin-build-ansi-code "31" "44")
 "\033[31;44m" "build-ansi-code fg+bg")
(assert-equal (tintin-build-ansi-code nil nil)
 "" "build-ansi-code both nil")

;; ============================================================================
;; Custom named colors - #color / #uncolor
;; ============================================================================
;; Setup: clear any existing custom colors
(set! *tintin-custom-colors* (make-hash-table))

;; Test: define and resolve a simple RGB custom color
(hash-set! *tintin-custom-colors* "failure" "<Fff6daa>")
(assert-equal (tintin-parse-color-spec "failure")
 '("38;2;255;109;170" nil) "custom color resolves RGB spec")

;; Test: define and resolve a custom color with attributes
(hash-set! *tintin-custom-colors* "info" "bold <Fff6dff>")
(assert-equal (tintin-parse-color-spec "info")
 '("1;38;2;255;109;255" nil) "custom color resolves bold + RGB spec")

;; Test: custom color in fg:bg position
(hash-set! *tintin-custom-colors* "success" "<F00ffb2>")
(assert-equal (tintin-parse-color-spec "failure:blue")
 '("38;2;255;109;170" "44") "custom color as fg with named bg")

;; Test: custom colors on both sides of colon
(hash-set! *tintin-custom-colors* "danger-bg" "red")
(let ((result (tintin-parse-color-spec "success:danger-bg")))
  (assert-equal (car result) "38;2;0;255;178" "custom color fg in fg:bg")
  (assert-equal (cadr result) "41" "custom color bg resolves as bg"))

;; Test: non-existent custom color falls through to normal parsing
(assert-equal (tintin-parse-color-spec "red")
 '("31" nil) "non-custom name still parses normally")

;; Test: chained custom colors (name → name → spec)
(hash-set! *tintin-custom-colors* "alias-color" "failure")
(assert-equal (tintin-parse-color-spec "alias-color")
 '("38;2;255;109;170" nil) "chained custom color resolves")

;; Test: circular custom color definition doesn't infinite loop
(hash-set! *tintin-custom-colors* "loop-a" "loop-b")
(hash-set! *tintin-custom-colors* "loop-b" "loop-a")
;; Should not hang; result is nil or falls through
(let ((result (tintin-parse-color-spec "loop-a")))
  (assert-true #t "circular custom color does not hang"))

;; Cleanup
(set! *tintin-custom-colors* (make-hash-table))

(print "All color tests passed!")
