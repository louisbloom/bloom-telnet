/* bloom-telnet - Terminal-based telnet client with Lisp scripting
 *
 * Main entry point implementing a TUI using raw terminal mode,
 * select()-based event loop, and bloom-lisp's lineedit for input.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <gc.h>

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
#include <conio.h>
#else
#include <unistd.h>
#include <termios.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#endif

#include "../include/telnet.h"
#include "../include/terminal_caps.h"
#include "lisp_extension.h"
#include "commands.h"
#include "dynamic_buffer.h"
#include <bloom-lisp/lineedit.h>

/* Version information */
#define BLOOM_TELNET_VERSION "0.1.0"

/* Global state */
static Telnet *g_telnet = NULL;
static LineEditState *g_lineedit = NULL;
static int g_connected = 0;
static int g_quit_requested = 0;
static int g_term_rows = 24;
static int g_term_cols = 80;

#ifndef _WIN32
static struct termios g_orig_termios;
static int g_raw_mode = 0;
#endif

/* Forward declarations */
static void cleanup(void);
static void handle_sigint(int sig);
static void handle_sigwinch(int sig);
static int enable_raw_mode(void);
static void disable_raw_mode(void);
static void update_terminal_size(void);
static void print_usage(const char *progname);
static void print_version(void);

/* Signal handler for SIGINT (Ctrl+C) */
static void handle_sigint(int sig) {
    (void)sig;
    g_quit_requested = 1;
}

#ifndef _WIN32
/* Signal handler for SIGWINCH (terminal resize) */
static void handle_sigwinch(int sig) {
    (void)sig;
    update_terminal_size();
    if (g_connected && g_telnet) {
        telnet_set_terminal_size(g_telnet, g_term_cols, g_term_rows);
    }
}
#endif

/* Enable raw terminal mode */
static int enable_raw_mode(void) {
#ifdef _WIN32
    /* Windows: No need to change console mode for basic operation */
    return 0;
#else
    if (g_raw_mode)
        return 0;

    if (tcgetattr(STDIN_FILENO, &g_orig_termios) < 0) {
        return -1;
    }

    struct termios raw = g_orig_termios;
    /* Input: no break, no CR->NL, no parity check, no strip, no XOFF */
    raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    /* Output: disable post processing (we handle newlines ourselves) */
    raw.c_oflag &= ~(OPOST);
    /* Control: 8-bit chars */
    raw.c_cflag |= (CS8);
    /* Local: no echo, no canonical mode, no signals, no extended */
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    /* Read with timeout */
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 1;

    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) < 0) {
        return -1;
    }

    g_raw_mode = 1;
    return 0;
#endif
}

/* Disable raw terminal mode */
static void disable_raw_mode(void) {
#ifndef _WIN32
    if (g_raw_mode) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &g_orig_termios);
        g_raw_mode = 0;
    }
#endif
}

/* Update terminal size from ioctl */
static void update_terminal_size(void) {
#ifdef _WIN32
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    if (GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi)) {
        g_term_cols = csbi.srWindow.Right - csbi.srWindow.Left + 1;
        g_term_rows = csbi.srWindow.Bottom - csbi.srWindow.Top + 1;
    }
#else
    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0) {
        if (ws.ws_col > 0)
            g_term_cols = ws.ws_col;
        if (ws.ws_row > 0)
            g_term_rows = ws.ws_row;
    }
#endif
}

/* Cleanup function called at exit */
static void cleanup(void) {
    disable_raw_mode();

    if (g_telnet) {
        if (g_connected) {
            telnet_disconnect(g_telnet);
        }
        telnet_destroy(g_telnet);
        g_telnet = NULL;
    }

    if (g_lineedit) {
        lineedit_destroy(g_lineedit);
        g_lineedit = NULL;
    }

    lisp_x_cleanup();
    termcaps_cleanup();
}

/* Print usage information */
static void print_usage(const char *progname) {
    fprintf(stderr,
            "Usage: %s [OPTIONS] [hostname [port]]\n"
            "\n"
            "A terminal-based telnet client with Lisp scripting support.\n"
            "\n"
            "Options:\n"
            "  -h, --help          Show this help message\n"
            "  -v, --version       Show version information\n"
            "  -l, --load FILE     Load a Lisp script at startup\n"
            "\n"
            "Arguments:\n"
            "  hostname            Server hostname or IP address\n"
            "  port                Server port (default: 23)\n"
            "\n"
            "Commands (prefix with ':'):\n"
            "  :help               Show available commands\n"
            "  :connect HOST PORT  Connect to a server\n"
            "  :disconnect         Disconnect from server\n"
            "  :load FILE          Load a Lisp script\n"
            "  :quit               Exit the client\n"
            "\n",
            progname);
}

