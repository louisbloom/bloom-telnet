# src/Makefile.am - Source files for bloom-telnet

bin_PROGRAMS = bloom-telnet

bloom_telnet_SOURCES = \
    main.c \
    telnet.c \
    path_utils.c \
    path_utils.h \
    lisp_extension.c \
    lisp_extension.h \
    commands.c \
    commands.h \
    terminal_caps.c \
    telnet_app.c \
    telnet_app.h

bloom_telnet_CPPFLAGS = \
    -I$(top_srcdir)/include \
    $(BLOOMBOBA_CFLAGS) \
    $(BLOOMLISP_CFLAGS)

bloom_telnet_LDADD = \
    $(BLOOMBOBA_LIBS) \
    $(BLOOMLISP_LIBS) \
    $(SOCKET_LIBS)
