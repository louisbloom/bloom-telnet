;; tests/test-case-completion.lisp - Tests for case-preserving tab completion
;;
;; Words with different case are stored as separate entries.
;; Lookup is case-insensitive but prioritizes case-exact prefix matches.
(load "tests/test-helpers.lisp")
(load "lisp/init.lisp")

;; ============================================================================
;; 1. Separate storage: each case variant is a distinct entry
;; ============================================================================
(reset-completion-store 50000)
(add-word-to-store "foobar")
(add-word-to-store "Foobar")
(add-word-to-store "FooBar")

(assert-equal *completion-word-count* 3 "three case variants stored separately")
(assert-true (hash-ref *completion-words* "foobar") "foobar in hash by original key")
(assert-true (hash-ref *completion-words* "Foobar") "Foobar in hash by original key")
(assert-true (hash-ref *completion-words* "FooBar") "FooBar in hash by original key")
(assert-false (hash-ref *completion-words* "FOOBAR") "FOOBAR not in hash (never added)")

;; ============================================================================
;; 2. Case-insensitive lookup: all variants found regardless of prefix case
;; ============================================================================
(let ((results (get-completions-from-store "f")))
  (assert-equal (length results) 3 "f<tab> finds all 3 variants")
  (assert-true (member? "foobar" results) "f<tab> finds foobar")
  (assert-true (member? "Foobar" results) "f<tab> finds Foobar")
  (assert-true (member? "FooBar" results) "f<tab> finds FooBar"))

(let ((results (get-completions-from-store "F")))
  (assert-equal (length results) 3 "F<tab> finds all 3 variants")
  (assert-true (member? "foobar" results) "F<tab> finds foobar")
  (assert-true (member? "Foobar" results) "F<tab> finds Foobar")
  (assert-true (member? "FooBar" results) "F<tab> finds FooBar"))

(let ((results (get-completions-from-store "foo")))
  (assert-equal (length results) 3 "foo<tab> finds all 3 variants"))

(let ((results (get-completions-from-store "FOO")))
  (assert-equal (length results) 3 "FOO<tab> finds all 3 variants"))

;; ============================================================================
;; 3. Case-match priority: uppercase prefix "F" prioritizes F-variants
;; ============================================================================
(reset-completion-store 50000)
;; Add in specific order: foobar(seq1), Foobar(seq2), FooBar(seq3)
(add-word-to-store "foobar")
(add-word-to-store "Foobar")
(add-word-to-store "FooBar")

(let ((results (get-completions-from-store "F")))
  ;; F-prefixed words (FooBar, Foobar) should come first, most recent first
  (assert-equal (car results) "FooBar"
   "F<tab> first result is FooBar (most recent F-match)")
  (assert-equal (list-ref results 1) "Foobar"
   "F<tab> second result is Foobar (older F-match)")
  (assert-equal (list-ref results 2) "foobar"
   "F<tab> third result is foobar (non-match, deprioritized)"))

;; ============================================================================
;; 4. Case-match priority: lowercase prefix "f" prioritizes f-variant
;; ============================================================================
(let ((results (get-completions-from-store "f")))
  (assert-equal (car results) "foobar"
   "f<tab> first result is foobar (case-matched)")
  ;; Non-matched variants follow in recency order
  (assert-equal (list-ref results 1) "FooBar"
   "f<tab> second result is FooBar (most recent non-match)")
  (assert-equal (list-ref results 2) "Foobar"
   "f<tab> third result is Foobar (older non-match)"))

;; ============================================================================
;; 5. Recency within priority groups
;; ============================================================================
(reset-completion-store 50000)
(add-word-to-store "Alpha")
(add-word-to-store "Apex")
(add-word-to-store "apple")
(add-word-to-store "arrow")

(let ((results (get-completions-from-store "a")))
  ;; lowercase "a" matches "apple" and "arrow" — most recent first
  (assert-equal (car results) "arrow"
   "a<tab> first is arrow (most recent a-match)")
  (assert-equal (list-ref results 1) "apple"
   "a<tab> second is apple (older a-match)")
  ;; Then non-matches (A-prefix) in recency order
  (assert-equal (list-ref results 2) "Apex"
   "a<tab> third is Apex (most recent non-match)")
  (assert-equal (list-ref results 3) "Alpha"
   "a<tab> fourth is Alpha (oldest non-match)"))

(let ((results (get-completions-from-store "A")))
  ;; uppercase "A" matches "Alpha" and "Apex" — most recent first
  (assert-equal (car results) "Apex"
   "A<tab> first is Apex (most recent A-match)")
  (assert-equal (list-ref results 1) "Alpha"
   "A<tab> second is Alpha (older A-match)")
  ;; Then non-matches (a-prefix) in recency order
  (assert-equal (list-ref results 2) "arrow"
   "A<tab> third is arrow (most recent non-match)")
  (assert-equal (list-ref results 3) "apple"
   "A<tab> fourth is apple (oldest non-match)"))

;; ============================================================================
;; 6. Duplicate update preserves other variants
;; ============================================================================
(reset-completion-store 50000)
(add-word-to-store "foobar")
(add-word-to-store "Foobar")
(add-word-to-store "FooBar")
;; Re-add foobar — should update recency, not affect Foobar/FooBar
(add-word-to-store "foobar")

(assert-equal *completion-word-count* 3 "still 3 entries after duplicate")
(let ((results (get-completions-from-store "f")))
  (assert-equal (length results) 3 "still 3 results after duplicate")
  ;; foobar is now most recent AND case-matched with "f"
  (assert-equal (car results) "foobar"
   "f<tab> first is foobar (re-added, most recent + case-matched)")
  (assert-true (member? "Foobar" results) "Foobar still present")
  (assert-true (member? "FooBar" results) "FooBar still present"))

