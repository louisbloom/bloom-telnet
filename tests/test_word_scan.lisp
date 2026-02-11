(load "tests/test-helpers.lisp")

;; Word break characters and scanner (from init.lisp)
(define *word-break-chars* ".,;:!?()[]{}'\"-")

(defun word-break-char? (c)
  (or (char-whitespace? c)
      (string-index *word-break-chars* (char->string c))))

;; Standalone extract-words for testing (same logic as collect-words-from-text
;; but returns a list instead of calling add-word-to-store)
(defun extract-words (text)
  (if (not (string? text))
    '()
    (let ((port (open-input-string text))
          (src text)
          (word-start -1)
          (result '()))
      (do () ((port-eof? port))
        (let ((c (port-read-char port))
              (pos (- (port-position port) 1)))
          (if (word-break-char? c)
            (when (>= word-start 0)
              (when (>= (- pos word-start) 3)
                (set! result (cons (substring src word-start pos) result)))
              (set! word-start -1))
            (when (< word-start 0)
              (set! word-start pos)))))
      ;; Flush trailing word
      (when (>= word-start 0)
        (let ((end (port-position port)))
          (when (>= (- end word-start) 3)
            (set! result (cons (substring src word-start end) result)))))
      (reverse result))))

;; Test 1: Basic words
(assert-equal (extract-words "hello world") '("hello" "world") "basic words")
(print "Test 1 passed: basic words")

;; Test 2: Short words excluded
(assert-equal (extract-words "be to it") '() "2-char words excluded")
(print "Test 2 passed: short words excluded")

;; Test 3: Word followed by question mark with trailing space
(assert-equal (extract-words "mourned? ") '("mourned") "word with question mark and space")
(print "Test 3 passed: mourned?<space>")

;; Test 4: Word followed by question mark at end
(assert-equal (extract-words "mourned?") '("mourned") "word with question mark at end")
(print "Test 4 passed: mourned? at end")

;; Test 5: Carrion Fields prompt
(define cf-prompt "By what name do you wish to be mourned? ")
(define cf-words (extract-words cf-prompt))
(print cf-words)
(assert-true (not (null? cf-words)) "should find words")

(defun member? (item lst)
  (cond ((null? lst) #f)
        ((equal? (car lst) item) #t)
        (#t (member? item (cdr lst)))))

(assert-true (member? "mourned" cf-words) "mourned in results")
(assert-true (member? "what" cf-words) "what in results")
(assert-true (member? "name" cf-words) "name in results")
(assert-true (member? "wish" cf-words) "wish in results")
(assert-false (member? "By" cf-words) "By excluded (2 chars)")
(assert-false (member? "do" cf-words) "do excluded (2 chars)")
(assert-false (member? "be" cf-words) "be excluded (2 chars)")
(print "Test 5 passed: carrion fields prompt")

;; Test 6: Punctuation stripping
(assert-equal (extract-words "hello, world!") '("hello" "world") "punctuation stripped")
(print "Test 6 passed: punctuation stripped")

;; Test 7: Mixed content with ASCII art
(define art-text "<!X!!!!HMM$$$$W. The Carrion Fields")
(define art-words (extract-words art-text))
(print art-words)
(assert-true (member? "The" art-words) "The in results")
(assert-true (member? "Carrion" art-words) "Carrion in results")
(assert-true (member? "Fields" art-words) "Fields in results")
(print "Test 7 passed: ASCII art mixed text")

;; Test 8: Trailing word with no trailing delimiter
(assert-equal (extract-words "hello") '("hello") "single word no delimiter")
(print "Test 8 passed: single trailing word")

;; Test 9: Empty and nil inputs
(assert-equal (extract-words "") '() "empty string")
(assert-equal (extract-words nil) '() "nil input")
(print "Test 9 passed: empty/nil inputs")

;; Test 10: Tabs and newlines as delimiters
(assert-equal (extract-words "hello\tworld\nfoo") '("hello" "world" "foo") "tabs and newlines")
(print "Test 10 passed: tabs and newlines")

;; Test 11: Full welcome screen from carrionfields.net
(define full-text "                          ::x.\r\n                    <!X!!!!HMM$$$$W.\r\n               ---!H8MMH?M$$$$$$$$$8X.\r\n              -<!!!MMM$$$$$$$$$$$$$$$$X!:           The Carrion Fields\r\n            !----!!M?M$$$$$$$$$$$$$$$$MM!!<\r\n          '<M!  !!!MMM$$$$$$$$$$$$$$$MMMX!X!\r\n           !M!--!!!MMM$$$$$$$$$$$$$$$MMM!X$!    A Playerkilling/Roleplaying\r\n           -!8!:!!!MMMMM$$$$$$$$$$$$RMMMX8RX-               MUD\r\nBy what name do you wish to be mourned? ")
(define full-words (extract-words full-text))
(print full-words)
(assert-true (member? "mourned" full-words) "mourned in full text")
(assert-true (member? "Carrion" full-words) "Carrion in full text")
(assert-true (member? "Fields" full-words) "Fields in full text")
(assert-true (member? "Playerkilling/Roleplaying" full-words) "compound word preserved")
(print "Test 11 passed: full welcome screen")

(print "All word scan tests passed!")
