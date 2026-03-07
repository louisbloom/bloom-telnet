;; tintin-read.lisp - #read command for loading TinTin++ config files
;;
;; Depends on: tintin-state.lisp, tintin-utils.lisp, tintin-parsing.lisp,
;;             tintin-commands.lisp
;; ============================================================================
;; FILE READING
;; ============================================================================
;; Read entire file into a string using read-line
(defun tintin-read-file-contents (filename)
  (let ((file (open filename "r"))
        (contents "")
        (first-line #t))
    (condition-case err
      (progn
        (let ((line (read-line file)))
          (do () ((not line))
            (if first-line
              (set! first-line #f)
              (set! contents (concat contents "\n")))
            (set! contents (concat contents line))
            (set! line (read-line file))))
        (close file)
        contents)
      (error (condition-case err2 (close file) (error nil))
       (error (concat "Failed to read file: " filename))))))

;; ============================================================================
;; COMMENT STRIPPING
;; ============================================================================
;; Remove /* ... */ block comments from text
(defun tintin-strip-block-comments (text)
  (let ((len (length text))
        (pos 0)
        (result "")
        (in-comment #f))
    (do () ((>= pos len) result)
      (if in-comment
        ;; Inside comment: look for */
        (if
          (and (< (+ pos 1) len) (char=? (string-ref text pos) #\*)
               (char=? (string-ref text (+ pos 1)) #\/))
          (progn (set! in-comment #f) (set! pos (+ pos 2)))
          (set! pos (+ pos 1)))
        ;; Outside comment: look for /*
        (if
          (and (< (+ pos 1) len) (char=? (string-ref text pos) #\/)
               (char=? (string-ref text (+ pos 1)) #\*))
          (progn (set! in-comment #t) (set! pos (+ pos 2)))
          (progn
            (set! result (concat result (char->string (string-ref text pos))))
            (set! pos (+ pos 1))))))))

;; ============================================================================
;; LINE JOINING
;; ============================================================================
;; Count net brace depth in a string
(defun tintin-brace-depth (str)
  (let ((len (length str))
        (pos 0)
        (depth 0))
    (do () ((>= pos len) depth)
      (let ((ch (string-ref str pos)))
        (cond
          ((char=? ch #\{) (set! depth (+ depth 1)))
          ((char=? ch #\}) (set! depth (- depth 1))))
        (set! pos (+ pos 1))))))

;; Check if next line is a continuation argument (starts with {)
;; In TinTin++ config files, commands like #act span multiple lines:
;;   #act {pattern}
;;   {body}
;; Even though line 1 has balanced braces, line 2 is a continuation.
(defun tintin-is-continuation-line? (line)
  (and (string? line) (> (length line) 0) (char=? (string-ref line 0) #\{)))

;; Join lines into complete commands.
;; Joins when: (a) braces are unclosed, or (b) next line starts with {
;; and current line is a # command (multi-line command arguments).
(defun tintin-join-continuation-lines (lines)
  (let ((result '())
        (current "")
        (depth 0))
    (do ((i 0 (+ i 1))) ((>= i (length lines)))
      (let ((line (list-ref lines i)))
        (if (string=? current "")
          (set! current line)
          (set! current (concat current " " line)))
        (set! depth (tintin-brace-depth current))
        (if (<= depth 0)
          ;; Braces are balanced — check if next line is a continuation
          (let ((next-i (+ i 1)))
            (if
              (and (< next-i (length lines)) (tintin-is-command? current)
                   (tintin-is-continuation-line? (list-ref lines next-i)))
              ;; Next line starts with { and we're in a # command: keep joining
              nil
              ;; Otherwise: emit this command
              (progn (set! result (cons current result)) (set! current "")
                (set! depth 0)))))))
    ;; Don't lose an incomplete last line
    (if (not (string=? current "")) (set! result (cons current result)))
    (reverse result)))

;; ============================================================================
;; CORE READER
;; ============================================================================
;; Read and process a TinTin++ commands file
(defun tintin-read-file (filename)
  ;; Read file contents
  (let* ((contents (tintin-read-file-contents filename))
         ;; Strip block comments
         (stripped (tintin-strip-block-comments contents))
         ;; Split into lines
         (raw-lines (split stripped "\n"))
         ;; Filter empty/whitespace-only lines and single-line comments
         (filtered '()))
    ;; Filter lines
    (do ((i 0 (+ i 1))) ((>= i (length raw-lines)))
      (let ((line (tintin-trim (list-ref raw-lines i))))
        (if
          (and (not (string=? line ""))
               ;; Skip lines starting with // (TinTin++ line comments)
               (not
                (and (>= (length line) 2) (char=? (string-ref line 0) #\/)
                     (char=? (string-ref line 1) #\/))))
          (set! filtered (cons line filtered)))))
    (set! filtered (reverse filtered))
    ;; Join multi-line commands (lines with unclosed braces)
    (let ((commands (tintin-join-continuation-lines filtered)))
      ;; Process each command through TinTin++ input processing
      (do ((i 0 (+ i 1))) ((>= i (length commands)))
        (let ((cmd (list-ref commands i)))
          (if (and (string? cmd) (not (string=? cmd "")))
            (tintin-process-input cmd)))))))

;; ============================================================================
;; COMMAND HANDLER
;; ============================================================================
(defun tintin-handle-read (args)
  (let ((filename (tintin-strip-braces (list-ref args 0))))
    ;; Expand ~/path if present
    (set! filename (expand-path filename))
    (condition-case err
      (progn (tintin-read-file filename)
        (terminal-echo (concat "Read '" filename "'\r\n"))
        "")
      (error
       (terminal-echo
        (concat "Failed to read '" filename "': " (error-message err) "\r\n")) ""))))

;; ============================================================================
;; COMMAND REGISTRY
;; ============================================================================
(hash-set! *tintin-commands* "read"
 (list tintin-handle-read 1 "#read {filename}"))

