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
