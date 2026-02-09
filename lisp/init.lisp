;; Bootstrap Lisp file for bloom-telnet
;; Loaded into base_env on startup after the TUI is initialized.
;; All variables defined here can be overridden in your custom Lisp configuration file.
;; ============================================================================
;; COMPLETION PATTERN CONFIGURATION
;; ============================================================================
(defvar *completion-pattern* "\\S+$"
  "PCRE2 regex pattern that matches the text to complete.")

;; ============================================================================
;; WORD STORE CONFIGURATION
;; ============================================================================
(defvar *completion-word-store-size* 50000
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
(defvar *input-history-size* 1000
  "Maximum number of input history entries to keep.")

(defvar *prompt* "❯ " "Input prompt string.")

;; ============================================================================
;; COLOR CONFIGURATION
;; ============================================================================
;; UI colors — each is an (R G B) list. Override in your config to customize.
(defvar *color-user-input* '(255 215 0)
  "Color for echoed user input. RGB list.")

(defvar *color-divider-connected* '(37 160 101)
  "Divider color when connected. RGB list.")

(defvar *color-divider-disconnected* '(88 88 88)
  "Divider color when disconnected. RGB list.")

(defvar *color-log-debug* '(128 128 128)
  "Color for debug log messages. RGB list.")

(defvar *color-log-info* '(128 128 128)
  "Color for info log messages. RGB list.")

(defvar *color-log-warn* '(255 200 0)
  "Color for warning log messages. RGB list.")

(defvar *color-log-error* '(255 80 80)
  "Color for error log messages. RGB list.")

(defvar *color-script-header* '(255 177 182)
  "Color for script-echo header text. RGB list.")

(defvar *color-script-desc* '(157 225 241)
  "Color for script-echo description text. RGB list.")

(defvar *color-script-section* '(189 147 249)
  "Color for script-echo section titles. RGB list.")

(defvar *color-script-detail* '(100 100 156)
  "Color for script-echo detail text. RGB list.")

(defvar *color-script-mdash* '(98 98 98)
  "Color for script-echo mdash separator. RGB list.")

(defun color->fg (rgb)
  "Convert an RGB list to a foreground ANSI escape sequence."
  (termcap 'fg-color (car rgb) (car (cdr rgb)) (car (cdr (cdr rgb)))))

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
  (if (string? old-word) (hash-remove! store old-word))
  (vector-set! vec slot new-word)
  (if (string? new-word) (hash-set! store new-word slot)))

(defun word-valid-for-store? (word) (and (string? word) (>= (length word) 3)))

(defun add-word-to-store (word)
  "Add a word to the completion store with FIFO eviction."
  (if (not (word-valid-for-store? word))
    0
    (let* ((vec *completion-word-order*)
           (vec-size (length vec))
           (existing-slot (hash-ref *completion-word-store* word)))
      (if existing-slot (vector-set! vec existing-slot nil))
      (if (>= *completion-word-order-index* vec-size)
        (set! *completion-word-order-index* 0))
      (let* ((slot
              (normalize-order-index *completion-word-order-index* vec-size))
             (old (vector-ref vec slot)))
        (insert-word-into-slot! vec *completion-word-store* slot old word)
        (advance-order-index vec-size)
        1))))

(defvar *collect-words-max-length* 65536
  "Maximum text length for word collection. Texts longer than this are truncated.")

(defun collect-words-from-text (text)
  "Extract words from text and add them to completion store."
  (if (not (string? text))
    ()
    (let ((input
           (if (> (length text) *collect-words-max-length*)
             (substring text 0 *collect-words-max-length*)
             text)))
      (let ((words (extract-words input)))
        (if (null? words)
          ()
          (do ((remaining words (cdr remaining))) ((null? remaining))
            (add-word-to-store (car remaining))))))))

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
;; HOOK WRAPPER FUNCTIONS
;; ============================================================================
;; Hook dispatch uses a per-session *hooks* hash table (key = hook name,
;; value = sorted list of (fn . priority) pairs). add-hook, remove-hook,
;; run-hook, run-filter-hook are C builtins that operate on this table.
;; These wrappers are called from C via lisp_x_call_* functions.
(defun telnet-input-hook (text)
  "Process telnet server output through registered hooks."
  (run-hook 'telnet-input-hook text)
  nil)

(defvar *user-input-handled* nil)

(defvar *user-input-result* nil)

(defun user-input-hook (text cursor-pos)
  "Transform user input before sending to telnet server."
  (set! *user-input-handled* nil)
  (set! *user-input-result* nil)
  (run-hook 'user-input-hook text cursor-pos)
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

(add-hook 'telnet-input-hook default-word-collector)

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
;; COMPLETION DIAGNOSTICS
;; ============================================================================
(defun completion-debug-info ()
  "Print completion word store diagnostics."
  (let* ((vec *completion-word-order*)
         (vec-size (length vec))
         (store-count (length (hash-keys *completion-word-store*)))
         (idx *completion-word-order-index*))
    (terminal-echo
     (concat "\r\nCompletion store: " (number->string store-count)
      " unique words\r\n" "Circular buffer size: " (number->string vec-size)
      "\r\n" "Buffer index: " (number->string idx) "\r\n"))))

;; ============================================================================
;; LOGGING CONVENIENCE WRAPPERS
;; ============================================================================
(defun report-error (message)
  "Log an error message via the bloom logging system."
  (bloom-log 'error "lisp" message))

(defun report-warn (message)
  "Log a warning message via the bloom logging system."
  (bloom-log 'warn "lisp" message))

;; ============================================================================
;; SCRIPT STARTUP BANNERS
;; ============================================================================
;; Bubbletea-inspired soft pastel color palette
(defun script-echo (title &rest args)
  "Print a styled script startup banner with optional description and sections.

Usage:
  (script-echo \"Title\")
  (script-echo \"Title\" :desc \"short description\")
  (script-echo \"Title\"
    :desc \"description\"
    :section \"Usage\" \"cmd1\" \"cmd2\"
    :section \"Features\" \"feature1\" \"feature2\")

Colors: header=pale pink, desc=pale cyan, section=lavender, details=slate blue"
  (let ((c-header (color->fg *color-script-header*))
        (c-desc (color->fg *color-script-desc*))
        (c-section (color->fg *color-script-section*))
        (c-detail (color->fg *color-script-detail*))
        (c-mdash (color->fg *color-script-mdash*))
        (reset (termcap 'reset))
        (desc nil)
        (sections nil)
        (current-section nil))
    ;; Parse args: extract :desc and :section markers
    (do ((rest args (cdr rest))) ((null? rest))
      (let ((item (car rest)))
        (cond
          ((eq? item :desc) (set! rest (cdr rest))
           (when rest (set! desc (car rest))))
          ((eq? item :section)
           ;; Save previous section if any
           (when current-section
             (set! sections (cons (reverse current-section) sections)))
           ;; Start new section with title
           (set! rest (cdr rest))
           (set! current-section (if rest (list (car rest)) nil)))
          (current-section
           ;; Add to current section's details
           (set! current-section (cons item current-section)))
          (#t
           ;; Backward compat: plain strings become anonymous section details
           (unless current-section (set! current-section '()))
           (set! current-section (cons item current-section))))))
    ;; Save final section
    (when current-section
      (set! sections (cons (reverse current-section) sections)))
    (set! sections (reverse sections))
    ;; Output header line
    (terminal-echo (concat c-header title reset))
    (when desc (terminal-echo (concat c-mdash " — " reset c-desc desc reset)))
    (terminal-echo "\r\n")
    ;; Output sections
    (do ((slist sections (cdr slist))) ((null? slist))
      (let ((section (car slist)))
        (when section
          (let ((sec-title (car section))
                (details (cdr section)))
            ;; Section title (if it looks like a title, not just a detail)
            (when (and sec-title (or details (not (null? (cdr sections)))))
              (terminal-echo (concat "  " c-section sec-title reset "\r\n")))
            ;; Section details
            (if details
              (do ((dlist details (cdr dlist))) ((null? dlist))
                (terminal-echo
                 (concat "    " c-detail (car dlist) reset "\r\n")))
              ;; Single item section (backward compat): treat title as detail
              (when (and sec-title (null? details) (null? (cdr sections)))
                (terminal-echo (concat "  " c-detail sec-title reset "\r\n"))))))))))

;; ============================================================================
;; STATUSBAR MODE REGISTRY
;; ============================================================================
;; Mode registry: list of (symbol text priority) entries
(defvar *statusbar-mode-registry* '()
  "Registry of active statusbar modes. Each entry is (symbol text priority).")

(defun statusbar--insert-sorted (entry lst)
  "Insert entry into list sorted by priority (descending)."
  (cond
    ((null? lst) (list entry))
    ((> (list-ref entry 2) (list-ref (car lst) 2)) (cons entry lst))
    (#t (cons (car lst) (statusbar--insert-sorted entry (cdr lst))))))

(defun statusbar--compose-modes ()
  "Compose all modes into a single string and update the statusbar."
  (if (null? *statusbar-mode-registry*)
    (statusbar-set-mode)
    (let ((texts (map (lambda (e) (list-ref e 1)) *statusbar-mode-registry*)))
      (statusbar-set-mode (string-join texts " · ")))))

(defun statusbar-mode-set (mode-symbol text priority)
  "Add or update a mode indicator in the statusbar.

   Arguments:
   - mode-symbol: A symbol identifying this mode (for later removal)
   - text: The display text shown in the statusbar
   - priority: Integer priority (higher = leftmost)

   Multiple modes are composed together with \" · \" separator,
   sorted by priority (highest first).

   Example:
     (statusbar-mode-set 'recording \"REC\" 100)
     (statusbar-mode-set 'practice \"Practice\" 50)"
  ;; Remove existing entry with same symbol
  (set! *statusbar-mode-registry*
   (filter (lambda (e) (not (eq? (car e) mode-symbol)))
    *statusbar-mode-registry*))
  ;; Insert new entry in sorted position
  (set! *statusbar-mode-registry*
   (statusbar--insert-sorted (list mode-symbol text priority)
    *statusbar-mode-registry*))
  (statusbar--compose-modes)
  nil)

(defun statusbar-mode-remove (mode-symbol)
  "Remove a mode indicator from the statusbar.

   The mode is identified by the symbol used when it was set.

   Example:
     (statusbar-mode-remove 'recording)"
  (set! *statusbar-mode-registry*
   (filter (lambda (e) (not (eq? (car e) mode-symbol)))
    *statusbar-mode-registry*))
  (statusbar--compose-modes)
  nil)

;; ============================================================================
;; STATUSBAR NOTIFICATION WRAPPER
;; ============================================================================
(defvar *notify-timer* nil "Timer for auto-clearing notifications.")

(defun notify (message &optional ttl)
  "Display a notification in the statusbar.
   Optional TTL (seconds) auto-clears the notification."
  (when *notify-timer* (cancel-timer *notify-timer*) (set! *notify-timer* nil))
  (statusbar-notify message)
  (when ttl
    (set! *notify-timer*
     (run-at-time ttl nil
      (lambda () (statusbar-clear) (set! *notify-timer* nil))))))

;; ============================================================================
;; DISPLAY UTILITY FUNCTIONS
;; ============================================================================
(defun visual-length (str)
  "Calculate display length of string, excluding ANSI escape codes."
  (if (not (string? str))
    0
    (let ((ansi-pattern "\\033\\[[0-9;]*m"))
      (length (regex-replace-all ansi-pattern str "")))))

(defun pad-string (str width)
  "Pad string to specified width with trailing spaces."
  (if (not (string? str))
    ""
    (let ((visual-len (visual-length str)))
      (let ((padding-needed (- width visual-len)))
        (if (<= padding-needed 0)
          str
          (let ((result str))
            (do ((i 0 (+ i 1))) ((>= i padding-needed) result)
              (set! result (concat result " ")))))))))

(defun repeat-string (str count)
  "Repeat a string N times."
  (if (<= count 0)
    ""
    (let ((result ""))
      (do ((i 0 (+ i 1))) ((>= i count) result)
        (set! result (concat result str))))))

;; ============================================================================
;; STARTUP MESSAGE
;; ============================================================================
(let* ((sep (if (termcap 'unicode?) " · " ", "))
       (term-type (termcap 'type))
       (encoding (termcap 'encoding))
       (color-name
        (let ((level (termcap 'color-level)))
          (cond
            ((= level 4) "truecolor")
            ((= level 3) "256-color")
            ((= level 2) "16-color")
            ((> level 0) "8-color")
            (#t nil))))
       (term-info
        (concat term-type (if color-name (concat sep color-name) "")
         (if (and (string? encoding) (not (string=? encoding "ASCII")))
           (concat sep encoding)
           ""))))
  (script-echo (concat "bloom-telnet " *version*) :desc ":help for commands"
   :section "Terminal" term-info))

