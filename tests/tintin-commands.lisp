;; tintin-commands.lisp - Tests for the command processing pipeline
;;
;; Tests tintin-process-command, tintin-process-input, alias expansion,
;; filter hook integration, # command dispatch, semicolon splitting,
;; and the send-input alias expansion architecture.

(load "tests/test-helpers.lisp")
(defmacro load-system-file (name) `(load (string-append "lisp/" ,name)))
(load "lisp/tintin.lisp")
(set! *tintin-speedwalk-enabled* #f) ;; Disable speedwalk to avoid interference

;; Helper: collect terminal-echo output
(define *echoed* '())
(defun terminal-echo (msg)
  (set! *echoed* (append *echoed* (list msg))))

(defun clear-echoed () (set! *echoed* '()))

;; Helper: check if any echoed message contains a substring
(defun some-echoed-contains (substr)
  (let ((found #f))
    (do ((remaining *echoed* (cdr remaining)))
        ((or (null? remaining) found) found)
      (if (and (string? (car remaining))
               (string-index (car remaining) substr))
        (set! found #t)))))

;; Helper: reset aliases to clean state
(defun reset-aliases ()
  (set! *tintin-aliases* (make-hash-table))
  (set! *tintin-alias-depth* 0)
  (set! *sent-inputs* '())
  (set! *sent-results* '())
  (clear-echoed))

;; ============================================================================
;; Test 1: Simple alias expansion (via send-input)
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "gh" (list "go home"))

(let ((result (tintin-process-command "gh")))
  (assert-equal result "" "Simple alias returns empty (sent via send-input)")
  (assert-true (member? "go home" *sent-inputs*)
    "Alias expanded command sent via send-input"))

(print "Test 1 passed: simple alias expansion via send-input")

;; ============================================================================
;; Test 2: Alias with arguments (%0)
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "say" (list "say %0"))

(let ((result (tintin-process-command "say hello world")))
  (assert-equal result "" "Alias with args returns empty")
  (assert-true (member? "say hello world" *sent-inputs*)
    "Alias with %0 sends expanded command"))

(print "Test 2 passed: alias with %0")

;; ============================================================================
;; Test 3: Alias with numbered args (%1, %2)
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "k" (list "kill %1"))

(let ((result (tintin-process-command "k orc")))
  (assert-equal result "" "Alias with %1 returns empty")
  (assert-true (member? "kill orc" *sent-inputs*)
    "Alias with %1 sends expanded command"))

(print "Test 3 passed: alias with numbered args")

;; ============================================================================
;; Test 4: No alias match — pass through to server
;; ============================================================================
(reset-aliases)

(assert-equal (tintin-process-command "look") "look"
  "Non-aliased command passes through")

(print "Test 4 passed: no alias pass-through")

;; ============================================================================
;; Test 5: Alias with semicolons — split and send each part
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "buff" (list "cast shield;cast armor"))

(let ((result (tintin-process-command "buff")))
  (assert-equal result "" "Alias with semicolons returns empty")
  (assert-true (member? "cast shield" *sent-inputs*)
    "First part sent via send-input")
  (assert-true (member? "cast armor" *sent-inputs*)
    "Second part sent via send-input"))

(print "Test 5 passed: alias with semicolons")

;; ============================================================================
;; Test 6: Nested alias — alias expands to another alias (via send-input chain)
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "fb" (list "fullbuff"))
(hash-set! *tintin-aliases* "fullbuff" (list "cast shield;cast armor"))

(tintin-process-command "fb")
;; fb -> send-input("fullbuff") -> hook pipeline -> fullbuff alias ->
;;   send-input("cast shield"), send-input("cast armor")
(assert-true (member? "fullbuff" *sent-inputs*)
  "First level alias sends fullbuff")
(assert-true (member? "cast shield" *sent-inputs*)
  "Nested alias sends cast shield")
(assert-true (member? "cast armor" *sent-inputs*)
  "Nested alias sends cast armor")

(print "Test 6 passed: nested alias expansion via send-input")

;; ============================================================================
;; Test 7: # command dispatch from alias expansion
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "makealias" (list "#alias {zz} {sleep}"))

(tintin-process-command "makealias")
;; send-input("#alias {zz} {sleep}") -> hook pipeline -> dispatches #alias
(assert-true (hash-ref *tintin-aliases* "zz")
  "#alias command created the alias via send-input chain")

(print "Test 7 passed: # command in alias")

;; ============================================================================
;; Test 8: Filter hook consumption via send-input
;; ============================================================================
;; An alias expands to a slash command that should be consumed by the filter hook.
(reset-aliases)

(define *slash-consumed* nil)
(defun test-slash-filter (cmd)
  (if (and (> (length cmd) 0) (char=? (string-ref cmd 0) #\/))
    (progn
      (set! *slash-consumed* cmd)
      nil) ;; consume
    cmd)) ;; pass through

(add-hook 'user-input-hook 'test-slash-filter)

;; Alias that expands to a slash command
(hash-set! *tintin-aliases* "gr" (list "/greet %0"))

(set! *slash-consumed* nil)
(tintin-process-command "gr all")
;; send-input("/greet all") -> filter hook consumes it
(assert-equal *slash-consumed* "/greet all"
  "Filter hook saw the expanded /greet all command via send-input")

(remove-hook 'user-input-hook 'test-slash-filter)

(print "Test 8 passed: filter hook consumes slash command from alias via send-input")

;; ============================================================================
;; Test 9: Filter hook consumption in semicolon-split alias
;; ============================================================================
(reset-aliases)

(define *filter-seen* '())
(defun test-multi-filter (cmd)
  (set! *filter-seen* (append *filter-seen* (list cmd)))
  (if (and (> (length cmd) 0) (char=? (string-ref cmd 0) #\/))
    nil ;; consume slash commands
    cmd)) ;; pass through

(add-hook 'user-input-hook 'test-multi-filter)

;; Alias with mix of server command and slash command
(hash-set! *tintin-aliases* "combo" (list "look;/greet room"))

(set! *filter-seen* '())
(tintin-process-command "combo")
;; send-input("look") -> passes filter, goes to transform hook -> sent
;; send-input("/greet room") -> consumed by filter
(assert-true (member? "/greet room" *filter-seen*)
  "Filter hook saw /greet room from semicolon split via send-input")

(remove-hook 'user-input-hook 'test-multi-filter)

(print "Test 9 passed: filter hook in semicolon-split alias via send-input")

;; ============================================================================
;; Test 10: # command in semicolon-split alias
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "setup" (list "look;#echo {Ready}"))

(tintin-process-command "setup")
;; send-input("look") and send-input("#echo {Ready}") both go through pipeline
(assert-true (member? "look" *sent-inputs*)
  "look sent via send-input")
(assert-true (member? "#echo {Ready}" *sent-inputs*)
  "#echo sent via send-input")

(print "Test 10 passed: # command in semicolon-split alias")

;; ============================================================================
;; Test 11: tintin-process-input splits top-level semicolons
;; ============================================================================
(reset-aliases)

(let ((result (tintin-process-input "north;south")))
  (assert-equal result "north;south"
    "process-input joins multiple commands with semicolons"))

(print "Test 11 passed: process-input semicolon splitting")

;; ============================================================================
;; Test 12: Circular alias detection (depth limit)
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "loop1" (list "loop2"))
(hash-set! *tintin-aliases* "loop2" (list "loop1"))

(set! *tintin-alias-depth* 0)
(tintin-process-command "loop1")
;; loop1 -> send-input("loop2") (depth=1) -> send-input("loop1") (depth=2) -> ...
;; Eventually hits *tintin-max-alias-depth* and stops
(assert-true (>= *tintin-alias-depth* *tintin-max-alias-depth*)
  "Circular alias stops at depth limit")
(assert-true (some-echoed-contains "Circular alias")
  "Circular alias error message displayed")

(print "Test 12 passed: circular alias detection")

;; ============================================================================
;; Test 13: Empty and nil inputs
;; ============================================================================
(assert-equal (tintin-process-command "") "" "Empty string returns empty")
(assert-equal (tintin-process-command nil) "" "nil returns empty")

(print "Test 13 passed: empty/nil inputs")

;; ============================================================================
;; Test 14: tintin-try-alias returns nil on no match, string on match
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "zz" (list "sleep"))

(assert-nil (tintin-try-alias "unknown") "tintin-try-alias returns nil for no match")
(assert-equal (tintin-try-alias "zz") "sleep" "tintin-try-alias returns template on match")

(print "Test 14 passed: tintin-try-alias pure function")

;; ============================================================================
;; Test 15: Filter hook at depth 0 (run-filter-hook called for non-alias too)
;; ============================================================================
(reset-aliases)

(define *depth0-filtered* nil)
(defun test-depth0-filter (cmd)
  (if (string=? cmd "blocked")
    (progn (set! *depth0-filtered* #t) nil)
    cmd))

(add-hook 'user-input-hook 'test-depth0-filter)

(set! *depth0-filtered* nil)
(let ((result (tintin-process-command "blocked")))
  (assert-equal result "" "Filter hook consumes at depth 0")
  (assert-true *depth0-filtered* "Filter hook was called at depth 0"))

(set! *depth0-filtered* nil)
(let ((result (tintin-process-command "allowed")))
  (assert-equal result "allowed" "Non-blocked command passes through at depth 0")
  (assert-false *depth0-filtered* "Filter hook did not consume allowed command"))

(remove-hook 'user-input-hook 'test-depth0-filter)

(print "Test 15 passed: filter hook at depth 0")

;; ============================================================================
;; Test 16: Pattern alias with wildcards
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "cast %1 at %2" (list "cast '%1' target '%2'"))

(tintin-process-command "cast fireball at dragon")
(assert-true (member? "cast 'fireball' target 'dragon'" *sent-inputs*)
  "Pattern alias with wildcards sends expanded command via send-input")

(print "Test 16 passed: pattern alias with wildcards")

;; ============================================================================
;; Test 17: Self-referencing alias stops at depth limit
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "x" (list "x"))

(set! *tintin-alias-depth* 0)
(tintin-process-command "x")
(assert-true (>= *tintin-alias-depth* *tintin-max-alias-depth*)
  "Self-referencing alias stops at depth limit")

(print "Test 17 passed: self-referencing alias")

;; ============================================================================
;; Test 18: Fork-bomb alias stops at depth limit
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "bomb" (list "bomb;bomb"))

(set! *tintin-alias-depth* 0)
(tintin-process-command "bomb")
(assert-true (>= *tintin-alias-depth* *tintin-max-alias-depth*)
  "Fork-bomb alias stops at depth limit")

(print "Test 18 passed: fork-bomb alias")

;; ============================================================================
;; Test 19: Depth resets on fresh input
;; ============================================================================
;; After circular alias test, depth is at max.
;; Simulate fresh input by resetting (what process_line does in C)
(set! *tintin-alias-depth* 0)
(tintin-process-command "look")
(assert-equal *tintin-alias-depth* 0
  "Non-alias command doesn't increment depth")

(print "Test 19 passed: depth resets on fresh input")

;; ============================================================================
;; Test 20: Alias depth increments per send-input call
;; ============================================================================
(reset-aliases)
(hash-set! *tintin-aliases* "tri" (list "a;b;c"))

(set! *tintin-alias-depth* 0)
(tintin-process-command "tri")
;; 3 parts -> 3 send-input calls -> depth increments 3 times
(assert-true (>= *tintin-alias-depth* 3)
  "Alias with 3 parts increments depth at least 3 times")

(print "Test 20 passed: depth increments per send-input")

(print "")
(print "All command processing tests passed!")
