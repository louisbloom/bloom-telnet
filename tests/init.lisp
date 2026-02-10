;; tests/init.lisp - Tests for init.lisp helper functions
;; Tests visual-length, pad-string, repeat-string, and completion word store.
(load "tests/test-helpers.lisp")

;; ============================================================================
;; Mock builtins required by init.lisp
;; ============================================================================
;; termcap is provided by test-helpers.lisp
(defvar *version* "1.0.0-test")

;; ============================================================================
;; Load init.lisp (this verifies it parses correctly)
;; ============================================================================
(load "lisp/init.lisp")

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

;; ============================================================================
;; Test: trim-punctuation
;; ============================================================================
(assert-equal (trim-punctuation "hello") "hello"
 "trim-punctuation no-op on clean word")
(assert-equal (trim-punctuation "hello!") "hello"
 "trim-punctuation strips trailing !")
(assert-equal (trim-punctuation "\"hello\"") "hello"
 "trim-punctuation strips surrounding quotes")
(assert-equal (trim-punctuation "(hello)") "hello"
 "trim-punctuation strips surrounding parens")
(assert-equal (trim-punctuation "...") ""
 "trim-punctuation on all-punctuation returns empty")
(assert-equal (trim-punctuation "") "" "trim-punctuation on empty string")
(assert-equal (trim-punctuation nil) "" "trim-punctuation on nil")

;; ============================================================================
;; Test: extract-words
;; ============================================================================
(assert-equal (extract-words "hello world") '("hello" "world")
 "extract-words splits on whitespace")
(assert-equal (extract-words "hello, world!") '("hello" "world")
 "extract-words trims punctuation from words")