/* Print version information */
static void print_version(void) {
    printf("bloom-telnet %s\n", BLOOM_TELNET_VERSION);
}

/* Main event loop */
static int run_event_loop(void) {
    char recv_buffer[4096];
    const char *prompt = lisp_x_get_prompt();

    /* Print initial prompt */
    printf("%s", prompt);
    fflush(stdout);

    while (!g_quit_requested) {
#ifdef _WIN32
        /* Windows: Simple polling approach */
        if (_kbhit()) {
            /* Read input line using lineedit */
            char *line = lineedit_readline(g_lineedit, prompt);
            if (line == NULL) {
                /* EOF or error */
                g_quit_requested = 1;
                break;
            }

            if (line[0] != '\0') {
                lineedit_history_add(g_lineedit, line);

                /* Check for command */
                if (line[0] == ':') {
                    process_command(line, g_telnet, &g_connected,
                                    &g_quit_requested, g_term_cols, g_term_rows);
                } else if (g_connected) {
                    /* Process through user input hook */
                    const char *processed = lisp_x_call_user_input_hook(line, strlen(line));
                    if (processed && processed[0] != '\0') {
                        telnet_send_with_crlf(g_telnet, processed, strlen(processed));
                    }
                } else {
                    printf("Not connected. Use :connect <host> <port>\r\n");
                }
            }

            free(line);
            prompt = lisp_x_get_prompt();
            printf("%s", prompt);
            fflush(stdout);
        }

        /* Check telnet socket */
        if (g_connected) {
            int received = telnet_receive(g_telnet, recv_buffer, sizeof(recv_buffer) - 1);
            if (received < 0) {
                g_connected = 0;
                printf("\r\n*** Connection lost ***\r\n%s", prompt);
                fflush(stdout);
            } else if (received > 0) {
                recv_buffer[received] = '\0';

                /* Call input hooks */
                lisp_x_call_telnet_input_hook(recv_buffer, received);
                size_t filtered_len;
                const char *filtered = lisp_x_call_telnet_input_filter_hook(
                    recv_buffer, received, &filtered_len);

                /* Output to terminal */
                fwrite(filtered, 1, filtered_len, stdout);
                fflush(stdout);
            }
        }

        /* Run timers */
        lisp_x_run_timers();

        Sleep(10); /* Small delay to prevent busy-waiting */
#else
        /* Unix: Use select() for multiplexing */
        fd_set read_fds;
        struct timeval tv;
        int max_fd = STDIN_FILENO;

        FD_ZERO(&read_fds);
        FD_SET(STDIN_FILENO, &read_fds);

        if (g_connected) {
            int sock = telnet_get_socket(g_telnet);
            if (sock >= 0) {
                FD_SET(sock, &read_fds);
                if (sock > max_fd)
                    max_fd = sock;
            }
        }

        /* Timer tick every 100ms */
        tv.tv_sec = 0;
        tv.tv_usec = 100000;

        int ready = select(max_fd + 1, &read_fds, NULL, NULL, &tv);

        if (ready < 0) {
            if (errno == EINTR)
                continue;
            perror("select");
            break;
        }

        /* Handle stdin input */
        if (FD_ISSET(STDIN_FILENO, &read_fds)) {
            char *line = lineedit_readline(g_lineedit, prompt);

            if (line == NULL) {
                /* EOF (Ctrl+D) */
                g_quit_requested = 1;
                printf("\r\n");
                break;
            }

            if (line[0] != '\0') {
                lineedit_history_add(g_lineedit, line);

                /* Check for command */
                if (line[0] == ':') {
                    process_command(line, g_telnet, &g_connected,
                                    &g_quit_requested, g_term_cols, g_term_rows);
                } else if (g_connected) {
                    /* Process through user input hook */
                    const char *processed = lisp_x_call_user_input_hook(line, strlen(line));
                    if (processed && processed[0] != '\0') {
                        telnet_send_with_crlf(g_telnet, processed, strlen(processed));
                    }
                } else {
                    printf("Not connected. Use :connect <host> <port>\r\n");
                }
            }

            free(line);
            prompt = lisp_x_get_prompt();
            printf("%s", prompt);
            fflush(stdout);
        }

        /* Handle telnet socket */
        if (g_connected) {
            int sock = telnet_get_socket(g_telnet);
            if (sock >= 0 && FD_ISSET(sock, &read_fds)) {
                int received = telnet_receive(g_telnet, recv_buffer, sizeof(recv_buffer) - 1);
                if (received < 0) {
                    g_connected = 0;
                    printf("\r\n*** Connection lost ***\r\n%s", prompt);
                    fflush(stdout);
                } else if (received > 0) {
                    recv_buffer[received] = '\0';

                    /* Call input hooks */
                    lisp_x_call_telnet_input_hook(recv_buffer, received);
                    size_t filtered_len;
                    const char *filtered = lisp_x_call_telnet_input_filter_hook(
                        recv_buffer, received, &filtered_len);

                    /* Output to terminal */
                    fwrite(filtered, 1, filtered_len, stdout);
                    fflush(stdout);
                }
            }
        }

        /* Run timers */
        lisp_x_run_timers();
#endif
    }

    return 0;
}

