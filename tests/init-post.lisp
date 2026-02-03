;; tests/init-post.lisp - Tests for init-post.lisp
;; This test verifies init-post.lisp parses correctly and tests its helper functions.
(load "tests/test-helpers.lisp")

;; ============================================================================
;; Mock builtins required by init-post.lisp
;; ============================================================================
;; termcap is provided by test-helpers.lisp
(defvar *version* "1.0.0-test")

(defun script-echo (title &rest args) "Mock: no-op for startup banner" nil)

;; ============================================================================
;; Load init-post.lisp (this verifies it parses correctly)
;; ============================================================================
(load "lisp/init-post.lisp")

;; ============================================================================
;; Test: visual-length
;; ============================================================================
(assert-equal (visual-length "hello") 5 "visual-length of plain string")
(assert-equal (visual-length "") 0 "visual-length of empty string")
(assert-equal (visual-length "\033[31mred\033[0m") 3
 "visual-length strips ANSI color codes")
(assert-equal (visual-length "\033[38;2;255;0;0mtruecolor\033[0m") 9
 "visual-length strips truecolor ANSI codes")
(assert-equal (visual-length nil) 0 "visual-length of nil returns 0")
;; ============================================================================
;; Test: pad-string
;; ============================================================================
(assert-equal (pad-string "hi" 5) "hi   " "pad-string adds trailing spaces")
(assert-equal (pad-string "hello" 5) "hello"
 "pad-string doesn't pad when already at width")
(assert-equal (pad-string "hello world" 5) "hello world"
 "pad-string doesn't truncate longer strings")
(assert-equal (pad-string "" 3) "   " "pad-string pads empty string")
(assert-equal (pad-string nil 5) "" "pad-string of nil returns empty string")
;; ============================================================================
;; Test: repeat-string
;; ============================================================================
(assert-equal (repeat-string "ab" 3) "ababab" "repeat-string repeats N times")
(assert-equal (repeat-string "x" 1) "x" "repeat-string with count 1")
(assert-equal (repeat-string "x" 0) ""
 "repeat-string with count 0 returns empty")
(assert-equal (repeat-string "x" -1) ""
 "repeat-string with negative count returns empty")
(assert-equal (repeat-string "" 5) "" "repeat-string of empty string")

(print "All init-post.lisp tests passed!")

