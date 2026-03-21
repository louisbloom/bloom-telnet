;; tintin-state.lisp - Global state and constants for TinTin++ emulator
;;
;; This file must be loaded first - all other tintin-* files depend on it.
;; ============================================================================
;; DATA STRUCTURES
;; ============================================================================
(define *tintin-aliases* (make-hash-table))

(define *tintin-variables* (make-hash-table))

(define *tintin-highlights* (make-hash-table))

(define *tintin-actions* (make-hash-table))

(define *tintin-custom-colors* (make-hash-table))

(define *tintin-action-executing* #f)

(define *tintin-reading-file* #f)

;; Performance caches for highlight processing
(define *tintin-pattern-cache* (make-hash-table))

(define *tintin-sorted-highlights-cache* nil)

(define *tintin-highlights-dirty* #t)

(defvar *tintin-speedwalk-enabled* #t
  "When non-nil, enable speedwalk expansion (e.g., 3n2e → n;n;n;e;e).

Speedwalk is a MUD client feature that expands directional shorthand into
multiple commands. For example, `3n2e` expands to `north;north;north;east;east`.

## Values
- `#t` - Enable speedwalk expansion (default)
- `#f` - Disable speedwalk expansion

## See Also
- `*tintin-speedwalk-diagonals*` - Enable diagonal directions (ne, sw, etc.)")

(defvar *tintin-speedwalk-diagonals* #f
  "When non-nil, enable diagonal directions in speedwalk (ne, nw, se, sw).

By default, speedwalk only supports cardinal directions (n, s, e, w, u, d).
Enable this to also support diagonal directions.

## Values
- `#t` - Enable diagonal directions (ne, nw, se, sw)
- `#f` - Cardinal directions only (default)

## See Also
- `*tintin-speedwalk-enabled*` - Master speedwalk toggle")

(defvar *tintin-enabled* #t
  "Master toggle for TinTin++ functionality.

When disabled, all TinTin++ features are bypassed and input is sent directly
to the telnet server without processing.

## Values
- `#t` - Enable TinTin++ processing (default)
- `#f` - Disable TinTin++ (pass-through mode)

## Functions
- `(tintin-toggle!)` - Toggle on/off
- `(tintin-enable!)` - Enable TinTin++
- `(tintin-disable!)` - Disable TinTin++")

(define *tintin-alias-depth* 0)

(defvar *tintin-max-alias-depth* 10
  "Maximum recursion depth for alias expansion.

Prevents infinite loops when aliases reference each other. When this depth
is exceeded, alias expansion stops and remaining text is sent as-is.

## Values
- 10 - Default, sufficient for most use cases
- Higher values allow deeper alias nesting
- Lower values provide faster loop detection")

;; TinTin++ command registry with metadata
;; Each entry: (handler-fn arg-count syntax-help)
;; Registry is populated after handlers are defined (see tintin-commands.lisp)
(define *tintin-commands* (make-hash-table))

;; ============================================================================
;; COLOR CONSTANTS
;; ============================================================================
;; TinTin++ Color Name Mappings
(defconst *tintin-colors-fg*
  '(("black" . "30") ("red" . "31") ("green" . "32") ("yellow" . "33")
    ("blue" . "34") ("magenta" . "35") ("cyan" . "36") ("white" . "37"))
  "Standard ANSI foreground color codes (30-37).

Maps color names to their ANSI SGR foreground codes.")

(defconst *tintin-colors-bg*
  '(("black" . "40") ("red" . "41") ("green" . "42") ("yellow" . "43")
    ("blue" . "44") ("magenta" . "45") ("cyan" . "46") ("white" . "47"))
  "Standard ANSI background color codes (40-47).

Maps color names to their ANSI SGR background codes.")

(defconst *tintin-colors-bright-fg*
  '(("light black" . "90") ("light red" . "91") ("light green" . "92")
    ("light yellow" . "93") ("light blue" . "94") ("light magenta" . "95")
    ("light cyan" . "96") ("light white" . "97"))
  "Bright/light ANSI foreground color codes (90-97).

Maps 'light <color>' names to their ANSI SGR bright foreground codes.")

(defconst *tintin-colors-bright-bg*
  '(("light black" . "100") ("light red" . "101") ("light green" . "102")
    ("light yellow" . "103") ("light blue" . "104") ("light magenta" . "105")
    ("light cyan" . "106") ("light white" . "107"))
  "Bright/light ANSI background color codes (100-107).

Maps 'light <color>' names to their ANSI SGR bright background codes.")

(defconst *tintin-tertiary-colors*
  '(("azure" . "acf") ("ebony" . "000") ("jade" . "afc") ("lime" . "cfa")
    ("orange" . "fc8") ("pink" . "fca") ("silver" . "ccc") ("tan" . "ca8")
    ("violet" . "fac") ("white" . "fff"))
  "TinTin++ tertiary colors mapped to 3-char RGB hex values.

These named colors expand to 24-bit RGB ANSI sequences.")

(defconst *tintin-attributes*
  '(("reset" . "0") ("bold" . "1") ("dim" . "2") ("italic" . "3")
    ("underscore" . "4") ("underline" . "4") ("blink" . "5") ("reverse" . "7")
    ("strikethrough" . "9"))
  "ANSI text attribute codes.

Maps attribute names to their ANSI SGR codes.")
