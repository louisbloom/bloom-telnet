;; tests/spell-translator.lisp - Tests for spell translator
(load "tests/test-helpers.lisp")

;; Load spell-translator (will use our mocks)
(load "lisp/contrib/spell-translator.lisp")

;; ============================================================================
;; Character translation
;; ============================================================================

(assert-equal (translate-garbled-char #\a) #\a "a -> a")
(assert-equal (translate-garbled-char #\z) #\e "z -> e")
(assert-equal (translate-garbled-char #\q) #\c "q -> c")
(assert-equal (translate-garbled-char #\u) #\i "u -> i")
(assert-equal (translate-garbled-char #\r) #\l "r -> l")
(assert-equal (translate-garbled-char #\w) #\m "w -> m")
(assert-equal (translate-garbled-char #\i) #\n "i -> n")
;; Unknown chars pass through
(assert-equal (translate-garbled-char #\1) #\1 "digits pass through")
(assert-equal (translate-garbled-char #\-) #\- "punctuation passes through")

;; ============================================================================
;; Syllable matching
;; ============================================================================

;; Match at start of word
(let ((result (try-match-syllable "candus" 0 6)))
  (assert-true result "candus matches")
  (assert-equal (car result) "re" "candus -> re")
  (assert-equal (cdr result) 6 "candus consumes 6 chars"))

;; Match at offset
(let ((result (try-match-syllable "xxabra" 2 6)))
  (assert-true result "abra matches at offset 2")
  (assert-equal (car result) "ar" "abra -> ar"))

;; No match
(assert-nil (try-match-syllable "xyz" 0 3) "no syllable match for xyz")

;; Longest match wins (candus before other shorter patterns)
(let ((result (try-match-syllable "candusxxx" 0 9)))
  (assert-equal (car result) "re" "greedy: candus matched before shorter"))

;; ============================================================================
;; Word translation
;; ============================================================================

;; Pure char-by-char translation
(assert-equal (translate-garbled-word "ozrr") "gell"
  "ozrr -> gell (char-by-char)")

;; Syllable translation
(assert-equal (translate-garbled-word "abragru") "arra"
  "abragru -> arra (syllable: abra->ar, gru->ra)")

;; Mixed syllable + char
(assert-equal (translate-garbled-word "zrzwunsohar") "elemental"
  "zrzwunsohar -> elemental (mixed syllable+char)")

;; Dictionary override takes precedence
(assert-equal (translate-garbled-word "qaiyjcandus") "conjure"
  "dictionary override: qaiyjcandus -> conjure")

(assert-equal (translate-garbled-word "eaaf") "door"
  "dictionary override: eaaf -> door")

;; ============================================================================
;; Phrase translation
;; ============================================================================

(assert-equal (translate-garbled-phrase "qaiyjcandus zrzwunsohar") "conjure elemental"
  "phrase: conjure elemental")

;; ============================================================================
;; Known spell detection
;; ============================================================================

(assert-true (known-spell? "cure light") "cure is a known spell word")
(assert-true (known-spell? "CURE LIGHT") "case-insensitive known spell check")
(assert-false (known-spell? "qaiyjcandus") "garbled text is not known")

;; ============================================================================
;; spell-add / spell-remove
;; ============================================================================

(spell-add "hzgh" "override")
(assert-equal (translate-garbled-word "hzgh") "override"
  "spell-add override works")

(spell-remove "hzgh")
(assert-equal (translate-garbled-word "hzgh") "test"
  "spell-remove clears override, falls back to cipher")

;; ============================================================================
;; spell-add-known / spell-remove-known
;; ============================================================================

(assert-false (known-spell? "xyzzy") "xyzzy not known before add")
(spell-add-known "xyzzy")
(assert-true (known-spell? "xyzzy") "xyzzy known after spell-add-known")

(spell-remove-known "xyzzy")
(assert-false (known-spell? "xyzzy") "xyzzy not known after spell-remove-known")

;; Removing nonexistent word doesn't error
(spell-remove-known "nonexistent")

;; ============================================================================
;; Filter hook - garbled text gets translation appended
;; ============================================================================

(let ((input "Det utters the words, 'qaiyjcandus zrzwunsohar'."))
  (let ((result (spell-translator-filter input)))
    (assert-true (string-contains? result "conjure elemental")
      "filter adds translation for garbled text")
    (assert-true (string-contains? result "'")
      "filter preserves original quote")))

;; ============================================================================
;; Filter hook - known spells pass through unchanged
;; ============================================================================

(let ((input "Det utters the words, 'cure light'."))
  (assert-equal (spell-translator-filter input) input
    "filter passes through known spells unchanged"))

;; ============================================================================
;; Filter hook - non-utterance text passes through
;; ============================================================================

(let ((input "The goblin hits you!"))
  (assert-equal (spell-translator-filter input) input
    "filter passes through non-utterance text"))

;; ============================================================================
;; Filter hook - same text after translation skipped
;; ============================================================================

;; Text that translates to itself should pass through
(let ((input "Det utters the words, 'abba'."))
  ;; abba translates to abba (a->a, b->b), so no annotation should be added
  (assert-equal (spell-translator-filter input) input
    "filter skips when translation matches original"))

;; ============================================================================
;; Filter hook - add-known causes filter to skip
;; ============================================================================

(spell-add-known "qaiyjcandus")
(let ((input "Det utters the words, 'qaiyjcandus zrzwunsohar'."))
  (assert-equal (spell-translator-filter input) input
    "filter skips after spell-add-known marks word"))
(spell-remove-known "qaiyjcandus")

;; ============================================================================
;; Hook registration
;; ============================================================================

(let ((hooks (hash-ref *hooks* "telnet-input-filter-hook")))
  (assert-true hooks "spell-translator-filter registered on telnet-input-filter-hook")
  (assert-true (hooks--has-fn? hooks spell-translator-filter)
    "spell-translator-filter is in hook list"))

(print "All tests passed!")
