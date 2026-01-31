;; tests/tintin-highlights.lisp - Tests for highlight pipeline
(load "tests/test-loader.lisp")

;; ============================================================================
;; tintin-parse-ansi - plain text extraction
;; ============================================================================
(let ((result (tintin-parse-ansi "hello world")))
  (assert-equal (car result) "hello world" "parse-ansi plain text unchanged")
  (assert-equal (cdr result) '() "parse-ansi no codes in plain text"))

;; ============================================================================
;; tintin-parse-ansi - strips ANSI, builds ansi-map
;; ============================================================================
(let ((result (tintin-parse-ansi "\033[31mhello\033[0m")))
  (assert-equal (car result) "hello" "parse-ansi extracts plain text from ANSI")
  (assert-equal (length (cdr result)) 2 "parse-ansi two entries in ansi-map")
  ;; First entry: color code at position 0
  (assert-equal (car (car (cdr result))) 0
   "parse-ansi first code at position 0")
  (assert-equal (cdr (car (cdr result))) "\033[31m"
   "parse-ansi first code is red")
  ;; Second entry: reset at position 5 (after "hello")
  (assert-equal (car (cadr (cdr result))) 5
   "parse-ansi reset at position 5")
  (assert-equal (cdr (cadr (cdr result))) "\033[0m"
   "parse-ansi second code is reset"))

;; ============================================================================
;; tintin-find-all-regex-positions
;; ============================================================================
(let ((positions (tintin-find-all-regex-positions "hello world hello" "hello")))
  (assert-equal (length positions) 2
   "find-all-regex-positions finds two matches")
  (assert-equal (car (car positions)) 0
   "find-all-regex-positions first match at 0")
  (assert-equal (cdr (car positions)) 5
   "find-all-regex-positions first match ends at 5")
  (assert-equal (car (cadr positions)) 12
   "find-all-regex-positions second match at 12")
  (assert-equal (cdr (cadr positions)) 17
   "find-all-regex-positions second match ends at 17"))

(let ((positions (tintin-find-all-regex-positions "no match here" "xyz")))
  (assert-equal positions '() "find-all-regex-positions no match returns empty"))

;; ============================================================================
;; tintin-highlight-line - end-to-end with registered highlights
;; ============================================================================
;; Register a highlight: pattern -> (fg bg priority)
(hash-set! *tintin-highlights* "orc" '("red" nil 5))
(set! *tintin-highlights-dirty* #t)

(let ((result (tintin-highlight-line "an orc appears")))
  ;; Should contain ANSI red around "orc"
  (assert-true (string-contains? result "\033[31m")
   "highlight-line contains red ANSI code")
  (assert-true (string-contains? result "orc")
   "highlight-line still contains the word orc"))

;; Clean up
(hash-remove! *tintin-highlights* "orc")
(set! *tintin-highlights-dirty* #t)

;; ============================================================================
;; tintin-highlight-line - no highlights returns original
;; ============================================================================
(let ((line "nothing to highlight"))
  (assert-equal (tintin-highlight-line line) line
   "highlight-line no highlights returns original"))

;; ============================================================================
;; tintin-apply-highlights - multi-line processing
;; ============================================================================
(hash-set! *tintin-highlights* "goblin" '("green" nil 5))
(set! *tintin-highlights-dirty* #t)

(let ((result (tintin-apply-highlights "a goblin\na goblin\n")))
  ;; Should have green ANSI on both lines
  (assert-true (string-contains? result "\033[32m")
   "apply-highlights contains green ANSI"))

;; Clean up
(hash-remove! *tintin-highlights* "goblin")
(set! *tintin-highlights-dirty* #t)

;; ============================================================================
;; Overlapping highlights: "is" inside "this is a line"
;; ============================================================================
(hash-set! *tintin-highlights* "is" '("red" nil 5))
(hash-set! *tintin-highlights* "this is" '("blue" nil 10))
(set! *tintin-highlights-dirty* #t)

(let ((result (tintin-highlight-line "this is a line")))
  ;; Higher-priority "this is" (blue=34) should win over "is" (red=31)
  (assert-true (string-contains? result "\033[34m")
   "overlapping highlights higher priority wins"))

;; Clean up
(hash-remove! *tintin-highlights* "is")
(hash-remove! *tintin-highlights* "this is")
(set! *tintin-highlights-dirty* #t)

;; ============================================================================
;; Server ANSI preservation
;; ============================================================================
(hash-set! *tintin-highlights* "world" '("green" nil 5))
(set! *tintin-highlights-dirty* #t)

(let ((result (tintin-highlight-line "\033[31mhello\033[0m world")))
  ;; Should still contain the green highlight for "world"
  (assert-true (string-contains? result "\033[32m")
   "server-ansi preservation green highlight applied")
  ;; Should contain the original server codes
  (assert-true (string-contains? result "\033[31m")
   "server-ansi preservation original red preserved"))

;; Clean up
(hash-remove! *tintin-highlights* "world")
(set! *tintin-highlights-dirty* #t)
