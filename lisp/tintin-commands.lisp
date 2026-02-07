;; tintin-commands.lisp - Command handlers and dispatcher for TinTin++ emulator
;;
;; Depends on: tintin-state.lisp, tintin-utils.lisp, tintin-colors.lisp,
;;             tintin-parsing.lisp, tintin-tables.lisp, tintin-save.lisp
;; ============================================================================
;; COMMAND DETECTION
;; ============================================================================
;; Check if a string is a TinTin++ command (starts with #)
(defun tintin-is-command? (str)
  (and (string? str) (> (length str) 0) (char=? (string-ref str 0) #\#)))

;; Extract command name from TinTin++ command string
;; Example: "#alias {k} {kill}" → "alias"
;;          "#var{x}" → "var"
;;          "# " → nil
(defun tintin-extract-command-name (str)
  (if (not (tintin-is-command? str))
    nil
    (let ((len (length str))
          (pos 1))
      ;; Skip any whitespace after #
      (do () ((or (>= pos len) (not (char=? (string-ref str pos) #\space))))
        (set! pos (+ pos 1)))
      ;; Check if we have any characters left
      (if (>= pos len)
        nil
        ;; Find end of command word (space, {, or end of string)
        (let ((start pos)
              (end pos))
          (do ()
            ((or (>= end len) (char=? (string-ref str end) #\space)
                 (char=? (string-ref str end) #\{)))
            (set! end (+ end 1)))
          ;; Extract and lowercase the command name
          (if (= start end) nil (string-downcase (substring str start end))))))))

;; Find a TinTin++ command by partial prefix match
;; Returns the full command name or nil if no match
;; Example: "al" → "alias", "var" → "variable"
(defun tintin-find-command (prefix)
  "Find TinTin++ command by exact match first, then partial prefix (case-insensitive)."
  (if (not (string? prefix))
    nil
    (let ((prefix-lower (string-downcase prefix)))
      ;; First: exact match (O(1) hash lookup)
      (if (hash-ref *tintin-commands* prefix-lower)
        prefix-lower
        ;; Then: prefix match (linear scan)
        (let ((commands (hash-keys *tintin-commands*))
              (result nil))
          (do ((i 0 (+ i 1))) ((or (>= i (length commands)) result) result)
            (let ((cmd (list-ref commands i)))
              (if (string-prefix? prefix-lower cmd) (set! result cmd)))))))))

;; ============================================================================
;; COMMAND HANDLERS
;; ============================================================================
;; Handle #alias command
;; args: (), (name), or (name commands)
(defun tintin-handle-alias (args)
  "Handle #alias command (list, show, or create aliases)."
  (cond
    ;; No arguments - list all aliases
    ((or (null? args) (= 0 (length args))) (tintin-list-aliases))
    ;; One argument - show specific alias
    ((= 1 (length args))
     (let ((name (tintin-strip-braces (list-ref args 0))))
       (let ((alias-data (hash-ref *tintin-aliases* name)))
         (if alias-data
           (let ((commands (car alias-data))
                 (priority (cadr alias-data)))
             (terminal-echo
              (concat "Alias '" name "': " name " → " commands
               (if (= priority 5)
                 ""
                 (concat " (priority: " (number->string priority) ")")) "\r\n"))
             "")
           (progn (terminal-echo (concat "Alias '" name "' not found\r\n")) "")))))
    ;; Two arguments - create alias
    (#t
     (let ((name (tintin-strip-braces (list-ref args 0)))
           (commands (tintin-strip-braces (list-ref args 1)))
           (priority 5))
       (hash-set! *tintin-aliases* name (list commands priority))
       (terminal-echo
        (concat "Alias '" name "' created: " name " → " commands
         (if (= priority 5)
           ""
           (concat " (priority: " (number->string priority) ")")) "\r\n"))
       ""))))

;; Handle #variable command
;; args: (), (name), or (name value)
(defun tintin-handle-variable (args)
  "Handle #variable command (list, show, or create variables)."
  (cond
    ;; No arguments - list all variables
    ((or (null? args) (= 0 (length args))) (tintin-list-variables))
    ;; One argument - show specific variable
    ((= 1 (length args))
     (let ((name (tintin-strip-braces (list-ref args 0))))
       (let ((value (hash-ref *tintin-variables* name)))
         (if value
           (progn
             (terminal-echo
              (concat "Variable '" name "': " name " = " value "\r\n"))
             "")
           (progn
             (terminal-echo (concat "Variable '" name "' not found\r\n")) "")))))
    ;; Two arguments - create variable
    (#t
     (let ((name (tintin-strip-braces (list-ref args 0)))
           (value (tintin-strip-braces (list-ref args 1))))
       (hash-set! *tintin-variables* name value)
       (terminal-echo (concat "Variable '" name "' set to '" value "'\r\n"))
       ""))))

;; Handle #unalias command
;; args: (name)
(defun tintin-handle-unalias (args)
  "Handle #unalias command (remove alias)."
  (let ((name (tintin-strip-braces (list-ref args 0))))
    (if (hash-ref *tintin-aliases* name)
      (progn (hash-remove! *tintin-aliases* name)
        (terminal-echo (concat "Alias '" name "' removed\r\n"))
        "")
      (progn (terminal-echo (concat "Alias '" name "' not found\r\n")) ""))))

;; Handle #highlight command
;; args: (), (pattern), (pattern color), or (pattern color priority)
;; Color spec format: "fg", "fg:bg", "<rgb>", "bold red", etc.
;; Entry format: pattern → (fg-color bg-color priority)
(defun tintin-handle-highlight (args)
  "Handle #highlight command (list, show, or create highlights)."
  (cond
    ;; No arguments - list all highlights
    ((or (null? args) (= 0 (length args))) (tintin-list-highlights))
    ;; One argument - show specific highlight
    ((= 1 (length args))
     (let ((pattern (tintin-strip-braces (list-ref args 0))))
       (let ((highlight-data (hash-ref *tintin-highlights* pattern)))
         (if highlight-data
           (let ((fg-color (car highlight-data))
                 (bg-color (cadr highlight-data))
                 (priority (caddr highlight-data)))
             (terminal-echo
              (concat "Highlight '" pattern "': " pattern " → "
               (if fg-color fg-color "") (if (and fg-color bg-color) ":" "")
               (if bg-color bg-color "")
               (if (= priority 5)
                 ""
                 (concat " (priority: " (number->string priority) ")")) "\r\n"))
             "")
           (progn
             (terminal-echo (concat "Highlight '" pattern "' not found\r\n"))
             "")))))
    ;; Two or three arguments - create highlight
    (#t
     (let* ((pattern (tintin-strip-braces (list-ref args 0)))
            (color-spec (tintin-strip-braces (list-ref args 1)))
            (priority
             (if (>= (length args) 3)
               (string->number (tintin-strip-braces (list-ref args 2)))
               5)))
       ;; Parse color spec into FG and BG components
       (let ((parts (tintin-split-fg-bg color-spec)))
         (let ((fg-part (list-ref parts 0))
               (bg-part (list-ref parts 1)))
           ;; Store as (fg-color bg-color priority)
           (hash-set! *tintin-highlights* pattern
            (list (if (string=? fg-part "") nil fg-part) bg-part priority))
           ;; Invalidate caches
           (set! *tintin-highlights-dirty* #t)
           (terminal-echo
            (concat "Highlight '" pattern "' created: " pattern " → "
             color-spec
             (if (= priority 5)
               ""
               (concat " (priority: " (number->string priority) ")")) "\r\n"))
           ""))))))

;; Handle #unhighlight command
;; args: (pattern)
(defun tintin-handle-unhighlight (args)
  (let ((pattern (tintin-strip-braces (list-ref args 0))))
    (if (hash-ref *tintin-highlights* pattern)
      (progn (hash-remove! *tintin-highlights* pattern)
        ;; Invalidate caches
        (hash-remove! *tintin-pattern-cache* pattern)
        (set! *tintin-highlights-dirty* #t)
        (terminal-echo (concat "Highlight '" pattern "' removed\r\n"))
        "")
      (progn (terminal-echo (concat "Highlight '" pattern "' not found\r\n"))
        ""))))

;; Handle #action command
;; args: (), (pattern), (pattern commands), or (pattern commands priority)
;; Entry format: pattern → (commands-string priority)
(defun tintin-handle-action (args)
  "Handle #action command (list, show, or create triggers)."
  (cond
    ;; No arguments - list all actions
    ((or (null? args) (= 0 (length args))) (tintin-list-actions))
    ;; One argument - show specific action
    ((= 1 (length args))
     (let ((pattern (tintin-strip-braces (list-ref args 0))))
       (let ((action-data (hash-ref *tintin-actions* pattern)))
         (if action-data
           (let ((commands (car action-data))
                 (priority (cadr action-data)))
             (terminal-echo
              (concat "Action '" pattern "': " pattern " → " commands
               (if (= priority 5)
                 ""
                 (concat " (priority: " (number->string priority) ")")) "\r\n"))
             "")
           (progn
             (terminal-echo (concat "Action '" pattern "' not found\r\n")) "")))))
    ;; Two or three arguments - create action
    (#t
     (let* ((pattern (tintin-strip-braces (list-ref args 0)))
            (commands (tintin-strip-braces (list-ref args 1)))
            (priority
             (if (>= (length args) 3)
               (string->number (tintin-strip-braces (list-ref args 2)))
               5)))
       ;; Store as (commands-string priority)
       (hash-set! *tintin-actions* pattern (list commands priority))
       (terminal-echo
        (concat "Action '" pattern "' created: " pattern " → " commands
         (if (= priority 5)
           ""
           (concat " (priority: " (number->string priority) ")")) "\r\n"))
       ""))))

;; Handle #unaction command
;; args: (pattern)
(defun tintin-handle-unaction (args)
  (let ((pattern (tintin-strip-braces (list-ref args 0))))
    (if (hash-ref *tintin-actions* pattern)
      (progn (hash-remove! *tintin-actions* pattern)
        (terminal-echo (concat "Action '" pattern "' removed\r\n"))
        "")
      (progn (terminal-echo (concat "Action '" pattern "' not found\r\n")) ""))))

;; ============================================================================
;; COMMAND REGISTRY
;; ============================================================================
;; Register commands with metadata (now that handlers are defined)
(hash-set! *tintin-commands* "alias"
 (list tintin-handle-alias 2
  "#alias or #alias {name} or #alias {name} {commands}"))
(hash-set! *tintin-commands* "unalias"
 (list tintin-handle-unalias 1 "#unalias {name}"))
(hash-set! *tintin-commands* "variable"
 (list tintin-handle-variable 2
  "#variable or #variable {name} or #variable {name} {value}"))
(hash-set! *tintin-commands* "highlight"
 (list tintin-handle-highlight 2
  "#highlight or #highlight {pattern} or #highlight {pattern} {color}"))
(hash-set! *tintin-commands* "unhighlight"
 (list tintin-handle-unhighlight 1 "#unhighlight {pattern}"))
(hash-set! *tintin-commands* "save"
 (list tintin-handle-save 1 "#save {filename}"))
(hash-set! *tintin-commands* "load"
 (list tintin-handle-load 1 "#load {filename}"))
(hash-set! *tintin-commands* "action"
 (list tintin-handle-action 3
  "#action or #action {pattern} or #action {pattern} {commands} [priority]"))
(hash-set! *tintin-commands* "unaction"
 (list tintin-handle-unaction 1 "#unaction {pattern}"))

;; ============================================================================
;; GENERIC COMMAND DISPATCHER
;; ============================================================================
;; Check if a TinTin++ command has any arguments
;; Returns #t if arguments present, #f if just command name
(defun tintin-has-arguments? (input)
  (let ((len (length input))
        (pos 1))
    ;; Skip whitespace after #
    (do () ((or (>= pos len) (not (char=? (string-ref input pos) #\space))))
      (set! pos (+ pos 1)))
    ;; Skip command name
    (do ()
      ((or (>= pos len) (char=? (string-ref input pos) #\space)
           (char=? (string-ref input pos) #\{)))
      (set! pos (+ pos 1)))
    ;; Skip whitespace after command name
    (do () ((or (>= pos len) (not (char=? (string-ref input pos) #\space))))
      (set! pos (+ pos 1)))
    ;; If we have more characters, there are arguments
    (< pos len)))

;; Try parsing with progressively fewer arguments (for variable-arg commands)
;; Returns parsed args list or nil if all attempts fail
(defun tintin-try-parse-arguments (input max-count)
  (if (<= max-count 0)
    nil
    (let ((args (tintin-parse-arguments input max-count)))
      (if args
        args
        ;; Try with one fewer argument
        (tintin-try-parse-arguments input (- max-count 1))))))

;; Dispatch a TinTin++ command using metadata-driven approach
;; cmd-name: matched command name (e.g., "alias")
;; input: original input string (e.g., "#alias {k} {kill %1}")
(defun tintin-dispatch-command (cmd-name input)
  (let ((cmd-data (hash-ref *tintin-commands* cmd-name)))
    (if (not cmd-data)
      ;; Should never happen (tintin-find-command validated it)
      ""
      (let ((handler (list-ref cmd-data 0))
            (arg-count (list-ref cmd-data 1))
            (syntax-help (list-ref cmd-data 2)))
        ;; Check if input has any arguments after command name
        (let ((has-args (tintin-has-arguments? input)))
          (if (not has-args)
            ;; No arguments - call handler with empty list
            (handler '())
            ;; Has arguments - try parsing with max count down to 1
            (let ((args (tintin-try-parse-arguments input arg-count)))
              (if args
                (handler args)
                (progn
                  (terminal-echo (concat "Syntax error: " syntax-help "\r\n"))
                  "")))))))))

