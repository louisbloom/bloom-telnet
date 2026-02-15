;; tests/practice.lisp - Tests for practice mode
(load "tests/test-helpers.lisp")

;; Load practice.lisp (will use our mocks)
(load "lisp/contrib/practice.lisp")

;; ============================================================================
;; practice-send - delegates to send-input
;; ============================================================================

;; Single command
(set! *sent-inputs* '())
(practice-send "cast fireball")
(assert-equal *sent-inputs* '("cast fireball")
  "practice-send passes command to send-input")

;; Multiline command (semicolons preserved for input pipeline to handle)
(set! *sent-inputs* '())
(practice-send "cast heal;cast armor")
(assert-equal *sent-inputs* '("cast heal;cast armor")
  "practice-send preserves semicolons for input pipeline")

;; ============================================================================
;; practice-command? - /practice prefix matching
;; ============================================================================

(assert-equal (practice-command? "/p stop") "stop"
  "/p stop returns args")
(assert-equal (practice-command? "/practice stop") "stop"
  "/practice stop returns args")
(assert-equal (practice-command? "/pr c heal") "c heal"
  "/pr with args returns args")
(assert-equal (practice-command? "/p") ""
  "/p alone returns empty string")
(assert-nil (practice-command? "hello") "/practice rejects non-slash input")
(assert-nil (practice-command? "/pizza") "/pizza is not a practice command")

(print "All practice.lisp tests passed!")
