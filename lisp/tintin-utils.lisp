;; tintin-utils.lisp - Core utility functions for TinTin++ emulator
;;
;; Depends on: tintin-state.lisp
;; ============================================================================
;; STRING UTILITIES
;; ============================================================================
;; Helper: Find first non-whitespace character index
(defun tintin-find-first-non-ws (str pos len)
  (if (>= pos len)
    pos
    (let ((ch (string-ref str pos)))
      (if
        (or (char=? ch #\space) (char=? ch #\tab) (char=? ch #\return)
            (char=? ch #\newline))
        (tintin-find-first-non-ws str (+ pos 1) len)
        pos))))

;; Helper: Find last non-whitespace character index
(defun tintin-find-last-non-ws (str pos)
  (if (< pos 0)
    -1
    (let ((ch (string-ref str pos)))
      (if
        (or (char=? ch #\space) (char=? ch #\tab) (char=? ch #\return)
            (char=? ch #\newline))
        (tintin-find-last-non-ws str (- pos 1))
        pos))))

;; Helper: Trim leading and trailing whitespace from string
(defun tintin-trim (str)
  "Remove leading and trailing whitespace from string.

  ## Parameters
  - `str` - String to trim

  ## Returns
  String with leading and trailing whitespace removed. Returns empty string `\"\"`
  if input is invalid or all whitespace.

  ## Description
  Removes space, tab, carriage return, and newline characters from both ends
  of the string. Uses two-pass algorithm: find first non-whitespace character
  from start, then find last non-whitespace character from end, and extract
  substring between them.

  **Whitespace characters**: space, tab (`\\t`), carriage return (`\\r`),
  newline (`\\n`)

  ## Examples
  ```lisp
  (tintin-trim \"  hello  \")
  ; => \"hello\"

  (tintin-trim \"\\t\\n hello world \\r\\n\")
  ; => \"hello world\"
  ```"
  (if (not (string? str))
    ""
    (let ((len (length str)))
      (if (= len 0)
        ""
        ;; Find first non-whitespace character
        (let ((start (tintin-find-first-non-ws str 0 len)))
          (if (>= start len)
            "" ; All whitespace
            ;; Find last non-whitespace character
            (let ((end (tintin-find-last-non-ws str (- len 1))))
              (substring str start (+ end 1)))))))))

;; ============================================================================
;; BRACE/STRING UTILITIES
;; ============================================================================
;; Strip outer braces from a string if present
;; Example: "{text}" → "text", "text" → "text", "{a{b}c}" → "a{b}c"
(defun tintin-strip-braces (str)
  (if (not (string? str))
    str
    (let ((len (length str)))
      (if
        (and (> len 1) (char=? (string-ref str 0) #\{)
             (char=? (string-ref str (- len 1)) #\}))
        (substring str 1 (- len 1))
        str))))

;; Helper: Find first occurrence of character in string
;; Returns position or nil if not found
;; ch should be a character (e.g., #\:)
(defun tintin-string-find-char (str ch)
  (let ((len (length str))
        (pos 0)
        (found nil))
    (do () ((or (>= pos len) found) found)
      (if (char=? (string-ref str pos) ch)
        (set! found pos)
        (set! pos (+ pos 1))))))

;; Check if character is valid in variable name: [a-zA-Z0-9_-]
(defun tintin-is-varname-char? (ch)
  (or (and (char>=? ch #\a) (char<=? ch #\z))
      (and (char>=? ch #\A) (char<=? ch #\Z))
      (and (char>=? ch #\0) (char<=? ch #\9)) (char=? ch #\_) (char=? ch #\-)))
