;; tests/practice.lisp - Tests for practice mode multiline commands
(load "tests/test-helpers.lisp")

;; ============================================================================
;; Mock builtins needed by practice.lisp
;; ============================================================================
(defvar *sent-commands* '() "Commands sent via practice-send-one")

(defun terminal-echo (msg) nil) ; No-op for tests
(defun telnet-send (msg) nil)   ; No-op for tests
(defun script-echo (title &rest args) nil)
(defun add-hook (hook func &optional priority) nil)
(defun run-at-time (delay repeat func) nil)
(defun cancel-timer (timer) nil)

;; Load practice.lisp (will use our mocks)
(load "lisp/contrib/practice.lisp")

;; Override practice-send-one to capture sent commands
(defun practice-send-one (cmd)
  "Mock: capture command instead of sending"
  (set! *sent-commands* (append *sent-commands* (list cmd))))

(defun reset-sent-commands ()
  (set! *sent-commands* '()))

;; ============================================================================
;; practice-send - multiline command splitting
;; ============================================================================

;; Single command (no semicolon)
(reset-sent-commands)
(practice-send "cast fireball")
(assert-equal *sent-commands* '("cast fireball")
  "practice-send single command")

;; Two commands separated by semicolon
(reset-sent-commands)
(practice-send "cast heal;cast armor")
(assert-equal *sent-commands* '("cast heal" "cast armor")
  "practice-send two commands")

;; Three commands
(reset-sent-commands)
(practice-send "c heal;c armor;c bless")
(assert-equal *sent-commands* '("c heal" "c armor" "c bless")
  "practice-send three commands")

;; Commands with spaces around semicolon
(reset-sent-commands)
(practice-send "cast heal ; cast armor")
(assert-equal *sent-commands* '("cast heal" "cast armor")
  "practice-send trims whitespace")

;; Empty parts should be skipped
(reset-sent-commands)
(practice-send "cast heal;;cast armor")
(assert-equal *sent-commands* '("cast heal" "cast armor")
  "practice-send skips empty parts")

;; Leading/trailing semicolons
(reset-sent-commands)
(practice-send ";cast heal;")
(assert-equal *sent-commands* '("cast heal")
  "practice-send handles leading/trailing semicolons")

(print "All practice.lisp tests passed!")
