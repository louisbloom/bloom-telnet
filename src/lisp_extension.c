/* Lisp extension implementation for bloom-telnet */

#include "lisp_extension.h"
#include "../include/telnet.h"
#include "../include/terminal_caps.h"
#include "path_utils.h"
#include <bloom-boba/dynamic_buffer.h>
#include <bloom-lisp/file_utils.h>
#include <bloom-lisp/lisp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Lisp environment for hooks and primitives */
static Environment *lisp_env = NULL;

/* Registered telnet pointer for telnet-send builtin */
static Telnet *registered_telnet = NULL;

/* Terminal echo callback */
static TerminalEchoCallback echo_callback = NULL;

/* Static buffers for hook processing */
static char *ansi_strip_buffer = NULL;
static size_t ansi_strip_buffer_size = 0;

static char *telnet_filter_buffer = NULL;
static size_t telnet_filter_buffer_size = 0;

static char *telnet_filter_temp_buffer = NULL;
static size_t telnet_filter_temp_buffer_size = 0;

static char *user_input_hook_buffer = NULL;
static size_t user_input_hook_buffer_size = 0;

/* Utility function to ensure a buffer is large enough */
static int ensure_buffer_size(char **buffer, size_t *buffer_size,
                              size_t required_size) {
  if (!buffer || !buffer_size) {
    return -1;
  }

  if (!*buffer || *buffer_size < required_size) {
    size_t new_size = required_size;
    if (*buffer_size > 0) {
      new_size = *buffer_size;
      while (new_size < required_size) {
        new_size *= 2;
      }
    } else {
      if (new_size < 4096) {
        new_size = 4096;
      }
    }
    char *new_buffer = realloc(*buffer, new_size);
    if (!new_buffer) {
      return -1;
    }
    *buffer = new_buffer;
    *buffer_size = new_size;
  }
  return 0;
}

/* Strip ANSI escape sequences from input */
static char *strip_ansi_codes(const char *input, size_t len, size_t *out_len) {
  if (!input || len == 0 || !out_len) {
    if (out_len)
      *out_len = 0;
    return NULL;
  }

  if (!ansi_strip_buffer || ansi_strip_buffer_size < len + 1) {
    size_t new_size = len + 1;
    if (new_size < 4096) {
      new_size = 4096;
    }
    char *new_buffer = realloc(ansi_strip_buffer, new_size);
    if (!new_buffer) {
      if (out_len)
        *out_len = 0;
      return NULL;
    }
    ansi_strip_buffer = new_buffer;
    ansi_strip_buffer_size = new_size;
  }

  size_t out_pos = 0;
  int in_escape = 0;
  int in_csi = 0;

  for (size_t i = 0; i < len; i++) {
    unsigned char c = (unsigned char)input[i];

    if (in_escape) {
      if (c == '[') {
        in_csi = 1;
        in_escape = 0;
      } else if (c >= 0x40 && c <= 0x5F) {
        in_escape = 0;
      } else if (c == 0x1B) {
        /* Another ESC */
      } else {
        in_escape = 0;
      }
      continue;
    }

    if (in_csi) {
      if ((c >= 0x40 && c <= 0x7E) || c == 0x1B) {
        in_csi = 0;
        if (c == 0x1B) {
          in_escape = 1;
        }
      }
      continue;
    }

    if (c == 0x1B) {
      in_escape = 1;
      continue;
    }

    if (c >= 0x20 || c == '\n' || c == '\r' || c == '\t') {
      if (out_pos < ansi_strip_buffer_size - 1) {
        ansi_strip_buffer[out_pos++] = c;
      }
    }
  }

  ansi_strip_buffer[out_pos] = '\0';
  *out_len = out_pos;
  return ansi_strip_buffer;
}

/* Builtin: strip-ansi - Remove ANSI escape sequences from text */
static LispObject *builtin_strip_ansi(LispObject *args, Environment *env) {
  (void)env;

  if (args == NIL) {
    return lisp_make_error("strip-ansi requires 1 argument");
  }

  LispObject *text_obj = lisp_car(args);
  if (text_obj->type != LISP_STRING) {
    return lisp_make_error("strip-ansi: argument must be a string");
  }

  const char *text = text_obj->value.string;
  size_t len = strlen(text);
  size_t out_len = 0;

  char *stripped = strip_ansi_codes(text, len, &out_len);
  if (!stripped) {
    return lisp_make_string("");
  }

  return lisp_make_string(stripped);
}

