;; tests/bench-completion.lisp - Benchmark tab completion performance
(load "tests/test-helpers.lisp")
(defvar *version* "1.0.0-test")
(load "lisp/init.lisp")

;; Helper to reset store at a given capacity
(defun reset-store (capacity)
  (set! *completion-trie* (make-hash-table))
  (set! *completion-seq* 0)
  (set! *completion-word-order* (make-vector capacity nil))
  (set! *completion-word-store-size* capacity)
  (set! *completion-word-order-index* 0)
  (set! *completion-word-count* 0))

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
