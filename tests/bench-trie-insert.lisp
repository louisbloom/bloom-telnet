;; tests/bench-trie-insert.lisp - Benchmark trie insertion with real MUD payloads
;; Uses clean text extracted from telnet log RECV payloads.
;; Run: ./tests/run-test.sh tests/bench-trie-insert.lisp
(load "tests/test-helpers.lisp")
(defvar *version* "1.0.0-test")
(load "lisp/init.lisp")

;; ============================================================================
;; File reading helper
;; ============================================================================
(defun read-all (path)
  "Read entire file contents as a single string."
  (let ((f (open path "r"))
        (acc ""))
    (do ((line (read-line f) (read-line f)))
      ((null? line) (close f) acc)
      (set! acc (string-append acc line "\n")))))

;; ============================================================================
;; Reset helper
;; ============================================================================
(defun reset-store (capacity)
  (set! *completion-trie* (cons nil (make-hash-table)))
  (set! *completion-words* (make-hash-table))
  (set! *completion-seq* 0)
  (set! *completion-word-order* (make-vector capacity nil))
  (set! *completion-word-store-size* capacity)
  (set! *completion-word-order-index* 0)
  (set! *completion-word-count* 0))

;; ============================================================================
;; Load payloads
;; ============================================================================
(print "Loading payloads from telnet logs...")

(define *payload-200* (read-all "tests/bench-data/clean-200.txt"))
(define *payload-500* (read-all "tests/bench-data/clean-500.txt"))
(define *payload-1k* (read-all "tests/bench-data/clean-1k.txt"))
(define *payload-2k* (read-all "tests/bench-data/clean-2k.txt"))

(print (string-append "  200-byte payload: " (number->string (length *payload-200*)) " chars"))
(print (string-append "  500-byte payload: " (number->string (length *payload-500*)) " chars"))
(print (string-append "   1k-byte payload: " (number->string (length *payload-1k*)) " chars"))
(print (string-append "   2k-byte payload: " (number->string (length *payload-2k*)) " chars"))

;; ============================================================================
;; Benchmark helper
;; ============================================================================
(defun bench (label iterations thunk)
  "Time a thunk over N iterations, print ms/call."
  (let ((t0 (current-time-ms)))
    (do ((i 0 (+ i 1))) ((>= i iterations))
      (thunk))
    (let ((elapsed (- (current-time-ms) t0)))
      (print (string-append "  " label ": "
              (number->string elapsed) " ms total, "
              (number->string (/ elapsed iterations)) " ms/call"
              " (" (number->string iterations) " iterations)")))))

;; ============================================================================
;; Benchmark: collect-words-from-text into empty store
;; ============================================================================
(print "")
(print "--- collect-words-from-text into empty store (per-call reset) ---")

(bench "200-byte payload" 1000
  (lambda ()
    (reset-store 50000)
    (collect-words-from-text *payload-200*)))

(bench "500-byte payload" 1000
  (lambda ()
    (reset-store 50000)
    (collect-words-from-text *payload-500*)))

(bench "1k-byte payload" 1000
  (lambda ()
    (reset-store 50000)
    (collect-words-from-text *payload-1k*)))

(bench "2k-byte payload" 500
  (lambda ()
    (reset-store 50000)
    (collect-words-from-text *payload-2k*)))

;; ============================================================================
;; Benchmark: collect-words-from-text into populated store (steady state)
;; ============================================================================
(print "")
(print "--- collect-words-from-text into populated store (2000 existing words) ---")

(defun fill-and-bench (label payload iterations)
  (reset-store 50000)
  ;; Pre-populate with 2000 words (typical MUD session)
  (do ((i 0 (+ i 1))) ((>= i 2000))
    (add-word-to-store (string-append "word" (number->string i))))
  (let ((pre-count *completion-word-count*))
    (bench label iterations (lambda () (collect-words-from-text payload)))
    (print (string-append "    word count: " (number->string pre-count)
            " -> " (number->string *completion-word-count*)))))

(fill-and-bench "200-byte payload" *payload-200* 1000)
(fill-and-bench "500-byte payload" *payload-500* 1000)
(fill-and-bench "1k-byte payload" *payload-1k* 1000)
(fill-and-bench "2k-byte payload" *payload-2k* 500)

;; ============================================================================
;; Benchmark: rapid-fire ingestion (simulate burst of server output)
;; ============================================================================
(print "")
(print "--- Burst ingestion: 100 consecutive 500-byte payloads ---")
(reset-store 50000)
(let ((t0 (current-time-ms)))
  (do ((i 0 (+ i 1))) ((>= i 100))
    (collect-words-from-text *payload-500*))
  (let ((elapsed (- (current-time-ms) t0)))
    (print (string-append "  100x 500-byte payloads: " (number->string elapsed) " ms"))
    (print (string-append "  word count: " (number->string *completion-word-count*)))))

(print "")
(print "--- Burst ingestion: 100 consecutive 2k-byte payloads ---")
(reset-store 50000)
(let ((t0 (current-time-ms)))
  (do ((i 0 (+ i 1))) ((>= i 100))
    (collect-words-from-text *payload-2k*))
  (let ((elapsed (- (current-time-ms) t0)))
    (print (string-append "  100x 2k-byte payloads: " (number->string elapsed) " ms"))
    (print (string-append "  word count: " (number->string *completion-word-count*)))))

(print "")
(print "Done.")
