;; Bootstrap Lisp file for bloom-telnet
;; This file is always loaded on startup before any user-provided Lisp file
;; All variables defined here can be overridden in your custom Lisp configuration file
;; ============================================================================
;; COMPLETION PATTERN CONFIGURATION
;; ============================================================================
(defvar *completion-pattern* "\\S+$"
  "PCRE2 regex pattern that matches the text to complete.")

;; ============================================================================
;; WORD STORE CONFIGURATION
;; ============================================================================
(defvar *completion-word-store-size* 10000
  "Maximum number of words to store for completions.")

(defvar *completion-max-results* 64
  "Maximum number of completion candidates to return per prefix.")

;; Initialize word store (hash table for fast lookups)
(define *completion-word-store* (make-hash-table))

;; Initialize word order (vector for FIFO bounded storage)
(define *completion-word-order* (make-vector *completion-word-store-size* nil))

;; Current position in the order vector (circular buffer index)
(define *completion-word-order-index* 0)

;; ============================================================================
;; TELNET I/O LOGGING CONFIGURATION
;; ============================================================================
(defvar *enable-telnet-logging* #t
  "Enable/disable telnet I/O logging (both send and receive).")

(defvar *telnet-log-directory* "~/telnet-logs"
  "Directory for telnet log files (supports ~/ expansion).")

;; ============================================================================
;; TCP KEEPALIVE CONFIGURATION
;; ============================================================================
(defvar *tcp-keepalive-enabled* #t
  "Enable TCP keepalive probes on telnet connections.")

(defvar *tcp-keepalive-time* 60
  "Seconds of idle time before sending the first keepalive probe.")

(defvar *tcp-keepalive-interval* 10
  "Seconds between keepalive probes after the first probe.")

;; ============================================================================
;; INPUT CONFIGURATION
;; ============================================================================
(defvar *input-history-size* 100
  "Maximum number of input history entries to keep.")

(defvar *prompt* "> " "Input prompt string.")

;; ============================================================================
;; WORD STORE HELPER FUNCTIONS
;; ============================================================================
(define *trim-punctuation-string* ".,!?;:()[]{}'\"-")

(defun punctuation-char? (c)
  "Check if character is punctuation to trim."
  (string-index *trim-punctuation-string* (char->string c)))

(defun trim-punctuation (word)
  "Remove leading and trailing punctuation from word."
  (if (not (and (string? word) (> (length word) 0)))
    ""
    (let ((len (length word)))
      (do ((start 0 (+ start 1)))
        ((or (>= start len) (not (punctuation-char? (string-ref word start))))
         (do ((end len (- end 1)))
           ((or (<= end start)
                (not (punctuation-char? (string-ref word (- end 1)))))
            (if (>= start end) "" (substring word start end)))))))))

(defun clean-word (word)
  "Clean a word by trimming punctuation."
  (if (and (string? word) (> (length word) 0)) (trim-punctuation word) ""))

(defun valid-word? (cleaned)
  "Check if a cleaned word is valid for storage."
  (and (string? cleaned) (> (length cleaned) 0)))