(assert-equal (extract-words "") '() "extract-words on empty string")
(assert-equal (extract-words nil) '() "extract-words on nil")

;; ============================================================================
;; Test: obj-to-string
;; ============================================================================
(assert-equal (obj-to-string 'foo) "foo" "obj-to-string symbol")
(assert-equal (obj-to-string "bar") "bar" "obj-to-string string")
(assert-equal (obj-to-string #t) "#t" "obj-to-string true")
(assert-equal (obj-to-string #f) "#f" "obj-to-string false")
(assert-equal (obj-to-string 42) "42" "obj-to-string number")

;; ============================================================================
;; Test: build-indent
;; ============================================================================
(assert-equal (build-indent 0) "" "build-indent level 0")
(assert-equal (build-indent 1) "  " "build-indent level 1")
(assert-equal (build-indent 3) "      " "build-indent level 3")

;; ============================================================================
;; Test: completion word store
;; ============================================================================

;; Helper to reset trie store for testing
(defun reset-completion-store (capacity)
  (set! *completion-trie* (make-hash-table))
  (set! *completion-seq* 0)
  (set! *completion-word-store-size* capacity)
  (set! *completion-word-order* (make-vector capacity nil))
  (set! *completion-word-order-index* 0)
  (set! *completion-word-count* 0))

;; Reset store for testing
(reset-completion-store 10)

;; Basic insertion
(add-word-to-store "hello")
(add-word-to-store "world")
(let ((leaf (trie-lookup *completion-trie* "hello")))
  (assert-true (not (null? leaf)) "hello present in trie")
  (assert-equal (list-ref leaf 2) 0 "hello stored at slot 0"))
(let ((leaf (trie-lookup *completion-trie* "world")))
  (assert-equal (list-ref leaf 2) 1 "world stored at slot 1"))

;; Duplicate moves to front (most recent position)
(add-word-to-store "hello")
(let ((leaf (trie-lookup *completion-trie* "hello")))
  (assert-equal (list-ref leaf 2) 2 "duplicate hello moved to slot 2"))
(assert-equal (vector-ref *completion-word-order* 0) nil
 "old slot cleared to nil after move")

;; Completions return newest first
(reset-completion-store 10)
(add-word-to-store "apple")
(add-word-to-store "avocado")
(add-word-to-store "apricot")
(let ((results (get-completions-from-store "a")))
  (assert-equal (car results) "apricot" "newest word first in results")
  (assert-equal (car (cdr results)) "avocado" "second newest next")
  (assert-equal (car (cdr (cdr results))) "apple" "oldest word last"))

;; Duplicate refreshes recency
(add-word-to-store "apple")
(let ((results (get-completions-from-store "a")))
  (assert-equal (car results) "apple"
   "duplicate apple is now newest after re-add"))

;; Short words rejected
(assert-equal (add-word-to-store "ab") 0 "2-char word rejected")
(assert-equal (add-word-to-store "hi") 0 "2-char word rejected")

;; FIFO eviction with full buffer
(reset-completion-store 5)
(add-word-to-store "aaa")
(add-word-to-store "bbb")
(add-word-to-store "ccc")
(add-word-to-store "ddd")
(add-word-to-store "eee")
;; Buffer is full, next insert evicts "aaa" at slot 0
(add-word-to-store "fff")
(assert-true (null? (trie-lookup *completion-trie* "aaa"))
 "aaa evicted after buffer wraps")
(let ((leaf (trie-lookup *completion-trie* "fff")))
  (assert-equal (list-ref leaf 2) 0 "fff occupies slot 0 after wrap"))

;; Word count tracking
(reset-completion-store 10)
(add-word-to-store "aaa")
(add-word-to-store "bbb")
(add-word-to-store "ccc")
(assert-equal *completion-word-count* 3 "count tracks new insertions")
(add-word-to-store "aaa")
(assert-equal *completion-word-count* 3 "count unchanged on duplicate")
;; With eviction in a small buffer
(reset-completion-store 3)
(add-word-to-store "aaa")
(add-word-to-store "bbb")
(add-word-to-store "ccc")
(assert-equal *completion-word-count* 3 "count at capacity")
(add-word-to-store "ddd")
(assert-equal *completion-word-count* 3 "count stays at capacity after eviction")
;; Trie lookup is fast regardless of buffer size
(reset-completion-store 50000)
(add-word-to-store "alpha")
(add-word-to-store "bravo")
(assert-equal *completion-word-count* 2 "only 2 words in 50K buffer")
(let ((results (get-completions-from-store "xyz")))
  (assert-equal results '() "no-match returns empty instantly via trie"))
(let ((results (get-completions-from-store "alp")))
  (assert-equal (length results) 1 "finds word in sparse buffer")
  (assert-equal (car results) "alpha" "correct word from sparse buffer"))

;; Vector entries are lowercase strings (buffer slot stores lowercase key)
(reset-completion-store 10)
(add-word-to-store "Hello")
(let ((entry (vector-ref *completion-word-order* 0)))
  (assert-true (string? entry) "vector entry is a string")
  (assert-equal entry "hello" "vector entry is lowercase key"))

;; Trie leaf contains original case
(let ((leaf (trie-lookup *completion-trie* "hello")))
  (assert-true (not (null? leaf)) "trie has entry for lowercase key")
  (assert-equal (car leaf) "Hello" "trie leaf stores original case"))

;; Case-insensitive matching returns original case
(add-word-to-store "World")
(add-word-to-store "APPLE")
(let ((results (get-completions-from-store "w")))
  (assert-equal (length results) 1 "one match for 'w'")
  (assert-equal (car results) "World"
   "lowercase prefix returns original-case word"))
(let ((results (get-completions-from-store "W")))
  (assert-equal (length results) 1 "one match for 'W'")
  (assert-equal (car results) "World"
   "uppercase prefix returns original-case word"))
(let ((results (get-completions-from-store "app")))
  (assert-equal (car results) "APPLE"
   "lowercase prefix matches all-caps word"))

;; Mixed-case duplicate detection (same lowercase key)
(reset-completion-store 10)
(add-word-to-store "Hello")
(add-word-to-store "hello")
(let ((leaf (trie-lookup *completion-trie* "hello")))
  (assert-equal (list-ref leaf 2) 1
   "second insert of same-lowercase word takes new slot"))
(assert-equal (vector-ref *completion-word-order* 0) nil
 "first slot cleared when same-lowercase duplicate inserted")
(let ((results (get-completions-from-store "hel")))
  (assert-equal (length results) 1 "only one entry for case-variant duplicates")
  (assert-equal (car results) "hello"
   "latest case variant is the one returned"))

;; Re-insert with different case updates stored word
(add-word-to-store "HELLO")
(let ((results (get-completions-from-store "hel")))
  (assert-equal (length results) 1 "still one entry after case-variant re-add")
  (assert-equal (car results) "HELLO"
   "re-add with different case updates stored word"))

;; get-completions-from-store edge cases
(assert-equal (get-completions-from-store "") '()
 "empty prefix returns empty list")
(assert-equal (get-completions-from-store nil) '()
 "nil prefix returns empty list")
(reset-completion-store 10)
(assert-equal (get-completions-from-store "xyz") '()
 "no matches in empty store returns empty list")

;; No matches in populated store returns empty
(add-word-to-store "alpha")
(add-word-to-store "beta")
(assert-equal (get-completions-from-store "xyz") '()
 "no matches in populated store returns empty list")

;; max-results limits results
(reset-completion-store 10)
(set! *completion-max-results* 2)
(add-word-to-store "aaa")
(add-word-to-store "aab")
(add-word-to-store "aac")
(add-word-to-store "aad")
(let ((results (get-completions-from-store "aa")))
  (assert-equal (length results) 2
   "max-results limits number of completions returned")
  (assert-equal (car results) "aad" "most recent result first with limit")
  (assert-equal (car (cdr results)) "aac" "second most recent with limit"))
(set! *completion-max-results* 20)

;; collect-words-from-text integration
(reset-completion-store 10)
(collect-words-from-text "The quick Brown fox")
(let ((results (get-completions-from-store "bro")))
  (assert-equal (length results) 1 "collect-words-from-text adds words")
  (assert-equal (car results) "Brown"
   "collect-words-from-text preserves original case"))
(let ((results (get-completions-from-store "qui")))
  (assert-equal (car results) "quick" "multi-word text all searchable"))
;; Short words from text are filtered
(collect-words-from-text "I am ok")
(assert-equal (get-completions-from-store "am") '()
 "collect-words-from-text skips short words")
;; nil and empty text
(collect-words-from-text nil)
(collect-words-from-text "")

;; FIFO eviction removes word from trie
(reset-completion-store 3)
(add-word-to-store "Alpha")
(add-word-to-store "Beta")
(add-word-to-store "Gamma")
(add-word-to-store "Delta")
(assert-true (null? (trie-lookup *completion-trie* "alpha"))
 "evicted word removed from trie")
(let ((leaf (trie-lookup *completion-trie* "delta")))
  (assert-equal (list-ref leaf 2) 0 "new word takes evicted slot"))
(assert-equal (get-completions-from-store "alp") '()
 "evicted word not found in completions")

;; Trie node pruning: empty nodes are cleaned up on removal
(reset-completion-store 10)
(add-word-to-store "cat")
(add-word-to-store "car")
(trie-remove! *completion-trie* "cat")
;; "c" -> "a" path should still exist for "car"
(assert-true (not (null? (trie-lookup *completion-trie* "car")))
 "car still in trie after removing cat")
(assert-true (null? (trie-lookup *completion-trie* "cat"))
 "cat removed from trie")
;; Remove car too — now trie should be empty
(trie-remove! *completion-trie* "car")
(assert-equal (length (hash-keys *completion-trie*)) 0
 "trie is empty after removing all words")

;; Restore defaults
(set! *completion-word-store-size* 50000)
(set! *completion-max-results* 20)

(print "All init.lisp tests passed!")
