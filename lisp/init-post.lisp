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
  (script-echo (concat "bloom-telnet " *version*) ":help for commands"
   term-info))

