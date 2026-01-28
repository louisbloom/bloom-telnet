# bloom-boba/Makefile.am - Build bloom-boba TUI library

# Build the library
noinst_LIBRARIES = libbloom-boba.a

libbloom_boba_a_SOURCES = \
    src/msg.c \
    src/cmd.c \
    src/input_parser.c \
    src/runtime.c \
    src/dynamic_buffer.c \
    src/ansi_sequences.c \
    src/components/textinput.c \
    src/components/textview.c \
    src/components/viewport.c

libbloom_boba_a_CPPFLAGS = \
    -I$(srcdir)/include

# Distribute headers
EXTRA_DIST = \
    README.md \
    include/bloom-boba/tui.h \
    include/bloom-boba/msg.h \
    include/bloom-boba/cmd.h \
    include/bloom-boba/component.h \
    include/bloom-boba/input_parser.h \
    include/bloom-boba/runtime.h \
    include/bloom-boba/dynamic_buffer.h \
    include/bloom-boba/ansi_sequences.h \
    include/bloom-boba/components/textinput.h \
    include/bloom-boba/components/textview.h \
    include/bloom-boba/components/viewport.h
