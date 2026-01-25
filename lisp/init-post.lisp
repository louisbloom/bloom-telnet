;; init-post.lisp - Post-initialization setup for bloom-telnet
;;
;; This file is loaded after init.lisp and after the system is ready.
;; For a TUI client, this file handles any startup messages and hooks
;; that need the main loop to be running.
;; ============================================================================
;; HELPER FUNCTIONS FOR DISPLAY
;; ============================================================================
;; Calculate visual display length of string, excluding ANSI escape codes
(defun visual-length (str)
  (if (not (string? str))
    0
    (let ((ansi-pattern "\\033\\[[0-9;]*m"))
      (length (regex-replace-all ansi-pattern str "")))))

;; Pad string to specified width with trailing spaces
(defun pad-string (str width)
  (if (not (string? str))
    ""
    (let ((visual-len (visual-length str)))
      (let ((padding-needed (- width visual-len)))
        (if (<= padding-needed 0)
          str
          (let ((result str))
            (do ((i 0 (+ i 1))) ((>= i padding-needed) result)
              (set! result (concat result " ")))))))))

;; Repeat a string N times
(defun repeat-string (str count)
  (if (<= count 0)
    ""
    (let ((result ""))
      (do ((i 0 (+ i 1))) ((>= i count) result)
        (set! result (concat result str))))))

;; ============================================================================
;; STARTUP MESSAGE
;; ============================================================================
;; Display simple startup info with capability-aware colors
;; Helper function to get appropriate color for startup message
(defun startup-color () (terminal-best-fg-color 100 149 237)) ; Cornflower blue

(defun startup-reset () (terminal-reset-color))

;; Display startup message with adaptive coloring
(terminal-echo (startup-color))
(terminal-echo "Lisp scripting enabled.\r\n")
(terminal-echo "  Tab completion from telnet output\r\n")
(terminal-echo "  Hook system for extensibility\r\n")
(terminal-echo "  Timer support for automation\r\n")

;; Show terminal capability summary if color is supported
(if (> (terminal-color-level) 0)
  (progn (terminal-echo "  Terminal: ") (terminal-echo (terminal-type))
    (terminal-echo " (")
    (let ((level (terminal-color-level)))
      (cond
        ((= level 4) (terminal-echo "truecolor"))
        ((= level 3) (terminal-echo "256-color"))
        ((= level 2) (terminal-echo "16-color"))
        (t (terminal-echo "8-color"))))
    (terminal-echo ")\r\n")))

(terminal-echo (startup-reset))