/* Builtin: terminal-echo - Output text to textview/stdout (local echo) */
static LispObject *builtin_terminal_echo(LispObject *args, Environment *env) {
  (void)env;

  if (args == NIL) {
    return NIL;
  }

  LispObject *text_obj = lisp_car(args);
  if (text_obj->type != LISP_STRING) {
    return lisp_make_error("terminal-echo: argument must be a string");
  }

  const char *text = text_obj->value.string;
  size_t len = strlen(text);

  /* Use callback if registered (handles scroll region positioning) */
  if (echo_callback) {
    echo_callback(text, len);
  } else {
    /* Fallback: output to stdout, converting \n to \r\n */
    for (const char *p = text; *p; p++) {
      if (*p == '\n' && (p == text || *(p - 1) != '\r')) {
        putchar('\r');
      }
      putchar(*p);
    }
    fflush(stdout);
  }

  return NIL;
}

/* Builtin: telnet-send - Send text to telnet server */
static LispObject *builtin_telnet_send(LispObject *args, Environment *env) {
  (void)env;

  if (!registered_telnet) {
    return lisp_make_error("telnet-send: no telnet connection registered");
  }

  if (args == NIL) {
    return lisp_make_error("telnet-send requires 1 argument");
  }

  LispObject *text_obj = lisp_car(args);
  if (text_obj->type != LISP_STRING) {
    return lisp_make_error("telnet-send: argument must be a string");
  }

  const char *text = text_obj->value.string;
  size_t len = strlen(text);

  /* Send with CRLF appended */
  int result = telnet_send_with_crlf(registered_telnet, text, len);
  if (result < 0) {
    return lisp_make_error("telnet-send: failed to send data");
  }

  return NIL;
}

/* Builtin: termcap - Unified terminal capability query */
static LispObject *builtin_termcap(LispObject *args, Environment *env) {
  (void)env;
  extern int g_term_cols;
  extern int g_term_rows;

  if (args == NIL) {
    return lisp_make_error("termcap requires at least 1 argument");
  }

  LispObject *key = lisp_car(args);
  if (key->type != LISP_SYMBOL) {
    return lisp_make_error("termcap: first argument must be a symbol");
  }

  const char *name = key->value.symbol->name;
  args = lisp_cdr(args);

  /* Simple queries */
  if (strcmp(name, "cols") == 0)
    return lisp_make_integer(g_term_cols);
  if (strcmp(name, "rows") == 0)
    return lisp_make_integer(g_term_rows);
  if (strcmp(name, "type") == 0) {
    const char *t = termcaps_get_term_type();
    return lisp_make_string(t ? t : "");
  }
  if (strcmp(name, "encoding") == 0) {
    const char *e = termcaps_get_encoding();
    return lisp_make_string(e ? e : "ASCII");
  }
  if (strcmp(name, "color-level") == 0)
    return lisp_make_integer(termcaps_get_color_level());
  if (strcmp(name, "truecolor?") == 0)
    return termcaps_supports_truecolor() ? LISP_TRUE : NIL;
  if (strcmp(name, "256color?") == 0)
    return termcaps_supports_256color() ? LISP_TRUE : NIL;
  if (strcmp(name, "unicode?") == 0)
    return termcaps_supports_unicode() ? LISP_TRUE : NIL;
  if (strcmp(name, "describe") == 0) {
    const char *d = termcaps_describe();
    return lisp_make_string(d ? d : "");
  }
  if (strcmp(name, "reset") == 0) {
    const char *s = termcaps_format_reset();
    return lisp_make_string(s ? s : "");
  }

  /* Color queries with RGB args */
  if (strcmp(name, "fg-color") == 0 || strcmp(name, "bg-color") == 0) {
    if (args == NIL)
      return lisp_make_error("termcap: fg-color/bg-color need r g b");
    LispObject *r_obj = lisp_car(args);
    args = lisp_cdr(args);
    if (args == NIL)
      return lisp_make_error("termcap: fg-color/bg-color need r g b");
    LispObject *g_obj = lisp_car(args);
    args = lisp_cdr(args);
    if (args == NIL)
      return lisp_make_error("termcap: fg-color/bg-color need r g b");
    LispObject *b_obj = lisp_car(args);

    if (r_obj->type != LISP_INTEGER || g_obj->type != LISP_INTEGER ||
        b_obj->type != LISP_INTEGER) {
      return lisp_make_error("termcap: color args must be integers");
    }

    int r = (int)r_obj->value.integer;
    int g = (int)g_obj->value.integer;
    int b = (int)b_obj->value.integer;

    const char *seq = (strcmp(name, "fg-color") == 0)
                          ? termcaps_format_fg_color(r, g, b)
                          : termcaps_format_bg_color(r, g, b);
    return lisp_make_string(seq ? seq : "");
  }

  return lisp_make_error("termcap: unknown capability");
}

