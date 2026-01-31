;; tintin.lisp - TinTin++ emulator for bloom-telnet
;;
;; This is the main entry point that loads all TinTin++ modules and
;; provides the input processing hooks for the telnet client.
;;
;; ## Module Load Order
;;
;; Modules must be loaded in dependency order:
;; 1. tintin-state.lisp    - Global state and constants (no dependencies)
;; 2. tintin-utils.lisp    - Core utilities (depends on state)
;; 3. tintin-colors.lisp   - Color parsing (depends on state, utils)
;; 4. tintin-patterns.lisp - Pattern matching (depends on state)
;; 5. tintin-parsing.lisp  - Argument parsing (depends on state, utils)
;; 6. tintin-speedwalk.lisp - Speedwalk expansion (depends on state, parsing)
;; 7. tintin-highlights.lisp - Highlight application (depends on state, colors, patterns)
;; 8. tintin-actions.lisp  - Action triggering (depends on state, utils, patterns, parsing)
;; 9. tintin-aliases.lisp  - Alias expansion (depends on state, utils, patterns, parsing, speedwalk)
;; 10. tintin-tables.lisp  - Table formatting (depends on state, utils)
;; 11. tintin-save.lisp    - Save/load (depends on state, utils)
;; 12. tintin-commands.lisp - Command handlers (depends on all above)
;;
;; ============================================================================
;; LOAD MODULES
;; ============================================================================
;; Use load-system-file to search in standard lisp directories
(load-system-file "tintin-state.lisp")
(load-system-file "tintin-utils.lisp")
(load-system-file "tintin-colors.lisp")
(load-system-file "tintin-patterns.lisp")
(load-system-file "tintin-parsing.lisp")
(load-system-file "tintin-speedwalk.lisp")
(load-system-file "tintin-highlights.lisp")
(load-system-file "tintin-actions.lisp")
(load-system-file "tintin-aliases.lisp")
(load-system-file "tintin-tables.lisp")
(load-system-file "tintin-save.lisp")
(load-system-file "tintin-commands.lisp")

;; ============================================================================
;; INPUT PROCESSING
;; ============================================================================
;; Main command router with depth tracking (internal)
(defun tintin-process-command-internal (cmd depth)
  (if (or (not (string? cmd)) (string=? cmd ""))
    ""
    ;; Check if it's a # command
    (if (tintin-is-command? cmd)
      ;; TinTin++ command - dispatch (main.c handles echoing)
      (let ((cmd-name (tintin-extract-command-name cmd)))
        (if (not cmd-name)
          (progn
            (terminal-echo
             (concat "Invalid TinTin++ command format: " cmd "\r\n"))
            "")
          (let ((matched (tintin-find-command cmd-name)))
            (if (not matched)
              (progn
                (terminal-echo
                 (concat "Unknown TinTin++ command: #" cmd-name "\r\n"))
                "")
              (tintin-dispatch-command matched cmd)))))
      ;; Regular command - expand aliases
      (tintin-expand-alias cmd depth))))