;; ============================================================================
;; 7. Eviction removes only the targeted variant
;; ============================================================================
(reset-completion-store 5)
;; Fill 3 of 5 slots with case variants
(add-word-to-store "hello")   ;; slot 0
(add-word-to-store "Hello")   ;; slot 1
(add-word-to-store "HELLO")   ;; slot 2
;; Fill remaining slots to trigger eviction of slot 0 (hello)
(add-word-to-store "world")   ;; slot 3
(add-word-to-store "other")   ;; slot 4
(add-word-to-store "extra")   ;; slot 0 — evicts "hello"

(assert-false (hash-ref *completion-words* "hello") "hello evicted from hash")
(assert-true (hash-ref *completion-words* "Hello") "Hello survives eviction")
(assert-true (hash-ref *completion-words* "HELLO") "HELLO survives eviction")

(let ((results (get-completions-from-store "h")))
  (assert-false (member? "hello" results) "hello not in results after eviction")
  (assert-true (member? "Hello" results) "Hello in results after eviction")
  (assert-true (member? "HELLO" results) "HELLO in results after eviction"))

;; ============================================================================
;; 8. collect-words-from-text preserves case variants
;; ============================================================================
(reset-completion-store 50000)
(collect-words-from-text "Hello hello HELLO world")

(let ((results (get-completions-from-store "h")))
  (assert-equal (length results) 3 "Hello/hello/HELLO all stored separately")
  (assert-true (member? "Hello" results) "Hello preserved from text")
  (assert-true (member? "hello" results) "hello preserved from text")
  (assert-true (member? "HELLO" results) "HELLO preserved from text"))

;; ============================================================================
;; 9. Multi-character prefix matching: only exact case prefix matches prioritized
;; ============================================================================
(reset-completion-store 50000)
(add-word-to-store "FooBar")
(add-word-to-store "Foobar")
(add-word-to-store "foobar")
(add-word-to-store "FOOBAR")

;; Prefix "Fo" matches "FooBar" and "Foobar" exactly
(let ((results (get-completions-from-store "Fo")))
  (assert-equal (length results) 4 "Fo<tab> finds all 4")
  ;; "Fo" prefix matches "FooBar" and "Foobar" (both start with "Fo")
  ;; "foobar" and "FOOBAR" don't match "Fo" case-exactly
  (let ((first-two (list (car results) (list-ref results 1))))
    (assert-true (member? "FooBar" first-two) "FooBar in top 2 for Fo<tab>")
    (assert-true (member? "Foobar" first-two) "Foobar in top 2 for Fo<tab>")))

;; Prefix "fo" matches only "foobar"
(let ((results (get-completions-from-store "fo")))
  (assert-equal (car results) "foobar" "fo<tab> first is foobar (exact match)"))

;; Prefix "FO" matches only "FOOBAR"
(let ((results (get-completions-from-store "FO")))
  (assert-equal (car results) "FOOBAR" "FO<tab> first is FOOBAR (exact match)"))

;; ============================================================================
;; 10. Regression: single-case words work correctly
;; ============================================================================
(reset-completion-store 50000)
(add-word-to-store "alpha")
(add-word-to-store "beta")
(add-word-to-store "gamma")

(assert-equal *completion-word-count* 3 "3 single-case words stored")
(let ((results (get-completions-from-store "a")))
  (assert-equal (length results) 1 "a<tab> finds 1 result")
  (assert-equal (car results) "alpha" "a<tab> finds alpha"))

(let ((results (get-completions-from-store "b")))
  (assert-equal (car results) "beta" "b<tab> finds beta"))

;; Duplicate update works
(add-word-to-store "alpha")
(assert-equal *completion-word-count* 3 "still 3 after duplicate alpha")
(let ((results (get-completions-from-store "a")))
  (assert-equal (length results) 1 "still 1 result for a<tab>")
  (assert-equal (car results) "alpha" "alpha still found"))

;; ============================================================================
;; 11. Completion hook entry point works with case prioritization
;; ============================================================================
(reset-completion-store 50000)
(add-word-to-store "test")
(add-word-to-store "Test")
(add-word-to-store "TEST")

(let ((results (completion-hook "t")))
  (assert-equal (length results) 3 "completion-hook finds all 3 variants")
  (assert-equal (car results) "test" "completion-hook t: first is test (case-matched)"))

(let ((results (completion-hook "T")))
  (assert-equal (length results) 3 "completion-hook T finds all 3 variants")
  ;; TEST and Test both start with T, most recent first
  (assert-equal (car results) "TEST" "completion-hook T: first is TEST (most recent T-match)")
  (assert-equal (list-ref results 1) "Test" "completion-hook T: second is Test")
  (assert-equal (list-ref results 2) "test" "completion-hook T: third is test (deprioritized)"))

;; ============================================================================
;; 12. Trie structure integrity: all entries are proper lists
;; ============================================================================
(reset-completion-store 50000)
(add-word-to-store "abc")
(add-word-to-store "Abc")
(add-word-to-store "ABC")
(add-word-to-store "abd")

(let* ((a-node (trie-walk-to *completion-trie* "a"))
       (entries (trie-collect a-node)))
  (assert-equal (length entries) 4 "4 entries under prefix 'a'")
  (do ((remaining entries (cdr remaining))) ((null? remaining))
    (let ((entry (car remaining)))
      (assert-true (pair? entry) "each entry is a proper list")
      (assert-true (string? (car entry)) "entry word is a string")
      (assert-true (number? (list-ref entry 1)) "entry seq is a number")
      (assert-true (number? (list-ref entry 2)) "entry slot is a number"))))

(print "All case-completion tests passed!")