/* Load a Lisp file from standard search paths */
static int load_lisp_system_file(const char *filename) {
  if (!lisp_env || !filename) {
    return 0;
  }

  char *base_path = path_get_exe_directory();
  char exe_relative_path[1024] = {0};
  char lisp_subdir_path[256];
  char parent_lisp_path[256];
  const char *search_paths[10];
  int path_count = 0;

  /* Try executable-relative path first */
  if (base_path) {
    if (path_construct_exe_relative(base_path, filename, exe_relative_path,
                                    sizeof(exe_relative_path))) {
      search_paths[path_count++] = exe_relative_path;
    }
    free(base_path);
  }

  /* Source tree paths for development */
  snprintf(lisp_subdir_path, sizeof(lisp_subdir_path), "lisp/%s", filename);
  search_paths[path_count++] = lisp_subdir_path;

  snprintf(parent_lisp_path, sizeof(parent_lisp_path), "../lisp/%s", filename);
  search_paths[path_count++] = parent_lisp_path;

  /* Installed path */
  static char installed_path[TELNET_MAX_PATH];
  if (path_construct_installed_resource("lisp", filename, installed_path,
                                        sizeof(installed_path))) {
    search_paths[path_count++] = installed_path;
  }

  search_paths[path_count] = NULL;

  for (int i = 0; search_paths[i] != NULL; i++) {
    FILE *test = file_open(search_paths[i], "rb");
    if (test) {
      fclose(test);
      LispObject *result = lisp_load_file(search_paths[i], lisp_env);
      if (result && result->type == LISP_ERROR) {
        char *err_str = lisp_print(result);
        fprintf(stderr, "Lisp error loading %s: %s\n", search_paths[i],
                err_str);
      } else {
        fprintf(stderr, "Loaded: %s\n", search_paths[i]);
        return 1;
      }
    }
  }

  fprintf(stderr, "Failed to load Lisp file: %s\n", filename);
  return 0;
}

/* Initialize Lisp interpreter and environment */
int lisp_x_init(void) {
  if (lisp_init() < 0) {
    fprintf(stderr, "Failed to initialize Lisp interpreter\n");
    return -1;
  }

  lisp_env = env_create_global();
  if (!lisp_env) {
    fprintf(stderr, "Failed to create Lisp environment\n");
    lisp_cleanup();
    return -1;
  }

  /* Allocate static buffers */
  ansi_strip_buffer_size = 4096;
  ansi_strip_buffer = malloc(ansi_strip_buffer_size);

  telnet_filter_buffer_size = 4096;
  telnet_filter_buffer = malloc(telnet_filter_buffer_size);

  telnet_filter_temp_buffer_size = 4096;
  telnet_filter_temp_buffer = malloc(telnet_filter_temp_buffer_size);

  user_input_hook_buffer_size = 4096;
  user_input_hook_buffer = malloc(user_input_hook_buffer_size);

  if (!ansi_strip_buffer || !telnet_filter_buffer ||
      !telnet_filter_temp_buffer || !user_input_hook_buffer) {
    fprintf(stderr, "Failed to allocate buffers\n");
    lisp_x_cleanup();
    return -1;
  }

  /* Register builtins */
  env_define(lisp_env, "strip-ansi",
             lisp_make_builtin(builtin_strip_ansi, "strip-ansi"));
  env_define(lisp_env, "terminal-echo",
             lisp_make_builtin(builtin_terminal_echo, "terminal-echo"));
  env_define(lisp_env, "telnet-send",
             lisp_make_builtin(builtin_telnet_send, "telnet-send"));

  /* Terminal capability builtin */
  env_define(lisp_env, "termcap",
             lisp_make_builtin(builtin_termcap, "termcap"));

  /* Define default configuration variables */
  env_define(lisp_env, "*input-history-size*", lisp_make_integer(100));
  env_define(lisp_env, "*prompt*", lisp_make_string("> "));

  /* Define default hooks as identity functions */
  LispObject *identity_hook = lisp_eval_string("(lambda (x) x)", lisp_env);
  if (identity_hook && identity_hook->type != LISP_ERROR) {
    env_define(lisp_env, "telnet-input-hook", identity_hook);
    env_define(lisp_env, "telnet-input-filter-hook", identity_hook);
  }

  LispObject *user_hook =
      lisp_eval_string("(lambda (text cursor) text)", lisp_env);
  if (user_hook && user_hook->type != LISP_ERROR) {
    env_define(lisp_env, "user-input-hook", user_hook);
  }

  /* Load init.lisp */
  load_lisp_system_file("init.lisp");

  return 0;
}