int main(int argc, char *argv[]) {
    const char *hostname = NULL;
    int port = 23;
    const char *load_file = NULL;

    /* Parse command line arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--version") == 0) {
            print_version();
            return 0;
        } else if ((strcmp(argv[i], "-l") == 0 || strcmp(argv[i], "--load") == 0) && i + 1 < argc) {
            load_file = argv[++i];
        } else if (argv[i][0] != '-') {
            if (!hostname) {
                hostname = argv[i];
            } else {
                port = atoi(argv[i]);
                if (port <= 0 || port > 65535) {
                    fprintf(stderr, "Invalid port: %s\n", argv[i]);
                    return 1;
                }
            }
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }

    /* Initialize GC */
    GC_INIT();

    /* Register cleanup */
    atexit(cleanup);

    /* Setup signal handlers */
    signal(SIGINT, handle_sigint);
#ifndef _WIN32
    signal(SIGWINCH, handle_sigwinch);
#endif

    /* Get terminal size */
    update_terminal_size();

    /* Detect terminal capabilities */
    if (termcaps_init() < 0) {
        fprintf(stderr, "Warning: Could not detect terminal capabilities\n");
    }

    /* Initialize Lisp */
    if (lisp_x_init() < 0) {
        fprintf(stderr, "Failed to initialize Lisp interpreter\n");
        return 1;
    }

    /* Load additional script if specified */
    if (load_file) {
        if (lisp_x_load_file(load_file) < 0) {
            fprintf(stderr, "Failed to load: %s\n", load_file);
        }
    }

    /* Create telnet client */
    g_telnet = telnet_create();
    if (!g_telnet) {
        fprintf(stderr, "Failed to create telnet client\n");
        return 1;
    }

    /* Register telnet with Lisp extension */
    lisp_x_register_telnet(g_telnet);

    /* Create lineedit state */
    g_lineedit = lineedit_create();
    if (!g_lineedit) {
        fprintf(stderr, "Failed to create line editor\n");
        return 1;
    }

    /* Configure lineedit */
    lineedit_set_history_size(g_lineedit, lisp_x_get_input_history_size());
    lineedit_set_completer(g_lineedit, lisp_x_complete, NULL);

    /* Load init-post.lisp */
    lisp_x_load_init_post();

    /* Print banner */
    printf("bloom-telnet %s - Type :help for commands\n", BLOOM_TELNET_VERSION);

    /* Connect if hostname provided */
    if (hostname) {
        printf("Connecting to %s:%d...\n", hostname, port);
        if (telnet_connect(g_telnet, hostname, port) < 0) {
            fprintf(stderr, "Failed to connect to %s:%d\n", hostname, port);
        } else {
            g_connected = 1;
            telnet_set_terminal_size(g_telnet, g_term_cols, g_term_rows);
            printf("Connected.\n");
        }
    }

    /* Enable raw mode for terminal */
    if (enable_raw_mode() < 0) {
        fprintf(stderr, "Warning: Could not enable raw terminal mode\n");
    }

    /* Run main event loop */
    int result = run_event_loop();

    /* Cleanup handled by atexit */
    printf("\nGoodbye.\n");

    return result;
}
