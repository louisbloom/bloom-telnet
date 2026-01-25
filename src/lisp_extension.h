/* Lisp interface for bloom-telnet */

#ifndef BLOOM_TELNET_LISP_H
#define BLOOM_TELNET_LISP_H

#include "dynamic_buffer.h"
#include <stddef.h>

/* Initialize Lisp interpreter, environment, and load init file */
int lisp_x_init(void);

/* Load and evaluate additional Lisp file (after init) */
int lisp_x_load_file(const char *filepath);

/* Cleanup Lisp interpreter */
void lisp_x_cleanup(void);

/* Call telnet-input-hook with telnet data (stripped of ANSI codes) */
void lisp_x_call_telnet_input_hook(const char *text, size_t len);

/* Run all due timers - calls (run-timers) in Lisp each frame */
void lisp_x_run_timers(void);

/* Call telnet-input-filter-hook with telnet data (with ANSI codes) before
 * displaying Returns transformed text or original */
const char *lisp_x_call_telnet_input_filter_hook(const char *text, size_t len,
                                                 size_t *out_len);

/* Call user-input-hook with user input before sending to telnet
 * Returns transformed text or original */
const char *lisp_x_call_user_input_hook(const char *text, int cursor_pos);

/* Get input history size from Lisp config (default: 100) */
int lisp_x_get_input_history_size(void);

/* Forward declaration for Telnet type (defined in telnet.h) */
struct Telnet;

/* Register telnet pointer for telnet-send builtin */
void lisp_x_register_telnet(struct Telnet *t);

/* Get lisp environment (for accessing Lisp variables from C) */
void *lisp_x_get_environment(void);

/* Evaluate Lisp code and build echo buffer (eval-mode style)
 * Uses preallocated DynamicBuffer
 * Output format: "> code\r\n" + (result or "; Error: ...\r\n")
 * Returns: 0 on success, -1 on failure
 */
int lisp_x_eval_and_echo(const char *code, DynamicBuffer *buf);

/* Load init-post.lisp after initialization is complete */
void lisp_x_load_init_post(void);

/* Get prompt string from Lisp config (default: "> ") */
const char *lisp_x_get_prompt(void);

/* Completion callback for lineedit - returns NULL-terminated array of
 * completions */
char **lisp_x_complete(const char *buffer, int cursor_pos, void *userdata);

#endif /* BLOOM_TELNET_LISP_H */
