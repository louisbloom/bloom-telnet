# tests/Makefile.am - Test files

TESTS = \
    tintin-colors.lisp \
    tintin-patterns.lisp \
    tintin-parsing.lisp \
    tintin-highlights.lisp \
    tintin-speedwalk.lisp

TEST_EXTENSIONS = .lisp
LISP_LOG_COMPILER = $(srcdir)/run-test.sh

AM_TESTS_ENVIRONMENT = \
    BLOOM_REPL="$${BLOOM_REPL:-bloom-repl}"; \
    export BLOOM_REPL;

EXTRA_DIST = \
    run-test.sh \
    test-helpers.lisp \
    test-loader.lisp \
    $(TESTS)