(defun tintin-process-command (cmd)
  "Process a single TinTin++ command or server command.

  ## Parameters
  - `cmd` - Command string to process

  ## Returns
  - For TinTin++ commands (#...): Empty string (handled internally)
  - For regular commands: Expanded command string (after alias substitution)"
  (tintin-process-command-internal cmd 0))

;; Process a full input line (split by semicolons, process each command)
(defun tintin-process-input (input)
  "Process full input line with command separation and TinTin++ expansion.

  ## Parameters
  - `input` - Full input line from user (may contain multiple commands)

  ## Returns
  Semicolon-separated string of expanded commands ready to send to server."
  (if (not (string? input))
    ""
    (let ((commands (tintin-split-commands input))
          (results '()))
      ;; Process each command and collect results
      (do ((i 0 (+ i 1))) ((>= i (length commands)))
        (let ((processed (tintin-process-command (list-ref commands i))))
          (if (and (string? processed) (not (string=? processed "")))
            (set! results (cons processed results)))))
      ;; Reverse and join results with semicolons
      (let ((reversed-results (reverse results))
            (output ""))
        (do ((i 0 (+ i 1))) ((>= i (length reversed-results)) output)
          (set! output
           (concat output (if (> i 0) ";" "") (list-ref reversed-results i))))))))

;; ============================================================================
;; USER INPUT HOOK
;; ============================================================================
;; Hook function for user-input-hook integration
;; Signature: (lambda (text cursor-pos) -> string|nil)
;; - text: User input text
;; - cursor-pos: Cursor position (ignored for TinTin++ processing)
;; Returns: nil (hook handles echo/send) or text (when disabled)
;;
;; Hook Contract: Returns nil to indicate all echo/send handled by hook.
;; This hook processes TinTin++ commands and sends each one separately.
;; For example, "s;s" becomes two separate telnet sends: "s" and "s"
(defun tintin-user-input-hook (text cursor-pos)
  ;; Process with TinTin++ if enabled
  ;; Note: Slash commands are handled by higher-priority hooks (e.g., practice.lisp)
  (if (not *tintin-enabled*)
    () ;; TinTin++ disabled, don't handle
    ;; Empty input - don't handle, let C send blank line to server
    (if (or (not (string? text)) (string=? text ""))
      ()
      (progn
        ;; Note: main.c already echoes the original input, so we don't echo it here
        (let ((processed (tintin-process-input text))
              (commands nil))
          ;; Split processed output by semicolons
          (set! commands (tintin-split-commands processed))
          ;; Send each command separately
          (do ((i 0 (+ i 1))) ((>= i (length commands)))
            (let ((cmd (list-ref commands i)))
              (if (and (string? cmd) (not (string=? cmd "")))
                (progn
                  ;; Echo expanded command to terminal (if different from original)
                  (if
                    (and (string? cmd) (string? text) (not (string=? cmd text)))
                    (terminal-echo (concat cmd "\r\n")))
                  ;; Send to telnet server with error handling
                  (condition-case err
                    (progn
                      ;; Check if we can send (connected or test mode)
                      (let ((can-send
                             (condition-case err2
                               ;; Try to check connection mode
                               (or (eq? *connection-mode* 'conn)
                                   ;; If *connection-mode* undefined (test mode), check if telnet-send exists
                                   (and (symbol? 'telnet-send) #t))
                               ;; If *connection-mode* not defined, we're in test mode
                               (error #t))))
                        (if can-send
                          ;; Send the command
                          (telnet-send cmd)
                          ;; Not connected
                          (terminal-echo "\r\n*** Not connected ***\r\n"))))
                    ;; Catch any send errors
                    (error
                     (terminal-echo
                      (concat "\r\n*** Send failed: " (error-message err)
                       " ***\r\n")))))))))
        ;; Mark as handled via hook system
        (set! *user-input-handled* #t)
        (set! *user-input-result* nil)))))

;; ============================================================================
;; TOGGLE FUNCTIONS
;; ============================================================================
(defun tintin-toggle! ()
  "Toggle TinTin++ processing on or off."
  (set! *tintin-enabled* (not *tintin-enabled*))
  (terminal-echo
   (concat "TinTin++ " (if *tintin-enabled* "enabled" "disabled") "\r\n"))
  *tintin-enabled*)

(defun tintin-enable! ()
  "Enable TinTin++ processing."
  (set! *tintin-enabled* #t)
  (terminal-echo "TinTin++ enabled\r\n")
  #t)

(defun tintin-disable! ()
  "Disable TinTin++ processing."
  (set! *tintin-enabled* #f)
  (terminal-echo "TinTin++ disabled\r\n")
  #f)

;; ============================================================================
;; TELNET INPUT HOOKS
;; ============================================================================
;; Hook function for telnet-input-filter-hook integration
;; Signature: (lambda (text) -> string)
;; - text: Incoming telnet data (may contain ANSI codes)
;; Returns: Transformed text with highlights applied
;;
;; This hook receives data from the telnet server before it's displayed
;; in the terminal. We apply highlight patterns to colorize matching text.
;; After applying highlights, we post-process to handle nested ANSI states
;; so that server reset codes don't kill highlight colors.
(defun tintin-telnet-input-filter (text)
  (if (and *tintin-enabled* (> (hash-count *tintin-highlights*) 0))
    (tintin-apply-highlights text)
    text))

;; TinTin++ telnet input hook handler for triggering actions
;; This hook is called when data arrives from the telnet server
;; It sees stripped text (no ANSI codes), better for pattern matching
(defun tintin-telnet-input-hook (text)
  "Process telnet input for TinTin++ action triggering.
   Called via telnet-input-hook for each chunk of server output."
  (if
    (and *tintin-enabled* (not *tintin-action-executing*)
         (> (hash-count *tintin-actions*) 0))
    (let ((lines (tintin-split-lines text)))
      (do ((i 0 (+ i 1))) ((>= i (length lines)))
        (tintin-trigger-actions-for-line (list-ref lines i))))))

;; ============================================================================
;; AUTO-ACTIVATION
;; ============================================================================
;; Register TinTin++ user input hook via the extensible hook system
(add-hook 'user-input-hook 'tintin-user-input-hook)
;; Install telnet-input-filter-hook (use add-hook to chain with other filters)
(add-hook 'telnet-input-filter-hook 'tintin-telnet-input-filter)
;; Install telnet-input-hook (use add-hook to chain with other hooks)
(add-hook 'telnet-input-hook 'tintin-telnet-input-hook)

;; Announce activation (terminal is ready when this file loads via -l)
(script-echo "TinTin++ emulation active")

