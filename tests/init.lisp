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

;; Reset store for testing
(set! *completion-word-store* (make-hash-table))
(set! *completion-word-store-size* 10)
(set! *completion-word-order* (make-vector 10 nil))
(set! *completion-word-order-index* 0)

;; Basic insertion
(add-word-to-store "hello")
(add-word-to-store "world")
(assert-equal (hash-ref *completion-word-store* "hello") 0
 "hello stored at slot 0")
(assert-equal (hash-ref *completion-word-store* "world") 1
 "world stored at slot 1")

;; Duplicate moves to front (most recent position)
(add-word-to-store "hello")
(assert-equal (hash-ref *completion-word-store* "hello") 2
 "duplicate hello moved to slot 2")
(assert-equal (vector-ref *completion-word-order* 0) nil
 "old slot cleared to nil after move")

;; Completions return newest first
(set! *completion-word-store* (make-hash-table))
(set! *completion-word-order* (make-vector 10 nil))
(set! *completion-word-order-index* 0)
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
(set! *completion-word-store* (make-hash-table))
(set! *completion-word-order* (make-vector 5 nil))
(set! *completion-word-store-size* 5)
(set! *completion-word-order-index* 0)
(add-word-to-store "aaa")
(add-word-to-store "bbb")
(add-word-to-store "ccc")
(add-word-to-store "ddd")
(add-word-to-store "eee")
;; Buffer is full, next insert evicts "aaa" at slot 0
(add-word-to-store "fff")
(assert-true (null? (hash-ref *completion-word-store* "aaa"))
 "aaa evicted after buffer wraps")
(assert-equal (hash-ref *completion-word-store* "fff") 0
 "fff occupies slot 0 after wrap")

;; Vector entries are cons pairs (lowercase . original)
(set! *completion-word-store* (make-hash-table))
(set! *completion-word-order* (make-vector 10 nil))
(set! *completion-word-order-index* 0)
(add-word-to-store "Hello")
(let ((entry (vector-ref *completion-word-order* 0)))
  (assert-true (pair? entry) "vector entry is a cons pair")
  (assert-equal (car entry) "hello" "vector entry car is lowercase key")
  (assert-equal (cdr entry) "Hello" "vector entry cdr is original case"))

;; Hash key is lowercase
(assert-equal (hash-ref *completion-word-store* "hello") 0
 "hash key is lowercase for mixed-case word")
(assert-true (null? (hash-ref *completion-word-store* "Hello"))
 "original case is not a hash key")

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
(set! *completion-word-store* (make-hash-table))
(set! *completion-word-order* (make-vector 10 nil))
(set! *completion-word-order-index* 0)
(add-word-to-store "Hello")
(add-word-to-store "hello")
(assert-equal (hash-ref *completion-word-store* "hello") 1
 "second insert of same-lowercase word takes new slot")
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
(set! *completion-word-store* (make-hash-table))
(set! *completion-word-order* (make-vector 10 nil))
(set! *completion-word-order-index* 0)
(assert-equal (get-completions-from-store "xyz") '()
 "no matches in empty store returns empty list")

;; No matches in populated store returns empty
(add-word-to-store "alpha")
(add-word-to-store "beta")
(assert-equal (get-completions-from-store "xyz") '()
 "no matches in populated store returns empty list")

;; max-results limits circular buffer results
(set! *completion-word-store* (make-hash-table))
(set! *completion-word-order* (make-vector 10 nil))
(set! *completion-word-order-index* 0)
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
(set! *completion-word-store* (make-hash-table))
(set! *completion-word-order* (make-vector 10 nil))
(set! *completion-word-order-index* 0)
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

;; FIFO eviction removes old cons pair from hash
(set! *completion-word-store* (make-hash-table))
(set! *completion-word-order* (make-vector 3 nil))
(set! *completion-word-store-size* 3)
(set! *completion-word-order-index* 0)
(add-word-to-store "Alpha")
(add-word-to-store "Beta")
(add-word-to-store "Gamma")
(add-word-to-store "Delta")
(assert-true (null? (hash-ref *completion-word-store* "alpha"))
 "evicted word's lowercase key removed from hash")
(assert-equal (hash-ref *completion-word-store* "delta") 0
 "new word takes evicted slot")
(assert-equal (get-completions-from-store "alp") '()
 "evicted word not found in completions")

;; Restore defaults
(set! *completion-word-store-size* 50000)
(set! *completion-max-results* 20)

(print "All init.lisp tests passed!")
