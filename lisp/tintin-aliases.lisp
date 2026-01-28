;; tintin-aliases.lisp - Alias expansion for TinTin++ emulator
;;
;; Depends on: tintin-state.lisp, tintin-utils.lisp, tintin-patterns.lisp,
;;             tintin-parsing.lisp, tintin-speedwalk.lisp
;; ============================================================================
;; ALIAS MATCHING
;; ============================================================================
;; Match first word against alias hash table
;; Returns: (alias-entry . args) or nil
(defun tintin-match-simple-alias (cmd)
  "Match first word against simple (non-pattern) alias hash table.

  ## Parameters
  - `cmd` - Command string to match

  ## Returns
  Cons cell `(alias-entry . args)` where:
  - `alias-entry` - Alias data: `(expansion-template priority)`
  - `args` - List of remaining words after first word

  Returns `nil` if no match found."
  (let ((words (split cmd " ")))
    (if (or (null? words) (= (length words) 0))
      nil
      (let ((first-word (car words))
            (args (cdr words)))
        (let ((alias-entry (hash-ref *tintin-aliases* first-word)))
          (if alias-entry (cons alias-entry args) nil))))))

;; Linear search for pattern aliases
;; Returns: (pattern . match-values) or nil
(defun tintin-match-pattern-alias (cmd)
  "Match command against pattern (wildcard) aliases via linear search.

  ## Parameters
  - `cmd` - Command string to match against patterns

  ## Returns
  Cons cell `(pattern . match-values)` where:
  - `pattern` - Matched alias pattern string
  - `match-values` - List of captured wildcard values

  Returns `nil` if no pattern matches."
  (let ((alias-names (hash-keys *tintin-aliases*))
        (matched nil))
    (if (or (null? alias-names) (= (length alias-names) 0))
      nil
      (do ((i 0 (+ i 1))) ((or (>= i (length alias-names)) matched) matched)
        (let* ((pattern (list-ref alias-names i))
               (match-values (tintin-match-pattern pattern cmd)))
          (if match-values (set! matched (cons pattern match-values))))))))

;; ============================================================================
;; TEMPLATE SUBSTITUTION
;; ============================================================================
;; Replace %0, %1, %2... in template with args or match-values
;; Returns: template with placeholders replaced + unused args appended
(defun tintin-substitute-template (template args match-values)
  (let* ((arg-vals (or match-values args '()))
         (result template)
         (used-args (make-vector (length arg-vals) #f)))
    ;; Replace %0 with all arguments
    (if (> (length arg-vals) 0)
      (let ((all-args "")
            (old-result result))
        (do ((i 0 (+ i 1))) ((>= i (length arg-vals)))
          (set! all-args
           (concat all-args (if (> i 0) " " "") (list-ref arg-vals i))))
        (set! result (string-replace result "%0" all-args))
        ;; Mark all args as used if %0 was replaced
        (if (not (string=? result old-result))
          (do ((i 0 (+ i 1))) ((>= i (length arg-vals)))
            (vector-set! used-args i #t)))))
    ;; Replace %1, %2, etc.
    (do ((i 0 (+ i 1))) ((>= i (length arg-vals)))
      (let ((placeholder (concat "%" (number->string (+ i 1))))
            (old-result result))
        (set! result (string-replace result placeholder (list-ref arg-vals i)))
        (if (not (string=? result old-result)) (vector-set! used-args i #t))))
    ;; Append unused arguments (only for simple aliases with args)
    (if args
      (let ((unused-list '()))
        (do ((j 0 (+ j 1))) ((>= j (length arg-vals)))
          (if (not (vector-ref used-args j))
            (set! unused-list (cons (list-ref arg-vals j) unused-list))))
        (if (not (eq? unused-list '()))
          (let ((unused-args "")
                (reversed (reverse unused-list)))
            (do ((k 0 (+ k 1))) ((>= k (length reversed)))
              (set! unused-args
               (concat unused-args (if (> k 0) " " "") (list-ref reversed k))))
            (set! result (concat result " " unused-args))))))
    result))

;; ============================================================================
;; RECURSIVE EXPANSION
;; ============================================================================
;; Expand speedwalk, split by semicolons, recursively process
;; Returns: fully expanded and joined commands
;; KEY: This eliminates ~70 lines of duplication
(defun tintin-expand-and-recurse (result depth)
  ;; Check depth limit (circular alias detection)
  (if (>= depth *tintin-max-alias-depth*)
    (progn
      (tintin-echo
       (concat "Error: Circular alias detected or depth limit ("
        (number->string *tintin-max-alias-depth*) ") exceeded\r\n"))
      result) ; Return unexpanded to stop recursion
    ;; Expand speedwalk only (variables expand per-command for just-in-time evaluation)
    (let ((expanded (tintin-expand-speedwalk result)))
      ;; Split by semicolon
      (let ((split-commands (tintin-split-commands expanded)))
        (if (> (length split-commands) 1)
          ;; Multiple commands - recursively process each
          (let ((sub-results '()))
            (do ((j 0 (+ j 1))) ((>= j (length split-commands)))
              (let ((subcmd (list-ref split-commands j)))
                (if (and (string? subcmd) (not (string=? subcmd "")))
                  ;; Expand variables for THIS command only (just-in-time)
                  (let* ((cmd-with-vars (tintin-expand-variables-fast subcmd))
                         (result
                          (tintin-process-command-internal cmd-with-vars
                           (+ depth 1))))
                    (if (and (string? result) (not (string=? result "")))
                      (set! sub-results (cons result sub-results)))))))
            ;; Join with semicolons
            (if (eq? sub-results '())
              ""
              (let ((reversed (reverse sub-results))
                    (output ""))
                (do ((k 0 (+ k 1))) ((>= k (length reversed)) output)
                  (set! output
                   (concat output (if (> k 0) ";" "") (list-ref reversed k)))))))
          ;; Single command - recursively process
          (if (> (length split-commands) 0)
            (let ((cmd-with-vars
                   (tintin-expand-variables-fast (list-ref split-commands 0))))
              (tintin-process-command-internal cmd-with-vars (+ depth 1)))
            ""))))))

;; ============================================================================
;; MAIN ALIAS EXPANSION
;; ============================================================================
;; Orchestrate alias matching and expansion
;; Returns: expanded command (may contain semicolons)
(defun tintin-expand-alias (cmd depth)
  (let ((expanded-cmd (tintin-expand-variables-fast cmd)))
    ;; Try simple alias match
    (let ((simple-match (tintin-match-simple-alias expanded-cmd)))
      (if simple-match
        ;; Simple alias found
        (let* ((alias-entry (car simple-match))
               (args (cdr simple-match))
               (template (car alias-entry))
               (result (tintin-substitute-template template args nil)))
          (tintin-expand-and-recurse result depth))
        ;; Try pattern alias match
        (let ((pattern-match (tintin-match-pattern-alias expanded-cmd)))
          (if pattern-match
            ;; Pattern alias found
            (let* ((pattern (car pattern-match))
                   (match-values (cdr pattern-match))
                   (alias-data (hash-ref *tintin-aliases* pattern))
                   (template (car alias-data))
                   (result
                    (tintin-substitute-template template nil match-values)))
              (tintin-expand-and-recurse result depth))
            ;; No alias match - just expand speedwalk
            (tintin-expand-speedwalk expanded-cmd)))))))
