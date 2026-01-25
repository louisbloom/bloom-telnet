# src/Makefile.am - Source files for bloom-telnet

bin_PROGRAMS = bloom-telnet

bloom_telnet_SOURCES = \
    main.c \
    telnet.c \
    dynamic_buffer.c \
    dynamic_buffer.h \
    ansi_sequences.c \
    ansi_sequences.h \
    path_utils.c \
    path_utils.h \
    lisp_extension.c \
    lisp_extension.h \
    commands.c \
    commands.h \
    terminal_caps.c

bloom_telnet_CPPFLAGS = \
    -I$(top_srcdir)/include \
    $(BLOOMLISP_CFLAGS)

bloom_telnet_LDADD = \
    $(BLOOMLISP_LIBS) \
    $(SOCKET_LIBS)
