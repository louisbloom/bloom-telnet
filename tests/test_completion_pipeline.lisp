;; tests/test_completion_pipeline.lisp - Regression test for trie leaf key collision
;;
;; Bug: The trie used "*" as its leaf sentinel key in hash-table nodes.
;; Words containing a literal '*' character (e.g. "#*R$$M" from ASCII art)
;; created a child node with key "*", colliding with the sentinel.
;; trie-collect then returned hash-table objects instead of leaf entries,
;; crashing merge-sort-by-seq-desc with "list-ref: not a proper list".
;;
;; Fix: Trie nodes are now (leaf . children-hash) cons cells. Leaf data is
;; stored in car (structurally separate), so no sentinel key is needed.
(load "tests/test-helpers.lisp")

(defvar *version* "1.0.0-test")
(load "lisp/init.lisp")

(defun member? (item lst)
  (cond ((null? lst) #f)
        ((equal? (car lst) item) #t)
        (#t (member? item (cdr lst)))))

(defun reset-completion-store (capacity)
  (set! *completion-trie* (cons nil (make-hash-table)))
  (set! *completion-words* (make-hash-table))
  (set! *completion-seq* 0)
  (set! *completion-word-store-size* capacity)
  (set! *completion-word-order* (make-vector capacity nil))
  (set! *completion-word-order-index* 0)
  (set! *completion-word-count* 0))

;; ============================================================================
;; Regression: carrionfields.net banner — m<tab> must find "mourned"
;; ============================================================================
(reset-completion-store 50000)
(set! *completion-max-results* 64)

(define cf-full-banner "\n\n                          ::x.\n                    <!X!!!!HMM$$$$W.\n               ---!H8MMH?M$$$$$$$$$8X.\n              -<!!!MMM$$$$$$$$$$$$$$$$X!:           The Carrion Fields\n            !----!!M?M$$$$$$$$$$$$$$$$MM!!<\n          '<M!  !!!MMM$$$$$$$$$$$$$$$MMMX!X!\n           !M!--!!!MMM$$$$$$$$$$$$$$$MMM!X$!    A Playerkilling/Roleplaying\n           -!8!:!!!MMMMM$$$$$$$$$$$$RMMMX8RX-               MUD\n         <!-!$X!-!!!MHM$$$$$$$$$$$RMMMMMM$!!!\n         !!:-MRX!-!!MM$$$$8$$$$$$$$$MMMM$R!-!       Original DikuMUD by\n        '!X:--?X!--!!!M$$$RMR$$$$RMMRMM$R!!!X!     Hans Staerfeldt, Katya\n         -XX  'MX:!!!!!?RRMMMMM!!XMMMM$R-<!!!!   Nyboe, Tom Madsen, Michael\n          !?!-X$P\"````----!M!!---`#*R$$M !<!!-     Seifert, and Sebastian\n          -!MXf        -!-!!!X!        \"k!!!-              Hammer\n          '!!!X         !X!M?X         '!!!-\n          -<!XM         X!!R!!         !M!-'\n          :!XMMX  : ::s@---!!!Mbx:!!<::X8k !       Based on Merc 2.1 by\n         !!!$$$MTMM8$#!!   ! MXX!R$W86SW$$!!!      Hatchet, Furey, and\n          !!!M$$#TT!!!!!-  !  X!!!!!!RR#M!!!               Khan\n           `!MW$M- -!!M!!  !  !!:!-- #$R?!!
            -:..    -XM!k:!#hHMX!!-    ::-        carrionfields.net 4449\n             -M!   <!!!$X?XMMMB$!!!   !!\n              !X!  !XR!$MM$$$$$$?MM! '!!         Created from ROM 2.3 by\n              `MX  'XXX t!@!H!X8X    '!>         Yuval Oren, Matt Hamby,\n               !!X!!X!\" MM$M$RR?.!!:X!             Barbara Hargrove\n               ?&M<!X>!MR$M> M9M5M!!XMM                \n                M!?XX!!RRt?M@NRX?!XMX!R               Maintained by\n                 `!!MHXX!!Mt!MMXWMM!!!              Azorinne, Ishuli,\n                   `!XM$$$R9M$RTMMX-                   and Umiron\n                     #$WXXW$$MXW$\"\n                        `\"\"!\"\"`\n                                               Greeting screen designed by\n                                               Zapata (bsinger1@netcom.com)\n\nBy what name do you wish to be mourned? ")

(collect-words-from-text cf-full-banner)

(let ((entry (hash-ref *completion-words* "mourned")))
  (assert-true (not (null? entry)) "mourned is in word store"))

(let ((m-results (get-completions-from-store "m")))
  (assert-true (> (length m-results) 0) "m<tab> returns results")
  (assert-true (member? "mourned" m-results) "m<tab> finds mourned"))

(let ((mo-results (get-completions-from-store "mo")))
  (assert-true (member? "mourned" mo-results) "mo<tab> finds mourned"))

;; Every trie-collect entry must be a proper list, never a hash-table
(let* ((m-node (trie-walk-to *completion-trie* "m"))
       (entries (trie-collect m-node)))
  (do ((remaining entries (cdr remaining))) ((null? remaining))
    (let ((entry (car remaining)))
      (assert-true (pair? entry)
       (concat "trie entry is a list, not " (format nil "~S" entry))))))

(let ((hook-results (completion-hook "m")))
  (assert-true (member? "mourned" hook-results)
   "completion-hook 'm' includes mourned"))

;; ============================================================================
;; '*' in words is safe — cons-cell trie has no sentinel collision
;; ============================================================================
(reset-completion-store 50000)
(collect-words-from-text "hello*world")
(let ((results (get-completions-from-store "h")))
  (assert-equal (length results) 1 "hello*world stored as one word")
  (assert-equal (car results) "hello*world" "word contains *"))

;; ============================================================================
;; Direct trie test: add-word-to-store with '*' in word still works
;; (bypasses word-break filtering, tests trie-level safety)
;; ============================================================================
(reset-completion-store 50000)
(add-word-to-store "abc")
(add-word-to-store "a*d")
(add-word-to-store "a*e")

(let ((results (get-completions-from-store "a")))
  (assert-equal (length results) 3 "3 words for 'a' via direct add-word-to-store")
  (assert-true (member? "abc" results) "abc found")
  (assert-true (member? "a*d" results) "a*d found")
  (assert-true (member? "a*e" results) "a*e found"))

(let* ((a-node (trie-walk-to *completion-trie* "a"))
       (entries (trie-collect a-node)))
  (assert-equal (length entries) 3 "trie-collect finds all 3 direct entries")
  (do ((remaining entries (cdr remaining))) ((null? remaining))
    (assert-true (pair? (car remaining)) "each direct entry is a proper list")))

(add-word-to-store "a*d")
(let ((results (get-completions-from-store "a")))
  (assert-equal (length results) 3 "still 3 words after duplicate a*d")
  (assert-equal (car results) "a*d" "duplicate a*d is most recent"))

(print "All completion pipeline tests passed!")
