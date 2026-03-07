;; tintin-speedwalk.lisp - Speedwalk expansion for TinTin++ emulator
;;
;; Depends on: tintin-state.lisp, tintin-parsing.lisp
;; ============================================================================
;; SPEEDWALK EXPANSION
;; ============================================================================
;; Check if a string is a valid direction
(defun tintin-is-direction? (str)
  (or (string=? str "n") (string=? str "e") (string=? str "s")
      (string=? str "w") (string=? str "u") (string=? str "d")
      (and *tintin-speedwalk-diagonals*
           (or (string=? str "ne") (string=? str "nw") (string=? str "se")
               (string=? str "sw")))))

;; Expand speedwalk string like "3n2e" to "n;n;n;e;e"
(defun tintin-expand-speedwalk (input)
  "Expand speedwalk syntax into individual movement commands.

  ## Parameters
  - `input` - Input string potentially containing speedwalk syntax

  ## Description
  Converts compact movement notation into expanded movement commands separated
  by semicolons. Speedwalk syntax uses numeric prefixes to repeat directions:

  **Syntax:**
  - `n`, `s`, `e`, `w`, `u`, `d` - Single direction commands
  - `3n` - Repeat north 3 times (expands to `n;n;n`)
  - `2e3n` - Move east twice, then north 3 times (expands to `e;e;n;n;n`)
  - Diagonal directions (if `*tintin-speedwalk-diagonals*` is enabled):
    `ne`, `nw`, `se`, `sw`

  **Behavior:**
  - If speedwalk is disabled (`*tintin-speedwalk-enabled*` = `#f`): returns input unchanged
  - If input contains invalid syntax: returns input unchanged
  - If all syntax is valid: returns expanded commands joined with semicolons

  ## Returns
  - If valid speedwalk: Expanded command string (e.g., `\"n;n;n;e;e\"`)
  - If invalid or disabled: Original input string unchanged

  ## Examples
  ```lisp
  (tintin-expand-speedwalk \"3n2e\")
  ; => \"n;n;n;e;e\"

  (tintin-expand-speedwalk \"n\")
  ; => \"n\"

  (tintin-expand-speedwalk \"nsew\")
  ; => \"n;s;e;w\"
  ```"
  (if (or (not (string? input)) (not *tintin-speedwalk-enabled*))
    input
    (let ((len (length input))
          (pos 0)
          (result '())
          (valid #t))
      (do () ((>= pos len))
        (let ((count-str "")
              (direction ""))
          ;; Collect digits for count
          (do ()
            ((or (>= pos len)
                 (not (tintin-is-digit? (substring input pos (+ pos 1)))))
             nil)
            (set! count-str (concat count-str (substring input pos (+ pos 1))))
            (set! pos (+ pos 1)))
          ;; Get direction (1 or 2 characters)
          (if (< pos len)
            (let ((ch1 (substring input pos (+ pos 1))))
              ;; Try 2-char direction first (only if diagonals enabled)
              (if
                (and *tintin-speedwalk-diagonals* (< (+ pos 1) len)
                     (tintin-is-direction?
                      (concat ch1 (substring input (+ pos 1) (+ pos 2)))))
                (progn
                  (set! direction
                   (concat ch1 (substring input (+ pos 1) (+ pos 2))))
                  (set! pos (+ pos 2)))
                ;; Try 1-char direction
                (if (tintin-is-direction? ch1)
                  (progn (set! direction ch1) (set! pos (+ pos 1)))
                  ;; Not a valid direction - mark as invalid
                  (progn (set! valid #f) (set! pos (+ pos 1)))))))
          ;; Expand direction N times (only if we found a valid direction)
          (if (not (string=? direction ""))
            (let ((count
                   (if (string=? count-str "") 1 (string->number count-str))))
              (do ((i 0 (+ i 1))) ((>= i count))
                (set! result (cons direction result)))))))
      ;; Return original input if any part was invalid, otherwise return expanded
      (if (not valid)
        input
        ;; Join results with semicolons
        (let ((reversed (reverse result))
              (output ""))
          (do ((i 0 (+ i 1))) ((>= i (length reversed)) output)
            (set! output
             (concat output (if (> i 0) ";" "") (list-ref reversed i)))))))))
