;; tintin-action-depth.lisp - Regression test for depth leak across action firings
;;
;; Bug: tintin-expand-alias bumped *tintin-alias-depth* to (base-depth + 1) but
;; never restored it. tintin-user-input-hook masked this by resetting depth to 0
;; on each new user input, but tintin-execute-action had no such reset — so every
;; action that expanded an alias left depth permanently incremented. After ~10
;; action firings the "Circular alias detected or depth limit (10) exceeded"
;; error triggered on lines like
;;     #act {Your trip} {x; trip}    with    #alias x where

(load "tests/test-helpers.lisp")
(defmacro load-system-file (name) `(load (string-append "lisp/contrib/" ,name)))
(load "lisp/contrib/tintin.lisp")
(set! *tintin-speedwalk-enabled* #f)

(define *echoed* '())
(defun terminal-echo (msg) (set! *echoed* (append *echoed* (list msg))))

(define *sent* '())
(defun telnet-send (msg) (set! *sent* (append *sent* (list msg))))

(defun some-echoed-contains (needle)
  (let ((found nil))
    (do ((rest *echoed* (cdr rest))) ((or (null? rest) found) found)
      (if (and (string? (car rest)) (string-contains? (car rest) needle))
        (set! found #t)))))

;; ============================================================================
;; Setup: alias x=where, action "Your trip" → "x; trip"
;; ============================================================================
(hash-set! *tintin-aliases* "x" (list "where"))
(hash-set! *tintin-actions* "Your trip" (list "x; trip" 5))

;; ============================================================================
;; Test 1: Single action firing restores depth to 0
;; ============================================================================
(set! *tintin-alias-depth* 0)
(tintin-trigger-actions-for-line "Your trip misses a bloodoathed healer.")
(assert-equal *tintin-alias-depth* 0
  "Depth restored to 0 after action with alias-expanded command")
(assert-false (some-echoed-contains "Circular alias")
  "No circular alias error on single action firing")

(print "Test 1 passed: single action firing restores depth")

;; ============================================================================
;; Test 2: Many repeated action firings never accumulate depth
;; ============================================================================
(set! *echoed* '())
(set! *sent* '())
(set! *tintin-alias-depth* 0)

(do ((i 0 (+ i 1))) ((>= i 50))
  (tintin-trigger-actions-for-line "Your trip misses a bloodoathed healer."))

(assert-false (some-echoed-contains "Circular alias")
  "No circular alias error after 50 action firings")
(assert-equal *tintin-alias-depth* 0
  "Depth still 0 after 50 action firings")

(print "Test 2 passed: repeated action firings do not accumulate depth")

;; ============================================================================
;; Test 3: User-input alias expansion also restores depth
;; ============================================================================
(set! *echoed* '())
(set! *tintin-alias-depth* 0)
(tintin-process-command "x")
(assert-equal *tintin-alias-depth* 0
  "Depth restored to 0 after user-input alias expansion")

(print "Test 3 passed: user-input alias expansion restores depth")

(print "")
(print "All action depth regression tests passed!")
