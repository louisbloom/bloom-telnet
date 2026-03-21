;; tintin-tables.lisp - Table formatting for TinTin++ emulator
;;
;; Depends on: tintin-state.lisp, tintin-utils.lisp
;; ============================================================================
;; ALPHABETICAL SORTING
;; ============================================================================
;; Sort alias entries alphabetically by name
;; Input: list of (name . (commands priority)) pairs
;; Output: sorted list alphabetically by name
(defun tintin-sort-aliases-alphabetically (alias-list)
  "Sort alias entries alphabetically by name for display."
  (if (or (null? alias-list) (= (length alias-list) 0))
    '()
    ;; Simple insertion sort by name
    (let ((sorted '()))
      (do ((remaining alias-list (cdr remaining))) ((null? remaining) sorted)
        (let ((entry (car remaining))
              (name (caar remaining)))
          ;; Insert entry in alphabetically sorted position
          (set! sorted (tintin-insert-alias-alphabetically entry name sorted)))))))

;; Helper: Insert alias entry into sorted list alphabetically by name
(defun tintin-insert-alias-alphabetically (entry name sorted-list)
  (if (null? sorted-list)
    (list entry)
    (let ((first-entry (car sorted-list))
          (first-name (caar sorted-list)))
      (if (string<? name first-name)
        ;; Insert before first entry
        (cons entry sorted-list)
        ;; Insert later in list
        (cons first-entry
         (tintin-insert-alias-alphabetically entry name (cdr sorted-list)))))))

;; Sort highlight entries alphabetically by pattern
(defun tintin-sort-highlights-alphabetically (highlight-list)
  "Sort highlight entries alphabetically by pattern for display."
  (if (or (null? highlight-list) (= (length highlight-list) 0))
    '()
    ;; Simple insertion sort by pattern
    (let ((sorted '()))
      (do ((remaining highlight-list (cdr remaining)))
        ((null? remaining) sorted)
        (let ((entry (car remaining))
              (pattern (caar remaining)))
          ;; Insert entry in alphabetically sorted position
          (set! sorted
           (tintin-insert-highlight-alphabetically entry pattern sorted)))))))

;; Helper: Insert highlight entry into sorted list alphabetically by pattern
(defun tintin-insert-highlight-alphabetically (entry pattern sorted-list)
  (if (null? sorted-list)
    (list entry)
    (let ((first-entry (car sorted-list))
          (first-pattern (caar sorted-list)))
      (if (string<? pattern first-pattern)
        ;; Insert before first entry
        (cons entry sorted-list)
        ;; Insert later in list
        (cons first-entry
         (tintin-insert-highlight-alphabetically entry pattern
          (cdr sorted-list)))))))

;; Sort action entries alphabetically by pattern
(defun tintin-sort-actions-alphabetically (action-list)
  "Sort action entries alphabetically by pattern for display."
  (if (or (null? action-list) (= (length action-list) 0))
    '()
    ;; Simple insertion sort by pattern
    (let ((sorted '()))
      (do ((remaining action-list (cdr remaining)))
        ((null? remaining) sorted)
        (let ((entry (car remaining))
              (pattern (caar remaining)))
          ;; Insert entry in alphabetically sorted position
          (set! sorted
           (tintin-insert-action-alphabetically entry pattern sorted)))))))

;; Helper: Insert action entry into sorted list alphabetically by pattern
(defun tintin-insert-action-alphabetically (entry pattern sorted-list)
  (if (null? sorted-list)
    (list entry)
    (let ((first-entry (car sorted-list))
          (first-pattern (caar sorted-list)))
      (if (string<? pattern first-pattern)
        ;; Insert before first entry
        (cons entry sorted-list)
        ;; Insert later in list
        (cons first-entry
         (tintin-insert-action-alphabetically entry pattern (cdr sorted-list)))))))

;; Sort custom color entries alphabetically by name
(defun tintin-sort-colors-alphabetically (color-list)
  "Sort custom color entries alphabetically by name for display."
  (if (or (null? color-list) (= (length color-list) 0))
    '()
    (let ((sorted '()))
      (do ((remaining color-list (cdr remaining))) ((null? remaining) sorted)
        (let ((entry (car remaining))
              (name (caar remaining)))
          (set! sorted (tintin-insert-color-alphabetically entry name sorted)))))))

;; Helper: Insert color entry into sorted list alphabetically by name
(defun tintin-insert-color-alphabetically (entry name sorted-list)
  (if (null? sorted-list)
    (list entry)
    (let ((first-entry (car sorted-list))
          (first-name (caar sorted-list)))
      (if (string<? name first-name)
        (cons entry sorted-list)
        (cons first-entry
         (tintin-insert-color-alphabetically entry name (cdr sorted-list)))))))

;; ============================================================================
;; TABLE FORMATTING UTILITIES
;; ============================================================================
;; Repeat a string N times
(defun tintin-repeat-string (str count)
  "Repeat a string N times."
  (let ((result ""))
    (do ((i 0 (+ i 1))) ((>= i count) result)
      (set! result (concat result str)))))

;; Get visual length of string, excluding ANSI escape sequences
;; This is critical for table alignment with colored text
(defun tintin-visual-length (str)
  "Calculate visual display length of string, excluding ANSI escape codes."
  (if (not (string? str))
    0
    (let ((ansi-pattern "\\033\\[[0-9;]*m"))
      (length (regex-replace-all ansi-pattern str "")))))

;; Pad string to specified width with spaces
(defun tintin-pad-string (str width)
  "Pad string to specified width with trailing spaces."
  (if (not (string? str))
    ""
    (let ((visual-len (tintin-visual-length str)))
      (let ((padding-needed (- width visual-len)))
        (if (<= padding-needed 0)
          str
          (let ((result str))
            (do ((i 0 (+ i 1))) ((>= i padding-needed) result)
              (set! result (concat result " ")))))))))

;; Find best position to break text near width boundary
;; Returns position to break at (searches backwards for space/hyphen)
(defun tintin-find-break-point (text width)
  (if (<= (tintin-visual-length text) width)
    (length text)
    (let* ((text-len (length text))
           (start-pos (if (< width text-len) width (- text-len 1))))
      ;; Search backwards from width (or text end) for space or hyphen
      (do ((i start-pos (- i 1)))
        ((or (< i 0)
             (and (< i text-len) ; Bounds check
                  (let ((ch (string-ref text i)))
                    (or (char=? ch #\space) (char=? ch #\-)
                        (char=? ch #\newline)))))
         (if (< i 0)
           (if (< width text-len) width text-len) ; Hard break at width or text end
           (+ i 1))))))) ; Break after space/hyphen

;; Wrap text to fit within width, returning list of lines
(defun tintin-wrap-text (text width)
  "Wrap text to fit within specified width, breaking at word boundaries."
  (if (or (not (string? text)) (= (tintin-visual-length text) 0))
    '("")
    ;; Guard against invalid width
    (if (<= width 0)
      (list text) ; Return as-is if width is too small
      (if (<= (tintin-visual-length text) width)
        (list text)
        ;; Find break point and split
        (let* ((break-pos (tintin-find-break-point text width))
               ;; Ensure we always make progress (at least 1 char)
               (safe-break-pos (if (<= break-pos 0) 1 break-pos))
               (line1-raw (substring text 0 safe-break-pos))
               ;; Strip trailing spaces from line1 (they get added as padding later)
               (line1-len (length line1-raw))
               (line1-end line1-len)
               (line1
                (progn
                  ;; Find last non-space character
                  (do ()
                    ((or (<= line1-end 0)
                         (not
                          (char=? (string-ref line1-raw (- line1-end 1))
                           #\space))))
                    (set! line1-end (- line1-end 1)))
                  (if (= line1-end line1-len)
                    line1-raw ; No trailing spaces
                    (substring line1-raw 0 line1-end)))) ; Strip trailing spaces
               (rest-start safe-break-pos)
               ;; Skip leading space in rest
               (rest-start-adj
                (if
                  (and (< rest-start (length text))
                       (char=? (string-ref text rest-start) #\space))
                  (+ rest-start 1)
                  rest-start)))
          (if (>= rest-start-adj (length text))
            (list line1)
            (let ((rest (substring text rest-start-adj (length text))))
              (cons line1 (tintin-wrap-text rest width)))))))))

;; ============================================================================
;; TABLE BORDER DRAWING
;; ============================================================================
;; Draw generic table border for any number of columns
;; widths: list of column widths
;; position: 'top, 'middle, or 'bottom
;; Returns: border string with Unicode box-drawing characters
(defun tintin-draw-border (widths position)
  "Draw Unicode box-drawing border for table with specified column widths."
  (if (or (null? widths) (= (length widths) 0))
    ""
    (let* ((chars
            (cond
              ((eq? position 'top) '("┌" "┬" "┐"))
              ((eq? position 'middle) '("├" "┼" "┤"))
              ((eq? position 'bottom) '("└" "┴" "┘"))
              (#t '("├" "┼" "┤")))) ; default to middle
           (left (car chars))
           (middle (list-ref chars 1))
           (right (list-ref chars 2))
           (line left))
      ;; Build border: left + (─*width1) + middle + (─*width2) + ... + right
      (do ((i 0 (+ i 1))) ((>= i (length widths)))
        (let ((width (list-ref widths i)))
          ;; Add horizontal line segment
          (set! line (concat line "─" (tintin-repeat-string "─" width) "─"))
          ;; Add junction or right cap
          (if (< (+ i 1) (length widths))
            (set! line (concat line middle))
            (set! line (concat line right)))))
      (concat line "\r\n"))))

;; Draw table row with wrapping support
;; cells: list of cell values (strings)
;; widths: list of column widths
;; Returns: list of display lines for this logical row
(defun tintin-draw-row (cells widths)
  "Draw a table row with multi-line cell support and Unicode borders."
  (if (or (null? cells) (null? widths))
    '("")
    (let ((wrapped-cells '())
          (max-lines 0))
      ;; Step 1: Wrap each cell to its column width
      (do ((i 0 (+ i 1))) ((>= i (length cells)))
        (let ((cell (list-ref cells i))
              (width (list-ref widths i)))
          (let ((wrapped (tintin-wrap-text cell width)))
            (set! wrapped-cells (cons wrapped wrapped-cells))
            ;; Track max lines needed
            (if (> (length wrapped) max-lines)
              (set! max-lines (length wrapped))))))
      ;; Reverse to restore original order
      (set! wrapped-cells (reverse wrapped-cells))
      ;; Step 2: Build each display line
      (let ((result '()))
        (do ((line-idx 0 (+ line-idx 1)))
          ((>= line-idx max-lines) (reverse result))
          (let ((line "│ "))
            ;; Build this display line from all columns
            (do ((col-idx 0 (+ col-idx 1))) ((>= col-idx (length cells)))
              (let* ((wrapped-cell (list-ref wrapped-cells col-idx))
                     (width (list-ref widths col-idx))
                     ;; Get text for this line (or empty if this cell has fewer lines)
                     (text
                      (if (< line-idx (length wrapped-cell))
                        (list-ref wrapped-cell line-idx)
                        ""))
                     (padded (tintin-pad-string text width)))
                (set! line (concat line padded))
                ;; Add separator or end cap
                (if (< (+ col-idx 1) (length cells))
                  (set! line (concat line " │ "))
                  (set! line (concat line " │\r\n")))))
            (set! result (cons line result))))))))

;; ============================================================================
;; COLUMN WIDTH CALCULATION
;; ============================================================================
;; Calculate optimal column widths that fit within max-width
;; data: list of lists (rows x columns)
;; max-width: terminal width in characters (from terminal-info)
;; min-col-width: minimum width per column (default 8)
;; Returns: list of column widths that fit within max-width
(defun tintin-calculate-optimal-widths (data max-width min-col-width)
  "Calculate optimal column widths that fit within terminal width."
  (if (or (null? data) (= (length data) 0))
    '()
    (let ((num-cols (length (car data)))
          (col-maxes (make-vector (length (car data)) 0)))
      ;; Step 1: Find max visual width for each column
      (do ((i 0 (+ i 1))) ((>= i (length data)))
        (let ((row (list-ref data i)))
          (do ((j 0 (+ j 1))) ((>= j (length row)))
            (let ((cell (list-ref row j)))
              (let ((cell-width (tintin-visual-length cell))
                    (current-max (vector-ref col-maxes j)))
                (if (> cell-width current-max)
                  (vector-set! col-maxes j cell-width)))))))
      ;; Step 2: Calculate total needed width
      ;; formula: sum(widths) + (num-cols + 1) + (num-cols - 1) * 3
      (let ((content-width 0))
        ;; Sum up column widths
        (do ((k 0 (+ k 1))) ((>= k num-cols))
          (set! content-width (+ content-width (vector-ref col-maxes k))))
        (let* ((border-width 4) ; Left "│ " (2) + right " │" (2)
               (separator-width (* (- num-cols 1) 3))
               (total-width (+ content-width border-width separator-width)))
          ;; Step 3: Scale based on whether table fits
          (if (<= total-width max-width)
            ;; Case A: Fits naturally - scale UP to fill terminal
            (let ((available (- max-width border-width separator-width))
                  (result '()))
              (do ((k 0 (+ k 1))) ((>= k num-cols) (reverse result))
                (let* ((natural (vector-ref col-maxes k))
                       ;; Scale up proportionally
                       (scaled (quotient (* natural available) content-width)))
                  (set! result (cons scaled result)))))
            ;; Case B: Doesn't fit - scale DOWN with constraints
            (let ((available (- max-width border-width separator-width)))
              ;; New algorithm: separate small (< 8) and large (>= 8) columns
              (let ((widths (make-vector num-cols 0))
                    (small-cols '())
                    (large-cols '())
                    (small-total 0)
                    (large-natural-total 0))
                ;; Step 1: Categorize columns
                (do ((k 0 (+ k 1))) ((>= k num-cols))
                  (let ((natural (vector-ref col-maxes k)))
                    (if (< natural min-col-width)
                      (set! small-cols (cons k small-cols))
                      (progn (set! large-cols (cons k large-cols))
                        (set! large-natural-total
                         (+ large-natural-total natural))))))
                ;; Step 2: Small columns keep natural width (no scaling)
                (let ((iter-small small-cols))
                  (do () ((null? iter-small))
                    (let* ((k (car iter-small))
                           (natural (vector-ref col-maxes k)))
                      (vector-set! widths k natural)
                      (set! small-total (+ small-total natural))
                      (set! iter-small (cdr iter-small)))))
                ;; Step 3: Allocate remaining to large columns (min=8)
                (let ((large-available (- available small-total)))
                  (if (not (null? large-cols))
                    ;; Distribute to large columns
                    (let ((iter-large large-cols))
                      (do () ((null? iter-large))
                        (let* ((k (car iter-large))
                               (natural (vector-ref col-maxes k))
                               (scaled
                                (if (= large-natural-total 0)
                                  min-col-width ; Avoid division by zero
                                  (quotient (* natural large-available)
                                   large-natural-total)))
                               (final
                                (if (> scaled min-col-width)
                                  scaled
                                  min-col-width)))
                          (vector-set! widths k final)
                          (set! iter-large (cdr iter-large)))))))
                ;; Convert vector to list
                (let ((result '()))
                  (do ((k 0 (+ k 1))) ((>= k num-cols) (reverse result))
                    (set! result (cons (vector-ref widths k) result))))))))))))

;; ============================================================================
;; GENERIC TABLE PRINTER
;; ============================================================================
;; Print formatted table from list of lists
;; data: ((header1 header2 ...) (row1-col1 row1-col2 ...) ...)
;; First list is treated as headers (rendered in bold)
;; Automatically detects terminal width and optimizes column layout
(defun tintin-print-table (data &optional row-separators)
  "Print a formatted table with Unicode box-drawing characters."
  ;; Default row-separators to #t if not provided
  (let ((row-sep (or row-separators #t)))
    (if (or (null? data) (= (length data) 0))
      (terminal-echo "Error: Table data cannot be empty")
      (let* ((term-cols (termcap 'cols))
             (min-col-width 8)
             (headers (car data))
             (rows (cdr data))
             (all-rows data))
        ;; Validate that we have at least headers
        (if (or (null? headers) (= (length headers) 0))
          (terminal-echo "Error: Table must have at least header row")
          (let ((widths
                 (tintin-calculate-optimal-widths all-rows term-cols
                  min-col-width)))
            ;; Draw top border
            (terminal-echo (tintin-draw-border widths 'top))
            ;; Draw header row (with bold formatting)
            (let ((bold-headers '()))
              ;; Add bold formatting to each header (truncate if too long for column)
              (do ((i 0 (+ i 1))) ((>= i (length headers)))
                (let* ((header (list-ref headers i))
                       (col-width (list-ref widths i))
                       (header-len (tintin-visual-length header))
                       ;; Truncate header if longer than column width
                       (truncated
                        (if (> header-len col-width)
                          (substring header 0 col-width)
                          header)))
                  (set! bold-headers
                   (cons (concat "\033[1m" truncated "\033[0m") bold-headers))))
              (set! bold-headers (reverse bold-headers))
              ;; Draw header lines
              (let ((header-lines (tintin-draw-row bold-headers widths)))
                (do ((i 0 (+ i 1))) ((>= i (length header-lines)))
                  (terminal-echo (list-ref header-lines i)))))
            ;; Draw middle border
            (terminal-echo (tintin-draw-border widths 'middle))
            ;; Draw data rows (with wrapping if needed)
            (do ((row-idx 0 (+ row-idx 1))) ((>= row-idx (length rows)))
              (let* ((row (list-ref rows row-idx))
                     (row-lines (tintin-draw-row row widths)))
                (do ((line-idx 0 (+ line-idx 1)))
                  ((>= line-idx (length row-lines)))
                  (terminal-echo (list-ref row-lines line-idx))))
              ;; Draw separator after each row (except the last row)
              (if (and row-sep (< (+ row-idx 1) (length rows)))
                (terminal-echo (tintin-draw-border widths 'middle))))
            ;; Draw bottom border
            (terminal-echo (tintin-draw-border widths 'bottom))))))))

;; ============================================================================
;; LIST COMMANDS
;; ============================================================================
;; List all defined aliases
(defun tintin-list-aliases ()
  "Display formatted table of all defined aliases."
  (let ((alias-entries (hash-entries *tintin-aliases*))
        (count (hash-count *tintin-aliases*)))
    (if (= count 0)
      (progn (terminal-echo "No aliases defined.\r\n") "")
      (progn
        (terminal-echo (concat "Aliases (" (number->string count) "):\r\n"))
        ;; Sort aliases alphabetically
        (let ((sorted (tintin-sort-aliases-alphabetically alias-entries)))
          ;; Build data structure: headers + data rows
          (let ((data (list (list "Name" "Commands" "P"))))
            ;; Add data rows
            (do ((i 0 (+ i 1))) ((>= i (length sorted)))
              (let* ((entry (list-ref sorted i))
                     (name (car entry))
                     (value (cdr entry))
                     (commands (car value))
                     (priority (cadr value))
                     (priority-str (number->string priority)))
                (set! data
                 (append data (list (list name commands priority-str))))))
            ;; Print table using generic printer
            (tintin-print-table data)))
        ""))))

;; List all defined variables
(defun tintin-list-variables ()
  "Display formatted table of all defined variables."
  (let ((var-entries (hash-entries *tintin-variables*))
        (count (hash-count *tintin-variables*)))
    (if (= count 0)
      (progn (terminal-echo "No variables defined.\r\n") "")
      (progn
        (terminal-echo (concat "Variables (" (number->string count) "):\r\n"))
        ;; Build data structure: headers + data rows
        (let ((data (list (list "Variable" "Value"))))
          ;; Add data rows
          (do ((i 0 (+ i 1))) ((>= i (length var-entries)))
            (let* ((entry (list-ref var-entries i))
                   (name (car entry))
                   (value (cdr entry)))
              (set! data (append data (list (list name value))))))
          ;; Print table using generic printer
          (tintin-print-table data))
        ""))))

;; List all defined highlights (sorted alphabetically)
(defun tintin-list-highlights ()
  "Display formatted table of all defined highlights."
  (let ((highlight-entries (hash-entries *tintin-highlights*))
        (count (hash-count *tintin-highlights*)))
    (if (= count 0)
      (progn (terminal-echo "No highlights defined.\r\n") "")
      (progn
        (terminal-echo (concat "Highlights (" (number->string count) "):\r\n"))
        ;; Sort alphabetically before displaying
        (let ((sorted (tintin-sort-highlights-alphabetically highlight-entries)))
          ;; Build data structure: headers + data rows
          (let ((data (list (list "Pattern" "Color" "P"))))
            ;; Add data rows
            (do ((i 0 (+ i 1))) ((>= i (length sorted)))
              (let* ((entry (list-ref sorted i))
                     (pattern (car entry))
                     (entry-data (cdr entry))
                     (fg-color (car entry-data))
                     (bg-color (cadr entry-data))
                     (priority (caddr entry-data))
                     (color-str
                      (concat (if fg-color fg-color "")
                       (if (and fg-color bg-color) ":" "")
                       (if bg-color bg-color "")))
                     (priority-str (number->string priority)))
                (set! data
                 (append data (list (list pattern color-str priority-str))))))
            ;; Print table using generic printer
            (tintin-print-table data)))
        ""))))

;; List all defined custom colors (sorted alphabetically)
(defun tintin-list-colors ()
  "Display formatted table of all defined custom colors."
  (let ((color-entries (hash-entries *tintin-custom-colors*))
        (count (hash-count *tintin-custom-colors*)))
    (if (= count 0)
      (progn (terminal-echo "No custom colors defined.\r\n") "")
      (progn
        (terminal-echo (concat "Colors (" (number->string count) "):\r\n"))
        ;; Sort alphabetically before displaying
        (let ((sorted (tintin-sort-colors-alphabetically color-entries)))
          ;; Build data structure: headers + data rows
          (let ((data (list (list "Name" "Color" "Preview"))))
            ;; Add data rows
            (do ((i 0 (+ i 1))) ((>= i (length sorted)))
              (let* ((entry (list-ref sorted i))
                     (name (car entry))
                     (spec (cdr entry))
                     ;; Build preview: apply color to sample text
                     (parsed (tintin-parse-color-spec spec))
                     (fg-codes (car parsed))
                     (bg-codes (cadr parsed))
                     (ansi-open (tintin-build-ansi-code fg-codes bg-codes))
                     (preview (concat ansi-open "sample" "\033[0m")))
                (set! data (append data (list (list name spec preview))))))
            ;; Print table using generic printer
            (tintin-print-table data)))
        ""))))

;; List all defined actions (sorted alphabetically)
(defun tintin-list-actions ()
  "Display formatted table of all defined actions."
  (let ((action-entries (hash-entries *tintin-actions*))
        (count (hash-count *tintin-actions*)))
    (if (= count 0)
      (progn (terminal-echo "No actions defined.\r\n") "")
      (progn
        (terminal-echo (concat "Actions (" (number->string count) "):\r\n"))
        ;; Sort alphabetically before displaying
        (let ((sorted (tintin-sort-actions-alphabetically action-entries)))
          ;; Build data structure: headers + data rows
          (let ((data (list (list "Pattern" "Commands" "P"))))
            ;; Add data rows
            (do ((i 0 (+ i 1))) ((>= i (length sorted)))
              (let* ((entry (list-ref sorted i))
                     (pattern (car entry))
                     (entry-data (cdr entry))
                     (commands (car entry-data))
                     (priority (cadr entry-data))
                     (priority-str (number->string priority)))
                (set! data
                 (append data (list (list pattern commands priority-str))))))
            ;; Print table using generic printer
            (tintin-print-table data)))
        ""))))