/* Load additional Lisp file */
int lisp_x_load_file(const char *filepath) {
  if (!lisp_env || !filepath) {
    return -1;
  }

  /* If path is absolute, load directly */
  if (path_is_absolute(filepath)) {
    LispObject *result = lisp_load_file(filepath, lisp_env);
    if (result && result->type == LISP_ERROR) {
      char *err_str = lisp_print(result);
      fprintf(stderr, "Error loading %s: %s\n", filepath, err_str);
      return -1;
    }
    return 0;
  }

  /* Try relative paths */
  return load_lisp_system_file(filepath) ? 0 : -1;
}

/* Cleanup Lisp interpreter */
void lisp_x_cleanup(void) {
  if (ansi_strip_buffer) {
    free(ansi_strip_buffer);
    ansi_strip_buffer = NULL;
    ansi_strip_buffer_size = 0;
  }

  if (telnet_filter_buffer) {
    free(telnet_filter_buffer);
    telnet_filter_buffer = NULL;
    telnet_filter_buffer_size = 0;
  }

  if (telnet_filter_temp_buffer) {
    free(telnet_filter_temp_buffer);
    telnet_filter_temp_buffer = NULL;
    telnet_filter_temp_buffer_size = 0;
  }

  if (user_input_hook_buffer) {
    free(user_input_hook_buffer);
    user_input_hook_buffer = NULL;
    user_input_hook_buffer_size = 0;
  }

  if (lisp_env) {
    env_free(lisp_env);
    lisp_env = NULL;
  }

  lisp_cleanup();
}

/* Call telnet-input-hook with stripped ANSI text */
void lisp_x_call_telnet_input_hook(const char *text, size_t len) {
  if (!lisp_env || !text || len == 0) {
    return;
  }

  size_t stripped_len = 0;
  char *stripped_text = strip_ansi_codes(text, len, &stripped_len);
  if (!stripped_text || stripped_len == 0) {
    return;
  }

  LispObject *hook = env_lookup(lisp_env, "telnet-input-hook");
  if (!hook || (hook->type != LISP_LAMBDA && hook->type != LISP_BUILTIN)) {
    return;
  }

  LispObject *text_arg = lisp_make_string(stripped_text);
  if (!text_arg || text_arg->type == LISP_ERROR) {
    return;
  }

  LispObject *args = lisp_make_cons(text_arg, NIL);
  LispObject *call_expr = lisp_make_cons(hook, args);
  LispObject *result = lisp_eval(call_expr, lisp_env);

  if (result && result->type == LISP_ERROR) {
    char *err_str = lisp_print(result);
    if (err_str) {
      fprintf(stderr, "Error in telnet-input-hook: %s\n", err_str);
    }
  }
}

/* Run all due timers */
void lisp_x_run_timers(void) {
  if (!lisp_env)
    return;

  LispObject *fn = env_lookup(lisp_env, "run-timers");
  if (!fn || (fn->type != LISP_LAMBDA && fn->type != LISP_BUILTIN))
    return;

  LispObject *call = lisp_make_cons(fn, NIL);
  LispObject *result = lisp_eval(call, lisp_env);

  if (result && result->type == LISP_ERROR) {
    char *err_str = lisp_print(result);
    if (err_str) {
      fprintf(stderr, "Error in run-timers: %s\n", err_str);
    }
  }
}

