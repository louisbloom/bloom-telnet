;; tintin-colors.lisp - Color parsing system for TinTin++ emulator
;;
;; Depends on: tintin-state.lisp, tintin-utils.lisp
;; ============================================================================
;; RGB COLOR UTILITIES
;; ============================================================================
;; Helper: Convert hex character to decimal (0-15)
(defun tintin-hex-to-dec (hex-char)
  (let ((ch (string-downcase hex-char)))
    (cond
      ((string=? ch "0") 0)
      ((string=? ch "1") 1)
      ((string=? ch "2") 2)
      ((string=? ch "3") 3)
      ((string=? ch "4") 4)
      ((string=? ch "5") 5)
      ((string=? ch "6") 6)
      ((string=? ch "7") 7)
      ((string=? ch "8") 8)
      ((string=? ch "9") 9)
      ((string=? ch "a") 10)
      ((string=? ch "b") 11)
      ((string=? ch "c") 12)
      ((string=? ch "d") 13)
      ((string=? ch "e") 14)
      ((string=? ch "f") 15)
      (#t 0))))

;; Helper: Expand 3-char RGB to full RGB values
;; Example: "abc" → (170 187 204)
(defun tintin-expand-rgb (rgb-str)
  (let ((len (length rgb-str)))
    (if (= len 3)
      ;; 3-char: each char represents 0-255 in 16 steps (multiply by 17)
      (list (* (tintin-hex-to-dec (substring rgb-str 0 1)) 17)
       (* (tintin-hex-to-dec (substring rgb-str 1 2)) 17)
       (* (tintin-hex-to-dec (substring rgb-str 2 3)) 17))
      ;; 6-char: parse as two-digit hex pairs
      (if (= len 6)
        (list
         (+ (* (tintin-hex-to-dec (substring rgb-str 0 1)) 16)
          (tintin-hex-to-dec (substring rgb-str 1 2)))
         (+ (* (tintin-hex-to-dec (substring rgb-str 2 3)) 16)
          (tintin-hex-to-dec (substring rgb-str 3 4)))
         (+ (* (tintin-hex-to-dec (substring rgb-str 4 5)) 16)
          (tintin-hex-to-dec (substring rgb-str 5 6))))
        ;; Invalid length - return black
        (list 0 0 0)))))

;; Helper: Convert RGB values to ANSI 24-bit color code
;; is-bg: #t for background (48;2), #f for foreground (38;2)
(defun tintin-rgb-to-ansi (r g b is-bg)
  (concat (if is-bg "48;2;" "38;2;") (number->string r) ";" (number->string g)
   ";" (number->string b)))

;; Parse RGB color code <rgb>, <Frgb>, or <Frrggbb>
;; Returns ANSI code string or nil
(defun tintin-parse-rgb-color (rgb-string is-bg)
  (if
    (and (> (length rgb-string) 2) (string=? (substring rgb-string 0 1) "<")
         (string=?
          (substring rgb-string (- (length rgb-string) 1) (length rgb-string))
          ">"))
    ;; Extract content between < and >
    (let ((content (substring rgb-string 1 (- (length rgb-string) 1)))
          (len (- (length rgb-string) 2)))
      (cond
        ;; <rgb> format (3 chars)
        ((= len 3)
         (let ((rgb (tintin-expand-rgb content)))
           (tintin-rgb-to-ansi (list-ref rgb 0) (list-ref rgb 1)
            (list-ref rgb 2) is-bg)))
        ;; <Frgb> format (4 chars) - ignore F, use last 3
        ((= len 4)
         (let ((rgb (tintin-expand-rgb (substring content 1 4))))
           (tintin-rgb-to-ansi (list-ref rgb 0) (list-ref rgb 1)
            (list-ref rgb 2) is-bg)))
        ;; <Frrggbb> format (7 chars) - ignore F, use last 6
        ((= len 7)
         (let ((rgb (tintin-expand-rgb (substring content 1 7))))
           (tintin-rgb-to-ansi (list-ref rgb 0) (list-ref rgb 1)
            (list-ref rgb 2) is-bg)))
        (#t nil)))
    nil))

;; ============================================================================
;; NAMED COLOR UTILITIES
;; ============================================================================
;; Look up named color in association list
(defun tintin-lookup-color (name alist)
  (if (or (null? alist) (not (list? alist)))
    nil
    (let ((pair (assoc name alist))) (if pair (cdr pair) nil))))

;; Strip attribute keywords from text (bold, dim, italic, etc.)
;; Returns text with attribute keywords removed
(defun tintin-strip-attributes (text)
  (let* ((text-lower (string-downcase text))
         (result text-lower))
    ;; Remove each attribute keyword
    (do ((i 0 (+ i 1))) ((>= i (length *tintin-attributes*)) result)
      (let ((keyword (car (list-ref *tintin-attributes* i))))
        (set! result (string-replace result keyword ""))))
    ;; Trim whitespace
    (tintin-trim result)))

;; Parse named color (e.g., "red", "light blue")
;; Returns ANSI code string or nil
(defun tintin-parse-named-color (name is-bg)
  (let ((name-lower (string-downcase (tintin-trim name))))
    ;; Try tertiary colors first (convert to RGB)
    (let ((tertiary (tintin-lookup-color name-lower *tintin-tertiary-colors*)))
      (if tertiary
        (tintin-parse-rgb-color (concat "<" tertiary ">") is-bg)
        ;; Try light/bright colors
        (let ((bright
               (tintin-lookup-color name-lower
                (if is-bg *tintin-colors-bright-bg* *tintin-colors-bright-fg*))))
          (if bright
            bright
            ;; Try standard colors
            (tintin-lookup-color name-lower
             (if is-bg *tintin-colors-bg* *tintin-colors-fg*))))))))

;; Parse attributes from text (bold, underscore, etc.)
;; Returns list of ANSI attribute codes
(defun tintin-parse-attributes (text)
  (let ((text-lower (string-downcase text))
        (attrs '()))
    ;; Check each attribute keyword
    (do ((i 0 (+ i 1))) ((>= i (length *tintin-attributes*)) attrs)
      (let* ((pair (list-ref *tintin-attributes* i))
             (keyword (car pair))
             (code (cdr pair)))
        (if (string-contains? text-lower keyword)
          (set! attrs (cons code attrs)))))))

;; ============================================================================
;; COLOR SPEC PARSING
;; ============================================================================
;; Split color spec on colon (FG:BG separator)
;; Returns (fg-part bg-part) or (fg-part nil)
(defun tintin-split-fg-bg (spec)
  (let ((colon-pos (tintin-string-find-char spec #\:)))
    (if colon-pos
      (list (substring spec 0 colon-pos)
       (substring spec (+ colon-pos 1) (length spec)))
      (list spec nil))))

;; Parse single color component (foreground or background)
;; Returns ANSI code string (may include attributes)
(defun tintin-parse-color-component (text is-bg)
  (if (or (not text) (string=? text ""))
    nil
    (let ((text-trimmed (tintin-trim text))
          (codes '()))
      ;; Extract attributes first
      (let ((attr-codes (tintin-parse-attributes text-trimmed)))
        (set! codes attr-codes))
      ;; Try RGB color format
      (let ((start-bracket (string-index text-trimmed "<")))
        (if start-bracket
          (let ((end-bracket (string-index text-trimmed ">")))
            (if end-bracket
              (let ((rgb-str
                     (substring text-trimmed start-bracket (+ end-bracket 1))))
                (let ((rgb-code (tintin-parse-rgb-color rgb-str is-bg)))
                  (if rgb-code (set! codes (cons rgb-code codes)))))))))
      ;; If no RGB found, try named colors
      (if
        (and (not (string-contains? text-trimmed "<"))
             (or (string-contains? text-trimmed "black")
                 (string-contains? text-trimmed "red")
                 (string-contains? text-trimmed "green")
                 (string-contains? text-trimmed "yellow")
                 (string-contains? text-trimmed "blue")
                 (string-contains? text-trimmed "magenta")
                 (string-contains? text-trimmed "cyan")
                 (string-contains? text-trimmed "white")
                 (string-contains? text-trimmed "azure")
                 (string-contains? text-trimmed "jade")
                 (string-contains? text-trimmed "violet")
                 (string-contains? text-trimmed "lime")
                 (string-contains? text-trimmed "pink")
                 (string-contains? text-trimmed "orange")))
        (let ((color-only (tintin-strip-attributes text-trimmed)))
          (let ((named-code (tintin-parse-named-color color-only is-bg)))
            (if named-code (set! codes (cons named-code codes))))))
      ;; Combine codes with semicolons
      (if (eq? codes '())
        nil
        (let ((result "")
              (first #t))
          (do ((remaining (reverse codes) (cdr remaining)))
            ((null? remaining) result)
            (if first (set! first #f) (set! result (concat result ";")))
            (set! result (concat result (car remaining)))))))))

;; Build ANSI escape sequence from fg and bg codes
;; Returns complete \033[...m sequence
(defun tintin-build-ansi-code (fg-codes bg-codes)
  "Build complete ANSI SGR escape sequence from color codes.

  ## Parameters
  - `fg-codes` - Foreground ANSI codes (string or `nil`), e.g., `\"1;31\"`
  - `bg-codes` - Background ANSI codes (string or `nil`), e.g., `\"44\"`

  ## Returns
  Complete ANSI escape sequence: `\\033[codes...m`. Returns empty string `\"\"`
  if both fg-codes and bg-codes are `nil`."
  (let ((codes '()))
    (if fg-codes (set! codes (cons fg-codes codes)))
    (if bg-codes (set! codes (cons bg-codes codes)))
    (if (eq? codes '())
      ""
      (let ((combined "")
            (first #t))
        (do ((remaining (reverse codes) (cdr remaining))) ((null? remaining))
          (if first (set! first #f) (set! combined (concat combined ";")))
          (set! combined (concat combined (car remaining))))
        (concat "\033[" combined "m")))))

;; Main color spec parser
;; Parses TinTin++ color specification and returns ANSI escape code
;; Examples:
;;   "red" → "\033[31m"
;;   "<fff>" → "\033[38;2;255;255;255m"
;;   "bold red:blue" → "\033[1;31;44m"
;;   "light red" → "\033[91m"
(defun tintin-parse-color-spec (spec)
  "Parse TinTin++ color specification into ANSI escape codes.

  ## Parameters
  - `spec` - Color specification string (TinTin++ format)

  ## Returns
  List of two ANSI code strings: `(fg-codes bg-codes)`. Returns `(nil nil)`
  if spec is empty/invalid. Either element can be `nil` if not specified.

  ## Description
  Main entry point for color parsing. Converts TinTin++ color specifications
  into ANSI SGR (Select Graphic Rendition) escape codes for terminal display.
  Supports named colors, RGB colors, text attributes, and foreground:background
  combinations.

  ## Examples
  ```lisp
  (tintin-parse-color-spec \"red\")
  ; => (\"31\" nil)

  (tintin-parse-color-spec \"red:blue\")
  ; => (\"31\" \"44\")

  (tintin-parse-color-spec \"<fff>\")
  ; => (\"38;2;255;255;255\" nil)

  (tintin-parse-color-spec \"bold red\")
  ; => (\"1;31\" nil)
  ```"
  (if (or (not spec) (string=? spec ""))
    (list nil nil)
    (let ((parts (tintin-split-fg-bg spec)))
      (let ((fg-part (list-ref parts 0))
            (bg-part (list-ref parts 1)))
        (list (tintin-parse-color-component fg-part #f)
         (if bg-part (tintin-parse-color-component bg-part #t) nil))))))
