;; tintin-conditional.lisp - #if/#else/#elseif for TinTin++ emulator
;;
;; Depends on: tintin-state.lisp, tintin-utils.lisp, tintin-parsing.lisp,
;;             tintin-commands.lisp
;; ============================================================================
;; CONDITION UTILITIES
;; ============================================================================
;; Check if string is wrapped in double quotes
(defun tintin-is-quoted? (str)
  (and (string? str) (>= (length str) 2) (char=? (string-ref str 0) #\")
       (char=? (string-ref str (- (length str) 1)) #\")))

;; Remove outer double quotes from string
(defun tintin-strip-quotes (str)
  (if (tintin-is-quoted? str) (substring str 1 (- (length str) 1)) str))

;; Find a comparison operator outside quotes in a condition string.
;; Returns (operator . position) or nil.
;; Scans for ==, !=, >=, <=, >, < while tracking quote state.
(defun tintin-find-condition-operator (str)
  (let ((len (length str))
        (pos 0)
        (in-quote #f)
        (result nil))
    (do () ((or (>= pos len) result) result)
      (let ((ch (string-ref str pos)))
        (cond
          ;; Toggle quote tracking
          ((char=? ch #\") (set! in-quote (not in-quote)) (set! pos (+ pos 1)))
          ;; Outside quotes: check for operators
          ((not in-quote)
           (cond
             ;; Two-character operators first
             ((and (< (+ pos 1) len) (char=? ch #\=)
                   (char=? (string-ref str (+ pos 1)) #\=))
              (set! result (cons "==" pos)))
             ((and (< (+ pos 1) len) (char=? ch #\!)
                   (char=? (string-ref str (+ pos 1)) #\=))
              (set! result (cons "!=" pos)))
             ((and (< (+ pos 1) len) (char=? ch #\>)
                   (char=? (string-ref str (+ pos 1)) #\=))
              (set! result (cons ">=" pos)))
             ((and (< (+ pos 1) len) (char=? ch #\<)
                   (char=? (string-ref str (+ pos 1)) #\=))
              (set! result (cons "<=" pos)))
             ;; Single-character operators (only if not part of ==, !=, etc.)
             ((char=? ch #\>) (set! result (cons ">" pos)))
             ((char=? ch #\<) (set! result (cons "<" pos)))
             (#t (set! pos (+ pos 1)))))
          ;; Inside quotes: skip
          (#t (set! pos (+ pos 1))))))))

;; ============================================================================
;; CONDITION EVALUATION
;; ============================================================================
;; Evaluate a TinTin++ condition string.
;; Expands variables, finds operator, compares operands.
;; Quoted operands → string comparison.
;; Unquoted numeric operands → numeric comparison.
;; No operator → non-zero/non-empty = true.
(defun tintin-evaluate-condition (condition-str)
  (let ((expanded (tintin-expand-variables-fast condition-str)))
    (let ((op-result (tintin-find-condition-operator expanded)))
      (if (not op-result)
        ;; No operator: treat as truth test
        ;; "0" and "" are false, everything else is true
        (let ((trimmed (tintin-trim expanded)))
          (and (not (string=? trimmed "")) (not (string=? trimmed "0"))))
        ;; Has operator: split into left and right operands
        (let* ((op (car op-result))
               (op-pos (cdr op-result))
               (op-len (length op))
               (left-raw (tintin-trim (substring expanded 0 op-pos)))
               (right-raw
                (tintin-trim
                 (substring expanded (+ op-pos op-len) (length expanded))))
               (left-quoted (tintin-is-quoted? left-raw))
               (right-quoted (tintin-is-quoted? right-raw))
               (left-val (tintin-strip-quotes left-raw))
               (right-val (tintin-strip-quotes right-raw)))
          ;; Determine comparison mode
          (if (or left-quoted right-quoted)
            ;; String comparison
            (cond
              ((string=? op "==") (string=? left-val right-val))
              ((string=? op "!=") (not (string=? left-val right-val)))
              ((string=? op ">") (string>? left-val right-val))
              ((string=? op "<") (string<? left-val right-val))
              ((string=? op ">=") (not (string<? left-val right-val)))
              ((string=? op "<=") (not (string>? left-val right-val)))
              (#t #f))
            ;; Try numeric comparison
            (let ((left-num (string->number left-val))
                  (right-num (string->number right-val)))
              (if (and left-num right-num)
                ;; Numeric comparison
                (cond
                  ((string=? op "==") (= left-num right-num))
                  ((string=? op "!=") (not (= left-num right-num)))
                  ((string=? op ">") (> left-num right-num))
                  ((string=? op "<") (< left-num right-num))
                  ((string=? op ">=") (>= left-num right-num))
                  ((string=? op "<=") (<= left-num right-num))
                  (#t #f))
                ;; Fall back to string comparison
                (cond
                  ((string=? op "==") (string=? left-val right-val))
                  ((string=? op "!=") (not (string=? left-val right-val)))
                  (#t #f))))))))))

;; ============================================================================
;; COMMAND HANDLERS
;; ============================================================================
;; Handle #if command
;; args: 2-3 args: {condition} {true-body} [{false-body}]
(defun tintin-handle-if (args)
  (let* ((condition-str (tintin-strip-braces (list-ref args 0)))
         (true-body (tintin-strip-braces (list-ref args 1)))
         (has-else (>= (length args) 3))
         (false-body (if has-else (tintin-strip-braces (list-ref args 2)) ""))
         (result (tintin-evaluate-condition condition-str)))
    (set! *tintin-last-if-result* result)
    (if result
      (tintin-process-input true-body)
      (if has-else (tintin-process-input false-body) ""))))

;; Handle #else command
;; args: 1 arg: {body}
(defun tintin-handle-else (args)
  (let ((body (tintin-strip-braces (list-ref args 0))))
    (if (not *tintin-last-if-result*) (tintin-process-input body) "")))

;; Handle #elseif command
;; args: 2 args: {condition} {body}
(defun tintin-handle-elseif (args)
  (if *tintin-last-if-result*
    ;; Previous condition was true, skip
    ""
    ;; Previous condition was false, evaluate this one
    (let* ((condition-str (tintin-strip-braces (list-ref args 0)))
           (body (tintin-strip-braces (list-ref args 1)))
           (result (tintin-evaluate-condition condition-str)))
      (set! *tintin-last-if-result* result)
      (if result (tintin-process-input body) ""))))

;; ============================================================================
;; COMMAND REGISTRY
;; ============================================================================
(hash-set! *tintin-commands* "if"
 (list tintin-handle-if 3
  "#if {condition} {true-body} or #if {condition} {true-body} {false-body}"))
(hash-set! *tintin-commands* "else" (list tintin-handle-else 1 "#else {body}"))
(hash-set! *tintin-commands* "elseif"
 (list tintin-handle-elseif 2 "#elseif {condition} {body}"))

