/* Session management implementation for bloom-telnet */

#include "session.h"
#include "logging.h"
#include <gc/gc.h>
#include <string.h>

#define MAX_SESSIONS 32

/* Session manager state */
static Environment *base_env = NULL;
static Session *sessions[MAX_SESSIONS];
static int session_count_val = 0;
static Session *current_session = NULL;
static int next_session_id = 1;

/* Clear hook list pointers for a session (GC handles deallocation) */
static void session_clear_hooks(Session *s) {
    s->hooks = NULL;
}

int session_manager_init(void) {
    if (base_env) {
        return 0; /* Already initialized */
    }

    base_env = env_create_global();
    if (!base_env) {
        bloom_log(LOG_ERROR, "session", "Failed to create base environment");
        return -1;
    }

    memset(sessions, 0, sizeof(sessions));
    session_count_val = 0;
    current_session = NULL;
    next_session_id = 1;

    return 0;
}

void session_manager_cleanup(void) {
    /* Destroy all sessions */
    for (int i = 0; i < session_count_val; i++) {
        if (sessions[i]) {
            if (sessions[i]->telnet && sessions[i]->connected) {
                telnet_disconnect(sessions[i]->telnet);
            }
            session_clear_hooks(sessions[i]);
            sessions[i] = NULL;
        }
    }
    session_count_val = 0;
    current_session = NULL;

    if (base_env) {
        env_free(base_env);
        base_env = NULL;
    }
}

Environment *session_get_base_env(void) {
    return base_env;
}

Session *session_create(const char *name) {
    if (!base_env) {
        bloom_log(LOG_ERROR, "session", "Session manager not initialized");
        return NULL;
    }

    if (session_count_val >= MAX_SESSIONS) {
        bloom_log(LOG_ERROR, "session", "Maximum session count reached (%d)",
                  MAX_SESSIONS);
        return NULL;
    }

    Session *s = GC_malloc(sizeof(Session));
    if (!s) {
        return NULL;
    }

    s->id = next_session_id++;
    s->name = GC_strdup(name ? name : "unnamed");
    s->env = env_create(base_env);
    s->telnet = NULL;
    s->connected = 0;
    s->hooks = NULL;

    if (!s->env) {
        return NULL;
    }

    sessions[session_count_val++] = s;

    bloom_log(LOG_INFO, "session", "Created session %d: \"%s\"", s->id,
              s->name);

    return s;
}

int session_destroy(int id) {
    if (current_session && current_session->id == id) {
        bloom_log(LOG_ERROR, "session", "Cannot destroy current session %d",
                  id);
        return -1;
    }

    for (int i = 0; i < session_count_val; i++) {
        if (sessions[i] && sessions[i]->id == id) {
            Session *s = sessions[i];

            if (s->telnet && s->connected) {
                telnet_disconnect(s->telnet);
            }
            session_clear_hooks(s);

            bloom_log(LOG_INFO, "session", "Destroyed session %d: \"%s\"",
                      s->id, s->name);

            /* Compact the array — GC handles memory deallocation */
            for (int j = i; j < session_count_val - 1; j++) {
                sessions[j] = sessions[j + 1];
            }
            sessions[--session_count_val] = NULL;

            return 0;
        }
    }

    return -1; /* Not found */
}

Session *session_get_current(void) {
    return current_session;
}

void session_set_current(Session *session) {
    current_session = session;
}

Session *session_find_by_id(int id) {
    for (int i = 0; i < session_count_val; i++) {
        if (sessions[i] && sessions[i]->id == id) {
            return sessions[i];
        }
    }
    return NULL;
}

Session *session_find_by_name(const char *name) {
    if (!name) {
        return NULL;
    }
    for (int i = 0; i < session_count_val; i++) {
        if (sessions[i] && strcmp(sessions[i]->name, name) == 0) {
            return sessions[i];
        }
    }
    return NULL;
}

int session_count(void) {
    return session_count_val;
}

Session **session_get_all(int *out_count) {
    if (out_count) {
        *out_count = session_count_val;
    }
    return sessions;
}

HookList *session_get_hook_list(Session *session, const char *name) {
    if (!session || !name) {
        return NULL;
    }

    /* Search for existing hook list */
    for (HookList *hl = session->hooks; hl; hl = hl->next) {
        if (strcmp(hl->name, name) == 0) {
            return hl;
        }
    }

    /* Create new hook list */
    HookList *hl = GC_malloc(sizeof(HookList));
    if (!hl) {
        return NULL;
    }
    hl->name = GC_strdup(name);
    hl->entries = NULL;
    hl->next = session->hooks;
    session->hooks = hl;
    return hl;
}

int session_add_hook(Session *session, const char *name, LispObject *fn,
                     int priority) {
    HookList *hl = session_get_hook_list(session, name);
    if (!hl) {
        return -1;
    }

    /* Check for duplicate by pointer identity */
    for (HookEntry *he = hl->entries; he; he = he->next) {
        if (he->fn == fn) {
            return 0; /* Already registered */
        }
    }

    /* Create new entry */
    HookEntry *entry = GC_malloc(sizeof(HookEntry));
    if (!entry) {
        return -1;
    }
    entry->fn = fn;
    entry->priority = priority;

    /* Insert sorted by priority (lower first) */
    HookEntry **pp = &hl->entries;
    while (*pp && (*pp)->priority <= priority) {
        pp = &(*pp)->next;
    }
    entry->next = *pp;
    *pp = entry;
    return 0;
}

int session_remove_hook(Session *session, const char *name, LispObject *fn) {
    if (!session || !name) {
        return -1;
    }

    /* Find the hook list */
    for (HookList *hl = session->hooks; hl; hl = hl->next) {
        if (strcmp(hl->name, name) == 0) {
            HookEntry **pp = &hl->entries;
            while (*pp) {
                if ((*pp)->fn == fn) {
                    /* Just unlink — GC handles deallocation */
                    *pp = (*pp)->next;
                    return 0;
                }
                pp = &(*pp)->next;
            }
            return -1; /* fn not found */
        }
    }
    return -1; /* hook list not found */
}
