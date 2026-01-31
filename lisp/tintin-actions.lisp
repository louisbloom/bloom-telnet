;; tintin-actions.lisp - Action triggering for TinTin++ emulator
;;
;; Depends on: tintin-state.lisp, tintin-utils.lisp, tintin-patterns.lisp,
;;             tintin-parsing.lisp
;; ============================================================================
;; CAPTURE EXTRACTION
;; ============================================================================
;; Extract %1-%99 capture groups from pattern match
;; Uses regex-extract builtin to get capture values from matched text
;; Returns: List of captured strings or empty list if no match
;; Example: pattern="You hit %1 for %2 damage", text="You hit orc for 15 damage"
;;          → ("orc" "15")
(defun tintin-extract-captures (pattern text)
  "Extract %1-%99 capture groups from TinTin++ pattern match.

  ## Parameters
  - `pattern` - TinTin++ pattern with wildcards (%*, %1-%99)
  - `text` - Text to extract captures from

  ## Returns
  List of captured strings (in order: %1, %2, ..., %99), or empty list if
  no match or invalid parameters.

  ## Examples
  ```lisp
  (tintin-extract-captures \"You hit %1 for %2 damage\"
                           \"You hit orc for 15 damage\")
  ; => (\"orc\" \"15\")
  ```"
  (if (or (not (string? pattern)) (not (string? text)))
    '()
    (let ((regex-pattern (tintin-pattern-to-regex pattern)))
      (if (string=? regex-pattern "")
        '()
        ;; Use regex-extract to get all capture groups
        (let ((captures (regex-extract regex-pattern text)))
          (if captures captures '()))))))

;; Replace %1-%99 in template with capture values
;; Iterates through captures list, replacing each placeholder
;; Returns: Template with placeholders replaced
;; Example: template="say %1 took %2!", captures=("orc" "15")
;;          → "say orc took 15!"
(defun tintin-substitute-captures (template captures)
  "Replace %1-%99 placeholders in template with capture values.

  ## Parameters
  - `template` - String containing %1-%99 placeholders
  - `captures` - List of captured strings to substitute

  ## Returns
  Template string with placeholders replaced by corresponding capture values.

  ## Examples
  ```lisp
  (tintin-substitute-captures \"say %1 took %2!\" '(\"orc\" \"15\"))
  ; => \"say orc took 15!\"
  ```"
  (if (or (not (string? template)) (not (list? captures)))
    template
    (let ((result template))
      ;; Replace each capture group placeholder (%1, %2, ..., %99)
      (do ((i 0 (+ i 1))) ((>= i (length captures)) result)
        (let ((placeholder (concat "%" (number->string (+ i 1))))
              (value (list-ref captures i)))
          (if (string? value)
            (set! result (string-replace result placeholder value))))))))

;; ============================================================================
;; ACTION EXECUTION
;; ============================================================================
;; Execute action commands with circular execution detection
;; Sets *tintin-action-executing* flag to prevent infinite loops
;; Processes commands via tintin-process-input and sends each via telnet-send
;; Returns: nil (side effect only)
(defun tintin-execute-action (commands)
  (if (not (string? commands))
    nil
    ;; Check circular execution flag
    (if *tintin-action-executing*
      (progn
        (terminal-echo
         "Warning: Action triggered during action execution (skipped)\r\n")
        nil)
      (progn (set! *tintin-action-executing* #t)
        ;; Process and send commands
        (condition-case err
          (progn
            (let ((processed (tintin-process-input commands)))
              (if (and (string? processed) (not (string=? processed "")))
                (let ((cmd-list (tintin-split-commands processed)))
                  (do ((i 0 (+ i 1))) ((>= i (length cmd-list)))
                    (let ((cmd (list-ref cmd-list i)))
                      (if (and (string? cmd) (not (string=? cmd "")))
                        (condition-case send-err (telnet-send cmd)
                          (error
                           (terminal-echo
                            (concat "Action send failed: "
                             (error-message send-err) "\r\n"))))))))))
            ;; Clear flag after execution
            (set! *tintin-action-executing* #f))
          (error
           ;; Clear flag on error
           (set! *tintin-action-executing* #f)
           (terminal-echo
            (concat "Action execution error: " (error-message err) "\r\n"))))))))

;; ============================================================================
;; ACTION TRIGGERING
;; ============================================================================
;; Test all action patterns against line and execute matches
;; Processes ALL matching actions in priority order (low to high)
;; For each match: extract captures → substitute → expand vars → execute
(defun tintin-trigger-actions-for-line (line)
  "Execute all matching action triggers for a line of server output.

  ## Parameters
  - `line` - Line of text from server (ANSI codes already stripped)

  ## Returns
  `nil` (side effects only - commands sent via `telnet-send`)

  ## Description
  Tests all defined action patterns against incoming server output and
  executes matching actions in priority order (lower priority first)."
  (if (or (not (string? line)) (= (hash-count *tintin-actions*) 0))
    nil
    ;; Get all actions sorted by priority (low to high)
    (let ((action-entries (hash-entries *tintin-actions*)))
      (let ((sorted (tintin-sort-actions-by-priority action-entries)))
        ;; Try all patterns and execute all that match
        (do ((i 0 (+ i 1))) ((>= i (length sorted)))
          (let* ((entry (list-ref sorted i))
                 (pattern (car entry))
                 (data (cdr entry))
                 (commands (car data))
                 (priority (cadr data)))
            ;; Check if pattern matches the line
            (if (tintin-match-highlight-pattern pattern line)
              ;; Pattern matches - extract captures and execute
              (let ((captures (tintin-extract-captures pattern line)))
                ;; Substitute captures in commands
                (let ((substituted
                       (tintin-substitute-captures commands captures)))
                  ;; Expand variables
                  (let ((expanded (tintin-expand-variables-fast substituted)))
                    ;; Execute the action
                    (tintin-execute-action expanded)))))))))))
