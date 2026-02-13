# tests/Makefile.am - Test files

# C tests
check_PROGRAMS = test_telnet_app

test_telnet_app_SOURCES = test_telnet_app.c
test_telnet_app_CPPFLAGS = \
    -I$(top_srcdir)/src \
    -I$(top_srcdir)/include \
    $(BLOOMBOBA_CFLAGS)
test_telnet_app_LDADD = \
    $(top_builddir)/src/bloom_telnet-telnet_app.o \
    $(BLOOMBOBA_LIBS)

# Lisp tests
TESTS = \
    test_telnet_app \
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
    run-bench.sh \
    test-helpers.lisp \
    test-loader.lisp \
    bench-completion.lisp \
    bench-trie-insert.lisp \
    tintin-colors.lisp \
    tintin-patterns.lisp \
    tintin-parsing.lisp \
    tintin-highlights.lisp \
    tintin-speedwalk.lisp
