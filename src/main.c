/* bloom-telnet - Terminal-based telnet client with Lisp scripting
 *
 * Main entry point implementing a TUI using raw terminal mode,
 * select()-based event loop, and software-based scrolling (Bubbletea-style).
 */

#include <errno.h>
#include <gc.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <conio.h>
#include <windows.h>
#include <winsock2.h>
#else
#include <sys/ioctl.h>
#include <sys/select.h>
#include <termios.h>
#include <unistd.h>
#endif

#include "../include/telnet.h"
#include "../include/terminal_caps.h"
#include "commands.h"
#include "lisp_extension.h"
#include "telnet_app.h"
#include <bloom-boba/ansi_sequences.h>
#include <bloom-boba/cmd.h>
#include <bloom-boba/dynamic_buffer.h>
#include <bloom-boba/input_parser.h>

/* Version information */
#define BLOOM_TELNET_VERSION "0.1.0"

/* Global state */
static Telnet *g_telnet = NULL;
static TelnetAppModel *g_app = NULL;
static TuiInputParser *g_input_parser = NULL;
static DynamicBuffer *g_render_buf = NULL;
static int g_connected = 0;
static int g_quit_requested = 0;
int g_term_rows = 24;
int g_term_cols = 80;

/* Convenience accessor for textinput component */
#define g_textinput (telnet_app_get_textinput(g_app))

#ifndef _WIN32
static struct termios g_orig_termios;
static int g_raw_mode = 0;
#endif

/* Event readiness structure for unified event handling */
typedef struct {
  int stdin_ready;
  int socket_ready;
  int error;
} EventReadiness;

/* Forward declarations */
static void cleanup(void);
static void handle_sigint(int sig);
static void handle_sigwinch(int sig);
static int enable_raw_mode(void);
static void disable_raw_mode(void);
static void update_terminal_size(void);
static void print_usage(const char *progname);
static void print_version(void);
static EventReadiness wait_for_events(int socket_fd);
static int handle_user_input(const char **prompt);
static int handle_telnet_data(char *recv_buffer, size_t buffer_size,
                              const char **prompt);
