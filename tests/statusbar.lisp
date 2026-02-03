;; Tests for statusbar Lisp API (init.lisp)
;; Run with: ./tests/run-test.sh tests/statusbar.lisp

(load "tests/test-helpers.lisp")

;; ============================================================================
;; Mock raw C API builtins for testing
;; ============================================================================
(defvar *statusbar-mode* "" "Captured composed mode text from raw API")
(defvar *statusbar-notification* "" "Captured notification from raw API")

(defun statusbar-set-mode (&optional text)
  "Mock raw C API: Set mode text directly"
  (set! *statusbar-mode* (if text text ""))
  nil)

(defun statusbar-notify (msg)
  "Mock raw C API: Set notification"
  (set! *statusbar-notification* msg)
  nil)

(defun statusbar-clear ()
  "Mock raw C API: Clear notification"
  (set! *statusbar-notification* "")
  nil)

;; Mock terminal-echo for init.lisp
(defun terminal-echo (msg) nil)

;; ============================================================================
;; Load init.lisp to get Lisp-side statusbar functions
;; ============================================================================
(load "lisp/init.lisp")

;; Helper to reset registry state between tests
(defun reset-statusbar-state ()
  (set! *statusbar-mode-registry* '())
  (set! *statusbar-mode* "")
  (set! *statusbar-notification* "")
  (set! *notify-timer* nil))

;; ============================================================================
;; Test: statusbar--insert-sorted helper function
;; ============================================================================
(print "Testing statusbar--insert-sorted...")

;; Insert into empty list
(assert-equal (statusbar--insert-sorted '(a "A" 50) '())
              '((a "A" 50))
              "Insert into empty list")

;; Insert higher priority at front
(assert-equal (statusbar--insert-sorted '(b "B" 100) '((a "A" 50)))
              '((b "B" 100) (a "A" 50))
              "Higher priority inserted at front")

;; Insert lower priority at end
(assert-equal (statusbar--insert-sorted '(c "C" 25) '((a "A" 50)))
              '((a "A" 50) (c "C" 25))
              "Lower priority inserted at end")

;; Insert middle priority in correct position
(assert-equal (statusbar--insert-sorted '(b "B" 75) '((a "A" 100) (c "C" 50)))
              '((a "A" 100) (b "B" 75) (c "C" 50))
              "Middle priority inserted in correct position")

;; Equal priority: new item goes after existing (stable insert)
(assert-equal (statusbar--insert-sorted '(b "B" 50) '((a "A" 50)))
              '((a "A" 50) (b "B" 50))
              "Equal priority: new item after existing")

(print "statusbar--insert-sorted tests passed!")

;; ============================================================================
;; Test: statusbar--compose-modes helper function
;; ============================================================================
(print "Testing statusbar--compose-modes...")

(reset-statusbar-state)

;; Empty registry clears mode
(statusbar--compose-modes)
(assert-equal *statusbar-mode* "" "Empty registry clears mode")

;; Single entry
(set! *statusbar-mode-registry* '((a "AAA" 50)))
(statusbar--compose-modes)
(assert-equal *statusbar-mode* "AAA" "Single entry composed")

;; Multiple entries joined with separator
(set! *statusbar-mode-registry* '((b "BBB" 100) (a "AAA" 50)))
(statusbar--compose-modes)
(assert-equal *statusbar-mode* "BBB · AAA" "Multiple entries joined")

;; Three entries
(set! *statusbar-mode-registry* '((c "CCC" 150) (b "BBB" 100) (a "AAA" 50)))
(statusbar--compose-modes)
(assert-equal *statusbar-mode* "CCC · BBB · AAA" "Three entries joined")

(print "statusbar--compose-modes tests passed!")

;; ============================================================================
;; Test: statusbar-mode-set
;; ============================================================================
(print "Testing statusbar-mode-set...")

(reset-statusbar-state)

;; Add first mode
(statusbar-mode-set 'mode-a "Mode A" 50)
(assert-equal *statusbar-mode* "Mode A" "First mode added")
(assert-equal (length *statusbar-mode-registry*) 1 "Registry has 1 entry")

;; Add higher priority mode
(statusbar-mode-set 'mode-b "Mode B" 100)
(assert-equal *statusbar-mode* "Mode B · Mode A" "Higher priority at front")
(assert-equal (length *statusbar-mode-registry*) 2 "Registry has 2 entries")

;; Add lower priority mode
(statusbar-mode-set 'mode-c "Mode C" 25)
(assert-equal *statusbar-mode* "Mode B · Mode A · Mode C" "Lower priority at end")
(assert-equal (length *statusbar-mode-registry*) 3 "Registry has 3 entries")

;; Update existing mode text (same priority)
(statusbar-mode-set 'mode-a "Updated A" 50)
(assert-equal *statusbar-mode* "Mode B · Updated A · Mode C" "Text updated, position same")
(assert-equal (length *statusbar-mode-registry*) 3 "Registry still has 3 entries")

;; Update existing mode priority (moves position)
(statusbar-mode-set 'mode-c "Mode C" 200)
(assert-equal *statusbar-mode* "Mode C · Mode B · Updated A" "Priority update moves position")
(assert-equal (length *statusbar-mode-registry*) 3 "Registry still has 3 entries")

;; Update both text and priority
(statusbar-mode-set 'mode-a "New A" 150)
(assert-equal *statusbar-mode* "Mode C · New A · Mode B" "Both text and priority updated")

(print "statusbar-mode-set tests passed!")

;; ============================================================================
;; Test: statusbar-mode-remove
;; ============================================================================
(print "Testing statusbar-mode-remove...")

(reset-statusbar-state)

;; Setup: add three modes
(statusbar-mode-set 'x "X" 100)
(statusbar-mode-set 'y "Y" 50)
(statusbar-mode-set 'z "Z" 25)
(assert-equal *statusbar-mode* "X · Y · Z" "Initial state")

;; Remove middle
(statusbar-mode-remove 'y)
(assert-equal *statusbar-mode* "X · Z" "Middle removed")
(assert-equal (length *statusbar-mode-registry*) 2 "Registry has 2 entries")

;; Remove first (highest priority)
(statusbar-mode-remove 'x)
(assert-equal *statusbar-mode* "Z" "First removed")
(assert-equal (length *statusbar-mode-registry*) 1 "Registry has 1 entry")

;; Remove last
(statusbar-mode-remove 'z)
(assert-equal *statusbar-mode* "" "Last removed, mode cleared")
(assert-equal (length *statusbar-mode-registry*) 0 "Registry is empty")

;; Remove non-existent (no-op)
(statusbar-mode-remove 'nonexistent)
(assert-equal *statusbar-mode* "" "Remove non-existent is no-op")
(assert-equal (length *statusbar-mode-registry*) 0 "Registry still empty")

;; Remove from empty registry (no-op)
(statusbar-mode-remove 'anything)
(assert-equal *statusbar-mode* "" "Remove from empty is no-op")

(print "statusbar-mode-remove tests passed!")

;; ============================================================================
;; Test: Edge cases
;; ============================================================================
(print "Testing edge cases...")

(reset-statusbar-state)

;; Empty text
(statusbar-mode-set 'empty "" 50)
(assert-equal *statusbar-mode* "" "Empty text mode")

;; Negative priority
(statusbar-mode-set 'neg "Negative" -100)
(assert-equal *statusbar-mode* " · Negative" "Negative priority works")

(reset-statusbar-state)

;; Zero priority
(statusbar-mode-set 'zero "Zero" 0)
(statusbar-mode-set 'pos "Positive" 50)
(statusbar-mode-set 'neg "Negative" -50)
(assert-equal *statusbar-mode* "Positive · Zero · Negative" "Mixed priorities sorted")

;; Very large priorities
(reset-statusbar-state)
(statusbar-mode-set 'big "Big" 999999)
(statusbar-mode-set 'small "Small" 1)
(assert-equal *statusbar-mode* "Big · Small" "Large priority difference")

;; Same symbol added twice (should update, not duplicate)
(reset-statusbar-state)
(statusbar-mode-set 'dup "First" 50)
(statusbar-mode-set 'dup "Second" 50)
(assert-equal (length *statusbar-mode-registry*) 1 "No duplicate entries")
(assert-equal *statusbar-mode* "Second" "Second value used")

;; Unicode text
(reset-statusbar-state)
(statusbar-mode-set 'unicode "🔴 Recording" 100)
(assert-equal *statusbar-mode* "🔴 Recording" "Unicode in mode text")

(print "Edge case tests passed!")

;; ============================================================================
;; Test: notify function
;; ============================================================================
(print "Testing notify...")

(reset-statusbar-state)

;; Basic notify
(notify "Hello")
(assert-equal *statusbar-notification* "Hello" "notify sets notification")

;; notify with different message
(notify "World")
(assert-equal *statusbar-notification* "World" "notify updates notification")

;; notify clears previous timer
(set! *notify-timer* 'fake-timer)
;; Note: can't fully test timer cancellation without mocking cancel-timer
;; but we can verify the flow works
(notify "New message")
(assert-equal *statusbar-notification* "New message" "notify after fake timer")

;; Empty notification
(notify "")
(assert-equal *statusbar-notification* "" "Empty notification")

(print "notify tests passed!")

;; ============================================================================
;; Test: statusbar-clear
;; ============================================================================
(print "Testing statusbar-clear...")

(reset-statusbar-state)

(statusbar-notify "Test")
(assert-equal *statusbar-notification* "Test" "Notification set")

(statusbar-clear)
(assert-equal *statusbar-notification* "" "Notification cleared")

;; Clear when already empty
(statusbar-clear)
(assert-equal *statusbar-notification* "" "Clear when empty is no-op")

(print "statusbar-clear tests passed!")

;; ============================================================================
;; Test: Integration - modes and notifications are independent
;; ============================================================================
(print "Testing mode/notification independence...")

(reset-statusbar-state)

;; Set mode
(statusbar-mode-set 'test "Mode" 50)
(assert-equal *statusbar-mode* "Mode" "Mode set")
(assert-equal *statusbar-notification* "" "Notification still empty")

;; Set notification
(notify "Notice")
(assert-equal *statusbar-mode* "Mode" "Mode unchanged")
(assert-equal *statusbar-notification* "Notice" "Notification set")

;; Clear notification doesn't affect mode
(statusbar-clear)
(assert-equal *statusbar-mode* "Mode" "Mode still set")
(assert-equal *statusbar-notification* "" "Notification cleared")

;; Remove mode doesn't affect notification
(notify "Another")
(statusbar-mode-remove 'test)
(assert-equal *statusbar-mode* "" "Mode removed")
(assert-equal *statusbar-notification* "Another" "Notification unchanged")

(print "Mode/notification independence tests passed!")

;; ============================================================================
;; Test: Rapid updates
;; ============================================================================
(print "Testing rapid updates...")

(reset-statusbar-state)

;; Add and remove many modes rapidly
(statusbar-mode-set 'a "A" 10)
(statusbar-mode-set 'b "B" 20)
(statusbar-mode-set 'c "C" 30)
(statusbar-mode-set 'd "D" 40)
(statusbar-mode-set 'e "E" 50)
(assert-equal *statusbar-mode* "E · D · C · B · A" "5 modes added")

(statusbar-mode-remove 'c)
(statusbar-mode-remove 'a)
(statusbar-mode-remove 'e)
(assert-equal *statusbar-mode* "D · B" "3 modes removed")

(statusbar-mode-set 'f "F" 35)
(assert-equal *statusbar-mode* "D · F · B" "New mode inserted in middle")

(print "Rapid update tests passed!")

;; ============================================================================
;; All tests passed
;; ============================================================================
(print "")
(print "All statusbar tests passed!")
