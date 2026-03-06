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
;; ALIAS EXPANSION (PURE)
;; ============================================================================
;; Try one level of alias expansion: variable expansion + match + substitute.
;; Returns expanded template string, or nil if no alias matched.
(defun tintin-try-alias (cmd)
  (let ((expanded-cmd (tintin-expand-variables-fast cmd)))
    ;; Try simple alias match
    (let ((simple-match (tintin-match-simple-alias expanded-cmd)))
      (if simple-match
        ;; Simple alias found
        (let* ((alias-entry (car simple-match))
               (args (cdr simple-match))
               (template (car alias-entry)))
          (tintin-substitute-template template args nil))
        ;; Try pattern alias match
        (let ((pattern-match (tintin-match-pattern-alias expanded-cmd)))
          (if pattern-match
            ;; Pattern alias found
            (let* ((pattern (car pattern-match))
                   (match-values (cdr pattern-match))
                   (alias-data (hash-ref *tintin-aliases* pattern))
                   (template (car alias-data)))
              (tintin-substitute-template template nil match-values))
            ;; No alias match
            nil))))))

;; ============================================================================
;; EXPAND ALIAS (synchronous, depth-first, collect results)
;; ============================================================================
;; Expand speedwalk, split by semicolon, process each part synchronously
;; through the full hook pipeline (filter + transform) for depth-first ordering.
;; Returns semicolon-joined string of all expanded commands (preserving order).
(defun tintin-expand-alias (result)
  (let ((expanded (tintin-expand-speedwalk result)))
    (let ((parts (tintin-split-commands expanded))
          (collected '()))
      (let ((base-depth *tintin-alias-depth*))
        (do ((i 0 (+ i 1))) ((>= i (length parts)))
          (let ((part (list-ref parts i)))
            (if (and (string? part) (not (string=? part "")))
              (let ((cmd (tintin-expand-variables-fast part)))
                ;; Reset depth for each sibling — they're at the same nesting level
                (set! *tintin-alias-depth* (+ base-depth 1))
                ;; Recurse via process-command-internal for nested alias expansion.
                ;; Do NOT run the full hook pipeline here — the caller's pipeline
                ;; will apply other transforms (command prefixing, etc.) to our result.
                (let ((processed (tintin-process-command-internal cmd)))
                  (if (and (string? processed) (not (string=? processed "")))
                    (set! collected (cons processed collected)))))))))
      ;; Join collected results with semicolons
      (let ((reversed (reverse collected))
            (output ""))
        (do ((i 0 (+ i 1))) ((>= i (length reversed)) output)
          (set! output
           (concat output (if (> i 0) ";" "") (list-ref reversed i))))))))

