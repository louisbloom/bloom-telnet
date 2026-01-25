/* Special colon commands implementation for bloom-telnet */

#include "commands.h"
#include "../include/telnet.h"
#include "dynamic_buffer.h"
#include "lisp_extension.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Helper: Output message to stdout */
static void output_message(const char *msg) {
  printf("%s", msg);
  fflush(stdout);
}

/* Process special commands (starting with :) */
int process_command(const char *text, Telnet *telnet, int *connected_mode,
                    int *quit_requested, int term_cols, int term_rows) {
  if (!text || text[0] != ':')
    return 0; /* Not a command */

  /* Skip the leading ':' */
  const char *cmd = text + 1;

  /* :help or :h command */
  if (strcmp(cmd, "help") == 0 || strcmp(cmd, "h") == 0) {
    output_message(
        "\r\n"
        "Available commands:\r\n"
        "  :help, :h                     - Show this help message\r\n"
        "  :connect <server> <port>      - Connect to a telnet server\r\n"
        "  :connect <server>:<port>      - Connect to a telnet server\r\n"
        "  :disconnect                   - Disconnect from current server\r\n"
        "  :load <filepath>              - Load and execute a Lisp file\r\n"
        "  :repl <code>                  - Evaluate Lisp code and show "
        "result\r\n"
        "  :quit, :q                     - Exit application\r\n"
        "\r\n");
    return 1;
  }

  /* :disconnect command */
  if (strcmp(cmd, "disconnect") == 0) {
    if (*connected_mode) {
      telnet_disconnect(telnet);
      *connected_mode = 0;
      output_message("\r\n*** Disconnected ***\r\n");
    } else {
      output_message("\r\n*** Not connected ***\r\n");
    }
    return 1;
  }

  /* :quit or :q command */
  if (strcmp(cmd, "quit") == 0 || strcmp(cmd, "q") == 0) {
    output_message("\r\n*** Exiting... ***\r\n");
    *quit_requested = 1;
    return 1;
  }

  /* :load command */
  if (strncmp(cmd, "load ", 5) == 0) {
    const char *filepath = cmd + 5;

    /* Skip leading spaces */
    while (*filepath == ' ')
      filepath++;

    if (*filepath == '\0') {
      output_message("\r\n*** Usage: :load <filepath> ***\r\n");
      return 1;
    }

    /* Remove trailing whitespace */
    size_t len = strlen(filepath);
    while (len > 0 &&
           (filepath[len - 1] == ' ' || filepath[len - 1] == '\t' ||
            filepath[len - 1] == '\r' || filepath[len - 1] == '\n')) {
      len--;
    }

    if (len == 0) {
      output_message("\r\n*** Error: Invalid filepath ***\r\n");
      return 1;
    }

    /* Copy filepath */
    char load_filepath[512] = {0};
    if (len >= sizeof(load_filepath)) {
      output_message("\r\n*** Error: Filepath too long ***\r\n");
      return 1;
    }
    memcpy(load_filepath, filepath, len);
    load_filepath[len] = '\0';

    /* Show loading message */
    printf("\r\n*** Loading: %s ***\r\n", load_filepath);
    fflush(stdout);

    /* Load and execute the file */
    int result = lisp_x_load_file(load_filepath);
    if (result < 0) {
      printf("\r\n*** Failed to load: %s ***\r\n", load_filepath);
    } else {
      output_message("\r\n*** File loaded successfully ***\r\n");
    }

    return 1;
  }

  /* :repl <code> - Evaluate Lisp code and echo result */
  if (strncmp(cmd, "repl ", 5) == 0) {
    const char *code = cmd + 5;

    /* Skip leading spaces */
    while (*code == ' ')
      code++;

    if (*code == '\0') {
      output_message("\r\n*** Usage: :repl <lisp-code> ***\r\n");
      return 1;
    }

    /* Use static preallocated buffer for eval output */
    static DynamicBuffer *eval_buf = NULL;
    if (!eval_buf) {
      eval_buf = dynamic_buffer_create(4096);
      if (!eval_buf) {
        output_message("\r\n*** Error: Buffer allocation failed ***\r\n");
        return 1;
      }
    }

    /* Delegate to eval mode logic */
    if (lisp_x_eval_and_echo(code, eval_buf) < 0) {
      output_message("\r\n*** Error: Buffer operation failed ***\r\n");
      return 1;
    }

    printf("%s", dynamic_buffer_data(eval_buf));
    fflush(stdout);
    return 1;
  }

  /* :connect command */
  if (strncmp(cmd, "connect ", 8) == 0) {
    const char *args = cmd + 8;

    /* Skip leading spaces */
    while (*args == ' ')
      args++;

    if (*args == '\0') {
      output_message("\r\n*** Usage: :connect <server> <port> or :connect "
                     "<server>:<port> ***\r\n");
      return 1;
    }

    /* Parse hostname and port */
    char hostname[256] = {0};
    int port = 0;

    /* Check for <server>:<port> format */
    const char *colon = strchr(args, ':');
    if (colon) {
      /* Format: server:port */
      size_t hostname_len = colon - args;
      if (hostname_len >= sizeof(hostname)) {
        output_message("\r\n*** Error: Hostname too long ***\r\n");
        return 1;
      }
      memcpy(hostname, args, hostname_len);
      hostname[hostname_len] = '\0';
      port = atoi(colon + 1);
    } else {
      /* Format: server port */
      const char *space = strchr(args, ' ');
      if (!space) {
        output_message("\r\n*** Usage: :connect <server> <port> or :connect "
                       "<server>:<port> ***\r\n");
        return 1;
      }
      size_t hostname_len = space - args;
      if (hostname_len >= sizeof(hostname)) {
        output_message("\r\n*** Error: Hostname too long ***\r\n");
        return 1;
      }
      memcpy(hostname, args, hostname_len);
      hostname[hostname_len] = '\0';

      /* Skip spaces before port */
      const char *port_str = space + 1;
      while (*port_str == ' ')
        port_str++;
      port = atoi(port_str);
    }

    /* Validate port */
    if (port <= 0 || port > 65535) {
      output_message(
          "\r\n*** Error: Invalid port number (must be 1-65535) ***\r\n");
      return 1;
    }

    /* Disconnect if already connected */
    if (*connected_mode) {
      telnet_disconnect(telnet);
      *connected_mode = 0;
    }

    /* Attempt connection */
    printf("\r\n*** Connecting to %s:%d... ***\r\n", hostname, port);
    fflush(stdout);

    if (telnet_connect(telnet, hostname, port) < 0) {
      printf("\r\n*** Failed to connect to %s:%d ***\r\n", hostname, port);
      fflush(stdout);
    } else {
      *connected_mode = 1;
      output_message("\r\n*** Connected ***\r\n");

      /* Send NAWS with terminal size */
      telnet_set_terminal_size(telnet, term_cols, term_rows);
    }
    return 1;
  }

  /* Unknown command */
  printf(
      "\r\n*** Unknown command: %s (type :help for available commands) ***\r\n",
      cmd);
  fflush(stdout);
  return 1;
}