static void render_full_screen(void);
static void echo_to_viewport(const char *text, size_t len);

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
  if (g_app) {
    telnet_app_set_terminal_size(g_app, g_term_cols, g_term_rows);
  }
  /* Re-render on resize */
  render_full_screen();
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

  /* Move cursor to bottom of screen and clear line for clean exit */
  printf(CSI "%d;1H" CSI "K", g_term_rows);

  if (g_telnet) {
    if (g_connected) {
      telnet_disconnect(g_telnet);
    }
    telnet_destroy(g_telnet);
    g_telnet = NULL;
  }

  if (g_app) {
    telnet_app_free(g_app);
    g_app = NULL;
  }

  if (g_input_parser) {
    tui_input_parser_free(g_input_parser);
    g_input_parser = NULL;
  }

  if (g_render_buf) {
    dynamic_buffer_destroy(g_render_buf);
    g_render_buf = NULL;
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

/* Wait for events on stdin and/or socket */
static EventReadiness wait_for_events(int socket_fd) {
  EventReadiness events = {0, 0, 0};

#ifdef _WIN32
  /* Windows: Use _kbhit() for stdin, select() for socket */
  if (_kbhit()) {
    events.stdin_ready = 1;
  }

  if (socket_fd >= 0) {
    fd_set read_fds;
    struct timeval tv = {0, 0}; /* Zero timeout for non-blocking check */

    FD_ZERO(&read_fds);
    FD_SET((SOCKET)socket_fd, &read_fds);

    int ready = select(0, &read_fds, NULL, NULL, &tv);
    if (ready > 0 && FD_ISSET((SOCKET)socket_fd, &read_fds)) {
      events.socket_ready = 1;
    }
  }

  /* If nothing ready, sleep briefly to prevent busy-waiting */
  if (!events.stdin_ready && !events.socket_ready) {
    Sleep(10);
  }
#else
  /* Unix: Use select() for both stdin and socket */
  fd_set read_fds;
  struct timeval tv;
  int max_fd = STDIN_FILENO;

  FD_ZERO(&read_fds);
  FD_SET(STDIN_FILENO, &read_fds);

  if (socket_fd >= 0) {
    FD_SET(socket_fd, &read_fds);
    if (socket_fd > max_fd) {
      max_fd = socket_fd;
    }
  }

  /* Timer tick every 100ms */
  tv.tv_sec = 0;
  tv.tv_usec = 100000;

  int ready = select(max_fd + 1, &read_fds, NULL, NULL, &tv);

  if (ready < 0) {
    if (errno == EINTR) {
      /* Interrupted by signal, not an error */
      return events;
    }
    perror("select");
    events.error = 1;
    return events;
  }

  if (FD_ISSET(STDIN_FILENO, &read_fds)) {
    events.stdin_ready = 1;
  }

  if (socket_fd >= 0 && FD_ISSET(socket_fd, &read_fds)) {
    events.socket_ready = 1;
  }
#endif

  return events;
}

/* Process a submitted line */
static void process_line(const char *line, const char **prompt) {
  TuiTextInput *textinput = g_textinput;
  if (line[0] != '\0') {
    tui_textinput_history_add(textinput, line);
  }

  /* Check for command */
  if (line[0] == ':') {
    int was_connected = g_connected;
    echo_to_viewport("\n", 1);
    process_command(line, g_telnet, &g_connected, &g_quit_requested,
                    g_term_cols, g_term_rows);
    /* Update prompt visibility on connect/disconnect */
    if (g_connected && !was_connected) {
      telnet_app_set_show_prompt(g_app, 0);
    } else if (!g_connected && was_connected) {
      telnet_app_set_show_prompt(g_app, 1);
    }
  } else if (g_connected) {
    /* Echo user input to viewport */
    echo_to_viewport(line, strlen(line));
    echo_to_viewport("\n", 1);

    /* Process through user input hook (sends empty lines too) */
    const char *processed = lisp_x_call_user_input_hook(line, strlen(line));
    if (processed) {
      telnet_send_with_crlf(g_telnet, processed, strlen(processed));
    }
  } else if (line[0] != '\0') {
    echo_to_viewport("\nNot connected. Use :connect <host> <port>\n", 44);
  } else {
    /* Empty line when not connected */
    echo_to_viewport("\n", 1);
  }

  /* Update prompt */
  *prompt = lisp_x_get_prompt();
  telnet_app_set_prompt(g_app, *prompt);
}

/* Render the full screen (viewport + textinput) */
static void render_full_screen(void) {
  dynamic_buffer_clear(g_render_buf);

  /* Hide cursor during render to prevent flicker */
  dynamic_buffer_append_str(g_render_buf, CSI "?25l");

  /* Render viewport and textinput with absolute positioning */
  telnet_app_view(g_app, g_render_buf);

  /* Show cursor */
  dynamic_buffer_append_str(g_render_buf, CSI "?25h");

  /* Output all at once */
  fwrite(dynamic_buffer_data(g_render_buf), 1, dynamic_buffer_len(g_render_buf),
         stdout);
  fflush(stdout);
}

/* Echo callback for terminal-echo builtin */
static void echo_to_viewport(const char *text, size_t len) {
  if (g_app) {
    /* Append to viewport */
    telnet_app_echo(g_app, text, len);

    /* Re-render full screen */
    render_full_screen();
  }
}

/* Handle user input from stdin. Returns 0 on success, -1 on EOF/quit */
static int handle_user_input(const char **prompt) {
  unsigned char buf[256];
  ssize_t n;

#ifdef _WIN32
  /* Windows: Use _getch() for non-blocking input */
  n = 0;
  while (_kbhit() && n < sizeof(buf)) {
    buf[n++] = _getch();
  }
#else
  n = read(STDIN_FILENO, buf, sizeof(buf));
  if (n <= 0) {
    if (n == 0 || errno == EAGAIN || errno == EWOULDBLOCK) {
      return 0; /* No data available */
    }
    /* Error */
    g_quit_requested = 1;
    return -1;
  }
#endif

  /* Feed bytes to input parser and process messages */
  for (ssize_t i = 0; i < n; i++) {
    TuiMsg msg;
    if (tui_input_parser_feed(g_input_parser, buf[i], &msg)) {
      /* Route message through TelnetApp */
      TuiUpdateResult result = telnet_app_update(g_app, msg);

      /* Check for commands from textinput */
      if (result.cmd) {
        if (result.cmd->type == TUI_CMD_LINE_SUBMIT) {
          const char *line = result.cmd->payload.line;
          process_line(line, prompt);
          tui_cmd_free(result.cmd);
          render_full_screen();
        } else if (result.cmd->type == TUI_CMD_QUIT) {
          /* EOF (Ctrl+D on empty line) */
          g_quit_requested = 1;
          tui_cmd_free(result.cmd);
          echo_to_viewport("\n", 1);
          return -1;
        } else {
          tui_cmd_free(result.cmd);
        }
      } else {
        /* No command, just re-render */
        render_full_screen();
      }
    }
  }

  return 0;
}

/* Handle incoming telnet data. Returns 0 on success, -1 on disconnect */
static int handle_telnet_data(char *recv_buffer, size_t buffer_size,
                              const char **prompt) {
  (void)prompt; /* Unused */
  int received = telnet_receive(g_telnet, recv_buffer, buffer_size - 1);

  if (received < 0) {
    g_connected = 0;
    telnet_app_set_show_prompt(g_app, 1);
    echo_to_viewport("\n*** Connection lost ***\n", 25);
    return -1;
  }

  if (received > 0) {
    recv_buffer[received] = '\0';

    /* Call input hooks */
    lisp_x_call_telnet_input_hook(recv_buffer, received);
    size_t filtered_len;
    const char *filtered = lisp_x_call_telnet_input_filter_hook(
        recv_buffer, received, &filtered_len);

    /* Append filtered data to viewport */
    telnet_app_echo(g_app, filtered, filtered_len);

    /* Re-render full screen */
    render_full_screen();
  }

  return 0;
}

/* Main event loop */
static int run_event_loop(void) {
  char recv_buffer[4096];
  const char *prompt = lisp_x_get_prompt();

  /* Configure textinput with current state */
  telnet_app_set_prompt(g_app, prompt);
  telnet_app_set_show_prompt(g_app, g_connected ? 0 : 1);

  /* Clear screen and render initial state */
  printf(CSI "2J" CSI "H"); /* Clear screen and home cursor */
  fflush(stdout);
  render_full_screen();

  while (!g_quit_requested) {
    int socket_fd = g_connected ? telnet_get_socket(g_telnet) : -1;
    EventReadiness events = wait_for_events(socket_fd);

    if (events.error) {
      break;
    }

    if (events.stdin_ready) {
      if (handle_user_input(&prompt) < 0) {
        break;
      }
    }

    if (g_connected && events.socket_ready) {
      handle_telnet_data(recv_buffer, sizeof(recv_buffer), &prompt);
    }

    lisp_x_run_timers();
  }

  return 0;
}

int main(int argc, char *argv[]) {
  const char *hostname = NULL;
  int port = 23;
  const char **load_files = NULL;
  int load_file_count = 0;
  int load_file_capacity = 0;

  /* Parse command line arguments */
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
      print_usage(argv[0]);
      return 0;
    } else if (strcmp(argv[i], "-v") == 0 ||
               strcmp(argv[i], "--version") == 0) {
      print_version();
      return 0;
    } else if ((strcmp(argv[i], "-l") == 0 || strcmp(argv[i], "--load") == 0) &&
               i + 1 < argc) {
      if (load_file_count >= load_file_capacity) {
        load_file_capacity = load_file_capacity ? load_file_capacity * 2 : 4;
        load_files = realloc(load_files, load_file_capacity * sizeof(char *));
      }
      load_files[load_file_count++] = argv[++i];
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

  /* Register terminal echo callback */
  lisp_x_register_echo_callback(echo_to_viewport);

  /* Load additional scripts if specified */
  for (int i = 0; i < load_file_count; i++) {
    if (lisp_x_load_file(load_files[i]) < 0) {
      fprintf(stderr, "Failed to load: %s\n", load_files[i]);
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

  /* Create input parser */
  g_input_parser = tui_input_parser_create();
  if (!g_input_parser) {
    fprintf(stderr, "Failed to create input parser\n");
    return 1;
  }

  /* Create TelnetApp component (composes viewport + textinput) */
  TelnetAppConfig app_config = {
      .terminal_width = g_term_cols,
      .terminal_height = g_term_rows,
      .prompt = lisp_x_get_prompt(),
      .history_size = lisp_x_get_input_history_size(),
      .completer = lisp_x_complete,
      .completer_data = NULL,
  };
  g_app = telnet_app_create(&app_config);
  if (!g_app) {
    fprintf(stderr, "Failed to create TelnetApp\n");
    return 1;
  }

  /* Create render buffer */
  g_render_buf = dynamic_buffer_create(4096);
  if (!g_render_buf) {
    fprintf(stderr, "Failed to create render buffer\n");
    return 1;
  }

  /* Load init-post.lisp */
  lisp_x_load_init_post();

  /* Print banner to viewport */
  telnet_app_echo(g_app, "bloom-telnet ", 13);
  telnet_app_echo(g_app, BLOOM_TELNET_VERSION, strlen(BLOOM_TELNET_VERSION));
  telnet_app_echo(g_app, " - Type :help for commands\n", 27);

  /* Connect if hostname provided */
  if (hostname) {
    char msg[256];
    snprintf(msg, sizeof(msg), "Connecting to %s:%d...\n", hostname, port);
    telnet_app_echo(g_app, msg, strlen(msg));
    if (telnet_connect(g_telnet, hostname, port) < 0) {
      snprintf(msg, sizeof(msg), "Failed to connect to %s:%d\n", hostname,
               port);
      telnet_app_echo(g_app, msg, strlen(msg));
    } else {
      g_connected = 1;
      telnet_set_terminal_size(g_telnet, g_term_cols, g_term_rows);
      telnet_app_set_show_prompt(g_app, 0);
      telnet_app_echo(g_app, "Connected.\n", 11);
    }
  }

  /* Enable raw mode for terminal */
  if (enable_raw_mode() < 0) {
    fprintf(stderr, "Warning: Could not enable raw terminal mode\n");
  }

  /* Run main event loop */
  int result = run_event_loop();

  /* Cleanup handled by atexit */
  free(load_files);
  printf("\r\nGoodbye.\r\n");

  return result;
}
