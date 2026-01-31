;; tests/tintin-parsing.lisp - Tests for argument and command parsing
(load "tests/test-loader.lisp")

;; ============================================================================
;; tintin-split-commands - basic splitting
;; ============================================================================
(assert-equal (tintin-split-commands "n;s;e") '("n" "s" "e")
 "split-commands basic semicolons")
(assert-equal (tintin-split-commands "single") '("single")
 "split-commands single command")
(assert-nil (tintin-split-commands "") "split-commands empty string")

;; ============================================================================
;; tintin-split-commands - brace awareness
;; ============================================================================
(assert-equal (tintin-split-commands "#alias {go} {n;s;e}")
 '("#alias {go} {n;s;e}") "split-commands braces protect semicolons")
(assert-equal (tintin-split-commands "a;{b;c};d") '("a" "{b;c}" "d")
 "split-commands mixed braces and bare")

;; ============================================================================
;; tintin-extract-braced
;; ============================================================================
(let ((result (tintin-extract-braced "{hello}" 0)))
  (assert-equal (car result) "{hello}" "extract-braced simple text")
  (assert-equal (cdr result) 7 "extract-braced end pos"))

;; Nested braces
(let ((result (tintin-extract-braced "{a{b}c}" 0)))
  (assert-equal (car result) "{a{b}c}" "extract-braced nested")
  (assert-equal (cdr result) 7 "extract-braced nested end pos"))

;; With leading text
(let ((result (tintin-extract-braced "cmd {arg}" 0)))
  (assert-equal (car result) "{arg}" "extract-braced skips leading text")
  (assert-equal (cdr result) 9 "extract-braced after skip end pos"))

;; No braces
(assert-nil (tintin-extract-braced "no braces" 0)
 "extract-braced returns nil when no braces")

;; ============================================================================
;; tintin-parse-arguments
;; ============================================================================
(assert-equal (tintin-parse-arguments "#alias bag {kill %1}" 2)
 '("bag" "{kill %1}") "parse-arguments mixed unbraced+braced")
(assert-equal (tintin-parse-arguments "#load Det" 1)
 '("Det") "parse-arguments single unbraced")
(assert-equal (tintin-parse-arguments "#highlight {red} {orc}" 2)
 '("{red}" "{orc}") "parse-arguments two braced")