(defun filter-valid-words (words)
  (let ((filtered '()))
    (do ((remaining words (cdr remaining)))
      ((null? remaining) (reverse filtered))
      (let ((cleaned (clean-word (car remaining))))
        (if (not (valid-word? cleaned))
          ()
          (set! filtered (cons cleaned filtered)))))))

(defun extract-words (text)
  (if (not (string? text))
    '()
    (let ((words (regex-split "\\s+" text)))
      (if (null? words) '() (filter-valid-words words)))))

(defun normalize-order-index (idx vec-size) (if (>= idx vec-size) 0 idx))

(defun advance-order-index (vec-size)
  (set! *completion-word-order-index* (+ *completion-word-order-index* 1))
  (if (>= *completion-word-order-index* vec-size)
    (set! *completion-word-order-index* 0)))

(defun insert-word-into-slot! (vec store slot old-word new-word)
  (if (and (string? old-word) (string? new-word) (string=? old-word new-word))
    ()
    (progn
      (if (string? old-word)
        (let ((count (hash-ref store old-word)))
          (if (and count (> count 1))
            (hash-set! store old-word (- count 1))
            (hash-remove! store old-word))))
      (vector-set! vec slot new-word)
      (let ((count (hash-ref store new-word)))
        (hash-set! store new-word (if count (+ count 1) 1))))))

(defun word-valid-for-store? (word) (and (string? word) (>= (length word) 3)))

(defun add-word-to-store (word)
  "Add a word to the completion store with FIFO eviction."
  (if (not (word-valid-for-store? word))
    0
    (let* ((vec *completion-word-order*)
           (vec-size (length vec)))
      (if (>= *completion-word-order-index* vec-size)
        (set! *completion-word-order-index* 0))
      (let* ((slot
              (normalize-order-index *completion-word-order-index* vec-size))
             (old (vector-ref vec slot)))
        (insert-word-into-slot! vec *completion-word-store* slot old word)
        (advance-order-index vec-size)
        1))))

(defun collect-words-from-text (text)
  "Extract words from text and add them to completion store."
  (if (> (length text) 2000)
    ()
    (let ((words (extract-words text)))
      (if (null? words)
        ()
        (do ((remaining words (cdr remaining))) ((null? remaining))
          (add-word-to-store (car remaining)))))))

(defun compute-circular-index (pos vec-size)
  (if (< pos 0) (+ pos vec-size) pos))

(defun word-matches-prefix? (word prefix-lower seen)
  (and (string? word) (string-prefix? prefix-lower (string-downcase word))
       (null? (hash-ref seen word))))

(defun scan-circular-buffer
  (vec vec-size start prefix-lower seen max-results)
  (let ((acc '())
        (count 0))
    (do ((i 0 (+ i 1)))
      ((or (>= i vec-size) (>= count max-results)) (cons (reverse acc) count))
      (let* ((pos (- start 1 i))
             (idx (compute-circular-index pos vec-size))
             (k (vector-ref vec idx)))
        (if (not (string? k))
          ()
          (if (not (word-matches-prefix? k prefix-lower seen))
            ()
            (progn (hash-set! seen k 1) (set! acc (cons k acc))
              (set! count (+ count 1)))))))))

(defun scan-hash-keys (store prefix-lower seen acc count max-results)
  (let ((keys (hash-keys store)))
    (if (null? keys)
      acc
      (do ((remaining keys (cdr remaining)))
        ((or (null? remaining) (>= count max-results)) acc)
        (let ((k (car remaining)))
          (if (not (word-matches-prefix? k prefix-lower seen))
            ()
            (progn (hash-set! seen k 1) (set! acc (cons k acc))
              (set! count (+ count 1)))))))))

(defun get-completions-from-store (prefix)
  "Retrieve words from store matching a prefix (case-insensitive)."
  (if (not (and (string? prefix) (> (length prefix) 0)))
    '()
    (let* ((p (string-downcase prefix))
           (vec *completion-word-order*)
           (vec-size (length vec))
           (start *completion-word-order-index*)
           (seen (make-hash-table))
           (result
            (scan-circular-buffer vec vec-size start p seen
             *completion-max-results*))
           (acc (car result))
           (count (cdr result)))
      (if (> count 0)
        acc
        (scan-hash-keys *completion-word-store* p seen acc count
         *completion-max-results*)))))

;; ============================================================================
;; EXTENSIBLE HOOK SYSTEM
;; ============================================================================
(defun memq (item lst)
  "Return sublist starting at first eq? match, or nil if not found."
  (cond
    ((null? lst) nil)
    ((eq? item (car lst)) lst)
    (#t (memq item (cdr lst)))))

(defvar *hooks* '() "Global registry of hooks.")

(defun add-hook (hook-name fn-symbol &optional priority)
  "Add a function to a hook by symbol name with optional priority."
  (let ((prio (if priority priority 50)))
    (let ((entry (assoc hook-name *hooks*)))
      (if entry
        (unless
          (assoc fn-symbol
           (map (lambda (p) (cons (cdr p) (car p))) (cdr entry)))
          (let ((new-pair (cons prio fn-symbol))
                (inserted #f)
                (new-list '()))
            (do ((pairs (cdr entry) (cdr pairs))) ((null? pairs))
              (let ((cur (car pairs)))
                (when (and (not inserted) (< prio (car cur)))
                  (set! new-list (cons new-pair new-list))
                  (set! inserted #t))
                (set! new-list (cons cur new-list))))
            (unless inserted (set! new-list (cons new-pair new-list)))
            (set! *hooks*
             (map
              (lambda (e)
                (if (eq? (car e) hook-name)
                  (cons hook-name (reverse new-list))
                  e)) *hooks*))))
        (set! *hooks*
         (cons (cons hook-name (list (cons prio fn-symbol))) *hooks*)))))
  nil)

(defun remove-hook (hook-name fn-symbol)
  "Remove a function from a hook by symbol name."
  (let ((entry (assoc hook-name *hooks*)))
    (when entry
      (set! *hooks*
       (map
        (lambda (e)
          (if (eq? (car e) hook-name)
            (cons hook-name
             (filter (lambda (pair) (not (eq? (cdr pair) fn-symbol))) (cdr e)))
            e)) *hooks*))))
  nil)

(defun run-hook (hook-name &rest args)
  "Run all functions in a hook with given arguments."
  (let ((entry (assoc hook-name *hooks*)))
    (when entry
      (do ((pairs (cdr entry) (cdr pairs))) ((null? pairs))
        (apply (eval (cdar pairs)) args))))
  nil)

(defun run-filter-hook (hook-name initial-value)
  "Run all functions in a filter hook, chaining return values."
  (let ((entry (assoc hook-name *hooks*)))
    (if entry
      (do ((pairs (cdr entry) (cdr pairs)) (result initial-value))
        ((null? pairs) result)
        (set! result ((eval (cdar pairs)) result)))
      initial-value)))

;; ============================================================================
;; HOOK IMPLEMENTATIONS
;; ============================================================================
(defun telnet-input-hook (text)
  "Process telnet server output through registered hooks."
  (run-hook 'telnet-input-hook text)
  nil)

(defvar *user-input-handled* nil)

(defvar *user-input-result* nil)

(defun run-user-input-hooks (text cursor-pos)
  (let ((entry (assoc 'user-input-hook *hooks*)))
    (when entry
      (do ((pairs (cdr entry) (cdr pairs)))
        ((or (null? pairs) *user-input-handled*))
        ((eval (cdar pairs)) text cursor-pos)))))

(defun user-input-hook (text cursor-pos)
  "Transform user input before sending to telnet server."
  (set! *user-input-handled* nil)
  (set! *user-input-result* nil)
  (run-user-input-hooks text cursor-pos)
  (if *user-input-handled* *user-input-result* text))

;; ============================================================================
;; COMPLETION HOOK
;; ============================================================================
(defun completion-hook (text)
  "Provide tab completion candidates from word store."
  (if (and (string? text) (> (length text) 0))
    (get-completions-from-store text)
    '()))

;; ============================================================================
;; DEFAULT HOOKS
;; ============================================================================
(defun default-word-collector (text)
  "Default telnet-input-hook handler that collects words for tab completion."
  (collect-words-from-text text))

(add-hook 'telnet-input-hook 'default-word-collector)

;; ============================================================================
;; TELNET INPUT FILTER HOOK
;; ============================================================================
(defun telnet-input-filter-hook (text)
  "Transform telnet server output before displaying."
  (run-filter-hook 'telnet-input-filter-hook text))

;; ============================================================================
;; TIMER SYSTEM
;; ============================================================================
(defvar *timer-list* '() "List of active timers.")

(defvar *timer-next-id* 1 "Next timer ID to assign.")

(defun run-at-time (time repeat function &rest args)
  "Schedule FUNCTION to run after TIME seconds."
  (let* ((delay-ms (* time 1000))
         (repeat-ms (if repeat (* repeat 1000) 0))
         (fire-time (+ (current-time-ms) delay-ms))
         (id *timer-next-id*)
         (timer (list id fire-time repeat-ms function args)))
    (set! *timer-next-id* (+ *timer-next-id* 1))
    (set! *timer-list* (cons timer *timer-list*))
    timer))

(defun cancel-timer (timer)
  "Cancel TIMER."
  (let ((found #f))
    (set! *timer-list*
     (filter (lambda (t) (if (eq? t timer) (progn (set! found #t) #f) #t))
      *timer-list*))
    found))

(defun list-timers () "Return list of active timers." *timer-list*)

(defun run-timers ()
  "Run all due timers. Called automatically by main loop."
  (when (not (null? *timer-list*))
    (let ((now (current-time-ms))
          (to-process *timer-list*)
          (new-list '()))
      (set! *timer-list* '())
      (do ((remaining to-process (cdr remaining))) ((null? remaining))
        (let* ((timer (car remaining))
               (fire-time (list-ref timer 1))
               (repeat-ms (list-ref timer 2))
               (callback (list-ref timer 3))
               (args (list-ref timer 4)))
          (if (>= now fire-time)
            (progn (apply callback args)
              (when (> repeat-ms 0) (set-car! (cdr timer) (+ now repeat-ms))
                (set! new-list (cons timer new-list))))
            (set! new-list (cons timer new-list)))))
      (set! *timer-list* (append new-list *timer-list*)))))

;; ============================================================================
;; UTILITY FUNCTIONS
;; ============================================================================
(defun build-indent (level)
  (let ((result ""))
    (do ((i 0 (+ i 1))) ((>= i level) result)
      (set! result (concat result "  ")))))

(defun obj-to-string (obj)
  "Convert an object to its string representation."
  (cond
    ((symbol? obj) (symbol->string obj))
    ((string? obj) obj)
    ((eq? obj #t) "#t")
    ((eq? obj #f) "#f")
    (#t (format nil "~A" obj))))

(defconst *ansi-reset* "\033[0m"
  "ANSI escape sequence to reset all text attributes.")

(defun ansi-fg-rgb (r g b)
  "Generate ANSI true color foreground escape sequence."
  (concat "\033[38;2;" (number->string r) ";" (number->string g) ";"
   (number->string b) "m"))

;; ============================================================================
;; GUI COMPATIBILITY STUBS
;; ============================================================================
;; These functions provide no-op stubs for GUI features used by contrib scripts.
;; In the GUI version, divider-mode shows status icons in the divider line.
;; In TUI mode, we just ignore these calls silently.
(defun divider-mode-set (mode-symbol icon priority)
  "Stub: Set divider mode indicator (no-op in TUI)."
  nil)

(defun divider-mode-remove (mode-symbol)
  "Stub: Remove divider mode indicator (no-op in TUI)."
  nil)

(defun notify (message)
  "Display a notification message. In TUI, echoes to terminal."
  (terminal-echo (concat "\r\n" message "\r\n")))

