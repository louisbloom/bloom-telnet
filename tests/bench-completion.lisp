;; tests/bench-completion.lisp - Benchmark tab completion performance
(load "tests/test-helpers.lisp")
(load "lisp/init.lisp")

;; Alias for convenience
(defun reset-store (capacity) (reset-completion-store capacity))

;; Helper to fill store with N words using a prefix
(defun fill-store (n prefix)
  (do ((i 0 (+ i 1)))
    ((>= i n))
    (add-word-to-store (string-append prefix (number->string i)))))

;; Helper to bench a completion search
(defun bench (label prefix iterations)
  (let ((t0 (current-time-ms)))
    (do ((i 0 (+ i 1)))
      ((>= i iterations))
      (get-completions-from-store prefix))
    (let ((elapsed (- (current-time-ms) t0)))
      (print (string-append label ": " (number->string elapsed) " ms ("
              (number->string (/ elapsed iterations)) " ms/call)")))))

;; === Full buffer (50K words in 50K slots) ===
(print "--- Full buffer: 50K words in 50K slots ---")
(reset-store 50000)
(let ((t0 (current-time-ms)))
  (fill-store 50000 "word")
  (let ((elapsed (- (current-time-ms) t0)))
    (print (string-append "Fill: " (number->string elapsed) " ms"))))
(print (string-append "word-count: " (number->string *completion-word-count*)))

(bench "match-all 'word'" "word" 10)
(bench "match-few 'word49'" "word49" 10)
(bench "match-none 'zzz'" "zzz" 10)

;; === Sparse buffer (100 words in 50K slots) ===
(print "--- Sparse buffer: 100 words in 50K slots ---")
(reset-store 50000)
(fill-store 100 "word")
(print (string-append "word-count: " (number->string *completion-word-count*)))

(bench "match-all 'word'" "word" 100)
(bench "match-none 'zzz'" "zzz" 100)

;; === Typical MUD session (~2000 words) ===
(print "--- Typical session: 2000 words in 50K slots ---")
(reset-store 50000)
(fill-store 2000 "word")
(print (string-append "word-count: " (number->string *completion-word-count*)))

(bench "match-all 'word'" "word" 10)
(bench "match-none 'zzz'" "zzz" 10)

;; === Case variants: 3 case forms per word ===
;; Helper to fill store with N words, each having 3 case variants
(defun fill-store-with-variants (n prefix)
  (do ((i 0 (+ i 1))) ((>= i n))
    (let ((base (string-append prefix (number->string i))))
      (add-word-to-store base)
      (add-word-to-store (string-append (string-upcase (substring base 0 1))
                          (substring base 1 (length base))))
      (add-word-to-store (string-upcase base)))))

(print "--- Case variants: 2000 words x 3 cases in 50K slots ---")
(reset-store 50000)
(let ((t0 (current-time-ms)))
  (fill-store-with-variants 2000 "word")
  (let ((elapsed (- (current-time-ms) t0)))
    (print (string-append "Fill (with variants): " (number->string elapsed) " ms"))))
(print (string-append "word-count: " (number->string *completion-word-count*)))

(bench "case-variant match-all 'word'" "word" 10)
(bench "case-variant match-all 'Word'" "Word" 10)
(bench "case-variant match-all 'WORD'" "WORD" 10)
(bench "case-variant match-few 'word19'" "word19" 10)
(bench "case-variant match-none 'zzz'" "zzz" 10)

;; === Case variant insertion benchmark ===
(print "--- Case variant insertion: add-word-to-store x3 variants ---")
(reset-store 50000)
(let ((t0 (current-time-ms)))
  (do ((i 0 (+ i 1))) ((>= i 1000))
    (add-word-to-store "testword")
    (add-word-to-store "Testword")
    (add-word-to-store "TESTWORD"))
  (let ((elapsed (- (current-time-ms) t0)))
    (print (string-append "3000 inserts (3 variants, heavy duplicates): "
            (number->string elapsed) " ms"))))
