;; tintin-highlights.lisp - Highlight application for TinTin++ emulator
;;
;; Depends on: tintin-state.lisp, tintin-colors.lisp, tintin-patterns.lisp
;; ============================================================================
;; LINE SPLITTING
;; ============================================================================
;; Split text into lines, preserving line endings
;; Returns list of lines with their line endings intact
(defun tintin-split-lines (text)
  (if (not (string? text))
    '()
    (let ((len (length text))
          (pos 0)
          (line-start 0)
          (lines '()))
      (do ()
        ((>= pos len)
         ;; Add final line if any
         (if (< line-start len)
           (reverse (cons (substring text line-start len) lines))
           (reverse lines)))
        (let ((ch (string-ref text pos)))
          (if (char=? ch #\newline)
            ;; Found line ending - add line including \n
            (progn
              (set! lines (cons (substring text line-start (+ pos 1)) lines))
              (set! pos (+ pos 1))
              (set! line-start pos))
            ;; Regular character - continue
            (set! pos (+ pos 1))))))))

;; ============================================================================
;; ANSI STATE TRACKING
;; ============================================================================
;; Extract the most recent (closest) ANSI escape sequence before a position
;; This represents the "active formatting state" at that position
;; Returns the ANSI sequence string or "" if none found or if reset encountered
(defun tintin-find-active-ansi-before (text pos)
  "Extract the active ANSI formatting state before a text position.

  ## Parameters
  - `text` - Text containing ANSI escape sequences
  - `pos` - Character position to scan before

  ## Returns
  Most recent ANSI SGR escape sequence before `pos`. Returns empty string if
  no ANSI sequence found or reset code encountered."
  (if (or (not (string? text)) (<= pos 0))
    ""
    (let ((scan-pos (- pos 1))
          (found-ansi ""))
      ;; Scan backwards looking for the FIRST (most recent) ANSI sequence
      (do () ((or (< scan-pos 0) (not (string=? found-ansi ""))) found-ansi)
        (if
          (and (>= scan-pos 0)
               (string=? (substring text scan-pos (+ scan-pos 1)) "\033")
               (< (+ scan-pos 1) (length text))
               (string=? (substring text (+ scan-pos 1) (+ scan-pos 2)) "["))
          ;; Found ESC[ - extract the complete sequence
          (let ((seq-end (+ scan-pos 2)))
            ;; Find the 'm' terminator
            (do ()
              ((or (>= seq-end (length text))
                   (string=? (substring text seq-end (+ seq-end 1)) "m")))
              (set! seq-end (+ seq-end 1)))
            ;; Check if we found a complete sequence
            (if
              (and (< seq-end (length text))
                   (string=? (substring text seq-end (+ seq-end 1)) "m"))
              (let ((sequence (substring text scan-pos (+ seq-end 1))))
                ;; Check if this is a reset code (ESC[0m or ESC[m)
                (if
                  (or (string=? sequence "\033[0m")
                      (string=? sequence "\033[m"))
                  ;; Reset code - return empty (no active formatting)
                  (set! found-ansi "reset") ; Special marker to exit and return ""
                  ;; Non-reset code - this is the active state
                  (set! found-ansi sequence))
                ;; Don't continue scanning - we found what we need
                (set! scan-pos -1))
              (set! scan-pos (- scan-pos 1))))
          ;; Not an ANSI sequence, continue backwards
          (set! scan-pos (- scan-pos 1))))
      ;; Return empty string if we found a reset, otherwise return the sequence
      (if (string=? found-ansi "reset") "" found-ansi))))

;; Find the position where matched text starts in the line
;; Returns position or -1 if not found
(defun tintin-find-match-position (line matched-text)
  (if (or (not (string? line)) (not (string? matched-text)))
    -1
    (let ((pos (string-index line matched-text))) (if pos pos -1))))

;; Check what comes immediately after a position:
;; Returns: 'reset if reset code found, 'ansi if non-reset ANSI found, 'text if regular text
(defun tintin-check-after-match (text pos)
  (if (or (not (string? text)) (>= pos (length text)))
    'text
    (let ((len (length text))
          (scan-pos pos))
      ;; Check if there's an ANSI code immediately after
      (if
        (and (< (+ scan-pos 1) len)
             (string=? (substring text scan-pos (+ scan-pos 1)) "\033")
             (< (+ scan-pos 1) len)
             (string=? (substring text (+ scan-pos 1) (+ scan-pos 2)) "["))
        ;; Found ESC[ - check what kind
        (let ((seq-end (+ scan-pos 2)))
          ;; Find the 'm' terminator
          (do ()
            ((or (>= seq-end len)
                 (string=? (substring text seq-end (+ seq-end 1)) "m")))
            (set! seq-end (+ seq-end 1)))
          ;; Check if complete sequence
          (if
            (and (< seq-end len)
                 (string=? (substring text seq-end (+ seq-end 1)) "m"))
            (let ((sequence (substring text scan-pos (+ seq-end 1))))
              (if
                (or (string=? sequence "\033[0m") (string=? sequence "\033[m"))
                'reset ; Reset code follows
                'ansi)) ; Non-reset ANSI code follows
            'text)) ; Incomplete sequence, treat as text
        ;; No ANSI code immediately after
        'text))))

;; ============================================================================
;; HIGHLIGHT WRAPPING
;; ============================================================================
;; Wrap matched pattern in line with ANSI color codes
;; Returns line with highlight applied or original line if no match
;; Now with ANSI state tracking: restores previous state unless reset follows
(defun tintin-wrap-match (line pattern fg-color bg-color)
  "Wrap matched text in line with ANSI color codes (with state tracking).

  ## Parameters
  - `line` - Line of text to process (may contain existing ANSI codes)
  - `pattern` - TinTin++ pattern to match (supports %* wildcards)
  - `fg-color` - Foreground color specification or `nil`
  - `bg-color` - Background color specification or `nil`

  ## Returns
  Line with matched text wrapped in ANSI escape codes. Returns original line
  unchanged if no match found or pattern/color invalid."
  (if (not (string? line))
    line
    (let ((regex-pattern
           (or (hash-ref *tintin-pattern-cache* pattern)
               (tintin-pattern-to-regex pattern))))
      (if (string=? regex-pattern "")
        line
        ;; Parse color spec to get ANSI codes
        (let ((fg-ansi
               (if fg-color (tintin-parse-color-component fg-color #f) nil))
              (bg-ansi
               (if bg-color (tintin-parse-color-component bg-color #t) nil)))
          ;; Build opening ANSI sequence
          (let ((ansi-open (tintin-build-ansi-code fg-ansi bg-ansi)))
            (if (string=? ansi-open "")
              line
              ;; Find the matched text
              (let ((matched-text (regex-find regex-pattern line)))
                (if matched-text
                  ;; Find where the match occurs in the line
                  (let ((match-pos
                         (tintin-find-match-position line matched-text)))
                    (if (< match-pos 0)
                      line
                      (let ((match-end-pos (+ match-pos (length matched-text))))
                        ;; Restore previous color directly (or reset if none)
                        (let ((prev-color
                               (tintin-find-active-ansi-before line match-pos)))
                          (let ((ansi-close
                                 (if (string=? prev-color "")
                                   "\033[0m"
                                   (concat "\033[0m" prev-color))))
                            (string-replace line matched-text
                             (concat ansi-open matched-text ansi-close)))))))
                  line)))))))))

;; ============================================================================
;; HIGHLIGHT APPLICATION
;; ============================================================================
;; Apply highlights to a single line
;; Returns highlighted line or original line if no highlights match
(defun tintin-highlight-line (line)
  "Apply all matching highlight patterns to a single line of text.

  ## Parameters
  - `line` - Line of text to highlight (may contain ANSI codes)

  ## Returns
  Line with ANSI color codes applied for all matching patterns."
  (if (or (not (string? line)) (= (hash-count *tintin-highlights*) 0))
    line
    (progn
      ;; Re-sort only if dirty
      (if *tintin-highlights-dirty*
        (progn
          (set! *tintin-sorted-highlights-cache*
           (tintin-sort-highlights-by-priority
            (hash-entries *tintin-highlights*)))
          (set! *tintin-highlights-dirty* #f)))
      ;; Use cached sorted list
      (let ((sorted *tintin-sorted-highlights-cache*))
        ;; Try all patterns and apply all that match
        (let ((result line))
          (do ((i 0 (+ i 1))) ((>= i (length sorted)) result)
            (let* ((entry (list-ref sorted i))
                   (pattern (car entry))
                   (data (cdr entry))
                   (fg-color (car data))
                   (bg-color (cadr data)))
              ;; Check if pattern matches the current result
              (if (tintin-match-highlight-pattern pattern result)
                ;; Apply highlight to current result (allows multiple highlights)
                (set! result
                 (tintin-wrap-match result pattern fg-color bg-color))))))))))

;; Main entry point: Apply highlights to incoming text
;; Splits text into lines, highlights each line, returns transformed text
(defun tintin-apply-highlights (text)
  "Apply color highlighting to text based on defined highlight patterns.

  ## Parameters
  - `text` - Text to process (typically server output)

  ## Returns
  Text with ANSI color codes inserted around matching patterns."
  (if (or (not (string? text)) (= (hash-count *tintin-highlights*) 0))
    text
    ;; Split into lines
    (let ((lines (tintin-split-lines text)))
      (if (null? lines)
        text
        ;; Highlight each line
        (let ((highlighted '()))
          (do ((i 0 (+ i 1)))
            ((>= i (length lines))
             ;; Join highlighted lines back together
             (let ((result ""))
               (do ((j 0 (+ j 1))) ((>= j (length highlighted)) result)
                 (set! result (concat result (list-ref highlighted j))))))
            (let ((line (list-ref lines i)))
              (set! highlighted (cons (tintin-highlight-line line) highlighted))))
          ;; Need to reverse since we cons'd in reverse order
          (set! highlighted (reverse highlighted))
          ;; Join lines
          (let ((result ""))
            (do ((k 0 (+ k 1))) ((>= k (length highlighted)) result)
              (set! result (concat result (list-ref highlighted k))))))))))

;; ============================================================================
;; ANSI POST-PROCESSING
;; ============================================================================
;; Check if an ANSI sequence is a reset code (\033[0m or \033[m)
(defun tintin-is-reset-code? (seq) (regex-match? "^\033\\[0*m$" seq))

;; Check if an ANSI sequence is an SGR code (ends with 'm')
;; SGR codes are the ones we want to track in our stack
(defun tintin-is-sgr-code? (seq) (regex-match? "^\033\\[[0-9;]*m$" seq))

;; Post-process text to handle nested ANSI states
;; Color restoration is now handled directly in tintin-wrap-match
(defun tintin-post-process-ansi-stack (text) text)

;; Recursive helper for ANSI stack processing
(defun tintin-ansi-stack-loop (text pos len result stack)
  (if (>= pos len)
    result
    (let ((char (string-ref text pos)))
      (if (char=? char #\escape) ;; ESC character
        ;; Try to parse ANSI sequence
        (let ((seq-end (tintin-find-ansi-end text pos len)))
          (if seq-end
            (let ((seq (substring text pos seq-end)))
              (if (tintin-is-reset-code? seq)
                ;; Reset code - pop from stack and potentially restore
                (if (null? stack)
                  ;; Empty stack - just pass through the reset
                  (tintin-ansi-stack-loop text seq-end len (concat result seq)
                   stack)
                  ;; Pop the top state
                  (let ((new-stack (cdr stack)))
                    (if (null? new-stack)
                      ;; Stack now empty - just output reset
                      (tintin-ansi-stack-loop text seq-end len
                       (concat result seq) new-stack)
                      ;; Stack has remaining state - output reset then restore top
                      (tintin-ansi-stack-loop text seq-end len
                       (concat result seq (car new-stack)) new-stack))))
                ;; Not a reset - check if SGR (should be pushed)
                (if (tintin-is-sgr-code? seq)
                  (tintin-ansi-stack-loop text seq-end len (concat result seq)
                   (cons seq stack))
                  ;; Non-SGR ANSI code - just pass through (don't push)
                  (tintin-ansi-stack-loop text seq-end len (concat result seq)
                   stack))))
            ;; Not a valid ANSI sequence - just add the char
            (tintin-ansi-stack-loop text (+ pos 1) len
             (concat result (char->string char)) stack)))
        ;; Regular character - just add it
        (tintin-ansi-stack-loop text (+ pos 1) len
         (concat result (char->string char)) stack)))))

;; Find the end position of an ANSI sequence starting at pos
;; Returns nil if not a valid ANSI sequence, or the end position (exclusive)
(defun tintin-find-ansi-end (text pos len)
  (if
    (and (< (+ pos 1) len) (char=? (string-ref text (+ pos 1)) #\[)) ;; '[' character
    ;; CSI sequence - find the terminator
    (tintin-find-ansi-terminator text (+ pos 2) len)
    nil))

;; Recursive helper to find ANSI terminator (scans digits and semicolons)
(defun tintin-find-ansi-terminator (text i len)
  (if (>= i len)
    nil ;; No terminator found
    (let ((c (string-ref text i)))
      (if (or (and (char>=? c #\0) (char<=? c #\9)) (char=? c #\;))
        ;; Still in parameter section, keep scanning
        (tintin-find-ansi-terminator text (+ i 1) len)
        ;; Check if this is a valid terminator (letter)
        (if
          (or (and (char>=? c #\A) (char<=? c #\Z))
              (and (char>=? c #\a) (char<=? c #\z)))
          (+ i 1) ;; Return position after terminator
          nil)))))
