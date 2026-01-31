;; tests/tintin-patterns.lisp - Tests for pattern matching system
(load "tests/test-loader.lisp")

;; ============================================================================
;; tintin-pattern-to-regex - literal patterns
;; ============================================================================
(assert-equal (tintin-pattern-to-regex "hello") "hello"
 "pattern-to-regex literal")
(assert-equal (tintin-pattern-to-regex "Valgar") "Valgar"
 "pattern-to-regex literal name")

;; ============================================================================
;; tintin-pattern-to-regex - %* wildcard
;; ============================================================================
(assert-equal (tintin-pattern-to-regex "You hit %*") "You hit (.*)"
 "pattern-to-regex %* at end")
(assert-equal (tintin-pattern-to-regex "%* hits you") "(.*?) hits you"
 "pattern-to-regex %* not at end")

;; ============================================================================
;; tintin-pattern-to-regex - %N numbered wildcards
;; ============================================================================
(assert-equal (tintin-pattern-to-regex "kill %1 with %2")
 "kill (.*?) with (.*)" "pattern-to-regex %1 %2")

;; ============================================================================
;; tintin-pattern-to-regex - ^ anchor
;; ============================================================================
(assert-equal (tintin-pattern-to-regex "^Health: %1")
 "^Health: (.*)" "pattern-to-regex ^ anchor")

;; ============================================================================
;; tintin-pattern-to-regex - special char escaping
;; ============================================================================
(assert-equal (tintin-pattern-to-regex "price is $10.00")
 "price is \\$10\\.00" "pattern-to-regex special chars")
(assert-equal (tintin-pattern-to-regex "a.b") "a\\.b"
 "pattern-to-regex dot escaping")

;; ============================================================================
;; tintin-match-highlight-pattern
;; ============================================================================
(assert-true (tintin-match-highlight-pattern "hello" "say hello world")
 "match-highlight-pattern substring match")
(assert-true (tintin-match-highlight-pattern "You hit %*" "You hit the orc")
 "match-highlight-pattern with %*")
(assert-false
 (tintin-match-highlight-pattern "^Health" "Your Health is low")
 "match-highlight-pattern ^ anchor no match")
(assert-true (tintin-match-highlight-pattern "^Health" "Health: 100")
 "match-highlight-pattern ^ anchor match")

;; ============================================================================
;; tintin-sort-highlights-by-priority
;; ============================================================================
;; Input: list of (pattern fg bg priority) -- stored as flat list entries
(let ((sorted
       (tintin-sort-highlights-by-priority
        '(("low" "red" nil 1) ("high" "green" nil 10)
          ("mid" "blue" nil 5)))))
  (assert-equal (car (car sorted)) "high"
   "sort-highlights first is highest priority")
  (assert-equal (car (cadr sorted)) "mid"
   "sort-highlights second is mid priority")
  (assert-equal (car (caddr sorted)) "low"
   "sort-highlights third is lowest priority"))

;; Tiebreaker: shorter pattern first at same priority
(let ((sorted
       (tintin-sort-highlights-by-priority
        '(("longer" "red" nil 5) ("short" "blue" nil 5)))))
  (assert-equal (car (car sorted)) "short"
   "sort-highlights tiebreaker shorter first"))