/* Call telnet-input-filter-hook */
const char *lisp_x_call_telnet_input_filter_hook(const char *text, size_t len,
                                                 size_t *out_len) {
  if (!lisp_env || !text || len == 0 || !out_len) {
    if (out_len)
      *out_len = len;
    return text;
  }

  LispObject *hook = env_lookup(lisp_env, "telnet-input-filter-hook");
  if (!hook || (hook->type != LISP_LAMBDA && hook->type != LISP_BUILTIN)) {
    *out_len = len;
    return text;
  }

  if (ensure_buffer_size(&telnet_filter_temp_buffer,
                         &telnet_filter_temp_buffer_size, len + 1) < 0) {
    *out_len = len;
    return text;
  }

  memcpy(telnet_filter_temp_buffer, text, len);
  telnet_filter_temp_buffer[len] = '\0';

  LispObject *arg = lisp_make_string(telnet_filter_temp_buffer);
  if (!arg || arg->type == LISP_ERROR) {
    *out_len = len;
    return text;
  }

  LispObject *args = lisp_make_cons(arg, NIL);
  LispObject *call_expr = lisp_make_cons(hook, args);
  LispObject *result = lisp_eval(call_expr, lisp_env);

  if (!result || result->type == LISP_ERROR) {
    char *err_str = lisp_print(result);
    if (err_str) {
      fprintf(stderr, "Error in telnet-input-filter-hook: %s\n", err_str);
    }
    *out_len = len;
    return text;
  }

  if (result->type != LISP_STRING) {
    *out_len = len;
    return text;
  }

  const char *transformed = result->value.string;
  size_t transformed_len = strlen(transformed);

  if (ensure_buffer_size(&telnet_filter_buffer, &telnet_filter_buffer_size,
                         transformed_len + 1) < 0) {
    *out_len = len;
    return text;
  }

  memcpy(telnet_filter_buffer, transformed, transformed_len);
  telnet_filter_buffer[transformed_len] = '\0';
  *out_len = transformed_len;

  return telnet_filter_buffer;
}

/* Call user-input-hook */
const char *lisp_x_call_user_input_hook(const char *text, int cursor_pos) {
  if (!lisp_env || !text) {
    return text;
  }

  LispObject *hook = env_lookup(lisp_env, "user-input-hook");
  if (!hook || (hook->type != LISP_LAMBDA && hook->type != LISP_BUILTIN)) {
    return text;
  }

  LispObject *text_arg = lisp_make_string(text);
  if (!text_arg || text_arg->type == LISP_ERROR) {
    return text;
  }

  LispObject *cursor_arg = lisp_make_integer(cursor_pos);
  if (!cursor_arg || cursor_arg->type == LISP_ERROR) {
    return text;
  }

  LispObject *args = lisp_make_cons(text_arg, lisp_make_cons(cursor_arg, NIL));
  LispObject *call_expr = lisp_make_cons(hook, args);
  LispObject *result = lisp_eval(call_expr, lisp_env);

  if (!result || result->type == LISP_ERROR) {
    char *err_str = lisp_print(result);
    if (err_str) {
      fprintf(stderr, "Error in user-input-hook: %s\n", err_str);
    }
    if (text && text[0] == '#') {
      return "";
    }
    return text;
  }

  if (result->type != LISP_STRING) {
    return "";
  }

  const char *transformed = result->value.string;
  size_t transformed_len = strlen(transformed);

  if (ensure_buffer_size(&user_input_hook_buffer, &user_input_hook_buffer_size,
                         transformed_len + 1) < 0) {
    return text;
  }

  memcpy(user_input_hook_buffer, transformed, transformed_len);
  user_input_hook_buffer[transformed_len] = '\0';

  return user_input_hook_buffer;
}

/* Get input history size from Lisp config */
int lisp_x_get_input_history_size(void) {
  if (!lisp_env) {
    return 100;
  }

  LispObject *value = env_lookup(lisp_env, "*input-history-size*");
  if (value && value->type == LISP_INTEGER) {
    int size = (int)value->value.integer;
    if (size > 0) {
      return size;
    }
  }
  return 100;
}

