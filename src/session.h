/* Session management for bloom-telnet
 *
 * A Session wraps a child Lisp environment (inheriting from a shared base env)
 * and an optional telnet connection. The base env holds builtins and init.lisp
 * definitions; each session env holds user-created bindings.
 */

#ifndef SESSION_H
#define SESSION_H

#include "../include/telnet.h"
#include <bloom-lisp/lisp.h>

typedef struct HookEntry {
  LispObject *fn;         /* Function value (LISP_LAMBDA or LISP_BUILTIN) */
  int priority;           /* Lower = runs first, default 50 */
  struct HookEntry *next; /* Sorted linked list */
} HookEntry;

typedef struct HookList {
  char *name;            /* Hook name (e.g. "telnet-input-hook") */
  HookEntry *entries;    /* Sorted by priority */
  struct HookList *next; /* Next hook in session's hook list */
} HookList;

typedef struct Session {
  int id;
  char *name;
  Environment *env; /* Child of base_env — user state lives here */
  Telnet *telnet;   /* Telnet connection (can be NULL) */
  int connected;
  HookList *hooks; /* Per-session hook registry */
} Session;

/* Initialize the session manager: create base env, register builtins,
 * load init.lisp. Must be called before any other session functions.
 * Returns 0 on success, -1 on failure. */
int session_manager_init(void);

/* Cleanup all sessions and the base environment */
void session_manager_cleanup(void);

/* Get the shared base environment (builtins + init.lisp) */
Environment *session_get_base_env(void);

/* Create a new session with a child environment. Returns the session,
 * or NULL on failure. The session is automatically added to the manager. */
Session *session_create(const char *name);

/* Destroy a session by ID. Disconnects telnet if connected.
 * Returns 0 on success, -1 if not found or if it's the current session. */
int session_destroy(int id);

/* Get/set the current active session */
Session *session_get_current(void);
void session_set_current(Session *session);

/* Find a session by ID or name. Returns NULL if not found. */
Session *session_find_by_id(int id);
Session *session_find_by_name(const char *name);

/* Get session count and array of all sessions */
int session_count(void);
Session **session_get_all(int *out_count);

/* Hook management */
HookList *session_get_hook_list(Session *session, const char *name);
int session_add_hook(Session *session, const char *name, LispObject *fn,
                     int priority);
int session_remove_hook(Session *session, const char *name, LispObject *fn);

#endif /* SESSION_H */
