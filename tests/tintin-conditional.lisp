;; tests/tintin-conditional.lisp - Tests for #if/#else/#elseif and #read
(load "tests/test-helpers.lisp")

;; Shim load-system-file as a macro so (load ...) runs at top level,
;; allowing (define ...) in loaded files to create global bindings.
(defmacro load-system-file (filename)
  `(load (concat "lisp/contrib/" ,filename)))

;; Load the full tintin stack (brings in all modules including conditionals)
(load "lisp/contrib/tintin.lisp")

;; ============================================================================
;; HELPERS
;; ============================================================================
;; Capture telnet-send calls for testing
(define *test-sent* '())
(defun telnet-send (msg)
  (set! *test-sent* (append *test-sent* (list msg))))
(defun reset-sent ()
  (set! *test-sent* '()))

;; ============================================================================
;; tintin-evaluate-condition - String equality
;; ============================================================================
(assert-true (tintin-evaluate-condition "\"a\" == \"a\"")
 "condition: string equality true")
(assert-false (tintin-evaluate-condition "\"a\" == \"b\"")
 "condition: string equality false")
(assert-true (tintin-evaluate-condition "\"a\" != \"b\"")
 "condition: string inequality true")
(assert-false (tintin-evaluate-condition "\"a\" != \"a\"")
 "condition: string inequality false")

;; ============================================================================
;; tintin-evaluate-condition - Numeric comparisons
;; ============================================================================
(assert-true (tintin-evaluate-condition "5 > 3")
 "condition: numeric greater than")
(assert-false (tintin-evaluate-condition "3 > 5")
 "condition: numeric greater than false")
(assert-true (tintin-evaluate-condition "3 < 5")
 "condition: numeric less than")
(assert-false (tintin-evaluate-condition "5 < 3")
 "condition: numeric less than false")
(assert-true (tintin-evaluate-condition "5 >= 5")
 "condition: numeric greater or equal")
(assert-true (tintin-evaluate-condition "5 >= 3")
 "condition: numeric greater or equal (greater)")
(assert-true (tintin-evaluate-condition "3 <= 3")
 "condition: numeric less or equal")
(assert-true (tintin-evaluate-condition "3 <= 5")
 "condition: numeric less or equal (less)")
(assert-true (tintin-evaluate-condition "5 == 5")
 "condition: numeric equality")
(assert-false (tintin-evaluate-condition "5 == 3")
 "condition: numeric equality false")
(assert-true (tintin-evaluate-condition "5 != 3")
 "condition: numeric inequality")

;; ============================================================================
;; tintin-evaluate-condition - Bare value truth tests
;; ============================================================================
(assert-true (tintin-evaluate-condition "1")
 "condition: bare 1 is true")
(assert-false (tintin-evaluate-condition "0")
 "condition: bare 0 is false")
(assert-true (tintin-evaluate-condition "hello")
 "condition: bare non-empty string is true")
(assert-false (tintin-evaluate-condition "")
 "condition: bare empty string is false")

;; ============================================================================
;; tintin-evaluate-condition - Variable expansion
;; ============================================================================
(hash-set! *tintin-variables* "testvar" "true")
(assert-true (tintin-evaluate-condition "\"$testvar\" == \"true\"")
 "condition: variable expansion in quoted comparison")
(hash-remove! *tintin-variables* "testvar")

;; ============================================================================
;; #if - 2-arg (condition + true-body)
;; ============================================================================
(assert-equal (tintin-process-input "#if {1} {north}") "north"
 "#if: true condition executes body")
(assert-equal (tintin-process-input "#if {0} {north}") ""
 "#if: false condition skips body")

;; ============================================================================
;; #if - 3-arg (condition + true-body + false-body)
;; ============================================================================
(assert-equal (tintin-process-input "#if {1} {north} {south}") "north"
 "#if: true condition selects true-body")
(assert-equal (tintin-process-input "#if {0} {north} {south}") "south"
 "#if: false condition selects false-body")

;; ============================================================================
;; #if - String comparison with variables
;; ============================================================================
(hash-set! *tintin-variables* "dir" "north")
(assert-equal (tintin-process-input "#if {\"$dir\" == \"north\"} {go_north}")
 "go_north"
 "#if: variable string comparison true")
(assert-equal (tintin-process-input "#if {\"$dir\" == \"south\"} {go_south}")
 ""
 "#if: variable string comparison false")
(hash-remove! *tintin-variables* "dir")

;; ============================================================================
;; #else - Executes when #if was false
;; ============================================================================
(tintin-process-input "#if {0} {north}")
(assert-equal (tintin-process-input "#else {south}") "south"
 "#else: executes when #if was false")

;; #else - Skipped when #if was true
(tintin-process-input "#if {1} {north}")
(assert-equal (tintin-process-input "#else {south}") ""
 "#else: skipped when #if was true")

;; ============================================================================
;; #elseif - Chain with #if
;; ============================================================================
;; #if false, #elseif true
(tintin-process-input "#if {0} {first}")
(assert-equal (tintin-process-input "#elseif {1} {second}") "second"
 "#elseif: executes when #if was false and condition is true")

;; #if true, #elseif skipped
(tintin-process-input "#if {1} {first}")
(assert-equal (tintin-process-input "#elseif {1} {second}") ""
 "#elseif: skipped when #if was true")

;; #if false, #elseif false, #else executes
(tintin-process-input "#if {0} {first}")
(tintin-process-input "#elseif {0} {second}")
(assert-equal (tintin-process-input "#else {third}") "third"
 "#else: executes after #if and #elseif both false")

;; #if false, #elseif true, #else skipped
(tintin-process-input "#if {0} {first}")
(tintin-process-input "#elseif {1} {second}")
(assert-equal (tintin-process-input "#else {third}") ""
 "#else: skipped after #elseif was true")

;; ============================================================================
;; Prefix matching - exact match priority
;; ============================================================================
(assert-equal (tintin-find-command "else") "else"
 "prefix matching: 'else' resolves to 'else' not 'elseif'")
(assert-equal (tintin-find-command "elseif") "elseif"
 "prefix matching: 'elseif' resolves to 'elseif'")
(assert-equal (tintin-find-command "if") "if"
 "prefix matching: 'if' resolves to 'if'")

;; ============================================================================
;; Integration - seaport.conf pattern
;; ============================================================================
;; Disable speedwalk so "sseen" isn't expanded as directional shorthand
(set! *tintin-speedwalk-enabled* #f)

(hash-set! *tintin-variables* "seaport" "true")
(reset-sent)
(let ((result
       (tintin-process-input
        "#if {\"$seaport\" == \"true\"} {sseen;op n;n}")))
  (assert-equal result "sseen;op n;n"
   "integration: seaport pattern with true variable"))

(hash-set! *tintin-variables* "seaport" "false")
(let ((result
       (tintin-process-input
        "#if {\"$seaport\" == \"true\"} {sseen;op n;n}")))
  (assert-equal result ""
   "integration: seaport pattern with false variable"))
(hash-remove! *tintin-variables* "seaport")

(set! *tintin-speedwalk-enabled* #t)

;; ============================================================================
;; #if with action body containing #unact
;; ============================================================================
(hash-set! *tintin-actions* "test-pattern" (list "#if {1} {north}" 5))
(assert-true (hash-ref *tintin-actions* "test-pattern")
 "integration: action with #if body stored")
(hash-remove! *tintin-actions* "test-pattern")

(print "All tintin-conditional tests passed!")