/* Register telnet instance */
void lisp_x_register_telnet(Telnet *t) { registered_telnet = t; }

/* Get lisp environment */
void *lisp_x_get_environment(void) { return lisp_env; }

/* Evaluate Lisp code and echo results */
int lisp_x_eval_and_echo(const char *code, DynamicBuffer *buf) {
  if (!lisp_env || !code || !buf) {
    return -1;
  }

  dynamic_buffer_clear(buf);

  /* Echo the command */
  dynamic_buffer_append_str(buf, "> ");
  dynamic_buffer_append_str(buf, code);
  dynamic_buffer_append_str(buf, "\r\n");

  /* Evaluate */
  LispObject *result = lisp_eval_string(code, lisp_env);

  if (result && result->type == LISP_ERROR) {
    dynamic_buffer_append_str(buf, "; Error: ");
    char *err_str = lisp_print(result);
    if (err_str) {
      /* Replace \n with \r\n */
      for (const char *p = err_str; *p; p++) {
        if (*p == '\n') {
          dynamic_buffer_append(buf, "\r\n", 2);
        } else {
          dynamic_buffer_append(buf, p, 1);
        }
      }
    }
    dynamic_buffer_append_str(buf, "\r\n");
  } else if (result) {
    char *result_str = lisp_print(result);
    if (result_str) {
      for (const char *p = result_str; *p; p++) {
        if (*p == '\n') {
          dynamic_buffer_append(buf, "\r\n", 2);
        } else {
          dynamic_buffer_append(buf, p, 1);
        }
      }
      dynamic_buffer_append_str(buf, "\r\n");
    }
  }

  return 0;
}

/* Load init-post.lisp */
void lisp_x_load_init_post(void) { load_lisp_system_file("init-post.lisp"); }

/* Get prompt string from Lisp config */
const char *lisp_x_get_prompt(void) {
  if (!lisp_env) {
    return "> ";
  }

  LispObject *value = env_lookup(lisp_env, "*prompt*");
  if (value && value->type == LISP_STRING) {
    return value->value.string;
  }
  return "> ";
}

/* Completion callback for lineedit */
char **lisp_x_complete(const char *buffer, int cursor_pos, void *userdata) {
  (void)userdata;

  if (!lisp_env || !buffer) {
    return NULL;
  }

  /* Look up completion-hook */
  LispObject *hook = env_lookup(lisp_env, "completion-hook");
  if (!hook || (hook->type != LISP_LAMBDA && hook->type != LISP_BUILTIN)) {
    return NULL;
  }

  /* Extract partial text (word before cursor) */
  int start = cursor_pos;
  while (start > 0 && buffer[start - 1] != ' ' && buffer[start - 1] != '\t') {
    start--;
  }

  char partial[256];
  int partial_len = cursor_pos - start;
  if (partial_len >= (int)sizeof(partial)) {
    partial_len = sizeof(partial) - 1;
  }
  memcpy(partial, buffer + start, partial_len);
  partial[partial_len] = '\0';

  /* Call hook with partial text */
  LispObject *arg = lisp_make_string(partial);
  LispObject *args = lisp_make_cons(arg, NIL);
  LispObject *call_expr = lisp_make_cons(hook, args);
  LispObject *result = lisp_eval(call_expr, lisp_env);

  if (!result || result->type == LISP_ERROR || result == NIL) {
    return NULL;
  }

  /* Convert result list to char** array */
  int count = 0;
  LispObject *p = result;
  while (p != NIL && p->type == LISP_CONS) {
    count++;
    p = lisp_cdr(p);
  }

  if (count == 0) {
    return NULL;
  }

  char **completions = malloc((count + 1) * sizeof(char *));
  if (!completions) {
    return NULL;
  }

  int i = 0;
  p = result;
  while (p != NIL && p->type == LISP_CONS && i < count) {
    LispObject *item = lisp_car(p);
    if (item && item->type == LISP_STRING) {
      completions[i] = strdup(item->value.string);
    } else {
      completions[i] = strdup("");
    }
    i++;
    p = lisp_cdr(p);
  }
  completions[i] = NULL;

  return completions;
}

/* Register terminal echo callback */
void lisp_x_register_echo_callback(TerminalEchoCallback callback) {
  echo_callback = callback;
}
