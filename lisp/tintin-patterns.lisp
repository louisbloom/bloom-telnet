;; tintin-patterns.lisp - Pattern matching system for TinTin++ emulator
;;
;; Depends on: tintin-state.lisp
;; ============================================================================
;; PATTERN TO REGEX CONVERSION
;; ============================================================================
;; Check if character needs regex escaping
(defun tintin-regex-special-char? (ch)
  (or (char=? ch #\.) (char=? ch #\*) (char=? ch #\+) (char=? ch #\?)
      (char=? ch #\[) (char=? ch #\]) (char=? ch #\{) (char=? ch #\})
      (char=? ch #\() (char=? ch #\)) (char=? ch #\|) (char=? ch #\\)
      (char=? ch #\^) (char=? ch #\$)))

;; Convert TinTin++ pattern to PCRE2 regex
;; Pattern translation:
;;   %* or %1-%99 → (.*?) (non-greedy capture)
;;   ^ at start → ^ (line anchor)
;;   Other chars → escaped for regex
;; Examples:
;;   "You hit %*" → "You hit (.*?)"
;;   "^Health: %1" → "^Health: (.*?)"
;;   "Valgar" → "Valgar"
(defun tintin-pattern-to-regex (pattern)
  "Convert TinTin++ pattern to PCRE2 regular expression.

  ## Parameters
  - `pattern` - TinTin++ pattern string with wildcards

  ## Returns
  PCRE2-compatible regular expression string. Returns empty string `\"\"` if
  pattern is invalid.

  ## Description
  Translates TinTin++ wildcard syntax into standard PCRE2 regex patterns.
  Automatically escapes regex special characters and converts wildcards into
  non-greedy capture groups for pattern matching and data extraction.

  **Pattern Translation Rules:**

  - **`%*`** → `(.*?)` - Match anything (non-greedy capture)
  - **`%1-%99`** → `(.*?)` - Numbered wildcards (capture group)
  - **`^` at start** → `^` - Line anchor (start of line)
  - **Regex special chars** → Escaped (`.` → `\\.`, `*` → `\\*`, etc.)
  - **Other characters** → Literal match"
  (if (not (string? pattern))
    ""
    (let ((len (length pattern))
          (pos 0)
          (result ""))
      (do () ((>= pos len) result)
        (let ((ch (string-ref pattern pos)))
          (cond
            ;; Handle % placeholders
            ((char=? ch #\%)
             (if (< (+ pos 1) len)
               (let ((next-ch (string-ref pattern (+ pos 1))))
                 (if (char=? next-ch #\*)
                   ;; %* at end → (.*), otherwise (.*?)
                   (let ((at-end (>= (+ pos 2) len)))
                     (set! result (concat result (if at-end "(.*)" "(.*?)")))
                     (set! pos (+ pos 2)))
                   ;; Check if it's %1-%99
                   (if (and (char>=? next-ch #\0) (char<=? next-ch #\9))
                     (let ((digit-end (+ pos 2)))
                       ;; Consume second digit if present
                       (if
                         (and (< digit-end len)
                              (char>=? (string-ref pattern digit-end) #\0)
                              (char<=? (string-ref pattern digit-end) #\9))
                         (set! digit-end (+ digit-end 1)))
                       ;; %N or %NN at end → (.*), otherwise (.*?)
                       (let ((at-end (>= digit-end len)))
                         (set! result
                          (concat result (if at-end "(.*)" "(.*?)")))
                         (set! pos digit-end)))
                     ;; Not %* or %N - literal %
                     (progn (set! result (concat result "\\%"))
                       (set! pos (+ pos 1))))))
               ;; % at end of string - literal
               (progn (set! result (concat result "\\%")) (set! pos (+ pos 1)))))
            ;; Handle ^ at start (line anchor)
            ((and (char=? ch #\^) (= pos 0)) (set! result (concat result "^"))
             (set! pos (+ pos 1)))
            ;; Escape regex special characters
            ((tintin-regex-special-char? ch)
             (set! result (concat result "\\" (char->string ch)))
             (set! pos (+ pos 1)))
            ;; Regular character - no escaping needed
            (#t (set! result (concat result (char->string ch)))
             (set! pos (+ pos 1)))))))))

;; ============================================================================
;; PATTERN MATCHING
;; ============================================================================
;; Test if TinTin++ pattern matches text using regex
;; Returns #t if match found, #f otherwise
(defun tintin-match-highlight-pattern (pattern text)
  "Test if TinTin++ pattern matches text using regex.

  ## Parameters
  - `pattern` - TinTin++ pattern string (with wildcards %*, %1-%99)
  - `text` - Text to test against pattern

  ## Returns
  `#t` if pattern matches text, `#f` otherwise. Returns `#f` if either
  parameter is invalid."
  (if (or (not (string? pattern)) (not (string? text)))
    #f
    (let ((regex-pattern
           (or (hash-ref *tintin-pattern-cache* pattern)
               (let ((computed (tintin-pattern-to-regex pattern)))
                 (hash-set! *tintin-pattern-cache* pattern computed)
                 computed))))
      (if (string=? regex-pattern "")
        #f
        ;; Use regex-match? to test if pattern matches
        (let ((match-result (regex-match? regex-pattern text)))
          (if match-result #t #f))))))

;; Match a pattern against input and extract placeholder values
;; Returns list of extracted values or nil if no match
;; Example: (tintin-match-pattern "k %1 with %2" "k orc with sword") => ("orc" "sword")
(defun tintin-match-pattern (pattern input)
  (let ((pattern-parts (split pattern " "))
        (input-parts (split input " ")))
    (if (not (= (length pattern-parts) (length input-parts)))
      nil
      (let ((matches '())
            (success #t))
        (do ((i 0 (+ i 1)))
          ((or (>= i (length pattern-parts)) (not success))
           (if success (reverse matches) nil))
          (let ((p-part (list-ref pattern-parts i))
                (i-part (list-ref input-parts i)))
            (if (string-prefix? "%" p-part)
              ;; Placeholder - capture the value
              (set! matches (cons i-part matches))
              ;; Literal - must match exactly
              (if
                (and (string? p-part) (string? i-part)
                     (not (string=? p-part i-part)))
                (set! success #f)))))))))

;; ============================================================================
;; HIGHLIGHT PRIORITY SORTING
;; ============================================================================
;; Sort highlight entries by priority (descending - higher priority first)
;; Input: list of (pattern . (fg bg priority)) pairs
;; Output: sorted list by priority (highest first)
(defun tintin-sort-highlights-by-priority (highlight-list)
  "Sort highlight entries by priority (descending order - higher priority first).

  ## Parameters
  - `highlight-list` - List of highlight entries: `((pattern . (fg bg priority)) ...)`

  ## Returns
  Sorted list with highest priority entries first."
  (if (or (null? highlight-list) (= (length highlight-list) 0))
    '()
    ;; Simple insertion sort by priority
    (let ((sorted '()))
      (do ((remaining highlight-list (cdr remaining)))
        ((null? remaining) sorted)
        (let* ((entry (car remaining))
               (priority (cadddr entry)))
          ;; Insert entry in sorted position
          (set! sorted (tintin-insert-by-priority entry priority sorted)))))))

;; Helper: Insert entry into sorted list by priority, then by pattern length
(defun tintin-insert-by-priority (entry priority sorted-list)
  (if (null? sorted-list)
    (list entry)
    (let ((first-entry (car sorted-list))
          (first-priority (cadddr (car sorted-list))))
      (if (> priority first-priority)
        ;; Higher priority - insert at head
        (cons entry sorted-list)
        (if (= priority first-priority)
          ;; Same priority - use pattern length as tiebreaker (longer first)
          (let ((entry-pattern (car entry))
                (first-pattern (car first-entry)))
            (if (>= (length entry-pattern) (length first-pattern))
              (cons entry sorted-list)
              (cons first-entry
               (tintin-insert-by-priority entry priority (cdr sorted-list)))))
          ;; Lower priority - insert later
          (cons first-entry
           (tintin-insert-by-priority entry priority (cdr sorted-list))))))))

;; ============================================================================
;; ACTION PRIORITY SORTING
;; ============================================================================
;; Sort action entries by priority (ascending - lower priority first)
;; Input: list of (pattern . (commands-string priority)) pairs
;; Output: sorted list by priority (lowest first)
(defun tintin-sort-actions-by-priority (action-list)
  "Sort action entries by priority (ascending order - lower priority first).

  ## Parameters
  - `action-list` - List of action entries: `((pattern . (commands priority)) ...)`

  ## Returns
  Sorted list with lowest priority entries first."
  (if (or (null? action-list) (= (length action-list) 0))
    '()
    ;; Simple insertion sort by priority
    (let ((sorted '()))
      (do ((remaining action-list (cdr remaining)))
        ((null? remaining) sorted)
        (let* ((entry (car remaining))
               (priority (caddr entry)))
          ;; Insert entry in sorted position
          (set! sorted (tintin-insert-action-by-priority entry priority sorted)))))))

;; Helper: Insert action entry into sorted list by priority, then by pattern length
(defun tintin-insert-action-by-priority (entry priority sorted-list)
  (if (null? sorted-list)
    (list entry)
    (let ((first-entry (car sorted-list))
          (first-priority (caddr (car sorted-list))))
      (if (< priority first-priority)
        ;; Lower priority - insert at head (actions use ascending order)
        (cons entry sorted-list)
        (if (= priority first-priority)
          ;; Same priority - use pattern length as tiebreaker (longer first)
          (let ((entry-pattern (car entry))
                (first-pattern (car first-entry)))
            (if (>= (length entry-pattern) (length first-pattern))
              (cons entry sorted-list)
              (cons first-entry
               (tintin-insert-action-by-priority entry priority
                (cdr sorted-list)))))
          ;; Higher priority - insert later
          (cons first-entry
           (tintin-insert-action-by-priority entry priority (cdr sorted-list))))))))
