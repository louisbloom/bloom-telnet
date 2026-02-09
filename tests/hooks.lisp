;; Hook system tests for bloom-telnet
;; Tests add-hook, remove-hook, run-hook, and run-filter-hook backed
;; by the *hooks* hash table.

(load "tests/test-helpers.lisp")

;; Reset hooks table for clean state
(set! *hooks* (make-hash-table))

;; ============================================================================
;; Test 1: add-hook with default priority (50)
;; ============================================================================
(define test-called nil)
(defun test-fn-1 (&rest args) (set! test-called #t))

(add-hook 'my-hook test-fn-1)

;; Verify the hook was registered
(let ((hook-list (hash-ref *hooks* "my-hook")))
  (assert-true (pair? hook-list) "Hook list is non-empty after add-hook")
  (assert-equal (length hook-list) 1 "Hook list has 1 entry")
  (let ((entry (car hook-list)))
    (assert-true (eq? (car entry) test-fn-1) "Hook fn is test-fn-1")
    (assert-equal (cdr entry) 50 "Default priority is 50")))

(print "Test 1 passed: add-hook with default priority")

;; ============================================================================
;; Test 2: Duplicate detection (same fn not added twice)
;; ============================================================================
(add-hook 'my-hook test-fn-1)
(add-hook 'my-hook test-fn-1 10)

(let ((hook-list (hash-ref *hooks* "my-hook")))
  (assert-equal (length hook-list) 1 "Still 1 entry after duplicate add-hook"))

(print "Test 2 passed: Duplicate detection")

;; ============================================================================
;; Test 3: Priority-sorted insertion
;; ============================================================================
(set! *hooks* (make-hash-table))

(defun fn-low (&rest args) nil)
(defun fn-mid (&rest args) nil)
(defun fn-high (&rest args) nil)

(add-hook 'sorted-hook fn-mid 50)
(add-hook 'sorted-hook fn-high 90)
(add-hook 'sorted-hook fn-low 10)

(let ((hook-list (hash-ref *hooks* "sorted-hook")))
  (assert-equal (length hook-list) 3 "3 entries after adding 3 hooks")
  ;; Verify order: low (10) -> mid (50) -> high (90)
  (assert-true (eq? (car (car hook-list)) fn-low) "First entry is fn-low (priority 10)")
  (assert-equal (cdr (car hook-list)) 10 "First priority is 10")
  (assert-true (eq? (car (car (cdr hook-list))) fn-mid) "Second entry is fn-mid (priority 50)")
  (assert-equal (cdr (car (cdr hook-list))) 50 "Second priority is 50")
  (assert-true (eq? (car (car (cdr (cdr hook-list)))) fn-high) "Third entry is fn-high (priority 90)")
  (assert-equal (cdr (car (cdr (cdr hook-list)))) 90 "Third priority is 90"))

(print "Test 3 passed: Priority-sorted insertion")

;; ============================================================================
;; Test 4: remove-hook removes by fn identity
;; ============================================================================
(remove-hook 'sorted-hook fn-mid)

(let ((hook-list (hash-ref *hooks* "sorted-hook")))
  (assert-equal (length hook-list) 2 "2 entries after remove-hook")
  (assert-true (eq? (car (car hook-list)) fn-low) "First is still fn-low")
  (assert-true (eq? (car (car (cdr hook-list))) fn-high) "Second is fn-high"))

;; Remove remaining hooks
(remove-hook 'sorted-hook fn-low)
(remove-hook 'sorted-hook fn-high)

(let ((hook-list (hash-ref *hooks* "sorted-hook")))
  (assert-true (null? hook-list) "Hook list is empty after removing all"))

(print "Test 4 passed: remove-hook")

;; ============================================================================
;; Test 5: run-hook calls all fns in priority order
;; ============================================================================
(set! *hooks* (make-hash-table))

(define call-order nil)

(defun recorder-a (&rest args) (set! call-order (append call-order (list "a"))))
(defun recorder-b (&rest args) (set! call-order (append call-order (list "b"))))
(defun recorder-c (&rest args) (set! call-order (append call-order (list "c"))))

(add-hook 'order-hook recorder-b 50)
(add-hook 'order-hook recorder-c 90)
(add-hook 'order-hook recorder-a 10)

(set! call-order nil)
(run-hook 'order-hook)

(assert-equal call-order '("a" "b" "c") "run-hook calls in priority order (a=10, b=50, c=90)")

(print "Test 5 passed: run-hook priority order")

;; ============================================================================
;; Test 6: run-hook passes arguments to hook functions
;; ============================================================================
(set! *hooks* (make-hash-table))

(define received-args nil)
(defun arg-recorder (x y) (set! received-args (list x y)))

(add-hook 'arg-hook arg-recorder)
(run-hook 'arg-hook "hello" 42)

(assert-equal received-args '("hello" 42) "run-hook passes args to hook functions")

(print "Test 6 passed: run-hook passes arguments")

;; ============================================================================
;; Test 7: run-filter-hook threads value through fns
;; ============================================================================
(set! *hooks* (make-hash-table))

(defun add-ten (n) (+ n 10))
(defun double-it (n) (* n 2))

(add-hook 'filter-hook add-ten 10)
(add-hook 'filter-hook double-it 50)

;; Should: 5 -> add-ten -> 15 -> double-it -> 30
(let ((result (run-filter-hook 'filter-hook 5)))
  (assert-equal result 30 "run-filter-hook threads value: 5 -> +10 -> *2 = 30"))

(print "Test 7 passed: run-filter-hook threading")

;; ============================================================================
;; Test 8: Empty/nonexistent hooks
;; ============================================================================
(set! *hooks* (make-hash-table))

(assert-nil (run-hook 'nonexistent-hook) "run-hook on nonexistent hook returns nil")
(assert-equal (run-filter-hook 'nonexistent-hook "initial")
  "initial" "run-filter-hook on nonexistent hook returns initial value")

(print "Test 8 passed: Empty/nonexistent hooks")

(print "")
(print "All hook system tests passed!")
