;; Test Assertion Macros for telnet-lisp Test Suite
;; Provides assertion macros for test files: assert-equal, assert-true, assert-false,
;; assert-error, and assert-nil. All macros abort tests via (error ...) on failure.
;;
;; Also provides common mock functions that tests can override if needed.

;; ============================================================================
;; Common Mock Functions
;; ============================================================================
(defun termcap (capability &rest args)
  "Mock: return sensible defaults for terminal capabilities.
   Tests can override this with their own version if needed."
  (cond
    ((eq? capability 'fg-color) "")
    ((eq? capability 'bg-color) "")
    ((eq? capability 'reset) "")
    ((eq? capability 'unicode?) #t)
    ((eq? capability 'type) "xterm-256color")
    ((eq? capability 'encoding) "UTF-8")
    ((eq? capability 'color-level) 4)
    ((eq? capability 'cols) 80)
    ((eq? capability 'rows) 24)
    ((eq? capability 'truecolor?) #t)
    (#t "")))

;; App-level mocks for C builtins
(defun terminal-echo (msg) nil)
(defun telnet-send (msg) nil)
(defun script-echo (title &rest args) nil)
(defun run-at-time (delay repeat func) nil)
(defun cancel-timer (timer) nil)
(defun statusbar-mode-set (sym text prio) nil)
(defun statusbar-mode-remove (sym) nil)

;; ============================================================================
;; Hook System Mock (backed by *hooks* hash table, matches C implementation)
;; ============================================================================
(define *hooks* (make-hash-table))
(define *default-hooks* nil)

;; Check if fn already exists in a hook entry list (by eq? identity)
(defun hooks--has-fn? (lst fn)
  (cond
    ((null? lst) #f)
    ((eq? (car (car lst)) fn) #t)
    (#t (hooks--has-fn? (cdr lst) fn))))

;; Insert (fn . priority) into a sorted list, return new list
(defun hooks--insert-sorted (fn priority lst)
  (let ((entry (cons fn priority)))
    (cond
      ((null? lst) (list entry))
      ((< priority (cdr (car lst)))
       (cons entry lst))
      (#t (cons (car lst) (hooks--insert-sorted fn priority (cdr lst)))))))

;; Remove fn from hook entry list by eq? identity, return new list
(defun hooks--remove-fn (lst fn)
  (cond
    ((null? lst) nil)
    ((eq? (car (car lst)) fn) (cdr lst))
    (#t (cons (car lst) (hooks--remove-fn (cdr lst) fn)))))

(defun add-hook (hook fn &rest rest-args)
  "Mock: add a hook function with optional priority."
  (let ((priority (if (null? rest-args) 50 (car rest-args)))
        (name (symbol->string hook)))
    (let ((hook-list (hash-ref *hooks* name)))
      (if (null? hook-list) (set! hook-list nil))
      (if (hooks--has-fn? hook-list fn)
        nil
        (hash-set! *hooks* name
                   (hooks--insert-sorted fn priority hook-list))))))

(defun remove-hook (hook fn)
  "Mock: remove a hook function."
  (let ((name (symbol->string hook)))
    (let ((hook-list (hash-ref *hooks* name)))
      (if hook-list
        (hash-set! *hooks* name (hooks--remove-fn hook-list fn))))))

(defun run-hook (hook &rest args)
  "Mock: run all functions registered on a hook."
  (let ((name (symbol->string hook)))
    (let ((hook-list (hash-ref *hooks* name)))
      (if hook-list
        (do ((remaining hook-list (cdr remaining)))
            ((null? remaining) nil)
          (apply (car (car remaining)) args))))))

(defun run-filter-hook--loop (entries val)
  "Helper: thread value through remaining hook entries."
  (if (null? entries)
    val
    (let ((fn (car (car entries))))
      (run-filter-hook--loop (cdr entries) (fn val)))))

(defun run-filter-hook (hook initial-value)
  "Mock: thread a value through all functions registered on a hook."
  (let ((name (symbol->string hook)))
    (let ((hook-list (hash-ref *hooks* name)))
      (if hook-list
        (run-filter-hook--loop hook-list initial-value)
        initial-value))))

;; ============================================================================
;; Session Mock System
;; ============================================================================
;; Simulates session isolation using hash tables as per-session variable stores.
;; Each session has its own hash table; session-switch changes the active one.

(define *mock-sessions* (make-hash-table))    ; "id" -> (name . vars-hash)
(define *mock-current-session* 1)
(define *mock-next-session-id* 2)

;; Helper: convert session id to hash key string
(defun mock-session-key (id) (format nil "~A" id))

;; Initialize default session
(hash-set! *mock-sessions* (mock-session-key 1) (cons "default" (make-hash-table)))

(defun session-create (name)
  "Mock: create a new session, returns its id."
  (let ((id *mock-next-session-id*))
    (set! *mock-next-session-id* (+ *mock-next-session-id* 1))
    (hash-set! *mock-sessions* (mock-session-key id)
               (cons name (make-hash-table)))
    id))

(defun session-list ()
  "Mock: return list of (id . name) pairs."
  (let ((result nil)
        (keys (hash-keys *mock-sessions*)))
    (do ((remaining keys (cdr remaining)))
        ((null? remaining) result)
      (let ((k (car remaining)))
        (let ((v (hash-ref *mock-sessions* k)))
          (set! result (cons (cons (string->number k) (car v)) result)))))))

(defun session-current ()
  "Mock: return current session id."
  *mock-current-session*)

(defun session-switch (id)
  "Mock: switch to session by id."
  (if (hash-ref *mock-sessions* (mock-session-key id))
    (progn (set! *mock-current-session* id) #t)
    (error "session-switch: no session with that id")))

(defun session-name (&rest args)
  "Mock: get session name. No args = current, one arg = by id."
  (let ((id (if (null? args) *mock-current-session* (car args))))
    (let ((entry (hash-ref *mock-sessions* (mock-session-key id))))
      (if entry (car entry) nil))))

(defun session-destroy (id)
  "Mock: destroy a session by id."
  (cond
    ((= id *mock-current-session*)
     (error "session-destroy: failed (not found or current session)"))
    ((hash-ref *mock-sessions* (mock-session-key id))
     (hash-remove! *mock-sessions* (mock-session-key id))
     #t)
    (#t (error "session-destroy: failed (not found or current session)"))))

;; Per-session variable helpers for testing isolation
(defun session-var-set (key value)
  "Set a variable in the current mock session's variable store."
  (let ((entry (hash-ref *mock-sessions* (mock-session-key *mock-current-session*))))
    (hash-set! (cdr entry) key value)))

(defun session-var-get (key)
  "Get a variable from the current mock session's variable store."
  (let ((entry (hash-ref *mock-sessions* (mock-session-key *mock-current-session*))))
    (hash-ref (cdr entry) key)))
;; Assert that actual equals expected (handles numbers and structural equality)
;; Usage: (assert-equal actual expected "description")
;; Returns: nil on success, aborts test with error on failure
(defmacro assert-equal (actual expected message)
  `(let ((actual-val ,actual)
         (expected-val ,expected))
     ;; Use = for numbers, equal? for everything else
     (let ((values-equal
            (if (and (number? actual-val) (number? expected-val))
              (= actual-val expected-val)
              (equal? actual-val expected-val))))
       (if values-equal
         nil ; Success: silent
         (error
          (format nil "Assertion failed: ~A~%  Expected: ~S~%  Actual:   ~S"
           ,message expected-val actual-val))))))

;; Assert that condition evaluates to truthy value (anything except nil/#f)
;; Usage: (assert-true condition "description")
;; Returns: nil on success, aborts test with error on failure
(defmacro assert-true (condition message)
  `(let ((result ,condition))
     (if result
       nil ; Success: silent
       (error
        (format nil "Assertion failed: ~A (expected truthy, got: ~S)" ,message
         result)))))

;; Assert that condition evaluates to falsy value (nil or #f)
;; Usage: (assert-false condition "description")
;; Returns: nil on success, aborts test with error on failure
(defmacro assert-false (condition message)
  `(let ((result ,condition))
     (if result
       (error
        (format nil "Assertion failed: ~A (expected falsy, got: ~S)" ,message
         result))
       nil))) ; Success: silent

;; Assert that expression throws an error
;; Usage: (assert-error expr "description")
;; Returns: nil on success (if error thrown), aborts test if expr succeeds
(defmacro assert-error (expr message)
  `(condition-case err
     (progn ,expr
       (error
        (format nil "Assertion failed: ~A (expected error but succeeded)"
         ,message)))
     (error nil))) ; Success: error was thrown

;; Assert that expression evaluates to nil explicitly
;; Usage: (assert-nil expr "description")
;; Returns: nil on success, aborts test with error on failure
(defmacro assert-nil (expr message)
  `(let ((result ,expr))
     (if (null? result)
       nil ; Success
       (error
        (format nil "Assertion failed: ~A (expected nil, got: ~S)" ,message
         result)))))
