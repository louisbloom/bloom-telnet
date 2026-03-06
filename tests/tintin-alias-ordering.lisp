;; tintin-alias-ordering.lisp - Regression test for alias command ordering
;;
;; Verifies that alias-expanded commands are returned in the correct order
;; relative to non-alias commands when mixed in semicolon-separated input.
;;
;; Bug: "buy seaweed;pb 1." would send "put 1. girdle" BEFORE "buy seaweed"
;; because alias expansion sent directly via telnet-send, while non-alias
;; commands were returned and sent later by the C caller.

(load "tests/test-helpers.lisp")
(defmacro load-system-file (name) `(load (string-append "lisp/" ,name)))
(load "lisp/tintin.lisp")
(set! *tintin-speedwalk-enabled* #f)

;; Mock terminal-echo (alias expansion echoes expanded commands)
(define *echoed* '())
(defun terminal-echo (msg)
  (set! *echoed* (append *echoed* (list msg))))

;; ============================================================================
;; Test 1: Non-alias then alias — ordering preserved
;; ============================================================================
(set! *tintin-alias-depth* 0)
(hash-set! *tintin-aliases* "pb" (list "put %0 girdle"))

(let ((result (tintin-process-input "buy seaweed;pb 1.")))
  (let ((parts (tintin-split-commands result)))
    (assert-equal (length parts) 2
      "Two commands in result")
    (assert-equal (list-ref parts 0) "buy seaweed"
      "Non-alias 'buy seaweed' comes first")
    (assert-equal (list-ref parts 1) "put 1. girdle"
      "Alias-expanded 'put 1. girdle' comes second")))

(print "Test 1 passed: non-alias before alias ordering")

;; ============================================================================
;; Test 2: Alias then non-alias — ordering preserved
;; ============================================================================
(set! *tintin-alias-depth* 0)

(let ((result (tintin-process-input "pb sword;look")))
  (let ((parts (tintin-split-commands result)))
    (assert-equal (length parts) 2
      "Two commands in result")
    (assert-equal (list-ref parts 0) "put sword girdle"
      "Alias-expanded command comes first")
    (assert-equal (list-ref parts 1) "look"
      "Non-alias 'look' comes second")))

(print "Test 2 passed: alias before non-alias ordering")

;; ============================================================================
;; Test 3: Multiple aliases interleaved with non-aliases
;; ============================================================================
(set! *tintin-alias-depth* 0)
(hash-set! *tintin-aliases* "gb" (list "get %1 bag"))

(let ((result (tintin-process-input "look;pb sword;north;gb potion")))
  (let ((parts (tintin-split-commands result)))
    (assert-equal (length parts) 4
      "Four commands in result")
    (assert-equal (list-ref parts 0) "look"
      "First: non-alias look")
    (assert-equal (list-ref parts 1) "put sword girdle"
      "Second: alias pb expanded")
    (assert-equal (list-ref parts 2) "north"
      "Third: non-alias north")
    (assert-equal (list-ref parts 3) "get potion bag"
      "Fourth: alias gb expanded")))

(print "Test 3 passed: interleaved alias/non-alias ordering")

;; ============================================================================
;; Test 4: Nested alias preserves ordering with siblings
;; ============================================================================
(set! *tintin-alias-depth* 0)
(hash-set! *tintin-aliases* "ef" (list "gb lamb;eat lamb"))

(let ((result (tintin-process-input "buy food;ef")))
  (let ((parts (tintin-split-commands result)))
    (assert-equal (length parts) 3
      "Three commands in result")
    (assert-equal (list-ref parts 0) "buy food"
      "First: non-alias buy food")
    (assert-equal (list-ref parts 1) "get lamb bag"
      "Second: nested alias gb expanded first (depth-first)")
    (assert-equal (list-ref parts 2) "eat lamb"
      "Third: eat lamb after nested expansion")))

(print "Test 4 passed: nested alias ordering with preceding non-alias")

(print "")
(print "All alias ordering tests passed!")
